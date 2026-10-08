class_name WharfBoat
extends HelmVessel
## A vessel based at a wharf (MapData.Wharf): fishing boats at their fish quay,
## pilot boats and tugs at the pilot station. This is the part they share.
##
## Alongside, it lies against the wharf's face pointing along it. It comes in
## along the lane off the face from astern and crabs in sideways, and leaves the
## same way round (crab out, then ahead along the lane); those manoeuvres take
## the wharf's lock (MarineTraffic.try_lock), and an arriving boat waits its turn
## off the wharf (MarineTraffic.wait_spot). Out on the water a Helm steers it.

const CRAB_SPEED := 1.8

var wharf: MapData.Wharf
var berth := 0
var path: NavPath              # the leg it is following in or out of its berth
var s := 0.0
var _legs: Array = []          # [[NavPath, crab], ...] the legs still to follow after this one
var _crab := false             # moving sideways along `path`, not ahead
var _coming_in := false        # (rather than leaving)
var crab_speed := CRAB_SPEED
var _hull: MeshInstance3D


# --- Hooks ----------------------------------------------------------------------------

## Lying at its berth.
func _alongside() -> bool:
	return false


## Waiting off the wharf for its turn to come in.
func _waiting_in() -> bool:
	return false


## Out along the lane from its berth: the passage begins (the wharf's lock is let go).
func _left_berth() -> void:
	pass


## In alongside its berth (the wharf's lock is let go).
func _came_alongside() -> void:
	pass


## Its attitude on the water, each frame it is under way.
func _pose(_delta: float) -> void:
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.BACK, sin(_bob * 0.83) * 0.02)


# --- Alongside ------------------------------------------------------------------------

func wharf_name() -> String:
	return wharf.title(traffic.sim.map)


## Its centre lying alongside berth `b`.
func _berth_pos(b: int) -> Vector2:
	var p := wharf.at(Layout.QUAY_FACE_U + Layout.QUAY_FENDER + spec.half_beam, wharf.berth_v(b))
	return Vector2(p.x, p.z)


func _lane_pos(v: float) -> Vector2:
	var p := wharf.at(Layout.QUAY_LANE_U, v)
	return Vector2(p.x, p.z)


func _along_yaw() -> float:
	var d := wharf.lateral() * wharf.side
	return atan2(d.x, d.z)


## Made fast alongside its berth.
func _lie_alongside() -> void:
	free_nav = false
	speed = 0.0
	path = null
	helm = null
	_yaw = _along_yaw()
	_pose_alongside()


func _pose_alongside() -> void:
	var p := _berth_pos(berth)
	position = Vector3(p.x, sin(_bob * 1.1) * 0.15, p.y)
	basis = Basis(Vector3.UP, _yaw + sin(_bob * 0.29) * 0.008) * Basis(Vector3.BACK, sin(_bob * 0.9) * 0.012)


# --- In and out -----------------------------------------------------------------------

## Crabs out of its berth into the lane, then runs ahead along it (the caller
## holds the wharf's lock).
func _leave() -> void:
	_coming_in = false
	var out := _lane_pos(wharf.berth_v(berth))
	_legs = [[NavPath.new(PackedVector2Array([out, _lane_pos(wharf.side * Layout.QUAY_RUN)])), false]]
	_start_leg(NavPath.new(PackedVector2Array([_berth_pos(berth), out])), true)


## In along the lane from astern to abreast of its berth, then crabs in (the
## caller holds the wharf's lock).
func _come_in() -> void:
	_coming_in = true
	free_nav = false
	helm = null
	var a := _lane_pos(-wharf.side * Layout.QUAY_RUN)
	var b := _lane_pos(wharf.berth_v(berth))
	var main := traffic.nav.find_path(pos2(), a, false)
	if main.is_empty():
		main = PackedVector2Array([pos2(), a])
	main.append(b)
	main = traffic.nav.finish(main, 0.0, 30.0, 2, hull_radius + 3.0)
	main[main.size() - 1] = b
	_legs = [[NavPath.new(PackedVector2Array([b, _berth_pos(berth)])), true]]
	_start_leg(NavPath.new(main), false)


func _start_leg(p: NavPath, crab: bool) -> void:
	path = p
	s = 0.0
	_crab = crab


func _follow_path(delta: float) -> void:
	var left := path.length - s
	var top := crab_speed if _crab else spec.motor_speed
	var target := top
	# It stops at the end of each leg but the last one out, which runs on into
	# the open water.
	if _crab or _coming_in or not _legs.is_empty():
		target = minf(top, 0.45 + sqrt(2.0 * 0.6 * left))
	target = minf(target, yield_speed())
	speed = move_toward(speed, target, (spec.accel if target > speed else spec.decel) * delta)
	s = minf(s + speed * delta, path.length)
	if not _crab:
		var t := path.tangent(s)
		_yaw = rotate_toward(_yaw, atan2(t.x, t.y), spec.motor_turn * delta)
	var p := path.sample(s)
	position = Vector3(p.x, sin(_bob * 1.1) * 0.15, p.y)
	_pose(delta)
	if left > 0.15:
		return
	if not _legs.is_empty():
		var next: Array = _legs.pop_front()
		_start_leg(next[0], next[1])
		return
	path = null
	traffic.unlock(wharf, self)
	if _coming_in:
		_came_alongside()
	else:
		_left_berth()


# --- Vessel ---------------------------------------------------------------------------

func waiting_on() -> Array[Vessel]:
	var out := super()
	if _waiting_in():
		var h := traffic.lock_holder(wharf)
		if h != null:
			out.append(h)
	return out


func wants_to_move() -> bool:
	return not _alongside()


func crabbing() -> bool:
	return path != null and _crab


func ahead(d: float) -> Vector2:
	if path != null:
		return path.sample(s + d)
	if _alongside():
		return pos2()
	return pos2() + Vector2(sin(_yaw), cos(_yaw)) * d


func path_left() -> float:
	if path != null:
		return path.length - s
	if helm != null:
		return helm.distance_left() + 30.0
	return 0.0
