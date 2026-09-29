class_name Ferry
extends Node3D
## A double-ended car ferry shuttling along one route. It never turns around: cars
## board at the end facing the pier, park on the deck (as children of the ferry, so
## they ride along) and drive off the opposite end at the destination.

enum State { UNLOADING, LOADING, SAILING }

const CAPACITY := 36
const CRUISE := 9.0
const ACCEL := 1.4
const MIN_DWELL := 10.0
const MAX_DWELL := 24.0
const DISPATCH_GAP := 0.5
const ROWS := [10.0, 7.5, 5.0, 2.5, 0.0, -2.5, -5.0, -7.5, -10.0]
const COLS := [-2.25, -0.75, 0.75, 2.25]
const END_Z := 14.0

var sim: Simulation
var route: MapData.Route
var ferry_name := ""
var term_a: Terminal
var term_b: Terminal
var state := State.LOADING
var at_a := true        # docked at A, or departed from A while sailing
var traveled := 0.0
var speed := 0.0
var trips := 0
var aboard: Array[Vehicle] = []
var _slots: Array[Vehicle] = []
var _boarding := 0
var _unload_queue: Array[Vehicle] = []
var _dispatch_timer := 0.0
var _state_time := 0.0
var _bob_time := 0.0
var _wake_back: MeshInstance3D
var _wake_front: MeshInstance3D
var _wake_mat: StandardMaterial3D


func setup(s: Simulation, r: MapData.Route, nm: String) -> void:
	sim = s
	route = r
	ferry_name = nm
	name = nm
	term_a = sim.terminals[r.a]
	term_b = sim.terminals[r.b]
	term_a.ferry_for[r.id] = self
	term_b.ferry_for[r.id] = self
	_slots.resize(CAPACITY)
	var hull := MeshInstance3D.new()
	hull.mesh = Models.ferry()
	add_child(hull)
	_wake_mat = Models.unshaded_material()
	_wake_back = MeshInstance3D.new()
	_wake_back.mesh = Models.wake()
	_wake_back.material_override = _wake_mat
	_wake_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wake_back)
	_wake_front = _wake_back.duplicate() as MeshInstance3D
	_wake_front.rotation.y = PI
	add_child(_wake_front)
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
	var c := _wake_mat.albedo_color
	c.a = clampf(speed / CRUISE, 0.0, 1.0) * 0.8
	_wake_mat.albedo_color = c
	_wake_back.visible = state == State.SAILING and at_a
	_wake_front.visible = state == State.SAILING and not at_a


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
	speed = minf(CRUISE, minf(sqrt(2.0 * ACCEL * traveled) + 0.8, sqrt(2.0 * ACCEL * maxf(remaining, 0.0)) + 0.4))
	traveled = minf(traveled + speed * delta, route.length)
	_place(traveled if at_a else route.length - traveled)
	_bob_time += delta
	position.y = sin(_bob_time * 1.3) * 0.07
	if traveled >= route.length - 0.01:
		speed = 0.0
		position.y = 0.0
		at_a = not at_a
		trips += 1
		_begin_unloading()


## Positions the ferry at distance s along the route. +Z always faces A → B.
func _place(s: float) -> void:
	var length := route.length
	var p := route.curve.sample_baked(s)
	var d := route.curve.sample_baked(minf(s + 1.5, length)) - route.curve.sample_baked(maxf(s - 1.5, 0.0))
	d.y = 0.0
	if d.length_squared() < 1e-6:
		return
	global_transform = Transform3D(Basis.looking_at(-d.normalized(), Vector3.UP), Vector3(p.x, 0.0, p.z))


func load_count() -> int:
	return aboard.size() + _boarding


func status_text() -> String:
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
