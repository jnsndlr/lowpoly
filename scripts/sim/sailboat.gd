class_name Sailboat
extends HelmVessel
## A small sailboat that lies at a marina berth for a while, then sails to a free
## berth elsewhere (now and then out for a day sail and back home). Only leaves in
## daylight.
##
## In and out of the marina it motors with its sails down along set legs: backing
## out of the berth, and from off the marina in to it. Those manoeuvres take the
## marina's lock (MarineTraffic.try_lock); an arriving boat holds station off the
## marina (MarineTraffic.wait_spot), head to wind under engine, until it gets it. Out on open water it hoists sail and a
## Helm takes it there: it sails by the wind (fastest on a reach, unable to point
## closer than NO_GO to it, so it beats upwind in tacks), keeps off the land,
## steers round wildlife, and keeps clear of other vessels by the rules of the
## road: ferries and ships, anything manoeuvring in or out of its berth, a
## fishing boat at work, and other sailboats when it is on port tack, to
## windward, or overtaking.

enum State { MOORED, LEAVING, SAILING, WAITING, ARRIVING }

const COAST := 0.18          # slowing with no drive from the sails
const REVERSE_SPEED := 0.7
const DWELL := Vector2(60.0, 260.0)   # game minutes moored between trips
const LEAVE_HOURS := Vector2(6.5, 19.5)
const GOAL_R := 14.0
const DOUSE_R := 45.0          # sails come down this far from the marina
const CLEAR_OF_MARINA := 25.0  # past the back-out point, where it lets go of the lock and hoists sail
const HOLD_R := 8.0            # waiting, it holds station this near its waiting spot
# Points of sail: none at all within NO_GO of the wind; close-hauled it sails
# CLOSE_HAULED off it. Speed (as a share of its cruise) by angle off the wind.
const NO_GO := 0.7
const CLOSE_HAULED := 0.78
const POLAR := [[0.7, 0.55], [0.8, 0.7], [1.05, 0.88], [1.57, 1.0], [2.3, 1.02], [2.7, 0.92], [PI, 0.78]]
const MIN_TACK := 8.0
# The hull length the marina's berths are laid out for (Layout.MARINA_BERTH_U);
# longer boats lie further out.
const BERTH_HALF_LENGTH := 1.8

var state := State.MOORED
var marina: MapData.Marina     # where it is moored, or where it last left from
var berth := 0
var dest: MapData.Marina
var dest_berth := 0
var path: NavPath              # the leg it is motoring along (backing out, or in to its berth)
var s := 0.0
var dwell := 0.0
var trips := 0
var motoring := true
var _goals: Array[Vector2] = []
var _hull: MeshInstance3D
var _main: MeshInstance3D
var _jib: MeshInstance3D
var _tack := 0                 # which side of the wind it is beating on (+1 / -1), 0 if not beating
var _tack_time := 0.0
var _leg_max := 60.0
var _sheet := 0.0              # how far the sails are swung out (signed: to port is +)
var _heel := 0.0
var _leaving: MapData.Marina = null    # holds this marina's lock while getting out
var _arriving := false                 # holds the destination's lock


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, m: MapData.Marina, b: int, first_dwell: float) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	_hull = apply_spec(sp)
	marina = m
	berth = b
	dwell = first_dwell
	_bob = t.rng.randf() * TAU
	_main = MeshInstance3D.new()
	_main.mesh = Models.sailboat_main()
	_main.position = Models.SAIL_MAIN_PIVOT
	_hull.add_child(_main)
	_jib = MeshInstance3D.new()
	_jib.mesh = Models.sailboat_jib()
	_jib.position = Models.SAIL_JIB_TACK
	_hull.add_child(_jib)
	_moor()


func _process(delta: float) -> void:
	_bob += delta
	match state:
		State.MOORED:
			dwell -= delta
			var h := traffic.sim.hour()
			if dwell <= 0.0 and h >= LEAVE_HOURS.x and h < LEAVE_HOURS.y:
				depart()
			_pose_moored()
		State.LEAVING:
			_back_out(delta)
		State.SAILING, State.WAITING:
			_navigate(delta)
		State.ARRIVING:
			_berth_in(delta)
	var under_way := state != State.MOORED and not (state == State.LEAVING)
	var d := Vector3(sin(_yaw), 0.0, cos(_yaw))
	wake.update(delta, global_position, d, speed * delta if under_way else 0.0,
			speed / cruise if under_way else 0.0, under_way and speed > 0.1)


## A point on berth `b`'s line at `u` out from the shore, for this boat's centre
## (a longer boat lies, and backs out, a little further out).
func _berth_pos(m: MapData.Marina, b: int, u: float) -> Vector2:
	var p := m.at(u + spec.half_length - BERTH_HALF_LENGTH, m.berth_v(b))
	return Vector2(p.x, p.z)


func _moor() -> void:
	_let_go()
	state = State.MOORED
	free_nav = false
	speed = 0.0
	path = null
	helm = null
	var d := -marina.dir
	_yaw = atan2(d.x, d.z)
	_set_sails(false)
	_pose_moored()


func _pose_moored() -> void:
	var p := _berth_pos(marina, berth, Layout.MARINA_BERTH_U)
	position = Vector3(p.x, sin(_bob * 1.4) * 0.04, p.y)
	basis = Basis(Vector3.UP, _yaw + sin(_bob * 0.37) * 0.03) * Basis(Vector3.BACK, sin(_bob * 1.1) * 0.025)


func _set_sails(up: bool) -> void:
	motoring = not up
	_hull.mesh = spec.model.call(0) if up else spec.model_alt.call(0)
	_main.visible = up
	_jib.visible = up


## Casts off for a free berth. `progress` > 0 starts it that far through the
## passage already, under sail (for boats already out when the map opens).
func depart(progress := 0.0) -> void:
	var pick := traffic.reserve_berth(self)
	if pick.is_empty():
		dwell = 30.0
		return
	var dm: MapData.Marina = pick[0]
	var db: int = pick[1]
	var home := dm == marina and db == berth
	var goals := _plan_goals(dm, db)
	if goals.is_empty() or (progress <= 0.0 and not traffic.try_lock(marina, self)):
		if not home:
			traffic.release_berth(dm, db, self)
		dwell = 30.0 if goals.is_empty() else 3.0
		return
	if progress > 0.0 and not _place_part_way(goals, progress):
		if not home:
			traffic.release_berth(dm, db, self)
		dwell = 3.0
		return
	if not home:
		traffic.release_berth(marina, berth, self)
	dest = dm
	dest_berth = db
	_goals = goals
	_arriving = false
	_stuck = 0.0
	if progress > 0.0:
		_leaving = null
		_start_sailing(true)
		speed = helm_speed(_yaw)
	else:
		_leaving = marina
		state = State.LEAVING
		path = NavPath.new(PackedVector2Array([_berth_pos(marina, berth, Layout.MARINA_BERTH_U),
			_berth_pos(marina, berth, Layout.MARINA_BACKOUT_U)]))
		s = 0.0


## Where it is bound: (on a day sail, somewhere out on open water first, then)
## the waiting point off the destination marina.
func _plan_goals(dm: MapData.Marina, db: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var from := _berth_pos(marina, berth, Layout.MARINA_BACKOUT_U)
	if dm == marina:
		for k in traffic.rng.randi_range(1, 2):
			var via := _waypoint(from if out.is_empty() else out.back())
			if via == Vector2.INF:
				break
			out.append(via)
		if out.is_empty():
			return out
	out.append(traffic.wait_spot(dm, db))
	return out


## Somewhere out on open water for a day sail.
func _waypoint(from: Vector2) -> Vector2:
	var nav := traffic.nav
	var lim := traffic.sim.map.half_size - 40.0
	for k in 16:
		var a := traffic.rng.randf() * TAU
		var p := from + Vector2(cos(a), sin(a)) * traffic.rng.randf_range(80.0, 220.0)
		if absf(p.x) < lim and absf(p.y) < lim and nav.open_at(p, false) and not nav.find_path(from, p, false).is_empty():
			return p
	return Vector2.INF


## Puts it `progress` of the way along its first passage, pointing along it.
func _place_part_way(goals: Array[Vector2], progress: float) -> bool:
	var from := _berth_pos(marina, berth, Layout.MARINA_BACKOUT_U)
	var pts := traffic.nav.find_path(from, goals[0], false)
	if pts.size() < 2:
		return false
	var p := NavPath.new(pts)
	if p.length < 80.0:
		return false
	var at := p.sample(p.length * progress)
	if not traffic.is_clear(at, 8.0, self) or not traffic.nav.open_at(at, false):
		return false
	var t := p.tangent(p.length * progress)
	_yaw = atan2(t.x, t.y)
	position = Vector3(at.x, 0.0, at.y)
	return true


# --- In and out of the marina, under engine ----------------------------------------

func _back_out(delta: float) -> void:
	var left := path.length - s
	var target := minf(REVERSE_SPEED, 0.2 + sqrt(2.0 * 0.4 * left))
	target = minf(target, yield_speed())
	speed = minf(target, speed + spec.accel * delta)
	s = minf(s + speed * delta, path.length)
	var p := path.sample(s)
	position = Vector3(p.x, sin(_bob * 1.6) * 0.05, p.y)
	_pose(delta)
	if path.length - s < 0.05:
		path = null
		_start_sailing(false)


func _start_sailing(sails_up: bool) -> void:
	state = State.SAILING
	free_nav = true
	_set_sails(sails_up)
	_tack = 0
	helm = Helm.new(self, traffic)
	helm.set_goal(_goals[0])


func _berth_in(delta: float) -> void:
	var left := path.length - s
	var target := minf(spec.motor_speed * 0.6, 0.3 + sqrt(2.0 * 0.3 * left))
	target = minf(target, yield_speed())
	speed = minf(target, speed + spec.accel * delta)
	s = minf(s + speed * delta, path.length)
	var t := path.tangent(s)
	_yaw = rotate_toward(_yaw, atan2(t.x, t.y), spec.motor_turn * delta)
	var p := path.sample(s)
	position = Vector3(p.x, sin(_bob * 1.6) * 0.05, p.y)
	_pose(delta)
	if path.length - s < 0.02:
		traffic.unlock(dest, self)
		_arriving = false
		marina = dest
		berth = dest_berth
		trips += 1
		dwell = traffic.rng.randf_range(DWELL.x, DWELL.y)
		_moor()


## From where it is to the approach point, then straight in to the berth.
func _plan_berthing() -> NavPath:
	var to := _berth_pos(dest, dest_berth, Layout.MARINA_APPROACH_U)
	var main := traffic.nav.find_path(pos2(), to, false)
	if main.is_empty():
		main = PackedVector2Array([pos2(), to])
	main = traffic.nav.finish(main, 0.0, 6.0, 2, hull_radius + 1.0)
	main.append(_berth_pos(dest, dest_berth, Layout.MARINA_BERTH_U))
	return NavPath.new(main)


# --- Out on the water ---------------------------------------------------------------

func _navigate(delta: float) -> void:
	if _leaving and pos2().distance_to(_berth_pos(_leaving, berth, Layout.MARINA_BACKOUT_U)) > CLEAR_OF_MARINA:
		_let_go()
		_set_sails(true)
	var final := _goals.size() == 1
	if state == State.SAILING:
		if not motoring and final and helm.distance_left() < DOUSE_R:
			_set_sails(false)
		if helm.distance_left() < GOAL_R:
			if not final:
				_goals.pop_front()
				helm.set_goal(_goals[0])
			elif traffic.try_lock(dest, self):
				_arriving = true
				_begin_berthing()
				return
			else:
				_let_go()
				state = State.WAITING
				traffic.queue_for(dest, self)
	if state == State.WAITING and traffic.try_lock(dest, self):
		_arriving = true
		_begin_berthing()
		return
	helm.update(delta)
	_sync_tack(delta)
	var want_yaw := helm.want_yaw
	var target := helm.want_speed
	# Waiting its turn: holds station on its spot, head to wind, unless something
	# needs keeping clear of.
	if state == State.WAITING:
		target = minf(target, 0.9)
		if helm.distance_left() < HOLD_R and helm.give_way_to == null:
			want_yaw = _wind_yaw()
			target = 0.0
	_make_way(delta, want_yaw, target, spec.motor_turn if motoring else spec.turn)
	position.y = sin(_bob * 1.6) * 0.05
	_pose(delta)


## Lets go of the marina it is leaving.
func _let_go() -> void:
	if _leaving:
		traffic.unlock(_leaving, self)
		_leaving = null


func _begin_berthing() -> void:
	_let_go()
	state = State.ARRIVING
	free_nav = false
	_set_sails(false)
	helm = null
	path = _plan_berthing()
	s = 0.0


## Keeps track of which tack it is beating on, and asks for a tack when one leg
## has gone on long enough with the mark on the other side.
func _sync_tack(delta: float) -> void:
	_tack_time += delta
	if motoring:
		_tack = 0
		return
	var off := angle_difference(_wind_yaw(), helm.want_yaw)
	if absf(off) > CLOSE_HAULED + 0.25:
		_tack = 0
		return
	var side := 1 if off > 0.0 else -1
	if side != _tack:
		_tack = side
		_tack_time = 0.0
		_leg_max = traffic.rng.randf_range(45.0, 100.0)


func _wind_yaw() -> float:
	var w := traffic.sim.wind_from()
	return atan2(w.x, w.y)


## Breeze strength scales how fast it sails.
func _breeze() -> float:
	return clampf(0.6 + traffic.sim.wind_speed / 40.0, 0.65, 1.25)


## Speed made on a heading `off` radians off the wind, as a share of its cruise.
static func polar(off: float) -> float:
	off = absf(off)
	if off < NO_GO:
		return 0.12 * off / NO_GO
	for i in range(1, POLAR.size()):
		if off <= POLAR[i][0]:
			var a: Array = POLAR[i - 1]
			var b: Array = POLAR[i]
			return lerpf(a[1], b[1], (off - a[0]) / (b[0] - a[0]))
	return POLAR.back()[1]


## Heel to leeward and the sails sheeted out to leeward, eased as the wind goes
## aft; they swing across as it tacks or gybes.
func _pose(delta: float) -> void:
	var w := traffic.sim.wind_from()
	var right := Vector2(-cos(_yaw), sin(_yaw))
	var lee := 1.0 if w.dot(right) > 0.0 else -1.0     # +1: leeward is to port
	var off := absf(angle_difference(_yaw, _wind_yaw()))
	var sails := not motoring and state != State.MOORED
	var sheet := clampf((off - 0.6) * 0.55, 0.12, 1.35) * lee if sails else 0.0
	_sheet = move_toward(_sheet, sheet, 1.4 * delta)
	var heel := -0.13 * lee * clampf(speed / cruise, 0.0, 1.0) * clampf(sin(off) * 1.3, 0.3, 1.0) if sails else 0.0
	_heel = move_toward(_heel, heel, 0.15 * delta)
	_main.basis = Basis(Vector3.UP, -_sheet)
	var stay := (Models.SAIL_JIB_HEAD - Models.SAIL_JIB_TACK).normalized()
	_jib.basis = Basis(stay, -clampf(_sheet, -0.8, 0.8))
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.BACK, _heel + sin(_bob * 1.2) * 0.03)


# --- Helm hooks ---------------------------------------------------------------------

## Coming about, the sails stop driving it as it turns through the wind, but it
## carries its way through the tack, slowing only gradually.
func _coast() -> float:
	return COAST


func helm_speed(yaw: float) -> float:
	if motoring:
		return spec.motor_speed
	return cruise * _breeze() * polar(angle_difference(_wind_yaw(), yaw))


## Straight for it, unless that is too close to the wind: then close-hauled on
## the tack it is on, or (for a little more) the other one. It reaches the layline
## when the mark comes out of the no-go zone, and sails straight for it from there.
func helm_courses(bearing: float) -> Array:
	if motoring:
		return [[bearing, 0.0]]
	var wy := _wind_yaw()
	var off := angle_difference(wy, bearing)
	if absf(off) >= CLOSE_HAULED:
		return [[bearing, 0.0]]
	var side := _tack
	if side == 0:
		side = 1 if off > 0.0 else -1
	# A long leg with the mark on the other side: time to go about.
	if _tack_time > _leg_max and off * side < 0.0:
		side = -side
	var other_cost := 0.4 if _tack_time > MIN_TACK else 1.5
	return [[wy + side * CLOSE_HAULED, 0.0], [wy - side * CLOSE_HAULED, other_cost]]


## The rules of the road, simplified.
func helm_role(o: Variant) -> String:
	if o is Wildlife.Visit:
		return "Keeping clear of the " + (o as Wildlife.Visit).species.plural.to_lower()
	if o is Sailboat:
		var b := o as Sailboat
		match b.state:
			State.MOORED:
				# Tied up in its berth: just don't hit it.
				return ""
			State.LEAVING, State.ARRIVING:
				return "Giving way to %s, manoeuvring" % b.vessel_name
		var me_sail := not motoring
		var them_sail := not b.motoring
		if me_sail != them_sail:
			# Power gives way to sail.
			return "" if me_sail else "Giving way to %s, under sail" % b.vessel_name
		# Overtaking: keep clear of the boat ahead.
		var rel := pos2() - b.pos2()
		var bf := b.heading2()
		if rel.dot(bf) < -rel.length() * 0.38 and speed > b.speed + 0.1:
			return "Overtaking %s" % b.vessel_name
		if not me_sail:
			# Two under engine: keep to starboard of each other; the one with the
			# other on its starboard side gives way.
			var right := Vector2(-cos(_yaw), sin(_yaw))
			return "Giving way to " + b.vessel_name if (b.pos2() - pos2()).dot(right) > 0.0 else ""
		var mine := _tack_side()
		var theirs := b._tack_side()
		if mine != theirs:
			return "Giving way to %s on starboard tack" % b.vessel_name if mine < 0 else ""
		var w := traffic.sim.wind_from()
		if pos2().dot(w) > b.pos2().dot(w):
			return "Giving way to %s to leeward" % b.vessel_name
		return ""
	if o is FishingBoat:
		var f := o as FishingBoat
		if not f.wants_to_move():
			return ""
		if f.manoeuvring():
			return "Giving way to %s, manoeuvring" % f.vessel_name
		if f.fishing():
			return "Giving way to %s, fishing" % f.vessel_name
		if not motoring:
			# Power gives way to sail.
			return ""
		var right := Vector2(-cos(_yaw), sin(_yaw))
		return "Giving way to " + f.vessel_name if (f.pos2() - pos2()).dot(right) > 0.0 else ""
	if o is Vessel:
		return "Giving way to " + (o as Vessel).vessel_name
	return "Keeping clear"


## +1 on starboard tack (wind over the starboard side), -1 on port tack.
func _tack_side() -> int:
	var right := Vector2(-cos(_yaw), sin(_yaw))
	return 1 if traffic.sim.wind_from().dot(right) > 0.0 else -1


# --- Vessel ---------------------------------------------------------------------------

func wake_hull() -> Vector4:
	# Under engine, a little prop wash.
	var h := spec.wake_hull()
	if motoring:
		h.z = maxf(h.z, 0.55)
	return h


func waits_for(v: Vessel) -> bool:
	return blocker == v or (state == State.WAITING and traffic.lock_holder(dest) == v)


func wants_to_move() -> bool:
	return state != State.MOORED


func ahead(d: float) -> Vector2:
	if path != null:
		return path.sample(s + d)
	if state == State.MOORED:
		return pos2()
	return pos2() + Vector2(sin(_yaw), cos(_yaw)) * d


func path_left() -> float:
	if path != null:
		return path.length - s
	if helm != null:
		return helm.distance_left() + 10.0
	return 0.0


func marina_name(m: MapData.Marina) -> String:
	return traffic.sim.map.islands[m.island].name + " Marina"


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
	if helm and helm.give_way_why != "":
		return helm.give_way_why
	if _leaving:
		return "Motoring out of " + marina_name(_leaving)
	if motoring:
		return "Motoring in to " + marina_name(dest)
	var off := absf(angle_difference(_yaw, _wind_yaw()))
	var tack := "starboard tack" if _tack_side() > 0 else "port tack"
	if _tack != 0:
		return "Beating to windward on " + tack
	var point := "running before the wind"
	if off < 1.1:
		point = "close reach"
	elif off < 1.9:
		point = "beam reach"
	elif off < 2.6:
		point = "broad reach"
	var where := "Day sail" if dest == marina and _goals.size() > 1 else "Sailing to " + marina_name(dest)
	return "%s · %s" % [where, point]
