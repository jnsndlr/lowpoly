class_name Layout
extends RefCounted
## Shared dimensions for terminals, ferries and vehicles. A car is ~2 units long.
##
## Terminal-local frame: origin where the pier meets the shore, +Z ("u") points out to
## sea along the pier, +X ("v") is lateral. The holding lot sits at negative u.

const LOT_Y := 1.05             # top surface of lot, piers and ferry car deck
const LOT_FRONT := -2.0         # seaward edge of the holding lot
const LOT_LENGTH := 24.0
const LOT_BACK := LOT_FRONT - LOT_LENGTH  # road entrance edge
const PIER_END := 10.0          # end of the pier / transfer span
const LANE_HEAD := -5.0         # first queue slot in each lane
const LANE_WIDTH := 2.4
const EXIT_CLEAR := 2.9         # lanes keep clear of the central exit lane
const EXIT_V := 0.8             # lateral position of the exit lane
const SLOT := 2.6               # spacing between queued cars
const SLIP_SPACING := 11.0
const FERRY_HALF := 15.0
const DOCK_U := PIER_END + FERRY_HALF + 0.4  # ferry centre when docked
const DECK_Y := LOT_Y

# Marina frame, like a terminal's: origin where the pier meets the shore, +Z ("u")
# out along the pier. The pier ends in a T-head; sailboats lie bow-in against its
# seaward face, side by side, and back straight out to MARINA_BACKOUT_U to leave.
const MARINA_PIER_END := 16.0
const MARINA_HEAD_U := 17.0        # centre of the T-head float
const MARINA_HEAD_HALF := 7.2      # its half length along v
const MARINA_BERTHS := 4
const MARINA_BERTH_SPACING := 3.0
const MARINA_BERTH_U := 20.6       # moored hull centre (bow just off the float)
const MARINA_BACKOUT_U := 29.0     # where a departing boat stops reversing
const MARINA_APPROACH_U := 33.0    # where an arriving boat lines up for its berth


## Lateral lane positions grouped per slip (left → right), clear of the exit lane.
static func lane_positions(half_width: float, slip_count: int) -> Array[PackedFloat32Array]:
	var all: Array[float] = []
	var v := EXIT_CLEAR
	while v <= half_width - 1.3:
		all.append(v)
		all.append(-v)
		v += LANE_WIDTH
	all.sort()
	var result: Array[PackedFloat32Array] = []
	var per := floori(float(all.size()) / maxi(slip_count, 1))
	for s in slip_count:
		var chunk := PackedFloat32Array()
		for k in per:
			chunk.append(all[s * per + k])
		result.append(chunk)
	return result


static func slots_per_lane() -> int:
	return int((LANE_HEAD - (LOT_BACK + 3.5)) / SLOT) + 1
