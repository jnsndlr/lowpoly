class_name Terminal
extends Node3D
## One island's ferry terminal. Cars spawn in town, drive to the holding lot, queue
## in per-route lanes, and board when their ferry is loading. Arriving cars drive
## off the pier, out through the exit lane and back into town.
## The node's transform is the terminal frame (see Layout).

var sim: Simulation
var island: MapData.Island
var lanes := {}        # route id -> Array of {v: float, queue: Array, enroute: int}
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
		out.append(pts[i] + last_dir.cross(Vector3.UP) * 0.8)
	return out


func _local(v: float, u: float) -> Vector3:
	return to_global(Vector3(v, Layout.LOT_Y, u))


func slot_position(v: float, index: int) -> Vector3:
	return _local(v, Layout.LANE_HEAD - index * Layout.SLOT)


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


func _pick_lane(rid: int) -> Dictionary:
	var best := {}
	var best_count := slots_per_lane
	for lane in lanes[rid]:
		var count: int = lane.queue.size() + lane.enroute
		if count < best_count:
			best_count = count
			best = lane
	return best


func _spawn_car() -> void:
	if lanes.is_empty():
		return
	var lane := _pick_lane(_pick_route())
	if lane.is_empty():
		turned_recent += 1.0
		return
	lane.enroute += 1
	var car := sim.make_vehicle()
	var path := _inbound[sim.rng.randi() % _inbound.size()].duplicate()
	path.append(_local(-Layout.EXIT_V, Layout.LOT_BACK + 0.8))
	path.append(_local(lane.v, Layout.LOT_BACK + 1.6))
	car.position = path[0]
	car.drive(path, _on_car_reached_lot.bind(lane))


func _on_car_reached_lot(car: Vehicle, lane: Dictionary) -> void:
	lane.enroute -= 1
	var queue: Array = lane.queue
	queue.append(car)
	car.lane_v = lane.v
	car.lot_arrival = sim.minutes
	car.drive(PackedVector3Array([slot_position(lane.v, queue.size() - 1)]))


## Places some already-waiting cars so the lot isn't empty at the start.
func prefill() -> void:
	for rid in lanes.keys():
		for lane in lanes[rid]:
			var queue: Array = lane.queue
			for i in sim.rng.randi_range(1, slots_per_lane - 2):
				var car := sim.make_vehicle()
				car.position = slot_position(lane.v, i)
				car.rotation.y = atan2(island.dock_dir.x, island.dock_dir.z)
				car.lane_v = lane.v
				car.lot_arrival = sim.minutes - sim.rng.randf_range(0.0, 20.0)
				queue.append(car)


## Removes the front car of the longest lane for this route (or null).
func take_car(rid: int) -> Vehicle:
	var best: Dictionary = {}
	for lane in lanes[rid]:
		if lane.queue.size() > 0 and (best.is_empty() or lane.queue.size() > best.queue.size()):
			best = lane
	if best.is_empty():
		return null
	var queue: Array = best.queue
	var car: Vehicle = queue.pop_front()
	for i in queue.size():
		(queue[i] as Vehicle).drive(PackedVector3Array([slot_position(best.v, i)]))
	avg_wait = lerpf(avg_wait, sim.minutes - car.lot_arrival, 0.1)
	served_today += 1
	return car


func boarding_path(car: Vehicle, rid: int) -> PackedVector3Array:
	var sv: float = slip_v[rid]
	return PackedVector3Array([
		_local(car.lane_v, Layout.LANE_HEAD + 2.0),
		_local(sv - 1.0, Layout.LOT_FRONT + 0.5),
		_local(sv - 1.0, Layout.PIER_END),
	])


func exit_path(rid: int) -> PackedVector3Array:
	var sv: float = slip_v[rid]
	var path := PackedVector3Array([
		_local(sv + 1.0, Layout.PIER_END),
		_local(sv + 1.0, Layout.LOT_FRONT + 0.5),
		_local(Layout.EXIT_V, Layout.LANE_HEAD + 2.0),
		_local(Layout.EXIT_V, Layout.LOT_BACK + 0.5),
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
