class_name Ferry
extends Vessel
## A double-ended car ferry shuttling along one route. It never turns around: cars
## board at the end facing the pier, park on the deck (as children of the ferry, so
## they ride along) and drive off the opposite end at the destination.

enum State { UNLOADING, LOADING, SAILING }

const CAPACITY := 36
const CRUISE := 9.0
const ACCEL := 1.4
# Arrival: ferries ease off to APPROACH_SPEED along the run-in, then from the
# moment the bow passes the outer dolphins the forward prop reverse-thrusts them
# to a stop at the dock (the stern props backing off).
const DECEL := 0.5
# Braking to give way to other traffic.
const YIELD_DECEL := 0.9
const APPROACH_SPEED := 3.2
const OUTER_DOLPHIN_U := Layout.PIER_END + 21.0
const MIN_DWELL := 10.0
const MAX_DWELL := 24.0
const DISPATCH_GAP := 0.5
const ROWS := [10.0, 7.5, 5.0, 2.5, 0.0, -2.5, -5.0, -7.5, -10.0]
const COLS := [-2.25, -0.75, 0.75, 2.25]
const END_Z := 14.0
const HULL_HALF_LENGTH := 15.0
const HULL_HALF_BEAM := 4.2

var sim: Simulation
var route: MapData.Route
var ferry_name := ""
var term_a: Terminal
var term_b: Terminal
var state := State.LOADING
var at_a := true        # docked at A, or departed from A while sailing
var hull: MeshInstance3D
var traveled := 0.0
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
var _runs := {}                   # at_a -> _corridor_runs() for that direction


func setup(s: Simulation, r: MapData.Route, nm: String) -> void:
	sim = s
	route = r
	ferry_name = nm
	vessel_name = nm
	name = nm
	cruise = CRUISE
	yield_decel = YIELD_DECEL
	# A capsule round the hull: its corners just touch, its ends cover the bows.
	half_seg = HULL_HALF_LENGTH - 4.3
	hull_radius = 4.3
	claim_step = 4.0
	wake = WakeTrail.new(HULL_HALF_LENGTH, 8.0, 24.0, 46)
	term_a = sim.terminals[r.a]
	term_b = sim.terminals[r.b]
	term_a.ferry_for[r.id] = self
	term_b.ferry_for[r.id] = self
	_slots.resize(CAPACITY)
	hull = MeshInstance3D.new()
	hull.mesh = Models.ferry()
	add_child(hull)
	_place(0.0)


## Spreads the fleet across different phases so the preview starts busy.
func start_staggered(i: int) -> void:
	match i % 3:
		0:
			_begin_loading()
		1:
			state = State.SAILING
			traveled = route.length * sim.rng.randf_range(0.25, 0.6)
			speed = CRUISE
			for k in sim.rng.randi_range(12, CAPACITY - 4):
				var slot := _free_slot()
				var car := sim.make_vehicle(self)
				car.position = _slot_local(slot)
				_slots[slot] = car
				aboard.append(car)
			_place(traveled)
		2:
			at_a = false
			_place(route.length)
			_begin_loading()


func here() -> Terminal:
	return term_a if at_a else term_b


func destination() -> Terminal:
	return term_b if at_a else term_a


func _slot_local(i: int) -> Vector3:
	return Vector3(COLS[i % COLS.size()], Layout.DECK_Y, ROWS[floori(i / float(COLS.size()))])


## Fills from the far end first so cars drive in past the ones already parked.
func _free_slot() -> int:
	for r in ROWS.size():
		var row := r if at_a else ROWS.size() - 1 - r
		for c in COLS.size():
			var idx := row * COLS.size() + c
			if _slots[idx] == null:
				return idx
	return -1


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
	var exit_z := -END_Z if at_a else END_Z
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
	if _dispatch_timer <= 0.0 and _state_time < MAX_DWELL and aboard.size() + _boarding < CAPACITY:
		var car := term.take_car(route.id)
		if car != null:
			_dispatch_timer = DISPATCH_GAP
			_drive_on(car, term)
	var full := aboard.size() + _boarding >= CAPACITY
	var queue_empty := term.queued_for(route.id) == 0
	if _boarding == 0 and _state_time >= MIN_DWELL and (full or queue_empty or _state_time >= MAX_DWELL):
		state = State.SAILING
		traveled = 0.0
		_state_time = 0.0
		# The last crossing's wake has long faded by now, and it lies along the same
		# water, so start a fresh trail.
		wake.clear()


func _drive_on(car: Vehicle, term: Terminal) -> void:
	var slot := _free_slot()
	_slots[slot] = car
	_boarding += 1
	var local := _slot_local(slot)
	var entry_z := -END_Z if at_a else END_Z
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
	var remaining := route.length - traveled
	# Distance from the bow reaching the outer dolphins to being docked.
	var zone := OUTER_DOLPHIN_U + HULL_HALF_LENGTH - Layout.DOCK_U
	var rem := maxf(remaining, 0.0)
	var brake_v: float
	if rem > zone:
		brake_v = APPROACH_SPEED + sqrt(2.0 * DECEL * (rem - zone))
	else:
		brake_v = 0.3 + (APPROACH_SPEED - 0.3) * sqrt(rem / zone)
	# Picks up from wherever it is (it may have stopped for traffic mid-crossing).
	var target := minf(CRUISE, minf(brake_v, yield_speed()))
	var wait := _corridor_wait()
	hold = wait
	target = minf(target, sqrt(2.0 * YIELD_DECEL * maxf(wait - 0.5, 0.0)))
	speed = minf(target, speed + ACCEL * delta)
	_thrust = move_toward(_thrust, 1.0 if rem < zone and rem > 0.5 else 0.0, delta * 0.8)
	traveled = minf(traveled + speed * delta, route.length)
	_place(traveled if at_a else route.length - traveled)
	_bob_time += delta
	position.y = sin(_bob_time * 1.3) * 0.07
	if traveled >= route.length - 0.01:
		_dock_corridors()
		hold = INF
		speed = 0.0
		position.y = 0.0
		at_a = not at_a
		trips += 1
		_begin_unloading()


## The corridors this crossing passes through, in order, grouped into runs where
## one starts before the last ends, as [start, end, [[end, corridor], ...]]
## (distances along the crossing). A ferry takes a whole run at once, so under
## way it never sits holding one corridor while it waits for the next, and no
## ring of ferries can each be waiting on the one ahead.
func _corridor_runs() -> Array:
	if _runs.has(at_a):
		return _runs[at_a]
	var list := []
	for c: MarineTraffic.Corridor in sim.marine.corridors[route.id]:
		var span: Vector2 = c.span[route.id]
		var t0 := span.x if at_a else route.length - span.y
		var t1 := span.y if at_a else route.length - span.x
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
				if r[1] >= route.length - 1.0:
					at = r[0]
		else:
			at = run[0]
		traveled = maxf(at - HULL_HALF_LENGTH, 0.0)
		speed = 0.0
		_place(traveled if at_a else route.length - traveled)
		claim_corridors_at_start()
		return


## Docking: if another route runs so close past this slip that the docked ferry
## is in its way, keeps the run of corridors round it (and takes back any of it
## that it passed coming in and are free), so nothing comes by until it has left
## again. Frees the rest.
func _dock_corridors() -> void:
	for run in _corridor_runs():
		var keep: bool = run[1] >= route.length - 1.0 and _run_blocks_dock(run, not at_a)
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
	var s := minf(traveled + d, route.length)
	var p := route.curve.sample_baked(s if at_a else route.length - s)
	return Vector2(p.x, p.z)


func path_left() -> float:
	return route.length - traveled if state == State.SAILING else 0.0


## Positions the ferry at distance s along the route. +Z always faces A → B.
func _place(s: float) -> void:
	var length := route.length
	var p := route.curve.sample_baked(s)
	var d := route.curve.sample_baked(minf(s + 1.5, length)) - route.curve.sample_baked(maxf(s - 1.5, 0.0))
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
			speed / CRUISE * (1.0 - 0.6 * _thrust), state == State.SAILING and moving)


func wake_shape() -> Vector4:
	# Double-ended and blunt: both ends square off over the last few metres.
	return Vector4(3.0, 0.62, 3.0, 0.62)


func wake_hull() -> Vector4:
	return Vector4(HULL_HALF_BEAM, HULL_HALF_LENGTH * 2.0, 1.0, 1.0)


## Reverse thrust from the forward prop, 0..1 (braking for, or holding at, the dock).
func front_thrust() -> float:
	return _thrust


func load_count() -> int:
	return aboard.size() + _boarding


func kind_text() -> String:
	return "Ferry"


func status_text() -> String:
	if state == State.SAILING and speed < 0.2 and _waiting_for:
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
	return (route.length - traveled) / (CRUISE * 0.85)


func minutes_until_departure_from(term: Terminal) -> float:
	var crossing := route.length / (CRUISE * 0.85)
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
