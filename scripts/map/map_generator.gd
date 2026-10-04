class_name MapGenerator
extends RefCounted
## Procedurally lays out an archipelago: a mainland rim, inhabited islands, ferry
## terminals and routes between them, small islets, and town roads.

const NAMES := ["Pinehurst", "Northpoint", "Driftwood", "Harborview", "Seaglass Isle", "Lumber Bay",
	"Cedar Island", "Westcove", "Southgate", "Sunset Point", "Orca Point", "Madrona", "Kelp Harbor",
	"Heron Key", "Fox Island", "Bramble Bay", "Stillwater", "Gull Rock", "Alder Cove", "Tern Island"]

var rng := RandomNumberGenerator.new()
var terrain: Terrain
var map: MapData
var _route_samples := PackedVector3Array()
var _slip_zones: Array = []   # [shore, dock_dir, lateral, slip offset, route id]

const DOCK_MIN_ANGLE := deg_to_rad(35.0)   # no two docks face within this of each other


func generate(map_seed: int) -> MapData:
	rng.seed = map_seed
	map = MapData.new()
	map.map_seed = map_seed
	terrain = Terrain.new(map_seed, map.half_size)
	_place_mainland()
	_place_islands()
	for isl in map.islands:
		terrain.stamp_island(isl.center, isl.radius, isl.strength)
	terrain.finalize()
	_plan_routes()
	_place_islets()
	terrain.finalize()
	_flatten_terminals()
	_name_islands()
	_layout_towns()
	return map


func _new_island(center: Vector2, radius: float, strength: float, inhabited: bool) -> MapData.Island:
	var isl := MapData.Island.new()
	isl.id = map.islands.size()
	isl.center = center
	isl.radius = radius
	isl.strength = strength
	isl.inhabited = inhabited
	map.islands.append(isl)
	return isl


func _place_mainland() -> void:
	var count := rng.randi_range(4, 6)
	var start := rng.randf() * TAU
	for k in count:
		var ang := start + TAU * k / count + rng.randf_range(-0.25, 0.25)
		var dist := rng.randf_range(map.half_size + 40.0, map.half_size + 90.0)
		var isl := _new_island(Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(120.0, 160.0), 1.3, false)
		isl.is_mainland = true


func _place_islands() -> void:
	var target := rng.randi_range(8, 11)
	var limit := map.half_size - 110.0
	var placed := 0
	for attempt in 5000:
		if placed >= target:
			break
		var r := rng.randf_range(46.0, 70.0)
		var c := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var ok := true
		for o in map.islands:
			var reach := o.radius * (0.72 if o.is_mainland else 1.0)
			if c.distance_to(o.center) < r + reach + 85.0:
				ok = false
				break
		if ok:
			_new_island(c, r, rng.randf_range(0.9, 1.15), true)
			placed += 1


func _main_islands() -> Array[MapData.Island]:
	var out: Array[MapData.Island] = []
	for isl in map.islands:
		if isl.inhabited and not isl.is_mainland:
			out.append(isl)
	return out


static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


## Picks island pairs (a spanning tree plus a few extra links), finds a dock site on
## each connected island, then keeps only routes a ferry can actually sail.
func _plan_routes() -> void:
	var mains := _main_islands()
	var edges: Array = []
	for i in mains.size():
		for j in range(i + 1, mains.size()):
			var d := mains[i].center.distance_to(mains[j].center)
			if d < 430.0:
				edges.append([d, i, j])
	edges.sort_custom(func(a, b): return a[0] < b[0])

	var parent: Array = range(mains.size())
	var degree := PackedInt32Array()
	degree.resize(mains.size())
	var chosen: Array = []
	for e in edges:
		var a: int = e[1]
		var b: int = e[2]
		if degree[a] >= 3 or degree[b] >= 3:
			continue
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra != rb:
			parent[ra] = rb
			chosen.append(e)
			degree[a] += 1
			degree[b] += 1
	for e in edges:
		var a: int = e[1]
		var b: int = e[2]
		if chosen.has(e) or e[0] > 260.0 or degree[a] >= 2 or degree[b] >= 2:
			continue
		if rng.randf() < 0.6:
			chosen.append(e)
			degree[a] += 1
			degree[b] += 1

	# Dock sites face the average direction of each island's neighbours.
	var desired := {}
	for e in chosen:
		for pair in [[e[1], e[2]], [e[2], e[1]]]:
			var me: MapData.Island = mains[pair[0]]
			var other: MapData.Island = mains[pair[1]]
			var v: Vector2 = desired.get(me.id, Vector2.ZERO)
			desired[me.id] = v + (other.center - me.center).normalized()
	var taken: Array[Vector3] = []
	for isl in mains:
		if desired.has(isl.id):
			var dir: Vector2 = desired[isl.id]
			if dir.length() < 0.1:
				dir = -isl.center if isl.center.length() > 1.0 else Vector2.RIGHT
			isl.has_terminal = _find_dock(isl, dir, taken)
			if isl.has_terminal:
				taken.append(isl.dock_dir)

	for e in chosen:
		var a: MapData.Island = mains[e[1]]
		var b: MapData.Island = mains[e[2]]
		if not (a.has_terminal and b.has_terminal):
			continue
		var test := _route_curve(a.shore + a.dock_dir * Layout.DOCK_U, a.dock_dir, b.shore + b.dock_dir * Layout.DOCK_U, b.dock_dir)
		if test == null:
			continue
		var r := MapData.Route.new()
		r.id = map.routes.size()
		r.a = a.id
		r.b = b.id
		r.curve = test
		map.routes.append(r)
		a.slips.append(r.id)
		b.slips.append(r.id)

	for isl in mains:
		if isl.slips.is_empty():
			isl.has_terminal = false
			continue
		var lat := isl.lateral()
		isl.slips.sort_custom(func(ra, rb): return _departure_lateral(isl, ra, lat) < _departure_lateral(isl, rb, lat))
		isl.lot_half_width = maxf(12.0, (isl.slips.size() - 1) * Layout.SLIP_SPACING * 0.5 + 5.0)
		for rid in isl.slips:
			_slip_zones.append([isl.shore, isl.dock_dir, lat, isl.slip_offset(isl.slip_index(rid)), rid])

	for r in map.routes:
		var a := map.islands[r.a]
		var b := map.islands[r.b]
		var pa := a.dock_center(r.id)
		var pb := b.dock_center(r.id)
		# Keep clear of every other slip; only if that's impossible, settle for
		# clear of land.
		var c := _route_curve(pa, a.dock_dir, pb, b.dock_dir, true, r.id)
		if c == null:
			c = _route_curve(pa, a.dock_dir, pb, b.dock_dir, false)
		r.curve = c
		r.length = r.curve.get_baked_length()
		_route_samples.append_array(r.curve.get_baked_points())


## Which side the route heads off to once clear of the terminal, from its planning
## curve, so neighbouring slips' routes peel away from each other instead of crossing.
func _departure_lateral(isl: MapData.Island, route_id: int, lat: Vector3) -> float:
	var r := map.routes[route_id]
	var length := r.curve.get_baked_length()
	var s := minf(RUN_IN + 60.0, length * 0.5)
	var p := r.curve.sample_baked(s if r.a == isl.id else length - s)
	return (p - isl.shore).dot(lat)


## Searches around the desired heading for a shoreline with land behind (for the
## holding lot) and open water ahead (for the slip and approach), never facing
## within DOCK_MIN_ANGLE of a dock already placed.
func _find_dock(isl: MapData.Island, desired: Vector2, taken: Array[Vector3]) -> bool:
	var base := atan2(desired.y, desired.x)
	for k in 17:
		var ang := base + ceili(k / 2.0) * 0.2 * (1.0 if k % 2 == 1 else -1.0)
		var dir := Vector2(cos(ang), sin(ang))
		var n3 := Vector3(dir.x, 0.0, dir.y)
		var clash := false
		for t in taken:
			if n3.angle_to(t) < DOCK_MIN_ANGLE:
				clash = true
				break
		if clash:
			continue
		var shore := -1.0
		var r := 0.0
		while r < isl.radius * 1.8:
			var p := isl.center + dir * r
			if terrain.height_at(p.x, p.y) < 0.3:
				shore = r
				break
			r += 0.5
		if shore < 8.0:
			continue
		var s3 := Vector3(isl.center.x + dir.x * shore, 0.0, isl.center.y + dir.y * shore)
		var lat := Vector3.UP.cross(n3)
		var land := 0
		for u: float in [-6.0, -12.0, -18.0, -24.0, -30.0]:
			if terrain.height_v(s3 + n3 * u) > 0.5:
				land += 1
		if land < 4:
			continue
		var water_ok := true
		for u in range(6, 52, 3):
			for v: float in [-12.0, 0.0, 12.0]:
				if terrain.height_v(s3 + n3 * float(u) + lat * v) > -1.0:
					water_ok = false
					break
			if not water_ok:
				break
		if not water_ok:
			continue
		isl.shore = s3
		isl.dock_dir = n3
		return true
	return false


# Ferries leave and enter each slip on a straight run along its centreline, long
# enough that the whole hull is lined up before the bow reaches the outer dolphins
# (~21 m out from docked), and turn no tighter than TURN_RADIUS in between. Where
# the coast or other slips leave no room, a shorter run-in and then a tighter turn
# are tried, and a wide sweep only as a last resort.
const RUN_IN := 30.0
const SHORT_RUN_IN := 22.0
const TURN_RADIUS := 32.0
const TIGHT_RADIUS := 22.0
const WIDE_RADIUS := 45.0
# Each slip's pier, guide walls and dolphins are off limits to other routes' hulls.
const ZONE_U := Layout.PIER_END + 25.0
const HULL_HALF_BEAM := 4.5


## Route from dock centre `pa` (facing out along `na`) to dock centre `pb`: straight
## out, the shortest turn–straight–turn path between the run-in ends, straight in.
## Returns the shortest clear one, or null if none is clear and `need_clear` is set
## (otherwise the shortest regardless). With `route_id` set it must also keep out of
## every slip but that route's own.
func _route_curve(pa: Vector3, na: Vector3, pb: Vector3, nb: Vector3, need_clear := true, route_id := -1) -> Curve3D:
	var h0 := Vector2(na.x, na.z).normalized()
	var h1 := -Vector2(nb.x, nb.z).normalized()
	# Every path for every option, scored by length plus a penalty for each
	# compromise, so a short run-in or tight turn wins over looping round.
	var candidates := []
	for option: Vector3 in [Vector3(RUN_IN, TURN_RADIUS, 0.0), Vector3(SHORT_RUN_IN, TURN_RADIUS, 25.0),
			Vector3(RUN_IN, TIGHT_RADIUS, 40.0), Vector3(SHORT_RUN_IN, TIGHT_RADIUS, 70.0),
			Vector3(RUN_IN, WIDE_RADIUS, 120.0)]:
		var p0 := Vector2(pa.x, pa.z) + h0 * option.x
		var p1 := Vector2(pb.x, pb.z) - h1 * option.x
		for path in _turn_paths(p0, h0, p1, h1, option.y):
			candidates.append([path[0] + option.z, path[1], option.x])
	candidates.sort_custom(func(x, y): return x[0] < y[0])
	for cand in candidates:
		var c := _curve_from(pa, cand[1], pb, cand[2])
		if _route_clear(c) and (route_id < 0 or _clear_of_slips(c, route_id)):
			return c
	if need_clear or candidates.is_empty():
		return null
	return _curve_from(pa, candidates[0][1], pb, candidates[0][2])


static func _left(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)


## The four turn–straight–turn paths from pose (p0, h0) to (p1, h1) at the given
## turn radius, as [length, PackedVector2Array of points every ~2 m].
static func _turn_paths(p0: Vector2, h0: Vector2, p1: Vector2, h1: Vector2, radius: float) -> Array:
	var out := []
	for s0: float in [1.0, -1.0]:
		for s1: float in [1.0, -1.0]:
			# A point turning with sign s about centre c has position c - s·R·left(h).
			var c0 := p0 + _left(h0) * s0 * radius
			var c1 := p1 + _left(h1) * s1 * radius
			var d := c1 - c0
			var k := (s1 - s0) * radius
			var dl2 := d.length_squared() - k * k
			if dl2 < 1e-4:
				continue
			var straight := sqrt(dl2)
			var t := d.rotated(-atan2(k, straight)).normalized()
			var a0 := fposmod(s0 * (t.angle() - h0.angle()), TAU)
			var a1 := fposmod(s1 * (h1.angle() - t.angle()), TAU)
			var pts := PackedVector2Array()
			_arc(pts, c0, h0, s0, radius, a0)
			var q0 := c0 - _left(t) * s0 * radius
			var q1 := c1 - _left(t) * s1 * radius
			var steps := maxi(1, ceili(straight / 2.0))
			for i in steps:
				pts.append(q0.lerp(q1, float(i) / steps))
			_arc(pts, c1, t, s1, radius, a1)
			pts.append(p1)
			out.append([radius * (a0 + a1) + straight, pts])
	return out


static func _arc(pts: PackedVector2Array, c: Vector2, h: Vector2, sgn: float, radius: float, angle: float) -> void:
	var steps := ceili(radius * angle / 2.0)
	for i in steps:
		var hh := h.rotated(sgn * angle * i / steps)
		pts.append(c - _left(hh) * sgn * radius)


func _curve_from(pa: Vector3, mid: PackedVector2Array, pb: Vector3, run_in: float) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var a2 := Vector2(pa.x, pa.z)
	var b2 := Vector2(pb.x, pb.z)
	var steps := ceili(run_in / 2.0)
	for i in steps:
		var q := a2.lerp(mid[0], float(i) / steps)
		c.add_point(Vector3(q.x, 0.0, q.y))
	for q in mid:
		c.add_point(Vector3(q.x, 0.0, q.y))
	for i in range(1, steps + 1):
		var q := mid[mid.size() - 1].lerp(b2, float(i) / steps)
		c.add_point(Vector3(q.x, 0.0, q.y))
	return c


func _route_clear(c: Curve3D) -> bool:
	var length := c.get_baked_length()
	var s := 12.0
	while s < length - 12.0:
		var p := c.sample_baked(s)
		var q := c.sample_baked(minf(s + 1.0, length))
		var lat := Vector3.UP.cross((q - p).normalized()) * 6.0
		for o: Vector3 in [Vector3.ZERO, lat, -lat]:
			if terrain.height_v(p + o) > -1.2:
				return false
		s += 3.0
	return true


## True if the hull, swept along `c`, never enters another route's slip.
func _clear_of_slips(c: Curve3D, route_id: int) -> bool:
	var length := c.get_baked_length()
	var s := 0.0
	while s <= length:
		var p := c.sample_baked(s)
		var t := c.sample_baked(minf(s + 1.0, length)) - c.sample_baked(maxf(s - 1.0, 0.0))
		t.y = 0.0
		t = t.normalized()
		var side := Vector3.UP.cross(t)
		for z in _slip_zones:
			if z[4] == route_id:
				continue
			var rel: Vector3 = p - z[0]
			# Cheap reject: nowhere near this terminal.
			var u: float = rel.dot(z[1])
			if u > ZONE_U + 16.0 or u < Layout.LOT_FRONT - 16.0 or absf(rel.dot(z[2]) - z[3]) > Layout.SLIP_SPACING + 16.0:
				continue
			for along: float in [-15.0, -7.5, 0.0, 7.5, 15.0]:
				for across: float in [-HULL_HALF_BEAM, 0.0, HULL_HALF_BEAM]:
					var q := rel + t * along + side * across
					var qu: float = q.dot(z[1])
					if qu < ZONE_U and qu > Layout.LOT_FRONT and absf(q.dot(z[2]) - z[3]) < Layout.SLIP_SPACING * 0.5:
						return false
		s += 2.0
	return true


## Small rocky islets for scenery, kept away from shipping lanes and docks.
func _place_islets() -> void:
	var target := rng.randi_range(12, 20)
	var placed := 0
	var limit := map.half_size - 40.0
	for attempt in 1500:
		if placed >= target:
			break
		var r := rng.randf_range(6.0, 13.0)
		var c := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var ok := true
		for o in map.islands:
			var reach := o.radius * (0.72 if o.is_mainland else 1.0)
			if c.distance_to(o.center) < r + reach + 10.0:
				ok = false
				break
			if o.has_terminal and c.distance_to(Vector2(o.shore.x, o.shore.z)) < r + 50.0:
				ok = false
				break
		if ok:
			for p in _route_samples:
				if Vector2(p.x, p.z).distance_to(c) < r * 1.25 + 14.0:
					ok = false
					break
		if ok:
			var isl := _new_island(c, r, rng.randf_range(0.85, 1.0), false)
			terrain.stamp_island(isl.center, isl.radius, isl.strength)
			placed += 1


func _flatten_terminals() -> void:
	for isl in map.islands:
		if not isl.has_terminal:
			continue
		var hw := isl.lot_half_width
		terrain.add_flat(isl.shore, isl.dock_dir, Layout.LOT_BACK - 2.0, Layout.LOT_FRONT + 1.0,
			-hw - 1.5, hw + 11.0, Layout.LOT_Y - 0.05, 7.0)
	terrain.apply_flats()


func _name_islands() -> void:
	var names := NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: String = names[i]
		names[i] = names[j]
		names[j] = t
	var k := 0
	for isl in _main_islands():
		isl.name = names[k % names.size()]
		k += 1
		isl.population = int(rng.randf_range(900.0, 6500.0) / 10.0) * 10
		isl.growth = rng.randf_range(-0.5, 4.5)


func _h(p: Vector3) -> float:
	return terrain.height_v(p)


## Main road from the lot entrance inland to a town centre, plus a cross street.
func _layout_towns() -> void:
	for isl in _main_islands():
		if isl.has_terminal:
			var nd := isl.dock_dir
			var t := isl.lateral()
			var e := isl.shore + nd * Layout.LOT_BACK
			var dist := 16.0
			while dist > 4.0:
				var p := e - nd * dist
				if _h(p) > 1.3 and _h(p - nd * 8.0) > 1.3:
					break
				dist -= 2.0
			var tc := e - nd * dist
			isl.road_main_a = _road_line(e, tc, t)
			var far := 0.0
			while far < 16.0 and _h(tc - nd * (far + 2.0)) > 1.3:
				far += 2.0
			if far >= 4.0:
				isl.road_main_b = _road_line(tc, tc - nd * far, t)
			for side: float in [-1.0, 1.0]:
				var length := 0.0
				while length < 24.0 and _h(tc + t * side * (length + 2.0)) > 1.3:
					length += 2.0
				if length >= 6.0:
					isl.road_cross.append(_road_line(tc, tc + t * side * length, nd))
			isl.town_center = tc
			isl.town_axis = t
		else:
			# Unconnected island: settle on the highest ground near the centre.
			var best := Vector3(isl.center.x, 0.0, isl.center.y)
			for k in 24:
				var p := Vector3(isl.center.x + rng.randf_range(-15, 15), 0.0, isl.center.y + rng.randf_range(-15, 15))
				if _h(p) > _h(best):
					best = p
			isl.town_center = best
			var a := rng.randf() * TAU
			isl.town_axis = Vector3(cos(a), 0.0, sin(a))
		isl.town_center.y = _h(isl.town_center)
		isl.label_pos = isl.town_center + Vector3(0, 16, 0)


func _road_line(a: Vector3, b: Vector3, lat: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var count := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		p.y = maxf(_h(p), maxf(_h(p + lat * 1.7), _h(p - lat * 1.7))) + 0.22
		pts.append(p)
	return pts
