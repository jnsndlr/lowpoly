class_name CargoShip
extends Vessel
## A cargo ship passing through the archipelago: in from beyond one edge of the
## map, out past another, keeping to the deep channels and to the right. It gives
## way to ferries, and sailboats find their way round it. Held nose to nose with
## a vessel that is waiting on it in turn, it plans a way round. Its size, speed
## and look come from its VesselSpec (VesselTypes.cargo_ships()).

const STUCK_REPLAN := 10.0

var traffic: MarineTraffic
var path: NavPath
var s := 0.0
var _bob := 0.0
var _stuck := 0.0


func setup(t: MarineTraffic, nm: String, sp: VesselSpec, p: NavPath, start: float, variant: int) -> void:
	traffic = t
	vessel_name = nm
	name = nm
	apply_spec(sp, variant)
	path = p
	s = start
	speed = cruise if start > 0.0 else minf(2.0, cruise)
	_bob = t.rng.randf() * TAU
	_place()


func _process(delta: float) -> void:
	_bob += delta
	var target := minf(cruise, yield_speed())
	speed = minf(target, speed + spec.accel * delta)
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


## Plans from where it is round the vessel in its way (and the way that one is
## heading) back to its old path, inside the map; the run out stays as it was.
## Each pose along the new way is checked like any other, so it only swings
## onto it if that is clear.
func _check_stuck(delta: float) -> void:
	if speed < 0.05 and clear < 1.0 and blocked_by_hull and is_instance_valid(blocker) and blocker.waits_for(self):
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
	return "Passing through"
