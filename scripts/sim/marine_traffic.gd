class_name MarineTraffic
extends Node
## Everything on the water besides the ferries' own schedule: the sailboats moving
## between marinas, cargo ships passing through, and the right-of-way rules that
## keep every hull (ferries included) from touching another.
##
## Each frame, before anything moves, every vessel under way gets `clear`: how far
## its centre may go along its path before it would come within reach of
##   - another vessel's hull, whatever its rank, or
##   - the path just ahead of a higher-ranked vessel that is under way (unless
##     it is already inside that path, when it must keep going to get out of it).
## Ferries outrank cargo ships, which outrank sailboats, but nothing gives way to
## a vessel that is itself waiting on it. Sailboats out on open water steer their
## own way (Helm) and keep clear of the others themselves; for them this is only
## the check against touching another hull.
##
## Ferries can't leave their routes, and in places two routes run too close for
## two hulls to pass (out of neighbouring slips, say). Each such stretch is a
## Corridor that one ferry at a time reserves before going in.

const SAIL_NAMES := ["Windsong", "Blue Heron", "Sea Otter", "Kittiwake", "Halcyon", "Second Wind",
	"Puffin", "Moonraker", "Tern", "Salt Spray", "Whimbrel", "Northern Light", "Selkie", "Dovekie",
	"Sandpiper", "Wayfarer", "Petrel", "Fair Isle", "Larkspur", "Merganser", "Loon", "Skerry",
	"Cormorant II", "Seabright", "Gannet", "Islay", "Brant", "Westerly"]
const CARGO_NAMES := ["Pacific Trader", "Nordic Star", "Cascade Carrier", "Salish Voyager",
	"Coastal Venture", "Georgia Strait", "Harbour Pride", "Ocean Ranger", "Juan de Fuca", "Arctic Tern"]
const YACHT_NAMES := ["Serenity", "Knot Working", "Reel Time", "Sea Esta", "Island Time", "Aquavit",
	"Blue Moon", "Liquid Asset", "Wanderlust", "Sundowner", "Pacific Rose", "Osprey", "Second Star", "Driftaway",
	"Tide Runner", "Madrona Lady", "Free Spirit", "Orca Bay"]
const FISH_NAMES := ["Northern Dawn", "Ocean Harvest", "Kristi Ann", "Sea Wolf", "Arctic Fox", "Pacific Pride",
	"Mary Ellen", "Silver Bay", "Westward", "Sea Rover", "Kodiak Queen", "Morning Star", "Lady Grace", "Provider"]
const MAX_CARGO := 2
const CARGO_GAP := Vector2(35.0, 90.0)   # game minutes between cargo ships
const RANK_SAIL := 1000
const RANK_POWER := 1200
const RANK_FISH := 1500
const RANK_CARGO := 2000
const RANK_FERRY := 3000
# Kept between hulls (their capsules already stand a little proud of the hulls).
const MARGIN := 0.4
# Two ferry hulls (as capsule segments) this close are in each other's way: two
# hull radii, MARGIN, the extra kept clear of a higher rank's path, and a metre over.
const CORRIDOR_GAP := 10.5
const POSE_STEP := 2.0

var sim: Simulation
var nav: NavGrid
var rng := RandomNumberGenerator.new()
var vessels: Array[Vessel] = []
var sailboats: Array[Sailboat] = []
var motor_yachts: Array[MotorYacht] = []
var cargo_ships: Array[CargoShip] = []
var fishing_boats: Array[FishingBoat] = []
var grounds: Array[FishingGround] = []
var anchorages: Array[Anchorage] = []
var pilotage: Pilotage
var berths := {}            # marina id -> Array of the MarinaBoat holding each berth (or null)
var corridors := {}         # route id -> Array of the Corridors along it
var _lock := {}             # harbour -> the vessel manoeuvring there
var _queue := {}            # harbour -> the vessels waiting to go in, in the order they got there
var _wait_spots := {}       # harbour -> where boats wait to go in (see wait_spot)
var _cargo_timer := 0.0
var _next := 0
var _cargo_named := 0


func setup(s: Simulation) -> void:
	sim = s
	name = "MarineTraffic"
	# Before the vessels move this frame.
	process_priority = -10
	rng.seed = s.map.map_seed * 7 + 11
	var t0 := Time.get_ticks_msec()
	nav = NavGrid.new(s.map, s.terrain)
	_find_corridors()
	for f in s.ferries:
		f.claim_corridors_at_start()
	for f in s.ferries:
		_register(f, RANK_FERRY)
	for m in s.map.marinas:
		var row := []
		row.resize(Layout.MARINA_BERTHS)
		berths[m.id] = row
	grounds = FishingGround.find_all(self)
	var t1 := Time.get_ticks_msec()
	anchorages = Anchorage.find_all(self)
	var spots := 0
	for a in anchorages:
		spots += a.spots.size()
	print("Anchorages: %d coves, %d spots (%d ms)" % [anchorages.size(), spots, Time.get_ticks_msec() - t1])
	_spawn_sailboats()
	_spawn_fishing_boats()
	pilotage = Pilotage.new(self)
	_spawn_cargo(true)
	_cargo_timer = rng.randf_range(CARGO_GAP.x, CARGO_GAP.y) * 0.5
	print("Marine traffic: %d marinas, %d sailboats, %d motor yachts, %d fish quays, %d fishing grounds, %d fishing boats, %d pilot boats, %d tugs, %d cargo ships (%d ms)" % [
		s.map.marinas.size(), sailboats.size(), motor_yachts.size(), s.map.quays.size(), grounds.size(), fishing_boats.size(),
		pilotage.pilot_boats.size(), pilotage.tugs.size(), cargo_ships.size(), Time.get_ticks_msec() - t0])


func register(v: Vessel, base_rank: int) -> void:
	_register(v, base_rank)


func _register(v: Vessel, base_rank: int) -> void:
	v.rank = base_rank + _next
	_next += 1
	vessels.append(v)


func remove(v: Vessel) -> void:
	vessels.erase(v)
	if v is CargoShip:
		cargo_ships.erase(v)
	elif v is Sailboat:
		sailboats.erase(v)
	elif v is MotorYacht:
		motor_yachts.erase(v)
	elif v is FishingBoat:
		fishing_boats.erase(v)
	if pilotage:
		pilotage.remove(v)


# --- Ferry corridors ---------------------------------------------------------------

## Where two ferry routes run too close for both to be sailed at once:
## `span[route id]` is the stretch of each (curve offsets from the route's A end)
## where a hull would be in the other route's way, `owner` the ferry that has the
## corridor reserved. One per pair of routes, however many places they meet.
## `docked[route id]` says whether a ferry docked at that route's A end (x) or
## B end (y) is itself in the other route's way (the other route runs past the
## slip that close).
class Corridor:
	var span := {}
	var docked := {}
	var owner: Ferry = null


func _find_corridors() -> void:
	var routes := sim.map.routes
	for r in routes:
		corridors[r.id] = []
	for i in routes.size():
		for j in range(i + 1, routes.size()):
			var r1 := routes[i]
			var r2 := routes[j]
			var w1 := _in_the_way(r1, r2)
			var w2 := _in_the_way(r2, r1)
			var span1: Vector2 = w1[0]
			var span2: Vector2 = w2[0]
			if span1.x > span1.y or span2.x > span2.y:
				continue
			var c := Corridor.new()
			c.span[r1.id] = span1
			c.span[r2.id] = span2
			c.docked[r1.id] = w1[1]
			c.docked[r2.id] = w2[1]
			corridors[r1.id].append(c)
			corridors[r2.id].append(c)


## [the stretch of `r` (first to last offset, padded a little) over which a ferry's
## hull comes within CORRIDOR_GAP of a ferry's hull anywhere along `other` (empty,
## x > y, if none), whether a ferry docked at r's A / B end is (x / y)].
func _in_the_way(r: MapData.Route, other: MapData.Route) -> Array:
	var mine := _route_poses(r)
	var theirs := _route_poses(other)
	# Their poses bucketed by where they are; two hulls that close are within a
	# bucket of each other.
	var cell := (Ferry.HULL_HALF_LENGTH - 4.3) * 2.0 + CORRIDOR_GAP
	var buckets := {}
	for j in theirs[0].size():
		var m: Vector2 = (theirs[0][j] + theirs[1][j]) * 0.5
		var key := Vector2i(floori(m.x / cell), floori(m.y / cell))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(j)
	var lo := INF
	var hi := -INF
	var ends := Vector2i.ZERO
	var last: int = mine[0].size() - 1
	for k in mine[0].size():
		var a: Vector2 = mine[0][k]
		var b: Vector2 = mine[1][k]
		var mid := (a + b) * 0.5
		var near := []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				near.append_array(buckets.get(Vector2i(floori(mid.x / cell) + dx, floori(mid.y / cell) + dy), []))
		for j in near:
			if _seg_dist(a, b, theirs[0][j], theirs[1][j]) < CORRIDOR_GAP:
				lo = minf(lo, k * POSE_STEP)
				hi = maxf(hi, k * POSE_STEP)
				if k == 0:
					ends.x = 1
				if k == last:
					ends.y = 1
				break
	if lo > hi:
		return [Vector2(1, 0), ends]
	return [Vector2(maxf(lo - 4.0, 0.0), minf(hi + 4.0, r.length)), ends]


## A ferry's hull every POSE_STEP along a route, as [ends a, ends b].
func _route_poses(r: MapData.Route) -> Array:
	var ea := PackedVector2Array()
	var eb := PackedVector2Array()
	var half := Ferry.HULL_HALF_LENGTH - 4.3
	var s := 0.0
	while s <= r.length:
		var p := r.curve.sample_baked(s)
		var t := r.curve.sample_baked(minf(s + 1.5, r.length)) - r.curve.sample_baked(maxf(s - 1.5, 0.0))
		var t2 := Vector2(t.x, t.z).normalized() * half
		ea.append(Vector2(p.x, p.z) - t2)
		eb.append(Vector2(p.x, p.z) + t2)
		s += POSE_STEP
	return [ea, eb]


# --- Sailboats ----------------------------------------------------------------------

func _spawn_sailboats() -> void:
	var names := SAIL_NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: String = names[i]
		names[i] = names[j]
		names[j] = t
	var k := 0
	var sail_types := VesselTypes.sailboats()
	var yacht_types := VesselTypes.motor_yachts()
	var yacht_names := YACHT_NAMES.duplicate()
	for i in range(yacht_names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: String = yacht_names[i]
		yacht_names[i] = yacht_names[j]
		yacht_names[j] = t
	for m in sim.map.marinas:
		for b in Layout.MARINA_BERTHS:
			if rng.randf() > 0.6:
				continue
			# About a third of the boats kept at the marinas are motor yachts.
			if rng.randf() < 0.35:
				var y := MotorYacht.new()
				sim.add_child(y)
				var ysp := VesselTypes.pick(yacht_types, rng)
				y.setup(self, yacht_names[motor_yachts.size() % yacht_names.size()], ysp, m, b,
						rng.randi_range(0, ysp.variants - 1), rng.randf_range(2.0, 120.0))
				berths[m.id][b] = y
				motor_yachts.append(y)
				_register(y, RANK_POWER)
				continue
			var boat := Sailboat.new()
			sim.add_child(boat)
			boat.setup(self, names[k % names.size()], VesselTypes.pick(sail_types, rng), m, b, rng.randf_range(2.0, 90.0))
			berths[m.id][b] = boat
			sailboats.append(boat)
			_register(boat, RANK_SAIL)
			k += 1
	# A few already out sailing, so the water isn't empty at first light.
	for boat in sailboats:
		if rng.randf() < 0.3:
			boat.depart(rng.randf_range(0.2, 0.7))
	# A few lay at anchor in a cove overnight.
	for y in motor_yachts:
		if rng.randf() < 0.3:
			y.start_at_anchor()


## Picks a free berth for `boat` to sail to (another marina if there is one,
## otherwise back home) and reserves it. Returns [marina, berth] or [].
func reserve_berth(boat: MarinaBoat) -> Array:
	var options: Array = []
	for m in sim.map.marinas:
		if m == boat.marina and sim.map.marinas.size() > 1 and rng.randf() < 0.85:
			continue
		var row: Array = berths[m.id]
		for b in row.size():
			if row[b] == null or row[b] == boat:
				options.append([m, b])
	if options.is_empty():
		return []
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	berths[pick[0].id][pick[1]] = boat
	return pick


func release_berth(m: MapData.Marina, b: int, boat: MarinaBoat) -> void:
	if berths[m.id][b] == boat:
		berths[m.id][b] = null


## One boat at a time backs out of, or noses into, a harbour's berths: they turn
## across each other's lanes there. Boats waiting their turn to come in (see
## queue_for) go in the order they got there, before any boat leaving.
func try_lock(h: MapData.Harbour, who: Vessel) -> bool:
	var holder: Vessel = _lock.get(h)
	if holder != null and holder != who and is_instance_valid(holder):
		return false
	var q: Array = _queue.get(h, [])
	while not q.is_empty() and not is_instance_valid(q[0]):
		q.pop_front()
	if not q.is_empty() and q[0] != who:
		return false
	q.erase(who)
	_lock[h] = who
	return true


## Joins the line of boats waiting to go in to `h`.
func queue_for(h: MapData.Harbour, who: Vessel) -> void:
	if not _queue.has(h):
		_queue[h] = []
	if not _queue[h].has(who):
		_queue[h].append(who)


## Leaves the line for `h` (it has somewhere else to be).
func leave_queue(h: MapData.Harbour, who: Vessel) -> void:
	if _queue.has(h):
		_queue[h].erase(who)


func lock_holder(h: MapData.Harbour) -> Vessel:
	var who: Vessel = _lock.get(h) if h else null
	return who if is_instance_valid(who) else null


func unlock(h: MapData.Harbour, who: Vessel) -> void:
	if h != null and _lock.get(h) == who:
		_lock.erase(h)


# --- Fishing boats ------------------------------------------------------------------

## A boat or two at each fish quay. Those that would have gone out before the map
## opens are already out on their grounds.
func _spawn_fishing_boats() -> void:
	if grounds.is_empty():
		return
	var types := VesselTypes.fishing_boats()
	var k := sim.map.map_seed
	for q in sim.map.quays:
		var n := 2 if rng.randf() < 0.6 else 1
		for b in n:
			var boat := FishingBoat.new()
			sim.add_child(boat)
			var sp := VesselTypes.pick(types, rng)
			boat.setup(self, FISH_NAMES[k % FISH_NAMES.size()], sp, q, b, rng.randi_range(0, sp.variants - 1))
			k += 1
			fishing_boats.append(boat)
			_register(boat, RANK_FISH)
	for boat in fishing_boats:
		if rng.randf() < 0.75:
			boat.start_at_sea()


## A ground for `boat` to work today, free of other boats, and reserved for it:
## the better grounds more often, the nearer ones more often. Null if none is free.
func reserve_ground(boat: FishingBoat) -> FishingGround:
	var home := boat.pos2()
	var total := 0.0
	var free: Array[FishingGround] = []
	var weights: Array[float] = []
	for g in grounds:
		if g.worked_by != null and g.worked_by != boat and is_instance_valid(g.worked_by):
			continue
		var w := g.richness / (1.0 + g.center.distance_to(home) / 300.0)
		free.append(g)
		weights.append(w)
		total += w
	if free.is_empty():
		return null
	var r := rng.randf() * total
	for i in free.size():
		r -= weights[i]
		if r <= 0.0 or i == free.size() - 1:
			free[i].worked_by = boat
			return free[i]
	return null


func release_ground(g: FishingGround, boat: FishingBoat) -> void:
	if g != null and g.worked_by == boat:
		g.worked_by = null


# --- Anchorages ---------------------------------------------------------------------

## A free spot in a cove for `boat`, reserved for it: the more sheltered coves
## more often, the nearer ones (to `from`) more often. Null if none is free.
func reserve_spot(boat: Vessel, from: Vector2) -> Anchorage.Spot:
	var free: Array[Anchorage.Spot] = []
	var weights: Array[float] = []
	var total := 0.0
	for a in anchorages:
		for sp in a.spots:
			if sp.taken_by != null and is_instance_valid(sp.taken_by) and sp.taken_by != boat:
				continue
			var w := a.shelter * a.shelter / (1.0 + sp.pos.distance_to(from) / 350.0)
			free.append(sp)
			weights.append(w)
			total += w
	if free.is_empty():
		return null
	var r := rng.randf() * total
	for i in free.size():
		r -= weights[i]
		if r <= 0.0 or i == free.size() - 1:
			free[i].taken_by = boat
			return free[i]
	return null


func release_spot(sp: Anchorage.Spot, boat: Vessel) -> void:
	if sp != null and sp.taken_by == boat:
		sp.taken_by = null


# --- Cargo ships --------------------------------------------------------------------

func _spawn_cargo(midway := false) -> void:
	var hs := sim.map.half_size
	for attempt in 8:
		var side_a := rng.randi_range(0, 3)
		var side_b := (side_a + rng.randi_range(1, 3)) % 4
		var a := _edge_point(side_a, hs + 80.0)
		var b := _edge_point(side_b, hs + 80.0)
		var pts := nav.find_path(a, b, true)
		if pts.size() < 2:
			continue
		# Run in from (and out to) well beyond the map, into the haze.
		pts.insert(0, a + _edge_normal(side_a) * 160.0)
		pts.append(b + _edge_normal(side_b) * 160.0)
		# Kept right all the way out, so ships coming and going there pass too.
		var sp := VesselTypes.pick(VesselTypes.cargo_ships(), rng)
		pts = nav.finish(pts, 10.0, 14.0, 3, sp.half_beam + 2.0, 0.0)
		var path := NavPath.new(pts)
		var s0 := path.length * rng.randf_range(0.3, 0.55) if midway else 0.0
		if not is_clear(path.sample(s0), 90.0) or _meets_head_on(path):
			continue
		var ship := CargoShip.new()
		sim.add_child(ship)
		ship.setup(self, CARGO_NAMES[(sim.map.map_seed + _cargo_named) % CARGO_NAMES.size()], sp, path, s0,
				rng.randi_range(0, sp.variants - 1))
		_cargo_named += 1
		cargo_ships.append(ship)
		_register(ship, RANK_CARGO)
		return


## True if `path` starts where another ship's ends (they'd meet bow to bow out
## beyond the edge, with nowhere to plan round each other).
func _meets_head_on(path: NavPath) -> bool:
	for ship in cargo_ships:
		var end := ship.path.pts[ship.path.pts.size() - 1]
		if end.distance_to(path.pts[0]) < 220.0:
			return true
	return false


func _edge_point(side: int, e: float) -> Vector2:
	var t := rng.randf_range(-0.7, 0.7) * sim.map.half_size
	match side:
		0:
			return Vector2(-e, t)
		1:
			return Vector2(e, t)
		2:
			return Vector2(t, -e)
	return Vector2(t, e)


func _edge_normal(side: int) -> Vector2:
	return [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN][side]


## The smallest gap between `v`'s hull, were its centre at `p` heading along `h`
## (unit), and any other hull.
func hull_gap(v: Vessel, p: Vector2, h: Vector2) -> float:
	var a := p - h * v.half_seg
	var b := p + h * v.half_seg
	var best := INF
	for o in vessels:
		if o == v or Vessel.paired(v, o):
			continue
		var q := o.pos2()
		var r := v.half_seg + o.half_seg + v.hull_radius + o.hull_radius + 2.0
		if absf(q.x - p.x) > r or absf(q.y - p.y) > r:
			continue
		var oh := o.heading2() * o.half_seg
		best = minf(best, _seg_dist(a, b, q - oh, q + oh) - v.hull_radius - o.hull_radius)
	return best


## Where a boat bound for harbour `h` waits its turn to go in: near by, out of
## the harbour's own approaches (Harbour.wait_bounds), and if possible in water
## too close in for cargo ships, so it isn't in their way. One spot per harbour,
## spread a little for each berth.
func wait_spot(h: MapData.Harbour, b: int) -> Vector2:
	if not _wait_spots.has(h):
		var best := Vector2.INF
		var best_score := INF
		var bounds := h.wait_bounds()
		var ap := h.approach()
		var approach := h.at(ap.x, ap.y)
		var a2 := Vector2(approach.x, approach.z)
		for u in range(int(bounds.x), int(bounds.x) + 60, 6):
			for v in range(-70, 71, 6):
				if absf(v) < bounds.y or not h.wait_ok(u, v):
					continue
				var p3 := h.at(u, v)
				var p := Vector2(p3.x, p3.z)
				if not nav.open_at(p, false) or nav.find_path(a2, p, false).is_empty():
					continue
				var score := p.distance_to(a2) + (80.0 if nav.open_at(p, true) else 0.0)
				if score < best_score:
					best_score = score
					best = p
		if best == Vector2.INF:
			var p3 := h.at(ap.x + 20.0, ap.y)
			best = Vector2(p3.x, p3.z)
		_wait_spots[h] = best
	var spot: Vector2 = _wait_spots[h]
	var lat := Vector2(h.lateral().x, h.lateral().z)
	return spot + lat * (b - (h.berths() - 1) * 0.5) * h.wait_spacing()


## True if `p` is within `r` of a harbour: a marina's T-head, a wharf's face, or a
## ferry terminal's slips.
func near_harbour(p: Vector2, r: float) -> bool:
	var map := sim.map
	for m in map.marinas:
		var a := m.at(Layout.MARINA_HEAD_U, 0.0)
		if Vector2(a.x, a.z).distance_squared_to(p) < r * r:
			return true
	for q in map.wharves():
		var a := q.at(Layout.QUAY_FACE_U, 0.0)
		if Vector2(a.x, a.z).distance_squared_to(p) < r * r:
			return true
	for isl in map.islands:
		if isl.has_terminal:
			var a := isl.shore + isl.dock_dir * Layout.DOCK_U
			if Vector2(a.x, a.z).distance_squared_to(p) < r * r:
				return true
	return false


## True if no hull (but `except`'s) is within `radius` of p.
func is_clear(p: Vector2, radius: float, except: Vessel = null) -> bool:
	for v in vessels:
		if v != except and v.pos2().distance_to(p) < radius + v.half_seg + v.hull_radius:
			return false
	return true


## Circles (x, z, radius) covering `o`'s hull and the path it is showing, for a
## boat planning its way round it.
func avoid_circles(o: Vessel, pad: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var p := o.pos2()
	out.append(Vector3(p.x, p.y, o.half_seg + o.hull_radius + pad))
	var look := minf(o.shown_look(), o.path_left()) if o.wants_to_move() else 0.0
	var d := o.half_seg
	while d < look:
		var q := o.ahead(d)
		out.append(Vector3(q.x, q.y, o.hull_radius + pad))
		d += maxf(o.hull_radius, 3.0)
	return out


# --- Right of way -------------------------------------------------------------------

func _process(delta: float) -> void:
	# Paused: nothing moves.
	if delta <= 0.0:
		return
	_cargo_timer -= delta
	if _cargo_timer <= 0.0:
		_cargo_timer = rng.randf_range(CARGO_GAP.x, CARGO_GAP.y)
		if cargo_ships.size() < MAX_CARGO:
			_spawn_cargo()
	pilotage.update(delta)
	_update_clearances()


## The hull at a run of poses along a vessel's path: its current pose, then every
## `claim_step` ahead up to `look`, each as a capsule segment (a[k] → b[k]) with
## the distance its centre has to go to get there.
class Claim:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var ds := PackedFloat32Array()
	var box := Rect2()

	func _init(v: Vessel, look: float) -> void:
		var pts := PackedVector2Array()
		var d := 0.0
		while true:
			pts.append(v.ahead(d))
			ds.append(d)
			if d >= look:
				break
			d = minf(d + v.claim_step, look)
		var h0 := v.heading2()
		for k in pts.size():
			var h := h0
			if k > 0 and not v.crabbing():
				var t := pts[mini(k + 1, pts.size() - 1)] - pts[k - 1]
				if t.length_squared() > 1e-6:
					# Either way along the hull: keep the pose's ends where they were.
					h = t.normalized() * signf(t.normalized().dot(h0) + 1e-3)
			a.append(pts[k] - h * v.half_seg)
			b.append(pts[k] + h * v.half_seg)
		box = Rect2(a[0], Vector2.ZERO)
		for k in a.size():
			box = box.expand(a[k]).expand(b[k])

	func size() -> int:
		return a.size()


func _update_clearances() -> void:
	var hulls := {}
	var own := {}
	var shown := {}
	for v in vessels:
		if v.wants_to_move():
			var left := v.path_left()
			var mine := Claim.new(v, minf(v.self_look(), left))
			own[v] = mine
			hulls[v] = mine
			var sl := minf(v.shown_look(), left)
			if sl > 0.5:
				shown[v] = Claim.new(v, sl)
		else:
			hulls[v] = Claim.new(v, 0.0)
	for v in vessels:
		v.clear = INF
		v.blocker = null
		v.blocked_by_hull = false
		if not own.has(v):
			continue
		var mine: Claim = own[v]
		for o in vessels:
			if o == v or Vessel.paired(v, o):
				continue
			var thr := v.hull_radius + o.hull_radius + MARGIN
			var reach := mine.box.grow(thr)
			var hull: Claim = hulls[o]
			if reach.intersects(hull.box):
				var k := _first_hit(mine, hull.a[0], hull.b[0], thr)
				if k > 0:
					_limit(v, o, mine.ds[k - 1], true)
			# Never wait on one that is waiting on you: get out of its way instead.
			# (A vessel steering its own way keeps out of others' paths itself.)
			if o.rank > v.rank and not v.free_nav and shown.has(o) and not o.waits_for(v):
				var theirs: Claim = shown[o]
				if not reach.grow(0.5).intersects(theirs.box) or _touches(mine.a[0], mine.b[0], theirs, thr):
					continue
				for j in theirs.size():
					var k2 := _first_hit(mine, theirs.a[j], theirs.b[j], thr + 0.5, false)
					if k2 > 0:
						_limit(v, o, mine.ds[k2 - 1], false)


func _limit(v: Vessel, o: Vessel, c: float, by_hull: bool) -> void:
	if c < v.clear:
		v.clear = c
		v.blocker = o
		v.blocked_by_hull = by_hull


## First pose (from 1) in `mine` within `thr` of the segment c → d, or -1. With
## `closing`, a pose only counts if it is also nearer than the current one, so a
## vessel already too close to something can always move away from it.
static func _first_hit(mine: Claim, c: Vector2, d: Vector2, thr: float, closing := true) -> int:
	var sbox := Rect2(c, Vector2.ZERO).expand(d).grow(thr)
	var now := _seg_dist(mine.a[0], mine.b[0], c, d) if closing else INF
	for k in range(1, mine.size()):
		if not sbox.intersects(Rect2(mine.a[k], Vector2.ZERO).expand(mine.b[k])):
			continue
		var dk := _seg_dist(mine.a[k], mine.b[k], c, d)
		if dk < thr and dk < now - 0.01:
			return k
	return -1


## True if the segment a → b comes within `thr` of any pose in `other`.
static func _touches(a: Vector2, b: Vector2, other: Claim, thr: float) -> bool:
	for j in other.size():
		if _seg_dist(a, b, other.a[j], other.b[j]) < thr:
			return true
	return false


static func _seg_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_pt_seg(a, c, d), _pt_seg(b, c, d)), minf(_pt_seg(c, a, b), _pt_seg(d, a, b)))


static func _pt_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
