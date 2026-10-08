class_name FishingBoat
extends WharfBoat
## A trawler working out of a fish quay. It casts off well before dawn and steams
## out to a fishing ground (see FishingGround), where it tows its net slowly up and
## down the ground; at the end of each tow it stops to haul the catch aboard, then
## shoots the net again and tows back the other way. Once its hold is full, or by the afternoon, it steams home, lands
## the catch, and lies alongside until the small hours.
##
## Alongside, it lies against the quay's face (see WharfBoat for how it comes
## and goes). Under way it is a power-driven vessel: it gives way to sail, keeps
## clear of the ferries and ships, and crosses other power vessels by the rules.
## Fishing, it is the stand-on vessel to sail and power alike (but still keeps
## out of the way of the ferries and ships).

enum State { ALONGSIDE, LEAVING, STEAMING, FISHING, HOMEWARD, WAITING, ARRIVING }
enum Work { SHOOTING, TOWING, HAULING }

const SAIL_HOURS := Vector2(2.5, 4.5)       # when it casts off (hours of the day)
const HOME_BY := Vector2(13.0, 16.0)        # heads home by then even with room in the hold
const DAY_OFF := 0.12                       # chance it stays in harbour on a given day
const LANDING := Vector2(35.0, 60.0)        # game minutes landing the catch
const TOW_SPEED := 4.2
const SHOOT_SPEED := 2.7
const HAUL_TIME := Vector2(40.0, 70.0)      # game minutes
const SHOOT_TIME := Vector2(10.0, 20.0)
const CATCH := Vector2(0.24, 0.4)           # of a full hold, per haul (on an average ground)
const GOAL_R := 48.0
const HOLD_R := 36.0
const SWELL_ROLL := 0.025

var state := State.ALONGSIDE
var work := Work.TOWING
var quay: MapData.FishQuay
var ground: FishingGround
var fish_hold := 0.0                # how full its hold is, 0..1
var trips := 0
var hauls := 0
var _sail_at := 0.0            # when it next casts off (game minutes since day 0)
var _home_by := 15.0
var _landed_at := -INF
var _timer := 0.0              # in a haul or shooting the net: game minutes left
var _tow_end := 1.0            # the end of the ground it is towing towards (-1 / +1)
var _tow_across := 0.0
var _warps: MeshInstance3D
var _nav_lights: MeshInstance3D
var _steam_lights: MeshInstance3D
var _work_lights: MeshInstance3D


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, q: MapData.FishQuay, b: int, variant: int) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	_hull = apply_spec(sp, variant)
	_nav_lights = MeshInstance3D.new()
	_nav_lights.mesh = Models.trawler_nav_lights()
	_steam_lights = MeshInstance3D.new()
	_steam_lights.mesh = Models.trawler_steaming_lights()
	_work_lights = MeshInstance3D.new()
	_work_lights.mesh = Models.trawler_working_lights()
	for l: MeshInstance3D in [_nav_lights, _steam_lights, _work_lights]:
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.layers = NightLights.LAYER
		lights.add_child(l)
	_warps = MeshInstance3D.new()
	_warps.mesh = Models.trawler_warps()
	_warps.visible = false
	_hull.add_child(_warps)
	quay = q
	wharf = q
	berth = b
	_bob = t.rng.randf() * TAU
	_plan_next_trip()
	_tie_up()


func _process(delta: float) -> void:
	_bob += delta
	match state:
		State.ALONGSIDE:
			if _now() >= _sail_at:
				_cast_off()
			_pose_alongside()
		State.LEAVING, State.ARRIVING:
			_follow_path(delta)
		_:
			_navigate(delta)
	_show_lights()
	var under_way := state != State.ALONGSIDE
	var d := Vector3(sin(_yaw), 0.0, cos(_yaw))
	wake.update(delta, global_position, d, speed * delta if under_way else 0.0, _load() if under_way else 0.0,
			under_way and speed > 0.3)


func _now() -> float:
	return traffic.sim.day * 1440.0 + traffic.sim.minutes


## How hard its engine is working, as a share of full power: towing the net is
## heavy going at little more than walking pace.
func _load() -> float:
	if state == State.FISHING and work != Work.HAULING:
		return 0.85
	return clampf(speed / cruise, 0.0, 1.0)


func fishing() -> bool:
	return state == State.FISHING


## In or out of its berth on a set track.
func manoeuvring() -> bool:
	return state == State.LEAVING or state == State.ARRIVING


func quay_name() -> String:
	return wharf_name()


func _tie_up() -> void:
	state = State.ALONGSIDE
	_lie_alongside()


## When it next goes out: in the small hours of a coming day (now and then it
## takes a day off).
func _plan_next_trip() -> void:
	var day := traffic.sim.day + 1
	if traffic.sim.hour() < SAIL_HOURS.x:
		day = traffic.sim.day
	if traffic.rng.randf() < DAY_OFF:
		day += 1
	_sail_at = day * 1440.0 + traffic.rng.randf_range(SAIL_HOURS.x, SAIL_HOURS.y) * 60.0


func _cast_off() -> void:
	var g := traffic.reserve_ground(self)
	if g == null:
		_sail_at = _now() + 30.0
		return
	if not traffic.try_lock(quay, self):
		traffic.release_ground(g, self)
		return
	ground = g
	fish_hold = 0.0
	_home_by = traffic.rng.randf_range(HOME_BY.x, HOME_BY.y)
	# It shoots the net at the near end of the ground and tows to the far end.
	var b := _berth_pos(berth)
	_tow_end = 1.0 if g.at(1.0, 0.0).distance_to(b) > g.at(-1.0, 0.0).distance_to(b) else -1.0
	_tow_across = traffic.rng.randf_range(-FishingGround.HALF_WIDTH, FishingGround.HALF_WIDTH)
	state = State.LEAVING
	_leave()


## Starts it already out on its ground (for boats at sea when the map opens).
func start_at_sea() -> bool:
	var g := traffic.reserve_ground(self)
	if g == null:
		return false
	_tow_end = 1.0 if traffic.rng.randf() < 0.5 else -1.0
	_tow_across = traffic.rng.randf_range(-FishingGround.HALF_WIDTH, FishingGround.HALF_WIDTH)
	var p := g.at(traffic.rng.randf_range(-0.6, 0.6) * _tow_end, _tow_across)
	if not traffic.is_clear(p, 75.0, self):
		traffic.release_ground(g, self)
		return false
	ground = g
	fish_hold = traffic.rng.randf_range(0.1, 0.35)
	_home_by = traffic.rng.randf_range(HOME_BY.x, HOME_BY.y)
	var d := g.axis * _tow_end
	_yaw = atan2(d.x, d.y)
	position = Vector3(p.x, 0.0, p.y)
	_start_helm(State.FISHING)
	work = Work.TOWING
	helm.set_goal(_tow_target())
	speed = TOW_SPEED
	return true


# --- In and out of the quay ---------------------------------------------------------

func _alongside() -> bool:
	return state == State.ALONGSIDE


func _waiting_in() -> bool:
	return state == State.WAITING


func _left_berth() -> void:
	_start_helm(State.STEAMING)
	helm.set_goal(ground.at(-_tow_end, _tow_across))


func _came_alongside() -> void:
	trips += 1
	_landed_at = _now()
	_plan_next_trip()
	_tie_up()


func _start_helm(st: State) -> void:
	state = st
	free_nav = true
	helm = Helm.new(self, traffic)


func _begin_arriving() -> void:
	state = State.ARRIVING
	_come_in()


# --- Out on the water ---------------------------------------------------------------

## Where it is towing to now: the far end of the ground, on this tow's line.
func _tow_target() -> Vector2:
	return ground.at(_tow_end, _tow_across)


func _navigate(delta: float) -> void:
	match state:
		State.STEAMING:
			if helm.distance_left() < GOAL_R * 2.0:
				state = State.FISHING
				_begin_shooting()
		State.FISHING:
			_work(delta)
		State.HOMEWARD:
			if helm.distance_left() < GOAL_R:
				if traffic.try_lock(quay, self):
					_begin_arriving()
					return
				state = State.WAITING
				traffic.queue_for(quay, self)
		State.WAITING:
			if traffic.try_lock(quay, self):
				_begin_arriving()
				return
	helm.update(delta)
	var want_yaw := helm.want_yaw
	var target := helm.want_speed
	match state:
		State.WAITING:
			target = minf(target, 3.6)
			if helm.distance_left() < HOLD_R and helm.give_way_to == null:
				want_yaw = _yaw
				target = 0.0
		State.FISHING:
			# Hauling, it lies stopped, the others keeping clear; unless one of the
			# ferries or ships needs it out of the way.
			if work == Work.HAULING and not _must_move():
				want_yaw = _yaw
				target = 0.0
	_make_way(delta, want_yaw, target, spec.turn)
	position.y = sin(_bob * 1.1) * 0.18
	_pose(delta)


## Whether what it is keeping clear of is a ship or a vessel working with one,
## which it must get out of the way of even while hauling.
func _must_move() -> bool:
	if not (helm.give_way_to is Vessel):
		return false
	var r := (helm.give_way_to as Vessel).road()
	return r == Road.SHIP or r == Road.RESTRICTED


## The round of the work on the ground: shoot the net, tow it to the end of the
## ground, stop to haul it, and go again the other way (turning as it shoots).
func _work(delta: float) -> void:
	match work:
		Work.SHOOTING:
			_timer -= delta
			if _timer <= 0.0:
				work = Work.TOWING
		Work.TOWING:
			if helm.distance_left() < GOAL_R:
				_tow_end = -_tow_end
				_tow_across = traffic.rng.randf_range(-FishingGround.HALF_WIDTH, FishingGround.HALF_WIDTH)
				helm.set_goal(_tow_target())
				work = Work.HAULING
				_timer = traffic.rng.randf_range(HAUL_TIME.x, HAUL_TIME.y)
		Work.HAULING:
			if not _must_move():
				_timer -= delta
			if _timer <= 0.0:
				hauls += 1
				fish_hold = minf(fish_hold + traffic.rng.randf_range(CATCH.x, CATCH.y) * ground.richness, 1.0)
				if fish_hold >= 0.95 or traffic.sim.hour() >= _home_by:
					_head_home()
				else:
					_begin_shooting()


func _begin_shooting() -> void:
	work = Work.SHOOTING
	_timer = traffic.rng.randf_range(SHOOT_TIME.x, SHOOT_TIME.y)
	helm.set_goal(_tow_target())


func _head_home() -> void:
	traffic.release_ground(ground, self)
	state = State.HOMEWARD
	helm.set_goal(traffic.wait_spot(quay, berth))


## A slow roll in the swell; towing, it sits down a little by the stern.
func _pose(_delta: float) -> void:
	var squat := 0.012 if state == State.FISHING and work != Work.HAULING else 0.0
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -squat + sin(_bob * 0.7) * 0.008) \
			* Basis(Vector3.BACK, sin(_bob * 0.83) * SWELL_ROLL)


## Sidelights and stern light under way, and the masthead light steaming;
## working, the trawling lights and its deck lit (and alongside, landing the
## catch). The warps show while the net is out.
func _show_lights() -> void:
	_warps.visible = state == State.FISHING and work != Work.HAULING
	_nav_lights.visible = state != State.ALONGSIDE
	var working := state == State.FISHING
	_steam_lights.visible = state != State.ALONGSIDE and not working
	_work_lights.visible = working or (state == State.ALONGSIDE and _now() - _landed_at < LANDING.y)


# --- Helm hooks ---------------------------------------------------------------------

func helm_speed(_yaw_to: float) -> float:
	if state == State.FISHING:
		return SHOOT_SPEED if work == Work.SHOOTING else TOW_SPEED
	return cruise


func helm_turn_rate() -> float:
	return spec.turn


func road() -> Road:
	match state:
		State.ALONGSIDE:
			return Road.MOORED
		State.LEAVING, State.ARRIVING:
			return Road.MANOEUVRING
		State.FISHING:
			return Road.FISHING
	return Road.POWER


# --- Vessel ---------------------------------------------------------------------------

func wake_hull() -> Vector4:
	var h := spec.wake_hull()
	# Towing, the prop churns hard for the little way it makes: a low, broad,
	# messy wash rather than a clean wake.
	if state == State.FISHING and work != Work.HAULING:
		h.z = 1.1
		h.w *= 0.5
	elif manoeuvring():
		h.z = 0.8
	return h


func resting() -> bool:
	return fishing() and work == Work.HAULING


func status_text() -> String:
	var holding := holding_text()
	if holding != "":
		return holding
	match state:
		State.ALONGSIDE:
			if _now() - _landed_at < LANDING.x + 15.0:
				return "Landing the catch at " + quay_name()
			return "Alongside at " + quay_name()
		State.LEAVING:
			return "Leaving " + quay_name()
		State.WAITING:
			return "Waiting to come alongside at " + quay_name()
		State.ARRIVING:
			return "Coming alongside at " + quay_name()
	if helm and helm.give_way_why != "":
		return helm.give_way_why
	match state:
		State.STEAMING:
			return "Steaming out to the fishing grounds"
		State.HOMEWARD:
			return "Steaming home with the catch"
	if work == Work.SHOOTING:
		return "Shooting the net"
	if work == Work.HAULING:
		return "Hauling the net"
	var to := helm.aim() - pos2()
	if absf(angle_difference(_yaw, atan2(to.x, to.y))) > 0.6:
		return "Trawling · turning for the next tow"
	return "Trawling"
