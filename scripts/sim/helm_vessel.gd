class_name HelmVessel
extends Vessel
## A vessel that steers its own way out on open water (see Helm): sailboats,
## motor yachts, fishing boats, pilot boats and tugs. This is the part they share:
## making way on the heading and speed its helm asks for, as fast as the hull
## check lets it, never into another hull or aground, planning round whatever
## holds it up for long, and the rules of the road (helm_role).

const STUCK_REPLAN := 4.0
const CREEP := 1.05             # m/s, working its way out from against another hull
const TAIL_SHOAL := -2.7        # its trailing end never swings over water shallower than this

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
	if safe < target - 0.15:
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
## nearer another hull than it is (`now_gap`, or 0.9 m clear), and without its
## leading end (`lead`, along the way it is moving), its middle or its trailing
## end (swinging out as it turns) going any further over the shallows than it
## is: anywhere deep enough for it is fine, and backing off a shoal always is.
func _safe(p: Vector2, d: Vector2, lead: Vector2, now_gap: float) -> bool:
	if traffic.hull_gap(self, p, d) < minf(0.9, now_gap) - 0.003:
		return false
	var terrain := traffic.sim.terrain
	var cur := Vector2(sin(_yaw), cos(_yaw))
	var now_lead := cur * signf(cur.dot(lead) + 1e-3)
	var deep := -3.0 - (spec.draft - 3.0)
	# Turning where it lies, it only has to keep its ends off the shoals.
	var turning := p.distance_squared_to(pos2()) < 1e-8
	for e: float in [1.0, 0.0, -1.0]:
		var q := p + lead * spec.half_length * e
		var h := terrain.height_at(q.x, q.y)
		if h <= (deep if e > 0.0 and not turning else TAIL_SHOAL):
			continue
		var was := pos2() + now_lead * spec.half_length * e
		if h > terrain.height_at(was.x, was.y) + 0.001:
			return false
	return true


## Held up against another hull for a while: plan round it.
func _check_stuck(delta: float) -> void:
	if speed < 0.3 and clear < 3.0 and blocked_by_hull and is_instance_valid(blocker):
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck < STUCK_REPLAN:
		return
	_stuck = 0.0
	helm.replan(traffic.avoid_circles(blocker, 9.0))


func helm_yaw() -> float:
	return _yaw


# --- The rules of the road ----------------------------------------------------------

## Why it must keep clear of `o` (a Vessel or a Wildlife.Visit), or "" if it is
## the stand-on vessel. Simplified from the collision regulations: everyone keeps
## clear of ships, of anything manoeuvring in or out of a berth and of anything
## restricted in how it can manoeuvre; an overtaking vessel keeps clear of the one
## it is overtaking; power gives way to sail and to a vessel fishing, and sail to
## a vessel fishing; and two of a kind cross by the rules for their kind
## (_same_kind).
func helm_role(o: Variant) -> String:
	if o is Wildlife.Visit:
		return "Keeping clear of the " + (o as Wildlife.Visit).species.plural.to_lower()
	if not (o is Vessel):
		return "Keeping clear"
	var v := o as Vessel
	match v.road():
		Road.MOORED:
			# Lying at a berth or at anchor: just don't hit it.
			return ""
		Road.MANOEUVRING:
			return "Giving way to %s, manoeuvring" % v.vessel_name
		Road.SHIP:
			return "Giving way to " + v.vessel_name
		Road.RESTRICTED:
			return "Giving way to %s, %s" % [v.vessel_name, v.restricted_text()]
	var me := road()
	if me == Road.RESTRICTED or me == Road.SHIP:
		return ""
	if _overtaking(v):
		return "Overtaking " + v.vessel_name
	var mine := _precedence(me)
	var theirs := _precedence(v.road())
	if mine != theirs:
		if mine > theirs:
			return ""
		return "Giving way to %s, %s" % [v.vessel_name, "fishing" if v.road() == Road.FISHING else "under sail"]
	return _same_kind(v)


## Who gives way to whom out on open water: power to sail and fishing, sail to
## fishing.
static func _precedence(r: Road) -> int:
	match r:
		Road.FISHING:
			return 3
		Road.SAIL:
			return 2
	return 1


## Two of a kind meeting (neither overtaking): power vessels (and two fishing)
## cross by the starboard rule. Sailboats under sail have their own (Sailboat).
func _same_kind(o: Vessel) -> String:
	return _crossing(o)


## Coming up from more than 22.5° abaft its beam, and faster.
func _overtaking(o: Vessel) -> bool:
	var rel := pos2() - o.pos2()
	return rel.dot(o.heading2()) < -rel.length() * 0.38 and speed > o.speed + 0.3


## Two power vessels crossing: the one with the other on its starboard side gives way.
func _crossing(o: Vessel) -> String:
	var right := Vector2(-cos(_yaw), sin(_yaw))
	return "Giving way to " + o.vessel_name if (o.pos2() - pos2()).dot(right) > 0.0 else ""
