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
			if c.distance_to(o.center) < r + reach + 22.0:
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
			if d < 340.0:
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
		if chosen.has(e) or e[0] > 200.0 or degree[a] >= 2 or degree[b] >= 2:
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
	for isl in mains:
		if desired.has(isl.id):
			var dir: Vector2 = desired[isl.id]
			if dir.length() < 0.1:
				dir = -isl.center if isl.center.length() > 1.0 else Vector2.RIGHT
			isl.has_terminal = _find_dock(isl, dir)

	for e in chosen:
		var a: MapData.Island = mains[e[1]]
		var b: MapData.Island = mains[e[2]]
		if not (a.has_terminal and b.has_terminal):
			continue
		var test := _route_curve(a.shore + a.dock_dir * Layout.DOCK_U, a.dock_dir, b.shore + b.dock_dir * Layout.DOCK_U, b.dock_dir)
		if not _route_clear(test):
			continue
		var r := MapData.Route.new()
		r.id = map.routes.size()
		r.a = a.id
		r.b = b.id
		map.routes.append(r)
		a.slips.append(r.id)
		b.slips.append(r.id)

	for isl in mains:
		if isl.slips.is_empty():
			isl.has_terminal = false
			continue
		var lat := isl.lateral()
		isl.slips.sort_custom(func(ra, rb): return _other_end_lateral(isl, ra, lat) < _other_end_lateral(isl, rb, lat))
		isl.lot_half_width = maxf(12.0, (isl.slips.size() - 1) * Layout.SLIP_SPACING * 0.5 + 5.0)

	for r in map.routes:
		var a := map.islands[r.a]
		var b := map.islands[r.b]
		r.curve = _route_curve(a.dock_center(r.id), a.dock_dir, b.dock_center(r.id), b.dock_dir)
		r.length = r.curve.get_baked_length()
		_route_samples.append_array(r.curve.get_baked_points())


func _other_end_lateral(isl: MapData.Island, route_id: int, lat: Vector3) -> float:
	var r := map.routes[route_id]
	var other := map.islands[r.b if r.a == isl.id else r.a]
	return (Vector3(other.center.x, 0.0, other.center.y) - isl.shore).dot(lat)


## Searches around the desired heading for a shoreline with land behind (for the
## holding lot) and open water ahead (for the slip and approach).
func _find_dock(isl: MapData.Island, desired: Vector2) -> bool:
	var base := atan2(desired.y, desired.x)
	for k in 17:
		var ang := base + ceili(k / 2.0) * 0.2 * (1.0 if k % 2 == 1 else -1.0)
		var dir := Vector2(cos(ang), sin(ang))
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
		var n3 := Vector3(dir.x, 0.0, dir.y)
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


func _route_curve(pa: Vector3, na: Vector3, pb: Vector3, nb: Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var h := clampf(pa.distance_to(pb) * 0.38, 18.0, 70.0)
	c.add_point(pa, Vector3.ZERO, na * h)
	c.add_point(pb, nb * h, Vector3.ZERO)
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


## Small rocky islets for scenery, kept away from shipping lanes and docks.
func _place_islets() -> void:
	var target := rng.randi_range(8, 14)
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
