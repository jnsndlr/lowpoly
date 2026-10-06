class_name CargoShip
extends Vessel
## A cargo ship passing through the archipelago: in from beyond one edge of the
## map, out past another, keeping to the deep channels and to the right. It gives
## way to ferries, and sailboats find their way round it. Held nose to nose with
## a vessel that is waiting on it in turn, it plans a way round. Its size, speed
## and look come from its VesselSpec (VesselTypes.cargo_ships()).
##
## Coming in, it picks up a pilot from a pilot boat on its boarding ground just
## inside the edge of the map, and drops the pilot again before it goes out
## (Pilotage); it slows down for the boat to come alongside. A laden tanker has
## a tug escorting it through.

const STUCK_REPLAN := 10.0
const BOARD_SPEED := 2.6       # with the pilot boat alongside
const INSIDE := 70.0           # the boarding and landing grounds lie this far inside the map
const SLOW_FOR := 120.0        # (s) it eases down for the pilot boat at most this long before it is alongside

var traffic: MarineTraffic
var path: NavPath
var s := 0.0
var pilot_aboard := false
var pilot_boat: PilotBoat      # the pilot boat bound for it, or alongside
var escort: Tug                # its escort, if it is a tanker
var board_s := 0.0             # where along its path it takes its pilot aboard,
var land_s := INF              # and drops the pilot
var escorted := false          # (it has had its escort; once is enough)
var pilot_landed := false
var land_here := true          # (whether the pilot station fetches the pilot off, or it stays aboard to the next port)
var _bob := 0.0
var _stuck := 0.0
var _slowed := 0.0             # how long it has been easing down for a pilot boat not yet alongside


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, p: NavPath, start: float, variant: int) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	apply_spec(sp, variant)
	path = p
	s = start
	_find_grounds()
	# Already well in when the map opens: the pilot is aboard.
	pilot_aboard = s > board_s - 40.0
	speed = cruise if start > 0.0 else minf(2.0, cruise)
	_bob = t.rng.randf() * TAU
	_place()


func _process(delta: float) -> void:
	_bob += delta
	var pilot := _pilot_speed()
	_slowed = _slowed + delta if pilot < INF and not (is_instance_valid(pilot_boat) and pilot_boat.working()) else 0.0
	var want := minf(cruise, pilot)
	speed = move_toward(speed, want, (spec.accel if want > speed else spec.decel) * delta)
	speed = minf(speed, yield_speed())
	s += speed * delta
	if s >= path.length:
		traffic.remove(self)
		queue_free()
		return
	_place()
	var h := heading2()
	wake.update(delta, global_position, Vector3(h.x, 0.0, h.y), speed * delta, speed / cruise, speed > 0.1)
	_check_stuck(delta)


func _place() -> void:
	var p := path.sample(s)
	var t := path.tangent(s, spec.half_length * 0.4)
	position = Vector3(p.x, sin(_bob * 0.6) * 0.08, p.y)
	basis = Basis(Vector3.UP, atan2(t.x, t.y)) * Basis(Vector3.BACK, sin(_bob * 0.45) * 0.012)


## Held up by a hull that is waiting on it in turn, or that isn't going anywhere
## (a boat at anchor, say): plans from where it is round the vessel in its way
## (and the way that one is heading) back to its old path, inside the map; the run out stays as it was.
## Each pose along the new way is checked like any other, so it only swings
## onto it if that is clear.
func _check_stuck(delta: float) -> void:
	if speed < 0.05 and clear < 1.0 and blocked_by_hull and is_instance_valid(blocker) \
			and (blocker.waits_for(self) or not blocker.wants_to_move()):
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck < STUCK_REPLAN:
		return
	_stuck = 0.0
	var rejoin_s := path.length - 160.0
	if rejoin_s - s < 120.0:
		return
	var main := traffic.nav.find_path(pos2(), path.sample(rejoin_s), true, traffic.avoid_circles(blocker, 10.0))
	if main.size() < 2:
		return
	main = traffic.nav.finish(main, 10.0, 14.0, 3, spec.half_beam + 2.0)
	main.append(path.pts[path.pts.size() - 1])
	path = NavPath.new(main)
	s = 0.0
	_find_grounds()
	board_s = minf(board_s, 0.0)


## Its boarding and landing grounds: where its path first comes, and last is,
## INSIDE the map.
func _find_grounds() -> void:
	var hs := traffic.sim.map.half_size - INSIDE
	board_s = 0.0
	land_s = path.length
	var first := true
	var d := 0.0
	while d <= path.length:
		var p := path.sample(d)
		if absf(p.x) < hs and absf(p.y) < hs:
			if first:
				board_s = d
				first = false
			land_s = d
		d += 10.0


## The side the pilot's ladder goes over (+1 starboard): its lee, away from
## `wind_from` (where the wind blows from).
func lee_side(wind_from: Vector2) -> float:
	var h := heading2()
	return 1.0 if Vector2(-h.y, h.x).dot(wind_from) < 0.0 else -1.0


func needs_escort() -> bool:
	return spec.id == "tanker"


## The escort's job is done once it is out past where it drops its pilot.
func escort_done() -> bool:
	return s >= land_s - 30.0


## Slow while the pilot boat is alongside, and easing down for it to come
## alongside; slow too if it is past its boarding ground with no pilot aboard
## yet, so the boat can catch it up.
func _pilot_speed() -> float:
	if pilot_boat == null or not is_instance_valid(pilot_boat) or pilot_boat.ship != self:
		return INF
	if pilot_boat.working():
		return BOARD_SPEED
	# (Not for ever: the boat is quick enough to catch it up.)
	if _slowed > SLOW_FOR:
		return INF
	if pilot_boat.pos2().distance_to(pos2()) < 260.0:
		return BOARD_SPEED * 1.2
	if not pilot_aboard and s > board_s:
		return cruise * 0.6
	return INF


func wants_to_move() -> bool:
	return true


func ahead(d: float) -> Vector2:
	return path.sample(s + d)


func path_left() -> float:
	return path.length - s


func status_text() -> String:
	var holding := holding_text()
	if holding != "":
		return holding
	if pilot_boat != null and is_instance_valid(pilot_boat) and pilot_boat.ship == self:
		if pilot_boat.working():
			return "Embarking the pilot" if not pilot_aboard else "Disembarking the pilot"
		if speed < cruise * 0.9 and _pilot_speed() < cruise:
			return "Slowing for the pilot boat"
	var text := "Passing through under pilotage" if pilot_aboard else "Passing through"
	if escort != null and is_instance_valid(escort) and escort.state == ShipTender.State.WORKING:
		text += " · escorted by " + escort.vessel_name
	return text


func pilot_text() -> String:
	if pilot_aboard:
		return "Aboard"
	if pilot_boat != null and is_instance_valid(pilot_boat):
		return "Coming out on " + pilot_boat.vessel_name
	return "Not aboard" if s > board_s else "Boards on the way in"
