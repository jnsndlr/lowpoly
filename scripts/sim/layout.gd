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
# Far enough apart that ferries at neighbouring slips, lying alongside or
# coming and going straight in and out, never come near each other.
const SLIP_SPACING := 20.0
const FERRY_HALF := 15.0
const DOCK_U := PIER_END + FERRY_HALF + 0.4  # centre of a 30 m hull docked (route ends)
# Each slip's wing walls (u, v of the starboard one's ends, mirrored to port): one
# straight wall either side, splayed WING_ANGLE off the centreline, that takes
# any size of hull's end.
const WING_ANGLE := deg_to_rad(38.0)
const WING_LENGTH := 8.0
const WING_WALL := [Vector2(PIER_END + 0.3, 3.0),
	Vector2(PIER_END + 0.3 + WING_LENGTH * cos(WING_ANGLE), 3.0 + WING_LENGTH * sin(WING_ANGLE))]
# Guide dolphins either side of each slip (u, v off the centreline, cluster
# radius): an inner pair the longer hulls lie against, and a lit outer pair that
# lines ferries up coming in.
const DOLPHIN_INNER := Vector3(PIER_END + 17.0, 5.9, 1.05)
const DOLPHIN_OUTER := Vector3(PIER_END + 29.0, 6.9, 1.35)
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


# Fish quay frame, like a marina's. A jetty runs out to a wharf along v whose
# seaward face (at QUAY_FACE_U) the boats lie alongside, bow to stern, pointing
# the quay's `side` along v. They come and go along the lane QUAY_LANE_U out,
# running QUAY_RUN either side of the wharf, crabbing between it and the berth.
const QUAY_JETTY_END := 7.0
const QUAY_FACE_U := 13.0
const QUAY_HALF := 24.0            # the wharf's half length along v
const QUAY_BERTHS := 2
const QUAY_BERTH_SPACING := 23.0
const QUAY_FENDER := 0.5           # between the face and a hull lying alongside
const QUAY_LANE_U := 30.0
const QUAY_RUN := 60.0
# A pilot station is laid out like a fish quay, with a berth more for its
# shorter boats.
const STATION_BERTHS := 3
const STATION_BERTH_SPACING := 16.0


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
