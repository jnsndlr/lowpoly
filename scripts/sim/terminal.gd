class_name Terminal
extends Node3D
## One island's ferry terminal. Cars spawn in town, drive to the holding lot, queue
## in per-route lanes, and board when their ferry is loading. Arriving cars drive
## off the pier, out through the exit lane and back into town.
## The node's transform is the terminal frame (see Layout).

var sim: Simulation
var island: MapData.Island
var lanes := {}        # route id -> Array of {v: float, queue: Array, enroute: int (slots)}
var slip_v := {}       # route id -> lateral offset of that route's slip
var ferry_for := {}    # route id -> Ferry
var slots_per_lane := Layout.slots_per_lane()
var avg_wait := 6.0    # minutes, moving average
var turned_recent := 0.0
var served_today := 0
var _inbound: Array[PackedVector3Array] = []
var _outbound: Array[PackedVector3Array] = []
var _spawn_acc := 0.0


func setup(s: Simulation, isl: MapData.Island) -> void:
	sim = s
	island = isl
	name = isl.name + " Terminal"
	transform = isl.terminal_xform()
	var lane_sets := Layout.lane_positions(isl.lot_half_width, isl.slips.size())
	for i in isl.slips.size():
		var rid := isl.slips[i]
		slip_v[rid] = isl.slip_offset(i)
		var arr: Array = []
		for v in lane_sets[i]:
			arr.append({"v": v, "queue": [], "enroute": 0})
		lanes[rid] = arr
	_build_road_paths()


func _build_road_paths() -> void:
	var to_lot := island.road_main_a.duplicate()
	to_lot.reverse()
	var branches: Array[PackedVector3Array] = []
	if island.road_main_b.size() > 1:
		branches.append(island.road_main_b)
	branches.append_array(island.road_cross)
	if branches.is_empty():
		branches.append(PackedVector3Array([island.road_main_a[island.road_main_a.size() - 1]]))
	for b in branches:
		var inbound := b.duplicate()
		inbound.reverse()
		inbound.append_array(to_lot)
		_inbound.append(_keep_right(inbound))
		var outbound := island.road_main_a.duplicate()
		outbound.append_array(b)
		_outbound.append(_keep_right(outbound))


## Offsets a centre-line path onto the right-hand lane.
static func _keep_right(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var last_dir := Vector3.FORWARD
	for i in pts.size():
		var d := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		d.y = 0.0
		if d.length_squared() > 0.0001:
			last_dir = d.normalized()
		out.append(pts[i] + last_dir.cross(Vector3.UP) * 2.4)
	return out


func _local(v: float, u: float) -> Vector3:
	return to_global(Vector3(v, Layout.LOT_Y, u))


## Where `car` waits with `ahead` slots taken in front of it: the middle of its slots,
## shifted for a rig (whose tractor is ahead of its middle).
func queue_position(v: float, ahead: int, car: Vehicle) -> Vector3:
	var mid := Layout.LANE_HEAD - (ahead + (car.slots - 1) * 0.5) * Layout.SLOT
	return _local(v, mid - car.center_offset)


## Slots a lane's queue takes.
static func _slots_in(queue: Array) -> int:
	var n := 0
	for c: Vehicle in queue:
		n += c.slots
	return n


## Moves each car in `lane` up to its place in the queue.
func _close_up(lane: Dictionary) -> void:
	var k := 0
	var ahead: Vehicle = null
	for c: Vehicle in lane.queue:
		c.drive(PackedVector3Array([queue_position(lane.v, k, c)]))
		c.leader = ahead
		ahead = c
		k += c.slots


func _process(delta: float) -> void:
	_spawn_acc += sim.demand_rate(island) * delta
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_spawn_car()
	turned_recent *= pow(0.985, delta)


func _pick_route() -> int:
	var total := 0.0
	var weights := {}
	for rid in lanes.keys():
		var r: MapData.Route = sim.map.routes[rid]
		var other := sim.map.islands[r.b if r.a == island.id else r.a]
		weights[rid] = other.population + 600.0
		total += weights[rid]
	var pick := sim.rng.randf() * total
	for rid in weights.keys():
		pick -= weights[rid]
		if pick <= 0.0:
			return rid
	return lanes.keys()[0]


func _pick_lane(rid: int, need := 1) -> Dictionary:
	var best := {}
	var best_count := slots_per_lane - need + 1
	for lane in lanes[rid]:
		var count: int = _slots_in(lane.queue) + lane.enroute
		if count < best_count:
			best_count = count
			best = lane
	return best


func _spawn_car() -> void:
	if lanes.is_empty():
		return
	var car := sim.make_vehicle()
	var lane := _pick_lane(_pick_route(), car.slots)
	if lane.is_empty():
		turned_recent += 1.0
		car.queue_free()
		return
	lane.enroute += car.slots
	var path := _inbound[sim.rng.randi() % _inbound.size()].duplicate()
	path.append(_local(-Layout.EXIT_V, Layout.LOT_BACK + 2.4))
	path.append(_local(lane.v, Layout.LOT_BACK + 4.8))
	car.position = path[0]
	if path.size() > 1:
		var d := path[1] - path[0]
		car.rotation.y = atan2(d.x, d.z)
		car.straighten()
	car.drive(path, _on_car_reached_lot.bind(lane))


func _on_car_reached_lot(car: Vehicle, lane: Dictionary) -> void:
	lane.enroute -= car.slots
	var queue: Array = lane.queue
	var ahead := _slots_in(queue)
	car.leader = queue.back() if not queue.is_empty() else null
	queue.append(car)
	car.lane_v = lane.v
	car.lot_arrival = sim.minutes
	car.drive(PackedVector3Array([queue_position(lane.v, ahead, car)]))


## Places some already-waiting cars so the lot isn't empty at the start.
func prefill() -> void:
	for rid in lanes.keys():
		for lane in lanes[rid]:
			var queue: Array = lane.queue
			var want := sim.rng.randi_range(1, slots_per_lane - 2)
			var k := 0
			while k < want:
				var car := sim.make_vehicle()
				if k + car.slots > slots_per_lane:
					car.queue_free()
					break
				car.position = queue_position(lane.v, k, car)
				car.rotation.y = atan2(island.dock_dir.x, island.dock_dir.z)
				car.straighten()
				car.lane_v = lane.v
				car.lot_arrival = sim.minutes - sim.rng.randf_range(0.0, 20.0)
				queue.append(car)
				k += car.slots


## Removes the front car of the longest lane for this route whose front car `fits`
## (fn(Vehicle) -> bool: room for it on the deck), or null.
func take_car(rid: int, fits := Callable()) -> Vehicle:
	var best: Dictionary = {}
	for lane in lanes[rid]:
		if lane.queue.size() > 0 and (best.is_empty() or lane.queue.size() > best.queue.size()):
			if fits.is_null() or fits.call(lane.queue[0]):
				best = lane
	if best.is_empty():
		return null
	var queue: Array = best.queue
	var car: Vehicle = queue.pop_front()
	_close_up(best)
	avg_wait = lerpf(avg_wait, sim.minutes - car.lot_arrival, 0.1)
	served_today += 1
	return car


func boarding_path(car: Vehicle, rid: int) -> PackedVector3Array:
	var sv: float = slip_v[rid]
	return PackedVector3Array([
		_local(car.lane_v, Layout.LANE_HEAD + 6.0),
		_local(sv - 3.0, Layout.LOT_FRONT + 1.5),
		_local(sv - 3.0, Layout.PIER_END),
	])


func exit_path(rid: int) -> PackedVector3Array:
	var sv: float = slip_v[rid]
	var path := PackedVector3Array([
		_local(sv + 3.0, Layout.PIER_END),
		_local(sv + 3.0, Layout.LOT_FRONT + 1.5),
		_local(Layout.EXIT_V, Layout.LANE_HEAD + 6.0),
		_local(Layout.EXIT_V, Layout.LOT_BACK + 1.5),
	])
	path.append_array(_outbound[sim.rng.randi() % _outbound.size()])
	return path


func queued_for(rid: int) -> int:
	var total := 0
	for lane in lanes[rid]:
		total += lane.queue.size()
	return total


func total_queued() -> int:
	var total := 0
	for rid in lanes.keys():
		total += queued_for(rid)
	return total


func capacity() -> int:
	var total := 0
	for rid in lanes.keys():
		total += lanes[rid].size() * slots_per_lane
	return total


func satisfaction() -> float:
	return clampf(96.0 - maxf(avg_wait - 18.0, 0.0) * 0.9 - turned_recent * 2.0, 15.0, 99.0)


## Returns [minutes until next departure, Ferry] across this terminal's routes.
func next_departure() -> Array:
	var best_min := INF
	var best_ferry: Ferry = null
	for rid in ferry_for.keys():
		var f: Ferry = ferry_for[rid]
		var m := f.minutes_until_departure_from(self)
		if m < best_min:
			best_min = m
			best_ferry = f
	return [best_min, best_ferry]
