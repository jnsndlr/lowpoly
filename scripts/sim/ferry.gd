class_name Ferry
extends Vessel
## A double-ended car ferry shuttling along one route. It never turns around: cars
## board at the end facing the pier, park on the deck (as children of the ferry, so
## they ride along) and drive off the opposite end at the destination. Its size
## (FerryClass) sets how many cars it takes and how fast it goes; whatever its
## length, it docks with its end at the ramp.

enum State { UNLOADING, LOADING, SAILING }

const ACCEL := 1.4
# Arrival: ferries ease off to APPROACH_SPEED along the run-in, then from the
# moment the bow passes the outer dolphins the forward prop reverse-thrusts them
# to a stop at the dock (the stern props backing off).
const DECEL := 0.5
# Braking to give way to other traffic.
const YIELD_DECEL := 0.9
const APPROACH_SPEED := 3.2
const OUTER_DOLPHIN_U := Layout.DOLPHIN_OUTER.x
const MIN_DWELL := 10.0
const MAX_DWELL := 24.0
const DISPATCH_GAP := 0.5
# A ferry about to leave holds in at the dock while a stretch of water it shares
# with another route, no further out than this, is taken, or while a ferry
# coming in to the same terminal, this close to it, has it still to pass.
const ARRIVAL_PRIORITY := 220.0

var sim: Simulation
var fc: FerryClass
var route: MapData.Route
var ferry_name := ""
var term_a: Terminal
var term_b: Terminal
var state := State.LOADING
var at_a := true        # docked at A, or departed from A while sailing
var hull: MeshInstance3D
var traveled := 0.0      # how far the hull's centre has come, dock to dock
var trips := 0
var aboard: Array[Vehicle] = []
var _slots: Array[Vehicle] = []
var _boarding := 0
var _unload_queue: Array[Vehicle] = []
var _dispatch_timer := 0.0
var _state_time := 0.0
var _bob_time := 0.0
var _thrust := 0.0   # forward prop reverse thrust while braking, 0..1
var _last_pos := Vector3.ZERO
var _tracking := false
var _waiting_for: Ferry = null   # holding off a corridor this ferry has reserved
var _giving_way := false         # (holding in at the dock for _waiting_for to come in)
var _runs := {}                   # at_a -> _corridor_runs() for that direction
# Route curves run between where a size-4 ferry's centre lies docked
# (Layout.DOCK_U); a shorter one docks this much further in at both ends, a
# longer one further out (negative).
var _inset := 0.0


func setup(s: Simulation, r: MapData.Route, nm: String, size: int) -> void:
	sim = s
	route = r
	fc = FerryClass.of(size)
	ferry_name = nm
	vessel_name = nm
	name = nm
	cruise = fc.cruise
	yield_decel = YIELD_DECEL
	_inset = Layout.FERRY_HALF - fc.half_length
	# A capsule round the hull: its corners just touch, its ends cover the bows.
	half_seg = fc.half_seg()
	hull_radius = fc.hull_radius
	claim_step = 4.0
	wake = WakeTrail.new(fc.half_length, 8.0 * fc.half_length / 15.0, 24.0, 46)
	term_a = sim.terminals[r.a]
	term_b = sim.terminals[r.b]
	term_a.ferry_for[r.id] = self
	term_b.ferry_for[r.id] = self
	_slots.resize(fc.capacity)
	hull = MeshInstance3D.new()
	hull.mesh = Models.ferry(fc)
	# Fixes which of its rooms are lit (lit_vc.gdshader); the origin would change every frame.
	hull.material_override = Models.hull_material()
	hull.set_instance_shader_parameter("room_seed", randf_range(1.0, 1000.0))
	add_child(hull)
	_place(-_inset)


## Spreads the fleet across different phases so the preview starts busy.
func start_staggered(i: int) -> void:
	match i % 3:
		0:
			_begin_loading()
		1:
			state = State.SAILING
			traveled = run_length() * sim.rng.randf_range(0.25, 0.6)
			speed = fc.cruise
			for k in sim.rng.randi_range(fc.capacity / 3, fc.capacity - fc.capacity / 9):
				var car := sim.make_vehicle(self)
				var slot := _free_slot(car.is_truck)
				car.position = _slot_local(slot)
				_slots[slot] = car
				aboard.append(car)
			_place(_route_s(traveled))
		2:
			at_a = false
			_place(route.length + _inset)
			_begin_loading()


func here() -> Terminal:
	return term_a if at_a else term_b


func destination() -> Terminal:
	return term_b if at_a else term_a


## How much further in than the route curve's ends this ferry lies docked.
func dock_inset() -> float:
	return _inset


## How far the hull's centre runs from dock to dock.
func run_length() -> float:
	return route.length + 2.0 * _inset


## Where on the route curve the hull's centre is, `t` into this crossing (beyond
## its ends, for a short ferry docking further in).
func _route_s(t: float) -> float:
	return t - _inset if at_a else route.length + _inset - t


## Point `s` along the route curve, carried on straight past its ends (they run
## square out from the slips).
func route_point(s: float) -> Vector3:
	var length := route.length
	if s >= 0.0 and s <= length:
		return route.curve.sample_baked(s)
	var end := 0.0 if s < 0.0 else length
	var inner := clampf(end + (1.5 if s < 0.0 else -1.5), 0.0, length)
	var p := route.curve.sample_baked(end)
	var dir := p - route.curve.sample_baked(inner)
	dir.y = 0.0
	return p + dir.normalized() * absf(s - end)


func _slot_local(i: int) -> Vector3:
	return Vector3(fc.cols[i % fc.lanes], Layout.DECK_Y, fc.row_z[floori(i / float(fc.lanes))])


## Fills from the far end first so cars drive in past the ones already parked, and
## sends trucks to the lanes with the headroom (cars to the others) while there's
## room there.
func _free_slot(truck := false) -> int:
	var fallback := -1
	for r in fc.rows:
		var row := r if at_a else fc.rows - 1 - r
		for c in fc.lanes:
			var idx := row * fc.lanes + c
			if _slots[idx] == null:
				if fc.lane_suits(c, truck):
					return idx
				if fallback < 0:
					fallback = idx
	return fallback


func _process(delta: float) -> void:
	_state_time += delta
	match state:
		State.UNLOADING:
			_tick_unloading(delta)
		State.LOADING:
			_tick_loading(delta)
		State.SAILING:
			_tick_sailing(delta)
	if state != State.SAILING:
		# Holds the ferry against the dock for a moment after arriving.
		_thrust = move_toward(_thrust, 0.0, delta * 0.4)
	_update_trail(delta)


func _begin_unloading() -> void:
	state = State.UNLOADING
	_state_time = 0.0
	_dispatch_timer = 0.0
	_unload_queue = aboard.duplicate()
	var exit_sign := -1.0 if at_a else 1.0
	_unload_queue.sort_custom(func(a: Vehicle, b: Vehicle): return a.position.z * exit_sign > b.position.z * exit_sign)
	aboard.clear()
	_slots.fill(null)


func _tick_unloading(delta: float) -> void:
	_dispatch_timer -= delta
	if not _unload_queue.is_empty():
		if _dispatch_timer <= 0.0:
			_dispatch_timer = DISPATCH_GAP
			_drive_off(_unload_queue.pop_front())
	elif _dispatch_timer < -2.0:
		_begin_loading()


func _drive_off(car: Vehicle) -> void:
	var exit_z := -fc.end_z if at_a else fc.end_z
	var start := to_global(Vector3(car.position.x, Layout.DECK_Y, exit_z))
	car.reparent(sim.traffic)
	var path := PackedVector3Array([start])
	path.append_array(here().exit_path(route.id))
	car.drive(path, func(c: Vehicle): c.queue_free())


func _begin_loading() -> void:
	state = State.LOADING
	_state_time = 0.0
	_dispatch_timer = 0.0
	speed = 0.0


func _tick_loading(delta: float) -> void:
	_dispatch_timer -= delta
	var term := here()
	if _dispatch_timer <= 0.0 and _state_time < MAX_DWELL and aboard.size() + _boarding < fc.capacity:
		var car := term.take_car(route.id)
		if car != null:
			_dispatch_timer = DISPATCH_GAP
			_drive_on(car, term)
	var full := aboard.size() + _boarding >= fc.capacity
	var queue_empty := term.queued_for(route.id) == 0
	if _boarding == 0 and _state_time >= MIN_DWELL and (full or queue_empty or _state_time >= MAX_DWELL):
		state = State.SAILING
		traveled = 0.0
		_state_time = 0.0
		# The last crossing's wake has long faded by now, and it lies along the same
		# water, so start a fresh trail.
		wake.clear()


func _drive_on(car: Vehicle, term: Terminal) -> void:
	var slot := _free_slot(car.is_truck)
	_slots[slot] = car
	_boarding += 1
	var local := _slot_local(slot)
	var entry_z := -fc.end_z if at_a else fc.end_z
	var path := term.boarding_path(car, route.id)
	path.append(to_global(Vector3(local.x, Layout.DECK_Y, entry_z)))
	path.append(to_global(local))
	car.drive(path, _on_boarded.bind(slot))
	sim.collect_fare(car)


func _on_boarded(car: Vehicle, slot: int) -> void:
	car.reparent(self)
	car.position = _slot_local(slot)
	car.rotation = Vector3(0.0, 0.0 if at_a else PI, 0.0)
	aboard.append(car)
	_boarding -= 1


func _tick_sailing(delta: float) -> void:
	var remaining := run_length() - traveled
	# Distance from the bow reaching the outer dolphins to being docked.
	var zone := OUTER_DOLPHIN_U - Layout.PIER_END - 0.4
	var rem := maxf(remaining, 0.0)
	var brake_v: float
	if rem > zone:
		brake_v = APPROACH_SPEED + sqrt(2.0 * DECEL * (rem - zone))
	else:
		brake_v = 0.3 + (APPROACH_SPEED - 0.3) * sqrt(rem / zone)
	# Picks up from wherever it is (it may have stopped for traffic mid-crossing).
	var target := minf(fc.cruise, minf(brake_v, yield_speed()))
	var wait := _corridor_wait()
	hold = wait
	target = minf(target, sqrt(2.0 * YIELD_DECEL * maxf(wait - 0.5, 0.0)))
	speed = minf(target, speed + ACCEL * delta)
	_thrust = move_toward(_thrust, 1.0 if rem < zone and rem > 0.5 else 0.0, delta * 0.8)
	traveled = minf(traveled + speed * delta, run_length())
	_place(_route_s(traveled))
	_bob_time += delta
	position.y = sin(_bob_time * 1.3) * 0.07
	if traveled >= run_length() - 0.01:
		_dock_corridors()
		hold = INF
		speed = 0.0
		position.y = 0.0
		at_a = not at_a
		trips += 1
		_begin_unloading()


## The corridors this crossing passes through, in order, grouped into runs where
## one starts before the last ends, as [start, end, [[end, corridor], ...]]
## (distances along the crossing, as `traveled`). A ferry takes a whole run at once, so under
## way it never sits holding one corridor while it waits for the next, and no
## ring of ferries can each be waiting on the one ahead.
func _corridor_runs() -> Array:
	if _runs.has(at_a):
		return _runs[at_a]
	var list := []
	for c: MarineTraffic.Corridor in sim.marine.corridors[route.id]:
		var span: Vector2 = c.span[route.id]
		var t0 := span.x + _inset if at_a else route.length + _inset - span.y
		var t1 := span.y + _inset if at_a else route.length + _inset - span.x
		list.append([t0, t1, c])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var runs := []
	for e in list:
		if not runs.is_empty() and e[0] <= runs[-1][1] + 1.0:
			runs[-1][1] = maxf(runs[-1][1], e[1])
			runs[-1][2].append([e[1], e[2]])
		else:
			runs.append([e[0], e[1], [[e[1], e[2]]]])
	_runs[at_a] = runs
	return runs


## Distance to go before the next run of corridors another ferry holds part of
## (INF if none). Reserves the next run when it is free and frees corridors as
## the ferry leaves them behind.
func _corridor_wait() -> float:
	_waiting_for = null
	_giving_way = false
	if traveled < 0.5 and _blocked_at_dock():
		return 0.0
	for run in _corridor_runs():
		for e in run[2]:
			if traveled > e[0] and e[1].owner == self:
				e[1].owner = null
		if traveled > run[1]:
			continue
		if run[0] - traveled > self_look() + 10.0:
			break
		var holder := _run_holder(run, traveled)
		if holder == null:
			for e in run[2]:
				if traveled <= e[0]:
					e[1].owner = self
		else:
			_waiting_for = holder
			return run[0] - traveled
		break
	return INF


## Ready to cast off: whether to hold in at the dock instead, because a stretch
## of shared water not far out is taken by another ferry (rather than going out
## only to stop short of it), or one coming in here has it still to pass (the
## arrival goes first). Never for a ferry already waiting on this one, which
## this one may be lying in the way of.
func _blocked_at_dock() -> bool:
	for run in _corridor_runs():
		if run[0] - traveled > ARRIVAL_PRIORITY:
			break
		var holder := _run_holder(run, traveled)
		if holder != null and holder._waiting_for != self:
			_waiting_for = holder
			return true
		holder = _arriving_through(run)
		if holder != null:
			_waiting_for = holder
			_giving_way = true
			return true
	return false


## Another ferry coming in to the terminal this one is leaving that has a corridor
## of `run` still to pass and is nearly there: the arrival goes first. (Not one
## already waiting on this ferry, which may be lying in its way.)
func _arriving_through(run: Array) -> Ferry:
	for e in run[2]:
		var c: MarineTraffic.Corridor = e[1]
		for f: Ferry in c.ferry.values():
			if f == self or f.state != State.SAILING or f.destination() != here() or f._waiting_for == self:
				continue
			var to_go := f.distance_to(c)
			if to_go >= 0.0 and to_go < ARRIVAL_PRIORITY:
				return f
	return null


## How far this ferry has to go to the run of corridors that holds `c` (0 once
## in it), or -1 if it has passed it or isn't sailing.
func distance_to(c: MarineTraffic.Corridor) -> float:
	if state != State.SAILING:
		return -1.0
	for run in _corridor_runs():
		for e in run[2]:
			if e[1] == c:
				if traveled > e[0]:
					return -1.0
				return maxf(run[0] - traveled, 0.0)
	return -1.0


## Whether a ferry docked at the A end (`end_a`) or B end of the route is in the
## way of another route in `run`.
func _run_blocks_dock(run: Array, end_a: bool) -> bool:
	for e in run[2]:
		var d: Vector2i = e[1].docked[route.id]
		if (d.x if end_a else d.y) == 1:
			return true
	return false


## Another ferry (under way, or docked by it) holding a corridor of `run` this one
## has still to pass, `at` along its crossing.
func _run_holder(run: Array, at: float) -> Ferry:
	for e in run[2]:
		var c: MarineTraffic.Corridor = e[1]
		if at <= e[0] and c.owner != null and c.owner != self:
			return c.owner
	return null


## At the start of the game: a ferry docked at a slip some other route runs
## through takes the run of corridors round it (as one arriving would have); one
## mid-crossing takes the run it is in. If another ferry already has it, this one
## drops back to wait outside, turned round to be arriving if it was docked.
func claim_corridors_at_start() -> void:
	var at := 0.0 if state != State.SAILING else traveled
	for run in _corridor_runs():
		if at < run[0] or at > run[1]:
			continue
		# Docked where it is in nobody's way: it takes the run when it leaves.
		if state != State.SAILING and not _run_blocks_dock(run, at_a):
			return
		if _run_holder(run, at) == null:
			for e in run[2]:
				if at <= e[0]:
					e[1].owner = self
			return
		if state != State.SAILING:
			at_a = not at_a
			state = State.SAILING
			_state_time = 0.0
			for r in _corridor_runs():
				if r[1] >= run_length() - 1.0:
					at = r[0]
		else:
			at = run[0]
		traveled = maxf(at - fc.half_length, 0.0)
		speed = 0.0
		_place(_route_s(traveled))
		claim_corridors_at_start()
		return


## Docking: if another route runs so close past this slip that the docked ferry
## is in its way, keeps the run of corridors round it (and takes back any of it
## that it passed coming in and are free), so nothing comes by until it has left
## again. Frees the rest.
func _dock_corridors() -> void:
	for run in _corridor_runs():
		var keep: bool = run[1] >= run_length() - 1.0 and _run_blocks_dock(run, not at_a)
		for e in run[2]:
			if keep:
				# (Never from another ferry: one that has taken a corridor this one
				# already passed keeps it.)
				if e[1].owner == null:
					e[1].owner = self
			elif e[1].owner == self:
				e[1].owner = null


func wants_to_move() -> bool:
	return state == State.SAILING


func waiting_on() -> Array[Vessel]:
	var out := super()
	if is_instance_valid(_waiting_for):
		out.append(_waiting_for)
	return out


func ahead(d: float) -> Vector2:
	# Docked, `traveled` still counts the last crossing but at_a has flipped.
	if state != State.SAILING:
		return pos2()
	var p := route_point(_route_s(minf(traveled + d, run_length())))
	return Vector2(p.x, p.z)


func path_left() -> float:
	return run_length() - traveled if state == State.SAILING else 0.0


## Positions the ferry at distance s along the route curve. +Z always faces A → B.
func _place(s: float) -> void:
	var p := route_point(s)
	var d := route_point(s + 1.5) - route_point(s - 1.5)
	d.y = 0.0
	if d.length_squared() < 1e-6:
		return
	global_transform = Transform3D(Basis.looking_at(-d.normalized(), Vector3.UP), Vector3(p.x, 0.0, p.z))


func _update_trail(delta: float) -> void:
	# Taken from the actual movement, so it can't disagree with which end leads
	# (the ferry is double-ended).
	var moved := global_position - _last_pos
	moved.y = 0.0
	# The first frame has nothing to compare against.
	var moving := _tracking and moved.length_squared() > 1e-8
	_tracking = true
	_last_pos = global_position
	# Only once the ferry is actually under way: on the frame it casts off the
	# heading still points the way it arrived, which would put the first crumb at
	# the wrong end of the hull and fold the trail back on itself. The stern
	# props ease off while the forward prop brakes.
	wake.update(delta, global_position, moved.normalized() if moving else Vector3.ZERO, speed * delta,
			speed / fc.cruise * (1.0 - 0.6 * _thrust), state == State.SAILING and moving)


func wake_shape() -> Vector4:
	# Double-ended and blunt: both ends square off over the last few metres.
	return Vector4(3.0, 0.62, 3.0, 0.62)


func wake_hull() -> Vector4:
	return Vector4(fc.half_beam, fc.half_length * 2.0, 1.0, 1.0)


## Reverse thrust from the forward prop, 0..1 (braking for, or holding at, the dock).
func front_thrust() -> float:
	return _thrust


func load_count() -> int:
	return aboard.size() + _boarding


func kind_text() -> String:
	return fc.label


func status_text() -> String:
	if state == State.SAILING and speed < 0.2 and _waiting_for:
		if _giving_way:
			return "Holding in for %s to come in" % _waiting_for.ferry_name
		return "Waiting for %s to clear the channel" % _waiting_for.ferry_name
	var holding := holding_text()
	if holding != "":
		return holding
	match state:
		State.UNLOADING:
			return "Unloading at " + here().island.name
		State.LOADING:
			return "Boarding at " + here().island.name
	return "En route to %s (%d min)" % [destination().island.name, ceili(eta_minutes())]


func eta_minutes() -> float:
	return (run_length() - traveled) / (fc.cruise * 0.85)


func minutes_until_departure_from(term: Terminal) -> float:
	var crossing := crossing_minutes()
	var turnaround := 16.0
	match state:
		State.LOADING:
			var m := maxf(MIN_DWELL + 2.0 - _state_time, 0.0)
			return m if here() == term else m + crossing + turnaround
		State.UNLOADING:
			var m := turnaround
			return m if here() == term else m + crossing + turnaround
	if destination() == term:
		return eta_minutes() + turnaround
	return eta_minutes() + turnaround + crossing + turnaround


func crossing_minutes() -> float:
	return run_length() / (fc.cruise * 0.85)
