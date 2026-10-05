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


## A small-boat pier with a T-head (see Layout's marina frame).
class Marina:
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

	func berth_v(i: int) -> float:
		return (i - (Layout.MARINA_BERTHS - 1) * 0.5) * Layout.MARINA_BERTH_SPACING


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
