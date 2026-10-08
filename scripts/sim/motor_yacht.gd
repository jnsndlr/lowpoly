class_name MotorYacht
extends MarinaBoat
## A motor yacht kept at a marina berth. Most days out it runs to a cove
## (Anchorage) for a swim and lunch and lies at anchor for a few hours, now and
## then for the night; sometimes it cruises to another marina instead, or just
## goes out for a run and home. It goes out far more in summer than in winter,
## and only leaves in daylight.
##
## Out on open water a Helm steers it, at speed on the plane, its bow lifting as
## it climbs over its own bow wave and settling as it gets on top. It comes off
## the plane to no-wake speed near harbours, among anchored and moored boats, and
## in coves. It is a power-driven vessel (HelmVessel.helm_role): it gives way to
## sail and to vessels fishing, keeps clear of ships, and crosses other power
## vessels by the starboard rule.
##
## To anchor it noses up into the wind to its spot, lets go and drops back on its
## cable; at anchor it lies head to wind, swinging a little, and at night shows
## its anchor light.

enum State { MOORED, LEAVING, CRUISING, ANCHORING, SETTING, ANCHORED, WEIGHING, WAITING, ARRIVING }
enum Trip { COVE, MARINA, RUN }

const LEAVE_HOURS := Vector2(8.5, 14.0)
const BACK_BY := 18.5          # weighs anchor for home by then (unless staying the night)
const MORNING := Vector2(7.5, 10.5)   # leaving an overnight anchorage
const AT_ANCHOR := Vector2(90.0, 300.0)    # game minutes
const DWELL := Vector2(120.0, 400.0)       # in a berth after a trip
# Chance it goes out on a given day, by season (spring, summer, autumn, winter).
const OUTINGS := [0.55, 0.9, 0.5, 0.2]
const OVERNIGHT := [0.12, 0.3, 0.1, 0.0]
const GOAL_R := 36.0
const HOLD_R := 24.0
const CLEAR_OF_MARINA := 66.0
const SCOPE := 15.0             # how far it lies back from its anchor
const APPROACH := 84.0         # lines up this far downwind of its spot
const ANCHOR_SPEED := 2.4
const SET_SPEED := 1.05
const WEIGH_TIME := 20.0
# Where it comes off the plane: near harbours, near anything lying at a berth or
# at anchor, and in coves.
const NO_WAKE_HARBOUR := 225.0
const NO_WAKE_MOORED := 135.0
const NO_WAKE_COVE := 210.0

var state := State.MOORED
var trip := Trip.COVE
var dwell := 0.0
var spot: Anchorage.Spot
var overnight := false
var _outbound := false         # bound for its cove (rather than home)
var _goals: Array[Vector2] = []
var _leave_at := 0.0            # (anchored) when it weighs anchor
var _timer := 0.0
var _swing := 0.0
var _no_wake := false
var _no_wake_check := 0.0
var _trim := 0.0
var _roll := 0.0
var _last_yaw := 0.0
var _nav_lights: MeshInstance3D
var _mast_light: MeshInstance3D
var _rode: MeshInstance3D


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, m: MapData.Marina, b: int, variant: int, first_dwell: float) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	_hull = apply_spec(sp, variant)
	_nav_lights = MeshInstance3D.new()
	_nav_lights.mesh = Models.motor_yacht_nav_lights()
	_mast_light = MeshInstance3D.new()
	_mast_light.mesh = Models.motor_yacht_mast_light()
	for l: MeshInstance3D in [_nav_lights, _mast_light]:
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.layers = NightLights.LAYER
		lights.add_child(l)
	_rode = MeshInstance3D.new()
	_rode.mesh = Models.motor_yacht_rode()
	_rode.visible = false
	_hull.add_child(_rode)
	marina = m
	berth = b
	dwell = first_dwell
	_bob = t.rng.randf() * TAU
	_swing = t.rng.randf() * TAU
	_moor()


func _process(delta: float) -> void:
	_bob += delta
	_swing += delta
	match state:
		State.MOORED:
			dwell -= delta
			var h := traffic.sim.hour()
			if dwell <= 0.0 and h >= LEAVE_HOURS.x and h < LEAVE_HOURS.y:
				_maybe_go_out()
			_pose_moored()
		State.LEAVING:
			_back_out(delta)
		State.CRUISING, State.ANCHORING, State.WAITING:
			_navigate(delta)
		State.SETTING:
			_set_anchor(delta)
		State.ANCHORED:
			_lie_at_anchor(delta)
		State.WEIGHING:
			_weigh(delta)
		State.ARRIVING:
			_berth_in(delta)
	_show_lights()
	var under_way := state in [State.CRUISING, State.ANCHORING, State.WAITING, State.ARRIVING]
	var d := Vector3(sin(_yaw), 0.0, cos(_yaw))
	wake.update(delta, global_position, d, speed * delta if under_way else 0.0,
			clampf(speed / cruise, 0.0, 1.0) if under_way else 0.0, under_way and speed > 0.3)


func _now() -> float:
	return traffic.sim.day * 1440.0 + traffic.sim.minutes


func _moor() -> void:
	state = State.MOORED
	_make_fast()
	_pose_moored()


## Whether today is a day out (more likely in summer); if not, it looks again
## tomorrow morning.
func _maybe_go_out() -> void:
	var season := traffic.sim.season() % 4
	if traffic.rng.randf() > OUTINGS[season]:
		dwell = (24.0 - traffic.sim.hour() + LEAVE_HOURS.x) * 60.0 + traffic.rng.randf_range(0.0, 120.0)
		return
	depart()


## Casts off on a trip: to a cove if there is a spot free (mostly), otherwise to
## another marina's free berth, otherwise out for a run and home. Holds its own
## berth while it is away, unless bound for another marina.
func depart() -> void:
	if not traffic.try_lock(marina, self):
		dwell = 3.0
		return
	var from := _berth_pos(marina, berth, Layout.MARINA_BACKOUT_U)
	var r := traffic.rng.randf()
	var goals: Array[Vector2] = []
	if r < 0.68:
		var sp := traffic.reserve_spot(self, from)
		if sp != null:
			trip = Trip.COVE
			spot = sp
			_outbound = true
			overnight = traffic.rng.randf() < OVERNIGHT[traffic.sim.season() % 4]
			goals.append(_approach_point())
	if goals.is_empty() and r < 0.88 and traffic.sim.map.marinas.size() > 1:
		var pick := traffic.reserve_berth(self)
		if not pick.is_empty() and pick[0] != marina:
			trip = Trip.MARINA
			traffic.release_berth(marina, berth, self)
			dest = pick[0]
			dest_berth = pick[1]
			goals.append(traffic.wait_spot(dest, dest_berth))
		elif not pick.is_empty() and (pick[0] != marina or pick[1] != berth):
			traffic.release_berth(pick[0], pick[1], self)
	if goals.is_empty():
		trip = Trip.RUN
		for k in traffic.rng.randi_range(1, 2):
			var via := _waypoint(from if goals.is_empty() else goals.back())
			if via != Vector2.INF:
				goals.append(via)
		if goals.is_empty():
			traffic.unlock(marina, self)
			dwell = 60.0
			return
		goals.append(traffic.wait_spot(marina, berth))
	if trip != Trip.MARINA:
		dest = marina
		dest_berth = berth
	_goals = goals
	_arriving = false
	_stuck = 0.0
	state = State.LEAVING
	_start_backing_out()


## Somewhere out on open water for a run.
func _waypoint(from: Vector2) -> Vector2:
	var nav := traffic.nav
	var lim := traffic.sim.map.half_size - 120.0
	for k in 16:
		var a := traffic.rng.randf() * TAU
		var p := from + Vector2(cos(a), sin(a)) * traffic.rng.randf_range(360.0, 900.0)
		if absf(p.x) < lim and absf(p.y) < lim and nav.open_at(p, false) and not nav.find_path(from, p, false).is_empty():
			return p
	return Vector2.INF


## Starts it lying at anchor in a cove (for boats already out when the map opens).
func start_at_anchor() -> bool:
	var sp := traffic.reserve_spot(self, pos2())
	if sp == null:
		return false
	spot = sp
	trip = Trip.COVE
	dest = marina
	dest_berth = berth
	overnight = traffic.sim.hour() < 7.0
	_anchored()
	_leave_at = _now() + traffic.rng.randf_range(AT_ANCHOR.x, AT_ANCHOR.y) * 0.6
	if overnight:
		_leave_at = _morning()
	return true


# --- Out on the water ---------------------------------------------------------------

func _backed_out() -> void:
	state = State.CRUISING
	free_nav = true
	helm = Helm.new(self, traffic)
	helm.set_goal(_goals[0])


func _navigate(delta: float) -> void:
	if _clear_of_marina(CLEAR_OF_MARINA):
		_let_go()
	match state:
		State.CRUISING:
			if helm.distance_left() < GOAL_R:
				if _goals.size() > 1:
					_goals.pop_front()
					helm.set_goal(_goals[0])
				elif _outbound:
					state = State.ANCHORING
					helm.set_goal(spot.pos)
				elif traffic.try_lock(dest, self):
					_begin_berthing()
					return
				else:
					_let_go()
					state = State.WAITING
					traffic.queue_for(dest, self)
		State.ANCHORING:
			if pos2().distance_to(spot.pos) < 4.5:
				_let_go_anchor()
				return
		State.WAITING:
			if traffic.try_lock(dest, self):
				_begin_berthing()
				return
	helm.update(delta)
	var want_yaw := helm.want_yaw
	var target := helm.want_speed
	match state:
		State.WAITING:
			target = minf(target, 2.7)
			if helm.distance_left() < HOLD_R and helm.give_way_to == null:
				want_yaw = _wind_yaw()
				target = 0.0
		State.ANCHORING:
			# Up to the spot slowly, head to wind, to stop over it.
			var left := pos2().distance_to(spot.pos)
			target = minf(target, minf(ANCHOR_SPEED, 0.45 + sqrt(2.0 * 0.75 * left)))
	_make_way(delta, want_yaw, target, spec.turn if speed > spec.motor_speed * 1.5 else spec.motor_turn)
	_pose(delta)


## Downwind of its spot, where it lines up to come up into the wind (or the spot
## itself, if that is foul).
func _approach_point() -> Vector2:
	var p := spot.pos - traffic.sim.wind_from() * APPROACH
	if traffic.nav.open_at(p, false) and traffic.sim.terrain.height_at(p.x, p.y) < -spec.draft - 1.8:
		return p
	return spot.pos


func _begin_berthing() -> void:
	state = State.ARRIVING
	_start_berthing()


func _berthed() -> void:
	dwell = traffic.rng.randf_range(DWELL.x, DWELL.y)
	_moor()


# --- At anchor ----------------------------------------------------------------------

## Over its spot: lets go, and drops back on the cable.
func _let_go_anchor() -> void:
	state = State.SETTING
	free_nav = false
	helm = null
	speed = 0.0
	_timer = 0.0


## Dropping back until it lies SCOPE from the anchor, head to wind.
func _set_anchor(delta: float) -> void:
	_timer += delta * SET_SPEED
	var a := _swing_yaw()
	_yaw = rotate_toward(_yaw, a, 0.25 * delta)
	var back := minf(_timer, SCOPE)
	var p := spot.pos - Vector2(sin(_yaw), cos(_yaw)) * back
	position = Vector3(p.x, sin(_bob * 1.3) * 0.12, p.y)
	_pose(delta)
	if _timer >= SCOPE:
		_anchored()
		_leave_at = _morning() if overnight else _now() + traffic.rng.randf_range(AT_ANCHOR.x, AT_ANCHOR.y)


func _anchored() -> void:
	state = State.ANCHORED
	free_nav = false
	helm = null
	path = null
	speed = 0.0
	_yaw = _swing_yaw()
	_lie_at_anchor(0.0)


## Tomorrow morning's time to weigh anchor (or this morning's, in the small hours).
func _morning() -> float:
	var day := traffic.sim.day + (0 if traffic.sim.hour() < 4.0 else 1)
	return day * 1440.0 + traffic.rng.randf_range(MORNING.x, MORNING.y) * 60.0


## Head to wind, swinging a little about its anchor, until it is time to go
## (by the evening unless it is staying the night, and only in daylight).
func _lie_at_anchor(delta: float) -> void:
	_yaw = rotate_toward(_yaw, _swing_yaw(), 0.08 * delta)
	var p := spot.pos - Vector2(sin(_yaw), cos(_yaw)) * SCOPE
	position = Vector3(p.x, sin(_bob * 1.3) * 0.12, p.y)
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, sin(_bob * 0.9) * 0.012) \
			* Basis(Vector3.BACK, sin(_bob * 1.1) * 0.025)
	if delta <= 0.0:
		return
	var h := traffic.sim.hour()
	var due := _now() >= _leave_at or (not overnight and h >= BACK_BY)
	if due and h >= 6.5 and h < 21.0:
		state = State.WEIGHING
		_timer = 0.0


func _swing_yaw() -> float:
	return _wind_yaw() + sin(_swing * 0.05) * 0.22 + sin(_swing * 0.013 + 1.3) * 0.12


## Motoring up over the anchor and breaking it out, then off home.
func _weigh(delta: float) -> void:
	_timer += delta
	var f := clampf(_timer / WEIGH_TIME, 0.0, 1.0)
	var p := spot.pos - Vector2(sin(_yaw), cos(_yaw)) * SCOPE * (1.0 - f)
	position = Vector3(p.x, sin(_bob * 1.3) * 0.12, p.y)
	_pose(delta)
	if f < 1.0:
		return
	traffic.release_spot(spot, self)
	spot = null
	_outbound = false
	_goals = [traffic.wait_spot(dest, dest_berth)]
	state = State.CRUISING
	free_nav = true
	helm = Helm.new(self, traffic)
	helm.set_goal(_goals[0])


func _wind_yaw() -> float:
	var w := traffic.sim.wind_from()
	return atan2(w.x, w.y)


# --- Speed and attitude ---------------------------------------------------------------

## Off the plane near harbours, near boats lying at a berth or at anchor, and in
## coves: looked for a little ahead, so it is down to speed by the time it gets
## there.
func _in_no_wake_zone() -> bool:
	var p := pos2() + Vector2(sin(_yaw), cos(_yaw)) * clampf(speed * 4.0, 0.0, 75.0)
	if traffic.near_harbour(p, NO_WAKE_HARBOUR):
		return true
	for a in traffic.anchorages:
		if a.center.distance_to(p) < NO_WAKE_COVE:
			return true
	for o in traffic.vessels:
		if o != self and o.road() == Road.MOORED and o.pos2().distance_to(p) < NO_WAKE_MOORED:
			return true
	return false


func no_wake() -> bool:
	return _no_wake


func helm_speed(_y: float) -> float:
	return spec.motor_speed if _no_wake or state == State.WAITING else cruise


func helm_turn_rate() -> float:
	return spec.turn


## Bow up as it climbs onto the plane (most at about half its top speed), settling
## flatter once on top; it banks into its turns at speed.
func _pose(delta: float) -> void:
	_no_wake_check -= delta
	if _no_wake_check <= 0.0:
		_no_wake_check = 0.5
		_no_wake = _in_no_wake_zone()
	var f := clampf(speed / cruise, 0.0, 1.2)
	var hump := exp(-pow((f - 0.42) / 0.17, 2.0))
	var trim := 0.1 * hump + 0.05 * smoothstep(0.5, 0.85, f)
	_trim = move_toward(_trim, trim, 0.12 * delta)
	var rate := angle_difference(_last_yaw, _yaw) / maxf(delta, 1e-3)
	_last_yaw = _yaw
	_roll = move_toward(_roll, clampf(rate * f * 0.25, -0.12, 0.12), 0.3 * delta)
	position.y = sin(_bob * 1.4) * 0.12 + 0.24 * smoothstep(0.55, 0.9, f)
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_trim + sin(_bob * 1.1) * 0.01) \
			* Basis(Vector3.BACK, _roll + sin(_bob * 0.9) * 0.02)


## Masthead (on the arch), sidelights and stern light under way; the anchor
## light on the arch at anchor.
func _show_lights() -> void:
	var under_way := state != State.MOORED and road() != Road.MOORED
	_nav_lights.visible = under_way
	_mast_light.visible = under_way or state == State.ANCHORED or state == State.SETTING or state == State.WEIGHING
	_rode.visible = state == State.ANCHORED or state == State.SETTING or (state == State.WEIGHING and _timer < WEIGH_TIME * 0.85)


## A clean small wake off the plane; climbing onto it, a big wave train (the hump
## is where it makes most); on top, a long white wash and lower waves.
func wake_hull() -> Vector4:
	var h := spec.wake_hull()
	var f := clampf(speed / cruise, 0.0, 1.0)
	var hump := exp(-pow((f - 0.42) / 0.2, 2.0))
	h.z = spec.wash * (0.35 + 0.9 * f)
	h.w = spec.kelvin * (0.35 + 1.5 * hump + 0.5 * f)
	return h


# --- Vessel ---------------------------------------------------------------------------

func _moored() -> bool:
	return state == State.MOORED


func _waiting_in() -> bool:
	return state == State.WAITING


func road() -> Road:
	match state:
		State.MOORED, State.SETTING, State.ANCHORED, State.WEIGHING:
			return Road.MOORED
		State.LEAVING, State.ARRIVING:
			return Road.MANOEUVRING
	return Road.POWER


func wants_to_move() -> bool:
	return state in [State.LEAVING, State.CRUISING, State.ANCHORING, State.WAITING, State.ARRIVING]


func ahead(d: float) -> Vector2:
	if path != null:
		return path.sample(s + d)
	if not wants_to_move():
		return pos2()
	return pos2() + Vector2(sin(_yaw), cos(_yaw)) * d


func status_text() -> String:
	var holding := holding_text()
	if holding != "":
		return holding
	match state:
		State.MOORED:
			return "Moored at " + marina_name(marina)
		State.LEAVING:
			return "Leaving " + marina_name(marina)
		State.WAITING:
			return "Waiting to berth at " + marina_name(dest)
		State.ARRIVING:
			return "Berthing at " + marina_name(dest)
		State.SETTING:
			return "Dropping anchor " + spot.anchorage.place
		State.ANCHORED:
			return "At anchor %s%s" % [spot.anchorage.place, " for the night" if overnight and _leave_at - _now() > 120.0 else ""]
		State.WEIGHING:
			return "Weighing anchor"
	if helm and helm.give_way_why != "":
		return helm.give_way_why
	var where := ""
	if state == State.ANCHORING:
		where = "Coming up to anchor " + spot.anchorage.place
	elif _outbound:
		where = "Heading for a cove" + spot.anchorage.place.trim_prefix("in a cove")
	elif trip == Trip.RUN and _goals.size() > 1:
		where = "Out for a run"
	elif dest == marina:
		where = "Heading home to " + marina_name(dest)
	else:
		where = "Cruising to " + marina_name(dest)
	if _no_wake and speed < spec.motor_speed * 1.3:
		return where + " · no-wake speed"
	return where
