class_name Tug
extends ShipTender
## An escort tug: meets each laden tanker as it comes in and keeps station off
## its quarter, ready to take a line, all the way through until the pilot is
## fetched off; then it heads home (see Pilotage). Between jobs it lies alongside
## at the pilot station.

const ASTERN := 24.0           # its station: this far astern of the tanker's stern, along its track,
const OFF := 4.0               # and this far out to one side of its wake

var _mast_light: MeshInstance3D


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, st: MapData.PilotStation, b: int, variant: int) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	_hull = apply_spec(sp, variant)
	_nav_lights = MeshInstance3D.new()
	_nav_lights.mesh = Models.tug_nav_lights()
	_mast_light = MeshInstance3D.new()
	_mast_light.mesh = Models.tug_mast_light()
	for l: MeshInstance3D in [_nav_lights, _mast_light]:
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.layers = NightLights.LAYER
		lights.add_child(l)
	wharf = st
	berth = b
	# (Handier alongside than a trawler: thrusters, or twin screws.)
	crab_speed = 0.9
	_bob = t.rng.randf() * TAU
	_tie_up()


func escort(sh: CargoShip, meet: Vector2) -> void:
	# Off the quarter away from the pilot's ladder.
	assign(sh, meet, -sh.lee_side(traffic.sim.wind_from()))
	sh.escort = self


## Off the tanker's quarter (ship frame, for the hooks that want it).
func _station(g: float) -> Vector2:
	return Vector2(-(ship.half_seg + ship.hull_radius + ASTERN), ship.hull_radius * 0.5 + hull_radius + g)


## Astern of the tanker along its track (so it follows the tanker round its
## turns rather than swinging wide of them), a little off to one side of its
## wake: further in, straight astern, where that would be shoal.
func _station_world(g: float) -> Vector2:
	var back := ship.s - (ship.half_seg + ship.hull_radius + ASTERN)
	var p := ship.path.sample(back) if back > 0.0 else ship.pos2() - ship.heading2() * (ship.half_seg + ship.hull_radius + ASTERN)
	var t := ship.path.tangent(maxf(back, 0.0), 10.0)
	var right := Vector2(-t.y, t.x)
	var lat := ship.hull_radius * 0.5 + hull_radius + g
	var shoal := -spec.draft - 0.6
	while lat > 0.0:
		var q := p + right * side * lat
		if traffic.sim.terrain.height_at(q.x, q.y) < shoal:
			return q
		lat -= 3.0
	return p


## It keeps steering for its station rather than holding it, braking for
## anything in its way.
func _lockable() -> bool:
	return false


## Done: straight off home (it is astern of the tanker already).
func _sheer(_delta: float) -> bool:
	return true


func _working_gap() -> float:
	return OFF


func _closing_gap() -> float:
	return OFF + 10.0


## Escorting until the tanker has dropped its pilot (or is nearly out).
func _work_done(_delta: float) -> bool:
	return ship.escort_done()


func _start_work() -> void:
	ship.escorted = true
	traffic.pilotage.escorts += 1


func _finished() -> void:
	jobs += 1


func _release_ship() -> void:
	if ship != null and is_instance_valid(ship) and ship.escort == self:
		ship.escort = null
	super()


func _show_lights() -> void:
	super()
	_mast_light.visible = state != State.ALONGSIDE


func _pose(_delta: float) -> void:
	var f := clampf(speed / cruise, 0.0, 1.0)
	basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -0.015 * f + sin(_bob * 0.7) * 0.008) \
			* Basis(Vector3.BACK, sin(_bob * 0.8) * 0.022)


func restricted_text() -> String:
	return "escorting " + ship.vessel_name if ship != null and is_instance_valid(ship) else "escorting"


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
			return "Heading out to meet " + who
		State.STANDING_BY:
			return "Standing by for " + who
		State.CLOSING:
			return "Taking station on " + who
		State.WORKING:
			return "Escorting " + who
		State.SHEERING:
			return "Escort done · leaving " + who
		State.WAITING:
			return "Waiting to come alongside at " + wharf_name()
		State.ARRIVING:
			return "Coming alongside at " + wharf_name()
	if helm and helm.give_way_why != "":
		return helm.give_way_why
	return "Returning to " + wharf_name()
