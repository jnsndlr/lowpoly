class_name PilotBoat
extends ShipTender
## A pilot boat: runs a pilot out to each ship coming in, and fetches the pilot
## off again before it goes out (see Pilotage). It works the ship's lee side
## (the ship makes a lee for the ladder): it comes up abreast of the ladder,
## matches the ship's course and speed, closes in until its fendered side is
## against the ship's, and holds there while the pilot climbs the ladder (or
## down it); then it sheers off. On duty it shows the pilot vessel's lights,
## white over red.

enum Job { BOARD, LAND }

const TRANSFER := Vector2(25.0, 40.0)    # game minutes on the ladder

var job := Job.BOARD
var _timer := 0.0
var _duty_lights: MeshInstance3D
var _ladder: MeshInstance3D


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, st: MapData.PilotStation, b: int, variant: int) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	_hull = apply_spec(sp, variant)
	_nav_lights = MeshInstance3D.new()
	_nav_lights.mesh = Models.pilot_boat_nav_lights()
	_duty_lights = MeshInstance3D.new()
	_duty_lights.mesh = Models.pilot_boat_duty_lights()
	for l: MeshInstance3D in [_nav_lights, _duty_lights]:
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.layers = NightLights.LAYER
		lights.add_child(l)
	_ladder = MeshInstance3D.new()
	_ladder.visible = false
	_hull.add_child(_ladder)
	wharf = st
	berth = b
	# (Handier alongside than a trawler: thrusters, or twin screws.)
	crab_speed = 1.1
	_bob = t.rng.randf() * TAU
	_tie_up()


## Takes the job of boarding `sh`'s pilot, or fetching the pilot off, working its
## lee side unless that is the shoal side where they will meet.
func assign_job(sh: CargoShip, j: Job, meet: Vector2) -> void:
	job = j
	var s0 := maxf(sh.s, sh.board_s) if j == Job.BOARD else sh.land_s - 300.0
	var lee := sh.lee_side(traffic.sim.wind_from())
	assign(sh, meet, _pick_side(sh, lee, s0, s0 + 400.0))
	sh.pilot_boat = self


## Abreast of the ladder, a little aft of amidships.
func _station(g: float) -> Vector2:
	return Vector2(-ship.spec.half_length * 0.12, ship.hull_radius + hull_radius + g)


func _working_gap() -> float:
	return 0.4


func _closing_gap() -> float:
	return 14.0


func _start_work() -> void:
	_timer = traffic.rng.randf_range(TRANSFER.x, TRANSFER.y)
	# The ship's ladder, over its side by the boat (which side of the boat that is).
	var out := (hull_radius + _working_gap()) * side
	var ship_deck := 3.2 * ship.spec.scale
	_ladder.mesh = Models.pilot_ladder(absf(out), ship_deck)
	_ladder.rotation = Vector3(0, 0 if side > 0.0 else PI, 0)
	_ladder.visible = true


func _work_done(delta: float) -> bool:
	_timer -= delta
	if _timer <= 0.0:
		_ladder.visible = false
	return _timer <= 0.0


func _finished() -> void:
	jobs += 1
	if job == Job.BOARD:
		ship.pilot_aboard = true
		traffic.pilotage.boarded += 1
	else:
		ship.pilot_aboard = false
		ship.pilot_landed = true
		traffic.pilotage.landed += 1
	if ship.pilot_boat == self:
		ship.pilot_boat = null


func _release_ship() -> void:
	_ladder.visible = false
	if ship != null and is_instance_valid(ship) and ship.pilot_boat == self:
		ship.pilot_boat = null
	super()


func _show_lights() -> void:
	super()
	_duty_lights.visible = state != State.ALONGSIDE


## Running fast and light, she sits up by the bow.
func _pose(_delta: float) -> void:
	var f := clampf(speed / cruise, 0.0, 1.0)
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -0.04 * smoothstep(0.3, 0.8, f) + sin(_bob * 0.8) * 0.008) \
			* Basis(Vector3.BACK, sin(_bob * 0.83) * 0.02)


func restricted_text() -> String:
	if ship == null:
		return "working"
	return "alongside " + ship.vessel_name if state == State.WORKING else "working with " + ship.vessel_name


func status_text() -> String:
	var holding := holding_text()
	if holding != "":
		return holding
	var who := ship.vessel_name if ship != null and is_instance_valid(ship) else ""
	match state:
		State.ALONGSIDE:
			return "Alongside at " + wharf_name()
		State.LEAVING:
			return "Leaving " + wharf_name()
		State.OUTBOUND:
			return "Running the pilot out to " + who if job == Job.BOARD else "Running out to fetch the pilot off " + who
		State.STANDING_BY:
			return "Standing by for " + who
		State.CLOSING:
			return "Coming alongside " + who
		State.WORKING:
			return ("Pilot boarding " if job == Job.BOARD else "Pilot coming down the ladder of ") + who
		State.SHEERING:
			return "Sheering off from " + who
		State.WAITING:
			return "Waiting to come alongside at " + wharf_name()
		State.ARRIVING:
			return "Coming alongside at " + wharf_name()
	if helm and helm.give_way_why != "":
		return helm.give_way_why
	return "Returning to " + wharf_name()
