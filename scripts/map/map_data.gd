class_name MapData
extends RefCounted
## Pure data describing a map: islands, terminals, towns and routes.
## Produced by MapGenerator today (and by a map editor later); WorldBuilder and
## Simulation only read from it, so hand-authored maps can plug straight in.


class Island:
	var id := 0
	var name := ""
	var center := Vector2.ZERO      # x, z
	var radius := 40.0
	var strength := 1.0             # elevation multiplier
	var inhabited := true
	var is_mainland := false
	var population := 0
	var growth := 0.0               # base % per year
	var wildlife_appeal := 1.0      # how strongly it pulls marine wildlife visits

	# Ferry terminal (valid when has_terminal)
	var has_terminal := false
	var shore := Vector3.ZERO       # where the pier meets land, y = 0
	var dock_dir := Vector3.FORWARD # horizontal unit vector pointing out to sea
	var slips: Array[int] = []      # route ids, ordered left → right along lateral()
	var lot_half_width := 12.0

	# Town
	var town_center := Vector3.ZERO
	var town_axis := Vector3.RIGHT
	var road_main_a := PackedVector3Array()   # lot entrance → town centre
	var road_main_b := PackedVector3Array()   # town centre → inland end
	var road_cross: Array[PackedVector3Array] = []
	var label_pos := Vector3.ZERO

	func lateral() -> Vector3:
		return Vector3.UP.cross(dock_dir)

	func terminal_xform() -> Transform3D:
		return Transform3D(Basis(lateral(), Vector3.UP, dock_dir), shore)

	func slip_offset(i: int) -> float:
		return (i - (slips.size() - 1) * 0.5) * Layout.SLIP_SPACING

	func slip_index(route_id: int) -> int:
		return slips.find(route_id)

	func dock_center(route_id: int) -> Vector3:
		return shore + dock_dir * Layout.DOCK_U + lateral() * slip_offset(slip_index(route_id))


## Somewhere boats tie up along a shore. Its frame is like a terminal's: origin
## where the pier meets the shore, +Z ("u") out to sea, +X ("v") lateral.
class Harbour:
	var id := 0
	var island := 0                 # island id
	var shore := Vector3.ZERO       # where the pier meets land, y = 0
	var dir := Vector3.FORWARD      # horizontal unit vector pointing out to sea

	func lateral() -> Vector3:
		return Vector3.UP.cross(dir)

	func xform() -> Transform3D:
		return Transform3D(Basis(lateral(), Vector3.UP, dir), shore)

	func at(u: float, v: float) -> Vector3:
		return shore + dir * u + lateral() * v

	func berths() -> int:
		return 0

	## Berth `i`'s place along v.
	func berth_v(_i: int) -> float:
		return 0.0

	## Where a boat lines up to come in (u, v).
	func approach() -> Vector2:
		return Vector2.ZERO

	## Where boats waiting to come in may hold: no nearer the shore than `x`, and
	## no nearer the centre line than `y` (to keep out of the approach).
	func wait_bounds() -> Vector2:
		return Vector2.ZERO

	## How far apart boats waiting here hold station.
	func wait_spacing() -> float:
		return 7.0

	## Whether a boat may wait its turn at (u, v) (out of the way in).
	func wait_ok(_u: float, _v: float) -> bool:
		return true


## A small-boat pier with a T-head (see Layout's marina frame).
class Marina extends Harbour:
	func berth_v(i: int) -> float:
		return (i - (Layout.MARINA_BERTHS - 1) * 0.5) * Layout.MARINA_BERTH_SPACING

	func berths() -> int:
		return Layout.MARINA_BERTHS

	func approach() -> Vector2:
		return Vector2(Layout.MARINA_APPROACH_U, 0.0)

	func wait_bounds() -> Vector2:
		return Vector2(40.0, Layout.MARINA_HEAD_HALF + 12.0)


## A wharf boats lie alongside (see Layout's quay frame): a jetty out to a wharf
## whose seaward face the boats lie against, bow to stern, all pointing `side`
## along v. They come in along the lane off the face from astern and crab in
## sideways, and leave the same way round: crab out, then ahead along the lane.
class Wharf extends Harbour:
	var side := 1.0

	func approach() -> Vector2:
		return Vector2(Layout.QUAY_LANE_U, -side * Layout.QUAY_RUN)

	func wait_bounds() -> Vector2:
		return Vector2(Layout.QUAY_LANE_U + 20.0, 0.0)

	func wait_spacing() -> float:
		return 32.0

	## Not off the end of the lane where boats run in.
	func wait_ok(_u: float, v: float) -> bool:
		return absf(v + side * Layout.QUAY_RUN) > 30.0

	## Its name, as the HUD shows it.
	func title(map: MapData) -> String:
		return map.islands[island].name


## The fishing boats' wharf.
class FishQuay extends Wharf:
	func berth_v(i: int) -> float:
		return (i - (Layout.QUAY_BERTHS - 1) * 0.5) * Layout.QUAY_BERTH_SPACING

	func berths() -> int:
		return Layout.QUAY_BERTHS

	func title(map: MapData) -> String:
		return map.islands[island].name + " fish quay"


## Where the pilot boats and tugs that work with the ships are based.
class PilotStation extends Wharf:
	func berth_v(i: int) -> float:
		return (i - (Layout.STATION_BERTHS - 1) * 0.5) * Layout.STATION_BERTH_SPACING

	func berths() -> int:
		return Layout.STATION_BERTHS

	func title(map: MapData) -> String:
		return map.islands[island].name + " pilot station"


class Route:
	var id := 0
	var a := 0      # island id
	var b := 0
	var curve: Curve3D
	var length := 0.0


var map_seed := 0
var half_size := 460.0
var islands: Array[Island] = []
var routes: Array[Route] = []
var marinas: Array[Marina] = []
var quays: Array[FishQuay] = []
var stations: Array[PilotStation] = []


## Every wharf on the map: fish quays and pilot stations.
func wharves() -> Array[Wharf]:
	var out: Array[Wharf] = []
	out.append_array(quays)
	out.append_array(stations)
	return out
