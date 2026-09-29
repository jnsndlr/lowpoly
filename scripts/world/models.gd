class_name Models
extends RefCounted
## Procedural low-poly meshes, cached so every instance shares geometry.

const GLASS := Color(0.16, 0.22, 0.27)
const WSF_GREEN := Color(0.07, 0.36, 0.25)
const WHITE := Color(0.94, 0.95, 0.94)
const HULL_DARK := Color(0.13, 0.14, 0.16)
const WOOD := Color(0.33, 0.26, 0.2)
const CAR_COLORS := [Color(0.75, 0.16, 0.14), Color(0.16, 0.32, 0.62), Color(0.92, 0.92, 0.9),
	Color(0.62, 0.64, 0.66), Color(0.12, 0.12, 0.14), Color(0.9, 0.72, 0.2), Color(0.2, 0.45, 0.3),
	Color(0.85, 0.4, 0.15), Color(0.2, 0.55, 0.6)]

static var _vc_mat: StandardMaterial3D
static var _cache := {}


static func vc_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.92
	return _vc_mat


static func unshaded_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _cached(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


static func pine_tree() -> ArrayMesh:
	return _cached("pine", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3(0, -0.4, 0), 0.28, 0.2, 1.6, 5, Color(0.36, 0.25, 0.17))
		mb.cylinder(Vector3(0, 0.9, 0), 1.6, 0.0, 2.4, 6, Color(0.16, 0.34, 0.19), Color(-1, 0, 0), 0.3)
		mb.cylinder(Vector3(0, 2.2, 0), 1.25, 0.0, 2.1, 6, Color(0.19, 0.39, 0.21), Color(-1, 0, 0), 0.8)
		mb.cylinder(Vector3(0, 3.4, 0), 0.85, 0.0, 1.8, 6, Color(0.22, 0.44, 0.23), Color(-1, 0, 0), 0.1)
		return mb.commit())


static func round_tree() -> ArrayMesh:
	return _cached("round", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3(0, -0.4, 0), 0.26, 0.2, 1.8, 5, Color(0.38, 0.27, 0.18))
		var c := Color(0.3, 0.5, 0.2)
		mb.cylinder(Vector3(0, 1.2, 0), 0.9, 1.5, 0.9, 7, c)
		mb.cylinder(Vector3(0, 2.1, 0), 1.5, 0.6, 1.2, 7, c.lightened(0.08))
		return mb.commit())


static func rock() -> ArrayMesh:
	return _cached("rock", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3(0, -0.6, 0), 1.0, 0.55, 1.4, 5, Color(0.5, 0.48, 0.45), Color(0.58, 0.56, 0.52), 0.4)
		mb.cylinder(Vector3(0.6, -0.5, 0.3), 0.6, 0.25, 0.9, 5, Color(0.45, 0.43, 0.41), Color(-1, 0, 0), 1.1)
		return mb.commit())


static func house(wall: Color, roof: Color, stories: int) -> ArrayMesh:
	var key := "house_%s_%s_%d" % [wall.to_html(), roof.to_html(), stories]
	return _cached(key, func():
		var mb := MeshBuilder.new()
		var wh := 2.0 if stories == 1 else 3.4
		# Body extends below ground so houses on slopes never float.
		mb.box(Vector3(0, (wh - 1.2) * 0.5, 0), Vector3(2.8, wh + 1.2, 3.4), wall)
		mb.box(Vector3(0.6, 0.6, 1.71), Vector3(0.6, 1.2, 0.05), Color(0.35, 0.24, 0.18))
		mb.box(Vector3(-0.6, wh * 0.55, 1.71), Vector3(0.8, 0.6, 0.05), GLASS)
		mb.box(Vector3(1.41, wh * 0.55, 0.0), Vector3(0.05, 0.6, 1.2), GLASS)
		mb.box(Vector3(-1.41, wh * 0.55, 0.0), Vector3(0.05, 0.6, 1.2), GLASS)
		var y0 := wh
		var y1 := wh + 1.4
		var hx := 1.65
		var hz := 1.95
		var l0 := Vector3(-hx, y0, -hz)
		var l1 := Vector3(-hx, y0, hz)
		var r0 := Vector3(hx, y0, -hz)
		var r1 := Vector3(hx, y0, hz)
		var t0 := Vector3(0, y1, -hz)
		var t1 := Vector3(0, y1, hz)
		mb.quad(l0, l1, t1, t0, roof, Vector3(-1, 1, 0))
		mb.quad(r0, t0, t1, r1, roof, Vector3(1, 1, 0))
		mb.quad(l0, r0, r1, l1, roof.darkened(0.4), Vector3.DOWN)
		mb.tri(Vector3(-1.4, y0, 1.7), Vector3(1.4, y0, 1.7), Vector3(0, y1 - 0.2, 1.7), wall, Vector3.BACK)
		mb.tri(Vector3(-1.4, y0, -1.7), Vector3(1.4, y0, -1.7), Vector3(0, y1 - 0.2, -1.7), wall, Vector3.FORWARD)
		mb.box(Vector3(0.8, y1 - 0.2, -0.7), Vector3(0.45, 1.2, 0.45), Color(0.55, 0.3, 0.24))
		return mb.commit())


static func block(wall: Color) -> ArrayMesh:
	return _cached("block_" + wall.to_html(), func():
		var mb := MeshBuilder.new()
		var h := 6.6
		mb.box(Vector3(0, (h - 1.2) * 0.5, 0), Vector3(4.4, h + 1.2, 5.0), wall)
		for level in 3:
			var y := 1.3 + level * 2.1
			mb.box(Vector3(0, y, 0), Vector3(4.5, 0.7, 4.2), GLASS)
			mb.box(Vector3(0, y, 0), Vector3(3.6, 0.7, 5.1), GLASS)
		mb.box(Vector3(0, h + 0.15, 0), Vector3(4.6, 0.3, 5.2), Color(0.3, 0.31, 0.33))
		mb.box(Vector3(0.8, h + 0.6, -0.8), Vector3(1.2, 0.7, 1.2), Color(0.6, 0.6, 0.6))
		return mb.commit())


static func car(color_index: int) -> ArrayMesh:
	return _cached("car_%d" % color_index, func():
		var col: Color = CAR_COLORS[color_index % CAR_COLORS.size()]
		var mb := MeshBuilder.new()
		mb.box(Vector3(0, 0.44, 0), Vector3(1.0, 0.5, 2.0), col)
		mb.box(Vector3(0, 0.86, -0.12), Vector3(0.84, 0.36, 1.05), col.lightened(0.05))
		mb.box(Vector3(0, 0.86, -0.12), Vector3(0.86, 0.24, 0.95), GLASS)
		mb.box(Vector3(0, 0.86, -0.12), Vector3(0.7, 0.24, 1.07), GLASS)
		for x: float in [-0.46, 0.46]:
			for z: float in [-0.62, 0.62]:
				mb.box(Vector3(x, 0.2, z), Vector3(0.16, 0.36, 0.42), Color(0.08, 0.08, 0.08))
		return mb.commit())


static func truck(color_index: int) -> ArrayMesh:
	return _cached("truck_%d" % color_index, func():
		var col: Color = CAR_COLORS[color_index % CAR_COLORS.size()]
		var mb := MeshBuilder.new()
		mb.box(Vector3(0, 0.7, 0.72), Vector3(1.1, 1.0, 0.8), col)
		mb.box(Vector3(0, 0.9, 1.1), Vector3(0.95, 0.4, 0.06), GLASS)
		mb.box(Vector3(0, 0.95, -0.42), Vector3(1.15, 1.3, 1.5), Color(0.9, 0.9, 0.88))
		for x: float in [-0.5, 0.5]:
			for z: float in [-0.8, 0.75]:
				mb.box(Vector3(x, 0.2, z), Vector3(0.16, 0.38, 0.44), Color(0.08, 0.08, 0.08))
		return mb.commit())


## Double-ended car ferry, 30 long. +Z and -Z ends are identical; car deck top at DECK_Y.
static func ferry() -> ArrayMesh:
	return _cached("ferry", func():
		var mb := MeshBuilder.new()
		var hull := PackedVector2Array([Vector2(-4.2, -12), Vector2(-2.6, -15), Vector2(2.6, -15), Vector2(4.2, -12),
			Vector2(4.2, 12), Vector2(2.6, 15), Vector2(-2.6, 15), Vector2(-4.2, 12)])
		mb.extrude(hull, -1.4, 0.15, HULL_DARK, Color(0, 0, 0, 0), 0.8)
		mb.extrude(hull, 0.15, 0.55, WSF_GREEN, Color(0, 0, 0, 0))
		mb.extrude(hull, 0.55, 0.95, WHITE, Color(0.42, 0.44, 0.47))
		mb.box(Vector3(0, 1.0, 0), Vector3(7.8, 0.1, 24.0), Color(0.45, 0.47, 0.5))
		# Car deck side walls with an open gallery above.
		for x: float in [-4.05, 4.05]:
			mb.box(Vector3(x, 1.7, 0), Vector3(0.3, 1.3, 21.0), WHITE)
			for z in range(-9, 10, 3):
				mb.box(Vector3(x, 2.8, z), Vector3(0.3, 1.0, 0.4), WHITE)
		# Passenger deck
		mb.box(Vector3(0, 3.35, 0), Vector3(8.75, 0.3, 20.2), WSF_GREEN)
		mb.box(Vector3(0, 4.3, 0), Vector3(8.6, 1.6, 20.0), WHITE)
		mb.box(Vector3(0, 4.4, 0), Vector3(8.7, 0.6, 18.4), GLASS)
		# Sun deck and upper cabin
		mb.box(Vector3(0, 5.7, 0), Vector3(6.4, 1.2, 12.0), WHITE)
		mb.box(Vector3(0, 5.8, 0), Vector3(6.5, 0.45, 10.6), GLASS)
		# Wheelhouses at both ends
		for z: float in [-7.4, 7.4]:
			mb.box(Vector3(0, 6.85, z), Vector3(4.2, 1.1, 2.4), WHITE)
			mb.box(Vector3(0, 6.95, z), Vector3(4.3, 0.45, 2.5), GLASS)
			mb.box(Vector3(0, 8.3, z), Vector3(0.15, 1.8, 0.15), WHITE)
		# Funnel
		mb.box(Vector3(0, 7.4, 0), Vector3(1.6, 2.2, 2.6), WHITE)
		mb.box(Vector3(0, 8.35, 0), Vector3(1.65, 0.35, 2.65), WSF_GREEN)
		mb.box(Vector3(0, 8.8, 0), Vector3(1.7, 0.5, 2.7), Color(0.1, 0.1, 0.1))
		# Lifeboats
		for x: float in [-3.5, 3.5]:
			for z: float in [-3.2, 3.2]:
				mb.box(Vector3(x, 6.5, z), Vector3(0.8, 0.5, 2.2), Color(0.95, 0.45, 0.12))
		return mb.commit())


## Foam trail behind a ferry, pointing towards -Z from the stern.
static func wake() -> ArrayMesh:
	return _cached("wake", func():
		var mb := MeshBuilder.new()
		var near := Color(1, 1, 1, 0.3)
		var far := Color(1, 1, 1, 0.0)
		var z0 := -13.5
		var z1 := -50.0
		var a := Vector3(-3.0, 0.3, z0)
		var b := Vector3(3.0, 0.3, z0)
		var c := Vector3(5.5, 0.3, z1)
		var d := Vector3(-5.5, 0.3, z1)
		mb.tri3(a, b, c, near, near, far, Vector3.UP)
		mb.tri3(a, c, d, near, far, far, Vector3.UP)
		# Kelvin wake arms
		for s: float in [-1.0, 1.0]:
			var p0 := Vector3(3.8 * s, 0.3, -11.0)
			var p1 := Vector3(15.0 * s, 0.3, -40.0)
			var p2 := Vector3(13.8 * s, 0.3, -40.5)
			mb.tri3(p0, p1, p2, Color(1, 1, 1, 0.3), far, far, Vector3.UP)
		return mb.commit(null))


static func sailboat() -> ArrayMesh:
	return _cached("sailboat", func():
		var mb := MeshBuilder.new()
		var hull := PackedVector2Array([Vector2(-0.6, -1.6), Vector2(0.6, -1.6), Vector2(0.65, 0.6), Vector2(0.0, 2.0), Vector2(-0.65, 0.6)])
		mb.extrude(hull, -0.3, 0.35, WHITE, Color(0.75, 0.62, 0.45), 0.7)
		mb.box(Vector3(0, 2.3, 0.3), Vector3(0.08, 4.0, 0.08), Color(0.8, 0.8, 0.8))
		var a := Vector3(0, 0.7, 0.2)
		var b := Vector3(0, 4.2, 0.2)
		var c := Vector3(0, 0.7, -1.4)
		mb.tri(a, b, c, Color(0.98, 0.98, 0.96), Vector3.RIGHT)
		mb.tri(a, b, c, Color(0.98, 0.98, 0.96), Vector3.LEFT)
		mb.tri(Vector3(0, 3.6, 0.35), Vector3(0, 0.8, 0.4), Vector3(0, 0.8, 1.7), Color(0.95, 0.95, 0.9), Vector3.RIGHT)
		mb.tri(Vector3(0, 3.6, 0.35), Vector3(0, 0.8, 0.4), Vector3(0, 0.8, 1.7), Color(0.95, 0.95, 0.9), Vector3.LEFT)
		return mb.commit())


static func add_lighthouse(mb: MeshBuilder, base: Vector3) -> void:
	mb.cylinder(base + Vector3(0, -1.0, 0), 1.5, 1.15, 4.0, 8, WHITE)
	mb.cylinder(base + Vector3(0, 3.0, 0), 1.15, 1.0, 1.6, 8, Color(0.75, 0.17, 0.14))
	mb.cylinder(base + Vector3(0, 4.6, 0), 1.0, 0.9, 2.2, 8, WHITE)
	mb.cylinder(base + Vector3(0, 6.8, 0), 1.35, 1.35, 0.25, 8, Color(0.2, 0.2, 0.2))
	mb.cylinder(base + Vector3(0, 7.05, 0), 0.65, 0.65, 0.9, 8, Color(0.95, 0.9, 0.6))
	mb.cylinder(base + Vector3(0, 7.95, 0), 0.85, 0.0, 1.0, 8, Color(0.75, 0.17, 0.14))
	mb.box(base + Vector3(2.6, 0.2, 0.6), Vector3(2.4, 2.4, 3.0), WHITE)
	mb.box(base + Vector3(2.6, 1.55, 0.6), Vector3(2.6, 0.3, 3.2), Color(0.75, 0.17, 0.14))


static func add_buoy(mb: MeshBuilder, base: Vector3, col: Color) -> void:
	mb.cylinder(base + Vector3(0, -0.5, 0), 0.5, 0.45, 1.3, 6, col)
	mb.cylinder(base + Vector3(0, 0.8, 0), 0.3, 0.0, 0.7, 6, col.darkened(0.2))
