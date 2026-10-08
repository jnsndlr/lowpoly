class_name ShipTender
extends WharfBoat
## A boat based at the pilot station that works with the ships passing through:
## pilot boats and tugs (see Pilotage, which hands out the jobs). This is the part
## they share.
##
## Given a ship to meet, it casts off and a Helm takes it out to a point off the
## ship's track ahead of it, on the side it will work (the lee, for a pilot boat:
## the ship makes a lee for the ladder), and stands by there. As the ship comes
## up it closes in on a station that moves with the ship (abreast of its ladder,
## or off its quarter), matching course and speed, and does its work there; then
## it sheers off and a Helm takes it home. While it is working with the ship it is
## restricted in its ability to manoeuvre (everyone else keeps clear). From
## taking the job to finishing it, the ship doesn't brake for it (Vessel.consort):
## the boat keeps clear of the ship itself, its helm steering round it until it
## is working with it, and never moving any nearer its hull than it is.

enum State { ALONGSIDE, LEAVING, OUTBOUND, STANDING_BY, CLOSING, WORKING, SHEERING, RETURNING, WAITING, ARRIVING }

const GOAL_R := 42.0
const HOLD_R := 30.0
const STANDOFF := 120.0         # off the ship's track, standing by
const CLOSE_FROM := 510.0      # starts closing in from this far from its station
const PURSUE_GAIN := 0.35      # closing speed (m/s) per metre off station
const MATCHED := 1.8           # this near its station, its course and speed matched, it holds there
const HARBOUR_CLEAR := 330.0
const ALIGNED := 0.04          # (rad) it only closes the last of the gap once its course is the ship's

var state := State.ALONGSIDE
var ship: CargoShip            # the ship it is working with (or bound for)
var side := 1.0                # the ship's side it works: +1 starboard, -1 port
var jobs := 0
var _goal_timer := 0.0
var _gap := 0.0                # how far off the ship's side its station is now
var _locked := false           # holding its station
var _along := 0.0              # how far its station has dropped back along the ship (sheering off)
var _holding := false          # lying stopped at its standby or waiting spot
var _nav_lights: MeshInstance3D


# --- Hooks ----------------------------------------------------------------------------

## Its station in the ship's frame: x along the ship from its centre (+ forward),
## y out from the ship's side (beyond both hulls), for gap `g`.
func _station(_g: float) -> Vector2:
	return Vector2.ZERO


## How far off the ship's side it closes in to, and works at.
func _working_gap() -> float:
	return 1.2


func _closing_gap() -> float:
	return 48.0


## Whether it holds its station once matched with the ship (rather than keeping
## on steering for it, braking for any other hull as it goes).
func _lockable() -> bool:
	return true


## In position: the work begins.
func _start_work() -> void:
	pass


## Each frame of the work; true when it is done.
func _work_done(_delta: float) -> bool:
	return true


## The work done and clear of the ship.
func _finished() -> void:
	pass


## Each frame of sheering off once the work is done; true when clear of the
## ship. By default it drops back along the ship's side, easing out a little,
## until it is astern of it (in its wake: deep water).
func _sheer(delta: float) -> bool:
	_along -= 4.8 * delta
	_gap = move_toward(_gap, 7.5, 1.5 * delta)
	return _station(_gap).x + _along < -(ship.half_seg + ship.hull_radius + spec.half_length + 18.0)


# --- Jobs -----------------------------------------------------------------------------

## Free for a new job (alongside at the station, or heading back to it).
func available() -> bool:
	return not is_instance_valid(ship) and state in [State.ALONGSIDE, State.RETURNING, State.WAITING]


## How long it would take to get to `p` from where it is (seconds), including
## casting off.
func eta(p: Vector2) -> float:
	var t := pos2().distance_to(p) * 1.25 / cruise
	return t + (60.0 if state == State.ALONGSIDE else 0.0)


## Takes the job of meeting `sh` near `meet` (a point on its track), working its
## `work_side` (+1 starboard).
func assign(sh: CargoShip, meet: Vector2, work_side: float) -> void:
	ship = sh
	consort = sh
	side = work_side
	_goal_timer = 0.0
	match state:
		State.ALONGSIDE:
			_cast_off()
		State.RETURNING, State.WAITING:
			traffic.leave_queue(wharf, self)
			_set_out(meet)


func _cast_off() -> void:
	if not traffic.try_lock(wharf, self):
		return
	state = State.LEAVING
	_leave()


## Out along the lane: off to the ship.
func _left_berth() -> void:
	if not is_instance_valid(ship):
		ship = null
		_head_home()
		return
	_set_out(ship.pos2())


func _set_out(_meet: Vector2) -> void:
	state = State.OUTBOUND
	free_nav = true
	if helm == null:
		helm = Helm.new(self, traffic)
	helm.set_goal(_standby_point())


## Where it stands by for the ship: off its track ahead of it on the working side,
## as far ahead as it can get to before the ship does, in open water deep enough
## for it (further in towards the track, or further along, if not).
func _standby_point() -> Vector2:
	var lead := clampf(pos2().distance_to(ship.pos2()) * ship.speed / maxf(cruise, 0.3), 180.0, 1200.0)
	var shoal := -spec.draft - 3.0
	for more: float in [0.0, 240.0, 480.0, -120.0]:
		var at := clampf(ship.s + lead + more, ship.s + 120.0, ship.path.length)
		var p := ship.path.sample(at)
		var t := ship.path.tangent(at, 30.0)
		var right := Vector2(-t.y, t.x)
		var off := STANDOFF + ship.hull_radius
		while off >= ship.hull_radius + hull_radius + 36.0:
			var q := p + right * side * off
			if traffic.nav.open_at(q, false) and traffic.sim.terrain.height_at(q.x, q.y) < shoal:
				return q
			off -= 18.0
	return ship.ahead(lead) + Vector2(-ship.heading2().y, ship.heading2().x) * side * (ship.hull_radius + 60.0)


func _head_home() -> void:
	_release_ship()
	state = State.RETURNING
	free_nav = true
	if helm == null:
		helm = Helm.new(self, traffic)
	helm.set_goal(traffic.wait_spot(wharf, berth))


func _release_ship() -> void:
	ship = null
	consort = null
	_locked = false


# --- Each frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_bob += delta
	# (A freed ship compares equal to null.)
	if _on_job() and not is_instance_valid(ship):
		_lost_ship()
	match state:
		State.ALONGSIDE:
			if is_instance_valid(ship):
				_cast_off()
			_pose_alongside()
		State.LEAVING, State.ARRIVING:
			_follow_path(delta)
		State.CLOSING, State.WORKING, State.SHEERING:
			_keep_station(delta)
		_:
			_navigate(delta)
	_show_lights()
	var under_way := state != State.ALONGSIDE
	var d := Vector3(sin(_yaw), 0.0, cos(_yaw))
	wake.update(delta, global_position, d, speed * delta if under_way else 0.0,
			clampf(speed / cruise, 0.0, 1.0) if under_way else 0.0, under_way and speed > 0.3)


func _on_job() -> bool:
	return state in [State.OUTBOUND, State.STANDING_BY, State.CLOSING, State.WORKING, State.SHEERING]


## Its ship has gone (out of the map): home.
func _lost_ship() -> void:
	_release_ship()
	_head_home()


func _navigate(delta: float) -> void:
	match state:
		State.OUTBOUND, State.STANDING_BY:
			_goal_timer -= delta
			if _goal_timer <= 0.0 and state == State.OUTBOUND:
				_goal_timer = 2.0
				helm.set_goal(_standby_point())
			if state == State.OUTBOUND and helm.distance_left() < GOAL_R:
				state = State.STANDING_BY
			if _ready_to_close():
				_start_closing()
				return
		State.RETURNING:
			if helm.distance_left() < GOAL_R:
				if traffic.try_lock(wharf, self):
					_begin_arriving()
					return
				state = State.WAITING
				traffic.queue_for(wharf, self)
		State.WAITING:
			if traffic.try_lock(wharf, self):
				_begin_arriving()
				return
	helm.update(delta)
	var want_yaw := helm.want_yaw
	var target := helm.want_speed
	# Easing off as it comes up to its spot, so it can stop there rather than
	# running round and round it (its turning circle is wider than the spot);
	# once stopped it lies there until something moves it well off.
	var left := helm.distance_left()
	target = minf(target, _approach_speed(left))
	if state in [State.WAITING, State.STANDING_BY]:
		if helm.give_way_to != null or left > HOLD_R * 3.0:
			_holding = false
		elif left < HOLD_R:
			_holding = true
	else:
		_holding = false
	match state:
		State.WAITING:
			target = minf(target, 3.6)
			if _holding:
				want_yaw = _yaw
				target = 0.0
		State.STANDING_BY:
			# Lies stopped off the track, heading the way the ship is going.
			if _holding:
				var h := ship.heading2()
				want_yaw = atan2(h.x, h.y)
				target = 0.0
	_make_way(delta, want_yaw, target, spec.turn)
	_pose(delta)


## The most it makes coming up to a spot `left` metres off, so that it can
## stop inside HOLD_R of it.
func _approach_speed(left: float) -> float:
	return 1.8 + sqrt(2.0 * spec.decel * maxf(left - HOLD_R * 0.5, 0.0)) * 0.8


## Near enough its station, with open water straight there, and on the working
## side of the ship well clear of its hull (so closing in never takes it across
## the ship's bow).
func _ready_to_close() -> bool:
	var st := _station_world(_closing_gap())
	if pos2().distance_to(st) > CLOSE_FROM or not _water_line(pos2(), st):
		return false
	# Not right off a harbour, where the ship slowing would hold up everyone else.
	if traffic.near_harbour(ship.pos2(), HARBOUR_CLEAR) or traffic.near_harbour(st, HARBOUR_CLEAR):
		return false
	var rel := pos2() - ship.pos2()
	var h := ship.heading2()
	var right := Vector2(-h.y, h.x)
	var lat := rel.dot(right) * side
	var along := rel.dot(h)
	return lat > ship.hull_radius + hull_radius + 24.0 or along < -(ship.half_seg + ship.hull_radius + hull_radius + 30.0)


func _start_closing() -> void:
	state = State.CLOSING
	helm = null
	_gap = _closing_gap()
	_along = 0.0
	_locked = false


## Shoal water where it is working (or the ship has run on towards some): it
## breaks off and comes round again under the helm.
func _break_off() -> void:
	state = State.OUTBOUND
	_locked = false
	helm = Helm.new(self, traffic)
	helm.set_goal(_standby_point())
	_goal_timer = 2.0


func _begin_arriving() -> void:
	state = State.ARRIVING
	_come_in()


func _came_alongside() -> void:
	_tie_up()


func _tie_up() -> void:
	state = State.ALONGSIDE
	_lie_alongside()


## Station keeping on the ship: closing in on its station, working there, then
## sheering off. Until matched with the ship it steers for its station at the
## ship's speed plus a little for every metre off; matched, it holds the station
## (closing the last of the gap only once it is on the ship's course).
func _keep_station(delta: float) -> void:
	var h := ship.heading2()
	var ship_yaw := atan2(h.x, h.y)
	match state:
		State.CLOSING:
			var on_station := _locked and absf(angle_difference(_yaw, ship_yaw)) < ALIGNED
			if not _lockable():
				on_station = pos2().distance_to(_station_world(_gap)) < 15.0
			if on_station:
				_gap = move_toward(_gap, _working_gap(), 1.8 * delta)
				if _gap <= _working_gap() + 0.03:
					state = State.WORKING
					_start_work()
		State.WORKING:
			if _work_done(delta):
				state = State.SHEERING
		State.SHEERING:
			if _sheer(delta):
				_finished()
				_head_home()
				return
	var st := _station_world(_gap)
	if _locked:
		if not _hull_afloat(st, ship_yaw) or traffic.hull_gap(self, st, h) < 0.9:
			if state == State.SHEERING:
				_finished()
				_head_home()
			else:
				_break_off()
			return
		var p := pos2().move_toward(st, (ship.speed + 4.5) * delta)
		position = Vector3(p.x, position.y, p.y)
		_yaw = rotate_toward(_yaw, ship_yaw, 0.6 * delta)
		speed = ship.speed
	else:
		# Coming up from astern, it swings wide of the ship's quarter first.
		var rel := pos2() - ship.pos2()
		var right := Vector2(-h.y, h.x)
		var wide := ship.hull_radius + hull_radius + 18.0
		var along_now := rel.dot(h)
		var lat_now := rel.dot(right) * side
		if lat_now < wide and along_now < -ship.half_seg:
			st = ship.pos2() - h * (ship.half_seg + ship.hull_radius + 30.0) + right * side * (wide + 24.0)
		# Ahead of the ship's bow and close to its track: straight out to the side
		# first, never across its bow.
		elif lat_now < wide + 6.0 and along_now > ship.half_seg:
			st = ship.pos2() + h * along_now + right * side * (wide + 30.0)
		# One that keeps station off the ship (rather than alongside it) passes
		# well wide of it while it is abreast of it.
		elif not _lockable() and absf(rel.dot(h)) < ship.half_seg + ship.hull_radius + 24.0:
			var lat := (st - ship.pos2()).dot(right) * side
			if lat < wide + 18.0:
				st += right * side * (wide + 18.0 - lat)
		var off := st - pos2()
		var v := h * ship.speed + off.limit_length(180.0) * PURSUE_GAIN
		# Near the ship it never turns back against the ship's way: to drop back
		# it eases off and lets the ship draw ahead.
		if absf(rel.dot(h)) < ship.half_seg + ship.hull_radius + 75.0 and absf(rel.dot(right)) < wide + 75.0:
			var va := maxf(v.dot(h), ship.speed * 0.35)
			v = h * va + (v - h * v.dot(h))
		var want := v.length()
		var want_yaw := atan2(v.x, v.y) if want > 0.9 else ship_yaw
		# Close in, steer as the ship steers.
		if off.length() < 18.0:
			want_yaw = lerp_angle(ship_yaw, want_yaw, clampf(off.length() / 18.0, 0.0, 1.0))
		# (Braking for any other hull in its way.)
		var target := minf(minf(want, cruise), yield_speed())
		# Land in the way of the straight run in: round it under the helm, then
		# try again.
		if not _water_line(pos2(), pos2() + Vector2(sin(want_yaw), cos(want_yaw)) * (24.0 + speed * 4.0)):
			_break_off()
			return
		var yaw := rotate_toward(_yaw, want_yaw, spec.turn * 1.5 * delta)
		speed = move_toward(speed, target, (spec.accel if target > speed else spec.decel) * 1.5 * delta)
		var d := Vector2(sin(yaw), cos(yaw))
		var p := pos2() + d * speed * delta
		# Never closer in against the ship than three metres (its station is further
		# out than that until it has its course): parallel to it instead, easing out.
		var ship_now := _ship_gap(pos2(), _yaw)
		var ship_new := _ship_gap(p, yaw)
		# (More room forward of the ship's beam, where it is coming on.)
		var room := 3.0 + (ship.speed if along_now > 0.0 else 0.0)
		if ship_new < room and ship_new <= ship_now + 0.03:
			yaw = rotate_toward(_yaw, ship_yaw, spec.turn * delta)
			speed = ship.speed
			d = Vector2(sin(yaw), cos(yaw))
			p = pos2() + h * ship.speed * delta + right * side * (1.8 if ship_new > 1.5 else 4.5) * delta
			if _ship_gap(p, yaw) < minf(0.9, ship_now):
				p = pos2() + h * ship.speed * delta
		# Never into another hull, even swinging its stern round.
		var now_gap := traffic.hull_gap(self, pos2(), Vector2(sin(_yaw), cos(_yaw)))
		if _safe(p, d, d, now_gap):
			_yaw = yaw
			position = Vector3(p.x, position.y, p.y)
		else:
			speed = 0.0
		if _lockable() and off.length() < MATCHED and absf(speed - ship.speed) < 1.2 \
				and absf(angle_difference(_yaw, ship_yaw)) < 0.15:
			_locked = true
	position.y = sin(_bob * 1.1) * 0.15
	_pose(delta)


## (HelmVessel) Nor any nearer its own ship's hull, which doesn't count in the
## hull check (consort).
func _safe(p: Vector2, d: Vector2, lead: Vector2, now_gap: float) -> bool:
	if not super(p, d, lead, now_gap):
		return false
	if not is_instance_valid(ship):
		return true
	return _ship_gap(p, atan2(d.x, d.y)) >= minf(0.9, _ship_gap(pos2(), _yaw)) - 0.003


## The gap between its hull, were it at `p` heading `yaw`, and its ship's.
func _ship_gap(p: Vector2, yaw: float) -> float:
	var d := Vector2(sin(yaw), cos(yaw)) * half_seg
	var q := ship.pos2()
	var e := ship.heading2() * ship.half_seg
	return MarineTraffic._seg_dist(p - d, p + d, q - e, q + e) - hull_radius - ship.hull_radius


## Whether its hull would lie in water deep enough for it at `p`, heading `yaw`.
func _hull_afloat(p: Vector2, yaw: float) -> bool:
	var d := Vector2(sin(yaw), cos(yaw)) * spec.half_length
	var shoal := -spec.draft - 0.6
	for q: Vector2 in [p, p + d, p - d]:
		if traffic.sim.terrain.height_at(q.x, q.y) > shoal:
			return false
	return true


## Whether the straight line a → b keeps to water deep enough for it.
func _water_line(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / 9.0)
	var shoal := -spec.draft - 1.2
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		if traffic.sim.terrain.height_at(q.x, q.y) > shoal:
			return false
	return true


## Its station in world x, z: out a little further while its course is not yet
## the ship's (so its ends can't swing in against the ship's side).
func _station_world(g: float) -> Vector2:
	var h := ship.heading2()
	var swing := half_seg * absf(sin(angle_difference(_yaw, atan2(h.x, h.y)))) + 0.45
	var st := _station(g + swing)
	var right := Vector2(-h.y, h.x)
	return ship.pos2() + h * (st.x + _along) + right * side * st.y


## Which side of `sh` to work, preferring `prefer`: the other one if the water is
## shoal where it would lie alongside over the stretch of its track from s0 to s1.
func _pick_side(sh: CargoShip, prefer: float, s0: float, s1: float) -> float:
	var bad := [0, 0]
	var lat := sh.hull_radius + hull_radius + 3.0
	var shoal := -spec.draft - 1.5
	var d := maxf(s0, 0.0)
	while d <= minf(s1, sh.path.length):
		var p := sh.path.sample(d)
		var t := sh.path.tangent(d, 30.0)
		var right := Vector2(-t.y, t.x)
		for k in 2:
			var sd := prefer if k == 0 else -prefer
			for o: float in [0.0, spec.half_length]:
				var q := p + right * sd * lat + t * o
				if traffic.sim.terrain.height_at(q.x, q.y) > shoal:
					bad[k] += 1
		d += 24.0
	return prefer if bad[0] <= bad[1] else -prefer


func _show_lights() -> void:
	_nav_lights.visible = state != State.ALONGSIDE


# --- Vessel ---------------------------------------------------------------------------

func _alongside() -> bool:
	return state == State.ALONGSIDE


func _waiting_in() -> bool:
	return state == State.WAITING


func working() -> bool:
	return state in [State.CLOSING, State.WORKING, State.SHEERING]


func road() -> Road:
	match state:
		State.ALONGSIDE:
			return Road.MOORED
		State.LEAVING, State.ARRIVING:
			return Road.MANOEUVRING
		State.CLOSING, State.WORKING, State.SHEERING:
			return Road.RESTRICTED
	return Road.POWER


func resting() -> bool:
	return state == State.STANDING_BY


func helm_turn_rate() -> float:
	return spec.turn


func ahead(d: float) -> Vector2:
	if working():
		return pos2() + Vector2(sin(_yaw), cos(_yaw)) * d
	return super(d)


func path_left() -> float:
	if working():
		return 180.0
	return super()
