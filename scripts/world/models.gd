class_name Models
extends RefCounted
## Procedural low-poly meshes, cached so every instance shares geometry.

const GLASS := Color(0.16, 0.22, 0.27)
# Glass that lights up at night (lit_vc.gdshader reads the alpha): WINDOW_LIT always,
# WINDOW for some rooms and not others.
const WINDOW_LIT := Color(0.16, 0.22, 0.27, 0.0)
const WINDOW := Color(0.16, 0.22, 0.27, 0.5)
const WSF_GREEN := Color(0.07, 0.36, 0.25)
const WHITE := Color(0.94, 0.95, 0.94)
const HULL_DARK := Color(0.13, 0.14, 0.16)
const WOOD := Color(0.33, 0.26, 0.2)
const BRASS := Color(0.72, 0.55, 0.24)
const LAMP_DARK := Color(0.12, 0.12, 0.13)
const CAR_COLORS := [Color(0.75, 0.16, 0.14), Color(0.16, 0.32, 0.62), Color(0.92, 0.92, 0.9),
	Color(0.62, 0.64, 0.66), Color(0.12, 0.12, 0.14), Color(0.9, 0.72, 0.2), Color(0.2, 0.45, 0.3),
	Color(0.85, 0.4, 0.15), Color(0.2, 0.55, 0.6)]

# Glass of a lamp fixture (lit_vc.gdshader reads the alpha): glows in its own colour
# at night, with the first lights.
const LAMP_GLASS_ALPHA := 0.15
# night_lights level the fixtures' glass comes on at; their glows match it.
const LAMP_ON_AT := 0.05
# Flashing lamp glass: alpha (BLINK_ALPHA0 + q) / 255 flashes with phase q / BLINK_STEPS,
# every BLINK_PERIOD seconds (lit_vc.gdshader's lamp_blink_period). Its glow gets the
# same phase through GlowBuilder's blink.
const BLINK_ALPHA0 := 180
const BLINK_STEPS := 64
const BLINK_PERIOD := 4.0
# Porch lamps (where on the front wall, and how big), shared with WorldBuilder's glows.
const HOUSE_LAMP := Vector3(1.1, 1.45, 1.7)
const HOUSE_LAMP_SCALE := 0.7
const BLOCK_LAMP := Vector3(0.0, 2.35, 2.5)
const BLOCK_LAMP_SCALE := 0.9
# Ferry lamps in the hull's frame: x of the gallery pillars' outer faces, their lamps'
# height and scale; mast tops over the wheelhouses; red / green sidelights.
const FERRY_GALLERY_X := 4.2
const FERRY_GALLERY_Y := 3.15
const FERRY_GALLERY_LAMP := 0.9
const FERRY_MAST_TOP := 9.2
const FERRY_LANTERN := 1.2
# Sidelights on the wheelhouse walls (x is the wall, z the wheelhouse centre).
const FERRY_SIDELIGHT := Vector3(2.15, 6.98, 7.4)
const FERRY_SIDELIGHT_SCALE := 1.3
# Sidelight lenses (lit_vc.gdshader reads the alpha): lit only at the end that's the
# bow on this crossing, set by the hull's nav_flip.
const NAV_GLASS_ALPHA := 0.3
const NAV_RED := Color(0.85, 0.1, 0.07, NAV_GLASS_ALPHA)
const NAV_GREEN := Color(0.1, 0.75, 0.3, NAV_GLASS_ALPHA)
# The sailboat's anchor light, on top of the mast.
const SAIL_MAST_TOP := Vector3(0, 4.3, 0.3)
const SAIL_LANTERN := 0.8
# Channel buoys' lanterns: height above the waterline and scale.
const BUOY_LAMP_Y := 1.65
const BUOY_LANTERN := 1.1

static var _vc_mat: ShaderMaterial
static var _cache := {}


static func vc_material() -> ShaderMaterial:
	if _vc_mat == null:
		_vc_mat = ShaderMaterial.new()
		_vc_mat.shader = load("res://shaders/lit_vc.gdshader")
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
		mb.cylinder(Vector3(0, 0.9, 0), 1.6, 0.0, 2.4, 6, Color(0.16, 0.34, 0.22), Color(-1, 0, 0), 0.3)
		mb.cylinder(Vector3(0, 2.2, 0), 1.25, 0.0, 2.1, 6, Color(0.25, 0.42, 0.2), Color(-1, 0, 0), 0.8)
		mb.cylinder(Vector3(0, 3.4, 0), 0.85, 0.0, 1.8, 6, Color(0.34, 0.5, 0.19), Color(-1, 0, 0), 0.1)
		return mb.commit())


static func round_tree() -> ArrayMesh:
	return _cached("round", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3(0, -0.4, 0), 0.26, 0.2, 1.8, 5, Color(0.38, 0.27, 0.18))
		var c := Color(0.4, 0.53, 0.19)
		mb.cylinder(Vector3(0, 1.2, 0), 0.9, 1.5, 0.9, 7, c)
		mb.cylinder(Vector3(0, 2.1, 0), 1.5, 0.6, 1.2, 7, c.lightened(0.08))
		return mb.commit())


static func rock() -> ArrayMesh:
	return _cached("rock", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3(0, -0.6, 0), 1.0, 0.55, 1.4, 5, Color(0.56, 0.47, 0.46), Color(0.68, 0.58, 0.52), 0.4)
		mb.cylinder(Vector3(0.6, -0.5, 0.3), 0.6, 0.25, 0.9, 5, Color(0.5, 0.42, 0.42), Color(-1, 0, 0), 1.1)
		return mb.commit())


static func house(wall: Color, roof: Color, stories: int) -> ArrayMesh:
	var key := "house_%s_%s_%d" % [wall.to_html(), roof.to_html(), stories]
	return _cached(key, func():
		var mb := MeshBuilder.new()
		var wh := 2.0 if stories == 1 else 3.4
		# Body extends below ground so houses on slopes never float.
		mb.box(Vector3(0, (wh - 1.2) * 0.5, 0), Vector3(2.8, wh + 1.2, 3.4), wall)
		mb.box(Vector3(0.6, 0.6, 1.71), Vector3(0.6, 1.2, 0.05), Color(0.35, 0.24, 0.18))
		mb.box(Vector3(-0.6, wh * 0.55, 1.71), Vector3(0.8, 0.6, 0.05), WINDOW)
		mb.box(Vector3(1.41, wh * 0.55, 0.0), Vector3(0.05, 0.6, 1.2), WINDOW)
		mb.box(Vector3(-1.41, wh * 0.55, 0.0), Vector3(0.05, 0.6, 1.2), WINDOW)
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
		add_bulkhead_lamp(mb, HOUSE_LAMP, Vector3.BACK, Color(1.0, 0.7, 0.4), HOUSE_LAMP_SCALE, LAMP_DARK)
		return mb.commit())


static func block(wall: Color) -> ArrayMesh:
	return _cached("block_" + wall.to_html(), func():
		var mb := MeshBuilder.new()
		var h := 6.6
		mb.box(Vector3(0, (h - 1.2) * 0.5, 0), Vector3(4.4, h + 1.2, 5.0), wall)
		for level in 3:
			var y := 1.3 + level * 2.1
			mb.box(Vector3(0, y, 0), Vector3(4.5, 0.7, 4.2), WINDOW)
			mb.box(Vector3(0, y, 0), Vector3(3.6, 0.7, 5.1), WINDOW)
		mb.box(Vector3(0, h + 0.15, 0), Vector3(4.6, 0.3, 5.2), Color(0.3, 0.31, 0.33))
		mb.box(Vector3(0.8, h + 0.6, -0.8), Vector3(1.2, 0.7, 1.2), Color(0.6, 0.6, 0.6))
		add_bulkhead_lamp(mb, BLOCK_LAMP, Vector3.BACK, Color(1.0, 0.7, 0.4), BLOCK_LAMP_SCALE, LAMP_DARK)
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
				add_bulkhead_lamp(mb, Vector3(signf(x) * FERRY_GALLERY_X, FERRY_GALLERY_Y, z), Vector3(signf(x), 0, 0),
					GlowBuilder.WARM, FERRY_GALLERY_LAMP)
		# Passenger deck
		mb.box(Vector3(0, 3.35, 0), Vector3(8.75, 0.3, 20.2), WSF_GREEN)
		mb.box(Vector3(0, 4.3, 0), Vector3(8.6, 1.6, 20.0), WHITE)
		mb.box(Vector3(0, 4.4, 0), Vector3(8.7, 0.6, 18.4), WINDOW_LIT)
		# Sun deck and upper cabin
		mb.box(Vector3(0, 5.7, 0), Vector3(6.4, 1.2, 12.0), WHITE)
		mb.box(Vector3(0, 5.8, 0), Vector3(6.5, 0.45, 10.6), WINDOW_LIT)
		# Wheelhouses at both ends
		for z: float in [-7.4, 7.4]:
			mb.box(Vector3(0, 6.85, z), Vector3(4.2, 1.1, 2.4), WHITE)
			mb.box(Vector3(0, 6.95, z), Vector3(4.3, 0.45, 2.5), WINDOW_LIT)
			mb.box(Vector3(0, 8.3, z), Vector3(0.15, 1.8, 0.15), WHITE)
			add_lantern(mb, Vector3(0, FERRY_MAST_TOP, z), GlowBuilder.LED, FERRY_LANTERN)
			for x: float in [-1.0, 1.0]:
				add_sidelight(mb, x, signf(z))
		# Funnel
		mb.box(Vector3(0, 7.4, 0), Vector3(1.6, 2.2, 2.6), WHITE)
		mb.box(Vector3(0, 8.35, 0), Vector3(1.65, 0.35, 2.65), WSF_GREEN)
		mb.box(Vector3(0, 8.8, 0), Vector3(1.7, 0.5, 2.7), Color(0.1, 0.1, 0.1))
		# Lifeboats
		for x: float in [-3.5, 3.5]:
			for z: float in [-3.2, 3.2]:
				mb.box(Vector3(x, 6.5, z), Vector3(0.8, 0.5, 2.2), Color(0.95, 0.45, 0.12))
		return mb.commit())


## Head and tail lights for every car and truck (+Z is the front), plus the cone
## they throw down the road. Drawn per vehicle by NightLights' multimesh.
static func car_lights() -> ArrayMesh:
	return _cached("car_lights", func():
		var gb := GlowBuilder.new()
		for x: float in [-0.32, 0.32]:
			gb.glow(Vector3(x, 0.5, 1.08), GlowBuilder.HEADLIGHT, 0.14, 7.0, false, 0.0, Vector3.BACK, 0.0)
			gb.glow(Vector3(x * 1.1, 0.55, -1.14), GlowBuilder.TAIL, 0.11, 5.0, false, 0.0, Vector3.FORWARD, 0.0)
		gb.cone(Vector3(0, 0.1, 1.4), Vector3.BACK, 9.0, 2.2, GlowBuilder.HEADLIGHT, 0.4)
		return gb.commit())


## Ferry lights in the hull's frame: masthead lights over both wheelhouses, red /
## green sidelights, a row of lamps along each car-deck gallery, and the lit cabin
## windows' reflections on the water.
static func ferry_lights() -> ArrayMesh:
	return _cached("ferry_lights", func():
		var gb := GlowBuilder.new()
		for z: float in [-7.4, 7.4]:
			gb.glow(lantern_glow_at(Vector3(0, FERRY_MAST_TOP, z), FERRY_LANTERN), GlowBuilder.LED, 0.3, 9.0, true, 0.0, Vector3.ZERO, 0.0)
			for x: float in [-1.0, 1.0]:
				gb.nav(sidelight_glow_at(x, signf(z)), 0.22, 7.0, Vector3(x, 0, signf(z) * 0.8))
		for x: float in [-1.0, 1.0]:
			var out := Vector3(x, 0, 0)
			for z in range(-9, 10, 3):
				var lamp := Vector3(x * FERRY_GALLERY_X, FERRY_GALLERY_Y, z)
				gb.glow(bulkhead_glow_at(lamp, out, FERRY_GALLERY_LAMP), GlowBuilder.WARM, bulkhead_glow_size(FERRY_GALLERY_LAMP),
					4.0, true, 0.0, out, 0.0)
		# Window rows (Models.WINDOW_LIT): passenger deck, sun deck, and the ends.
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-4.35, 4.35]:
			for i in 13:
				gb.reflection(Vector3(x, 4.4, -9.0 + i * 1.5), window, 0.3, 2.2, Vector3(signf(x), 0, 0))
		for x: float in [-3.25, 3.25]:
			for i in 6:
				gb.reflection(Vector3(x, 5.8, -5.0 + i * 2.0), window, 0.22, 1.6, Vector3(signf(x), 0, 0))
		for z: float in [-9.2, 9.2]:
			for i in 5:
				gb.reflection(Vector3(-3.0 + i * 1.5, 4.4, z), window, 0.3, 2.2, Vector3(0, 0, signf(z)))
		return gb.commit())


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
		add_lantern(mb, SAIL_MAST_TOP, GlowBuilder.LED, SAIL_LANTERN)
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


## A channel buoy with its flashing lantern on a short post at the top (see
## buoy_glow_at for where its glow goes).
static func add_buoy(mb: MeshBuilder, base: Vector3, col: Color, light: Color, blink_phase: float) -> void:
	mb.cylinder(base + Vector3(0, -0.5, 0), 0.5, 0.45, 1.3, 6, col)
	mb.cylinder(base + Vector3(0, 0.8, 0), 0.3, 0.0, 0.7, 6, col.darkened(0.2))
	mb.cylinder(base + Vector3(0, 1.2, 0), 0.06, 0.06, 0.45, 6, LAMP_DARK)
	add_cage_lantern(mb, base + Vector3(0, BUOY_LAMP_Y, 0), light, BUOY_LANTERN, blink_phase)


static func buoy_glow_at(base: Vector3) -> Vector3:
	return cage_lantern_glow_at(base + Vector3(0, BUOY_LAMP_Y, 0), BUOY_LANTERN)


# --- Lamp fixtures --------------------------------------------------------------------
# The fixtures are solid geometry in the lit_vc mesh; the glow sits in their glass
# (GlowBuilder, which draws in a separate mesh), so each pair of helpers below
# agrees on where that is.

## Pale glass in a light's colour, lit at night; flashing if `blink_phase` (0..1, from
## blink_phase_at) is given.
static func lamp_glass(col: Color, blink_phase := -1.0) -> Color:
	var c := col.lerp(Color.WHITE, 0.2)
	c.a = LAMP_GLASS_ALPHA
	if blink_phase >= 0.0:
		c.a = (BLINK_ALPHA0 + roundi(blink_phase * BLINK_STEPS) % BLINK_STEPS) / 255.0
	return c


## A flash phase picked from a light's position, on the steps flashing glass can hold.
static func blink_phase_at(p: Vector3) -> float:
	var h := fposmod(sin(p.x * 12.9898 + p.z * 78.233) * 43758.5453, 1.0)
	return floorf(h * BLINK_STEPS) / BLINK_STEPS


## GlowBuilder's blink for a light flashing with `phase`.
static func blink_of(phase: float) -> float:
	return BLINK_PERIOD + phase


## A caged bulkhead lamp, the ship's-deck kind: a round plate on the wall at `p`,
## an arm out along `out` (horizontal) to a domed cap, and the glass hanging under
## it in a cage. `s` scales it (1: about half a metre tall).
static func add_bulkhead_lamp(mb: MeshBuilder, p: Vector3, out: Vector3, col: Color, s := 1.0, body := BRASS) -> void:
	var saved := mb.xform
	mb.xform = saved * _lamp_frame(p, out, s)
	mb.box(Vector3(0, 0.02, 0.02), Vector3(0.2, 0.24, 0.04), body)
	mb.box(Vector3(0, 0.06, 0.11), Vector3(0.07, 0.07, 0.16), body)
	mb.cylinder(Vector3(0, 0.0, 0.24), 0.12, 0.1, 0.1, 8, body, Color(-1, 0, 0), PI / 8.0)
	mb.cylinder(Vector3(0, 0.1, 0.24), 0.1, 0.0, 0.05, 8, body, Color(-1, 0, 0), PI / 8.0)
	mb.cylinder(Vector3(0, -0.03, 0.24), 0.125, 0.125, 0.03, 8, body, Color(-1, 0, 0), PI / 8.0)
	var glass := lamp_glass(col)
	mb.cylinder(Vector3(0, -0.27, 0.24), 0.085, 0.085, 0.24, 8, glass, Color(-1, 0, 0), PI / 8.0)
	mb.cylinder(Vector3(0, -0.32, 0.24), 0.0, 0.085, 0.05, 8, glass, Color(-1, 0, 0), PI / 8.0)
	# The cage: four bars round the glass, a band at its waist, a ring at the foot.
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		mb.box(Vector3(cos(a) * 0.1, -0.15, 0.24 + sin(a) * 0.1), Vector3(0.022, 0.27, 0.022), body)
	mb.cylinder(Vector3(0, -0.16, 0.24), 0.1, 0.1, 0.025, 8, body, Color(-1, 0, 0), PI / 8.0)
	mb.cylinder(Vector3(0, -0.31, 0.24), 0.08, 0.08, 0.025, 8, body, Color(-1, 0, 0), PI / 8.0)
	mb.xform = saved


## Where add_bulkhead_lamp's glass is, and its radius: put the glow there.
static func bulkhead_glow_at(p: Vector3, out: Vector3, s := 1.0) -> Vector3:
	return _lamp_frame(p, out, s) * Vector3(0, -0.16, 0.24)


static func bulkhead_glow_size(s := 1.0) -> float:
	return 0.1 * s


## A masthead lantern standing on `base`: a dark foot, a glass drum and a conical
## cap. `s` scales it (1: about 0.4 m tall).
static func add_lantern(mb: MeshBuilder, base: Vector3, col: Color, s := 1.0) -> void:
	mb.cylinder(base, 0.13 * s, 0.11 * s, 0.06 * s, 8, LAMP_DARK)
	mb.cylinder(base + Vector3(0, 0.06 * s, 0), 0.09 * s, 0.09 * s, 0.2 * s, 8, lamp_glass(col))
	mb.cylinder(base + Vector3(0, 0.26 * s, 0), 0.13 * s, 0.0, 0.1 * s, 8, LAMP_DARK)


static func lantern_glow_at(base: Vector3, s := 1.0) -> Vector3:
	return base + Vector3(0, 0.16 * s, 0)


## A brass-caged 360° lantern standing on `base`, for buoys, dolphins and the ramp
## lift: a foot, a glass drum in a cage of bars, and a domed cap. `s` scales it (1:
## about half a metre tall); `blink_phase` makes the glass flash (see lamp_glass).
static func add_cage_lantern(mb: MeshBuilder, base: Vector3, col: Color, s := 1.0, blink_phase := -1.0) -> void:
	var saved := mb.xform
	mb.xform = saved * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), base)
	var r := PI / 8.0
	var none := Color(-1, 0, 0)
	mb.cylinder(Vector3.ZERO, 0.13, 0.11, 0.05, 8, BRASS, none, r)
	mb.cylinder(Vector3(0, 0.05, 0), 0.085, 0.085, 0.24, 8, lamp_glass(col, blink_phase), none, r)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		mb.box(Vector3(cos(a) * 0.1, 0.17, sin(a) * 0.1), Vector3(0.022, 0.24, 0.022), BRASS)
	mb.cylinder(Vector3(0, 0.16, 0), 0.1, 0.1, 0.025, 8, BRASS, none, r)
	mb.cylinder(Vector3(0, 0.29, 0), 0.13, 0.11, 0.05, 8, BRASS, none, r)
	mb.cylinder(Vector3(0, 0.34, 0), 0.11, 0.0, 0.08, 8, BRASS, none, r)
	mb.box(Vector3(0, 0.44, 0), Vector3(0.03, 0.06, 0.03), BRASS)
	mb.xform = saved


static func cage_lantern_glow_at(base: Vector3, s := 1.0) -> Vector3:
	return base + Vector3(0, 0.17 * s, 0)


## A sidelight on the wheelhouse wall at side `sx` (±1) of the end `sz` (±1): a lens
## drum on a bracket, a cap, and a screen on its aft side so it only shows ahead and
## abeam. Whichever end is the bow, port is where x and z have the same sign, so
## that lens is red and the other green.
static func add_sidelight(mb: MeshBuilder, sx: float, sz: float) -> void:
	var s := FERRY_SIDELIGHT_SCALE
	var w := Vector3(sx * FERRY_SIDELIGHT.x, FERRY_SIDELIGHT.y, sz * FERRY_SIDELIGHT.z)
	var c := w + Vector3(sx * 0.2 * s, 0, 0)
	var none := Color(-1, 0, 0)
	mb.box(w + Vector3(sx * 0.1 * s, -0.13 * s, 0), Vector3(0.24 * s, 0.04 * s, 0.34 * s), LAMP_DARK)
	mb.box(w + Vector3(sx * 0.04 * s, 0, 0), Vector3(0.08 * s, 0.3 * s, 0.34 * s), LAMP_DARK)
	mb.cylinder(c + Vector3(0, -0.11 * s, 0), 0.11 * s, 0.11 * s, 0.2 * s, 8, NAV_RED if sx * sz > 0.0 else NAV_GREEN, none, PI / 8.0)
	mb.cylinder(c + Vector3(0, 0.09 * s, 0), 0.13 * s, 0.09 * s, 0.05 * s, 8, LAMP_DARK, none, PI / 8.0)
	# Screen on the aft side (towards the middle of the ship).
	mb.box(c + Vector3(-sx * 0.02 * s, -0.01 * s, -sz * 0.14 * s), Vector3(0.3 * s, 0.26 * s, 0.03 * s), LAMP_DARK)


static func sidelight_glow_at(sx: float, sz: float) -> Vector3:
	return Vector3(sx * (FERRY_SIDELIGHT.x + 0.2 * FERRY_SIDELIGHT_SCALE), FERRY_SIDELIGHT.y, sz * FERRY_SIDELIGHT.z)


## Frame for a wall fixture at `p`: +Z out from the wall, +Y up, scaled by `s`.
static func _lamp_frame(p: Vector3, out: Vector3, s: float) -> Transform3D:
	var z := Vector3(out.x, 0.0, out.z).normalized()
	var x := Vector3.UP.cross(z)
	return Transform3D(Basis(x, Vector3.UP, z).scaled(Vector3.ONE * s), p)

