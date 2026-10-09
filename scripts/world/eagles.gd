class_name Eagles
extends Node3D
## Bald eagles: Wildlife's "bald_eagle" visits, flown and drawn here as one multimesh.
##
## Each visit is a lone eagle or a mated pair holding a territory round its target
## island. They spend most of the day sitting on lookouts: the tops of the tall
## conifers along the shore (facing out over the water), now and then a terminal's
## dolphin or the top of its ramp lift, putting the gulls up when they come in.
## Between sits they soar in slow circles on flat wings, drop on a fish near the
## shore (talons thrown forward at the last moment) and carry it off to a tree to
## eat, or just move along the shore. At dusk they go to roost in the trees and stay
## there until morning. A pair mostly goes about together: when one takes off the
## other often follows, they circle in the same thermal, and they sit close, on
## neighbouring trees or the two ends of a lift. Loners now and then settle near
## another eagle too. When the visit is up they fly off out to sea (another takes
## its place: Wildlife keeps `resident` of them about).

enum Kind { TREE, DOLPHIN, LIFT }
enum State { PERCHED, FLY, SOAR, FOLLOW, LAND, STRIKE, AWAY }

const LAYER := 1 << (CloudLayer.VISUAL_LAYER - 1)
# Bigger than life, like the gulls (~3.2 m across), so they read at a distance.
const SCALE := 1.5
const MAX_EAGLES := 32
const FEET := 0.2               # model feet below its origin
const SPEED := 25.0
const SOAR_SPEED := 15.0
const ACCEL := 14.0
const MIN_AIRSPEED := 9.0
const LAND_START := 70.0
# How far round its island a territory reaches, beyond the shore.
const TERRITORY := 520.0
const FALLOFF := 260.0
const APPEAL := {Kind.TREE: 1.0, Kind.DOLPHIN: 0.3, Kind.LIFT: 0.22}
# A mate (or, sometimes, a loner) settling near another eagle: this close.
const PAIR_RANGE := 45.0
const FOLLOW_CHANCE := 0.65
const JOIN_CHANCE := 0.15
const SOAR_CHANCE := 0.35
const FISH_CHANCE := 0.3
# Gulls keep this far off an eagle sitting on a structure, and leave when it lands.
const GULL_CLEAR := 3.0
const CLICK_GRACE := 1500


## A lookout: a single seat (`at` is where the feet go) facing `look` (yaw), or into
## the wind if `look` is NAN.
class Perch:
	var at: Vector3
	var kind := Kind.TREE
	var look := NAN
	var bird: Bird = null

	func _init(p: Vector3, k: int, l := NAN) -> void:
		at = p
		kind = k
		look = l


class Bird:
	var visit: Wildlife.Visit
	var mate: Bird = null
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var bank := 0.0
	var pitch := 0.0
	var state := State.FLY
	var timer := 0.0
	var think := 0.0
	var perch: Perch = null     # where it sits, or is headed
	var size := 1.0
	var age := 0                # plumage: 0 adult, 1 sub-adult, 2 juvenile
	var facing := 0.0           # personal offset from the perch's lookout
	var leader: Bird = null     # flying with its mate
	var offset := Vector3.ZERO
	var orbit := Vector3.ZERO   # soaring: centre of the circle (y = height it climbs to)
	var orbit_r := 45.0
	var orbit_dir := 1.0
	var boost := 0.0            # seconds of hard flapping left after taking off
	var flap_phase := 0.0
	var flap_amp := 0.0
	var flap_burst := 0.0
	var fold := 1.0
	var talons := 0.0
	var mantle := 0.0           # perched: stretching its wings
	var fish := false           # carrying one to a tree
	var glide_from := Vector3.ZERO
	var glide_vel := Vector3.ZERO
	var glide_to := Vector3.ZERO
	var glide_end := Vector3.ZERO
	var glide_t := 0.0
	var glide_time := 1.0
	var shown_ms := -100000


var wildlife: Wildlife
var sim: Simulation
var day_cycle: DayCycle
var gulls: Seagulls
var rng := RandomNumberGenerator.new()
var _perches: Array[Perch] = []
var _birds: Array[Bird] = []
var _wind_yaw := 0.0
var _bound := 900.0
var _mm: MultiMesh
var _buf := PackedFloat32Array()


func setup(w: Wildlife, d: DayCycle, perches: Array[Perch], g: Seagulls) -> void:
	name = "Eagles"
	wildlife = w
	sim = w.sim
	day_cycle = d
	gulls = g
	rng.seed = sim.map.map_seed * 29 + 3
	_bound = sim.terrain.half_size - 60.0
	_perches = perches
	var a: float = CloudLayer.DIRS.find(sim.wind_dir) * TAU / 8.0
	_wind_yaw = atan2(sin(a), -cos(a))
	var mesh := Models.eagle()
	if mesh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/eagle.gdshader")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_EAGLES
	_mm.visible_instance_count = 0
	_buf.resize(MAX_EAGLES * 16)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.layers = LAYER
	add_child(mmi)
	w.visit_started.connect(_on_visit)
	for v in w.active_visits():
		_on_visit(v)


func _exit_tree() -> void:
	for b in _birds:
		b.mate = null
		b.leader = null
		b.perch = null
	for p in _perches:
		p.bird = null


func _on_visit(v: Wildlife.Visit) -> void:
	if v.species.id != "bald_eagle" or _mm == null:
		return
	var flock: Array[Bird] = []
	for m in v.members:
		var b := Bird.new()
		b.visit = v
		# Young birds are brown all over, for four or five years going patchy white.
		if m.role == Wildlife.Role.JUVENILE:
			b.age = 2 if rng.randf() < 0.55 else 1
		# Females are the bigger ones.
		b.size = rng.randf_range(1.0, 1.08) if flock.is_empty() else rng.randf_range(0.88, 0.95)
		b.facing = rng.randf_range(-0.6, 0.6)
		b.flap_phase = rng.randf() * TAU
		b.think = rng.randf_range(0.0, 5.0)
		flock.append(b)
		_birds.append(b)
	if flock.size() == 2:
		flock[0].mate = flock[1]
		flock[1].mate = flock[0]
	for b in flock:
		# Already about when the game starts (Wildlife's residents): sitting somewhere.
		if v.age > 0.0 and _claim(b, _home(v), TERRITORY + _island_r(v), b.mate.perch if b.mate else null):
			b.pos = _seat(b.perch)
			b.yaw = _look_yaw(b)
			b.state = State.PERCHED
			b.fold = 1.0
			b.timer = rng.randf_range(5.0, 200.0)
		else:
			# Flying in from offshore, high.
			b.pos = v.pos + Vector3(rng.randf_range(-20, 20), rng.randf_range(80.0, 110.0), rng.randf_range(-20, 20))
			var to := _home(v) - b.pos
			b.yaw = atan2(to.x, to.z)
			b.vel = Vector3(sin(b.yaw), 0.0, cos(b.yaw)) * SPEED
			b.fold = 0.0
			if b.mate and b != flock[0]:
				_follow(b, flock[0])
			else:
				_go_perch(b)


func _process(delta: float) -> void:
	if _mm == null:
		return
	if delta > 0.0:
		for i in range(_birds.size() - 1, -1, -1):
			var b := _birds[i]
			_tick(b, delta)
			if b.state == State.AWAY and not b.visit.active():
				_release(b)
				if b.mate:
					b.mate.mate = null
				_birds.remove_at(i)
		_place_visits()
	_render()


## Keeps each visit's centre (sightings, the minimap, the camera) on its eagles.
func _place_visits() -> void:
	var sums := {}
	for b in _birds:
		if b.state == State.AWAY:
			continue
		var s: Array = sums.get(b.visit, [Vector3.ZERO, 0])
		s[0] += b.pos
		s[1] += 1
		sums[b.visit] = s
	for v: Wildlife.Visit in sums:
		var c: Vector3 = sums[v][0] / float(sums[v][1])
		v.pos = Vector3(c.x, 0.0, c.z)
		if is_instance_valid(v.marker):
			v.marker.position = c


func _tick(b: Bird, dt: float) -> void:
	b.think -= dt
	b.talons = move_toward(b.talons, 0.0, dt * 1.5) if b.state != State.STRIKE else b.talons
	var leaving := b.visit.phase == Wildlife.Phase.DEPART or not b.visit.active()
	if leaving and b.state != State.AWAY and b.state != State.PERCHED and b.state != State.LAND:
		_head_away(b, dt)
		_wings(b, dt)
		return
	match b.state:
		State.PERCHED:
			_tick_perched(b, dt, leaving)
			return
		State.LAND:
			_tick_glide(b, dt)
			return
		State.STRIKE:
			_tick_glide(b, dt)
			_wings(b, dt)
			return
		State.AWAY:
			return
		State.FLY:
			_tick_fly(b, dt)
		State.SOAR:
			_tick_soar(b, dt)
		State.FOLLOW:
			_tick_follow(b, dt)
	_wings(b, dt)


# --- Perched ------------------------------------------------------------------------

func _tick_perched(b: Bird, dt: float, leaving: bool) -> void:
	var p := b.perch
	b.pos = _seat(p)
	b.yaw = lerp_angle(b.yaw, _look_yaw(b), 1.0 - exp(-dt * 0.8))
	if rng.randf() < dt * 0.01:
		b.facing = rng.randf_range(-0.8, 0.8)
	b.pitch = move_toward(b.pitch, 0.0, dt * 2.0)
	b.bank = move_toward(b.bank, 0.0, dt * 2.0)
	# Now and then it mantles: wings half open, a slow shake.
	if b.mantle <= 0.0 and rng.randf() < dt * 0.008:
		b.mantle = rng.randf_range(1.2, 2.5)
	if b.mantle > 0.0:
		b.mantle -= dt
		b.fold = move_toward(b.fold, 0.45, dt * 2.0)
		b.flap_amp = move_toward(b.flap_amp, 0.2, dt * 2.0)
		b.flap_phase += dt * TAU * 1.2
	else:
		b.fold = move_toward(b.fold, 1.0, dt * 2.0)
		b.flap_amp = move_toward(b.flap_amp, 0.0, dt * 2.0)
	var night := day_cycle.night
	if leaving:
		b.timer = minf(b.timer, rng.randf_range(0.5, 6.0))
	elif night > 0.35:
		# Roosting: off the docks and into the trees for the night, then nothing till morning.
		if p.kind != Kind.TREE:
			b.timer = minf(b.timer, rng.randf_range(1.0, 15.0))
		else:
			b.timer = maxf(b.timer, rng.randf_range(5.0, 60.0))
			return
	b.timer -= dt
	if b.timer > 0.0:
		return
	_take_off(b)
	if leaving:
		_head_away(b, dt)
		return
	# A mate taking off: the other often comes along.
	var m := b.mate
	if m and m.state == State.PERCHED and rng.randf() < FOLLOW_CHANCE and night < 0.35:
		m.timer = rng.randf_range(0.5, 4.0)
		m.leader = b
	if b.leader and b.leader.state != State.PERCHED and b.leader.state != State.AWAY:
		_follow(b, b.leader)
		return
	b.leader = null
	_decide(b)


func _take_off(b: Bird) -> void:
	_release(b)
	b.mantle = 0.0
	b.boost = rng.randf_range(1.5, 2.5)
	b.vel = Vector3(sin(b.yaw), 0.0, cos(b.yaw)) * 6.0 + Vector3.UP * 4.0


## Where it goes next: to roost, after a fish, up to soar, or along to another lookout.
func _decide(b: Bird) -> void:
	if day_cycle.night > 0.35:
		_go_perch(b)
		return
	var r := rng.randf()
	if r < FISH_CHANCE and _start_fishing(b):
		return
	if r < FISH_CHANCE + SOAR_CHANCE:
		_start_soar(b)
		return
	_go_perch(b)


func _go_perch(b: Bird) -> void:
	var v := b.visit
	var near: Perch = null
	if b.mate and b.mate.perch and rng.randf() < 0.6:
		near = b.mate.perch
	elif not b.mate and rng.randf() < JOIN_CHANCE:
		near = _other_eagle_perch(b)
	if _claim(b, b.pos, TERRITORY, near):
		b.state = State.FLY
		b.timer = 120.0
	else:
		_start_soar(b)


# --- Flying -------------------------------------------------------------------------

func _tick_fly(b: Bird, dt: float) -> void:
	var target := _seat(b.perch)
	var flat := Vector2(target.x - b.pos.x, target.z - b.pos.z).length()
	b.timer -= dt
	if flat < LAND_START or b.timer < 0.0:
		_begin_land(b)
		return
	# Cruise high, then let down on a long shallow slope to just above the lookout.
	var aim := target
	aim.y = target.y + 8.0 + (flat - LAND_START) * 0.35
	aim.y = minf(aim.y, maxf(b.pos.y, target.y + 30.0))
	_steer(b, (aim - b.pos).normalized() * SPEED, ACCEL, dt)


## Wide slow circles on flat wings, climbing in a thermal over the shore.
func _start_soar(b: Bird, centre: Variant = null) -> void:
	b.state = State.SOAR
	b.timer = rng.randf_range(30.0, 100.0)
	var c: Vector3 = centre if centre != null else b.pos
	if centre == null:
		for attempt in 6:
			var a := rng.randf() * TAU
			var p := b.pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(20.0, 160.0)
			if _in_territory(b.visit, p):
				c = p
				break
	b.orbit = Vector3(c.x, rng.randf_range(70.0, 170.0), c.z)
	b.orbit_r = rng.randf_range(35.0, 65.0)
	b.orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0


func _tick_soar(b: Bird, dt: float) -> void:
	b.timer -= dt
	if b.timer <= 0.0:
		_decide_after_soar(b)
		return
	var rel := Vector2(b.pos.x - b.orbit.x, b.pos.z - b.orbit.z)
	var a := rel.angle() + b.orbit_dir * 0.45
	var aim := Vector3(b.orbit.x + cos(a) * b.orbit_r, b.orbit.y, b.orbit.z + sin(a) * b.orbit_r)
	var want := aim - b.pos
	want.y = clampf(want.y, -2.0, 2.5)
	var flat := Vector3(want.x, 0.0, want.z).normalized() * SOAR_SPEED
	_steer(b, Vector3(flat.x, want.y, flat.z), ACCEL * 0.6, dt)


func _decide_after_soar(b: Bird) -> void:
	if day_cycle.night < 0.35 and rng.randf() < 0.3 and _start_fishing(b):
		return
	_go_perch(b)


## Flying along with its mate: a few lengths off its wing, or circling opposite it
## in the same thermal.
func _follow(b: Bird, leader: Bird) -> void:
	_release(b)
	b.leader = leader
	b.state = State.FOLLOW
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	b.offset = Vector3(side * rng.randf_range(8.0, 18.0), rng.randf_range(-4.0, 6.0), -rng.randf_range(6.0, 20.0))
	b.think = rng.randf_range(10.0, 25.0)


func _tick_follow(b: Bird, dt: float) -> void:
	var l := b.leader
	if l == null or l.state == State.AWAY:
		b.leader = null
		_go_perch(b)
		return
	if l.state == State.PERCHED or l.state == State.LAND:
		# It's coming down: a lookout close by.
		b.leader = null
		if _claim(b, l.perch.at, TERRITORY, l.perch):
			b.state = State.FLY
			b.timer = 120.0
		else:
			_start_soar(b)
		return
	if b.think <= 0.0:
		b.think = rng.randf_range(10.0, 25.0)
		if rng.randf() < 0.12:
			# Off on its own for a while.
			b.leader = null
			_decide(b)
			return
	if l.state == State.SOAR:
		var rel := Vector2(l.pos.x - l.orbit.x, l.pos.z - l.orbit.z)
		var a := rel.angle() + PI * 0.7 * l.orbit_dir
		var slot := Vector3(l.orbit.x + cos(a) * l.orbit_r, l.pos.y + b.offset.y, l.orbit.z + sin(a) * l.orbit_r)
		var along := Vector3(-sin(a), 0.0, cos(a)) * l.orbit_dir * SOAR_SPEED
		_steer(b, (along + (slot - b.pos) * 0.4).limit_length(SPEED), ACCEL, dt)
		return
	var slot := l.pos + Basis(Vector3.UP, l.yaw) * b.offset
	var want := l.vel + (slot - b.pos) * 0.6
	_steer(b, want.limit_length(SPEED * 1.3), ACCEL * 1.3, dt)


## Picks a fish near the surface off the shore and goes down for it.
func _start_fishing(b: Bird) -> bool:
	for attempt in 16:
		var a := rng.randf() * TAU
		var p := b.pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(60.0, 420.0)
		var h := sim.terrain.height_at(p.x, p.z)
		if h > -2.0 or h < -14.0 or not _in_territory(b.visit, p) or _boat_near(p, 70.0):
			continue
		p.y = 0.25
		# Lined up from upwind of it, gliding in low.
		var to := p - b.pos
		to.y = 0.0
		var dir := to.normalized()
		b.state = State.STRIKE
		b.glide_from = b.pos
		b.glide_vel = b.vel if b.vel.length() > 5.0 else dir * SPEED
		b.glide_to = p
		b.glide_end = dir * 14.0 + Vector3.DOWN * 3.0
		b.glide_t = 0.0
		b.glide_time = clampf(b.pos.distance_to(p) / 18.0, 3.0, 14.0)
		return true
	return false


## After the grab: labouring up with it and off to a tree to eat.
func _after_strike(b: Bird) -> void:
	b.fish = true
	b.boost = rng.randf_range(2.5, 4.0)
	b.vel = Vector3(b.vel.x, 0.0, b.vel.z).normalized() * 10.0 + Vector3.UP * 4.0
	if gulls:
		gulls.flush(b.pos, 30.0)
	if _claim(b, b.pos, TERRITORY, null, true):
		b.state = State.FLY
		b.timer = 120.0
	else:
		_start_soar(b)


func _head_away(b: Bird, dt: float) -> void:
	_release(b)
	if b.state != State.FLY or b.perch != null:
		b.state = State.FLY
	var out := b.visit.exit - b.pos
	out.y = 0.0
	var dir := out.normalized() if out.length() > 30.0 else Vector3(b.pos.x, 0.0, b.pos.z).normalized()
	var want := dir * SPEED
	want.y = clampf(120.0 - b.pos.y, -3.0, 3.0)
	b.vel = b.vel.move_toward(want, ACCEL * dt)
	b.pos += b.vel * dt
	_orient(b, dt)
	if absf(b.pos.x) > _bound + 300.0 or absf(b.pos.z) > _bound + 300.0 \
			or (out.length() < 30.0 and not b.visit.active()):
		b.state = State.AWAY


# --- Landing / striking -------------------------------------------------------------

func _begin_land(b: Bird) -> void:
	b.state = State.LAND
	b.glide_from = b.pos
	b.glide_vel = b.vel
	b.glide_to = _seat(b.perch)
	var flat := Vector3(b.vel.x, 0.0, b.vel.z).normalized()
	b.glide_end = flat * 2.0 + Vector3.UP * 0.5
	b.glide_t = 0.0
	b.glide_time = clampf(b.pos.distance_to(b.glide_to) / maxf(b.vel.length(), 12.0) * 1.4, 2.0, 6.0)
	if gulls and b.perch.kind != Kind.TREE:
		gulls.flush(b.perch.at, GULL_CLEAR + 2.0)


## A Hermite glide from where it broke off to the lookout (flaring with big
## back-strokes at the end), or down to the water with its feet thrown forward.
func _tick_glide(b: Bird, dt: float) -> void:
	if b.state == State.LAND:
		b.glide_to = _seat(b.perch)
	b.glide_t += dt
	var t := b.glide_time
	var s := minf(b.glide_t / t, 1.0)
	var p0 := b.glide_from
	var p1 := b.glide_to
	var m0 := b.glide_vel * t
	var m1 := b.glide_end * t
	var s2 := s * s
	var s3 := s2 * s
	b.pos = p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)
	b.vel = (p0 * (6.0 * s2 - 6.0 * s) + m0 * (3.0 * s2 - 4.0 * s + 1.0) + p1 * (-6.0 * s2 + 6.0 * s) + m1 * (3.0 * s2 - 2.0 * s)) / t
	_orient(b, dt)
	if b.state == State.STRIKE:
		b.talons = smoothstep(0.7, 0.92, s)
		b.pitch = lerpf(b.pitch, 0.5 * smoothstep(0.8, 1.0, s), 1.0 - exp(-dt * 6.0))
		if s >= 1.0:
			_after_strike(b)
		return
	var flare := smoothstep(0.6, 0.92, s)
	b.pitch = lerpf(b.pitch, 0.8 * flare, 1.0 - exp(-dt * 6.0))
	b.flap_amp = move_toward(b.flap_amp, 0.9 * flare, dt * 3.0)
	b.flap_phase += dt * TAU * 2.6
	b.talons = 0.6 * smoothstep(0.75, 0.95, s) * (1.0 - smoothstep(0.97, 1.0, s))
	b.fold = smoothstep(0.92, 1.0, s)
	if s >= 1.0:
		b.state = State.PERCHED
		b.vel = Vector3.ZERO
		b.timer = _perch_time(b)
		b.fish = false
		if gulls and b.perch.kind != Kind.TREE:
			gulls.flush(b.perch.at, GULL_CLEAR + 2.0)


func _perch_time(b: Bird) -> float:
	var t := rng.randf_range(40.0, 260.0)
	if b.fish:
		t += rng.randf_range(120.0, 300.0)   # eating it
	if b.perch.kind != Kind.TREE:
		t *= 0.6
	return t


# --- Flight helpers -----------------------------------------------------------------

func _steer(b: Bird, want: Vector3, accel: float, dt: float) -> void:
	if absf(b.pos.x) > _bound or absf(b.pos.z) > _bound:
		want += Vector3(-signf(b.pos.x) if absf(b.pos.x) > _bound else 0.0, 0.0,
			-signf(b.pos.z) if absf(b.pos.z) > _bound else 0.0) * SPEED
	b.vel = b.vel.move_toward(want, accel * dt)
	var h := Vector2(b.vel.x, b.vel.z)
	if b.boost <= 0.0 and h.length() < MIN_AIRSPEED:
		var fwd := Vector2(sin(b.yaw), cos(b.yaw))
		h = fwd * MIN_AIRSPEED if h.length() < 0.3 else h.normalized() * MIN_AIRSPEED
		b.vel.x = h.x
		b.vel.z = h.y
	b.pos += b.vel * dt
	# Well clear of the treetops over land; down to a few metres over the water.
	var ground := sim.terrain.height_at(b.pos.x, b.pos.z)
	var floor_y := ground + 35.0 if ground > 0.0 else 8.0
	if b.pos.y < floor_y:
		b.vel.y = maxf(b.vel.y, (floor_y - b.pos.y) * 1.2)
	_orient(b, dt)


func _orient(b: Bird, dt: float) -> void:
	var h := Vector2(b.vel.x, b.vel.z)
	if h.length_squared() > 0.36:
		var ny := atan2(b.vel.x, b.vel.z)
		var rate := angle_difference(b.yaw, ny) / maxf(dt, 1e-4)
		b.yaw = ny
		b.bank = lerpf(b.bank, clampf(-rate * 0.6, -0.7, 0.7), 1.0 - exp(-dt * 3.0))
	var climb := clampf(atan2(b.vel.y, h.length()) * 0.5, -0.45, 0.45)
	b.pitch = lerpf(b.pitch, climb, 1.0 - exp(-dt * 3.0))


## Long glides on flat wings; slow, deep strokes taking off, climbing, or carrying.
func _wings(b: Bird, dt: float) -> void:
	b.fold = move_toward(b.fold, 0.0, dt * 2.0)
	b.boost -= dt
	b.flap_burst -= dt
	var soaring := b.state == State.SOAR or (b.state == State.FOLLOW and b.leader and b.leader.state == State.SOAR)
	if b.flap_burst <= 0.0 and not soaring and rng.randf() < dt * (0.5 if b.fish else 0.18):
		b.flap_burst = rng.randf_range(1.5, 3.5)
	var amp := 0.0
	var freq := 2.2
	if b.boost > 0.0:
		amp = 0.85
		freq = 2.8
	elif b.state == State.STRIKE:
		amp = 0.0
	elif b.vel.y > 2.0 and not soaring or b.flap_burst > 0.0:
		amp = 0.6
	b.flap_amp = move_toward(b.flap_amp, amp, dt * 2.0)
	if b.flap_amp > 0.01:
		b.flap_phase = fmod(b.flap_phase + dt * TAU * freq, TAU)
	else:
		b.flap_phase = 0.0


# --- Lookouts -----------------------------------------------------------------------

## Claims a free lookout in its territory, weighted by kind and nearness to `from`
## (or, given `near`, the closest free one to that: beside its mate). At night,
## or with a fish to eat, only trees will do.
func _claim(b: Bird, from: Vector3, radius: float, near: Perch = null, tree_only := false) -> bool:
	var v := b.visit
	var home := _home(v)
	var reach := _island_r(v) + TERRITORY
	tree_only = tree_only or day_cycle.night > 0.35
	if near:
		var best: Perch = null
		var best_d := PAIR_RANGE
		for p in _perches:
			if p.bird != null or p == near or (tree_only and p.kind != Kind.TREE):
				continue
			var d := p.at.distance_to(near.at)
			if d < best_d:
				best_d = d
				best = p
		if best:
			_take(b, best)
			return true
	var picks: Array[Perch] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for p in _perches:
		if p.bird != null or (tree_only and p.kind != Kind.TREE):
			continue
		if Vector2(p.at.x - home.x, p.at.z - home.z).length() > reach:
			continue
		var d := Vector2(p.at.x - from.x, p.at.z - from.z).length()
		if d > radius * 1.5 or d < 15.0:
			continue
		var w: float = APPEAL[p.kind] * exp(-d / FALLOFF)
		picks.append(p)
		weights.append(w)
		total += w
	if picks.is_empty():
		return false
	var r := rng.randf() * total
	for i in picks.size():
		r -= weights[i]
		if r <= 0.0:
			_take(b, picks[i])
			return true
	_take(b, picks.back())
	return true


func _take(b: Bird, p: Perch) -> void:
	_release(b)
	p.bird = b
	b.perch = p
	if gulls and p.kind != Kind.TREE:
		gulls.eagle_seats.append(p.at)


func _release(b: Bird) -> void:
	var p := b.perch
	if p == null:
		return
	if p.bird == b:
		p.bird = null
	b.perch = null
	if gulls and p.kind != Kind.TREE:
		gulls.eagle_seats.erase(p.at)


## Some other eagle's lookout nearby, for a loner to sit by.
func _other_eagle_perch(b: Bird) -> Perch:
	for o in _birds:
		if o != b and o.state == State.PERCHED and o.perch and o.pos.distance_to(b.pos) < TERRITORY:
			return o.perch
	return null


func _seat(p: Perch) -> Vector3:
	return p.at + Vector3.UP * FEET * SCALE


func _look_yaw(b: Bird) -> float:
	var base := _wind_yaw if is_nan(b.perch.look) else b.perch.look
	return base + b.facing


func _home(v: Wildlife.Visit) -> Vector3:
	return Vector3(v.target.center.x, 0.0, v.target.center.y)


func _island_r(v: Wildlife.Visit) -> float:
	return v.target.radius


func _in_territory(v: Wildlife.Visit, p: Vector3) -> bool:
	var h := _home(v)
	return Vector2(p.x - h.x, p.z - h.z).length() < _island_r(v) + TERRITORY \
		and absf(p.x) < _bound and absf(p.z) < _bound


func _boat_near(p: Vector3, r: float) -> bool:
	for vs in sim.marine.vessels:
		if vs.global_position.distance_squared_to(p) < r * r:
			return true
	for f in sim.ferries:
		if f.global_position.distance_squared_to(p) < (r + 40.0) * (r + 40.0):
			return true
	return false


# --- Picking and drawing -------------------------------------------------------------

## The visit whose eagle is nearest `screen` (and showing), if any.
func pick(screen: Vector2, cam: Camera3D) -> Wildlife.Visit:
	var now := Time.get_ticks_msec()
	var best: Wildlife.Visit = null
	var best_d := INF
	for b in _birds:
		if not b.visit.active() or b.state == State.AWAY or now - b.shown_ms > CLICK_GRACE:
			continue
		if cam.is_position_behind(b.pos):
			continue
		var reach := maxf(26.0, 2.0 * SCALE * 900.0 / cam.global_position.distance_to(b.pos))
		var d := cam.unproject_position(b.pos).distance_to(screen)
		if d < reach and d < best_d:
			best_d = d
			best = b.visit
	return best


func _render() -> void:
	var k := 0
	var now := Time.get_ticks_msec()
	for b in _birds:
		if k >= MAX_EAGLES or b.state == State.AWAY:
			continue
		b.shown_ms = now
		var basis := (Basis(Vector3.UP, b.yaw) * Basis(Vector3.RIGHT, -b.pitch) * Basis(Vector3.BACK, b.bank)).scaled(Vector3.ONE * SCALE * b.size)
		var o := k * 16
		_buf[o] = basis.x.x
		_buf[o + 1] = basis.y.x
		_buf[o + 2] = basis.z.x
		_buf[o + 3] = b.pos.x
		_buf[o + 4] = basis.x.y
		_buf[o + 5] = basis.y.y
		_buf[o + 6] = basis.z.y
		_buf[o + 7] = b.pos.y
		_buf[o + 8] = basis.x.z
		_buf[o + 9] = basis.y.z
		_buf[o + 10] = basis.z.z
		_buf[o + 11] = b.pos.z
		_buf[o + 12] = b.flap_phase
		_buf[o + 13] = b.flap_amp
		_buf[o + 14] = b.fold
		_buf[o + 15] = float(b.age) + b.talons * 0.9
		k += 1
	_mm.buffer = _buf
	_mm.visible_instance_count = k
