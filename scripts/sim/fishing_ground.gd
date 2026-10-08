class_name FishingGround
extends RefCounted
## A stretch of water the trawlers work: a strip along the edge of the bank off an
## island, which they tow up and down. One boat works a ground at a time. They
## aren't shown to the player; the boats just go there.

const COUNT := 6
const HALF_LENGTH := Vector2(255.0, 360.0)
const HALF_WIDTH := 48.0        # how far either side of its line the tows are spread
const OFFSHORE := Vector2(120.0, 225.0)   # its line from the shore
const DEPTH := -10.8             # the shallowest water anywhere on it
const KEEP_FROM_ROUTES := 165.0
const KEEP_FROM_HARBOURS := 225.0   # (their approaches, and the ferry terminals)
const KEEP_FROM_GROUNDS := 510.0

var center := Vector2.ZERO
var axis := Vector2.RIGHT       # along its line (unit)
var half_length := 300.0
var richness := 1.0             # how well the fishing goes here
var worked_by: Vessel = null


## A point on it: `along` (-1..1) from one end to the other, `across` metres off
## its line.
func at(along: float, across: float) -> Vector2:
	return center + axis * along * half_length + Vector2(-axis.y, axis.x) * across


## Lays out the grounds for `t`'s map, with its own RNG so the rest of the
## traffic stays the same.
static func find_all(t: MarineTraffic) -> Array[FishingGround]:
	var r := RandomNumberGenerator.new()
	r.seed = t.sim.map.map_seed * 41 + 13
	var map := t.sim.map
	var out: Array[FishingGround] = []
	var avoid: Array[Vector2] = []
	for isl in map.islands:
		if isl.has_terminal:
			avoid.append(Vector2(isl.shore.x, isl.shore.z))
	for m in map.marinas:
		var a := m.at(Layout.MARINA_APPROACH_U, 0.0)
		avoid.append(Vector2(a.x, a.z))
	for q in map.wharves():
		var a := q.at(Layout.QUAY_LANE_U, 0.0)
		avoid.append(Vector2(a.x, a.z))
	var route_pts := PackedVector2Array()
	for rt in map.routes:
		var pts := rt.curve.get_baked_points()
		for k in range(0, pts.size(), 6):
			route_pts.append(Vector2(pts[k].x, pts[k].z))
	for attempt in 900:
		if out.size() >= COUNT:
			break
		var isl := map.islands[r.randi_range(0, map.islands.size() - 1)]
		var a := r.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		# Out from the island's middle to its shore, then off it.
		var shore := -1.0
		var d := 0.0
		while d < isl.radius * 2.0:
			var p := isl.center + dir * d
			if t.sim.terrain.height_at(p.x, p.y) < -3.0:
				shore = d
				break
			d += 6.0
		if shore < 0.0:
			continue
		var g := FishingGround.new()
		g.center = isl.center + dir * (shore + r.randf_range(OFFSHORE.x, OFFSHORE.y))
		g.axis = Vector2(-dir.y, dir.x)
		g.half_length = r.randf_range(HALF_LENGTH.x, HALF_LENGTH.y)
		g.richness = r.randf_range(0.6, 1.4)
		if g._fits(t, out, avoid, route_pts) and g._reachable(t):
			out.append(g)
	return out


func _fits(t: MarineTraffic, others: Array[FishingGround], avoid: Array[Vector2], route_pts: PackedVector2Array) -> bool:
	var lim := t.sim.map.half_size - 90.0
	for o in others:
		if o.center.distance_to(center) < KEEP_FROM_GROUNDS:
			return false
	var along := -1.0
	while along <= 1.001:
		for across: float in [-HALF_WIDTH - 24.0, 0.0, HALF_WIDTH + 24.0]:
			var p := at(along, across)
			if absf(p.x) > lim or absf(p.y) > lim:
				return false
			if not t.nav.open_at(p, false) or t.sim.terrain.height_at(p.x, p.y) > DEPTH:
				return false
		var c := at(along, 0.0)
		for q in avoid:
			if q.distance_squared_to(c) < KEEP_FROM_HARBOURS * KEEP_FROM_HARBOURS:
				return false
		for q in route_pts:
			if q.distance_squared_to(c) < KEEP_FROM_ROUTES * KEEP_FROM_ROUTES:
				return false
		along += 0.1
	return true


## Whether the boats from every fish quay can get there.
func _reachable(t: MarineTraffic) -> bool:
	for q in t.sim.map.quays:
		var a := q.at(Layout.QUAY_LANE_U, q.side * Layout.QUAY_RUN)
		if t.nav.find_path(Vector2(a.x, a.z), center, false).is_empty():
			return false
	return true
