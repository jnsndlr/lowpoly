class_name FerryClass
extends RefCounted
## The five sizes of double-ended car ferry, smallest (1) to largest (5): lanes and
## rows of cars, hull, speed, and where the fittings (masthead and side lights,
## deck lamps, lit windows, gull perches) sit in the hull's frame, shared by
## Models' hull and lights and by Seagulls. Size 1 is an open-deck boat with the
## wheelhouse up on one side; size 2 (after the M/V Hiyu) runs its cars through a
## portal: passenger cabins over the two outer lanes, a bridge over the tall centre
## lane, and one double-ended pilothouse on top; 3 to 5 carry their passenger
## decks over the cars. +Z and -Z ends are identical.

const LANE_SPACING := 1.5
const ROW_SPACING := 2.5
# Side-house ferries' house and stack top heights.
const OPEN_DECK_Y := 1.0
const BULWARK_TOP := 1.9
# Full ferries' deck heights (as the size-4 boat was first built).
const MAST_TOP := 9.2
const SIDELIGHT_Y := 6.98

# size: [lanes, rows, half length, half beam, cruise, label]
const TABLE := {
	1: [2, 5, 8.5, 2.9, 6.5, "Open-deck ferry"],
	2: [3, 6, 10.5, 3.9, 7.5, "Small ferry"],
	3: [3, 8, 13.5, 3.5, 8.5, "Mid-size ferry"],
	4: [4, 9, 15.0, 4.2, 9.0, "Ferry"],
	5: [4, 12, 19.0, 4.3, 9.5, "Jumbo ferry"],
}

static var _cache := {}

var size := 4
var label := ""
var lanes := 4
var rows := 9
var capacity := 36
var half_length := 15.0
var half_beam := 4.2
var cruise := 9.0
var open_deck := false
var portal := false
var tall := PackedInt32Array()     # lanes with the headroom for trucks (none listed: all)
var cols := PackedFloat32Array()   # lane centres (x), port to starboard
var row_z := PackedFloat32Array()  # row centres (z), +Z end first
var end_z := 14.0                  # where cars cross the hull's end
# Hull outline: the sides run straight to ±(half_length - chamfer), then close in
# to ±(half_beam - end_in) at the ends.
var chamfer := 3.0
var end_in := 1.6
var hull_radius := 4.3             # capsule round the hull (corners just touching)
var sidelight_scale := 1.3
var lantern_scale := 1.2
var lamp_scale := 0.9

# Full ferries (3-5).
var sun_half := 6.0                # sun-deck cabin half length
var wheel_z := 7.4                 # wheelhouses at ±wheel_z
var wheel_half_w := 2.1
var funnels := PackedFloat32Array()   # funnel centres (z)
var lifeboats := PackedFloat32Array() # lifeboat centres (z), both sides
var gallery := PackedFloat32Array()   # gallery pillars (z)

# Side-house ferry (1): the house on the +X side, the stack on the -X side.
var house_x := 2.0
var house_half_w := 0.7
var house_half_len := 1.0
var cabin_top := 0.0               # 0: no cabin, the tower's a column
var wheel_y := 4.0                 # wheelhouse floor
var wheel_half_len := 1.5
var wheel_h := 1.2
var stack_x := -2.4
var stack_top := 5.0

# Portal ferry (2): side houses from side_in out to the hull's sides over the outer
# lanes (their undersides at low_y; the walls below them stop short at
# ±low_half_len and sweep up into the cabins' ends in a curve), a bridge just
# under the pilothouse between them over the centre lane (underside at span_y),
# the upper deck on top at cabin_top and the pilothouse on the bridge (wheel_y,
# wheel_h, wheel_half_len and wheel_half_w), masts at ±mast_z on its roof.
var side_in := 1.4
var low_y := 2.65
var span_y := 3.75
var span_half_len := 3.0
var low_half_len := 3.0
var mast_z := 0.9
var mast_top := 7.7
var pillars := PackedFloat32Array()   # overhang pillars (z), both sides

# Fittings, in the hull's frame.
var lanterns := PackedVector3Array()   # masthead lantern bases
var sidelights := []                   # [wall point, sx, sz]
var lamps := []                        # deck lamps: [point, out]
var windows := []                      # lit-window reflections: [point, size, energy, facing]
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
	open_deck = s == 1
	portal = s == 2
	end_z = half_length - 1.0
	for i in rows:
		row_z.append(((rows - 1) * 0.5 - i) * ROW_SPACING)
	if open_deck:
		chamfer = 2.0
		end_in = 1.0
		sidelight_scale = 0.9
		lantern_scale = 0.9
		lamp_scale = 0.7
		_lay_out_open()
	elif portal:
		chamfer = 2.0
		end_in = 1.0
		sidelight_scale = 0.9
		lantern_scale = 0.9
		lamp_scale = 0.7
		_lay_out_portal()
	else:
		for i in lanes:
			cols.append((i - (lanes - 1) * 0.5) * LANE_SPACING)
		_lay_out_full()
	var c := chamfer
	hull_radius = maxf(half_beam, (half_beam * half_beam + c * c) / (2.0 * c) - 0.14)


## Whether lane `c` suits a truck (`truck`) or a car: trucks want the headroom,
## cars leave it to them.
func lane_suits(c: int, truck: bool) -> bool:
	return tall.is_empty() or tall.has(c) == truck


func half_seg() -> float:
	return half_length - hull_radius


func _lay_out_full() -> void:
	var b := half_beam
	var l := half_length
	sun_half = 0.4 * l
	wheel_z = sun_half + 1.4
	wheel_half_w = 0.5 * b
	if size >= 5:
		funnels = PackedFloat32Array([-0.45 * sun_half, 0.45 * sun_half])
		lifeboats = PackedFloat32Array([-0.7 * sun_half, -0.26 * sun_half, 0.26 * sun_half, 0.7 * sun_half])
	else:
		funnels = PackedFloat32Array([0.0])
		lifeboats = PackedFloat32Array([-0.53 * sun_half, 0.53 * sun_half])
	var n := floori((l - 6.0) / 3.0)
	for i in range(-n, n + 1):
		gallery.append(i * 3.0)

	for z: float in [-wheel_z, wheel_z]:
		lanterns.append(Vector3(0, MAST_TOP, z))
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(x * (wheel_half_w + 0.05), SIDELIGHT_Y, z), x, signf(z)])
	for x: float in [-1.0, 1.0]:
		for z in gallery:
			lamps.append([Vector3(x * b, 3.15, z), Vector3(x, 0, 0)])
	# Window rows: passenger deck, sun deck, and the passenger deck's ends.
	for x: float in [-1.0, 1.0]:
		var z := -(l - 6.0)
		while z <= l - 6.0 + 0.01:
			windows.append([Vector3(x * (b + 0.15), 4.4, z), 0.3, 2.2, Vector3(x, 0, 0)])
			z += 1.5
		z = -(sun_half - 1.0)
		while z <= sun_half - 1.0 + 0.01:
			windows.append([Vector3(x * (b - 0.95), 5.8, z), 0.22, 1.6, Vector3(x, 0, 0)])
			z += 2.0
	for z: float in [-(l - 5.8), l - 5.8]:
		var x := -(b - 1.2)
		while x <= b - 1.2 + 0.01:
			windows.append([Vector3(x, 4.4, z), 0.3, 2.2, Vector3(0, 0, signf(z))])
			x += 1.5

	# Perches: wheelhouse roofs, the sun-deck roof clear of the funnels, the
	# passenger deck's edges, the funnel tops and the lifeboats.
	for z: float in [-wheel_z, wheel_z]:
		perches.append([Vector3(-(wheel_half_w - 0.4), 7.4, z), Vector3(wheel_half_w - 0.4, 7.4, z), 0.8])
	var roof_spread := b - 1.4
	var edges := [-(sun_half - 0.4)]
	for fz in funnels:
		edges.append(fz - 1.8)
		edges.append(fz + 1.8)
	edges.append(sun_half - 0.4)
	for i in range(0, edges.size(), 2):
		if edges[i + 1] - edges[i] > 1.0:
			perches.append([Vector3(0, 6.3, edges[i]), Vector3(0, 6.3, edges[i + 1]), roof_spread])
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.25), 5.1, -(l - 5.4)), Vector3(x * (b - 0.25), 5.1, l - 5.4), 0.0])
		for z in lifeboats:
			perches.append([Vector3(x * (b - 0.7), 6.75, z - 0.9), Vector3(x * (b - 0.7), 6.75, z + 0.9), 0.0])
	for fz in funnels:
		perches.append([Vector3(0, 9.05, fz - 1.1), Vector3(0, 9.05, fz + 1.1), 0.0])


func _lay_out_open() -> void:
	var b := half_beam
	var l := half_length
	# A tower on a sponson: a narrow stair column up to the wheelhouse.
	cols = PackedFloat32Array([-1.1, 0.4])
	house_x = 2.05
	house_half_w = 0.6
	house_half_len = 0.9
	cabin_top = 0.0
	wheel_y = 4.1
	wheel_half_len = 1.4
	stack_x = -2.35
	stack_top = 6.0
	var wx := house_x
	var whw := wheel_half_w_open()
	var top := wheel_y + wheel_h
	lanterns.append(Vector3(wx, top + 1.5, 0))
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(wx + x * (whw + 0.04), wheel_y + 0.62, z * (wheel_half_len - 0.4)), x, z])
	# Deck lamps on the house's inboard face and on posts along the far bulwark.
	for z: float in [-1.0, 1.0]:
		lamps.append([Vector3(wx - house_half_w, 2.6, z * (house_half_len - 0.25)), Vector3(-1, 0, 0)])
		lamps.append([Vector3(-(b - 0.1), 2.6, z * (l - 4.0)), Vector3(1, 0, 0)])
	# Wheelhouse windows all round, and the cabin's.
	for x: float in [-1.0, 1.0]:
		var z := -(wheel_half_len - 0.5)
		while z <= wheel_half_len - 0.5 + 0.01:
			windows.append([Vector3(wx + x * (whw + 0.05), wheel_y + 0.75, z), 0.2, 1.4, Vector3(x, 0, 0)])
			z += 0.9
	for z: float in [-1.0, 1.0]:
		windows.append([Vector3(wx, wheel_y + 0.75, z * (wheel_half_len + 0.05)), 0.22, 1.4, Vector3(0, 0, z)])

	perches.append([Vector3(wx, top + 0.05, -(wheel_half_len - 0.3)), Vector3(wx, top + 0.05, wheel_half_len - 0.3), whw - 0.25])
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.12), BULWARK_TOP, -(l - 2.6)), Vector3(x * (b - 0.12), BULWARK_TOP, l - 2.6), 0.0])
	perches.append([Vector3(stack_x, stack_top + 0.05, -0.1), Vector3(stack_x, stack_top + 0.05, 0.1), 0.0])


func wheel_half_w_open() -> float:
	return house_half_w + 0.15


func _lay_out_portal() -> void:
	var b := half_beam
	var l := half_length
	cols = PackedFloat32Array([-2.25, 0.0, 2.25])
	tall = PackedInt32Array([1])
	house_half_len = 0.42 * l
	low_half_len = house_half_len - 1.5
	cabin_top = 4.35
	wheel_y = cabin_top
	wheel_h = 1.5
	wheel_half_len = 1.6
	wheel_half_w = 1.5
	span_half_len = wheel_half_len + 0.3
	stack_top = cabin_top + 1.7
	var n := floori(house_half_len / 2.6)
	for i in range(-n, n + 1):
		pillars.append(i * house_half_len / n)
	var top := wheel_y + wheel_h
	for z: float in [-mast_z, mast_z]:
		lanterns.append(Vector3(0, mast_top, z))
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			sidelights.append([Vector3(x * (wheel_half_w + 0.04), wheel_y + 0.62, z * (wheel_half_len - 0.4)), x, z])
	# Deck lamps over the lanes' mouths: on the side houses' ends and the bridge's.
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			lamps.append([Vector3(x * (side_in + 0.5), low_y + 0.35, z * house_half_len), Vector3(0, 0, z)])
		lamps.append([Vector3(0, span_y + 0.25, z * span_half_len), Vector3(0, 0, z)])
	# Cabin windows down the sides and on the ends, and the pilothouse's all round.
	for x: float in [-1.0, 1.0]:
		var z := -(house_half_len - 0.9)
		while z <= house_half_len - 0.9 + 0.01:
			windows.append([Vector3(x * (b + 0.05), 3.45, z), 0.3, 2.0, Vector3(x, 0, 0)])
			z += cabin_window_step()
		z = -(wheel_half_len - 0.5)
		while z <= wheel_half_len - 0.5 + 0.01:
			windows.append([Vector3(x * (wheel_half_w + 0.05), wheel_y + 0.85, z), 0.22, 1.4, Vector3(x, 0, 0)])
			z += 0.9
	for z: float in [-1.0, 1.0]:
		for x: float in [-1.0, 1.0]:
			windows.append([Vector3(x * (b - 0.9), 3.45, z * (house_half_len + 0.05)), 0.28, 1.8, Vector3(0, 0, z)])
		windows.append([Vector3(0, wheel_y + 0.85, z * (wheel_half_len + 0.05)), 0.24, 1.4, Vector3(0, 0, z)])

	# Perches: the pilothouse roof, the upper deck's rails, the bulwarks at the open
	# ends, the stacks.
	perches.append([Vector3(0, top + 0.05, -(wheel_half_len - 0.3)), Vector3(0, top + 0.05, wheel_half_len - 0.3), wheel_half_w - 0.3])
	var rail := cabin_top + 0.9
	for x: float in [-1.0, 1.0]:
		perches.append([Vector3(x * (b - 0.1), rail, -(house_half_len - 0.1)), Vector3(x * (b - 0.1), rail, house_half_len - 0.1), 0.0])
		for z: float in [-1.0, 1.0]:
			perches.append([Vector3(x * (b - 0.12), BULWARK_TOP, z * (house_half_len + 0.6)), Vector3(x * (b - 0.12), BULWARK_TOP, z * (l - 2.6)), 0.0])
		perches.append([Vector3(x * stack_dx(), stack_top + 0.05, -0.1), Vector3(x * stack_dx(), stack_top + 0.05, 0.1), 0.0])
	for z: float in [-1.0, 1.0]:
		perches.append([Vector3(-(b - 0.3), rail, z * (house_half_len - 0.1)), Vector3(b - 0.3, rail, z * (house_half_len - 0.1)), 0.0])


## The portal ferry's two exhaust stacks stand on the upper deck at ±stack_dx().
func stack_dx() -> float:
	return wheel_half_w + 0.75


## The portal ferry's cabin windows, evenly down the sides from ±(house_half_len - 0.9).
func cabin_window_step() -> float:
	return 2.0 * (house_half_len - 0.9) / 5.0
