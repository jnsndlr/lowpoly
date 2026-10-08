class_name Terrain
extends RefCounted
## Heightfield for the whole map. Islands are "stamped" into an elevation grid, shaped
## into rocky shores and rolling hills, then flattened where terminals need level ground.
## height_at() matches the rendered triangles exactly, so props sit on the surface.

const CELL := 7.5
const SEA_FLOOR := -16.5

var half_size: float
var n: int  # cells per side
var e_grid := PackedFloat32Array()  # raw island "elevation" 0..~1.3
var h_grid := PackedFloat32Array()  # final heights
var warp := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var flats: Array[Dictionary] = []
## The land past the grid's edge (heights there come from it, see outer_height).
var mainland: Mainland
# Stamps that reach past the grid's edge (x, z, radius, strength), continued by outer_height.
var _edge_stamps: Array[Vector4] = []


func _init(map_seed: int, half: float) -> void:
	half_size = half
	n = int(round(half * 2.0 / CELL))
	e_grid.resize((n + 1) * (n + 1))
	e_grid.fill(0.0)
	warp.seed = map_seed
	warp.frequency = 0.0046667
	warp.fractal_octaves = 3
	detail.seed = map_seed + 17
	detail.frequency = 0.0166667
	mainland = Mainland.new(map_seed, half)


func _index_of(coord: float) -> int:
	return clampi(int((coord + half_size) / CELL), 0, n)


func stamp_island(center: Vector2, radius: float, strength: float) -> void:
	var reach := radius * 1.7
	if maxf(absf(center.x), absf(center.y)) + reach > half_size:
		_edge_stamps.append(Vector4(center.x, center.y, radius, strength))
	var i0 := _index_of(center.x - reach)
	var i1 := _index_of(center.x + reach)
	var j0 := _index_of(center.y - reach)
	var j1 := _index_of(center.y + reach)
	for j in range(j0, j1 + 1):
		var z := -half_size + j * CELL
		for i in range(i0, i1 + 1):
			var x := -half_size + i * CELL
			var e := _stamp_e(center, radius, strength, x, z)
			var k := j * (n + 1) + i
			if e > e_grid[k]:
				e_grid[k] = e


func _stamp_e(center: Vector2, radius: float, strength: float, x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(center) / radius + warp.get_noise_2d(x, z) * 0.3
	return clampf(1.0 - d, 0.0, 1.0) * strength


## Turns elevation into heights. The grid's edge needs no fade: the Backdrop carries
## the land on from it (outer_height), so the mainland runs on past it.
func finalize() -> void:
	h_grid.resize(e_grid.size())
	for j in n + 1:
		var z := -half_size + j * CELL
		for i in n + 1:
			var x := -half_size + i * CELL
			h_grid[j * (n + 1) + i] = _height_of(e_grid[j * (n + 1) + i], x, z)


## A steep rocky shoreline, then gentle hills.
func _height_of(e: float, x: float, z: float) -> float:
	var land := smoothstep(0.2, 0.32, e)
	return SEA_FLOOR + land * 18.6 + e * 21.0 + detail.get_noise_2d(x, z) * 5.4 * land


## Height past the grid: the mainland's shores, hills and mountains, and the parts
## of island stamps that reach out past the edge.
func outer_height(x: float, z: float) -> float:
	var inl := mainland.inland(x, z)
	var e := mainland.elev(x, z, inl)
	# Out in the open channel, stamps sink away just past the edge so they leave
	# the shipping lanes clear; near the shores they run on into the mainland.
	var out := maxf(absf(x), absf(z)) - half_size
	var keep := 1.0 - smoothstep(0.0, 180.0, out) * (1.0 - smoothstep(-660.0, -180.0, inl))
	if keep > 0.0:
		for s in _edge_stamps:
			e = maxf(e, _stamp_e(Vector2(s.x, s.y), s.z, s.w, x, z) * keep)
	return _height_of(e, x, z) + mainland.relief(x, z, inl, e)


func add_flat(origin: Vector3, dir: Vector3, u0: float, u1: float, v0: float, v1: float, height: float, blend: float) -> void:
	flats.append({"o": origin, "n": dir, "t": Vector3.UP.cross(dir), "u0": u0, "u1": u1,
		"v0": v0, "v1": v1, "h": height, "blend": blend})


func apply_flats() -> void:
	for f in flats:
		var o: Vector3 = f.o
		var nd: Vector3 = f.n
		var td: Vector3 = f.t
		var u0: float = f.u0
		var u1: float = f.u1
		var v0: float = f.v0
		var v1: float = f.v1
		var blend: float = f.blend
		var target: float = f.h
		var reach := maxf(absf(u0), absf(u1)) + maxf(absf(v0), absf(v1)) + blend
		var i0 := _index_of(o.x - reach)
		var i1 := _index_of(o.x + reach)
		var j0 := _index_of(o.z - reach)
		var j1 := _index_of(o.z + reach)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector3(-half_size + i * CELL, 0.0, -half_size + j * CELL) - o
				var u := p.dot(nd)
				var v := p.dot(td)
				var du := maxf(maxf(u0 - u, u - u1), 0.0)
				var dv := maxf(maxf(v0 - v, v - v1), 0.0)
				var dd := sqrt(du * du + dv * dv)
				if dd >= blend:
					continue
				var k := j * (n + 1) + i
				h_grid[k] = lerpf(h_grid[k], target, 1.0 - smoothstep(0.0, blend, dd))


## Cuts a pocket beach into the shore at `origin` (on the waterline), facing out
## along `dir`: a gentle slope from `back` inland, curving deeper in at the middle,
## down to `front` out to sea, `half_w` either side, blending into the banks.
func carve_beach(origin: Vector3, dir: Vector3, half_w: float, back: float, front: float) -> void:
	var td := Vector3.UP.cross(dir)
	var reach := half_w + back + front + 12.0
	for j in range(_index_of(origin.z - reach), _index_of(origin.z + reach) + 1):
		for i in range(_index_of(origin.x - reach), _index_of(origin.x + reach) + 1):
			var p := Vector3(-half_size + i * CELL, 0.0, -half_size + j * CELL) - origin
			var u := p.dot(dir)
			var v := p.dot(td)
			var across := absf(v) / half_w
			if across >= 1.0:
				continue
			var u_back := -back * (1.0 - 0.45 * across * across)
			var w := (1.0 - smoothstep(0.55, 1.0, across)) * smoothstep(u_back - 12.0, u_back, u) \
				* (1.0 - smoothstep(front - 9.0, front + 9.0, u))
			if w <= 0.0:
				continue
			var s := clampf((u - u_back) / (front - u_back), 0.0, 1.0)
			var k := j * (n + 1) + i
			# Only ever cut down: no spits built out into deep water off a point.
			h_grid[k] = minf(h_grid[k], lerpf(h_grid[k], lerpf(4.5, -7.8, pow(s, 0.85)), w))


func h_index(i: int, j: int) -> float:
	return h_grid[j * (n + 1) + i]


## Height of the rendered surface (matches the alternating-diagonal triangulation).
func height_at(x: float, z: float) -> float:
	var fx := (x + half_size) / CELL
	var fz := (z + half_size) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= n or fz >= n:
		return outer_height(x, z)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * (n + 1) + i
	var a := h_grid[k]
	var b := h_grid[k + 1]
	var c := h_grid[k + n + 1]
	var d := h_grid[k + n + 2]
	if (i + j) % 2 == 0:
		if tx >= tz:
			return a + (b - a) * tx + (d - b) * tz
		return a + (c - a) * tz + (d - c) * tx
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


func height_v(p: Vector3) -> float:
	return height_at(p.x, p.z)
