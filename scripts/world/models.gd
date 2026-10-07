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
# Ferry fixture scales the glows were tuned at (FerryClass places them).
const FERRY_LANTERN := 1.2
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
		# Each slope is a slab with some thickness, so the roof still reads when
		# seen edge-on from the gable end.
		_roof_slope(mb, l0, t0, hz, roof)
		_roof_slope(mb, r0, t0, hz, roof)
		mb.quad(l0, r0, r1, l1, roof.darkened(0.4), Vector3.DOWN)
		mb.tri(Vector3(-1.4, y0, 1.7), Vector3(1.4, y0, 1.7), Vector3(0, y1 - 0.2, 1.7), wall, Vector3.BACK)
		mb.tri(Vector3(-1.4, y0, -1.7), Vector3(1.4, y0, -1.7), Vector3(0, y1 - 0.2, -1.7), wall, Vector3.FORWARD)
		mb.box(Vector3(0.8, y1 - 0.2, -0.7), Vector3(0.45, 1.2, 0.45), Color(0.55, 0.3, 0.24))
		add_bulkhead_lamp(mb, HOUSE_LAMP, Vector3.BACK, Color(1.0, 0.7, 0.4), HOUSE_LAMP_SCALE, LAMP_DARK)
		return mb.commit())


## One slope of a gable roof, eave to ridge (both at -z), running to +z and
## `thick` deep below its top face.
static func _roof_slope(mb: MeshBuilder, eave: Vector3, ridge: Vector3, hz: float, col: Color, thick := 0.15) -> void:
	var n := Vector3(eave.x - ridge.x, 0, 0).normalized() * (ridge.y - eave.y) + Vector3(0, absf(eave.x - ridge.x), 0)
	n = n.normalized()
	var z := Vector3(0, 0, hz * 2.0)
	var e := eave - n * thick
	var r := ridge - n * thick
	var under := col.darkened(0.4)
	mb.quad(eave, ridge, ridge + z, eave + z, col, n)
	mb.quad(e, r, r + z, e + z, under, -n)
	mb.quad(eave, eave + z, e + z, e, col.darkened(0.15), eave - ridge)
	mb.quad(eave, ridge, r, e, col.darkened(0.15), Vector3.FORWARD)
	mb.quad(eave + z, ridge + z, r + z, e + z, col.darkened(0.15), Vector3.BACK)


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


## Double-ended car ferry of class `fc` (see FerryClass). +Z and -Z ends are
## identical; car deck top at DECK_Y.
static func ferry(fc: FerryClass) -> ArrayMesh:
	return _cached("ferry_%d" % fc.size, func():
		var mb := MeshBuilder.new()
		var b := fc.half_beam
		var l := fc.half_length
		var hull := PackedVector2Array([Vector2(-b, -(l - fc.chamfer)), Vector2(-(b - fc.end_in), -l),
			Vector2(b - fc.end_in, -l), Vector2(b, -(l - fc.chamfer)), Vector2(b, l - fc.chamfer),
			Vector2(b - fc.end_in, l), Vector2(-(b - fc.end_in), l), Vector2(-b, l - fc.chamfer)])
		if fc.portal:
			# Dark to the deck, the green running up the bulwarks.
			mb.extrude(hull, -1.4, 0.55, HULL_DARK, Color(0, 0, 0, 0), 0.8)
			mb.extrude(hull, 0.55, 0.95, WSF_GREEN, Color(0.42, 0.44, 0.47))
		else:
			mb.extrude(hull, -1.4, 0.15, HULL_DARK, Color(0, 0, 0, 0), 0.8)
			mb.extrude(hull, 0.15, 0.55, WSF_GREEN, Color(0, 0, 0, 0))
			mb.extrude(hull, 0.55, 0.95, WHITE, Color(0.42, 0.44, 0.47))
		if fc.open_deck:
			_open_ferry(mb, fc)
		elif fc.portal:
			_portal_ferry(mb, fc)
		else:
			_full_ferry(mb, fc)
		for p in fc.lanterns:
			add_lantern(mb, p, GlowBuilder.LED, fc.lantern_scale)
		for sl: Array in fc.sidelights:
			add_sidelight(mb, sl[0], sl[1], sl[2], fc.sidelight_scale)
		for lp: Array in fc.lamps:
			add_bulkhead_lamp(mb, lp[0], lp[1], GlowBuilder.WARM, fc.lamp_scale)
		return mb.commit())


## Sizes 3-5: an enclosed car deck with open galleries above, a passenger deck over
## it all, a sun-deck cabin, wheelhouses at both ends and the funnel(s) amidships.
static func _full_ferry(mb: MeshBuilder, fc: FerryClass) -> void:
	var b := fc.half_beam
	var l := fc.half_length
	mb.box(Vector3(0, 1.0, 0), Vector3(2.0 * b - 0.6, 0.1, 2.0 * (l - 3.0)), Color(0.45, 0.47, 0.5))
	# Car deck side walls with an open gallery above.
	for x: float in [-(b - 0.15), b - 0.15]:
		mb.box(Vector3(x, 1.7, 0), Vector3(0.3, 1.3, 2.0 * (l - 4.5)), WHITE)
		for z in fc.gallery:
			mb.box(Vector3(x, 2.8, z), Vector3(0.3, 1.0, 0.4), WHITE)
	# Passenger deck
	mb.box(Vector3(0, 3.35, 0), Vector3(2.0 * b + 0.35, 0.3, 2.0 * (l - 4.9)), WSF_GREEN)
	mb.box(Vector3(0, 4.3, 0), Vector3(2.0 * b + 0.2, 1.6, 2.0 * (l - 5.0)), WHITE)
	mb.box(Vector3(0, 4.4, 0), Vector3(2.0 * b + 0.3, 0.6, 2.0 * (l - 5.8)), WINDOW_LIT)
	# Sun deck and upper cabin
	mb.box(Vector3(0, 5.7, 0), Vector3(2.0 * b - 2.0, 1.2, 2.0 * fc.sun_half), WHITE)
	mb.box(Vector3(0, 5.8, 0), Vector3(2.0 * b - 1.9, 0.45, 2.0 * fc.sun_half - 1.4), WINDOW_LIT)
	# Wheelhouses at both ends
	var ww := 2.0 * fc.wheel_half_w
	for z: float in [-fc.wheel_z, fc.wheel_z]:
		mb.box(Vector3(0, 6.85, z), Vector3(ww, 1.1, 2.4), WHITE)
		mb.box(Vector3(0, 6.95, z), Vector3(ww + 0.1, 0.45, 2.5), WINDOW_LIT)
		mb.box(Vector3(0, 8.3, z), Vector3(0.15, 1.8, 0.15), WHITE)
	# Funnels
	for z in fc.funnels:
		mb.box(Vector3(0, 7.4, z), Vector3(1.6, 2.2, 2.6), WHITE)
		mb.box(Vector3(0, 8.35, z), Vector3(1.65, 0.35, 2.65), WSF_GREEN)
		mb.box(Vector3(0, 8.8, z), Vector3(1.7, 0.5, 2.7), Color(0.1, 0.1, 0.1))
	# Lifeboats
	for x: float in [-(b - 0.7), b - 0.7]:
		for z in fc.lifeboats:
			mb.box(Vector3(x, 6.5, z), Vector3(0.8, 0.5, 2.2), Color(0.95, 0.45, 0.12))


## The car deck of sizes 1 and 2, open to the sky at the ends: between bulwarks,
## with lane stripes down it.
static func _open_car_deck(mb: MeshBuilder, fc: FerryClass, bulwark := WHITE) -> void:
	var b := fc.half_beam
	var l := fc.half_length
	var deck_col := Color(0.45, 0.47, 0.5)
	var deck_l := l - 2.4
	mb.box(Vector3(0, 1.0, 0), Vector3(2.0 * b - 0.4, 0.1, 2.0 * deck_l), deck_col)
	for z: float in [-1.0, 1.0]:
		mb.box(Vector3(0, 0.99, z * (deck_l + 1.1)), Vector3(2.0 * (b - fc.end_in) - 0.2, 0.08, 2.2), deck_col)
	# Lane stripes, stopping short of the ends.
	for c in range(fc.cols.size() - 1):
		var x := (fc.cols[c] + fc.cols[c + 1]) * 0.5
		mb.box(Vector3(x, 1.06, 0), Vector3(0.06, 0.02, 2.0 * deck_l - 1.0), Color(0.9, 0.9, 0.85))
	# Bulwarks along both sides, open at the ends for the cars, with a life ring.
	var bl := l - fc.chamfer + 0.3
	for x: float in [-1.0, 1.0]:
		mb.box(Vector3(x * (b - 0.12), 1.45, 0), Vector3(0.24, 0.9, 2.0 * bl), bulwark)
		mb.box(Vector3(x * (b - 0.12), 1.92, 0), Vector3(0.3, 0.06, 2.0 * bl), bulwark.lightened(0.15))
		for z: float in [-1.0, 1.0]:
			mb.box(Vector3(x * (b + 0.01), 1.4, z * (bl - 1.2)), Vector3(0.06, 0.5, 0.5), Color(0.95, 0.45, 0.12))


## Size 1: the open car deck, the wheelhouse up on a stair column on the +X side
## and the exhaust stack standing against the -X bulwark.
static func _open_ferry(mb: MeshBuilder, fc: FerryClass) -> void:
	_open_car_deck(mb, fc)
	# Posts for the deck lamps on the -X side.
	for lp: Array in fc.lamps:
		var p: Vector3 = lp[0]
		if p.x < 0.0:
			mb.box(Vector3(p.x - 0.03, 2.0, p.z), Vector3(0.16, 2.0, 0.16), WHITE)
	# The house.
	var hx := fc.house_x
	var hw := fc.house_half_w
	var wy := fc.wheel_y
	var whw := fc.wheel_half_w_open()
	# Stair column, with a door at deck level and a railed landing halfway.
	mb.box(Vector3(hx, (1.0 + wy) * 0.5, 0), Vector3(2.0 * hw, wy - 1.0, 2.0 * fc.house_half_len), WHITE)
	mb.box(Vector3(hx - hw - 0.01, 1.85, 0), Vector3(0.04, 1.5, 0.7), Color(0.55, 0.57, 0.6))
	mb.box(Vector3(hx, 2.6, 0), Vector3(2.0 * hw + 0.5, 0.08, 2.0 * fc.house_half_len + 0.5), WSF_GREEN)
	# Wheelhouse, with windows all round, and its mast.
	var top := wy + fc.wheel_h
	mb.box(Vector3(hx, wy + 0.04, 0), Vector3(2.0 * whw + 0.3, 0.08, 2.0 * fc.wheel_half_len + 0.3), WSF_GREEN)
	mb.box(Vector3(hx, wy + fc.wheel_h * 0.5, 0), Vector3(2.0 * whw, fc.wheel_h, 2.0 * fc.wheel_half_len), WHITE)
	mb.box(Vector3(hx, wy + 0.75, 0), Vector3(2.0 * whw + 0.1, 0.42, 2.0 * fc.wheel_half_len + 0.1), WINDOW_LIT)
	mb.box(Vector3(hx, top + 0.03, 0), Vector3(2.0 * whw + 0.2, 0.06, 2.0 * fc.wheel_half_len + 0.2), WHITE)
	mb.box(Vector3(hx, top + 0.75, 0), Vector3(0.12, 1.5, 0.12), WHITE)
	mb.box(Vector3(hx, top + 1.0, 0), Vector3(0.9, 0.06, 0.06), WHITE)
	# Exhaust stack against the far bulwark.
	var sx := fc.stack_x
	mb.box(Vector3(sx, 1.6, 0), Vector3(0.6, 1.2, 1.0), WHITE)
	mb.cylinder(Vector3(sx, 2.2, 0), 0.2, 0.2, fc.stack_top - 2.6, 6, Color(0.3, 0.3, 0.32))
	mb.cylinder(Vector3(sx, fc.stack_top - 0.4, 0), 0.22, 0.22, 0.4, 6, Color(0.1, 0.1, 0.1))


## Size 2, after the M/V Hiyu: the open car deck runs through a portal amidships.
## Passenger cabins sit over the two outer lanes on slim pillars, a bridge spans
## the tall centre lane between them, and the upper deck on top, railed all round,
## carries the double-ended pilothouse, the stacks, a rescue boat and life rafts.
static func _portal_ferry(mb: MeshBuilder, fc: FerryClass) -> void:
	_open_car_deck(mb, fc, WSF_GREEN)
	var b := fc.half_beam
	var hl := fc.house_half_len
	var si := fc.side_in
	var lo := fc.low_y
	var ct := fc.cabin_top
	var dark := Color(0.2, 0.21, 0.23)
	var sign_y := Color(0.95, 0.78, 0.15)
	for x: float in [-1.0, 1.0]:
		# The outer wall down to the bulwark, shorter than the cabin and curving up
		# into its ends, with the car deck's openings in it.
		var ll := fc.low_half_len
		mb.box(Vector3(x * (b - 0.15), (1.9 + lo) * 0.5, 0), Vector3(0.3, lo - 1.9, 2.0 * ll), WHITE)
		for zs: float in [-1.0, 1.0]:
			_fillet(mb, x * (b - 0.3), x * b, zs * ll, zs * hl, 1.9, lo, WHITE)
		var z := -(ll - 0.8)
		while z <= ll - 0.8 + 0.01:
			mb.box(Vector3(x * (b - 0.1), 2.25, z), Vector3(0.3, 0.45, 0.9), dark)
			z += 2.0 * (ll - 0.8) / 3.0
		# The cabin over the outer lane, a green line at its foot, windows down the
		# side, on the inboard face and at the ends.
		var cx := x * (si + b) * 0.5
		mb.box(Vector3(cx, (lo + ct) * 0.5, 0), Vector3(b - si, ct - lo, 2.0 * hl), WHITE)
		mb.box(Vector3(cx, lo + 0.06, 0), Vector3(b - si + 0.04, 0.12, 2.0 * hl + 0.04), WSF_GREEN)
		z = -(hl - 0.9)
		while z <= hl - 0.9 + 0.01:
			mb.box(Vector3(x * b, 3.45, z), Vector3(0.1, 0.55, 1.0), WINDOW)
			z += fc.cabin_window_step()
		for zs: float in [-1.0, 1.0]:
			mb.box(Vector3(x * si, 3.45, zs * (fc.span_half_len + 0.5 * (hl - fc.span_half_len))),
				Vector3(0.1, 0.5, hl - fc.span_half_len - 0.8), WINDOW)
			mb.box(Vector3(x * (b - 0.9), 3.45, zs * hl), Vector3(1.0, 0.55, 0.1), WINDOW)
			# A clearance board on the overhang's end, yellow with black stripes.
			mb.box(Vector3(x * (si + 0.45), lo + 0.15, zs * (hl + 0.01)), Vector3(0.7, 0.2, 0.04), sign_y)
			for k in 3:
				mb.box(Vector3(x * (si + 0.2 + 0.25 * k), lo + 0.15, zs * (hl + 0.02)), Vector3(0.07, 0.2, 0.04), dark)
		# Pillars along the overhang's edge.
		for pz in fc.pillars:
			mb.box(Vector3(x * (si + 0.1), (1.0 + lo) * 0.5, pz), Vector3(0.16, lo - 1.0, 0.16), WHITE)
	# The bridge over the centre lane, with its own clearance board.
	mb.box(Vector3(0, (fc.span_y + ct) * 0.5, 0), Vector3(2.0 * si + 0.02, ct - fc.span_y, 2.0 * fc.span_half_len), WHITE)
	for zs: float in [-1.0, 1.0]:
		mb.box(Vector3(0, fc.span_y + 0.32, zs * (fc.span_half_len + 0.01)), Vector3(1.4, 0.18, 0.04), sign_y)
	# The upper deck over the cabins and the bridge (open over the lane either side
	# of it), edged green and railed all round.
	var floor_col := Color(0.5, 0.52, 0.54)
	for x: float in [-1.0, 1.0]:
		mb.box(Vector3(x * (si + b) * 0.5, ct + 0.04, 0), Vector3(b - si + 0.1, 0.08, 2.0 * hl + 0.1), floor_col)
		mb.box(Vector3(x * (si + b) * 0.5, ct - 0.08, 0), Vector3(b - si + 0.12, 0.16, 2.0 * hl + 0.12), WSF_GREEN)
	mb.box(Vector3(0, ct + 0.04, 0), Vector3(2.0 * si, 0.08, 2.0 * fc.span_half_len + 0.1), floor_col)
	mb.box(Vector3(0, ct - 0.08, 0), Vector3(2.0 * si, 0.16, 2.0 * fc.span_half_len + 0.12), WSF_GREEN)
	var rail := Color(0.12, 0.42, 0.3)
	for x: float in [-1.0, 1.0]:
		_rail(mb, Vector3(x * (b - 0.05), ct, -hl), Vector3(x * (b - 0.05), ct, hl), rail)
		for zs: float in [-1.0, 1.0]:
			_rail(mb, Vector3(x * (b - 0.05), ct, zs * (hl - 0.05)), Vector3(x * si, ct, zs * (hl - 0.05)), rail)
			_rail(mb, Vector3(x * si, ct, zs * (hl - 0.05)), Vector3(x * si, ct, zs * fc.span_half_len), rail)
	for zs: float in [-1.0, 1.0]:
		_rail(mb, Vector3(-si, ct, zs * fc.span_half_len), Vector3(si, ct, zs * fc.span_half_len), rail)
	# The pilothouse, windows all round so it cons either way, and its two masts.
	var wy := fc.wheel_y
	var whw := fc.wheel_half_w
	var wl := fc.wheel_half_len
	var top := wy + fc.wheel_h
	mb.box(Vector3(0, wy + fc.wheel_h * 0.5, 0), Vector3(2.0 * whw, fc.wheel_h, 2.0 * wl), WHITE)
	mb.box(Vector3(0, wy + 0.85, 0), Vector3(2.0 * whw + 0.1, 0.6, 2.0 * wl + 0.1), WINDOW_LIT)
	mb.box(Vector3(0, top - 0.1, 0), Vector3(2.0 * whw + 0.24, 0.2, 2.0 * wl + 0.24), WSF_GREEN)
	mb.box(Vector3(0, top + 0.02, 0), Vector3(2.0 * whw + 0.1, 0.05, 2.0 * wl + 0.1), WHITE)
	for zs: float in [-1.0, 1.0]:
		var mz := zs * fc.mast_z
		mb.box(Vector3(0, (top + fc.mast_top) * 0.5, mz), Vector3(0.12, fc.mast_top - top, 0.12), Color(0.3, 0.3, 0.32))
		mb.box(Vector3(0, top + 0.9, mz), Vector3(1.4, 0.06, 0.06), Color(0.3, 0.3, 0.32))
		mb.box(Vector3(0, top + 1.45, mz), Vector3(0.9, 0.05, 0.08), WHITE)
	mb.box(Vector3(whw - 0.3, top + 0.9, 0), Vector3(0.05, 1.8, 0.05), Color(0.3, 0.3, 0.32))
	# Stacks either side of the pilothouse.
	for x: float in [-1.0, 1.0]:
		var sx := x * fc.stack_dx()
		mb.box(Vector3(sx, ct + 0.35, 0), Vector3(0.6, 0.7, 0.8), WHITE)
		mb.cylinder(Vector3(sx, ct + 0.7, 0), 0.16, 0.16, fc.stack_top - ct - 1.0, 6, Color(0.3, 0.3, 0.32))
		mb.cylinder(Vector3(sx, fc.stack_top - 0.3, 0), 0.18, 0.18, 0.3, 6, Color(0.1, 0.1, 0.1))
	# The rescue boat in its cradle at one end, life-raft canisters at the others.
	var rx := b - 1.0
	mb.box(Vector3(rx, ct + 0.15, -(hl - 1.6)), Vector3(0.6, 0.3, 1.8), Color(0.55, 0.57, 0.6))
	mb.box(Vector3(rx, ct + 0.45, -(hl - 1.6)), Vector3(0.75, 0.3, 2.0), Color(0.95, 0.45, 0.12))
	mb.box(Vector3(rx, ct + 0.58, -(hl - 1.7)), Vector3(0.4, 0.12, 1.0), Color(0.2, 0.2, 0.22))
	for p: Vector3 in [Vector3(rx, 0, hl - 1.4), Vector3(-rx, 0, hl - 1.4), Vector3(-rx, 0, -(hl - 1.4))]:
		mb.cylinder(Vector3(p.x, ct + 0.08, p.z), 0.26, 0.26, 0.5, 6, WHITE)


## A concave fillet between x0 and x1: fills the corner of the (z, y) rectangle from
## (z0, y0) to (z1, y1) that lies off the quarter ellipse centred on (z1, y0), so a
## wall ending at z0 sweeps out under an overhang reaching to z1.
static func _fillet(mb: MeshBuilder, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, col: Color) -> void:
	const STEPS := 5
	var corner := Vector2(z0, y1)
	var centre := Vector2(z1, y0)
	var arc: Array[Vector2] = []
	for i in STEPS + 1:
		var t := PI * 0.5 * i / STEPS
		arc.append(Vector2(z1 - (z1 - z0) * cos(t), y0 + (y1 - y0) * sin(t)))
	var out_x := Vector3(signf(x1 - x0), 0, 0)
	for i in STEPS:
		var a := arc[i]
		var c := arc[i + 1]
		for side: Array in [[x0, -out_x], [x1, out_x]]:
			var x: float = side[0]
			mb.tri(Vector3(x, corner.y, corner.x), Vector3(x, a.y, a.x), Vector3(x, c.y, c.x), col, side[1])
		var m := (a + c) * 0.5
		var out := Vector3(0, centre.y - m.y, centre.x - m.x)
		mb.quad(Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, c.y, c.x), Vector3(x0, c.y, c.x), col, out)


## A railing along the deck from `a` to `b` (level, square to an axis): top and
## middle rails on posts about a metre apart.
static func _rail(mb: MeshBuilder, a: Vector3, b: Vector3, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	var along_x := absf(d.x) > absf(d.z)
	var mid := (a + b) * 0.5
	for h: float in [0.9, 0.5]:
		mb.box(Vector3(mid.x, a.y + h, mid.z), Vector3(len if along_x else 0.05, 0.05, 0.05 if along_x else len), col)
	var n := maxi(1, ceili(len / 1.1))
	for i in n + 1:
		var p := a + d * (float(i) / n)
		mb.box(Vector3(p.x, a.y + 0.45, p.z), Vector3(0.05, 0.9, 0.05), col)


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


## An orca one unit long (+Z forward, nose at z = 0.5), drawn per animal by Cetaceans'
## multimesh and scaled to its length. The dorsal fin's vertices carry alpha < 1:
## cetacean.gdshader raises them to each animal's fin height and sweeps them back (a
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


## A whale or porpoise one unit long (+Z forward, nose at z = 0.5), built like
## the orca for cetacean.gdshader (Cetaceans scales each to its length): rings
## of 8 facets through the stations in `st` ([z, half-width, half-height, centre
## height] nose to tail), each facet coloured by `paint`(station, band, facet)
## where band 0 is the back and 3 the belly.
static func _cetacean_body(mb: MeshBuilder, st: Array, paint: Callable) -> void:
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
			var a := rings[i][k]
			var b := rings[i][(k + 1) % 8]
			var c := rings[i + 1][(k + 1) % 8]
			var d := rings[i + 1][k]
			mb.quad(a, b, c, d, paint.call(i, mini(k, 7 - k), k), (a + b + c + d) * 0.25 - axis)


## A dorsal fin for cetacean.gdshader: its base (alpha 1) stays where it's
## modelled, along the back from `front` to `back` at height `y`; the waist and
## tip (alpha < 1) are raised to the animal's fin height and swept back.
static func _cetacean_fin(mb: MeshBuilder, front: float, back: float, y: float, base: Color, tip: Color) -> void:
	var bf := Vector3(0, y, front)
	var bb := Vector3(0, y, back)
	var mf := Vector3(0, y, lerpf(front, back, 0.3))
	var mback := Vector3(0, y, lerpf(front, back, 0.82))
	var t := Vector3(0, y, lerpf(front, back, 0.62))
	var c0 := Color(base, 1.0)
	var c1 := Color(base.lerp(tip, 0.5), 0.75)
	var c2 := Color(tip, 0.5)
	var w0 := (front - back) * 0.09
	for side: float in [-1.0, 1.0]:
		var w := Vector3(w0 * side, 0, 0)
		var wm := w * 0.5
		var out := Vector3(side, 0, 0)
		mb.tri3(bf + w, bb + w, mback + wm, c0, c0, c1, out)
		mb.tri3(bf + w, mback + wm, mf + wm, c0, c1, c1, out)
		mb.tri3(mf + wm, mback + wm, t, c1, c1, c2, out)
		mb.tri3(bf, bf + w, mf + wm, c0, c0, c1, Vector3(side, 0, 1))
		mb.tri3(bf, mf + wm, mf, c0, c1, c1, Vector3(side, 0, 1))
		mb.tri3(mf, mf + wm, t, c1, c1, c2, Vector3(side, 0, 1))
		mb.tri3(bb, bb + w, mback + wm, c0, c0, c1, Vector3(side, 0, -1))
		mb.tri3(bb, mback + wm, mback, c0, c1, c1, Vector3(side, 0, -1))
		mb.tri3(mback, mback + wm, t, c1, c1, c2, Vector3(side, 0, -1))


## Flukes off the tail stock (root at z `root`), `span` either side, the tips
## back at `tip_z`, notched in the middle. Their undersides are a second skin
## just below, so they can be another colour (a humpback's are mostly white).
static func _flukes(mb: MeshBuilder, root: float, span: float, tip_z: float, top: Color, under: Color) -> void:
	var y := 0.01
	for side: float in [-1.0, 1.0]:
		var r := Vector3(0, y, root)
		var notch := Vector3(0, y, tip_z + 0.025)
		var tip := Vector3(span * side, y - 0.005, tip_z)
		var trail := Vector3(span * 0.33 * side, y, tip_z + 0.01)
		var lead := Vector3(span * 0.45 * side, y, root - (root - tip_z) * 0.45)
		for skin: Array in [[top, 0.0, Vector3.UP], [under, -0.006, Vector3.DOWN]]:
			var o := Vector3(0, skin[1], 0)
			mb.tri(r + o, lead + o, trail + o, skin[0], skin[2])
			mb.tri(lead + o, tip + o, trail + o, skin[0], skin[2])
			mb.tri(r + o, trail + o, notch + o, skin[0], skin[2])


## A flipper from `root` out to `tip`, `chord` long at the root, two-faced like
## the flukes (`top` above, `under` below).
static func _flipper(mb: MeshBuilder, root: Vector3, tip: Vector3, chord: float, top: Color, under: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var s := Vector3(side, 1, 1)
		var a := root * s + Vector3(0, 0, chord * 0.5)
		var b := root * s - Vector3(0, 0, chord * 0.5)
		var t := tip * s
		var m := (root * s).lerp(t, 0.55) + Vector3(0, 0, chord * 0.25)
		for skin: Array in [[top, 0.0, Vector3.UP], [under, -0.004, Vector3.DOWN]]:
			var o := Vector3(0, skin[1], 0)
			mb.tri(a + o, m + o, b + o, skin[0], skin[2])
			mb.tri(m + o, t + o, b + o, skin[0], skin[2])


static func _spots(i: int, k: int, salt: float) -> float:
	return fposmod(sin(i * 12.9898 + k * 78.233 + salt) * 43758.5453, 1.0)


## A humpback: long, knobbly-headed, with a small dorsal fin on a hump, very long
## pale flippers and broad flukes whose undersides are mostly white.
static func humpback() -> ArrayMesh:
	return _cached("humpback", func():
		var mb := MeshBuilder.new()
		var dark := Color(0.09, 0.095, 0.11)
		var grey := Color(0.24, 0.25, 0.27)
		var pale := Color(0.82, 0.82, 0.8)
		var st := [[0.5, 0.0, 0.0, -0.025], [0.46, 0.045, 0.025, -0.012], [0.37, 0.085, 0.055, 0.0],
			[0.22, 0.108, 0.085, 0.0], [0.05, 0.112, 0.093, 0.0], [-0.12, 0.085, 0.08, 0.005],
			[-0.27, 0.048, 0.055, 0.01], [-0.38, 0.02, 0.034, 0.012], [-0.42, 0.0, 0.0, 0.012]]
		_cetacean_body(mb, st, func(i: int, band: int, k: int) -> Color:
			if band == 3 and i >= 1 and i <= 3:
				return pale.darkened(_spots(i, k, 1.0) * 0.25)
			if band == 2 and i <= 3:
				return grey.lerp(pale, 0.35 * _spots(i, k, 2.0))
			if band == 0 and i <= 1:
				# The knobs on its head.
				return dark.lightened(0.12 * _spots(i, k, 3.0))
			return dark if band < 2 else grey)
		_cetacean_fin(mb, -0.06, -0.17, 0.083, dark, dark)
		_flipper(mb, Vector3(0.09, -0.045, 0.24), Vector3(0.36, -0.14, -0.06), 0.12, grey.lerp(pale, 0.5), pale)
		_flukes(mb, -0.38, 0.19, -0.5, dark, pale)
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A gray whale: slimmer, mottled grey with pale patches of barnacles, no dorsal
## fin but a low hump and a row of knuckles down its tail stock.
static func gray_whale() -> ArrayMesh:
	return _cached("gray_whale", func():
		var mb := MeshBuilder.new()
		var base := Color(0.4, 0.42, 0.43)
		var light := Color(0.62, 0.63, 0.61)
		var barnacle := Color(0.8, 0.78, 0.72)
		var st := [[0.5, 0.0, 0.0, -0.03], [0.44, 0.035, 0.035, -0.02], [0.34, 0.065, 0.065, 0.0],
			[0.18, 0.09, 0.085, 0.0], [0.0, 0.095, 0.09, 0.0], [-0.16, 0.075, 0.075, 0.0],
			[-0.3, 0.042, 0.052, 0.006], [-0.4, 0.018, 0.035, 0.01], [-0.44, 0.0, 0.0, 0.01]]
		_cetacean_body(mb, st, func(i: int, band: int, k: int) -> Color:
			var r := _spots(i, k, 7.0)
			if r > 0.86 and band < 3:
				return barnacle
			return base.lerp(light, r * 0.7).darkened(0.08 * band))
		# A low hump, then knuckles along the ridge of the tail stock.
		_cetacean_fin(mb, -0.08, -0.16, 0.08, base, base)
		var z := -0.19
		while z > -0.38:
			var t := (z + 0.16) / -0.24
			var y := lerpf(0.074, 0.044, t)
			mb.tri(Vector3(-0.01, y - 0.004, z + 0.012), Vector3(0.01, y - 0.004, z + 0.012), Vector3(0, y + 0.012, z), base, Vector3(0, 1, 1))
			mb.tri(Vector3(-0.01, y - 0.004, z - 0.012), Vector3(0.01, y - 0.004, z - 0.012), Vector3(0, y + 0.012, z), base, Vector3(0, 1, -1))
			z -= 0.035
		_flipper(mb, Vector3(0.07, -0.05, 0.25), Vector3(0.19, -0.11, 0.12), 0.06, base, light)
		_flukes(mb, -0.39, 0.15, -0.51, base, light)
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A Dall's porpoise: stocky and black with a big white patch on each flank,
## a triangular fin frosted at the tip.
static func dalls_porpoise() -> ArrayMesh:
	return _cached("dalls_porpoise", func():
		var mb := MeshBuilder.new()
		var black := Color(0.04, 0.045, 0.05)
		var white := Color(0.92, 0.93, 0.92)
		var st := [[0.5, 0.0, 0.0, -0.01], [0.45, 0.04, 0.04, 0.0], [0.36, 0.085, 0.085, 0.0],
			[0.18, 0.115, 0.108, 0.0], [0.0, 0.115, 0.11, 0.0], [-0.15, 0.085, 0.09, 0.005],
			[-0.3, 0.035, 0.065, 0.01], [-0.4, 0.015, 0.035, 0.01], [-0.44, 0.0, 0.0, 0.01]]
		_cetacean_body(mb, st, func(i: int, band: int, _k: int) -> Color:
			if band >= 2 and i >= 3 and i <= 4:
				return white
			return black)
		_cetacean_fin(mb, 0.04, -0.12, 0.105, black, Color(0.75, 0.77, 0.78))
		_flipper(mb, Vector3(0.08, -0.06, 0.25), Vector3(0.17, -0.12, 0.15), 0.06, black, black)
		_flukes(mb, -0.38, 0.13, -0.49, black, black)
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A harbor porpoise: small and round-headed, dark grey above, paler below, with
## a little triangular fin.
static func harbor_porpoise() -> ArrayMesh:
	return _cached("harbor_porpoise", func():
		var mb := MeshBuilder.new()
		var dark := Color(0.17, 0.18, 0.2)
		var side := Color(0.42, 0.43, 0.44)
		var belly := Color(0.85, 0.85, 0.83)
		var st := [[0.5, 0.0, 0.0, -0.01], [0.45, 0.045, 0.045, 0.0], [0.35, 0.08, 0.08, 0.0],
			[0.18, 0.1, 0.1, 0.0], [0.0, 0.1, 0.1, 0.0], [-0.16, 0.075, 0.08, 0.0],
			[-0.3, 0.035, 0.05, 0.005], [-0.4, 0.015, 0.03, 0.01], [-0.44, 0.0, 0.0, 0.01]]
		_cetacean_body(mb, st, func(_i: int, band: int, _k: int) -> Color:
			return [dark, dark, side, belly][band])
		_cetacean_fin(mb, 0.02, -0.11, 0.095, dark, dark)
		_flipper(mb, Vector3(0.07, -0.06, 0.25), Vector3(0.16, -0.11, 0.16), 0.05, dark, dark)
		_flukes(mb, -0.38, 0.12, -0.48, dark, dark)
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A seal or sea lion one unit long (+Z forward, nose at z = 0.5) lying on its
## belly, the bottom of its belly at y = 0; drawn per animal by Pinnipeds and
## posed by pinniped.gdshader (head up, hind flippers up, swimming sway or the
## arch of a seal humping along on land). Rings of 8 facets through the stations
## `st` ([z, half-width, half-height, centre height]), coloured by
## `paint`(station, band, facet), band 0 the back and 3 the belly.
static func _pinniped_body(mb: MeshBuilder, st: Array, paint: Callable) -> void:
	_cetacean_body(mb, st, paint)
	# Close off the tail end (the flippers fan out from it).
	var last: Array = st[st.size() - 1]
	if last[1] > 0.0:
		var c := Vector3(0, last[3], last[0] - 0.01)
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			mb.tri(Vector3(last[1] * sin(a0), last[3] + last[2] * cos(a0), last[0]),
				Vector3(last[1] * sin(a1), last[3] + last[2] * cos(a1), last[0]), c, paint.call(st.size() - 2, mini(k, 7 - k), k), Vector3.FORWARD)


## Hind flippers: two webbed fans off the tail, toes spread.
static func _hind_flippers(mb: MeshBuilder, root_z: float, y: float, tip_z: float, spread: float, col: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var r := Vector3(0.012 * side, y, root_z)
		var outer := Vector3(spread * side, y - 0.004, tip_z)
		var inner := Vector3(spread * 0.25 * side, y - 0.004, tip_z + 0.02)
		var mid := Vector3(spread * 0.6 * side, y - 0.002, tip_z + 0.035)
		mb.tri(r, outer, mid, col, Vector3.UP)
		mb.tri(r, mid, inner, col, Vector3.UP)


## An eye on each side of the head, and the nose.
static func _face(mb: MeshBuilder, eye: Vector3, r: float, nose: Vector3) -> void:
	var black := Color(0.03, 0.03, 0.035)
	for side: float in [-1.0, 1.0]:
		var c := Vector3(eye.x * side, eye.y, eye.z)
		var o := Vector3(side * 0.004, 0, 0)
		mb.quad(c + o + Vector3(0, -r, r), c + o + Vector3(0, -r, -r), c + o + Vector3(0, r, -r), c + o + Vector3(0, r, r),
			black, Vector3(side, 0.2, 0.3))
	mb.tri(nose + Vector3(-0.012, 0.004, 0), nose + Vector3(0.012, 0.004, 0), nose + Vector3(0, -0.012, 0.004), black, Vector3(0, 0.3, 1))


## A harbor seal: rotund, no neck to speak of, short flippers, a dog-like face
## with big dark eyes. Pale grey and heavily spotted (the instance colour tints
## it silver, tawny or dark).
static func harbor_seal() -> ArrayMesh:
	return _cached("harbor_seal", func():
		var mb := MeshBuilder.new()
		var coat := Color(0.86, 0.85, 0.82)
		var spot := Color(0.42, 0.41, 0.4)
		var belly := Color(0.95, 0.94, 0.9)
		var st := [[0.5, 0.0, 0.0, 0.07], [0.47, 0.033, 0.028, 0.07], [0.43, 0.052, 0.046, 0.076],
			[0.37, 0.066, 0.058, 0.08], [0.3, 0.08, 0.07, 0.08], [0.18, 0.11, 0.098, 0.098],
			[0.03, 0.124, 0.108, 0.108], [-0.14, 0.1, 0.088, 0.088], [-0.28, 0.058, 0.056, 0.06],
			[-0.37, 0.028, 0.03, 0.046]]
		_pinniped_body(mb, st, func(i: int, band: int, k: int) -> Color:
			if band == 3 and i >= 4:
				return belly
			# Dappled: every facet a little darker or lighter.
			return coat.lerp(spot, _spots(i, k, 11.0) * 0.45) if i >= 2 else coat)
		_face(mb, Vector3(0.042, 0.095, 0.43), 0.011, Vector3(0, 0.072, 0.498))
		_hind_flippers(mb, -0.36, 0.045, -0.52, 0.075, spot)
		# Short fore flippers, tucked along the chest.
		for side: float in [-1.0, 1.0]:
			mb.tri(Vector3(0.1 * side, 0.035, 0.22), Vector3(0.105 * side, 0.03, 0.14),
				Vector3(0.15 * side, 0.004, 0.13), spot, Vector3(side, 1, 0))
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A California sea lion: sleeker, a real neck, a narrow pointed snout with
## little ear flaps, and long fore flippers it props itself up on. Brown, darker
## along the back (the instance colour tints bulls dark, females golden).
static func sea_lion() -> ArrayMesh:
	return _cached("sea_lion", func():
		var mb := MeshBuilder.new()
		var coat := Color(0.86, 0.84, 0.8)
		var back := Color(0.72, 0.7, 0.67)
		var muzzle := Color(0.95, 0.93, 0.88)
		var flipper := Color(0.45, 0.43, 0.42)
		var st := [[0.5, 0.0, 0.0, 0.125], [0.465, 0.022, 0.022, 0.125], [0.41, 0.043, 0.043, 0.132],
			[0.34, 0.05, 0.05, 0.128], [0.26, 0.066, 0.068, 0.11], [0.13, 0.108, 0.1, 0.1],
			[-0.02, 0.112, 0.098, 0.098], [-0.17, 0.082, 0.078, 0.078], [-0.29, 0.044, 0.048, 0.05],
			[-0.35, 0.024, 0.028, 0.034]]
		_pinniped_body(mb, st, func(i: int, band: int, _k: int) -> Color:
			if i <= 1:
				return muzzle
			return back if band == 0 else coat)
		_face(mb, Vector3(0.038, 0.148, 0.415), 0.009, Vector3(0, 0.128, 0.497))
		# Ear flaps.
		for side: float in [-1.0, 1.0]:
			mb.tri(Vector3(0.045 * side, 0.16, 0.36), Vector3(0.05 * side, 0.165, 0.345),
				Vector3(0.055 * side, 0.15, 0.335), flipper, Vector3(side, 0, -1))
		_hind_flippers(mb, -0.34, 0.03, -0.5, 0.07, flipper)
		# Long fore flippers, out to the side and down to the ground.
		for side: float in [-1.0, 1.0]:
			var r0 := Vector3(0.095 * side, 0.05, 0.17)
			var r1 := Vector3(0.1 * side, 0.045, 0.07)
			var tip := Vector3(0.25 * side, 0.0, -0.02)
			var mid := Vector3(0.18 * side, 0.015, 0.1)
			mb.tri(r0, mid, r1, flipper, Vector3.UP)
			mb.tri(mid, tip, r1, flipper, Vector3.UP)
		var mesh := mb.commit()
		mesh.shadow_mesh = null
		return mesh)


## A blow or a splash: a white plume one unit tall, drawn per puff by Cetaceans.
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


## Lights of ferry class `fc` in the hull's frame: masthead lights, red / green
## sidelights, the deck lamps, and the lit windows' reflections on the water.
static func ferry_lights(fc: FerryClass) -> ArrayMesh:
	return _cached("ferry_lights_%d" % fc.size, func():
		var gb := GlowBuilder.new()
		for p in fc.lanterns:
			gb.glow(lantern_glow_at(p, fc.lantern_scale), GlowBuilder.LED, 0.3 * fc.lantern_scale / FERRY_LANTERN, 9.0, true, 0.0, Vector3.ZERO, 0.0)
		for sl: Array in fc.sidelights:
			gb.nav(sidelight_glow_at(sl[0], sl[1], fc.sidelight_scale), 0.22 * fc.sidelight_scale / FERRY_SIDELIGHT_SCALE, 7.0,
				Vector3(sl[1], 0, sl[2] * 0.8))
		for lp: Array in fc.lamps:
			gb.glow(bulkhead_glow_at(lp[0], lp[1], fc.lamp_scale), GlowBuilder.WARM, bulkhead_glow_size(fc.lamp_scale),
				4.0, true, 0.0, lp[1], 0.0)
		var window := Color(1.0, 0.74, 0.42)
		for w: Array in fc.windows:
			gb.reflection(w[0], window, w[1], w[2], w[3])
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
		mb.cylinder(Vector3.ZERO, 0.85, 0.85, 3.6, 10, net, Color(-1, 0, 0), 0.0, true)
		mb.cylinder(Vector3(0, -0.06, 0), 1.05, 1.05, 0.12, 10, steel, Color(-1, 0, 0), 0.0, true)
		mb.cylinder(Vector3(0, 3.54, 0), 1.05, 1.05, 0.12, 10, steel, Color(-1, 0, 0), 0.0, true)
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


## A sidelight on a wheelhouse wall at `w` (on its side `sx`, ±1, and the end
## `sz`, ±1, it serves): a lens drum on a bracket, a cap, and a screen on its aft
## side so it only shows ahead and abeam. Whichever end is the bow, port is where x
## and z have the same sign, so that lens is red and the other green.
static func add_sidelight(mb: MeshBuilder, w: Vector3, sx: float, sz: float, s := FERRY_SIDELIGHT_SCALE) -> void:
	var c := w + Vector3(sx * 0.2 * s, 0, 0)
	var none := Color(-1, 0, 0)
	mb.box(w + Vector3(sx * 0.1 * s, -0.13 * s, 0), Vector3(0.24 * s, 0.04 * s, 0.34 * s), LAMP_DARK)
	mb.box(w + Vector3(sx * 0.04 * s, 0, 0), Vector3(0.08 * s, 0.3 * s, 0.34 * s), LAMP_DARK)
	mb.cylinder(c + Vector3(0, -0.11 * s, 0), 0.11 * s, 0.11 * s, 0.2 * s, 8, NAV_RED if sx * sz > 0.0 else NAV_GREEN, none, PI / 8.0)
	mb.cylinder(c + Vector3(0, 0.09 * s, 0), 0.13 * s, 0.09 * s, 0.05 * s, 8, LAMP_DARK, none, PI / 8.0)
	# Screen on the aft side (towards the middle of the ship).
	mb.box(c + Vector3(-sx * 0.02 * s, -0.01 * s, -sz * 0.14 * s), Vector3(0.3 * s, 0.26 * s, 0.03 * s), LAMP_DARK)


static func sidelight_glow_at(w: Vector3, sx: float, s := FERRY_SIDELIGHT_SCALE) -> Vector3:
	return w + Vector3(sx * 0.2 * s, 0, 0)


## Frame for a wall fixture at `p`: +Z out from the wall, +Y up, scaled by `s`.
static func _lamp_frame(p: Vector3, out: Vector3, s: float) -> Transform3D:
	var z := Vector3(out.x, 0.0, out.z).normalized()
	var x := Vector3.UP.cross(z)
	return Transform3D(Basis(x, Vector3.UP, z).scaled(Vector3.ONE * s), p)

