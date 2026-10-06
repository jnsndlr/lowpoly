class_name WorldBuilder
extends RefCounted
## Turns MapData + Terrain into renderable nodes: terrain, water, terminals, roads,
## towns, forests, rocks, marinas, the route overlay and all of their night lights.
## Pure presentation — no sim state.

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
# Scale of the caged lamps on the ramp lift towers.
const LIFT_LAMP := 1.6
# Scale of the 360° lanterns on top of the lift and on the dolphins.
const LIFT_LANTERN := 1.3
const DOLPHIN_LANTERN := 1.3
# Side (m) of the tiles that trees, rocks and houses are batched in for culling.
const MULTIMESH_TILE := 64.0

var map: MapData
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var root: Node3D
var route_overlay: MeshInstance3D
var water_material: ShaderMaterial
var night_lights: MeshInstance3D
var glows := GlowBuilder.new()
## Places seagulls can sit (where the feet go, in world space).
var gull_perches: Array[Seagulls.Perch] = []
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
	_build_marinas()
	_build_quays()
	_build_roads()
	_build_towns()
	_build_lighthouses()
	_build_vegetation()
	_build_route_overlay()
	night_lights = _add_mesh(glows.commit(), "NightLights", false)
	night_lights.visible = false
	return root


func _add_mesh(mesh: Mesh, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = node_name
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## Instances are split into MULTIMESH_TILE-sized tiles, one MultiMesh each, so the
## camera and every shadow cascade can cull the ones out of view (a single MultiMesh
## covering the map is drawn whole, everywhere).
func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], node_name: String) -> void:
	if xforms.is_empty():
		return
	var tiles := {}
	for i in xforms.size():
		var o := xforms[i].origin
		var key := Vector2i(floori(o.x / MULTIMESH_TILE), floori(o.z / MULTIMESH_TILE))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	var group := Node3D.new()
	group.name = node_name
	root.add_child(group)
	for key: Vector2i in tiles:
		var idx: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not colors.is_empty()
		mm.mesh = mesh
		mm.instance_count = idx.size()
		for j in idx.size():
			mm.set_instance_transform(j, xforms[idx[j]])
			if mm.use_colors:
				mm.set_instance_color(j, colors[idx[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "%s_%d_%d" % [node_name, key.x, key.y]
		group.add_child(mmi)


# --- Blocking grid so props don't overlap roads, lots and houses -------------------

func _block(p: Vector3, radius: float) -> void:
	var r := ceili(radius / 2.0)
	var cx := floori(p.x / 2.0)
	var cz := floori(p.z / 2.0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_blocked[Vector2i(cx + dx, cz + dz)] = true


## A perch along a → b, `spread` either side of it (see Seagulls.Perch).
func _perch(a: Vector3, b: Vector3, spread: float, kind: int) -> void:
	gull_perches.append(Seagulls.Perch.new(a, b, spread, kind))


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
		glows.xform = mb.xform
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
			_build_slip(mb, isl.slip_offset(i), i > 0)

		# Terminal building beside the lot
		var bv := hw + 5.0
		mb.box(Vector3(bv, ly + 1.2, -12.0), Vector3(7.0, 3.4, 12.0), Color(0.9, 0.9, 0.87))
		mb.box(Vector3(bv, ly + 1.6, -12.0), Vector3(7.1, 0.9, 10.5), Models.WINDOW_LIT)
		mb.box(Vector3(bv, ly + 3.1, -12.0), Vector3(7.8, 0.4, 12.8), Models.WSF_GREEN)
		mb.box(Vector3(bv - 3.9, ly + 3.4, -6.0), Vector3(0.12, 5.0, 0.12), Color(0.8, 0.8, 0.8))
		mb.box(Vector3(bv - 3.9, ly + 5.6, -5.55), Vector3(0.05, 0.6, 0.9), Models.WSF_GREEN)
		_perch(mb.xform * Vector3(bv, ly + 3.3, -17.6), mb.xform * Vector3(bv, ly + 3.3, -6.4), 3.3, Seagulls.Kind.ROOF)

		# Toll plaza on the approach road
		var tu := Layout.LOT_BACK - 3.0
		for v: float in [-2.7, 2.7]:
			mb.box(Vector3(v, ly + 0.4, tu), Vector3(1.1, 2.6, 1.8), Color(0.92, 0.92, 0.9))
			mb.box(Vector3(v, ly + 0.9, tu), Vector3(1.15, 0.6, 1.3), Models.WINDOW_LIT)
			mb.box(Vector3(v * 1.45, ly + 1.1, tu), Vector3(0.3, 4.0, 0.3), Color(0.85, 0.85, 0.85))
		mb.box(Vector3(0, ly + 3.25, tu), Vector3(8.6, 0.35, 3.4), Models.WSF_GREEN)
		for v: float in [-2.7, 0.0, 2.7]:
			mb.box(Vector3(v, ly + 3.06, tu), Vector3(0.7, 0.04, 0.7), Models.lamp_glass(GlowBuilder.LED))
			glows.glow(Vector3(v, ly + 3.0, tu), GlowBuilder.LED, 0.16, 4.0, false, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
		glows.pool(Vector3(0, ly + 0.05, tu), GlowBuilder.SODIUM, 5.5, 0.3)
		glows.glow(Vector3(bv - 3.9, ly + 5.6, -5.55), GlowBuilder.GREEN, 0.3, 2.5)
		glows.pool(Vector3(bv - 4.5, ly + 0.05, -12.0), GlowBuilder.WARM, 4.5, 0.3)

		# Light poles
		for v: float in [-hw + 0.4, hw - 0.4]:
			for pu: float in [Layout.LOT_FRONT - 1.0, Layout.LOT_BACK + 1.0]:
				mb.box(Vector3(v, ly + 2.5, pu), Vector3(0.18, 5.0, 0.18), Color(0.35, 0.36, 0.38))
				mb.box(Vector3(v, ly + 5.0, pu), Vector3(0.6, 0.18, 0.6), Color(0.95, 0.95, 0.8))
				mb.box(Vector3(v, ly + 4.87, pu), Vector3(0.48, 0.08, 0.48), Models.lamp_glass(GlowBuilder.SODIUM))
				glows.glow(Vector3(v, ly + 4.85, pu), GlowBuilder.SODIUM, 0.3, 6.0, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
				glows.pool(Vector3(v * 0.7, ly + 0.05, pu), GlowBuilder.SODIUM, 8.0, 0.22)
				var top := mb.xform * Vector3(v, ly + 5.09, pu)
				_perch(top, top, 0.0, Seagulls.Kind.LAMP)

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


## `shared_dolphin`: the slip before this one already put a dolphin where this
## slip's port-side one would go (they're SLIP_SPACING apart), so don't double it.
func _build_slip(mb: MeshBuilder, v: float, shared_dolphin: bool) -> void:
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
	# Steady red 360° light on top of the lift, for ferries lining up at night.
	var top := Vector3(v, 5.65, pe - 1.0)
	Models.add_cage_lantern(mb, top, GlowBuilder.RED, LIFT_LANTERN)
	glows.glow(Models.cage_lantern_glow_at(top, LIFT_LANTERN), GlowBuilder.RED, 0.2, 7.0, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
	# Along the lift's cross beam, either side of the lantern.
	for side: float in [-1.0, 1.0]:
		_perch(mb.xform * Vector3(v + side * 0.45, 5.65, pe - 1.0), mb.xform * Vector3(v + side * 2.9, 5.65, pe - 1.0),
			0.0, Seagulls.Kind.LIFT)
	for side: float in [-1.0, 1.0]:
		mb.box(Vector3(v + side * 4.95, 0.3, pe + 5.0), Vector3(0.9, 4.0, 9.0), Models.WOOD)
		var mark := GlowBuilder.GREEN if side < 0 else GlowBuilder.RED
		# Dolphin, with a lantern on its cap.
		if not (shared_dolphin and side < 0):
			var dolphin := Vector3(v + side * 5.7, -2.0, pe + 21.0)
			mb.cylinder(dolphin, 1.0, 0.85, 4.6, 7, Models.WOOD, Color(0.85, 0.85, 0.8))
			var cap := dolphin + Vector3(0, 4.6, 0)
			Models.add_cage_lantern(mb, cap, mark, DOLPHIN_LANTERN)
			glows.glow(Models.cage_lantern_glow_at(cap, DOLPHIN_LANTERN), mark, 0.14, 3.5, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
			for dz: float in [-0.55, 0.55]:
				var seat := mb.xform * (cap + Vector3(0, 0, dz))
				_perch(seat, seat, 0.0, Seagulls.Kind.DOLPHIN)
		# Channel buoy, flashing.
		var buoy := Vector3(v + side * 8.0, 0.0, pe + 44.0)
		var phase := Models.blink_phase_at(mb.xform * buoy)
		Models.add_buoy(mb, buoy, Color(0.2, 0.55, 0.3) if side < 0 else Color(0.8, 0.2, 0.15), mark, phase)
		glows.glow(Models.buoy_glow_at(buoy), mark, 0.22, 7.0, true, Models.blink_of(phase), Vector3.ZERO, Models.LAMP_ON_AT)
		# A caged lamp on the inside of each lift tower, lighting the ramp.
		var lamp := Vector3(v + side * 2.65, 4.6, pe - 1.0)
		var out := Vector3(-side, 0, 0)
		Models.add_bulkhead_lamp(mb, lamp, out, GlowBuilder.WARM, LIFT_LAMP)
		glows.glow(Models.bulkhead_glow_at(lamp, out, LIFT_LAMP), GlowBuilder.WARM,
			Models.bulkhead_glow_size(LIFT_LAMP), 5.0, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
	glows.pool(Vector3(v, ly + 0.05, pe - 3.0), GlowBuilder.SODIUM, 3.5, 0.3)


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
			_street_lamps(mb, line)
	_add_mesh(mb.commit(), "Roads", false)


## Sodium lamps every LAMP_GAP along a road, alternating sides.
func _street_lamps(mb: MeshBuilder, line: PackedVector3Array) -> void:
	const LAMP_GAP := 16.0
	glows.xform = Transform3D.IDENTITY
	var next := LAMP_GAP * 0.5
	var walked := 0.0
	var side := 1.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var lat := (b - a).cross(Vector3.UP)
		lat.y = 0.0
		var seg := Vector3(b.x - a.x, 0.0, b.z - a.z).length()
		if seg < 0.01:
			continue
		lat = lat.normalized()
		while next <= walked + seg:
			var p := a.lerp(b, (next - walked) / seg) + lat * 2.2 * side
			mb.box(p + Vector3(0, 1.7, 0), Vector3(0.12, 3.8, 0.12), Color(0.3, 0.31, 0.33))
			mb.box(p + Vector3(0, 3.6, 0), Vector3(0.4, 0.14, 0.4), Color(0.25, 0.26, 0.28))
			mb.box(p + Vector3(0, 3.5, 0), Vector3(0.3, 0.07, 0.3), Models.lamp_glass(GlowBuilder.SODIUM))
			glows.glow(p + Vector3(0, 3.45, 0), GlowBuilder.SODIUM, 0.22, 5.0, p.y < 4.0, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
			glows.pool(p + Vector3(0, 0.12, 0) - lat * 1.2 * side, GlowBuilder.SODIUM, 5.0, 0.22)
			_perch(p + Vector3(0, 3.67, 0), p + Vector3(0, 3.67, 0), 0.0, Seagulls.Kind.LAMP)
			side = -side
			next += LAMP_GAP
		walked += seg


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
				var xf := Transform3D(basis, Vector3(p.x, hmin - 0.05, p.z))
				bucket.append(xf)
				_porch_light(xf, vi >= 10, h < 5.0)
				_block(p, 2.6)
	var no_colors: Array[Color] = []
	for i in variants.size():
		var xforms: Array[Transform3D] = per_variant[i]
		_multimesh(variants[i], xforms, no_colors, "Houses%d" % i)


## A lamp by the door and the light it throws on the path; waterfront ones are
## reflected in the water.
func _porch_light(xf: Transform3D, block: bool, waterfront: bool) -> void:
	glows.xform = xf
	# In the fixture Models.house() / block() put by the door.
	var lamp := Models.BLOCK_LAMP if block else Models.HOUSE_LAMP
	var s := Models.BLOCK_LAMP_SCALE if block else Models.HOUSE_LAMP_SCALE
	glows.glow(Models.bulkhead_glow_at(lamp, Vector3.BACK, s), GlowBuilder.WARM, Models.bulkhead_glow_size(s),
		4.0 if block else 3.5, waterfront, 0.0, Vector3(0, 0, 1), Models.LAMP_ON_AT)
	if block:
		glows.pool(Vector3(0.0, 0.2, 3.6), GlowBuilder.WARM, 2.6, 0.35)
	else:
		glows.pool(Vector3(0.6, 0.2, 2.5), GlowBuilder.WARM, 1.8, 0.3)


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
		for k in 3:
			var a := ang + PI + (k - 1) * 0.9
			var seat := Vector3(p.x + cos(a) * 1.1, h + 6.95, p.z + sin(a) * 1.1)
			_perch(seat, seat, 0.0, Seagulls.Kind.LIGHTHOUSE)
		var lamp := Vector3(p.x, h + 7.4, p.z)
		var beacon := Color(1.0, 0.92, 0.75)
		glows.xform = Transform3D.IDENTITY
		glows.glow(lamp, beacon, 0.8, 9.0, true, 0.0, Vector3.ZERO, 0.0)
		glows.beam(lamp, beacon, 2.2, 75.0, 0.5, 0.3, _hash(p.x, p.z) * TAU)
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


## A wooden pier out to a T-head float with berths along its seaward face (the
## sailboats themselves are MarineTraffic's), a lamp at each end of the head.
func _build_marinas() -> void:
	var plank := Color(0.56, 0.46, 0.34)
	var float_col := Color(0.66, 0.6, 0.5)
	for m in map.marinas:
		var mb := MeshBuilder.new()
		mb.xform = m.xform()
		glows.xform = mb.xform
		var pe := Layout.MARINA_PIER_END
		var hu := Layout.MARINA_HEAD_U
		var hh := Layout.MARINA_HEAD_HALF
		mb.box(Vector3(0, 0.75, (pe - 4.0) * 0.5), Vector3(1.8, 0.25, pe + 4.0), plank)
		var u := -1.0
		while u < pe:
			for side: float in [-1.0, 1.0]:
				mb.box(Vector3(side * 1.0, -1.3, u), Vector3(0.28, 4.3, 0.28), Models.WOOD)
			u += 3.5
		# The T-head, a little lower, its pilings standing proud.
		mb.box(Vector3(0, 0.5, hu), Vector3(hh * 2.0, 0.3, 2.0), float_col)
		mb.box(Vector3(0, 0.36, hu + 1.02), Vector3(hh * 2.0, 0.12, 0.08), Color(0.25, 0.25, 0.26))
		for v: float in [-hh + 0.3, -1.5, 1.5, hh - 0.3]:
			mb.cylinder(Vector3(v, -2.0, hu - 1.2), 0.2, 0.18, 3.6, 6, Models.WOOD, Color(0.4, 0.33, 0.27))
		for b in Layout.MARINA_BERTHS:
			# A cleat for each berth.
			mb.box(Vector3(m.berth_v(b), 0.7, hu + 0.75), Vector3(0.35, 0.1, 0.12), Color(0.3, 0.3, 0.32))
		for side: float in [-1.0, 1.0]:
			var post := Vector3(side * (hh - 0.3), 0.65, hu)
			mb.box(post + Vector3(0, 0.8, 0), Vector3(0.1, 1.6, 0.1), Color(0.25, 0.26, 0.28))
			var lamp := post + Vector3(0, 1.6, 0)
			Models.add_lantern(mb, lamp, GlowBuilder.WARM, 0.9)
			glows.glow(Models.lantern_glow_at(lamp, 0.9), GlowBuilder.WARM, 0.16, 4.0, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
			glows.pool(Vector3(side * (hh - 1.2), 0.66, hu), GlowBuilder.WARM, 3.0, 0.25)
			var top := mb.xform * (lamp + Vector3(0, 0.36, 0))
			_perch(top, top, 0.0, Seagulls.Kind.LAMP)
		_add_mesh(mb.commit(), map.islands[m.island].name + " Marina")
		# Keep trees and houses off the pier's landing.
		var bu := -8.0
		while bu < 2.0:
			for bv: float in [-3.0, -1.5, 0.0, 1.5, 3.0]:
				_block(m.at(bu, bv), 1.0)
			bu += 1.5


## A timber jetty out to a wharf the boats lie alongside (the boats themselves
## are MarineTraffic's): bollards and tyre fenders along its face, and
## floodlights for working in the dark. A fish quay has a fish shed and stacked
## totes on it and a hoist over the water; the pilot station its pilot house,
## with a lookout and radar mast.
func _build_quays() -> void:
	var plank := Color(0.5, 0.42, 0.33)
	var cap := Color(0.6, 0.6, 0.57)
	var tyre := Color(0.1, 0.1, 0.11)
	var steel := Color(0.35, 0.36, 0.38)
	var r := RandomNumberGenerator.new()
	for q in map.wharves():
		var fish := q is MapData.FishQuay
		r.seed = map.map_seed * 13 + q.id + (0 if fish else 7919)
		var mb := MeshBuilder.new()
		mb.xform = q.xform()
		glows.xform = mb.xform
		var deck := 1.2
		var face := Layout.QUAY_FACE_U
		var back := Layout.QUAY_JETTY_END - 2.0
		var hh := Layout.QUAY_HALF
		# The jetty, on its pilings.
		mb.box(Vector3(0, deck - 0.15, (back - 2.0) * 0.5), Vector3(4.0, 0.3, back + 2.0), plank)
		var u := 0.0
		while u < back:
			for side: float in [-1.8, 1.8]:
				mb.box(Vector3(side, -1.6, u), Vector3(0.3, 5.4, 0.3), Models.WOOD)
			u += 3.0
		# The wharf: a heavy timber deck with a concrete cap along its face.
		var mid := (back + face) * 0.5
		mb.box(Vector3(0, deck - 0.2, mid), Vector3(hh * 2.0, 0.4, face - back), plank)
		mb.box(Vector3(0, deck + 0.02, face - 0.35), Vector3(hh * 2.0, 0.14, 0.7), cap)
		mb.box(Vector3(0, deck - 0.9, face - 0.08), Vector3(hh * 2.0, 1.2, 0.16), Models.WOOD)
		var v := -hh + 0.4
		while v <= hh - 0.3:
			mb.box(Vector3(v, -1.8, face - 0.2), Vector3(0.36, 5.6, 0.36), Models.WOOD)
			mb.box(Vector3(v, -1.6, back + 0.3), Vector3(0.32, 5.4, 0.32), Models.WOOD)
			v += 3.2
		# Tyre fenders hung along the face, and bollards for the boats' lines.
		v = -hh + 1.5
		while v < hh - 1.0:
			mb.box(Vector3(v, 0.3, face + 0.12), Vector3(0.75, 0.75, 0.26), tyre)
			mb.box(Vector3(v, 0.3, face + 0.26), Vector3(0.4, 0.4, 0.04), Color(0.03, 0.03, 0.03))
			v += 3.6 + r.randf() * 1.2
		var spread := (Layout.QUAY_BERTH_SPACING if fish else Layout.STATION_BERTH_SPACING) * 0.37
		for b in q.berths():
			for o: float in [-spread, 0.0, spread]:
				var bp := Vector3(q.berth_v(b) + o, deck + 0.09, face - 0.45)
				mb.cylinder(bp, 0.17, 0.15, 0.4, 8, Color(0.16, 0.17, 0.18))
				mb.cylinder(bp + Vector3(0, 0.4, 0), 0.24, 0.24, 0.07, 8, Color(0.16, 0.17, 0.18))
		if fish:
			_fish_quay_props(mb, q, r, deck, back, face, hh)
		else:
			_pilot_station_props(mb, q, r, deck, back, face, hh)
		# Floodlights on poles, lighting the wharf and the boats alongside (at the
		# pilot station, only at the end away from the pilot house).
		for fv: float in [-hh + 4.0, hh - 4.0]:
			if not fish and signf(fv) == -q.side:
				continue
			var pole := Vector3(fv, deck, back + 0.6)
			mb.box(pole + Vector3(0, 3.5, 0), Vector3(0.2, 7.0, 0.2), steel)
			mb.box(pole + Vector3(0, 7.0, 0.3), Vector3(0.9, 0.35, 0.5), Color(0.25, 0.26, 0.27))
			mb.box(pole + Vector3(0, 6.86, 0.42), Vector3(0.75, 0.08, 0.3), Models.lamp_glass(GlowBuilder.LED))
			glows.glow(pole + Vector3(0, 6.85, 0.45), GlowBuilder.LED, 0.32, 7.0, true, 0.0, Vector3(0, 0, 1), Models.LAMP_ON_AT)
			glows.pool(Vector3(fv * 0.85, deck + 0.05, (back + face) * 0.5 + 1.0), GlowBuilder.LED, 7.5, 0.22)
			var top := mb.xform * (pole + Vector3(0, 7.2, 0.3))
			_perch(top, top, 0.0, Seagulls.Kind.LAMP)
		_perch(mb.xform * Vector3(-hh + 1.0, deck + 0.16, face - 0.35), mb.xform * Vector3(hh - 1.0, deck + 0.16, face - 0.35),
			0.0, Seagulls.Kind.DOLPHIN)
		_add_mesh(mb.commit(), q.title(map).capitalize())
		# Keep trees and houses off the wharf and the jetty's landing.
		var bu := -10.0
		while bu < face:
			var half := hh + 1.5 if bu >= back - 1.0 else 4.5
			var bv := -half
			while bv <= half:
				_block(q.at(bu, bv), 1.0)
				bv += 1.5
			bu += 1.5


## The fish shed at one end, its big door onto the wharf, totes stacked about,
## and a hoist for landing the catch.
func _fish_quay_props(mb: MeshBuilder, q: MapData.Wharf, r: RandomNumberGenerator, deck: float, back: float,
		face: float, hh: float) -> void:
	var shed_wall := Color(0.6, 0.24, 0.19)
	var trim := Color(0.9, 0.89, 0.84)
	var totes := [Color(0.18, 0.38, 0.66), Color(0.9, 0.48, 0.14), Color(0.86, 0.86, 0.82)]
	# The fish shed at one end, its big door onto the wharf.
	var sv := -q.side * (hh - 8.0)
	var sz := Vector3(11.0, 3.0, 4.6)
	var sc := Vector3(sv, deck + sz.y * 0.5, back + sz.z * 0.5 + 0.3)
	mb.box(sc, sz, shed_wall)
	mb.box(sc + Vector3(0, -0.35, sz.z * 0.5 + 0.01), Vector3(3.2, 2.3, 0.04), shed_wall.darkened(0.45))
	for wv: float in [-3.8, 3.8]:
		mb.box(sc + Vector3(wv, 0.4, sz.z * 0.5 + 0.01), Vector3(1.0, 0.7, 0.04), Models.WINDOW)
	mb.box(sc + Vector3(0, sz.y * 0.5 - 0.06, 0), Vector3(sz.x + 0.1, 0.12, sz.z + 0.1), trim)
	var ry := deck + sz.y
	var rx := sz.x * 0.5 + 0.25
	var rz := sz.z * 0.5 + 0.35
	var roof := Color(0.3, 0.31, 0.33)
	var l0 := sc + Vector3(-rx, ry - sc.y, -rz)
	var l1 := sc + Vector3(rx, ry - sc.y, -rz)
	var f0 := sc + Vector3(-rx, ry - sc.y, rz)
	var f1 := sc + Vector3(rx, ry - sc.y, rz)
	var t0 := sc + Vector3(-rx, ry - sc.y + 1.5, 0)
	var t1 := sc + Vector3(rx, ry - sc.y + 1.5, 0)
	mb.quad(l0, t0, t1, l1, roof, Vector3(0, 1, -1))
	mb.quad(f0, f1, t1, t0, roof, Vector3(0, 1, 1))
	mb.quad(l0, l1, f1, f0, roof.darkened(0.4), Vector3.DOWN)
	for e: float in [-1.0, 1.0]:
		var ex := sc.x + e * sz.x * 0.5
		mb.tri(Vector3(ex, ry, sc.z - sz.z * 0.5), Vector3(ex, ry, sc.z + sz.z * 0.5),
			Vector3(ex, ry + 1.4, sc.z), shed_wall, Vector3(e, 0, 0))
	_perch(mb.xform * Vector3(sc.x - rx + 0.6, ry + 1.5, sc.z), mb.xform * Vector3(sc.x + rx - 0.6, ry + 1.5, sc.z), 0.0, Seagulls.Kind.ROOF)
	# Fish totes stacked about the wharf.
	for k in 9:
		var tv := r.randf_range(-hh + 3.0, hh - 3.0)
		if absf(tv - sv) < sz.x * 0.5 + 1.5:
			continue
		var tu := r.randf_range(back + 1.0, face - 2.2)
		var high := r.randi_range(1, 4)
		var col: Color = totes[r.randi_range(0, totes.size() - 1)]
		for t in high:
			mb.box(Vector3(tv, deck + 0.3 + t * 0.55, tu), Vector3(1.2, 0.52, 0.8), col.darkened(r.randf() * 0.15))
	# A hoist for landing the catch, its boom out over the berths.
	var hv := q.side * 2.0
	mb.box(Vector3(hv, deck + 2.6, face - 1.2), Vector3(0.35, 5.2, 0.35), Color(0.85, 0.72, 0.18))
	var saved := mb.xform
	mb.xform = saved * Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(hv, deck + 1.0, face - 1.2))
	mb.box(Vector3(0, 0, 3.0), Vector3(0.24, 0.24, 6.4), Color(0.85, 0.72, 0.18))
	mb.xform = saved
	mb.box(Vector3(hv, deck + 2.8, face + 4.0), Vector3(0.03, 1.4, 0.03), Color(0.2, 0.2, 0.2))
	var hook := mb.xform * Vector3(hv, deck + 5.2, face - 1.2)
	_perch(hook, hook, 0.0, Seagulls.Kind.LAMP)


## The pilot house at one end of the wharf (where the pilots wait between ships
## and the boats' crews keep watch), a lookout mast with the radar and a
## windsock, a liferaft and lifebuoys.
func _pilot_station_props(mb: MeshBuilder, q: MapData.Wharf, _r: RandomNumberGenerator, deck: float, back: float,
		face: float, hh: float) -> void:
	var wall := Color(0.92, 0.91, 0.87)
	var band := Color(0.86, 0.33, 0.1)
	var roof := Color(0.22, 0.24, 0.27)
	var sv := -q.side * (hh - 7.0)
	var sz := Vector3(9.0, 5.6, 4.8)
	var sc := Vector3(sv, deck + sz.y * 0.5, back + sz.z * 0.5 + 0.3)
	mb.box(sc, sz, wall)
	# An orange band at the eaves and round the ground floor, windows all round,
	# the upper floor's the watch room.
	mb.box(sc + Vector3(0, sz.y * 0.5 - 0.3, 0), Vector3(sz.x + 0.06, 0.6, sz.z + 0.06), band)
	mb.box(sc + Vector3(0, -sz.y * 0.5 + 0.25, 0), Vector3(sz.x + 0.06, 0.5, sz.z + 0.06), band.darkened(0.2))
	mb.box(sc + Vector3(0, 1.2, 0), Vector3(sz.x + 0.04, 1.1, sz.z - 0.8), Models.WINDOW_LIT)
	mb.box(sc + Vector3(0, 1.2, 0), Vector3(sz.x - 0.8, 1.1, sz.z + 0.04), Models.WINDOW_LIT)
	for wv: float in [-2.6, 2.6]:
		mb.box(sc + Vector3(wv, -1.2, sz.z * 0.5 + 0.01), Vector3(1.4, 0.9, 0.04), Models.WINDOW)
	mb.box(sc + Vector3(0, -1.75, sz.z * 0.5 + 0.01), Vector3(1.1, 2.1, 0.04), band.darkened(0.45))
	# A flat roof with a rail, the mast on it.
	var ry := deck + sz.y
	mb.box(Vector3(sc.x, ry + 0.08, sc.z), Vector3(sz.x + 0.5, 0.16, sz.z + 0.5), roof)
	for e: float in [-1.0, 1.0]:
		mb.box(Vector3(sc.x, ry + 0.6, sc.z + e * (sz.z * 0.5 + 0.2)), Vector3(sz.x + 0.4, 0.06, 0.06), wall)
		mb.box(Vector3(sc.x + e * (sz.x * 0.5 + 0.2), ry + 0.6, sc.z), Vector3(0.06, 0.06, sz.z + 0.4), wall)
	var mast := Vector3(sc.x + q.side * 2.5, ry, sc.z)
	mb.box(mast + Vector3(0, 3.0, 0), Vector3(0.2, 6.0, 0.2), wall)
	mb.box(mast + Vector3(0, 4.6, 0), Vector3(1.6, 0.08, 0.08), wall)
	mb.box(mast + Vector3(0, 5.3, 0), Vector3(0.3, 0.3, 0.3), roof)
	mb.box(mast + Vector3(0, 5.55, 0), Vector3(2.4, 0.12, 0.35), wall)
	Models.add_lantern(mb, mast + Vector3(0, 6.0, 0), GlowBuilder.RED, 0.9)
	glows.glow(Models.lantern_glow_at(mast + Vector3(0, 6.0, 0), 0.9), GlowBuilder.RED, 0.16, 5.0, true, 0.0, Vector3.ZERO, Models.LAMP_ON_AT)
	# The windsock, streaming off the yard.
	var sock := mast + Vector3(0.8, 4.6, 0)
	mb.box(sock + Vector3(0.45, -0.1, 0), Vector3(0.9, 0.3, 0.3), band)
	mb.box(sock + Vector3(1.1, -0.18, 0), Vector3(0.5, 0.2, 0.2), wall)
	var top := mb.xform * (mast + Vector3(0, 6.4, 0))
	_perch(top, top, 0.0, Seagulls.Kind.LAMP)
	_perch(mb.xform * Vector3(sc.x - sz.x * 0.5 + 0.5, ry + 0.2, sc.z), mb.xform * Vector3(sc.x + sz.x * 0.5 - 0.5, ry + 0.2, sc.z),
		0.0, Seagulls.Kind.ROOF)
	# A liferaft canister in its cradle and lifebuoys on posts along the face.
	var lr := Vector3(-sv * 0.35, deck + 0.4, back + 1.4)
	mb.box(lr, Vector3(1.6, 0.5, 0.9), Color(0.3, 0.32, 0.34))
	mb.cylinder(lr + Vector3(0, 0.25, 0), 0.4, 0.4, 0.5, 8, Color(0.95, 0.95, 0.93))
	for lv: float in [-hh * 0.5, hh * 0.5]:
		mb.box(Vector3(lv, deck + 0.6, face - 1.0), Vector3(0.12, 1.2, 0.12), Color(0.2, 0.2, 0.22))
		mb.box(Vector3(lv, deck + 1.0, face - 0.92), Vector3(0.7, 0.7, 0.1), band)
		mb.box(Vector3(lv, deck + 1.0, face - 0.9), Vector3(0.35, 0.35, 0.12), Color(0.2, 0.2, 0.22))


func _build_route_overlay() -> void:
	var mb := MeshBuilder.new()
	var col := Color(0.92, 0.96, 1.0, 0.1)
	for r in map.routes:
		var s := 14.0
		while s < r.length - 16.0:
			var a := r.curve.sample_baked(s)
			var b := r.curve.sample_baked(s + 2.4)
			var lat := (b - a).normalized().cross(Vector3.UP) * 0.25
			# High enough to clear the swell so waves don't swallow dashes.
			a.y = 0.8
			b.y = 0.8
			mb.quad(a - lat, a + lat, b + lat, b - lat, col, Vector3.UP)
			s += 5.5
	# Water is also transparent and both meshes sit centred on the origin, so depth
	# sorting between them flips with the camera. Force the overlay to draw after it.
	var mat := Models.unshaded_material()
	mat.render_priority = 5
	route_overlay = _add_mesh(mb.commit(mat), "RouteOverlay", false)
