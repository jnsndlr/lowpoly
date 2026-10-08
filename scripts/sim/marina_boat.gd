class_name MarinaBoat
extends HelmVessel
## A small boat kept at a marina berth: sailboats and motor yachts. This is the
## part they share: backing straight out of its berth to leave, and coming in
## from off the marina along a set leg to berth bow-in. Both manoeuvres take the
## marina's lock (MarineTraffic.try_lock); a boat arriving while another holds it
## waits its turn off the marina (MarineTraffic.wait_spot). Its berth is held for
## it while it is away (MarineTraffic.reserve_berth).

const REVERSE_SPEED := 2.1
# The hull length the marina's berths are laid out for (Layout.MARINA_BERTH_U);
# longer boats lie further out.
const BERTH_HALF_LENGTH := 5.4

var marina: MapData.Marina     # where it is moored, or where it last left from
var berth := 0
var dest: MapData.Marina       # where it is bound (its berth there reserved)
var dest_berth := 0
var path: NavPath              # the leg it is motoring along (backing out, or in to its berth)
var s := 0.0
var trips := 0
var _hull: MeshInstance3D
var _leaving: MapData.Marina = null    # holds this marina's lock while getting out
var _arriving := false                 # holds the destination's lock


# --- Hooks ----------------------------------------------------------------------------

## Lying in its berth.
func _moored() -> bool:
	return false


## Waiting off the destination marina for its turn to berth.
func _waiting_in() -> bool:
	return false


## Backed out of its berth (it still holds the marina's lock: _let_go when clear).
func _backed_out() -> void:
	pass


## In its new berth (marina and berth are now it).
func _berthed() -> void:
	pass


## Its attitude on the water, each frame it is manoeuvring.
func _pose(_delta: float) -> void:
	basis = Basis(Vector3.UP, _yaw)


# --- At the berth ---------------------------------------------------------------------

func marina_name(m: MapData.Marina) -> String:
	return traffic.sim.map.islands[m.island].name + " Marina"


## A point on berth `b`'s line at `u` out from the shore, for this boat's centre
## (a longer boat lies, and backs out, a little further out).
func _berth_pos(m: MapData.Marina, b: int, u: float) -> Vector2:
	var p := m.at(u + spec.half_length - BERTH_HALF_LENGTH, m.berth_v(b))
	return Vector2(p.x, p.z)


## Made fast in its berth, bow to the float.
func _make_fast() -> void:
	_let_go()
	free_nav = false
	speed = 0.0
	path = null
	helm = null
	var d := -marina.dir
	_yaw = atan2(d.x, d.z)


func _pose_moored() -> void:
	var p := _berth_pos(marina, berth, Layout.MARINA_BERTH_U)
	position = Vector3(p.x, sin(_bob * 1.4) * 0.12, p.y)
	basis = Basis(Vector3.UP, _yaw + sin(_bob * 0.37) * 0.03) * Basis(Vector3.BACK, sin(_bob * 1.1) * 0.025)


# --- Out and in -----------------------------------------------------------------------

## Starts backing out of its berth (the caller holds the marina's lock).
func _start_backing_out() -> void:
	_leaving = marina
	path = NavPath.new(PackedVector2Array([_berth_pos(marina, berth, Layout.MARINA_BERTH_U),
		_berth_pos(marina, berth, Layout.MARINA_BACKOUT_U)]))
	s = 0.0


func _back_out(delta: float) -> void:
	var left := path.length - s
	var target := minf(REVERSE_SPEED, 0.6 + sqrt(2.0 * 1.2 * left))
	target = minf(target, yield_speed())
	speed = minf(target, speed + spec.accel * delta)
	s = minf(s + speed * delta, path.length)
	var p := path.sample(s)
	position = Vector3(p.x, sin(_bob * 1.6) * 0.15, p.y)
	_pose(delta)
	if path.length - s < 0.15:
		path = null
		_backed_out()


## Whether it has motored far enough from the marina it is leaving to let go of it.
func _clear_of_marina(dist: float) -> bool:
	return _leaving != null and pos2().distance_to(_berth_pos(_leaving, berth, Layout.MARINA_BACKOUT_U)) > dist


## Lets go of the marina it is leaving.
func _let_go() -> void:
	if _leaving:
		traffic.unlock(_leaving, self)
		_leaving = null


## Leaves the helm for the set leg in to its berth (it holds the marina's lock).
func _start_berthing() -> void:
	_let_go()
	_arriving = true
	free_nav = false
	helm = null
	path = _plan_berthing()
	s = 0.0


## From where it is to the approach point, then straight in to the berth.
func _plan_berthing() -> NavPath:
	var to := _berth_pos(dest, dest_berth, Layout.MARINA_APPROACH_U)
	var main := traffic.nav.find_path(pos2(), to, false)
	if main.is_empty():
		main = PackedVector2Array([pos2(), to])
	main = traffic.nav.finish(main, 0.0, 18.0, 2, hull_radius + 3.0)
	main.append(_berth_pos(dest, dest_berth, Layout.MARINA_BERTH_U))
	return NavPath.new(main)


func _berth_in(delta: float) -> void:
	var left := path.length - s
	var target := minf(spec.motor_speed * 0.6, 0.9 + sqrt(2.0 * 0.9 * left))
	target = minf(target, yield_speed())
	speed = minf(target, speed + spec.accel * delta)
	s = minf(s + speed * delta, path.length)
	var t := path.tangent(s)
	_yaw = rotate_toward(_yaw, atan2(t.x, t.y), spec.motor_turn * delta)
	var p := path.sample(s)
	position = Vector3(p.x, sin(_bob * 1.6) * 0.15, p.y)
	_pose(delta)
	if path.length - s < 0.06:
		traffic.unlock(dest, self)
		_arriving = false
		marina = dest
		berth = dest_berth
		trips += 1
		_berthed()


# --- Vessel ---------------------------------------------------------------------------

func waiting_on() -> Array[Vessel]:
	var out := super()
	if _waiting_in():
		var h := traffic.lock_holder(dest)
		if h != null:
			out.append(h)
	return out


func wants_to_move() -> bool:
	return not _moored()


func ahead(d: float) -> Vector2:
	if path != null:
		return path.sample(s + d)
	if _moored():
		return pos2()
	return pos2() + Vector2(sin(_yaw), cos(_yaw)) * d


func path_left() -> float:
	if path != null:
		return path.length - s
	if helm != null:
		return helm.distance_left() + 30.0
	return 0.0
