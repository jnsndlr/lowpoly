class_name WorldBuilder
extends RefCounted
## Turns MapData + Terrain into renderable nodes: terrain, water, terminals, roads,
## towns, forests, rocks, boats and the route overlay. Pure presentation — no sim state.

const ASPHALT := Color(0.26, 0.27, 0.29)
const CONCRETE := Color(0.62, 0.62, 0.6)
const ROAD := Color(0.3, 0.31, 0.33)
const LINE_WHITE := Color(0.9, 0.9, 0.86)
const LINE_YELLOW := Color(0.92, 0.78, 0.3)
const WALLS := [Color(0.93, 0.89, 0.8), Color(0.94, 0.94, 0.92), Color(0.62, 0.7, 0.78),
	Color(0.66, 0.74, 0.62), Color(0.66, 0.38, 0.3), Color(0.92, 0.82, 0.52)]
const ROOFS := [Color(0.72, 0.26, 0.2), Color(0.28, 0.3, 0.34), Color(0.25, 0.36, 0.52),
	Color(0.45, 0.3, 0.22), Color(0.2, 0.45, 0.42)]
# Alternatives: water_gem.gdshader, water_sharp.gdshader, water_fold.gdshader, water_reference.gdshader.
const WATER_SHADER := "res://shaders/water.gdshader"

var map: MapData
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var root: Node3D
var route_overlay: MeshInstance3D
var water_material: ShaderMaterial
var _blocked := {}


func _init(m: MapData, t: Terrain) -> void:
	map = m
	terrain = t
	rng.seed = m.map_seed * 31 + 7


func build() -> Node3D:
	root = Node3D.new()
	root.name = "World"
	_build_terrain()
	_build_water()
	_build_terminals()
	_build_roads()
	_build_towns()
	_build_lighthouses()
	_build_vegetation()
	_build_boats()
	_build_route_overlay()
	return root


func _add_mesh(mesh: Mesh, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = node_name
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], node_name: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = node_name
	root.add_child(mmi)


# --- Blocking grid so props don't overlap roads, lots and houses -------------------

func _block(p: Vector3, radius: float) -> void:
	var r := ceili(radius / 2.0)
	var cx := floori(p.x / 2.0)
	var cz := floori(p.z / 2.0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_blocked[Vector2i(cx + dx, cz + dz)] = true


func _is_blocked(x: float, z: float) -> bool:
	return _blocked.has(Vector2i(floori(x / 2.0), floori(z / 2.0)))


static func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)


# --- Terrain ------------------------------------------------------------------------

func _build_terrain() -> void:
	var mb := MeshBuilder.new()
	var n := terrain.n
	var hs := terrain.half_size
	var c := Terrain.CELL
	for j in n:
		for i in n:
			var h00 := terrain.h_index(i, j)
			var h10 := terrain.h_index(i + 1, j)
			var h01 := terrain.h_index(i, j + 1)
			var h11 := terrain.h_index(i + 1, j + 1)
			if maxf(maxf(h00, h10), maxf(h01, h11)) < -5.2:
				continue
			var x0 := -hs + i * c
			var z0 := -hs + j * c
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + c, h10, z0)
			var p01 := Vector3(x0, h01, z0 + c)
			var p11 := Vector3(x0 + c, h11, z0 + c)
			if (i + j) % 2 == 0:
				_terrain_tri(mb, p00, p10, p11)
				_terrain_tri(mb, p00, p11, p01)
			else:
				_terrain_tri(mb, p00, p10, p01)
				_terrain_tri(mb, p10, p11, p01)
	_add_mesh(mb.commit(), "Terrain")

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(6000, 6000)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.4, 0.45, 0.36)
	floor_mesh.material = floor_mat
	var fl := _add_mesh(floor_mesh, "SeaFloor", false)
	fl.position.y = -5.35


func _terrain_tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		return
	nrm = nrm.normalized()
	var col := _ground_color((a.y + b.y + c.y) / 3.0, absf(nrm.y), a.x + c.x, a.z + b.z)
	if nrm.y < 0.0:
		mb.tri_raw(a, c, b, -nrm, col)
	else:
		mb.tri_raw(a, b, c, nrm, col)


func _ground_color(h: float, ny: float, sx: float, sz: float) -> Color:
	var r := _hash(sx, sz)
	var col: Color
	if h < -0.3:
		col = Color(0.66, 0.63, 0.47).darkened(clampf(-h * 0.07, 0.0, 0.45))
	elif ny < 0.72:
		col = Color(0.5, 0.43, 0.42).lerp(Color(0.63, 0.54, 0.49), r)
	elif h < 1.15:
		col = Color(0.8, 0.73, 0.54)
	else:
		var g := clampf((h - 1.2) / 8.0, 0.0, 1.0)
		col = Color(0.52, 0.6, 0.25).lerp(Color(0.33, 0.46, 0.2), g)
	return col.darkened(r * 0.08)


# --- Water --------------------------------------------------------------------------

func _build_water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_SHADER)
	# Float heights retain negative seabed elevations. The shader interpolates the
	# same triangles as Terrain, so shallow colours stay attached to the shore.
	var heights := Image.create_from_data(terrain.n + 1, terrain.n + 1,
		false, Image.FORMAT_RF, terrain.h_grid.to_byte_array())
	mat.set_shader_parameter("seabed_height", ImageTexture.create_from_image(heights))
	mat.set_shader_parameter("terrain_half_size", terrain.half_size)
	mat.set_shader_parameter("terrain_cell", Terrain.CELL)
	var inner := map.half_size + 100.0
	mat.set_shader_parameter("swell_extent", inner)
	water_material = mat
	var plane := PlaneMesh.new()
	plane.size = Vector2(inner * 2.0, inner * 2.0)
	plane.subdivide_width = 180
	plane.subdivide_depth = 180
	var water := _add_mesh(plane, "Water", false)
	water.material_override = mat

	# Flat ring out to the horizon around the detailed plane.
	var o := 3000.0
	var w := inner
	var mb := MeshBuilder.new()
	var col := Color.WHITE
	mb.quad(Vector3(-o, 0, -o), Vector3(o, 0, -o), Vector3(o, 0, -w), Vector3(-o, 0, -w), col, Vector3.UP)
	mb.quad(Vector3(-o, 0, w), Vector3(o, 0, w), Vector3(o, 0, o), Vector3(-o, 0, o), col, Vector3.UP)
	mb.quad(Vector3(-o, 0, -w), Vector3(-w, 0, -w), Vector3(-w, 0, w), Vector3(-o, 0, w), col, Vector3.UP)
	mb.quad(Vector3(w, 0, -w), Vector3(o, 0, -w), Vector3(o, 0, w), Vector3(w, 0, w), col, Vector3.UP)
	var ring := _add_mesh(mb.commit(), "WaterRing", false)
	ring.material_override = mat


# --- Terminals ----------------------------------------------------------------------

func _build_terminals() -> void:
	for isl in map.islands:
		if not isl.has_terminal:
			continue
		var mb := MeshBuilder.new()
		mb.xform = isl.terminal_xform()
		var hw := isl.lot_half_width
		var ly := Layout.LOT_Y
		var mid_u := (Layout.LOT_FRONT + Layout.LOT_BACK) * 0.5
		mb.box(Vector3(0, ly - 0.45, mid_u), Vector3(hw * 2.0 + 1.2, 0.8, Layout.LOT_LENGTH + 1.2), CONCRETE)
		mb.box(Vector3(0, ly - 0.3, mid_u), Vector3(hw * 2.0, 0.6, Layout.LOT_LENGTH), ASPHALT)

		# Lane markings
		var mark_len := Layout.LANE_HEAD - (Layout.LOT_BACK + 2.5) + 1.0
		var mark_u := (Layout.LANE_HEAD + 1.0 + Layout.LOT_BACK + 2.5) * 0.5
		for lane_set in Layout.lane_positions(hw, isl.slips.size()):
			for v in lane_set:
				for side: float in [-1.2, 1.2]:
					mb.box(Vector3(v + side, ly + 0.01, mark_u), Vector3(0.12, 0.02, mark_len), LINE_WHITE)
		var u := Layout.LOT_BACK + 1.5
		while u < Layout.LOT_FRONT - 1.0:
			mb.box(Vector3(0, ly + 0.01, u), Vector3(0.14, 0.02, 1.2), LINE_YELLOW)
			u += 2.4

		for i in isl.slips.size():
			_build_slip(mb, isl.slip_offset(i))

		# Terminal building beside the lot
		var bv := hw + 5.0
		mb.box(Vector3(bv, ly + 1.2, -12.0), Vector3(7.0, 3.4, 12.0), Color(0.9, 0.9, 0.87))
		mb.box(Vector3(bv, ly + 1.6, -12.0), Vector3(7.1, 0.9, 10.5), Models.GLASS)
		mb.box(Vector3(bv, ly + 3.1, -12.0), Vector3(7.8, 0.4, 12.8), Models.WSF_GREEN)
		mb.box(Vector3(bv - 3.9, ly + 3.4, -6.0), Vector3(0.12, 5.0, 0.12), Color(0.8, 0.8, 0.8))
		mb.box(Vector3(bv - 3.9, ly + 5.6, -5.55), Vector3(0.05, 0.6, 0.9), Models.WSF_GREEN)

		# Toll plaza on the approach road
		var tu := Layout.LOT_BACK - 3.0
		for v: float in [-2.7, 2.7]:
			mb.box(Vector3(v, ly + 0.4, tu), Vector3(1.1, 2.6, 1.8), Color(0.92, 0.92, 0.9))
			mb.box(Vector3(v, ly + 0.9, tu), Vector3(1.15, 0.6, 1.3), Models.GLASS)
			mb.box(Vector3(v * 1.45, ly + 1.1, tu), Vector3(0.3, 4.0, 0.3), Color(0.85, 0.85, 0.85))
		mb.box(Vector3(0, ly + 3.25, tu), Vector3(8.6, 0.35, 3.4), Models.WSF_GREEN)

		# Light poles
		for v: float in [-hw + 0.4, hw - 0.4]:
			for pu: float in [Layout.LOT_FRONT - 1.0, Layout.LOT_BACK + 1.0]:
				mb.box(Vector3(v, ly + 2.5, pu), Vector3(0.18, 5.0, 0.18), Color(0.35, 0.36, 0.38))
				mb.box(Vector3(v, ly + 5.0, pu), Vector3(0.6, 0.18, 0.6), Color(0.95, 0.95, 0.8))

		_add_mesh(mb.commit(), isl.name + " Terminal")

		# Keep trees and houses off the lot, piers and building.
		var t := isl.lateral()
		var bu := Layout.LOT_BACK - 6.0
		while bu < Layout.PIER_END:
			var bvv := -hw - 3.0
			while bvv < hw + 12.0:
				_block(isl.shore + isl.dock_dir * bu + t * bvv, 1.0)
				bvv += 1.5
			bu += 1.5


func _build_slip(mb: MeshBuilder, v: float) -> void:
	var ly := Layout.LOT_Y
	var pe := Layout.PIER_END
	var lf := Layout.LOT_FRONT
	mb.box(Vector3(v, ly - 0.2, (lf + pe) * 0.5), Vector3(5.0, 0.4, pe - lf + 0.4), CONCRETE)
	mb.box(Vector3(v, ly + 0.01, (lf + pe) * 0.5), Vector3(0.12, 0.02, pe - lf - 1.0), LINE_YELLOW)
	var u := lf + 1.0
	while u < pe:
		for side: float in [-2.2, 2.2]:
			mb.box(Vector3(v + side, -1.4, u), Vector3(0.4, 4.2, 0.4), Models.WOOD)
		u += 3.0
	mb.box(Vector3(v, ly - 0.12, pe - 1.5), Vector3(5.2, 0.36, 3.0), Color(0.4, 0.42, 0.45))
	for side: float in [-2.9, 2.9]:
		mb.box(Vector3(v + side, 2.8, pe - 1.0), Vector3(0.5, 5.6, 0.5), Models.WSF_GREEN)
	mb.box(Vector3(v, 5.4, pe - 1.0), Vector3(6.3, 0.5, 0.5), Models.WSF_GREEN)
	for side: float in [-1.0, 1.0]:
		mb.box(Vector3(v + side * 4.95, 0.3, pe + 5.0), Vector3(0.9, 4.0, 9.0), Models.WOOD)
		mb.cylinder(Vector3(v + side * 5.7, -2.0, pe + 21.0), 1.0, 0.85, 4.6, 7, Models.WOOD, Color(0.85, 0.85, 0.8))
		Models.add_buoy(mb, Vector3(v + side * 8.0, 0.0, pe + 44.0), Color(0.2, 0.55, 0.3) if side < 0 else Color(0.8, 0.2, 0.15))


# --- Roads & towns ------------------------------------------------------------------

func _build_roads() -> void:
	var mb := MeshBuilder.new()
	for isl in map.islands:
		if isl.road_main_a.is_empty():
			continue
		var main := isl.road_main_a.duplicate()
		main.append_array(isl.road_main_b)
		var lines: Array[PackedVector3Array] = [main]
		lines.append_array(isl.road_cross)
		for line in lines:
			mb.ribbon(line, 3.4, ROAD)
			for p in line:
				_block(p, 3.0)
	_add_mesh(mb.commit(), "Roads", false)


func _build_towns() -> void:
	var variants: Array[Mesh] = []
	for i in 10:
		var stories := 2 if i >= 7 else 1
		variants.append(Models.house(WALLS[i % WALLS.size()], ROOFS[(i * 3 + 1) % ROOFS.size()], stories))
	variants.append(Models.block(Color(0.72, 0.7, 0.66)))
	variants.append(Models.block(Color(0.62, 0.42, 0.34)))
	var per_variant: Array = []
	for v in variants:
		var list: Array[Transform3D] = []
		per_variant.append(list)

	for isl in map.islands:
		if not isl.inhabited or isl.is_mainland:
			continue
		var tc := isl.town_center
		var t := isl.town_axis
		var inland := Vector3.UP.cross(t)  # perpendicular to the cross street
		if isl.has_terminal:
			inland = -isl.dock_dir
		var town_r := sqrt(isl.population / 90.0) * 3.0
		var spacing := 5.5
		for b in range(-8, 9):
			for a in range(-8, 9):
				if isl.has_terminal and (a == 0 or b == 0):
					continue  # the streets
				var p := tc + t * (a * spacing) + inland * (b * spacing)
				p += Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
				var r := Vector2(a, b).length() * spacing
				if rng.randf() > exp(-pow(r / town_r, 2.0)) * 1.15:
					continue
				if isl.has_terminal and (p - isl.shore).dot(isl.dock_dir) > Layout.LOT_BACK - 4.0:
					continue
				if _is_blocked(p.x, p.z):
					continue
				var h := terrain.height_v(p)
				if h < 1.4 or h > 10.0:
					continue
				var hmin := h
				var hmax := h
				for o: Vector3 in [t * 1.6, -t * 1.6, inland * 1.9, -inland * 1.9]:
					var hh := terrain.height_v(p + o)
					hmin = minf(hmin, hh)
					hmax = maxf(hmax, hh)
				if hmax - hmin > 1.8 or hmin < 0.8:
					continue
				var front := -inland * signf(b) if absi(b) <= absi(a) or a == 0 else -t * signf(a)
				if not isl.has_terminal:
					front = -inland
				var basis := Basis(Vector3.UP, atan2(front.x, front.z) + rng.randf_range(-0.05, 0.05))
				basis = basis.scaled(Vector3.ONE * rng.randf_range(0.9, 1.1))
				var vi := rng.randi_range(0, 9)
				if r < town_r * 0.4 and isl.population > 3500 and rng.randf() < 0.5:
					vi = 10 + rng.randi_range(0, 1)
				var bucket: Array[Transform3D] = per_variant[vi]
				bucket.append(Transform3D(basis, Vector3(p.x, hmin - 0.05, p.z)))
				_block(p, 2.6)
	var no_colors: Array[Color] = []
	for i in variants.size():
		var xforms: Array[Transform3D] = per_variant[i]
		_multimesh(variants[i], xforms, no_colors, "Houses%d" % i)


func _build_lighthouses() -> void:
	var mb := MeshBuilder.new()
	for isl in map.islands:
		if isl.is_mainland or not isl.inhabited or rng.randf() > 0.5:
			continue
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var c := Vector3(isl.center.x, 0, isl.center.y)
		var r := 0.0
		while r < isl.radius * 1.6 and terrain.height_v(c + dir * r) > 1.6:
			r += 0.5
		var p := c + dir * maxf(r - 3.0, 0.0)
		var h := terrain.height_v(p)
		if h < 1.2 or _is_blocked(p.x, p.z):
			continue
		Models.add_lighthouse(mb, Vector3(p.x, h - 0.1, p.z))
		_block(p, 6.0)
	_add_mesh(mb.commit(), "Lighthouses")


# --- Vegetation ---------------------------------------------------------------------

func _build_vegetation() -> void:
	var forest := FastNoiseLite.new()
	forest.seed = map.map_seed + 5
	forest.frequency = 0.02
	var pines: Array[Transform3D] = []
	var pine_cols: Array[Color] = []
	var rounds: Array[Transform3D] = []
	var round_cols: Array[Color] = []
	var rocks: Array[Transform3D] = []
	var towns: Array[MapData.Island] = []
	for isl in map.islands:
		if isl.inhabited and not isl.is_mainland:
			towns.append(isl)

	var step := 2.7
	var hs := terrain.half_size - 3.0
	var z := -hs
	while z < hs:
		var x := -hs
		while x < hs:
			var px := x + rng.randf_range(-1.4, 1.4)
			var pz := z + rng.randf_range(-1.4, 1.4)
			x += step
			var h := terrain.height_at(px, pz)
			# Open water gets nothing (and draws no random numbers), so skip the slope.
			if h <= -1.0 or _is_blocked(px, pz):
				continue
			var slope := Vector2(terrain.height_at(px + 1.0, pz) - terrain.height_at(px - 1.0, pz),
				terrain.height_at(px, pz + 1.0) - terrain.height_at(px, pz - 1.0)).length() * 0.5
			if h > 1.3 and slope < 1.0:
				var density := 0.85 + forest.get_noise_2d(px, pz) * 1.2
				var near_town := false
				for isl in towns:
					var town_r := sqrt(isl.population / 90.0) * 3.0 + 6.0
					if Vector2(px - isl.town_center.x, pz - isl.town_center.z).length() < town_r:
						near_town = true
						break
				if near_town:
					density *= 0.2
				if rng.randf() > density:
					continue
				var s := rng.randf_range(0.75, 1.35)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
				var xf := Transform3D(basis, Vector3(px, h - 0.1, pz))
				var tint := Color(rng.randf_range(0.8, 1.0), rng.randf_range(0.85, 1.0), rng.randf_range(0.8, 0.95))
				if rng.randf() < (0.45 if near_town else 0.2):
					rounds.append(xf)
					round_cols.append(tint)
				else:
					pines.append(xf)
					pine_cols.append(tint)
			elif (h > -1.0 and h < 0.7 and rng.randf() < 0.14) or (h > 0.7 and slope >= 1.0 and rng.randf() < 0.1):
				var s := rng.randf_range(0.5, 1.7)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.4), s, s))
				rocks.append(Transform3D(basis, Vector3(px, h, pz)))
		z += step
	_multimesh(Models.pine_tree(), pines, pine_cols, "Pines")
	_multimesh(Models.round_tree(), rounds, round_cols, "RoundTrees")
	var no_colors: Array[Color] = []
	_multimesh(Models.rock(), rocks, no_colors, "Rocks")


func _build_boats() -> void:
	var samples := PackedVector3Array()
	for r in map.routes:
		samples.append_array(r.curve.get_baked_points())
	var boats: Array[Transform3D] = []
	var hs := terrain.half_size - 30.0
	for attempt in 60:
		if boats.size() >= 12:
			break
		var p := Vector3(rng.randf_range(-hs, hs), 0.0, rng.randf_range(-hs, hs))
		if terrain.height_v(p) > -3.5:
			continue
		var ok := true
		for s in samples:
			if Vector2(s.x - p.x, s.z - p.z).length() < 22.0:
				ok = false
				break
		if ok:
			boats.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
	var no_colors: Array[Color] = []
	_multimesh(Models.sailboat(), boats, no_colors, "Sailboats")


func _build_route_overlay() -> void:
	var mb := MeshBuilder.new()
	var col := Color(1, 1, 1, 0.85)
	for r in map.routes:
		var s := 14.0
		while s < r.length - 16.0:
			var a := r.curve.sample_baked(s)
			var b := r.curve.sample_baked(s + 2.6)
			var lat := (b - a).normalized().cross(Vector3.UP) * 0.35
			a.y = 0.55
			b.y = 0.55
			mb.quad(a - lat, a + lat, b + lat, b - lat, col, Vector3.UP)
			s += 5.5
	route_overlay = _add_mesh(mb.commit(Models.unshaded_material()), "RouteOverlay", false)
