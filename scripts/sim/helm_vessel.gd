class_name HelmVessel
extends Vessel
## A vessel that steers its own way out on open water (see Helm): sailboats and
## fishing boats. This is the part they share: making way on the heading and speed
## its helm asks for, as fast as the hull check lets it, never into another hull or
## aground, and planning round whatever holds it up for long.

const STUCK_REPLAN := 4.0
const CREEP := 0.35             # m/s, working its way out from against another hull

var traffic: MarineTraffic
var helm: Helm
var brake_time := 0.0          # (for the soak test) time the hull check has held it back under way
var _yaw := 0.0
var _bob := 0.0
var _stuck := 0.0
var _jammed := 0.0


## Turns towards `want_yaw` at `turn` rad/s and makes for `target` m/s (as far as
## helm_speed() on its new heading allows; with no more drive than that it slows
## at _coast() rather than braking), then moves. If it can't go on it turns where
## it lies; if it can't do that either (a long hull's ends swing a long way), it
## creeps straight ahead or astern, whichever opens the gap more, until it can.
func _make_way(delta: float, want_yaw: float, target: float, turn: float) -> void:
	var yaw := rotate_toward(_yaw, want_yaw, turn * delta)
	var decel := spec.decel
	var drive := helm_speed(yaw)
	if drive < target:
		target = drive
		decel = _coast()
	var safe := yield_speed()
	if safe < target - 0.05:
		brake_time += delta
		target = safe
		decel = spec.decel
	speed = move_toward(speed, target, (spec.accel if target > speed else decel) * delta)
	var d := Vector2(sin(yaw), cos(yaw))
	var p := pos2() + d * speed * delta
	# Never into another hull, even by swinging its stern round, nor aground.
	var here := pos2()
	var cur := Vector2(sin(_yaw), cos(_yaw))
	var now_gap := traffic.hull_gap(self, here, cur)
	if _safe(p, d, d, now_gap):
		_yaw = yaw
		position = Vector3(p.x, position.y, p.y)
		_jammed = 0.0
	else:
		speed = 0.0
		brake_time += delta
		if _safe(here, d, d, now_gap):
			_yaw = yaw
			_jammed = 0.0
		else:
			_jammed += delta
			if _jammed > 1.0:
				var fwd := here + cur * CREEP * delta
				var back := here - cur * CREEP * delta
				var ok_f := _safe(fwd, cur, cur, now_gap)
				var ok_b := _safe(back, cur, -cur, now_gap)
				if ok_f and ok_b:
					ok_f = traffic.hull_gap(self, fwd, cur) >= traffic.hull_gap(self, back, cur)
					ok_b = not ok_f
				var to := fwd if ok_f else back
				if ok_f or ok_b:
					position = Vector3(to.x, position.y, to.y)
	_check_stuck(delta)


## How quickly it slows with nothing driving it.
func _coast() -> float:
	return spec.decel


## Whether its hull could lie at `p` heading along `d` without getting any
## nearer another hull than it is (`now_gap`, or 0.3 m clear), or any further
## aground at its leading end (`lead`, along the way it is moving).
func _safe(p: Vector2, d: Vector2, lead: Vector2, now_gap: float) -> bool:
	if traffic.hull_gap(self, p, d) < minf(0.3, now_gap) - 0.001:
		return false
	var here := pos2() + lead * spec.half_length
	var tip := p + lead * spec.half_length
	var h := traffic.sim.terrain.height_at(tip.x, tip.y)
	return h <= -1.0 - (spec.draft - 1.0) or h <= traffic.sim.terrain.height_at(here.x, here.y)


## Held up against another hull for a while: plan round it.
func _check_stuck(delta: float) -> void:
	if speed < 0.1 and clear < 1.0 and blocked_by_hull and is_instance_valid(blocker):
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck < STUCK_REPLAN:
		return
	_stuck = 0.0
	helm.replan(traffic.avoid_circles(blocker, 3.0))


func helm_yaw() -> float:
	return _yaw
