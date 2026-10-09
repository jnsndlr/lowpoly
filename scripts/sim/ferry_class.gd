class_name FerryClass
extends RefCounted
## The five sizes of double-ended car ferry, smallest (1) to largest (5): lanes and
## rows of cars, hull, speed, and where the fittings (masthead and side lights,
## deck lamps, lit windows, gull perches) sit in the hull's frame, shared by
## Models' hull and lights and by Seagulls. Size 1 is Skagit County's M/V Guemes,
## from the mid-poly model (art/guemes_mid.py, shown at MID_SCALE like the Evergreen
## State): an open deck of three lanes, the house down the starboard side, the
## port lane's +Z end slot taken by the port engine room's box, its cars turning in
## round it (`--classic-ferry` keeps the code-built open-deck boat with the
## wheelhouse up on one side); size 2 is WSF's M/V Hiyu, from the mid-poly model
## (art/hiyu_mid.py, likewise): her cars drive through her, down a tall tunnel
## between the stair casings and a lane each side under the passenger cabins, a
## bridge over the tunnel carrying the double-ended pilothouse (`--classic-ferry`
## keeps the code-built portal boat after her); 3 to 5 carry their passenger
## decks over the cars. Size 4 is the WSF Evergreen State class, from the mid-poly
## model (art/ferry_mid.py, real scale, shown at MID_SCALE to match the game's cars):
## a two-lane tunnel between the stair casings and a lane in each wing, the wing
## lanes turning in to the apron's opening at the ends. +Z and -Z ends are identical.

const LANE_SPACING := 4.5
const ROW_SPACING := 7.5
# Side-house ferries' house and stack top heights.
const OPEN_DECK_Y := 3.0
const BULWARK_TOP := 5.7
# Full ferries' deck heights (as the size-4 boat was first built).
const MAST_TOP := 27.6
const SIDELIGHT_Y := 20.94

# The mid-poly Evergreen State (size 4): modelled in real metres, shown at MID_SCALE
# so she matches the game's cars and trucks (drawn at Models.LEGACY_SCALE, a third
# again over real; 1.0 once they're true size), dropped MID_DROP so her car deck
# (2.85 m up in the model) lies at Layout.DECK_Y. `--classic-ferry` or a missing model keeps
# the code-built size 4.
const MID_GLB := "res://assets/models/ferry_mid.glb"
const MID_SCALE := 1.26
const MID_CAR_DECK := 2.85  # her car deck above the waterline (art/ferry_mid.py CAR_DECK)
const MID_DROP := MID_CAR_DECK * MID_SCALE - Layout.DECK_Y
const MID_APRON_Z := 42.45  # where her car deck's asphalt gives way to the bare steel apron
static var mid := not "--classic-ferry" in OS.get_cmdline_user_args() and ResourceLoader.exists(MID_GLB)

# The mid-poly M/V Guemes (size 1), shown and dropped like the Evergreen State; her
# model's freeboard is raised so her car deck meets DECK_Y (MID_SCALE x 2.5 = 3.15).
const SMALL_GLB := "res://assets/models/guemes_mid.glb"
const SMALL_CAR_DECK := 2.5  # art/guemes_mid.py CAR_DECK
const SMALL_DROP := SMALL_CAR_DECK * MID_SCALE - Layout.DECK_Y
static var small := not "--classic-ferry" in OS.get_cmdline_user_args() and ResourceLoader.exists(SMALL_GLB)

# The mid-poly M/V Hiyu (size 2), shown and dropped the same way, her freeboard
# raised to match.
const HIYU_GLB := "res://assets/models/hiyu_mid.glb"
const HIYU_CAR_DECK := 2.5  # art/hiyu_mid.py CAR_DECK
const HIYU_DROP := HIYU_CAR_DECK * MID_SCALE - Layout.DECK_Y
static var hiyu_model := not "--classic-ferry" in OS.get_cmdline_user_args() and ResourceLoader.exists(HIYU_GLB)

# The rescue boat (art/rib_mid.py -> RIB_GLB), a sub model shared by the mid-poly
# ferries: Models._mid_ferry sets it in her cradle, sling hooked on her davit's fall.
# Each entry is [origin in the ferry model's metres, yaw about +Y]; keep them in step
# with RIB_AT / RIB_YAW in the ferry's script (art/ferry_mid.py, art/hiyu_mid.py).
const RIB_GLB := "res://assets/models/rib_mid.glb"
const MID_RIBS := [[Vector3(7.2, 7.3 + 0.78, -34.6), 0.0]]
const HIYU_RIBS := [[Vector3(6.6, 8.1 + 0.78, -4.0), PI]]

# size: [lanes, rows, half length, half beam, cruise, label]
const TABLE := {
	1: [2, 5, 25.5, 8.7, 19.5, "Open-deck ferry"],
	2: [3, 6, 31.5, 11.7, 22.5, "Small ferry"],
	3: [3, 8, 40.5, 10.5, 25.5, "Mid-size ferry"],
	4: [4, 9, 45.0, 12.6, 27.0, "Ferry"],
	5: [4, 12, 57.0, 12.9, 28.5, "Jumbo ferry"],
}

static var _cache := {}

var size := 4
var label := ""
var lanes := 4
var rows := 9
var capacity := 36
var half_length := 45.0
var half_beam := 12.6
var cruise := 27.0
var open_deck := false
var portal := false
var evergreen := false             # the mid-poly Evergreen State (size 4, `mid`)
var guemes := false                # the mid-poly M/V Guemes (size 1, `small`)
var hiyu := false                  # the mid-poly M/V Hiyu (size 2, `hiyu_model`)
var ribs: Array = []               # her rescue boats ([model-metre origin, yaw], see MID_RIBS)
# Slots no car may take (index row * lanes + lane): the Guemes' engine room box.
var blocked := PackedInt32Array()
# Lanes outboard of throat_x can't run straight out over the end: they turn in to it
# (at the end, end_z) from turn_z, beyond their last row.
var throat_x := INF
var turn_z := 0.0
var tall := PackedInt32Array()     # lanes with the headroom for trucks (none listed: all)
var cols := PackedFloat32Array()   # lane centres (x), port to starboard
var row_z := PackedFloat32Array()  # row centres (z), +Z end first
var end_z := 42.0                  # where cars cross the hull's end
# The nets across the car deck at ±net_z, net_half_w either side of the centreline:
# both up under way, the one at the docked end down while cars cross it.
var net_z := 0.0
var net_half_w := 0.0
# Hull outline: the sides run straight to ±(half_length - chamfer), then close in
# to ±(half_beam - end_in) at the ends.
var chamfer := 9.0
var end_in := 4.8
var hull_radius := 12.9             # capsule round the hull (corners just touching)
var sidelight_scale := 3.9
var lantern_scale := 3.6
var lamp_scale := 2.7

# Full ferries (3-5).
var sun_half := 18.0                # sun-deck cabin half length
var wheel_z := 22.2                 # wheelhouses at ±wheel_z
var wheel_half_w := 6.3
var funnels := PackedFloat32Array()   # funnel centres (z)
var lifeboats := PackedFloat32Array() # lifeboat centres (z), both sides
var gallery := PackedFloat32Array()   # gallery pillars (z)

# Side-house ferry (1): the house on the +X side, the stack on the -X side.
var house_x := 6.0
var house_half_w := 2.1
var house_half_len := 3.0
var cabin_top := 0.0               # 0: no cabin, the tower's a column
var wheel_y := 12.0                 # wheelhouse floor
var wheel_half_len := 4.5
var wheel_h := 3.6
var stack_x := -7.2
var stack_top := 15.0

# Portal ferry (2): side houses from side_in out to the hull's sides over the outer
# lanes (their undersides at low_y; the walls below them stop short at
# ±low_half_len and sweep up into the cabins' ends in a curve), a bridge just
# under the pilothouse between them over the centre lane (underside at span_y),
# the upper deck on top at cabin_top and the pilothouse on the bridge (wheel_y,
# wheel_h, wheel_half_len and wheel_half_w), masts at ±mast_z on its roof.
var side_in := 4.2
var low_y := 7.95
var span_y := 11.25
var span_half_len := 9.0
var low_half_len := 9.0
var mast_z := 2.7
var mast_top := 23.1
var pillars := PackedFloat32Array()   # overhang pillars (z), both sides

# Fittings, in the hull's frame.
var lanterns := PackedVector3Array()   # masthead lantern bases
var sidelights := []                   # [wall point, sx, sz]
var lamps := []                        # deck lamps: [point, out]
var windows := []                      # lit-window reflections: [point, size, energy, facing]
var deck_lights := PackedVector3Array() # lights filling the enclosed car deck (NightLights)
var perches := []                      # gull perches: [from, to, spread]


static func of(s: int) -> FerryClass:
	if not _cache.has(s):
		_cache[s] = FerryClass.new(s)
	return _cache[s]


## Sizes for routes with these demands (any measure, busier higher), by rank:
## the quietest get the little open-deck boats, the busiest the jumbos, and a
## fleet of five or more has one of every size. A smaller one still runs from the
## smallest to the largest.
static func sizes_by_demand(demand: Array[float]) -> Array[int]:
	var n := demand.size()
	var order := range(n)
	order.sort_custom(func(i, j): return demand[i] < demand[j] or (demand[i] == demand[j] and i < j))
	var out: Array[int] = []
	out.resize(n)
	for rank in n:
		var sz := 5
		if n >= 5:
			sz = 1 + floori(rank * 5.0 / n)
		elif n > 1:
			sz = 1 + roundi(rank * 4.0 / (n - 1))
		out[order[rank]] = sz
	return out


func _init(s: int) -> void:
	size = s
	var t: Array = TABLE[s]
	lanes = t[0]
	rows = t[1]
	half_length = t[2]
	half_beam = t[3]
	cruise = t[4]
	label = t[5]
	capacity = lanes * rows
	guemes = s == 1 and small
	open_deck = s == 1 and not guemes
	hiyu = s == 2 and hiyu_model
	portal = s == 2 and not hiyu
	evergreen = s == 4 and mid
	if guemes:
		lanes = 3
		rows = 5
		half_length = 18.9 * MID_SCALE
		half_beam = 7.93 * MID_SCALE
		label = "Guemes"
	if hiyu:
		lanes = 4
		rows = 8
		half_length = 26.5 * MID_SCALE
		half_beam = 9.6 * MID_SCALE
		label = "Hiyu"
	if evergreen:
		lanes = 4
		rows = 11
		half_length = 47.25 * MID_SCALE
		half_beam = 11.15 * MID_SCALE
		label = "Evergreen State class"
		capacity = lanes * rows
	end_z = half_length - 3.0
	for i in rows:
		row_z.append(((rows - 1) * 0.5 - i) * ROW_SPACING)
	if open_deck:
		chamfer = 6.0
		end_in = 3.0
		sidelight_scale = 2.7
		lantern_scale = 2.7
		lamp_scale = 2.1
		_lay_out_open()
	elif portal:
		chamfer = 6.0
		end_in = 3.0
		sidelight_scale = 2.7
		lantern_scale = 2.7
		lamp_scale = 2.1
		_lay_out_portal()
	elif guemes:
		chamfer = 15.6
		end_in = 5.4
		sidelight_scale = 2.7
		lantern_scale = 2.7
		lamp_scale = 2.1
		_lay_out_guemes()
	elif hiyu:
		chamfer = 12.1
		end_in = 7.1
		sidelight_scale = 2.7
		lantern_scale = 2.7
		lamp_scale = 2.1
		_lay_out_hiyu()
	elif evergreen:
		chamfer = 21.0
		end_in = 7.2
		_lay_out_evergreen()
	else:
		for i in lanes:
			cols.append((i - (lanes - 1) * 0.5) * LANE_SPACING)
		_lay_out_full()
	capacity = lanes * rows - blocked.size()
	var c := chamfer
	hull_radius = maxf(half_beam, (half_beam * half_beam + c * c) / (2.0 * c) - 0.42)
	if net_z == 0.0:
		_place_nets()


## The nets from wall to wall of the car deck: the Evergreen State's on the apron's
## edge, where her green bulwark ends (art/ferry_mid.py GREEN_Z - 0.3), to its inner
## face (0.3 thick, slanting in there); the code-built boats' just past the end rows'
## cars (and inside the hull's end). The Guemes' are set in _lay_out_guemes.
func _place_nets() -> void:
	if evergreen:
		net_z = MID_APRON_Z * MID_SCALE
		net_half_w = (_mid_beam(MID_APRON_Z) - 0.36) * MID_SCALE
		return
	net_z = minf(row_z[0] + 4.5, end_z - 1.5)
	var into := maxf(0.0, net_z - (half_length - chamfer)) / chamfer
	net_half_w = half_beam - end_in * into - 0.6


## Whether lane `c` suits a truck (`truck`) or a car: trucks want the headroom,
## cars leave it to them.
## Whether cars in the lane at `x` follow an arc (arc_x) rather than turning in at
## turn_z: the Hiyu's wings, which curve in with her side.
func arcs(x: float) -> bool:
	return hiyu and absf(x) > throat_x


## Where the arcing lane at `x` runs at `z` (both in the hull's frame): its own x
## amidships, then in with the hull's side, HIYU_WING_INSET in from it.
func arc_x(x: float, z: float) -> float:
	var k := MID_SCALE
	return signf(x) * minf(absf(x), (_hiyu_beam(z / k) - HIYU_WING_INSET) * k)


func lane_suits(c: int, truck: bool) -> bool:
	return tall.is_empty() or tall.has(c) == truck


func half_seg() -> float:
	return half_length - hull_radius


func _lay_out_full() -> void:
	var b := half_beam
	var l := half_length
	sun_half = 0.4 * l
	wheel_z = sun_half + 4.2
	wheel_half_w = 0.5 * b
	if size >= 5:
		funnels = PackedFloat32Array([-0.45 * sun_half, 0.45 * sun_half])
		lifeboats = PackedFloat32Array([-0.7 * sun_half, -0.26 * sun_half, 0.26 * sun_half, 0.7 * sun_half])
	else:
		funnels = PackedFloat32Array([0.0])
		lifeboats = PackedFloat32Array([-0.53 * sun_half, 0.53 * sun_half])
	var n := floori((l - 18.0) / 9.0)
	for i in range(-n, n + 1):
		gallery.append(i * 9.0)

	for z: float in [-wheel_z, wheel_z]:
		lanterns.append(Vector3(0, MAST_TOP, z))
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(x * (wheel_half_w + 0.15), SIDELIGHT_Y, z), x, signf(z)])
	for x: float in [-1.0, 1.0]:
		for z in gallery:
			lamps.append([Vector3(x * b, 9.45, z), Vector3(x, 0, 0)])
	# Window rows: passenger deck, sun deck, and the passenger deck's ends.
	for x: float in [-1.0, 1.0]:
		var z := -(l - 18.0)
		while z <= l - 18.0 + 0.03:
			windows.append([Vector3(x * (b + 0.45), 13.2, z), 0.9, 2.2, Vector3(x, 0, 0)])
			z += 4.5
		z = -(sun_half - 3.0)
		while z <= sun_half - 3.0 + 0.03:
			windows.append([Vector3(x * (b - 2.85), 17.4, z), 0.66, 1.6, Vector3(x, 0, 0)])
			z += 6.0
	for z: float in [-(l - 17.4), l - 17.4]:
		var x := -(b - 3.6)
		while x <= b - 3.6 + 0.03:
			windows.append([Vector3(x, 13.2, z), 0.9, 2.2, Vector3(0, 0, signf(z))])
			x += 4.5

	# Perches: wheelhouse roofs, the sun-deck roof clear of the funnels, the
	# passenger deck's edges, the funnel tops and the lifeboats.
	for z: float in [-wheel_z, wheel_z]:
		perches.append([Vector3(-(wheel_half_w - 1.2), 22.2, z), Vector3(wheel_half_w - 1.2, 22.2, z), 2.4])
	var roof_spread := b - 4.2
	var edges := [-(sun_half - 1.2)]
	for fz in funnels:
		edges.append(fz - 5.4)
		edges.append(fz + 5.4)
	edges.append(sun_half - 1.2)
	for i in range(0, edges.size(), 2):
		if edges[i + 1] - edges[i] > 3.0:
			perches.append([Vector3(0, 18.9, edges[i]), Vector3(0, 18.9, edges[i + 1]), roof_spread])
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.75), 15.3, -(l - 16.2)), Vector3(x * (b - 0.75), 15.3, l - 16.2), 0.0])
		for z in lifeboats:
			perches.append([Vector3(x * (b - 2.1), 20.25, z - 2.7), Vector3(x * (b - 2.1), 20.25, z + 2.7), 0.0])
	for fz in funnels:
		perches.append([Vector3(0, 27.15, fz - 3.3), Vector3(0, 27.15, fz + 3.3), 0.0])


## A point in the mid-poly model (metres, waterline at 0) in the hull's frame.
static func _mid(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * MID_SCALE - Vector3(0, MID_DROP, 0)


## The model's half beam at the deck at |z| (metres): its ends one smooth oval
## (art/ferry_mid.py deck_x).
static func _mid_beam(z: float) -> float:
	var t := clampf((absf(z) - 20.0) / 26.4, 0.0, 1.0)
	return 10.8 * pow(maxf(0.0, 1.0 - pow(t, 2.3)), 1.0 / 2.3)


func _lay_out_evergreen() -> void:
	ribs = MID_RIBS
	# Wing, tunnel, tunnel, wing; trucks keep to the tunnel.
	cols = PackedFloat32Array([-8.45 * MID_SCALE, -1.9 * MID_SCALE, 1.9 * MID_SCALE, 8.45 * MID_SCALE])
	tall = PackedInt32Array([1, 2])
	throat_x = 3.8 * MID_SCALE
	turn_z = row_z[0] + 1.0 * Models.LEGACY_SCALE
	var k := MID_SCALE
	for e: float in [-1.0, 1.0]:
		# Masthead lanterns on the masts over the pilothouse roofs, sidelights on the
		# pilothouses' sides toward the ends.
		lanterns.append(_mid(0, 21.95, e * 22.5))
		for x: float in [-1.0, 1.0]:
			sidelights.append([_mid(x * 4.52, 12.1, e * 25.2), x, e])
	# Lights filling the car deck under her ceiling lights: down the tunnel, and down
	# each wing short of where the hull sides round in.
	for z: float in [-33.0, -22.0, -11.0, 0.0, 11.0, 22.0, 33.0]:
		deck_lights.append(_mid(0, 6.3, z))
	for z: float in [-28.0, -14.0, 0.0, 14.0, 28.0]:
		for x: float in [-8.3, 8.3]:
			deck_lights.append(_mid(x, 6.3, z))
	# Lit windows: every other one down the cabin's sides, and across its end faces.
	for x: float in [-1.0, 1.0]:
		var z := -26.6
		while z <= 26.61:
			windows.append([_mid(x * 10.35, 9.03, z), 0.9, 2.2, Vector3(x, 0, 0)])
			z += 4.26
	for e: float in [-1.0, 1.0]:
		var x := -7.5
		while x <= 7.51:
			windows.append([_mid(x, 9.03, e * 28.6), 0.9, 2.2, Vector3(0, 0, e)])
			x += 3.0
	# Perches: the pilothouse roofs, the crew houses' roofs, the sun deck's and the
	# forks' rails, the walkways' rails, the funnel tops.
	for e: float in [-1.0, 1.0]:
		perches.append([_mid(-4.4, 14.02, e * 24.0), _mid(4.4, 14.02, e * 24.0), 1.9 * k])
		perches.append([_mid(0, 13.06, e * 6.6), _mid(0, 13.06, e * 20.6), 4.4 * k])
		perches.append([_mid(-4.6, 8.32, e * 30.65), _mid(4.6, 8.32, e * 30.65), 0.0])
		for x: float in [-1.0, 1.0]:
			perches.append([_mid(x * (_mid_beam(31.0) + 0.05), 8.32, e * 31.0),
				_mid(x * (_mid_beam(39.5) + 0.05), 8.32, e * 39.5), 0.0])
	for x: float in [-1.0, 1.0]:
		perches.append([_mid(x * 10.35, 11.8, -27.5), _mid(x * 10.35, 11.8, 27.5), 0.0])
		perches.append([_mid(x * 4.2, 14.82, -0.6), _mid(x * 4.2, 14.82, 0.6), 0.0])


## A point in the Guemes model (metres, waterline at 0) in the hull's frame.
static func _small(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * MID_SCALE - Vector3(0, SMALL_DROP, 0)


## The Guemes model's half beam at the deck at |z| (art/guemes_mid.py deck_x).
static func _small_beam(z: float) -> float:
	var t := clampf((absf(z) - 6.5) / 12.22, 0.0, 1.0)
	return 7.75 * pow(maxf(0.0, 1.0 - pow(t, 2.6)), 1.0 / 2.6)


func _lay_out_guemes() -> void:
	var k := MID_SCALE
	var d := SMALL_CAR_DECK
	cols = PackedFloat32Array([-5.2 * k, -1.63 * k, 1.94 * k])
	# The port lane's +Z end slot is the port engine room's; the lane's cars turn
	# in past its last row to clear the box on their way over that end (and the
	# other, alike).
	blocked = PackedInt32Array([0])
	net_z = 15.2 * k
	net_half_w = (_small_beam(15.2) - 0.2) * k
	throat_x = 2.0 * k
	turn_z = 8.6 * k
	lanterns.append(_small(5.75, d + 13.3, 0))
	for e: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			sidelights.append([_small(5.75 + x * 1.62, d + 5.5, e * 1.6), x, e])
	# Deck lamps on the house's inboard face and the corner panels opposite it.
	for e: float in [-1.0, 1.0]:
		lamps.append([_small(3.95, d + 2.9, e * 9.0), Vector3(-1, 0, 0)])
		lamps.append([_small(-(_small_beam(12.6) - 0.2), d + 1.95, e * 12.6), Vector3(1, 0, 0)])
	# Lit windows: the cabin's toward the cars and outboard, the pilothouse's.
	for z: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		windows.append([_small(3.9, d + 1.8, z), 0.75, 1.6, Vector3(-1, 0, 0)])
	for e: float in [-1.0, 1.0]:
		for z: float in [0.9, 1.65, 4.6, 5.35, 8.2]:
			windows.append([_small(7.6, d + 1.85, e * z), 0.6, 1.6, Vector3(1, 0, 0)])
		windows.append([_small(5.75, d + 6.4, e * 2.75), 0.9, 1.4, Vector3(0, 0, e)])
	for x: float in [-1.0, 1.0]:
		windows.append([_small(5.75 + x * 1.8, d + 6.4, 0), 0.9, 1.4, Vector3(x, 0, 0)])
	# Perches: the pilothouse roof, the upper deck's rail, the port pipe rail, the
	# corner panels' tops, the stacks.
	perches.append([_small(5.75, d + 7.47, -2.2), _small(5.75, d + 7.47, 2.2), 1.4 * k])
	for x: float in [3.4, 7.67]:
		perches.append([_small(x, d + 4.7, -10.9), _small(x, d + 4.7, 10.9), 0.0])
	perches.append([_small(-7.6, d + 1.75, -10.6), _small(-7.6, d + 1.75, 10.6), 0.0])
	for e: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			perches.append([_small(x * (_small_beam(12.4) - 0.1), d + 2.2, e * 12.4),
				_small(x * (_small_beam(14.8) - 0.1), d + 2.2, e * 14.8), 0.0])
	perches.append([_small(-6.25, d + 7.97, 13.4), _small(-6.25, d + 7.97, 13.5), 0.0])
	perches.append([_small(6.35, d + 7.97, -12.4), _small(6.35, d + 7.97, -12.5), 0.0])


## A point in the Hiyu model (metres, waterline at 0) in the hull's frame.
static func _hiyu(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * MID_SCALE - Vector3(0, HIYU_DROP, 0)


# The Hiyu model's half beam at the deck every 0.5 m of |z| from midships (the
# user's deck outline, art/hiyu_mid.py deck_x); it closes to her nose at 26.5.
const HIYU_BEAM := [
	9.6, 9.6, 9.6, 9.6, 9.6, 9.6, 9.6, 9.6, 9.6, 9.59,
	9.57, 9.55, 9.52, 9.49, 9.45, 9.41, 9.36, 9.31, 9.25, 9.19,
	9.12, 9.04, 8.96, 8.88, 8.78, 8.68, 8.57, 8.46, 8.33, 8.19,
	8.05, 7.89, 7.72, 7.54, 7.34, 7.13, 6.92, 6.69, 6.46, 6.22,
	5.97, 5.72, 5.45, 5.18, 4.89, 4.6, 4.29, 3.97, 3.63, 3.26,
	2.87, 2.42, 1.83,
]


## How far in from the Hiyu's side (metres) her wing lanes run where she tapers.
const HIYU_WING_INSET := 1.6


## The Hiyu model's half beam at the deck at |z| (metres).
static func _hiyu_beam(z: float) -> float:
	var f := absf(z) / 0.5
	var i := mini(floori(f), HIYU_BEAM.size() - 1)
	if i == HIYU_BEAM.size() - 1:
		return lerpf(HIYU_BEAM[i], 0.0, clampf((absf(z) - i * 0.5) / (26.5 - i * 0.5), 0.0, 1.0))
	return lerpf(HIYU_BEAM[i], HIYU_BEAM[i + 1], f - i)


func _lay_out_hiyu() -> void:
	ribs = HIYU_RIBS
	var k := MID_SCALE
	var d := HIYU_CAR_DECK
	# Wing, the tunnel's two, wing; trucks keep to the tunnel, the wings having only
	# 2.75 m under the cabins. Her ends taper too far in for the wings' end rows, so those
	# slots stay empty, and the wing lanes arc in with her side to the nose (arc_x; the
	# bulwark stops a metre short of the nets to let them).
	cols = PackedFloat32Array([-6.6 * k, -2.0 * k, 2.0 * k, 6.6 * k])
	tall = PackedInt32Array([1, 2])
	blocked = PackedInt32Array([0, 3, (rows - 1) * lanes, (rows - 1) * lanes + 3])
	throat_x = 3.0 * k
	net_z = 23.6 * k
	net_half_w = (_hiyu_beam(23.6) - 0.17) * k
	var cab_bot := d + 2.75
	var upper := d + 5.6
	var sill := upper + 1.35
	var roof := upper + 2.85
	# Masthead lanterns on the two masts (set diagonally), sidelights on the
	# pilothouse's sides toward each end.
	for e: float in [-1.0, 1.0]:
		lanterns.append(_hiyu(-e * 1.4, d + 14.05, e * 1.2))
		for x: float in [-1.0, 1.0]:
			sidelights.append([_hiyu(x * 3.95, sill - 0.45, e * 1.5), x, e])
	# Deck lamps on the cabins' ends over the wings, and on the bridge's over the tunnel.
	for e: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			lamps.append([_hiyu(x * 6.6, cab_bot + 0.6, e * 8.87), Vector3(0, 0, e)])
			lamps.append([_hiyu(x * 1.6, d + 4.65 + 0.75, e * 4.62), Vector3(0, 0, e)])
	# Lights filling the tunnel under the bridge and the wings under the cabins.
	deck_lights.append(_hiyu(0, d + 4.25, 0))
	for x: float in [-1.0, 1.0]:
		for z: float in [-4.5, 4.5]:
			deck_lights.append(_hiyu(x * 6.6, cab_bot - 0.4, z))
	# Lit windows: the cabins' down the sides and on the ends, the pilothouse's.
	for x: float in [-1.0, 1.0]:
		for z: float in [-6.0, -2.0, 2.0, 6.0]:
			windows.append([_hiyu(x * (_hiyu_beam(z) - 0.05), cab_bot + 1.5, z), 1.0, 2.0, Vector3(x, 0, 0)])
		for e: float in [-1.0, 1.0]:
			for cx: float in [5.3, 7.6]:
				windows.append([_hiyu(x * cx, cab_bot + 1.5, e * 8.95), 0.95, 2.0, Vector3(0, 0, e)])
			windows.append([_hiyu(x * 2.0, sill + 0.6, e * 2.65), 0.9, 1.4, Vector3(0, 0, e)])
		windows.append([_hiyu(x * 4.05, sill + 0.6, 0), 0.9, 1.4, Vector3(x, 0, 0)])
	# Perches: the pilothouse roof, the upper deck's rails (outboard and at the
	# cabins' ends), the rails on the bulwark's corners, the stack tops.
	perches.append([_hiyu(0, roof + 0.02, -1.8), _hiyu(0, roof + 0.02, 1.8), 3.0 * k])
	for x: float in [-1.0, 1.0]:
		var zs := [-8.5, -4.5, 4.5, 8.5]
		for j in zs.size() - 1:
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			perches.append([_hiyu(x * (_hiyu_beam(z0) - 0.17), upper + 1.0, z0),
				_hiyu(x * (_hiyu_beam(z1) - 0.17), upper + 1.0, z1), 0.0])
		perches.append([_hiyu(x * 4.85, roof + 1.0, -0.1), _hiyu(x * 4.85, roof + 1.0, 0.1), 0.0])
		for e: float in [-1.0, 1.0]:
			perches.append([_hiyu(x * 3.7, upper + 1.0, e * 8.83),
				_hiyu(x * (_hiyu_beam(8.83) - 0.17), upper + 1.0, e * 8.83), 0.0])
			for zz: Array in [[11.5, 16.5], [16.5, 21.5]]:
				perches.append([_hiyu(x * (_hiyu_beam(zz[0]) - 0.1), d + 1.7, e * zz[0]),
					_hiyu(x * (_hiyu_beam(zz[1]) - 0.1), d + 1.7, e * zz[1]), 0.0])


func _lay_out_open() -> void:
	var b := half_beam
	var l := half_length
	# A tower on a sponson: a narrow stair column up to the wheelhouse.
	cols = PackedFloat32Array([-3.3, 1.2])
	house_x = 6.15
	house_half_w = 1.8
	house_half_len = 2.7
	cabin_top = 0.0
	wheel_y = 12.3
	wheel_half_len = 4.2
	stack_x = -7.05
	stack_top = 18.0
	var wx := house_x
	var whw := wheel_half_w_open()
	var top := wheel_y + wheel_h
	lanterns.append(Vector3(wx, top + 4.5, 0))
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(wx + x * (whw + 0.12), wheel_y + 1.86, z * (wheel_half_len - 1.2)), x, z])
	# Deck lamps on the house's inboard face and on posts along the far bulwark.
	for z: float in [-1.0, 1.0]:
		lamps.append([Vector3(wx - house_half_w, 7.8, z * (house_half_len - 0.75)), Vector3(-1, 0, 0)])
		lamps.append([Vector3(-(b - 0.3), 7.8, z * (l - 12.0)), Vector3(1, 0, 0)])
	# Wheelhouse windows all round, and the cabin's.
	for x: float in [-1.0, 1.0]:
		var z := -(wheel_half_len - 1.5)
		while z <= wheel_half_len - 1.5 + 0.03:
			windows.append([Vector3(wx + x * (whw + 0.15), wheel_y + 2.25, z), 0.6, 1.4, Vector3(x, 0, 0)])
			z += 2.7
	for z: float in [-1.0, 1.0]:
		windows.append([Vector3(wx, wheel_y + 2.25, z * (wheel_half_len + 0.15)), 0.66, 1.4, Vector3(0, 0, z)])

	perches.append([Vector3(wx, top + 0.15, -(wheel_half_len - 0.9)), Vector3(wx, top + 0.15, wheel_half_len - 0.9), whw - 0.75])
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.36), BULWARK_TOP, -(l - 7.8)), Vector3(x * (b - 0.36), BULWARK_TOP, l - 7.8), 0.0])
	perches.append([Vector3(stack_x, stack_top + 0.15, -0.3), Vector3(stack_x, stack_top + 0.15, 0.3), 0.0])


func wheel_half_w_open() -> float:
	return house_half_w + 0.45


func _lay_out_portal() -> void:
	var b := half_beam
	var l := half_length
	cols = PackedFloat32Array([-6.75, 0.0, 6.75])
	tall = PackedInt32Array([1])
	house_half_len = 0.42 * l
	low_half_len = house_half_len - 4.5
	cabin_top = 13.05
	wheel_y = cabin_top
	wheel_h = 4.5
	wheel_half_len = 4.8
	wheel_half_w = 4.5
	span_half_len = wheel_half_len + 0.9
	stack_top = cabin_top + 5.1
	var n := floori(house_half_len / 7.8)
	for i in range(-n, n + 1):
		pillars.append(i * house_half_len / n)
	var top := wheel_y + wheel_h
	for z: float in [-mast_z, mast_z]:
		lanterns.append(Vector3(0, mast_top, z))
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(x * (wheel_half_w + 0.12), wheel_y + 1.86, z * (wheel_half_len - 1.2)), x, z])
	# Deck lamps over the lanes' mouths: on the side houses' ends and the bridge's.
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			lamps.append([Vector3(x * (side_in + 1.5), low_y + 1.05, z * house_half_len), Vector3(0, 0, z)])
		lamps.append([Vector3(0, span_y + 0.75, z * span_half_len), Vector3(0, 0, z)])
	# Cabin windows down the sides and on the ends, and the pilothouse's all round.
	for x: float in [-1.0, 1.0]:
		var z := -(house_half_len - 2.7)
		while z <= house_half_len - 2.7 + 0.03:
			windows.append([Vector3(x * (b + 0.15), 10.35, z), 0.9, 2.0, Vector3(x, 0, 0)])
			z += cabin_window_step()
		z = -(wheel_half_len - 1.5)
		while z <= wheel_half_len - 1.5 + 0.03:
			windows.append([Vector3(x * (wheel_half_w + 0.15), wheel_y + 2.55, z), 0.66, 1.4, Vector3(x, 0, 0)])
			z += 2.7
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			windows.append([Vector3(x * (b - 2.7), 10.35, z * (house_half_len + 0.15)), 0.84, 1.8, Vector3(0, 0, z)])
		windows.append([Vector3(0, wheel_y + 2.55, z * (wheel_half_len + 0.15)), 0.72, 1.4, Vector3(0, 0, z)])

	# Perches: the pilothouse roof, the upper deck's rails, the bulwarks at the open
	# ends, the stacks.
	perches.append([Vector3(0, top + 0.15, -(wheel_half_len - 0.9)), Vector3(0, top + 0.15, wheel_half_len - 0.9), wheel_half_w - 0.9])
	var rail := cabin_top + 2.7
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.3), rail, -(house_half_len - 0.3)), Vector3(x * (b - 0.3), rail, house_half_len - 0.3), 0.0])
		for z: float in [-1.0, 1.0]:
			perches.append([Vector3(x * (b - 0.36), BULWARK_TOP, z * (house_half_len + 1.8)), Vector3(x * (b - 0.36), BULWARK_TOP, z * (l - 7.8)), 0.0])
		perches.append([Vector3(x * stack_dx(), stack_top + 0.15, -0.3), Vector3(x * stack_dx(), stack_top + 0.15, 0.3), 0.0])
	for z: float in [-1.0, 1.0]:
		perches.append([Vector3(-(b - 0.9), rail, z * (house_half_len - 0.3)), Vector3(b - 0.9, rail, z * (house_half_len - 0.3)), 0.0])


## The portal ferry's two exhaust stacks stand on the upper deck at ±stack_dx().
func stack_dx() -> float:
	return wheel_half_w + 2.25


## The portal ferry's cabin windows, evenly down the sides from ±(house_half_len - 0.9).
func cabin_window_step() -> float:
	return 2.0 * (house_half_len - 2.7) / 5.0
