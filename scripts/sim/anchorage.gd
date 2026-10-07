class_name Anchorage
extends RefCounted
## A cove where yachts drop anchor for a swim and lunch, or for the night: water
## of anchoring depth close in under the land, with land round most of the
## horizon so it is sheltered. Found once per map (find_all), each with a few
## spots far enough apart for boats to swing to the wind without touching; a boat
## reserves a spot before it sets off. Not named or shown to the player; the HUD
## only says where a boat lies ("Anchored in a cove on Fox Island").

const COUNT := 7
const STEP := 8.0              # sampling grid for candidates (m)
const DEPTH := Vector2(-11.0, -2.6)   # seabed range a boat anchors in
const NEAR_LAND := 48.0        # how close in under the land a cove's water lies
const RAYS := 16
const RAY_REACH := 150.0
const SHELTER := 0.56          # share of the horizon closed by land
const SPOT_GAP := 15.0         # between spots (room to swing)
const SPOTS := 4
const SPREAD := 34.0           # spots lie within this of the cove's centre
const KEEP_FROM_COVES := 120.0
const KEEP_FROM_ROUTES := 60.0
const KEEP_FROM_HARBOURS := 90.0
const KEEP_FROM_HAUL_OUTS := 45.0   # seals' beaches and rocks: don't anchor off them
const KEEP_FROM_SHIPS := 18.0  # from water the ships can use (their hulls, and a boat swinging at anchor)

class Spot:
	var pos := Vector2.ZERO
	var taken_by: Vessel = null
	var anchorage: Anchorage

var center := Vector2.ZERO
var shelter := 0.0
var spots: Array[Spot] = []
var place := ""                # "in a cove on Fox Island"


## Finds the map's coves. Deterministic for a map (no RNG).
static func find_all(t: MarineTraffic) -> Array[Anchorage]:
	var map := t.sim.map
	var terrain := t.sim.terrain
	var nav := t.nav
	var hs := map.half_size
	# A coarse land mask to march the rays over.
	var n := ceili(hs * 2.0 / STEP) + 1
	var land := PackedByteArray()
	land.resize(n * n)
	var depth := PackedFloat32Array()
	depth.resize(n * n)
	for j in n:
		for i in n:
			var h := terrain.height_at(-hs + i * STEP, -hs + j * STEP)
			depth[j * n + i] = h
			land[j * n + i] = 1 if h > -0.4 else 0
	var avoid: Array[Vector2] = []
	for isl in map.islands:
		if isl.has_terminal:
			avoid.append(Vector2(isl.shore.x, isl.shore.z) + Vector2(isl.dock_dir.x, isl.dock_dir.z) * 30.0)
	for m in map.marinas:
		var a := m.at(Layout.MARINA_APPROACH_U, 0.0)
		avoid.append(Vector2(a.x, a.z))
	for q in map.wharves():
		for v: float in [-Layout.QUAY_RUN, 0.0, Layout.QUAY_RUN]:
			var a := q.at(Layout.QUAY_LANE_U, v)
			avoid.append(Vector2(a.x, a.z))
	for g in t.grounds:
		avoid.append(g.center)
	var seals: Array[Vector2] = []
	for h in map.haul_outs:
		if h.kind != MapData.HaulOut.Kind.DOCK:
			for sp in h.spots:
				seals.append(Vector2(sp.edge.x, sp.edge.z))
	var route_pts := PackedVector2Array()
	for rt in map.routes:
		var pts := rt.curve.get_baked_points()
		for k in range(0, pts.size(), 6):
			route_pts.append(Vector2(pts[k].x, pts[k].z))
	# Every candidate in anchoring depth, close under the land, well sheltered and
	# out of everyone's way, scored by how sheltered it is.
	var cands: Array = []
	var near_cells := ceili(NEAR_LAND / STEP)
	for j in range(2, n - 2):
		for i in range(2, n - 2):
			var h := depth[j * n + i]
			if h < DEPTH.x or h > DEPTH.y:
				continue
			var p := Vector2(-hs + i * STEP, -hs + j * STEP)
			if absf(p.x) > hs - 30.0 or absf(p.y) > hs - 30.0 or not nav.open_at(p, false):
				continue
			if not _land_within(land, n, i, j, near_cells):
				continue
			var sh := _shelter(land, n, i, j)
			if sh < SHELTER:
				continue
			if _near_any(p, avoid, KEEP_FROM_HARBOURS) or _near_points(p, route_pts, KEEP_FROM_ROUTES) \
					or _near_any(p, seals, KEEP_FROM_HAUL_OUTS):
				continue
			if _near_ship_water(nav, p):
				continue
			cands.append([sh, p])
	cands.sort_custom(func(a: Array, b: Array): return a[0] > b[0])
	var out: Array[Anchorage] = []
	var reach_from := _reach_from(t)
	for c: Array in cands:
		if out.size() >= COUNT:
			break
		var p: Vector2 = c[1]
		var far := true
		for o in out:
			if o.center.distance_to(p) < KEEP_FROM_COVES:
				far = false
				break
		if not far:
			continue
		if reach_from != Vector2.INF and nav.find_path(reach_from, p, false).is_empty():
			continue
		var a := Anchorage.new()
		a.center = p
		a.shelter = c[0]
		a._lay_spots(cands)
		if a.spots.is_empty():
			continue
		a.place = _place_name(map, p)
		out.append(a)
	return out


## Spots round its centre: the most sheltered candidates near it, far enough apart.
func _lay_spots(cands: Array) -> void:
	for c: Array in cands:
		if spots.size() >= SPOTS:
			return
		var p: Vector2 = c[1]
		if p.distance_to(center) > SPREAD:
			continue
		var ok := true
		for sp in spots:
			if sp.pos.distance_to(p) < SPOT_GAP:
				ok = false
				break
		if ok:
			var sp := Spot.new()
			sp.pos = p
			sp.anchorage = self
			spots.append(sp)


func free_spots() -> int:
	var k := 0
	for sp in spots:
		if sp.taken_by == null or not is_instance_valid(sp.taken_by):
			k += 1
	return k


## Somewhere every small boat can get to (a marina's approach), to check a cove
## is reachable from the rest of the water.
static func _reach_from(t: MarineTraffic) -> Vector2:
	for m in t.sim.map.marinas:
		var a := m.at(Layout.MARINA_APPROACH_U + 10.0, 0.0)
		return Vector2(a.x, a.z)
	return Vector2.INF


static func _land_within(land: PackedByteArray, n: int, i: int, j: int, r: int) -> bool:
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var a := i + di
			var b := j + dj
			if a >= 0 and b >= 0 and a < n and b < n and land[b * n + a] == 1:
				return true
	return false


## Share of RAYS rays from cell (i, j) that meet land within RAY_REACH.
static func _shelter(land: PackedByteArray, n: int, i: int, j: int) -> float:
	var hits := 0
	var steps := int(RAY_REACH / STEP)
	for k in RAYS:
		var a := TAU * k / RAYS
		var dx := cos(a)
		var dy := sin(a)
		for st in range(1, steps + 1):
			var x := i + roundi(dx * st)
			var y := j + roundi(dy * st)
			if x < 0 or y < 0 or x >= n or y >= n:
				break
			if land[y * n + x] == 1:
				hits += 1
				break
	return float(hits) / RAYS


## Whether any water open to the ships lies within KEEP_FROM_SHIPS of `p`.
static func _near_ship_water(nav: NavGrid, p: Vector2) -> bool:
	if nav.open_at(p, true):
		return true
	for k in 12:
		var a := TAU * k / 12.0
		for r: float in [KEEP_FROM_SHIPS * 0.5, KEEP_FROM_SHIPS]:
			if nav.open_at(p + Vector2(cos(a), sin(a)) * r, true):
				return true
	return false


static func _near_any(p: Vector2, pts: Array[Vector2], r: float) -> bool:
	for q in pts:
		if q.distance_squared_to(p) < r * r:
			return true
	return false


static func _near_points(p: Vector2, pts: PackedVector2Array, r: float) -> bool:
	for q in pts:
		if q.distance_squared_to(p) < r * r:
			return true
	return false


## "in a cove on Fox Island", or "off Fox Island" when the nearest land is an
## unnamed islet near a named island, or "in a cove on the mainland".
static func _place_name(map: MapData, p: Vector2) -> String:
	var best: MapData.Island = null
	var best_d := INF
	for isl in map.islands:
		var d := p.distance_to(isl.center) - isl.radius
		if d < best_d:
			best_d = d
			best = isl
	if best == null:
		return "in a cove"
	if best.is_mainland:
		return "in a cove on the mainland"
	if best.name != "":
		return "in a cove on " + best.name
	var named: MapData.Island = null
	var nd := INF
	for isl in map.islands:
		if isl.name == "":
			continue
		var d := p.distance_to(isl.center) - isl.radius
		if d < nd:
			nd = d
			named = isl
	return "in a cove off " + named.name if named else "in a cove"
