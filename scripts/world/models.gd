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


## A gull, about 1.4 m across (+Z forward, wings out along X, upper sides facing
## up). Wing vertices carry alpha 0.5, which seagull.gdshader flaps and folds about
## the shoulder (|x| = 0.06); it also lightens their undersides, so they are single panels.
static func seagull() -> ArrayMesh:
	return _cached("seagull", func():
		var mb := MeshBuilder.new()
		var white := Color(0.95, 0.95, 0.93)
		var mantle := Color(0.66, 0.7, 0.74, 0.5)
		var tip := Color(0.12, 0.12, 0.13, 0.5)
		# Body: an octahedron stretched along the spine, and a smaller one for the head.
		_octa(mb, Vector3(0, 0.01, 0.03), Vector3(0.065, 0.065, 0.0), 0.24, -0.23, white)
		_octa(mb, Vector3(0, 0.075, 0.22), Vector3(0.045, 0.045, 0.0), 0.06, -0.05, white)
		var beak := Color(0.95, 0.74, 0.2)
		var bp := Vector3(0, 0.06, 0.36)
		var b0 := Vector3(0.016, 0.075, 0.275)
		var b1 := Vector3(-0.016, 0.075, 0.275)
		var b2 := Vector3(0, 0.05, 0.275)
		mb.tri(b0, b1, bp, beak, Vector3.UP)
		mb.tri(b1, b2, bp, beak, Vector3(-1, -1, 0))
		mb.tri(b2, b0, bp, beak, Vector3(1, -1, 0))
		mb.quad(Vector3(-0.05, 0.03, -0.16), Vector3(0.05, 0.03, -0.16), Vector3(0.075, 0.02, -0.32),
			Vector3(-0.075, 0.02, -0.32), white, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var sh_f := Vector3(0.06 * side, 0.04, 0.1)
			var sh_b := Vector3(0.06 * side, 0.04, -0.07)
			var el_f := Vector3(0.4 * side, 0.04, 0.08)
			var el_b := Vector3(0.4 * side, 0.04, -0.09)
			var mid_f := Vector3(0.58 * side, 0.04, 0.03)
			var mid_b := Vector3(0.58 * side, 0.04, -0.1)
			var end := Vector3(0.72 * side, 0.04, -0.12)
			mb.quad(sh_f, el_f, el_b, sh_b, mantle, Vector3.UP)
			mb.quad(el_f, mid_f, mid_b, el_b, mantle, Vector3.UP)
			mb.tri(mid_f, end, mid_b, tip, Vector3.UP)
		return mb.commit())


## An orca one unit long (+Z forward, nose at z = 0.5), drawn per animal by Orcas'
## multimesh and scaled to its length. The dorsal fin's vertices carry alpha < 1:
## orca.gdshader raises them to each animal's fin height and sweeps them back (a
## bull's fin stands tall and straight, a cow's is shorter and curved). It also beats
## the tail. Belly, chin, eye patch and flank are white, the saddle grey.
static func orca() -> ArrayMesh:
	return _cached("orca", func():
		var mb := MeshBuilder.new()
		var black := Color(0.05, 0.055, 0.065)
		var white := Color(0.92, 0.93, 0.92)
		var saddle := Color(0.5, 0.52, 0.55)
		# Cross-sections nose to tail: z, half-width, half-height, centre height.
		var st := [[0.5, 0.0, 0.0, -0.01], [0.44, 0.045, 0.04, -0.005], [0.34, 0.075, 0.07, 0.0],
			[0.18, 0.095, 0.09, 0.0], [0.0, 0.095, 0.092, 0.0], [-0.16, 0.075, 0.075, 0.0],
			[-0.3, 0.045, 0.05, 0.005], [-0.4, 0.018, 0.035, 0.01], [-0.44, 0.0, 0.0, 0.01]]
		var rings: Array[PackedVector3Array] = []
		for s: Array in st:
			var ring := PackedVector3Array()
			for k in 8:
				var a := TAU * k / 8.0
				ring.append(Vector3(s[1] * sin(a), s[3] + s[2] * cos(a), s[0]))
			rings.append(ring)
		for i in st.size() - 1:
			var axis := Vector3(0, (st[i][3] + st[i + 1][3]) * 0.5, (st[i][0] + st[i + 1][0]) * 0.5)
			for k in 8:
				# Facet k runs from k * 45° (0 = the back) round to (k + 1) * 45°.
				var band := mini(k, 7 - k)   # 0 top, 1 upper side, 2 lower side, 3 belly
				var col := black
				if band == 3 and i <= 4:
					col = white
				elif band == 2 and (i <= 1 or i == 4 or i == 5):
					col = white
				elif band == 1 and i == 2:
					col = white
				elif band == 0 and i == 4:
					col = saddle
				var a := rings[i][k]
				var b := rings[i][(k + 1) % 8]
				var c := rings[i + 1][(k + 1) % 8]
				var d := rings[i + 1][k]
				mb.quad(a, b, c, d, col, (a + b + c + d) * 0.25 - axis)
		# Dorsal fin: base on the back, a waist and a tip; height and sweep come from the shader.
		var base_y := 0.085
		var bf := Vector3(0, base_y, 0.07)
		var bb := Vector3(0, base_y, -0.1)
		var mf := Vector3(0, base_y, 0.03)
		var mback := Vector3(0, base_y, -0.06)
		var tip := Vector3(0, base_y, -0.03)
		var fin_base := Color(black, 1.0)
		var fin_mid := Color(black, 0.75)
		var fin_tip := Color(black, 0.5)
		for side: float in [-1.0, 1.0]:
			var w := Vector3(0.014 * side, 0, 0)
			var wm := Vector3(0.007 * side, 0, 0)
			var out := Vector3(side, 0, 0)
			mb.tri3(bf + w, bb + w, mback + wm, fin_base, fin_base, fin_mid, out)
			mb.tri3(bf + w, mback + wm, mf + wm, fin_base, fin_mid, fin_mid, out)
			mb.tri3(mf + wm, mback + wm, tip, fin_mid, fin_mid, fin_tip, out)
			# Leading and trailing edges.
			mb.tri3(bf, bf + w, mf + wm, fin_base, fin_base, fin_mid, Vector3(side, 0, 1))
			mb.tri3(bf, mf + wm, mf, fin_base, fin_mid, fin_mid, Vector3(side, 0, 1))
			mb.tri3(mf, mf + wm, tip, fin_mid, fin_mid, fin_tip, Vector3(side, 0, 1))
			mb.tri3(bb, bb + w, mback + wm, fin_base, fin_base, fin_mid, Vector3(side, 0, -1))
			mb.tri3(bb, mback + wm, mback, fin_base, fin_mid, fin_mid, Vector3(side, 0, -1))
			mb.tri3(mback, mback + wm, tip, fin_mid, fin_mid, fin_tip, Vector3(side, 0, -1))
			# Paddle-shaped flippers, angled down and back.
			mb.tri(Vector3(0.07 * side, -0.065, 0.24), Vector3(0.21 * side, -0.12, 0.09),
				Vector3(0.07 * side, -0.07, 0.13), black, Vector3(0, -1, 0))
			# Flukes: swept-back wings off the tail stock with a notch in the middle.
			var root_f := Vector3(0, 0.01, -0.38)
			var notch := Vector3(0, 0.01, -0.46)
			var fluke_tip := Vector3(0.15 * side, 0.005, -0.52)
			mb.tri(root_f, fluke_tip, Vector3(0.05 * side, 0.01, -0.48), black, Vector3.UP)
			mb.tri(root_f, Vector3(0.05 * side, 0.01, -0.48), notch, black, Vector3.UP)
		var mesh := mb.commit()
		# The shader moves the fin and tail, which a baked shadow mesh can't follow.
		mesh.shadow_mesh = null
		return mesh)


## A blow or a splash: a white plume one unit tall, drawn per puff by Orcas.
static func spout() -> ArrayMesh:
	return _cached("spout", func():
		var mb := MeshBuilder.new()
		mb.cylinder(Vector3.ZERO, 0.12, 0.45, 0.6, 6, Color(0.95, 0.97, 1.0, 0.85))
		mb.cylinder(Vector3(0, 0.6, 0), 0.45, 0.2, 0.4, 6, Color(0.95, 0.97, 1.0, 0.6))
		return mb.commit(unshaded_material()))


## An octahedron at `c`, `r` wide (x) and tall (y), reaching `front` ahead and `back` behind.
static func _octa(mb: MeshBuilder, c: Vector3, r: Vector3, front: float, back: float, col: Color) -> void:
	var f := c + Vector3(0, 0, front)
	var b := c + Vector3(0, 0, back)
	var ring := [c + Vector3(r.x, 0, 0), c + Vector3(0, r.y, 0), c + Vector3(-r.x, 0, 0), c + Vector3(0, -r.y, 0)]
	for i in 4:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 4]
		var out := (p0 + p1) * 0.5 - c
		mb.tri(p0, p1, f, col, out)
		mb.tri(p1, p0, b, col, out)


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
		add_lantern(mb, SAIL_MAST_TOP, GlowBuilder.LED, SAIL_LANTERN)
		return mb.commit())


# The sails, each built round the line it swings on (Sailboat sheets them out
# to leeward): the mainsail and boom round the mast, the jib round its forestay.
const SAIL_MAIN_PIVOT := Vector3(0, 0, 0.2)
const SAIL_JIB_TACK := Vector3(0, 0.8, 1.7)
const SAIL_JIB_HEAD := Vector3(0, 3.6, 0.35)


static func sailboat_main() -> ArrayMesh:
	return _cached("sailboat_main", func():
		var mb := MeshBuilder.new()
		var a := Vector3(0, 0.7, 0)
		var b := Vector3(0, 4.2, 0)
		var c := Vector3(0, 0.7, -1.6)
		mb.tri(a, b, c, Color(0.98, 0.98, 0.96), Vector3.RIGHT)
		mb.tri(a, b, c, Color(0.98, 0.98, 0.96), Vector3.LEFT)
		mb.box(Vector3(0, 0.66, -0.8), Vector3(0.07, 0.07, 1.7), Color(0.8, 0.8, 0.8))
		return mb.commit())


static func sailboat_jib() -> ArrayMesh:
	return _cached("sailboat_jib", func():
		var mb := MeshBuilder.new()
		var head := SAIL_JIB_HEAD - SAIL_JIB_TACK
		var clew := Vector3(0, 0.8, 0.4) - SAIL_JIB_TACK
		mb.tri(head, clew, Vector3.ZERO, Color(0.95, 0.95, 0.9), Vector3.RIGHT)
		mb.tri(head, clew, Vector3.ZERO, Color(0.95, 0.95, 0.9), Vector3.LEFT)
		return mb.commit())


## The sailboat at its berth: sails stowed along the boom.
static func sailboat_furled() -> ArrayMesh:
	return _cached("sailboat_furled", func():
		var mb := MeshBuilder.new()
		var hull := PackedVector2Array([Vector2(-0.6, -1.6), Vector2(0.6, -1.6), Vector2(0.65, 0.6), Vector2(0.0, 2.0), Vector2(-0.65, 0.6)])
		mb.extrude(hull, -0.3, 0.35, WHITE, Color(0.75, 0.62, 0.45), 0.7)
		mb.box(Vector3(0, 2.3, 0.3), Vector3(0.08, 4.0, 0.08), Color(0.8, 0.8, 0.8))
		mb.box(Vector3(0, 0.78, -0.55), Vector3(0.07, 0.07, 1.8), Color(0.8, 0.8, 0.8))
		mb.box(Vector3(0, 0.9, -0.5), Vector3(0.2, 0.18, 1.6), Color(0.2, 0.32, 0.5))
		add_lantern(mb, SAIL_MAST_TOP, GlowBuilder.LED, SAIL_LANTERN)
		return mb.commit())


## The sailboat's anchor light, drawn by NightLights on each boat.
static func sailboat_lights() -> ArrayMesh:
	return _cached("sailboat_lights", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(SAIL_MAST_TOP, SAIL_LANTERN), GlowBuilder.LED, 0.13, 4.0, true, 0.0, Vector3.ZERO, LAMP_ON_AT)
		return gb.commit())


# Container ship (+Z is the bow): masthead lantern heights and the sidelights.
const CARGO_FORE_MAST := Vector3(0, 9.0, 28.5)
const CARGO_AFT_MAST := Vector3(0, 15.6, -24.0)
const CARGO_LANTERN := 1.6
const CARGO_SIDELIGHT := Vector3(6.3, 11.6, -24.0)
const CARGO_FUNNELS := [Color(0.85, 0.55, 0.12), Color(0.15, 0.35, 0.65), Color(0.75, 0.15, 0.13)]
const CONTAINERS := [Color(0.62, 0.2, 0.15), Color(0.18, 0.33, 0.6), Color(0.2, 0.48, 0.32),
	Color(0.88, 0.5, 0.15), Color(0.55, 0.57, 0.6), Color(0.14, 0.5, 0.55), Color(0.9, 0.9, 0.86),
	Color(0.85, 0.7, 0.2), Color(0.45, 0.25, 0.4)]


## A container ship about 64 m long and 11 m in the beam, its accommodation block
## aft. `variant` picks the funnel colour and how the boxes are stacked.
static func cargo_ship(variant: int) -> ArrayMesh:
	return _cached("cargo_%d" % variant, func():
		var mb := MeshBuilder.new()
		var topsides := Color(0.12, 0.16, 0.24)
		_cargo_hull(mb, topsides, Color(0.4, 0.42, 0.43), CARGO_FUNNELS[variant % CARGO_FUNNELS.size()])
		# Containers: seven bays of four stacks, one to three high.
		var r := RandomNumberGenerator.new()
		r.seed = 4111 + variant * 97
		for bay in 7:
			var z := -18.5 + bay * 6.2
			for col in 4:
				var x := -3.75 + col * 2.5
				var tiers := r.randi_range(1, 3) if variant % 3 != 2 else r.randi_range(2, 3)
				for t in tiers:
					var c: Color = CONTAINERS[r.randi_range(0, CONTAINERS.size() - 1)]
					mb.box(Vector3(x, 3.2 + 1.25 + t * 2.5, z), Vector3(2.4, 2.45, 6.0), c.darkened(r.randf() * 0.12))
		return mb.commit())


# Tankers: dark topsides over a deck painted green or oxide red, by variant.
const TANKER_TOPSIDES := [Color(0.1, 0.1, 0.11), Color(0.42, 0.11, 0.1), Color(0.12, 0.2, 0.3)]
const TANKER_DECKS := [Color(0.3, 0.42, 0.3), Color(0.3, 0.42, 0.3), Color(0.5, 0.22, 0.17)]
const TANKER_FUNNELS := [Color(0.85, 0.15, 0.12), Color(0.92, 0.92, 0.9), Color(0.9, 0.72, 0.18)]


## A tanker on the same hull as the container ship: a flat deck with its cargo
## lines and the catwalk running fore and aft, the manifold and its hose crane
## amidships.
static func tanker(variant: int) -> ArrayMesh:
	return _cached("tanker_%d" % variant, func():
		var mb := MeshBuilder.new()
		var deck: Color = TANKER_DECKS[variant % TANKER_DECKS.size()]
		_cargo_hull(mb, TANKER_TOPSIDES[variant % TANKER_TOPSIDES.size()], deck,
			TANKER_FUNNELS[variant % TANKER_FUNNELS.size()])
		var pipe := Color(0.62, 0.64, 0.6)
		var steel := Color(0.3, 0.32, 0.33)
		var z0 := -21.6
		var z1 := 22.8
		var zc := (z0 + z1) * 0.5
		var span := z1 - z0
		# Cargo lines along the deck either side of the centreline.
		for x: float in [-2.0, -1.4, 1.4, 2.0]:
			mb.box(Vector3(x, 3.5, zc), Vector3(0.3, 0.3, span), pipe)
		# The catwalk on its posts, high over the lines.
		mb.box(Vector3(0, 5.0, zc), Vector3(1.1, 0.12, span), WHITE)
		for i in 9:
			mb.box(Vector3(0, 4.1, z0 + 1.0 + i * (span - 2.0) / 8.0), Vector3(0.2, 1.8, 0.2), WHITE)
		# Tank hatches and vent posts down either side.
		for i in 6:
			var z := -17.0 + i * 7.0
			for x: float in [-3.6, 3.6]:
				mb.cylinder(Vector3(x, 3.2, z), 0.55, 0.55, 0.4, 8, steel)
				mb.box(Vector3(x * 0.8, 4.0, z + 2.0), Vector3(0.16, 1.6, 0.16), pipe)
		# The manifold athwartships, with its hose crane.
		for dz: float in [-0.6, 0.6]:
			mb.box(Vector3(0, 3.6, dz), Vector3(10.4, 0.36, 0.36), pipe)
		for x: float in [-5.0, 5.0]:
			mb.box(Vector3(x, 3.9, 0), Vector3(0.6, 1.1, 2.0), steel)
		mb.cylinder(Vector3(0, 3.2, -2.6), 0.4, 0.35, 4.4, 8, Color(0.88, 0.72, 0.2))
		var a := Vector3(0, 7.4, -2.6)
		var b := Vector3(3.6, 4.6, 3.0)
		mb.xform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
		mb.box(Vector3.ZERO, Vector3(0.36, 0.36, a.distance_to(b)), Color(0.88, 0.72, 0.2))
		mb.xform = Transform3D.IDENTITY
		# Fire monitors on their platform before the bridge.
		mb.box(Vector3(0, 5.6, -20.2), Vector3(4.0, 0.15, 1.4), WHITE)
		for x: float in [-1.4, 1.4]:
			mb.box(Vector3(x, 5.9, -20.2), Vector3(0.3, 0.5, 0.6), Color(0.75, 0.15, 0.13))
		return mb.commit())


# Bulk carriers: topsides, hatch covers and deck cranes, by variant.
const BULKER_TOPSIDES := [Color(0.14, 0.22, 0.34), Color(0.2, 0.21, 0.22), Color(0.48, 0.15, 0.12)]
const BULKER_HATCHES := [Color(0.55, 0.18, 0.14), Color(0.2, 0.42, 0.3), Color(0.18, 0.3, 0.5)]
const BULKER_CRANES := [Color(0.9, 0.74, 0.2), Color(0.92, 0.92, 0.9), Color(0.9, 0.74, 0.2)]
const BULKER_FUNNELS := [Color(0.15, 0.35, 0.65), Color(0.85, 0.55, 0.12), Color(0.94, 0.95, 0.94)]


## A geared bulk carrier on the same hull: five big hatches under folding
## covers, and four deck cranes between them with their jibs stowed forward.
static func bulk_carrier(variant: int) -> ArrayMesh:
	return _cached("bulker_%d" % variant, func():
		var mb := MeshBuilder.new()
		var topsides: Color = BULKER_TOPSIDES[variant % BULKER_TOPSIDES.size()]
		var hatch: Color = BULKER_HATCHES[variant % BULKER_HATCHES.size()]
		var crane: Color = BULKER_CRANES[variant % BULKER_CRANES.size()]
		_cargo_hull(mb, topsides, Color(0.45, 0.2, 0.16), BULKER_FUNNELS[variant % BULKER_FUNNELS.size()])
		var hatch_z := [-17.0, -8.2, 0.6, 9.4, 18.2]
		for z: float in hatch_z:
			# The coaming, and the two cover panels meeting on the centreline in
			# a shallow ridge.
			mb.box(Vector3(0, 3.95, z), Vector3(8.2, 1.5, 7.0), topsides.lightened(0.15))
			for x: float in [-1.0, 1.0]:
				mb.quad(Vector3(x * 4.0, 4.7, z - 3.4), Vector3(x * 4.0, 4.7, z + 3.4),
					Vector3(0, 5.2, z + 3.4), Vector3(0, 5.2, z - 3.4), hatch, Vector3(x * 0.2, 1, 0))
				for dz: float in [-1.7, 0.0, 1.7]:
					mb.box(Vector3(x * 2.0, 4.95, z + dz), Vector3(3.9, 0.12, 0.14), hatch.darkened(0.25))
			mb.tri(Vector3(-4.0, 4.7, z + 3.4), Vector3(4.0, 4.7, z + 3.4), Vector3(0, 5.2, z + 3.4), hatch.darkened(0.15), Vector3.BACK)
			mb.tri(Vector3(-4.0, 4.7, z - 3.4), Vector3(4.0, 4.7, z - 3.4), Vector3(0, 5.2, z - 3.4), hatch.darkened(0.15), Vector3.FORWARD)
		# Cranes between the hatches, jibs stowed forward and a touch outboard,
		# alternately to port and starboard.
		for i in 4:
			var z: float = (hatch_z[i] + hatch_z[i + 1]) * 0.5
			var side := 1.0 if i % 2 == 0 else -1.0
			mb.cylinder(Vector3(0, 3.2, z), 0.75, 0.65, 3.4, 8, crane)
			mb.box(Vector3(0, 7.3, z), Vector3(2.0, 1.6, 2.2), crane)
			mb.box(Vector3(side * 0.6, 7.5, z + 1.12), Vector3(0.7, 0.6, 0.06), GLASS)
			var a := Vector3(side * 0.5, 7.6, z + 0.6)
			var b := Vector3(side * 2.2, 9.8, z + 9.0)
			mb.xform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
			mb.box(Vector3.ZERO, Vector3(0.45, 0.5, a.distance_to(b)), crane)
			mb.xform = Transform3D.IDENTITY
			mb.box(Vector3(0, 8.5, z - 0.4), Vector3(0.3, 1.0, 0.3), crane)
		return mb.commit())


## What every cargo ship has in common, 64 m long and 11 m in the beam: the
## hull, forecastle, the accommodation block aft with its bridge and funnel,
## the masts and the sidelights.
static func _cargo_hull(mb: MeshBuilder, topsides: Color, deck: Color, funnel: Color) -> void:
	var hull := PackedVector2Array([Vector2(-5.6, -30), Vector2(-4.8, -32), Vector2(4.8, -32), Vector2(5.6, -30),
		Vector2(5.6, 20), Vector2(4.2, 27), Vector2(1.6, 31), Vector2(0, 32), Vector2(-1.6, 31), Vector2(-4.2, 27),
		Vector2(-5.6, 20)])
	mb.extrude(hull, -2.6, 0.25, Color(0.55, 0.14, 0.12), Color(0, 0, 0, 0), 0.85)
	mb.extrude(hull, 0.25, 3.2, topsides, deck)
	mb.extrude(hull, 0.18, 0.32, WHITE, Color(0, 0, 0, 0))
	# Forecastle and the breakwater behind it.
	mb.box(Vector3(0, 3.6, 26.0), Vector3(8.0, 0.8, 5.0), topsides)
	mb.box(Vector3(0, 4.4, 23.4), Vector3(10.4, 1.6, 0.25), WHITE)
	# Accommodation block, bridge with its wings, and the funnel.
	mb.box(Vector3(0, 7.2, -25.0), Vector3(10.0, 8.0, 6.0), WHITE)
	for y: float in [5.2, 7.4, 9.6]:
		mb.box(Vector3(0, y, -25.0), Vector3(10.1, 0.6, 6.1), WINDOW_LIT)
	mb.box(Vector3(0, 11.6, -24.0), Vector3(12.4, 1.4, 3.2), WHITE)
	mb.box(Vector3(0, 11.7, -24.0), Vector3(12.5, 0.5, 3.3), WINDOW_LIT)
	mb.box(Vector3(0, 12.4, -24.0), Vector3(12.8, 0.2, 3.6), Color(0.3, 0.32, 0.34))
	mb.box(Vector3(0, 14.0, -24.0), Vector3(0.25, 3.0, 0.25), WHITE)
	add_lantern(mb, CARGO_AFT_MAST, GlowBuilder.LED, CARGO_LANTERN)
	mb.box(Vector3(0, 13.4, -28.6), Vector3(2.6, 3.6, 2.8), funnel)
	mb.box(Vector3(0, 15.45, -28.6), Vector3(2.65, 0.5, 2.85), Color(0.1, 0.1, 0.1))
	# Port (+X) red, starboard green, on the bridge wings' ends.
	for x: float in [-1.0, 1.0]:
		mb.box(Vector3(x * CARGO_SIDELIGHT.x, CARGO_SIDELIGHT.y, CARGO_SIDELIGHT.z), Vector3(0.2, 0.35, 0.45),
			lamp_glass(GlowBuilder.RED if x > 0.0 else GlowBuilder.GREEN))
	# Foremast.
	mb.box(Vector3(0, 6.1, 28.5), Vector3(0.3, 5.8, 0.3), Color(0.85, 0.75, 0.2))
	add_lantern(mb, CARGO_FORE_MAST, GlowBuilder.LED, CARGO_LANTERN)


## Masthead, stern and sidelights and the lit bridge's reflection, in the ship's frame.
static func cargo_ship_lights() -> ArrayMesh:
	return _cached("cargo_lights", func():
		var gb := GlowBuilder.new()
		for top: Vector3 in [CARGO_FORE_MAST, CARGO_AFT_MAST]:
			gb.glow(lantern_glow_at(top, CARGO_LANTERN), GlowBuilder.LED, 0.35, 9.0, true, 0.0, Vector3.ZERO, 0.0)
		gb.glow(Vector3(-CARGO_SIDELIGHT.x, CARGO_SIDELIGHT.y, CARGO_SIDELIGHT.z), GlowBuilder.GREEN, 0.25, 7.0, true, 0.0, Vector3(-1, 0, 0.8), 0.0)
		gb.glow(CARGO_SIDELIGHT, GlowBuilder.RED, 0.25, 7.0, true, 0.0, Vector3(1, 0, 0.8), 0.0)
		gb.glow(Vector3(0, 4.0, -32.2), GlowBuilder.LED, 0.2, 5.0, true, 0.0, Vector3(0, 0, -1), 0.0)
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-6.25, 6.25]:
			for i in 5:
				gb.reflection(Vector3(x, 11.7, -25.4 + i * 0.7), window, 0.3, 2.2, Vector3(signf(x), 0, 0))
		for x in 7:
			gb.reflection(Vector3(-4.5 + x * 1.5, 11.7, -22.3), window, 0.3, 2.2, Vector3(0, 0, 1))
		return gb.commit())


# Stern trawler (+Z is the bow): about 20 m long and 6.4 m in the beam, the
# wheelhouse forward and the working deck aft under a gantry. The mast carries
# the trawling lights (green over white) and the masthead light.
const TRAWLER_DECK := 1.6
const TRAWLER_MAST := Vector3(0, 8.6, 1.3)       # the white lantern's foot
const TRAWLER_MAST_GREEN := Vector3(0, 9.6, 1.3)
const TRAWLER_LANTERN := 1.2
const TRAWLER_SIDELIGHT := Vector3(2.35, 4.45, 5.4)
const TRAWLER_GANTRY_Z := -9.3
const TRAWLER_GANTRY_TOP := 6.6
const TRAWLER_HULLS := [Color(0.12, 0.2, 0.36), Color(0.13, 0.33, 0.24), Color(0.58, 0.15, 0.12)]
const TRAWLER_GANTRIES := [Color(0.92, 0.52, 0.12), Color(0.9, 0.78, 0.2), Color(0.92, 0.52, 0.12)]
const TRAWLER_NETS := [Color(0.2, 0.55, 0.35), Color(0.85, 0.42, 0.15), Color(0.25, 0.4, 0.62)]


static func _trawler_outline(grow := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-2.9, -10), Vector2(2.9, -10), Vector2(3.2, -8), Vector2(3.2, 3),
		Vector2(2.65, 6.5), Vector2(1.45, 8.8), Vector2(0, 10), Vector2(-1.45, 8.8), Vector2(-2.65, 6.5),
		Vector2(-3.2, 3), Vector2(-3.2, -8)])
	if grow != 0.0:
		for i in pts.size():
			pts[i] = pts[i] * Vector2((3.2 + grow) / 3.2, (10.0 + grow) / 10.0)
	return pts


## A stern trawler; `variant` picks its colours.
static func trawler(variant: int) -> ArrayMesh:
	return _cached("trawler_%d" % variant, func():
		var mb := MeshBuilder.new()
		var hull_col: Color = TRAWLER_HULLS[variant % TRAWLER_HULLS.size()]
		var gantry: Color = TRAWLER_GANTRIES[variant % TRAWLER_GANTRIES.size()]
		var net: Color = TRAWLER_NETS[variant % TRAWLER_NETS.size()]
		var deck_col := Color(0.42, 0.43, 0.42)
		var steel := Color(0.22, 0.23, 0.25)
		var d := TRAWLER_DECK
		var outline := _trawler_outline()
		mb.extrude(outline, -2.0, 0.05, Color(0.55, 0.14, 0.12), Color(0, 0, 0, 0), 0.7)
		mb.extrude(outline, 0.05, d, hull_col, deck_col)
		mb.extrude(_trawler_outline(0.06), d - 0.2, d - 0.05, WHITE, Color(0, 0, 0, 0))
		# Bulwarks down either side of the working deck, the transom's open aft.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 3.12, d + 0.4, -3.0), Vector3(0.14, 0.8, 12.0), hull_col)
			mb.box(Vector3(x * 3.12, d + 0.82, -3.0), Vector3(0.2, 0.06, 12.0), WHITE)
		# The raised foredeck.
		var fore := PackedVector2Array([Vector2(-3.2, 3), Vector2(3.2, 3), Vector2(2.65, 6.5), Vector2(1.45, 8.8),
			Vector2(0, 10), Vector2(-1.45, 8.8), Vector2(-2.65, 6.5)])
		mb.extrude(fore, d, d + 1.0, hull_col, deck_col)
		mb.box(Vector3(0, d + 1.15, 6.6), Vector3(0.6, 0.3, 0.8), steel)
		# Deckhouse and the wheelhouse on top of it, windows all round.
		mb.box(Vector3(0, d + 1.0, 2.0), Vector3(4.8, 2.0, 4.6), WHITE)
		mb.box(Vector3(0, d + 2.0 + 0.9, 3.3), Vector3(4.4, 1.8, 3.4), WHITE)
		mb.box(Vector3(0, d + 2.0 + 1.15, 3.3), Vector3(4.46, 0.6, 3.46), WINDOW_LIT)
		mb.box(Vector3(0, d + 2.0 + 1.85, 3.3), Vector3(4.9, 0.12, 3.9), WHITE)
		mb.box(Vector3(0, d + 1.1, 2.0), Vector3(4.86, 0.5, 2.2), WINDOW_LIT)
		# Sidelights in their screens on the wheelhouse sides.
		for x: float in [-1.0, 1.0]:
			var sl := Vector3(x * TRAWLER_SIDELIGHT.x, TRAWLER_SIDELIGHT.y, TRAWLER_SIDELIGHT.z)
			mb.box(sl + Vector3(0, 0, -0.25), Vector3(0.3, 0.32, 0.06), LAMP_DARK)
			mb.box(sl, Vector3(0.18, 0.24, 0.3), lamp_glass(GlowBuilder.RED if x > 0.0 else GlowBuilder.GREEN))
		# Mast with its crosstree and lights, the radar, the exhaust stack.
		var mast_base := d + 2.0 + 1.9
		mb.box(Vector3(0, (mast_base + TRAWLER_MAST_GREEN.y) * 0.5, TRAWLER_MAST.z), Vector3(0.18, TRAWLER_MAST_GREEN.y - mast_base, 0.18), WHITE)
		mb.box(Vector3(0, 7.6, TRAWLER_MAST.z), Vector3(2.4, 0.1, 0.1), WHITE)
		add_lantern(mb, TRAWLER_MAST, GlowBuilder.LED, TRAWLER_LANTERN)
		add_lantern(mb, TRAWLER_MAST_GREEN, GlowBuilder.GREEN, TRAWLER_LANTERN)
		mb.box(Vector3(0, mast_base + 0.45, 2.6), Vector3(0.25, 0.5, 0.25), steel)
		mb.box(Vector3(0, mast_base + 0.75, 2.6), Vector3(2.2, 0.12, 0.3), WHITE)
		mb.cylinder(Vector3(1.6, d + 2.0, 0.4), 0.22, 0.2, 3.6, 8, Color(0.85, 0.85, 0.83))
		mb.cylinder(Vector3(1.6, d + 5.6, 0.4), 0.21, 0.21, 0.4, 8, Color(0.08, 0.08, 0.08))
		mb.cylinder(Vector3(-1.5, d + 2.0 + 1.9, 2.2), 0.3, 0.3, 0.7, 8, WHITE)
		# The working deck: fish hatch, net drum, and the gantry over the stern
		# with the trawl doors hung either side.
		mb.box(Vector3(0, d + 0.25, -2.6), Vector3(1.8, 0.5, 1.8), steel)
		var saved := mb.xform
		mb.xform = saved * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.8, d + 1.1, -6.4))
		mb.cylinder(Vector3.ZERO, 0.85, 0.85, 3.6, 10, net)
		mb.cylinder(Vector3(0, -0.06, 0), 1.05, 1.05, 0.12, 10, steel)
		mb.cylinder(Vector3(0, 3.54, 0), 1.05, 1.05, 0.12, 10, steel)
		mb.xform = saved
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 1.95, d + 0.55, -6.4), Vector3(0.2, 1.1, 0.4), steel)
			mb.box(Vector3(x * 2.7, (d + TRAWLER_GANTRY_TOP) * 0.5, TRAWLER_GANTRY_Z), Vector3(0.32, TRAWLER_GANTRY_TOP - d, 0.32), gantry)
			mb.box(Vector3(x * 3.32, d + 0.9, -8.4), Vector3(0.14, 1.1, 1.7), steel)
			mb.box(Vector3(x * 2.95, d + 1.6, -8.4), Vector3(0.6, 0.06, 0.06), steel)
		mb.box(Vector3(0, TRAWLER_GANTRY_TOP, TRAWLER_GANTRY_Z), Vector3(5.8, 0.34, 0.4), gantry)
		for x: float in [-1.4, 1.4]:
			mb.box(Vector3(x, TRAWLER_GANTRY_TOP - 0.45, TRAWLER_GANTRY_Z), Vector3(0.3, 0.5, 0.25), steel)
		# Tyres slung along the topsides for coming alongside.
		for x: float in [-1.0, 1.0]:
			for z: float in [-6.5, -3.0, 0.5, 4.0]:
				mb.box(Vector3(x * 3.28, d - 0.35, z), Vector3(0.18, 0.6, 0.6), Color(0.08, 0.08, 0.09))
		# The stern light.
		mb.box(Vector3(0, d + 0.15, -10.02), Vector3(0.22, 0.2, 0.08), lamp_glass(GlowBuilder.LED))
		return mb.commit())


## The trawl warps, out from the gantry's blocks and down into the water astern
## (shown while the net is out).
static func trawler_warps() -> ArrayMesh:
	return _cached("trawler_warps", func():
		var mb := MeshBuilder.new()
		for x: float in [-1.4, 1.4]:
			var a := Vector3(x, TRAWLER_GANTRY_TOP - 0.7, TRAWLER_GANTRY_Z)
			var b := Vector3(x * 1.6, -0.6, TRAWLER_GANTRY_Z - 8.5)
			mb.xform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
			mb.box(Vector3.ZERO, Vector3(0.07, 0.07, a.distance_to(b)), Color(0.15, 0.15, 0.16))
		return mb.commit())


## The lit wheelhouse's reflection, drawn by NightLights on each trawler.
static func trawler_lights() -> ArrayMesh:
	return _cached("trawler_lights", func():
		var gb := GlowBuilder.new()
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-2.25, 2.25]:
			for i in 3:
				gb.reflection(Vector3(x, TRAWLER_DECK + 3.15, 2.4 + i * 0.9), window, 0.26, 1.8, Vector3(signf(x), 0, 0))
		for i in 4:
			gb.reflection(Vector3(-1.5 + i, TRAWLER_DECK + 3.15, 5.05), window, 0.26, 1.8, Vector3(0, 0, 1))
		return gb.commit())


## Sidelights and stern light, shown under way.
static func trawler_nav_lights() -> ArrayMesh:
	return _cached("trawler_nav", func():
		var gb := GlowBuilder.new()
		gb.glow(Vector3(TRAWLER_SIDELIGHT.x, TRAWLER_SIDELIGHT.y, TRAWLER_SIDELIGHT.z + 0.1), GlowBuilder.RED, 0.2, 6.0, true, 0.0, Vector3(1, 0, 0.8), 0.0)
		gb.glow(Vector3(-TRAWLER_SIDELIGHT.x, TRAWLER_SIDELIGHT.y, TRAWLER_SIDELIGHT.z + 0.1), GlowBuilder.GREEN, 0.2, 6.0, true, 0.0, Vector3(-1, 0, 0.8), 0.0)
		gb.glow(Vector3(0, TRAWLER_DECK + 0.15, -10.1), GlowBuilder.LED, 0.16, 4.0, true, 0.0, Vector3(0, 0, -1), 0.0)
		return gb.commit())


## The masthead light, shown steaming.
static func trawler_steaming_lights() -> ArrayMesh:
	return _cached("trawler_steaming", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(TRAWLER_MAST, TRAWLER_LANTERN), GlowBuilder.LED, 0.22, 7.0, true, 0.0, Vector3.ZERO, 0.0)
		return gb.commit())


## Trawling: green over white all round, and the working deck floodlit from the
## gantry and the back of the wheelhouse.
static func trawler_working_lights() -> ArrayMesh:
	return _cached("trawler_working", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(TRAWLER_MAST_GREEN, TRAWLER_LANTERN), GlowBuilder.GREEN, 0.24, 7.0, true, 0.0, Vector3.ZERO, 0.0)
		gb.glow(lantern_glow_at(TRAWLER_MAST, TRAWLER_LANTERN), GlowBuilder.LED, 0.22, 7.0, true, 0.0, Vector3.ZERO, 0.0)
		for x: float in [-1.4, 1.4]:
			gb.glow(Vector3(x, TRAWLER_GANTRY_TOP - 0.55, TRAWLER_GANTRY_Z + 0.15), GlowBuilder.LED, 0.3, 6.0, true, 0.0, Vector3(0, -0.5, 1), 0.0)
		gb.glow(Vector3(0, TRAWLER_DECK + 3.7, 1.55), GlowBuilder.LED, 0.28, 5.0, false, 0.0, Vector3(0, -0.4, -1), 0.0)
		gb.pool(Vector3(0, TRAWLER_DECK + 0.05, -5.0), GlowBuilder.LED, 4.2, 0.5, 0.0)
		gb.pool(Vector3(0, 0.05, -12.0), GlowBuilder.LED, 4.0, 0.1, 0.0)
		return gb.commit())


# Motor yacht (+Z is the bow), at the sailboats' scale: about 5.5 m long and
# 1.8 m in the beam, a saloon with a raked windscreen, a flybridge under a bimini,
# and a radar arch carrying its masthead (or, at anchor, anchor) light.
const YACHT_ARCH_TOP := Vector3(0, 2.1, -0.85)
const YACHT_LANTERN := 0.5
const YACHT_SIDELIGHT := Vector3(0.74, 1.4, 0.44)
const YACHT_HULLS := [Color(0.94, 0.95, 0.94), Color(0.1, 0.16, 0.3), Color(0.78, 0.8, 0.82)]
const YACHT_STRIPES := [Color(0.1, 0.2, 0.42), Color(0.94, 0.95, 0.94), Color(0.13, 0.13, 0.15)]
const YACHT_CANVAS := [Color(0.13, 0.22, 0.38), Color(0.82, 0.78, 0.68), Color(0.2, 0.2, 0.22)]
const TEAK := Color(0.62, 0.45, 0.28)
# Sidelight lenses that only shine when the boat shows its lights (the glow is in
# its nav-light mesh, shown under way): plain coloured glass.
const LENS_RED := Color(0.62, 0.1, 0.08)
const LENS_GREEN := Color(0.1, 0.5, 0.24)
const CUSHION := Color(0.88, 0.85, 0.77)


static func _yacht_outline(grow := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-0.82, -2.75), Vector2(0.82, -2.75), Vector2(0.9, -1.8), Vector2(0.9, 0.4),
		Vector2(0.78, 1.5), Vector2(0.45, 2.3), Vector2(0, 2.75), Vector2(-0.45, 2.3), Vector2(-0.78, 1.5),
		Vector2(-0.9, 0.4), Vector2(-0.9, -1.8)])
	if grow != 0.0:
		for i in pts.size():
			pts[i] = pts[i] * Vector2((0.9 + grow) / 0.9, (2.75 + grow) / 2.75)
	return pts


## A flybridge motor yacht; `variant` picks its colours.
static func motor_yacht(variant: int) -> ArrayMesh:
	return _cached("yacht_%d" % variant, func():
		var mb := MeshBuilder.new()
		var hull: Color = YACHT_HULLS[variant % YACHT_HULLS.size()]
		var stripe: Color = YACHT_STRIPES[variant % YACHT_STRIPES.size()]
		var canvas: Color = YACHT_CANVAS[variant % YACHT_CANVAS.size()]
		var deck := Color(0.92, 0.91, 0.87)
		var outline := _yacht_outline()
		mb.extrude(outline, -0.4, 0.05, Color(0.12, 0.14, 0.2), Color(0, 0, 0, 0), 0.5)
		mb.extrude(outline, 0.05, 0.62, hull, deck)
		mb.extrude(_yacht_outline(0.03), 0.12, 0.2, stripe, Color(0, 0, 0, 0))
		# Hull ports for the cabins below, a teak cockpit and swim platform aft.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 0.88, 0.4, 0.55), Vector3(0.05, 0.1, 0.8), WINDOW)
		mb.box(Vector3(0, 0.632, -2.15), Vector3(1.5, 0.02, 1.1), TEAK)
		mb.box(Vector3(0, 0.12, -2.95), Vector3(1.55, 0.07, 0.42), TEAK)
		mb.box(Vector3(0, 0.76, -2.58), Vector3(1.4, 0.28, 0.26), CUSHION)
		# The saloon, windows down its sides and glass doors aft, and its raked
		# windscreen.
		mb.box(Vector3(0, 0.91, -0.45), Vector3(1.5, 0.58, 2.1), WHITE)
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 0.755, 0.95, -0.5), Vector3(0.02, 0.3, 1.8), WINDOW)
			mb.tri(Vector3(x * 0.75, 1.2, 0.6), Vector3(x * 0.75, 0.62, 0.6), Vector3(x * 0.75, 0.62, 1.2), WHITE, Vector3(x, 0, 0))
		mb.box(Vector3(0, 0.92, -1.505), Vector3(1.1, 0.44, 0.02), WINDOW)
		mb.quad(Vector3(-0.75, 1.2, 0.6), Vector3(0.75, 1.2, 0.6), Vector3(0.75, 0.62, 1.2), Vector3(-0.75, 0.62, 1.2),
			GLASS, Vector3(0, 1, 1))
		# The flybridge: deck, screen, helm and seats.
		mb.box(Vector3(0, 1.25, -0.55), Vector3(1.56, 0.1, 2.0), WHITE)
		mb.box(Vector3(0, 1.4, 0.36), Vector3(1.5, 0.22, 0.18), WHITE)
		mb.box(Vector3(0.38, 1.46, 0.12), Vector3(0.42, 0.3, 0.24), WHITE)
		mb.box(Vector3(0.38, 1.62, 0.18), Vector3(0.36, 0.04, 0.14), GLASS)
		mb.box(Vector3(0.38, 1.42, -0.32), Vector3(0.44, 0.24, 0.4), CUSHION)
		mb.box(Vector3(0, 1.4, -1.25), Vector3(1.25, 0.2, 0.42), CUSHION)
		# Sidelights in the screen's corners.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * YACHT_SIDELIGHT.x, YACHT_SIDELIGHT.y, YACHT_SIDELIGHT.z), Vector3(0.06, 0.08, 0.12),
				LENS_RED if x > 0.0 else LENS_GREEN)
		# The radar arch, leaning aft, with the radome and the lantern on top;
		# the bimini forward of it.
		var a_y := YACHT_ARCH_TOP.y - 0.22
		var a_z := YACHT_ARCH_TOP.z
		for x: float in [-1.0, 1.0]:
			var lo := Vector3(x * 0.68, 1.3, a_z + 0.2)
			var hi := Vector3(x * 0.5, a_y, a_z)
			mb.xform = Transform3D(Basis.looking_at(hi - lo), (lo + hi) * 0.5)
			mb.box(Vector3.ZERO, Vector3(0.09, 0.12, lo.distance_to(hi)), WHITE)
			mb.xform = Transform3D.IDENTITY
		mb.box(Vector3(0, a_y, a_z), Vector3(1.1, 0.1, 0.2), WHITE)
		mb.cylinder(Vector3(0, a_y + 0.05, a_z), 0.16, 0.16, 0.12, 8, WHITE)
		add_lantern(mb, YACHT_ARCH_TOP, GlowBuilder.LED, YACHT_LANTERN)
		mb.box(Vector3(0, 1.9, -0.3), Vector3(1.4, 0.04, 1.1), canvas)
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 0.66, 1.62, 0.2), Vector3(0.03, 0.56, 0.03), Color(0.8, 0.8, 0.8))
		# Foredeck: a sunpad, the bow rail and the anchor in its roller.
		mb.box(Vector3(0, 0.67, 1.55), Vector3(0.9, 0.08, 0.6), CUSHION)
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 0.6, 0.85, 1.7), Vector3(0.03, 0.03, 1.5), Color(0.82, 0.82, 0.82))
		mb.box(Vector3(0, 0.66, 2.55), Vector3(0.12, 0.06, 0.34), Color(0.5, 0.52, 0.54))
		mb.box(Vector3(0, 0.45, -2.76), Vector3(0.1, 0.06, 0.03), lamp_glass(GlowBuilder.LED))
		return mb.commit())


## The anchor's rode, out from the bow roller and down into the water ahead
## (shown at anchor).
static func motor_yacht_rode() -> ArrayMesh:
	return _cached("yacht_rode", func():
		var mb := MeshBuilder.new()
		var a := Vector3(0, 0.62, 2.72)
		var b := Vector3(0, -0.5, 4.3)
		mb.xform = Transform3D(Basis.looking_at(b - a), (a + b) * 0.5)
		mb.box(Vector3.ZERO, Vector3(0.04, 0.04, a.distance_to(b)), Color(0.3, 0.3, 0.32))
		return mb.commit())


## The lit saloon's reflection, drawn by NightLights on each motor yacht.
static func motor_yacht_lights() -> ArrayMesh:
	return _cached("yacht_lights", func():
		var gb := GlowBuilder.new()
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-0.78, 0.78]:
			for i in 2:
				gb.reflection(Vector3(x, 0.95, -1.0 + i * 0.8), window, 0.12, 1.2, Vector3(signf(x), 0, 0))
		return gb.commit())


## Sidelights and stern light, shown under way.
static func motor_yacht_nav_lights() -> ArrayMesh:
	return _cached("yacht_nav", func():
		var gb := GlowBuilder.new()
		gb.glow(YACHT_SIDELIGHT + Vector3(0.02, 0, 0.04), GlowBuilder.RED, 0.1, 4.0, true, 0.0, Vector3(1, 0, 0.8), 0.0)
		gb.glow(Vector3(-YACHT_SIDELIGHT.x - 0.02, YACHT_SIDELIGHT.y, YACHT_SIDELIGHT.z + 0.04), GlowBuilder.GREEN, 0.1, 4.0, true, 0.0, Vector3(-1, 0, 0.8), 0.0)
		gb.glow(Vector3(0, 0.45, -2.8), GlowBuilder.LED, 0.08, 3.0, true, 0.0, Vector3(0, 0, -1), 0.0)
		return gb.commit())


## The light on the arch: the masthead light under way, the anchor light at anchor.
static func motor_yacht_mast_light() -> ArrayMesh:
	return _cached("yacht_mast", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(YACHT_ARCH_TOP, YACHT_LANTERN), GlowBuilder.LED, 0.12, 4.5, true, 0.0, Vector3.ZERO, 0.0)
		return gb.commit())


# Pilot boat (+Z is the bow): about 9 m long and 3 m in the beam, heavily fendered
# to lie against a ship's side, the deckhouse forward and its mast carrying the
# pilot vessel's lights (white over red).
const PILOT_WHITE := Vector3(0, 3.95, 0.7)
const PILOT_RED := Vector3(0, 3.5, 0.7)
const PILOT_LANTERN := 0.9
const PILOT_SIDELIGHT := Vector3(1.13, 1.75, 1.8)
const PILOT_HULLS := [Color(0.08, 0.08, 0.09), Color(0.86, 0.33, 0.1), Color(0.1, 0.15, 0.28)]
const PILOT_TOPS := [Color(0.9, 0.4, 0.1), Color(0.94, 0.95, 0.94), Color(0.9, 0.4, 0.1)]


static func _pilot_outline(grow := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-1.4, -4.5), Vector2(1.4, -4.5), Vector2(1.5, -3.5), Vector2(1.5, 1.0),
		Vector2(1.3, 2.6), Vector2(0.75, 3.8), Vector2(0, 4.5), Vector2(-0.75, 3.8), Vector2(-1.3, 2.6),
		Vector2(-1.5, 1.0), Vector2(-1.5, -3.5)])
	if grow != 0.0:
		for i in pts.size():
			pts[i] = pts[i] * Vector2((1.5 + grow) / 1.5, (4.5 + grow) / 4.5)
	return pts


## A pilot boat; `variant` picks its colours.
static func pilot_boat(variant: int) -> ArrayMesh:
	return _cached("pilot_%d" % variant, func():
		var mb := MeshBuilder.new()
		var hull: Color = PILOT_HULLS[variant % PILOT_HULLS.size()]
		var top: Color = PILOT_TOPS[variant % PILOT_TOPS.size()]
		var deck := Color(0.4, 0.42, 0.42)
		var fender := Color(0.06, 0.06, 0.07)
		var outline := _pilot_outline()
		mb.extrude(outline, -0.8, 0.05, Color(0.5, 0.14, 0.12), Color(0, 0, 0, 0), 0.55)
		mb.extrude(outline, 0.05, 0.95, hull, deck)
		# The heavy rubber fender all round the gunwale.
		mb.extrude(_pilot_outline(0.14), 0.62, 0.95, fender, Color(0, 0, 0, 0))
		mb.extrude(_pilot_outline(0.04), 0.1, 0.18, WHITE, Color(0, 0, 0, 0))
		# Deckhouse, windows all round, and the roof in the station's colour with a
		# rail round it.
		mb.box(Vector3(0, 1.6, 0.4), Vector3(2.2, 1.3, 3.4), WHITE)
		mb.box(Vector3(0, 1.85, 0.4), Vector3(2.24, 0.48, 3.44), WINDOW_LIT)
		mb.box(Vector3(0, 2.3, 0.4), Vector3(2.4, 0.12, 3.6), top)
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 1.1, 2.6, 0.4), Vector3(0.05, 0.05, 3.2), WHITE)
		mb.box(Vector3(0, 2.6, -1.25), Vector3(2.2, 0.05, 0.05), WHITE)
		mb.box(Vector3(0, 2.6, 2.05), Vector3(2.2, 0.05, 0.05), WHITE)
		# A band of the top colour round the hull below the fender.
		mb.extrude(_pilot_outline(0.02), 0.38, 0.55, top, Color(0, 0, 0, 0))
		# Sidelights on the deckhouse's forward corners.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * PILOT_SIDELIGHT.x, PILOT_SIDELIGHT.y, PILOT_SIDELIGHT.z), Vector3(0.06, 0.16, 0.24),
				LENS_RED if x > 0.0 else LENS_GREEN)
		# The mast: radar, then the pilot's red and white lanterns.
		mb.box(Vector3(0, (2.36 + PILOT_WHITE.y) * 0.5, PILOT_WHITE.z), Vector3(0.12, PILOT_WHITE.y - 2.36, 0.12), WHITE)
		mb.box(Vector3(0, 3.05, PILOT_WHITE.z), Vector3(1.4, 0.08, 0.26), WHITE)
		mb.box(Vector3(0, 3.2, PILOT_WHITE.z), Vector3(0.8, 0.06, 0.08), Color(0.2, 0.2, 0.22))
		add_lantern(mb, PILOT_RED, GlowBuilder.RED, PILOT_LANTERN)
		add_lantern(mb, PILOT_WHITE, GlowBuilder.LED, PILOT_LANTERN)
		# Foredeck rails where the pilot steps across, a bitt aft and the stern light.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 1.05, 1.35, 3.0), Vector3(0.05, 0.05, 1.6), WHITE)
			for z: float in [2.3, 3.0, 3.7]:
				mb.box(Vector3(x * 1.05 * (1.0 - (z - 2.3) * 0.3), 1.15, z), Vector3(0.05, 0.4, 0.05), WHITE)
		mb.cylinder(Vector3(0, 0.95, -3.4), 0.14, 0.14, 0.35, 8, Color(0.2, 0.2, 0.22))
		mb.cylinder(Vector3(0.6, 0.95, -2.4), 0.3, 0.3, 0.5, 8, WHITE)
		mb.box(Vector3(0, 0.8, -4.52), Vector3(0.14, 0.1, 0.04), lamp_glass(GlowBuilder.LED))
		return mb.commit())


## The ship's pilot ladder, hung over its side down to just above the pilot
## boat's deck, in the boat's frame with the ship's side `out` metres to
## starboard (+X) and its deck `deck` metres up.
static func pilot_ladder(out: float, deck: float) -> ArrayMesh:
	return _cached("pilot_ladder_%.2f_%.2f" % [out, deck], func():
		var mb := MeshBuilder.new()
		var rope := Color(0.75, 0.66, 0.48)
		var foot := 1.45
		# Abreast of the foredeck, where the boat's boarding rails are.
		var z := 2.9
		for dz: float in [-0.25, 0.25]:
			mb.box(Vector3(out - 0.04, (deck + foot) * 0.5, z + dz), Vector3(0.04, deck - foot, 0.04), rope)
		var y := foot + 0.1
		while y < deck - 0.1:
			mb.box(Vector3(out - 0.05, y, z), Vector3(0.06, 0.05, 0.62), Color(0.55, 0.36, 0.2))
			y += 0.33
		# The pilot, stepping across from the foredeck in a hi-vis jacket.
		var px := out - 0.45
		mb.box(Vector3(px, 1.35, z), Vector3(0.24, 0.5, 0.22), Color(0.12, 0.13, 0.18))
		mb.box(Vector3(px, 1.78, z), Vector3(0.3, 0.38, 0.26), Color(0.95, 0.5, 0.1))
		mb.box(Vector3(px, 2.07, z), Vector3(0.18, 0.18, 0.18), Color(0.85, 0.65, 0.5))
		return mb.commit())


static func pilot_boat_lights() -> ArrayMesh:
	return _cached("pilot_lights", func():
		var gb := GlowBuilder.new()
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-1.15, 1.15]:
			for i in 3:
				gb.reflection(Vector3(x, 1.85, -0.6 + i), window, 0.16, 1.4, Vector3(signf(x), 0, 0))
		return gb.commit())


## Sidelights and stern light, shown under way.
static func pilot_boat_nav_lights() -> ArrayMesh:
	return _cached("pilot_nav", func():
		var gb := GlowBuilder.new()
		gb.glow(PILOT_SIDELIGHT + Vector3(0.04, 0, 0.1), GlowBuilder.RED, 0.15, 5.0, true, 0.0, Vector3(1, 0, 0.8), 0.0)
		gb.glow(Vector3(-PILOT_SIDELIGHT.x - 0.04, PILOT_SIDELIGHT.y, PILOT_SIDELIGHT.z + 0.1), GlowBuilder.GREEN, 0.15, 5.0, true, 0.0, Vector3(-1, 0, 0.8), 0.0)
		gb.glow(Vector3(0, 0.8, -4.56), GlowBuilder.LED, 0.1, 3.5, true, 0.0, Vector3(0, 0, -1), 0.0)
		return gb.commit())


## On pilotage duty: white over red, all round.
static func pilot_boat_duty_lights() -> ArrayMesh:
	return _cached("pilot_duty", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(PILOT_WHITE, PILOT_LANTERN), GlowBuilder.LED, 0.17, 6.0, true, 0.0, Vector3.ZERO, 0.0)
		gb.glow(lantern_glow_at(PILOT_RED, PILOT_LANTERN), GlowBuilder.RED, 0.17, 6.0, true, 0.0, Vector3.ZERO, 0.0)
		return gb.commit())


# Tug (+Z is the bow): about 14 m long and 5 m in the beam, heavily fendered, the
# wheelhouse high on its deckhouse forward, the stack behind it and the towing
# winch and staple on the after deck.
const TUG_MAST := Vector3(0, 7.7, 1.4)
const TUG_LANTERN := 1.1
const TUG_SIDELIGHT := Vector3(1.56, 4.7, 2.9)
const TUG_HULLS := [Color(0.1, 0.1, 0.11), Color(0.62, 0.15, 0.12), Color(0.13, 0.22, 0.36)]
const TUG_HOUSES := [Color(0.94, 0.95, 0.94), Color(0.94, 0.95, 0.94), Color(0.9, 0.84, 0.62)]
const TUG_STACKS := [Color(0.86, 0.33, 0.1), Color(0.1, 0.1, 0.11), Color(0.75, 0.15, 0.13)]


static func _tug_outline(grow := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-2.2, -7), Vector2(2.2, -7), Vector2(2.5, -5.5), Vector2(2.5, 2.0),
		Vector2(2.2, 4.5), Vector2(1.4, 6.3), Vector2(0, 7), Vector2(-1.4, 6.3), Vector2(-2.2, 4.5),
		Vector2(-2.5, 2.0), Vector2(-2.5, -5.5)])
	if grow != 0.0:
		for i in pts.size():
			pts[i] = pts[i] * Vector2((2.5 + grow) / 2.5, (7.0 + grow) / 7.0)
	return pts


## A tug; `variant` picks its colours.
static func tug(variant: int) -> ArrayMesh:
	return _cached("tug_%d" % variant, func():
		var mb := MeshBuilder.new()
		var hull: Color = TUG_HULLS[variant % TUG_HULLS.size()]
		var house: Color = TUG_HOUSES[variant % TUG_HOUSES.size()]
		var stack: Color = TUG_STACKS[variant % TUG_STACKS.size()]
		var deck := Color(0.36, 0.37, 0.37)
		var fender := Color(0.06, 0.06, 0.07)
		var steel := Color(0.25, 0.26, 0.28)
		var outline := _tug_outline()
		mb.extrude(outline, -2.2, 0.05, Color(0.55, 0.14, 0.12), Color(0, 0, 0, 0), 0.65)
		mb.extrude(outline, 0.05, 1.3, hull, deck)
		mb.extrude(_tug_outline(0.04), 0.95, 1.08, WHITE, Color(0, 0, 0, 0))
		# Fendering all round, and the big bow fender for pushing.
		mb.extrude(_tug_outline(0.3), 0.35, 1.0, fender, Color(0, 0, 0, 0))
		mb.box(Vector3(0, 1.1, 6.75), Vector3(2.4, 1.3, 0.9), fender)
		# Bulwarks down the sides, a white cap on them.
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 2.42, 1.6, -1.8), Vector3(0.14, 0.6, 9.4), hull)
			mb.box(Vector3(x * 2.42, 1.92, -1.8), Vector3(0.2, 0.06, 9.4), WHITE)
		# The deckhouse, the wheelhouse high on it with windows all round, and the
		# mast on its roof.
		mb.box(Vector3(0, 2.4, 1.6), Vector3(3.6, 2.2, 5.0), house)
		mb.box(Vector3(0, 2.6, 1.6), Vector3(3.64, 0.5, 4.2), WINDOW)
		mb.box(Vector3(0, 4.4, 2.2), Vector3(3.0, 1.8, 2.6), house)
		mb.box(Vector3(0, 4.62, 2.2), Vector3(3.06, 0.7, 2.66), WINDOW_LIT)
		mb.box(Vector3(0, 5.36, 2.2), Vector3(3.5, 0.12, 3.1), house)
		for x: float in [-1.0, 1.0]:
			var sl := Vector3(x * TUG_SIDELIGHT.x, TUG_SIDELIGHT.y, TUG_SIDELIGHT.z)
			mb.box(sl + Vector3(0, 0, -0.25), Vector3(0.3, 0.34, 0.06), LAMP_DARK)
			mb.box(sl, Vector3(0.12, 0.24, 0.3), LENS_RED if x > 0.0 else LENS_GREEN)
		mb.box(Vector3(0, (5.42 + TUG_MAST.y) * 0.5, TUG_MAST.z), Vector3(0.16, TUG_MAST.y - 5.42, 0.16), house)
		mb.box(Vector3(0, 6.3, TUG_MAST.z), Vector3(2.4, 0.1, 0.3), house)
		mb.box(Vector3(0, 6.45, TUG_MAST.z), Vector3(1.2, 0.06, 0.1), Color(0.2, 0.2, 0.22))
		add_lantern(mb, TUG_MAST, GlowBuilder.LED, TUG_LANTERN)
		# The stack, behind the wheelhouse.
		mb.box(Vector3(0, 3.9, -1.5), Vector3(1.3, 2.6, 1.4), stack)
		mb.box(Vector3(0, 5.25, -1.5), Vector3(1.32, 0.3, 1.42), Color(0.08, 0.08, 0.08))
		mb.box(Vector3(0, 4.2, -1.5), Vector3(1.34, 0.3, 1.44), WHITE)
		# Towing winch and the staple over the after deck, bitts either side.
		mb.box(Vector3(0, 1.8, -3.6), Vector3(2.2, 1.0, 1.3), steel)
		mb.cylinder(Vector3(0, 1.55, -3.6), 0.5, 0.5, 0.5, 10, Color(0.75, 0.6, 0.18))
		for x: float in [-1.0, 1.0]:
			mb.box(Vector3(x * 1.9, 2.4, -5.8), Vector3(0.3, 2.2, 0.3), stack)
			mb.cylinder(Vector3(x * 1.4, 1.3, -6.3), 0.2, 0.2, 0.5, 8, steel)
		mb.box(Vector3(0, 3.5, -5.8), Vector3(4.1, 0.3, 0.3), stack)
		mb.box(Vector3(0, 1.4, -7.02), Vector3(0.18, 0.14, 0.04), lamp_glass(GlowBuilder.LED))
		return mb.commit())


static func tug_lights() -> ArrayMesh:
	return _cached("tug_lights", func():
		var gb := GlowBuilder.new()
		var window := Color(1.0, 0.74, 0.42)
		for x: float in [-1.55, 1.55]:
			for i in 3:
				gb.reflection(Vector3(x, 4.62, 1.3 + i * 0.9), window, 0.2, 1.6, Vector3(signf(x), 0, 0))
		for i in 3:
			gb.reflection(Vector3(-1.0 + i, 4.62, 3.55), window, 0.2, 1.6, Vector3(0, 0, 1))
		return gb.commit())


## Sidelights and stern light, shown under way.
static func tug_nav_lights() -> ArrayMesh:
	return _cached("tug_nav", func():
		var gb := GlowBuilder.new()
		gb.glow(Vector3(TUG_SIDELIGHT.x, TUG_SIDELIGHT.y, TUG_SIDELIGHT.z + 0.1), GlowBuilder.RED, 0.18, 6.0, true, 0.0, Vector3(1, 0, 0.8), 0.0)
		gb.glow(Vector3(-TUG_SIDELIGHT.x, TUG_SIDELIGHT.y, TUG_SIDELIGHT.z + 0.1), GlowBuilder.GREEN, 0.18, 6.0, true, 0.0, Vector3(-1, 0, 0.8), 0.0)
		gb.glow(Vector3(0, 1.4, -7.08), GlowBuilder.LED, 0.12, 4.0, true, 0.0, Vector3(0, 0, -1), 0.0)
		return gb.commit())


## The masthead light, shown under way.
static func tug_mast_light() -> ArrayMesh:
	return _cached("tug_mast", func():
		var gb := GlowBuilder.new()
		gb.glow(lantern_glow_at(TUG_MAST, TUG_LANTERN), GlowBuilder.LED, 0.2, 7.0, true, 0.0, Vector3.ZERO, 0.0)
		return gb.commit())


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

