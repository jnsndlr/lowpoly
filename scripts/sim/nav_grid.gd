class_name NavGrid
extends RefCounted
## Coarse water grids that sailboats and cargo ships plan their passages on. A cell
## is open when it is far enough from land for that class of boat; ferry terminals
## marina piers and fish quays are closed off, and ferry lanes cost extra so other traffic
## crosses them rather than following them. Paths come back string-pulled, in
## world x, z; finish() shifts them to keep right and rounds their corners.

const CELL := 6.0
# Centre of an open cell to the nearest land cell's centre (land is anything
# shallower than LAND_DEPTH within a couple of metres of a cell's centre).
const SMALL_CLEAR := 12.0
const LARGE_CLEAR := 30.0
const LAND_DEPTH := -1.6
const SMALL_LANE_COST := 3.0
const LARGE_LANE_COST := 6.0

var ext := 0.0      # the grids cover [-ext, ext] on both axes
var n := 0
var terrain: Terrain
var small := AStarGrid2D.new()
var large := AStarGrid2D.new()


func _init(map: MapData, t: Terrain) -> void:
	terrain = t
	ext = map.half_size + 110.0
	n = ceili(ext * 2.0 / CELL)
	var land := PackedByteArray()
	land.resize(n * n)
	for j in n:
		for i in n:
			var c := center(Vector2i(i, j))
			var h := terrain.height_at(c.x, c.y)
			for o: Vector2 in [Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(-2.5, 2.5), Vector2(2.5, 2.5)]:
				h = maxf(h, terrain.height_at(c.x + o.x, c.y + o.y))
			land[j * n + i] = 1 if h > LAND_DEPTH else 0
	var dist := _distance(land)
	for g: AStarGrid2D in [small, large]:
		g.region = Rect2i(0, 0, n, n)
		g.cell_size = Vector2(CELL, CELL)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
	for j in n:
		for i in n:
			var d := dist[j * n + i]
			small.set_point_solid(Vector2i(i, j), d < SMALL_CLEAR)
			large.set_point_solid(Vector2i(i, j), d < LARGE_CLEAR)
	_mark_lanes(map)
	_close_terminals(map)
	_close_marinas(map)
	_close_quays(map)


func cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + ext) / CELL), 0, n - 1), clampi(floori((p.y + ext) / CELL), 0, n - 1))


func center(c: Vector2i) -> Vector2:
	return Vector2(-ext + (c.x + 0.5) * CELL, -ext + (c.y + 0.5) * CELL)


## Chamfer distance (in metres) from every cell to the nearest land cell.
func _distance(land: PackedByteArray) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n * n)
	for k in n * n:
		d[k] = 0.0 if land[k] == 1 else INF
	var o := CELL
	var dg := CELL * sqrt(2.0)
	for j in n:
		for i in n:
			var k := j * n + i
			var v := d[k]
			if i > 0:
				v = minf(v, d[k - 1] + o)
			if j > 0:
				v = minf(v, d[k - n] + o)
				if i > 0:
					v = minf(v, d[k - n - 1] + dg)
				if i < n - 1:
					v = minf(v, d[k - n + 1] + dg)
			d[k] = v
	for j in range(n - 1, -1, -1):
		for i in range(n - 1, -1, -1):
			var k := j * n + i
			var v := d[k]
			if i < n - 1:
				v = minf(v, d[k + 1] + o)
			if j < n - 1:
				v = minf(v, d[k + n] + o)
				if i < n - 1:
					v = minf(v, d[k + n + 1] + dg)
				if i > 0:
					v = minf(v, d[k + n - 1] + dg)
			d[k] = v
	return d


func _cells_within(p: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := cell(p - Vector2(radius, radius))
	var b := cell(p + Vector2(radius, radius))
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			var c := Vector2i(i, j)
			if center(c).distance_to(p) <= radius + CELL * 0.5:
				out.append(c)
	return out


func _mark_lanes(map: MapData) -> void:
	for r in map.routes:
		var pts := r.curve.get_baked_points()
		for k in range(0, pts.size(), 4):
			var p := Vector2(pts[k].x, pts[k].z)
			for c in _cells_within(p, 14.0):
				small.set_point_weight_scale(c, SMALL_LANE_COST)
			for c in _cells_within(p, 22.0):
				large.set_point_weight_scale(c, LARGE_LANE_COST)


## The terminal, its slips, dolphins and channel buoys.
func _close_terminals(map: MapData) -> void:
	for isl in map.islands:
		if not isl.has_terminal:
			continue
		var hw := isl.lot_half_width + 16.0
		var u := -10.0
		while u <= Layout.PIER_END + 54.0:
			var v := -hw
			while v <= hw:
				var p := isl.shore + isl.dock_dir * u + isl.lateral() * v
				var c := cell(Vector2(p.x, p.z))
				small.set_point_solid(c)
				large.set_point_solid(c)
				v += 3.0
			u += 3.0


## The pier, T-head and berths, and the water either side of them in under the
## shore (boats get to and from their berths on straight legs, never round the
## ends of the berths).
func _close_marinas(map: MapData) -> void:
	for m in map.marinas:
		var u := -2.0
		while u <= 52.0:
			var v := -26.0
			while v <= 26.0:
				var p := m.at(u, v)
				var c := cell(Vector2(p.x, p.z))
				large.set_point_solid(c)
				if u <= Layout.MARINA_BERTH_U + 4.0 and absf(v) <= Layout.MARINA_HEAD_HALF + 10.0:
					small.set_point_solid(c)
				v += 3.0
			u += 3.0


## The jetty and wharf, and (for ships) the lane off it the boats based there use.
func _close_quays(map: MapData) -> void:
	for q in map.wharves():
		var u := -2.0
		while u <= Layout.QUAY_LANE_U + 16.0:
			var v := -Layout.QUAY_RUN - 10.0
			while v <= Layout.QUAY_RUN + 10.0:
				var p := q.at(u, v)
				var c := cell(Vector2(p.x, p.z))
				large.set_point_solid(c)
				if u <= Layout.QUAY_FACE_U + 2.0 and absf(v) <= Layout.QUAY_HALF + 2.0:
					small.set_point_solid(c)
				v += 3.0
			u += 3.0


## Nearest open cell to `c`, searching outward a few rings; (-1, -1) if none.
func _nearest_open(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not g.is_point_solid(c):
		return c
	for r in range(1, 8):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for j in range(c.y - r, c.y + r + 1):
			for i in range(c.x - r, c.x + r + 1):
				if maxi(absi(i - c.x), absi(j - c.y)) != r or i < 0 or j < 0 or i >= n or j >= n:
					continue
				var q := Vector2i(i, j)
				if g.is_point_solid(q):
					continue
				var d := Vector2(q - c).length_squared()
				if d < best_d:
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## A path from `from` to `to` (both included), or empty if there is none.
## `avoid` is a list of Vector3(x, z, radius) circles to keep out of as well.
func find_path(from: Vector2, to: Vector2, big: bool, avoid: Array[Vector3] = []) -> PackedVector2Array:
	var g := large if big else small
	var closed: Array[Vector2i] = []
	var ends := [cell(from), cell(to)]
	for a in avoid:
		for c in _cells_within(Vector2(a.x, a.y), a.z):
			if not g.is_point_solid(c) and not ends.has(c):
				g.set_point_solid(c)
				closed.append(c)
	var out := PackedVector2Array()
	var ca := _nearest_open(g, ends[0])
	var cb := _nearest_open(g, ends[1])
	if ca.x >= 0 and cb.x >= 0:
		var ids := g.get_id_path(ca, cb)
		if not ids.is_empty():
			var raw := PackedVector2Array([from])
			for c in ids:
				raw.append(center(c))
			raw.append(to)
			out = _pull(g, raw)
	for c in closed:
		g.set_point_solid(c, false)
	return out


## True if the straight line a → b stays in water open to that class of boat.
func clear_line(a: Vector2, b: Vector2, big: bool) -> bool:
	return _sight(large if big else small, a, b)


## True if `p` is in water open to that class of boat.
func open_at(p: Vector2, big: bool) -> bool:
	var e := ext - CELL
	if absf(p.x) > e or absf(p.y) > e:
		return false
	return not (large if big else small).is_point_solid(cell(p))


## Drops every point that can be skipped with a clear straight line.
func _pull(g: AStarGrid2D, raw: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1 and not _sight(g, raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	return out


## True if the straight line a → b stays in open cells (ignoring the end cells,
## which may be closed: a boat starting at its berth, say).
func _sight(g: AStarGrid2D, a: Vector2, b: Vector2) -> bool:
	var ca := cell(a)
	var cb := cell(b)
	var steps := ceili(a.distance_to(b) / (CELL * 0.4))
	for k in range(1, steps):
		var c := cell(a.lerp(b, float(k) / steps))
		if c != ca and c != cb and g.is_point_solid(c):
			return false
	return true


## A string-pulled path made sailable: kept `keep` metres right of its course,
## corners rounded (no cut deeper than `cut`). Pulled paths wrap closely round the
## land they avoid and rounding cuts in towards it, so the result is checked
## against the seabed `half_width` either side of the track, falling back to
## gentler versions and at worst the path as it was.
func finish(pts: PackedVector2Array, keep: float, cut: float, iterations: int, half_width: float, taper := 25.0) -> PackedVector2Array:
	for f: float in [1.0, 0.5, 0.25]:
		var out := smooth(keep_right(pts, keep * f, taper), iterations, cut * f)
		if afloat(out, half_width):
			return out
	return pts


## True if the track stays in water deeper than LAND_DEPTH, `half_width` either side.
func afloat(pts: PackedVector2Array, half_width: float) -> bool:
	var p := NavPath.new(pts)
	var s := 0.0
	while s <= p.length:
		var q := p.sample(s)
		var t := p.tangent(s, 1.0)
		var side := Vector2(-t.y, t.x) * half_width
		for o: Vector2 in [Vector2.ZERO, side, -side]:
			if terrain.height_at(q.x + o.x, q.y + o.y) > LAND_DEPTH:
				return false
		s += 2.0
	return true


## Shifts a path `amount` to the right of travel (so boats on opposite courses pass
## each other), easing in and out over `taper` metres so the ends stay put (or
## shifting the ends too if `taper` is 0).
static func keep_right(pts: PackedVector2Array, amount: float, taper := 25.0) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var path := NavPath.new(pts)
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		var f := 1.0 if taper <= 0.0 else clampf(minf(path.cum[i], path.length - path.cum[i]) / taper, 0.0, 1.0)
		out.append(pts[i] + Vector2(-t.y, t.x) * amount * f)
	return out


## Rounds the corners (Chaikin, cutting no more than `cut` off each side of a
## corner), keeping both ends.
static func smooth(pts: PackedVector2Array, iterations: int, cut := INF) -> PackedVector2Array:
	for it in iterations:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var f := minf(0.25, cut / maxf(a.distance_to(b), 1e-3))
			if i > 0:
				out.append(a.lerp(b, f))
			if i < pts.size() - 2:
				out.append(a.lerp(b, 1.0 - f))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts
