class_name Ferry
extends Vessel
## A double-ended car ferry shuttling along one route. It never turns around: cars
## board at the end facing the pier, park on the deck (as children of the ferry, so
## they ride along) and drive off the opposite end at the destination. Its size
## (FerryClass) sets how many cars it takes and how fast it goes; whatever its
## length, it docks with its end at the ramp.

enum State { UNLOADING, LOADING, SAILING }

const ACCEL := 4.2
# Arrival: ferries ease off to APPROACH_SPEED along the run-in, then from the
# moment the bow passes the outer dolphins the forward prop reverse-thrusts them
# to a stop at the dock (the stern props backing off).
const DECEL := 1.5
# Braking to give way to other traffic.
const YIELD_DECEL := 2.7
const APPROACH_SPEED := 9.6
const OUTER_DOLPHIN_U := Layout.DOLPHIN_OUTER.x
const MIN_DWELL := 10.0
const MAX_DWELL := 24.0
const DISPATCH_GAP := 0.5
# A ferry about to leave holds in at the dock while a stretch of water it shares
# with another route, no further out than this, is taken, or while a ferry
# coming in to the same terminal, this close to it, has it still to pass.
const ARRIVAL_PRIORITY := 660.0
# Coming in, the slip's span starts down to the deck this far out (SlipRamp).
const RAMP_LOWER_AT := 40.0

var sim: Simulation
var fc: FerryClass
var route: MapData.Route
var ferry_name := ""
var term_a: Terminal
var term_b: Terminal
var state := State.LOADING
var at_a := true        # docked at A, or departed from A while sailing
var hull: MeshInstance3D
# The car deck nets at -Z and +Z (FerryClass.net_z).
var _nets: Array[MeshInstance3D] = []
var _net_wind := Vector2.ZERO
var traveled := 0.0      # how far the hull's centre has come, dock to dock
var trips := 0
var aboard: Array[Vehicle] = []
var _slots: Array[Vehicle] = []
var _boarding := 0
var _unload_queue: Array[Vehicle] = []
var _dispatch_timer := 0.0
var _last_sent: Vehicle  # the last car sent on or off, which the next one follows
var _state_time := 0.0
var _bob_time := 0.0
var _thrust := 0.0   # forward prop reverse thrust while braking, 0..1
var _last_pos := Vector3.ZERO
var _tracking := false
var _waiting_for: Ferry = null   # holding off a corridor this ferry has reserved
var _giving_way := false         # (holding in at the dock for _waiting_for to come in)
var _casting_off := false        # loaded, waiting for the apron to come up
var _ramp_synced := false
var _runs := {}                   # at_a -> _corridor_runs() for that direction
# Route curves run between where a 90 m hull's centre lies docked
# (Layout.DOCK_U); a shorter one docks this much further in at both ends, a
# longer one further out (negative).
var _inset := 0.0
# Her heading every metre along the route curve from YAW_PAD before its start,
# smoothed so she swings into and out of each turn rather than taking the
# curve's 6 m chords one kink at a time (see _build_yaws).
var _yaws := PackedFloat32Array()
const YAW_PAD := 120.0
const YAW_EASE := 16.0      # m, each of the two box filters (so a turn eases in over ~32 m)


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
	if SlipRamp.available():
		# In far enough for the apron's toe to land on her apron line, just outboard of the
		# yellow band across her deck at the net.
		_inset = Layout.DOCK_U - SlipRamp.dock_end(fc.half_length - fc.net_z - 0.35) - fc.half_length
	# A capsule round the hull: its corners just touch, its ends cover the bows.
	half_seg = fc.half_seg()
	hull_radius = fc.hull_radius
	claim_step = 12.0
	wake = WakeTrail.new(fc.half_length, 8.0 * fc.half_length / 15.0, 24.0, 46)
	term_a = sim.terminals[r.a]
	term_b = sim.terminals[r.b]
	term_a.ferry_for[r.id] = self
	term_b.ferry_for[r.id] = self
	_slots.resize(fc.lanes * fc.rows)
	hull = MeshInstance3D.new()
	hull.mesh = Models.ferry(fc)
	# Fixes which of its rooms are lit (lit_vc.gdshader); the origin would change every frame.
	hull.material_override = Models.hull_material()
	hull.set_instance_shader_parameter("room_seed", randf_range(1.0, 1000.0))
	add_child(hull)
	var thin_shadow := Models.ferry_thin_shadow(fc)
	if thin_shadow:
		var mi := MeshInstance3D.new()
		mi.mesh = thin_shadow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		hull.add_child(mi)
	for e: float in [-1.0, 1.0]:
		var net := MeshInstance3D.new()
		net.mesh = Models.ferry_net(fc)
		net.position.z = e * fc.net_z
		add_child(net)
		_nets.append(net)
	_build_yaws()
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
				var slot := _free_slot(car)
				if slot < 0:
					car.queue_free()
					break
				_take_slots(slot, car)
				_set_parked(car, _park_xform(slot, car))
				aboard.append(car)
			_place(_route_s(traveled))
		2:
			at_a = false
			_place(route.length + _inset)
			_begin_loading()


func here() -> Terminal:
	return term_a if at_a else term_b


## The span and apron at `term`'s slip for this route (null with the classic slip).
func _ramp(term: Terminal) -> SlipRamp:
	return term.ramps.get(route.id)


## `local` (a point on her deck at an end) in the world, up on the apron if that lies over it.
func _over_apron(local: Vector3) -> Vector3:
	var p := to_global(local)
	if _ramp(here()):
		p.y += SlipRamp.lift_at(here().to_local(p).z)
	return p


## Cars may cross between the slip and the deck.
func _ramp_down() -> bool:
	var ramp := _ramp(here())
	return ramp == null or ramp.is_down()


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
	var inner := clampf(end + (4.5 if s < 0.0 else -4.5), 0.0, length)
	var p := route.curve.sample_baked(end)
	var dir := p - route.curve.sample_baked(inner)
	dir.y = 0.0
	return p + dir.normalized() * absf(s - end)


func _slot_local(i: int) -> Vector3:
	var lane := i % fc.lanes
	var shift := fc.lane_shift[lane] if fc.lane_shift.size() > 0 else 0.0
	return Vector3(fc.cols[lane], Layout.DECK_Y, fc.row_z[floori(i / float(fc.lanes))] + shift)


## Where `car` parks with its slots starting at `slot` (the far end of its run of
## rows): the run's middle, its tractor ahead of that for a rig. Cars face +Z boarding
## at A, -Z at B.
func _park_local(slot: int, car: Vehicle) -> Vector3:
	var fwd := 1.0 if at_a else -1.0
	var p := _slot_local(slot)
	p.z -= fwd * (car.slots - 1) * 0.5 * FerryClass.ROW_SPACING
	p.z -= fwd * car.center_offset
	return p


## Where and which way `car` parks from `slot`: as _park_local, facing along the hull,
## or in an arcing lane laid along the arc between its two ends.
func _park_xform(slot: int, car: Vehicle) -> Transform3D:
	var fwd := 1.0 if at_a else -1.0
	var p := _park_local(slot, car)
	var yaw := 0.0 if at_a else PI
	if fc.arcs(p.x):
		var mid := p.z + fwd * car.center_offset
		var front := _arc_point(p.x, mid + fwd * car.length * 0.5)
		var back := _arc_point(p.x, mid - fwd * car.length * 0.5)
		var dir := (front - back).normalized()
		yaw = atan2(dir.x, dir.z)
		p = (front + back) * 0.5 - dir * car.center_offset
	return Transform3D(Basis(Vector3.UP, yaw), p)


## A point on the arcing lane at `x`, at z (the hull's frame).
func _arc_point(x: float, z: float) -> Vector3:
	return Vector3(fc.arc_x(x, z), Layout.DECK_Y, z)


## Waypoints (global) along the arcing lane at `x` from z0 (not included) to z1.
func _arc_path(x: float, z0: float, z1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(1, ceili(absf(z1 - z0) / 2.0))
	for i in range(1, n + 1):
		out.append(to_global(_arc_point(x, lerpf(z0, z1, float(i) / n))))
	return out


## The slots of `car`'s run from `slot`, going back toward the end it boards from.
func _run(slot: int, car: Vehicle) -> PackedInt32Array:
	var out := PackedInt32Array()
	var step := fc.lanes if at_a else -fc.lanes
	for k in car.slots:
		out.append(slot + k * step)
	return out


func _take_slots(slot: int, car: Vehicle) -> void:
	for i in _run(slot, car):
		_slots[i] = car


## Fills from the far end first so cars drive in past the ones already parked, and
## sends trucks and high-roofed vans to the lanes with the headroom (cars to the
## others) while there's room there. A long vehicle needs a run of free rows in one
## lane. -1 if there's no room for `car`.
func _free_slot(car: Vehicle) -> int:
	var fallback := -1
	for r in fc.rows - car.slots + 1:
		var row := r if at_a else fc.rows - 1 - r
		for c in fc.lanes:
			var idx := row * fc.lanes + c
			var free := true
			for i in _run(idx, car):
				if _slots[i] != null or fc.blocked.has(i):
					free = false
					break
			if free:
				if fc.lane_suits(c, car.is_tall):
					return idx
				if fallback < 0:
					fallback = idx
	return fallback


func _process(delta: float) -> void:
	_state_time += delta
	if not _ramp_synced:
		# (A ferry starting the game alongside already has the apron on her deck.)
		_ramp_synced = true
		if state != State.SAILING and _ramp(here()):
			_ramp(here()).snap_down()
	# Both nets up under way; alongside, the one at the docked end (-Z at A) is down
	# while cars drive off and on over it, once the apron is down on the deck.
	var docked := state != State.SAILING and _ramp_down()
	_nets[0].visible = not (docked and at_a)
	_nets[1].visible = not (docked and not at_a)
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
	if _ramp(here()):
		_ramp(here()).land()
	_state_time = 0.0
	_dispatch_timer = 0.0
	_last_sent = null
	_unload_queue = aboard.duplicate()
	var exit_sign := -1.0 if at_a else 1.0
	_unload_queue.sort_custom(func(a: Vehicle, b: Vehicle): return a.position.z * exit_sign > b.position.z * exit_sign)
	aboard.clear()
	_slots.fill(null)


func _tick_unloading(delta: float) -> void:
	if not _ramp_down():
		return
	_dispatch_timer -= delta
	if not _unload_queue.is_empty():
		if _dispatch_timer <= 0.0:
			var car: Vehicle = _unload_queue.pop_front()
			_dispatch_timer = _gap_after(car)
			_drive_off(car)
	elif _dispatch_timer < -2.0:
		_begin_loading()


## Seconds before the next car may follow `car`: long enough for it to pull its own
## length (and a gap) clear. Each car then follows the one before it.
func _gap_after(car: Vehicle) -> float:
	return maxf(DISPATCH_GAP, (car.length + Vehicle.FOLLOW_GAP) / car.speed)


func _send(car: Vehicle, path: PackedVector3Array, on_arrive: Callable) -> void:
	car.drive(path, on_arrive)
	car.leader = _last_sent
	_last_sent = car


func _drive_off(car: Vehicle) -> void:
	var exit_z := -fc.end_z if at_a else fc.end_z
	var path := PackedVector3Array()
	var x := car.position.x
	if fc.arcs(x):
		# Out of a wing: ahead to the car's nose, then round the hull's curve to the end.
		var lane: float = fc.cols[0]
		for c in fc.cols:
			if absf(c - x) < absf(lane - x):
				lane = c
		var ahead := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
		var nose := car.position + ahead * (car.center_offset + car.length * 0.5)
		path.append(to_global(_arc_point(lane, nose.z)))
		path.append_array(_arc_path(lane, nose.z, exit_z))
		x = fc.arc_x(lane, exit_z)
	elif absf(x) > fc.throat_x:
		# Out of a wing lane: turn in to the apron's opening past the fork's end.
		path.append(to_global(Vector3(x, Layout.DECK_Y, signf(exit_z) * fc.turn_z)))
		x = clampf(x, -fc.throat_x, fc.throat_x)
	path.append(_over_apron(Vector3(x, Layout.DECK_Y, exit_z)))
	car.reparent(sim.traffic)
	path.append_array(here().exit_path(route.id))
	_send(car, path, func(c: Vehicle): c.queue_free())


func _begin_loading() -> void:
	state = State.LOADING
	_state_time = 0.0
	_dispatch_timer = 0.0
	_last_sent = null
	speed = 0.0


func _tick_loading(delta: float) -> void:
	_dispatch_timer -= delta
	var term := here()
	var full := true
	if _dispatch_timer <= 0.0 and _state_time < MAX_DWELL and not _casting_off and _ramp_down():
		var car := term.take_car(route.id, func(c: Vehicle): return _free_slot(c) >= 0)
		if car != null:
			_dispatch_timer = _gap_after(car)
			_drive_on(car, term)
	# (full: nothing waiting would fit)
	for lane in term.lanes[route.id]:
		if lane.queue.size() > 0 and _free_slot(lane.queue[0]) >= 0:
			full = false
	var queue_empty := term.queued_for(route.id) == 0
	if _casting_off or _boarding == 0 and _state_time >= MIN_DWELL and (full or queue_empty or _state_time >= MAX_DWELL):
		# Apron up before she goes.
		_casting_off = true
		var ramp := _ramp(term)
		if ramp:
			ramp.lift()
			if not ramp.is_clear():
				return
		_casting_off = false
		state = State.SAILING
		traveled = 0.0
		_state_time = 0.0
		# The last crossing's wake has long faded by now, and it lies along the same
		# water, so start a fresh trail.
		wake.clear()


func _drive_on(car: Vehicle, term: Terminal) -> void:
	var slot := _free_slot(car)
	_take_slots(slot, car)
	_boarding += 1
	var park := _park_xform(slot, car)
	var local := park.origin
	var entry_z := -fc.end_z if at_a else fc.end_z
	var path := term.boarding_path(car, route.id)
	var lane := fc.cols[slot % fc.lanes]
	if fc.arcs(lane):
		# Into a wing: in over the end and round the hull's curve to the car's tail,
		# then on along its heading into place.
		var tail := local - park.basis.z * (car.length * 0.5 - car.center_offset)
		path.append(_over_apron(_arc_point(lane, entry_z)))
		path.append_array(_arc_path(lane, entry_z, tail.z))
	else:
		var mouth := clampf(local.x, -fc.throat_x, fc.throat_x)
		path.append(_over_apron(Vector3(mouth, Layout.DECK_Y, entry_z)))
		if mouth != local.x:
			# Into a wing lane: in through the apron's opening, then out round the fork's end.
			path.append(to_global(Vector3(local.x, Layout.DECK_Y, signf(entry_z) * fc.turn_z)))
	path.append(to_global(local))
	_send(car, path, _on_boarded.bind(park))
	sim.collect_fare(car)


func _on_boarded(car: Vehicle, park: Transform3D) -> void:
	car.reparent(self)
	_set_parked(car, park)
	aboard.append(car)
	_boarding -= 1


func _set_parked(car: Vehicle, park: Transform3D) -> void:
	car.position = park.origin
	car.rotation = Vector3(0.0, park.basis.get_euler().y, 0.0)
	car.straighten()


func _tick_sailing(delta: float) -> void:
	var remaining := run_length() - traveled
	# Distance from the bow reaching the outer dolphins to being docked.
	var zone := OUTER_DOLPHIN_U - Layout.PIER_END - 1.2
	var rem := maxf(remaining, 0.0)
	var brake_v: float
	if rem > zone:
		brake_v = APPROACH_SPEED + sqrt(2.0 * DECEL * (rem - zone))
	else:
		brake_v = 0.9 + (APPROACH_SPEED - 0.9) * sqrt(rem / zone)
	# Picks up from wherever it is (it may have stopped for traffic mid-crossing).
	var target := minf(fc.cruise, minf(brake_v, yield_speed()))
	var wait := _corridor_wait()
	hold = wait
	target = minf(target, sqrt(2.0 * YIELD_DECEL * maxf(wait - 1.5, 0.0)))
	speed = minf(target, speed + ACCEL * delta)
	_thrust = move_toward(_thrust, 1.0 if rem < zone and rem > 1.5 else 0.0, delta * 0.8)
	if rem < RAMP_LOWER_AT and _ramp(destination()):
		_ramp(destination()).lower()
	traveled = minf(traveled + speed * delta, run_length())
	_place(_route_s(traveled))
	_bob_time += delta
	position.y = sin(_bob_time * 1.3) * 0.21
	if traveled >= run_length() - 0.03:
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
		if not runs.is_empty() and e[0] <= runs[-1][1] + 3.0:
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
	if traveled < 1.5 and _blocked_at_dock():
		return 0.0
	for run in _corridor_runs():
		for e in run[2]:
			if traveled > e[0] and e[1].owner == self:
				e[1].owner = null
		if traveled > run[1]:
			continue
		if run[0] - traveled > self_look() + 30.0:
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
				if r[1] >= run_length() - 3.0:
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
		var keep: bool = run[1] >= run_length() - 3.0 and _run_blocks_dock(run, not at_a)
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
	global_transform = Transform3D(Basis(Vector3.UP, _yaw_at(s)), Vector3(p.x, 0.0, p.z))


## The curve is a polyline of ~6 m chords, so its own direction turns in kinks
## and changes rate abruptly where each arc meets a straight. Two passes of a box
## filter over the (unwrapped) chord headings give a turn rate that ramps up,
## holds steady round the arc and ramps down again, as under helm.
func _build_yaws() -> void:
	var n := int(ceil(route.length + 2.0 * YAW_PAD)) + 1
	var raw := PackedFloat32Array()
	raw.resize(n)
	var prev := 0.0
	for i in n:
		var s := i - YAW_PAD
		var d := route_point(s + 0.5) - route_point(s - 0.5)
		var y := atan2(d.x, d.z) if Vector2(d.x, d.z).length_squared() > 1e-8 else prev
		if i > 0:
			y = prev + angle_difference(prev, y)
		raw[i] = y
		prev = y
	_yaws = _box(_box(raw, int(YAW_EASE)), int(YAW_EASE))


static func _box(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var n := a.size()
	var h := w / 2
	var out := PackedFloat32Array()
	out.resize(n)
	var sum := 0.0
	for i in range(-h, h + 1):
		sum += a[clampi(i, 0, n - 1)]
	for i in n:
		out[i] = sum / (2 * h + 1)
		sum += a[clampi(i + h + 1, 0, n - 1)] - a[clampi(i - h, 0, n - 1)]
	return out


func _yaw_at(s: float) -> float:
	var f := clampf(s + YAW_PAD, 0.0, _yaws.size() - 1.001)
	var i := int(f)
	return lerpf(_yaws[i], _yaws[i + 1], f - i)


func _update_trail(delta: float) -> void:
	var moved := global_position - _last_pos
	moved.y = 0.0
	# The first frame has nothing to compare against.
	var moving := _tracking and moved.length_squared() > 1e-8
	_tracking = true
	_last_pos = global_position
	# The hull's own heading, not the way it moved this frame: that follows the
	# route curve's chords and kinks a few degrees at each, which would swing the
	# wake's bow and stern about. The end leading is the one it moved towards
	# (the ferry is double-ended).
	var fwd := global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if moved.dot(fwd) < 0.0:
		fwd = -fwd
	# Only once the ferry is actually under way: on the frame it casts off the
	# heading still points the way it arrived, which would put the first crumb at
	# the wrong end of the hull and fold the trail back on itself. The stern
	# props ease off while the forward prop brakes.
	wake.update(delta, global_position, fwd if moving else Vector3.ZERO, speed * delta,
			speed / fc.cruise * (1.0 - 0.6 * _thrust), state == State.SAILING and moving)
	_blow_nets(moved / delta if moving and delta > 0.0 else Vector3.ZERO, delta)


## The wind the nets feel (net.gdshader): the true wind less the ferry's own way, at
## real speeds, in the hull's frame. Eased, so a jerky frame doesn't snap them.
func _blow_nets(vel: Vector3, delta: float) -> void:
	var wf := sim.wind_from()
	var true_wind := -Vector3(wf.x, 0.0, wf.y) * sim.wind_speed / 3.6
	var local := global_basis.inverse() * (true_wind - vel / Units.SPEED_UP)
	_net_wind = _net_wind.lerp(Vector2(local.x, local.z), minf(1.0, delta * 1.5))
	for net in _nets:
		net.set_instance_shader_parameter("wind", _net_wind)


func wake_shape() -> Vector4:
	# Double-ended and blunt: both ends square off over the last few metres.
	return Vector4(9.0, 0.62, 9.0, 0.62)


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
	if state == State.SAILING and speed < 0.6 and _waiting_for:
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
