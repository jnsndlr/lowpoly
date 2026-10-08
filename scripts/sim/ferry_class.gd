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

const LANE_SPACING := 4.5
const ROW_SPACING := 7.5
# Side-house ferries' house and stack top heights.
const OPEN_DECK_Y := 3.0
const BULWARK_TOP := 5.7
# Full ferries' deck heights (as the size-4 boat was first built).
const MAST_TOP := 27.6
const SIDELIGHT_Y := 20.94

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
var tall := PackedInt32Array()     # lanes with the headroom for trucks (none listed: all)
var cols := PackedFloat32Array()   # lane centres (x), port to starboard
var row_z := PackedFloat32Array()  # row centres (z), +Z end first
var end_z := 42.0                  # where cars cross the hull's end
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
	else:
		for i in lanes:
			cols.append((i - (lanes - 1) * 0.5) * LANE_SPACING)
		_lay_out_full()
	var c := chamfer
	hull_radius = maxf(half_beam, (half_beam * half_beam + c * c) / (2.0 * c) - 0.42)


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
