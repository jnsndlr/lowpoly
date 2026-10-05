class_name Seagulls
extends Node3D
## A pool of simulated seagulls, drawn as one multimesh, that perch on lamp posts,
## ramp lifts, dolphins, terminal roofs, lighthouses, docked ferries and the water.
##
## Each gull sits for a while (facing into the wind, much longer at night), then
## either flies to another free perch nearby, wheels about for a bit, or tails a
## sailing ferry. A fishing boat out at work is better than any of that: gulls
## that notice one go out to it, follow it over its wake (all the more when it is
## hauling, or steaming home with the catch) and drop onto the water astern, then
## go after it again; once it is tied up they lose interest. Taking off, a gull may
## call up to a few perched neighbours to come along; they fly in loose formation
## off the leader and, when it comes down, look for spots near it. Followers drift
## off on their own now and then, and loners sometimes tag onto a passing group.
## Gulls on a ferry leave when it sails, and ones floating on the water get out of
## a vessel's way.

enum Kind { LAMP, LIFT, DOLPHIN, ROOF, LIGHTHOUSE, FERRY, BOAT, WATER }
enum State { PERCHED, FLY, ROAM, FOLLOW, LAND }

# Kept off the minimap, like the clouds.
const LAYER := 1 << (CloudLayer.VISUAL_LAYER - 1)
# Bigger than life (~1.4 m across unscaled) so they read at a distance.
const SCALE := 1.5
const PER_TERMINAL := 10
const PER_QUAY := 10
const MAX_GULLS := 110
# Weight of each kind of perch when picking where to go; distance falls off on top.
const APPEAL := {Kind.LAMP: 0.5, Kind.LIFT: 1.4, Kind.DOLPHIN: 1.2, Kind.ROOF: 1.0,
	Kind.LIGHTHOUSE: 1.0, Kind.FERRY: 2.0, Kind.BOAT: 1.6}
const WATER_APPEAL := 0.35
# Gulls like company: each one already on a perch (up to 4) adds this much appeal.
const COMPANY := 0.8
# Chance a landing gull sets down next to one already there rather than anywhere.
const HUDDLE := 0.6
const PERCH_RANGE := 240.0
const PERCH_FALLOFF := 70.0
# Ferry-local perches (Models.ferry) as (from, to, spread): wheelhouse roofs, the
# upper cabin roof either side of the funnel, the passenger-deck edges, the funnel
# top and the lifeboats.
const FERRY_PERCHES := [
	[Vector3(-1.7, 7.4, 7.4), Vector3(1.7, 7.4, 7.4), 0.8], [Vector3(-1.7, 7.4, -7.4), Vector3(1.7, 7.4, -7.4), 0.8],
	[Vector3(0, 6.3, 1.8), Vector3(0, 6.3, 5.6), 2.8], [Vector3(0, 6.3, -1.8), Vector3(0, 6.3, -5.6), 2.8],
	[Vector3(3.95, 5.1, -9.6), Vector3(3.95, 5.1, 9.6), 0.0], [Vector3(-3.95, 5.1, -9.6), Vector3(-3.95, 5.1, 9.6), 0.0],
	[Vector3(0, 9.05, -1.1), Vector3(0, 9.05, 1.1), 0.0],
	[Vector3(3.5, 6.75, 2.3), Vector3(3.5, 6.75, 4.1), 0.0], [Vector3(-3.5, 6.75, -2.3), Vector3(-3.5, 6.75, -4.1), 0.0],
]
# Trawler-local perches (Models.trawler), used while it lies alongside: the
# wheelhouse roof, the gantry's crossbar, the bulwark rails and the foredeck.
const TRAWLER_PERCHES := [
	[Vector3(0, 5.52, 2.0), Vector3(0, 5.52, 4.6), 1.6],
	[Vector3(-2.6, 6.78, -9.3), Vector3(2.6, 6.78, -9.3), 0.0],
	[Vector3(3.12, 2.48, -8.5), Vector3(3.12, 2.48, 2.5), 0.0], [Vector3(-3.12, 2.48, -8.5), Vector3(-3.12, 2.48, 2.5), 0.0],
	[Vector3(0, 2.62, 5.2), Vector3(0, 2.62, 7.6), 1.2],
]
# A fishing boat at work draws gulls from this far (further when it is hauling or
# steaming home with the catch: there's fish to be had), and they follow it this
# much more readily than anything else.
const FISH_ATTENTION := 220.0
const FISH_ATTENTION_FED := 340.0
const FISH_CHANCE := 0.8
const FISH_RESTLESS := 0.12     # chance a second a perched gull within reach gets up for it
# Spread of a raft of gulls on the water.
const RAFT := 6.0
# Height of the body's origin above the perch point (water: sitting in it).
const REST := 0.1 * SCALE
const FLOAT := 0.03
const SPEED := 10.0
const ACCEL := 7.0
# Horizontal distance from its perch at which a gull starts its landing glide.
const LAND_START := 15.0
const GROUP_CHANCE := 0.4
const RECRUIT_RADIUS := 26.0
const MAX_RECRUITS := 5
const ROAM_CHANCE := 0.2
const ESCORT_CHANCE := 0.25
const JOIN_RADIUS := 35.0


## Somewhere gulls can sit: a point, a line from `a` to `b` (a beam, a rail), a
## strip `spread` either side of it (a roof), or a disc of radius `spread` around
## `a` (a raft on the water). Each gull takes its own seat on it.
class Perch:
	var a: Vector3          # world, or local to `ferry` / `boat`
	var b: Vector3
	var spread := 0.0
	var ferry: Ferry = null
	var boat: FishingBoat = null
	var kind := Kind.LAMP
	var gulls: Array[Gull] = []
	var capacity := 1

	func _init(pa: Vector3, pb: Vector3, s: float, k: int, f: Ferry = null) -> void:
		a = pa
		b = pb
		spread = s
		kind = k
		ferry = f
		var length := (b - a).length()
		capacity = maxi(1, floori((length + 1.0) * (2.0 * spread + 1.0) / 2.2) if spread > 0.0 else floori(length / 1.1) + 1)

	func to_world(p: Vector3) -> Vector3:
		if ferry:
			return ferry.global_transform * p
		return boat.global_transform * p if boat else p

	func center() -> Vector3:
		return to_world((a + b) * 0.5)

	func usable() -> bool:
		if boat:
			return boat.state == FishingBoat.State.ALONGSIDE
		return ferry == null or ferry.state != Ferry.State.SAILING

	func _across() -> Vector3:
		var d := b - a
		d.y = 0.0
		return d.cross(Vector3.UP).normalized() if d.length_squared() > 1e-4 else Vector3.ZERO

	func sample(rng: RandomNumberGenerator) -> Vector3:
		var p := a.lerp(b, rng.randf())
		if spread > 0.0:
			var across := _across()
			if across == Vector3.ZERO:
				var ang := rng.randf() * TAU
				p += Vector3(cos(ang), 0.0, sin(ang)) * spread * sqrt(rng.randf())
			else:
				p += across * rng.randf_range(-spread, spread)
		return p

	## The nearest point to `p` on this perch.
	func project(p: Vector3) -> Vector3:
		var d := b - a
		var t := clampf((p - a).dot(d) / d.length_squared(), 0.0, 1.0) if d.length_squared() > 1e-4 else 0.0
		var base := a.lerp(b, t)
		if spread <= 0.0:
			return base
		var off := p - base
		off.y = 0.0
		var across := _across()
		if across == Vector3.ZERO:
			return base + off.limit_length(spread)
		return base + across * clampf(off.dot(across), -spread, spread)


class Gull:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var bank := 0.0
	var pitch := 0.0
	var state := State.PERCHED
	var timer := 0.0            # perched: until it leaves; roam: until it heads somewhere
	var think := 0.0            # until the next look around for company / break-away roll
	var perch: Perch = null     # where it sits, or is headed
	var seat := Vector3.ZERO    # its spot on the perch (in the perch's frame)
	var size := 1.0
	var leader: Gull = null     # flying with (or, while perched, about to follow)
	var offset := Vector3.ZERO  # formation slot in the leader's frame / escort offset
	var alt := 20.0             # cruising height for this leg
	var orbit := Vector3.ZERO   # roam: centre of the circle (y = height)
	var orbit_r := 20.0
	var orbit_dir := 1.0
	var escort: Vessel = null   # roam: the ferry or fishing boat it's tailing
	var boost := 0.0            # seconds of hard flapping left after take-off
	var flap_phase := 0.0
	var flap_amp := 0.0
	var flap_burst := 0.0       # > 0 while flapping between glides
	var fold := 1.0
	var stretch := 0.0
	var facing := 0.0           # personal offset from facing into the wind
	var land_from := Vector3.ZERO
	var land_vel := Vector3.ZERO
	var land_t := 0.0
	var land_time := 1.0
	var bob := 0.0


var sim: Simulation
var day_cycle: DayCycle
var rng := RandomNumberGenerator.new()
var _perches: Array[Perch] = []
var _gulls: Array[Gull] = []
var _wind_yaw := 0.0
var _bound := 300.0
var _mm: MultiMesh
var _buf := PackedFloat32Array()


func setup(s: Simulation, d: DayCycle, perches: Array[Perch]) -> void:
	name = "Seagulls"
	sim = s
	day_cycle = d
	rng.seed = sim.map.map_seed * 17 + 5
	_bound = sim.terrain.half_size - 40.0
	# Perched gulls face into the wind (named for where it blows from; -Z is north).
	var a: float = CloudLayer.DIRS.find(sim.wind_dir) * TAU / 8.0
	_wind_yaw = atan2(sin(a), -cos(a))
	_perches.append_array(perches)
	for f in sim.ferries:
		for fp: Array in FERRY_PERCHES:
			_perches.append(Perch.new(fp[0], fp[1], fp[2], Kind.FERRY, f))
	for b in sim.marine.fishing_boats:
		for bp: Array in TRAWLER_PERCHES:
			var p := Perch.new(bp[0], bp[1], bp[2], Kind.BOAT)
			p.boat = b
			_perches.append(p)
	_build_pool()


func _build_pool() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/seagull.gdshader")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = Models.seagull()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.layers = LAYER
	add_child(mmi)

	var homes: Array[Vector3] = []
	for t: Terminal in sim.terminals.values():
		for k in PER_TERMINAL:
			homes.append(t.global_position)
	for q in sim.map.quays:
		for k in PER_QUAY:
			homes.append(q.at(Layout.QUAY_FACE_U, 0.0))
	if homes.is_empty():
		homes.append(Vector3.ZERO)
	var count := mini(homes.size() + 8, MAX_GULLS)
	for i in count:
		var g := Gull.new()
		g.facing = _pick_facing()
		g.size = rng.randf_range(0.88, 1.08)
		g.flap_phase = rng.randf() * TAU
		_gulls.append(g)
		var home: Vector3 = homes[i % homes.size()]
		if rng.randf() < 0.75 and _claim(g, home, PERCH_RANGE):
			g.pos = _seat_world(g)
			g.yaw = _wind_yaw + g.facing
			g.timer = rng.randf_range(1.0, 40.0)
		else:
			g.pos = home + Vector3(rng.randf_range(-40, 40), rng.randf_range(10, 30), rng.randf_range(-40, 40))
			g.yaw = rng.randf() * TAU
			g.vel = Vector3(sin(g.yaw), 0.0, cos(g.yaw)) * SPEED
			g.fold = 0.0
			_start_roam(g)
	_mm.instance_count = _gulls.size()
	_buf.resize(_gulls.size() * 16)


## Gulls and perches point at each other; let them go with the scene.
func _exit_tree() -> void:
	for g in _gulls:
		g.perch = null
		g.leader = null
	for p in _perches:
		p.gulls.clear()


func _process(delta: float) -> void:
	if delta > 0.0:
		for g in _gulls:
			_tick(g, delta)
	_render()


func _tick(g: Gull, dt: float) -> void:
	g.think -= dt
	match g.state:
		State.PERCHED:
			_tick_perched(g, dt)
			return
		State.LAND:
			_tick_land(g, dt)
			return
		State.FLY:
			_tick_fly(g, dt)
		State.ROAM:
			_tick_roam(g, dt)
		State.FOLLOW:
			_tick_follow(g, dt)
	_wings_in_flight(g, dt)


# --- Perched ------------------------------------------------------------------------

func _tick_perched(g: Gull, dt: float) -> void:
	var p := g.perch
	g.pos = _seat_world(g)
	if p.kind == Kind.WATER:
		g.bob += dt
		g.pos.y += sin(g.bob * 1.6) * 0.06
		g.yaw += sin(g.bob * 0.3) * 0.1 * dt
		# Paddle out of the way of a ferry, or a fishing boat coming back over them.
		if g.timer > 1.0 and (_ferry_near(g.pos, 34.0) != null or _boat_bearing_down(g.pos)):
			g.timer = rng.randf_range(0.0, 0.8)
	else:
		g.yaw = lerp_angle(g.yaw, _wind_yaw + g.facing, 1.0 - exp(-dt * 1.5))
		if rng.randf() < dt * 0.015:
			g.facing = _pick_facing()
	# The ferry's leaving: everyone off, not quite all at once.
	if not p.usable() and g.timer > 1.6:
		g.timer = rng.randf_range(0.1, 1.5)
	# A fishing boat at work in sight: time to go and see.
	if g.think <= 0.0:
		g.think = rng.randf_range(1.0, 3.0)
		if g.timer > 3.0 and rng.randf() < FISH_RESTLESS * 2.0 * (1.0 - day_cycle.night) and _fish_near(g.pos) != null:
			g.timer = rng.randf_range(0.2, 3.0)
	# Now and then a stretch of the wings.
	if g.stretch <= 0.0 and rng.randf() < dt * 0.02:
		g.stretch = rng.randf_range(0.6, 1.2)
	if g.stretch > 0.0:
		g.stretch -= dt
		g.fold = move_toward(g.fold, 0.35, dt * 4.0)
		g.flap_amp = move_toward(g.flap_amp, 0.35, dt * 3.0)
		g.flap_phase += dt * TAU * 1.5
	else:
		g.fold = move_toward(g.fold, 1.0, dt * 3.0)
		g.flap_amp = move_toward(g.flap_amp, 0.0, dt * 3.0)
	g.pitch = move_toward(g.pitch, 0.0, dt * 2.0)
	g.bank = move_toward(g.bank, 0.0, dt * 2.0)
	g.timer -= dt
	if g.timer > 0.0:
		return
	var carrier: Vessel = p.ferry if not p.usable() else null
	_take_off(g)
	if g.leader != null:
		if _airborne(g.leader):
			_start_follow(g, g.leader)
			return
		g.leader = null
	_recruit(g)
	if carrier != null and rng.randf() < 0.5:
		_start_roam(g, carrier)
	else:
		_decide(g)


func _take_off(g: Gull) -> void:
	_release(g)
	g.stretch = 0.0
	g.boost = rng.randf_range(0.8, 1.4)
	g.alt = rng.randf_range(12.0, 32.0)
	g.vel = Vector3(sin(g.yaw), 0.0, cos(g.yaw)) * 3.0 + Vector3.UP * 3.5


## Calls some perched neighbours up to fly along.
func _recruit(g: Gull) -> void:
	if rng.randf() > GROUP_CHANCE:
		return
	var n := 0
	for o in _gulls:
		if n >= MAX_RECRUITS:
			break
		if o == g or o.state != State.PERCHED or o.leader != null:
			continue
		if o.pos.distance_squared_to(g.pos) < RECRUIT_RADIUS * RECRUIT_RADIUS and rng.randf() < 0.6:
			o.leader = g
			o.timer = rng.randf_range(0.15, 1.3)
			n += 1


## Where a solo gull (or a group's leader) goes next.
func _decide(g: Gull) -> void:
	var fish := _fish_near(g.pos)
	if fish != null and rng.randf() < FISH_CHANCE:
		_start_roam(g, fish)
		return
	var r := rng.randf()
	var f := _ferry_near(g.pos, 150.0)
	if f != null and r < ESCORT_CHANCE:
		_start_roam(g, f)
		return
	if r < ESCORT_CHANCE + ROAM_CHANCE:
		_start_roam(g)
		return
	if _claim(g, g.pos, PERCH_RANGE):
		_fly_to(g)
	else:
		_start_roam(g)


# --- Flying -------------------------------------------------------------------------

## Heads for the seat it has claimed.
func _fly_to(g: Gull) -> void:
	g.state = State.FLY
	g.escort = null
	g.timer = 60.0
	g.alt = maxf(g.alt, _seat_world(g).y + 6.0)


func _tick_fly(g: Gull, dt: float) -> void:
	var p := g.perch
	if not p.usable():
		_release(g)
		_start_roam(g)
		return
	var target := _seat_world(g)
	var flat := Vector2(target.x - g.pos.x, target.z - g.pos.z).length()
	g.timer -= dt
	if flat < LAND_START or g.timer < 0.0:
		_begin_land(g)
		return
	# Cruise, then let down along a shallow slope to just above the perch.
	var aim := target
	aim.y = minf(target.y + 2.0 + (flat - LAND_START) * 0.4, maxf(g.alt, target.y + 2.0))
	_steer(g, (aim - g.pos).normalized() * SPEED, ACCEL, dt)


func _start_roam(g: Gull, escort: Vessel = null) -> void:
	g.state = State.ROAM
	g.escort = escort
	g.timer = rng.randf_range(8.0, 25.0) if escort else rng.randf_range(5.0, 15.0)
	g.offset = Vector3(rng.randf_range(-7.0, 7.0), rng.randf_range(5.0, 12.0), rng.randf_range(14.0, 26.0))
	if escort is FishingBoat:
		# A loose, low, squabbling crowd over the wake.
		g.timer = rng.randf_range(15.0, 45.0)
		g.offset = Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(3.0, 10.0), rng.randf_range(8.0, 34.0))
	var a := rng.randf() * TAU
	var c := g.pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(10.0, 40.0)
	g.orbit = Vector3(c.x, rng.randf_range(10.0, 35.0), c.z)
	g.orbit_r = rng.randf_range(10.0, 28.0)
	g.orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	g.think = rng.randf_range(1.0, 3.0)


func _tick_roam(g: Gull, dt: float) -> void:
	g.timer -= dt
	var f := g.escort
	if f != null and not _escorting(f):
		# Arrived with it: likely drops onto it or nearby.
		g.timer = minf(g.timer, 0.0)
	if g.timer <= 0.0:
		if f is FishingBoat and _escorting(f):
			# Down onto the water in its wake for a bit, or round again.
			if rng.randf() < 0.45 and _claim_wake(g, f):
				_fly_to(g)
			else:
				_start_roam(g, f)
			return
		if _claim(g, f.global_position if f else g.pos, PERCH_RANGE):
			_fly_to(g)
		else:
			_start_roam(g)
		return
	if f != null:
		# Hang off the stern quarter, over the wake.
		var dir := _escort_dir(f)
		var side := dir.cross(Vector3.UP)
		var aim := f.global_position - dir * g.offset.z + side * g.offset.x + Vector3.UP * g.offset.y
		if f is FishingBoat:
			# Wheeling about over it rather than holding station.
			var wob := g.timer * 0.7 + g.flap_phase
			aim += Vector3(sin(wob) * 6.0, sin(wob * 1.3) * 2.0, cos(wob * 0.8) * 6.0)
		var want := dir * f.speed + (aim - g.pos) * 0.5
		_steer(g, want.limit_length(SPEED * 1.4), ACCEL, dt)
	else:
		var rel := Vector2(g.pos.x - g.orbit.x, g.pos.z - g.orbit.z)
		var a := rel.angle() + g.orbit_dir * 0.5
		var aim := Vector3(g.orbit.x + cos(a) * g.orbit_r, g.orbit.y, g.orbit.z + sin(a) * g.orbit_r)
		_steer(g, (aim - g.pos).normalized() * SPEED * 0.85, ACCEL, dt)
		_look_for_company(g)


## Loners now and then fall in with a passing gull's group.
func _look_for_company(g: Gull) -> void:
	if g.think > 0.0:
		return
	g.think = rng.randf_range(2.0, 4.0)
	if rng.randf() > 0.3:
		return
	for o in _gulls:
		if o == g or not _airborne(o) or o.pos.distance_squared_to(g.pos) > JOIN_RADIUS * JOIN_RADIUS:
			continue
		var head := _root(o)
		if head != g:
			_start_follow(g, head)
			return


func _start_follow(g: Gull, leader: Gull) -> void:
	g.leader = leader
	g.state = State.FOLLOW
	g.escort = null
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	g.offset = Vector3(side * rng.randf_range(2.5, 7.0), rng.randf_range(-1.5, 1.5), -rng.randf_range(2.0, 8.0))
	g.think = rng.randf_range(3.0, 6.0)


func _tick_follow(g: Gull, dt: float) -> void:
	var l := g.leader
	if l == null or not _airborne(l):
		# The leader's coming down: find a spot near it.
		var near := _seat_world(l) if l != null and l.perch != null else g.pos
		g.leader = null
		if _claim(g, near, 35.0):
			_fly_to(g)
		else:
			_start_roam(g)
		return
	if g.think <= 0.0:
		g.think = rng.randf_range(3.0, 6.0)
		if rng.randf() < 0.1:
			g.leader = null
			_decide(g)
			return
	var slot := l.pos + Basis(Vector3.UP, l.yaw) * g.offset
	var want := l.vel + (slot - g.pos) * 0.9
	_steer(g, want.limit_length(SPEED * 1.4), ACCEL * 1.5, dt)


func _begin_land(g: Gull) -> void:
	g.state = State.LAND
	g.land_from = g.pos
	g.land_vel = g.vel
	g.land_t = 0.0
	var d := g.pos.distance_to(_seat_world(g))
	g.land_time = clampf(d / maxf(g.vel.length(), 4.0) * 1.5, 1.0, 3.0)


## A Hermite glide from where it broke off to the perch, braking and flaring at the end.
func _tick_land(g: Gull, dt: float) -> void:
	var p := g.perch
	if not p.usable():
		_release(g)
		g.fold = 0.0
		_start_roam(g)
		return
	g.land_t += dt
	var t := g.land_time
	var s := minf(g.land_t / t, 1.0)
	var p0 := g.land_from
	var p1 := _seat_world(g)
	var m0 := g.land_vel * t
	var flat := Vector3(g.land_vel.x, 0.0, g.land_vel.z).normalized()
	var m1 := (flat * 1.2 + Vector3.DOWN * 0.4) * t
	var s2 := s * s
	var s3 := s2 * s
	g.pos = p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)
	g.vel = (p0 * (6.0 * s2 - 6.0 * s) + m0 * (3.0 * s2 - 4.0 * s + 1.0) + p1 * (-6.0 * s2 + 6.0 * s) + m1 * (3.0 * s2 - 2.0 * s)) / t
	_orient(g, dt)
	# Glide in, then back-flap and flare to a stop.
	var flare := smoothstep(0.55, 0.9, s)
	g.pitch = lerpf(g.pitch, 0.7 * flare, 1.0 - exp(-dt * 8.0))
	g.flap_amp = move_toward(g.flap_amp, 1.0 * flare, dt * 4.0)
	g.flap_phase += dt * TAU * 4.5
	g.fold = smoothstep(0.9, 1.0, s)
	if s >= 1.0:
		g.state = State.PERCHED
		g.vel = Vector3.ZERO
		g.bob = rng.randf() * TAU
		g.timer = _perch_time(p)


func _steer(g: Gull, want: Vector3, accel: float, dt: float) -> void:
	# Stay over the map.
	if absf(g.pos.x) > _bound or absf(g.pos.z) > _bound:
		want += Vector3(-signf(g.pos.x) if absf(g.pos.x) > _bound else 0.0, 0.0,
			-signf(g.pos.z) if absf(g.pos.z) > _bound else 0.0) * SPEED
	g.vel = g.vel.move_toward(want, accel * dt)
	# Gulls can't hover: keep some airspeed once clear of the perch.
	var h := Vector2(g.vel.x, g.vel.z)
	if g.boost <= 0.0 and h.length() < 5.0:
		var fwd := Vector2(sin(g.yaw), cos(g.yaw))
		h = fwd * 5.0 if h.length() < 0.1 else h.normalized() * 5.0
		g.vel.x = h.x
		g.vel.z = h.y
	g.pos += g.vel * dt
	# Clear the treetops over land, skim no lower than a few metres over water.
	var ground := sim.terrain.height_at(g.pos.x, g.pos.z)
	var floor_y := ground + 10.0 if ground > 0.0 else 3.0
	if g.pos.y < floor_y:
		g.vel.y = maxf(g.vel.y, (floor_y - g.pos.y) * 1.5)
	_orient(g, dt)


func _orient(g: Gull, dt: float) -> void:
	var h := Vector2(g.vel.x, g.vel.z)
	if h.length_squared() > 0.04:
		var ny := atan2(g.vel.x, g.vel.z)
		var rate := angle_difference(g.yaw, ny) / maxf(dt, 1e-4)
		g.yaw = ny
		g.bank = lerpf(g.bank, clampf(-rate * 0.35, -0.8, 0.8), 1.0 - exp(-dt * 4.0))
	var climb := clampf(atan2(g.vel.y, h.length()) * 0.6, -0.5, 0.5)
	g.pitch = lerpf(g.pitch, climb, 1.0 - exp(-dt * 4.0))


## Flapping in bursts between glides; hard and fast taking off or climbing.
func _wings_in_flight(g: Gull, dt: float) -> void:
	g.fold = move_toward(g.fold, 0.0, dt * 3.0)
	g.boost -= dt
	g.flap_burst -= dt
	if g.flap_burst <= 0.0 and rng.randf() < dt * 0.45:
		g.flap_burst = rng.randf_range(0.8, 2.0)
	var amp := 0.0
	var freq := 3.2
	if g.boost > 0.0:
		amp = 1.0
		freq = 4.5
	elif g.vel.y > 0.8 or g.flap_burst > 0.0:
		amp = 0.7
	g.flap_amp = move_toward(g.flap_amp, amp, dt * 3.0)
	g.flap_phase = fmod(g.flap_phase + dt * TAU * freq, TAU)


# --- Helpers ------------------------------------------------------------------------

func _airborne(g: Gull) -> bool:
	return g.state == State.FLY or g.state == State.ROAM or g.state == State.FOLLOW


func _root(g: Gull) -> Gull:
	var r := g
	for i in 8:
		if r.leader == null or not _airborne(r.leader):
			break
		r = r.leader
	return r


func _rest(p: Perch) -> float:
	return FLOAT if p.kind == Kind.WATER else REST


func _perch_time(p: Perch) -> float:
	var t := rng.randf_range(10.0, 70.0)
	if p.kind == Kind.WATER:
		t *= 0.6
	# Roosting: they mostly stay put through the night.
	return t * lerpf(1.0, 5.0, day_cycle.night)


## Whether `v` is still worth tailing: a ferry under way, or a fishing boat out
## on the water.
func _escorting(v: Vessel) -> bool:
	if v is Ferry:
		return (v as Ferry).state == Ferry.State.SAILING
	if v is FishingBoat:
		return is_instance_valid(v) and (v as FishingBoat).free_nav
	return false


## The way it is heading (a ferry's bow is whichever end it is sailing towards).
func _escort_dir(v: Vessel) -> Vector3:
	if v is Ferry:
		return v.global_transform.basis.z * (1.0 if (v as Ferry).at_a else -1.0)
	var h := v.heading2()
	return Vector3(h.x, 0.0, h.y)


## The nearest fishing boat out at work that a gull at `p` would notice.
func _fish_near(p: Vector3) -> FishingBoat:
	var best: FishingBoat = null
	var best_d := INF
	for b in sim.marine.fishing_boats:
		if not b.free_nav:
			continue
		var fed: bool = (b.fishing() and b.work == FishingBoat.Work.HAULING) or b.state == FishingBoat.State.HOMEWARD
		var reach := FISH_ATTENTION_FED if fed else FISH_ATTENTION
		var d := b.global_position.distance_to(p)
		if d < reach and d < best_d:
			best = b
			best_d = d
	return best


## A fishing boat under way heading for a gull sitting on the water at `p`.
func _boat_bearing_down(p: Vector3) -> bool:
	for b in sim.marine.fishing_boats:
		if b.speed < 0.3 or b.global_position.distance_squared_to(p) > 30.0 * 30.0:
			continue
		var to := Vector2(p.x - b.global_position.x, p.z - b.global_position.z)
		if to.dot(b.heading2()) > 0.0:
			return true
	return false


## A seat on the water astern of fishing boat `b`, among the others there.
func _claim_wake(g: Gull, b: FishingBoat) -> bool:
	var h := b.heading2()
	var stern := b.global_position - Vector3(h.x, 0.0, h.y) * (b.spec.half_length + rng.randf_range(6.0, 22.0))
	for p in _perches:
		if p.kind == Kind.WATER and p.gulls.size() < p.capacity and Vector2(p.a.x - stern.x, p.a.z - stern.z).length() < 14.0:
			var seat: Variant = _find_seat(p)
			if seat != null:
				p.gulls.append(g)
				g.perch = p
				g.seat = seat
				return true
	if sim.terrain.height_at(stern.x, stern.z) > -1.5:
		return false
	var raft := Perch.new(Vector3(stern.x, 0.0, stern.z), Vector3(stern.x, 0.0, stern.z), RAFT, Kind.WATER)
	var s0: Variant = _find_seat(raft)
	if s0 == null:
		return false
	_perches.append(raft)
	raft.gulls.append(g)
	g.perch = raft
	g.seat = s0
	return true


func _ferry_near(p: Vector3, radius: float) -> Ferry:
	for f in sim.ferries:
		if f.state == Ferry.State.SAILING and f.global_position.distance_squared_to(p) < radius * radius:
			return f
	return null


## Claims a seat on a perch with room, weighted by appeal, nearness to `near` and
## the company already there. Open water is always an option: an existing raft
## of gulls, or a fresh spot.
func _claim(g: Gull, near: Vector3, radius: float) -> bool:
	var picks: Array[Perch] = []
	var weights := PackedFloat32Array()
	var total := WATER_APPEAL
	for p in _perches:
		if p.gulls.size() >= p.capacity or not p.usable():
			continue
		var c := p.center()
		var d := Vector2(c.x - near.x, c.z - near.z).length()
		if d > radius:
			continue
		var appeal: float = WATER_APPEAL if p.kind == Kind.WATER else APPEAL[p.kind]
		var wt := appeal * exp(-d / PERCH_FALLOFF) * (1.0 + COMPANY * mini(p.gulls.size(), 4)) * sqrt(float(mini(p.capacity, 6)))
		picks.append(p)
		weights.append(wt)
		total += wt
	for attempt in 4:
		var r := rng.randf() * total
		var chosen: Perch = null
		for i in picks.size():
			r -= weights[i]
			if r <= 0.0:
				chosen = picks[i]
				total -= weights[i]
				weights[i] = 0.0
				break
		if chosen == null:
			chosen = _new_raft(near, radius)
			if chosen == null:
				return false
		var seat: Variant = _find_seat(chosen)
		if seat != null:
			chosen.gulls.append(g)
			g.perch = chosen
			g.seat = seat
			if chosen.kind == Kind.WATER and not _perches.has(chosen):
				_perches.append(chosen)
			return true
	return false


## A free spot on the perch, often beside a gull already there, never on top of one.
func _find_seat(p: Perch) -> Variant:
	for attempt in 10:
		var s: Vector3
		if not p.gulls.is_empty() and rng.randf() < HUDDLE:
			var o: Gull = p.gulls[rng.randi() % p.gulls.size()]
			var a := rng.randf() * TAU
			s = p.project(o.seat + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.9, 2.2))
		else:
			s = p.sample(rng)
		var gap := rng.randf_range(0.85, 1.3)
		var ok := true
		for o in p.gulls:
			if o.seat.distance_to(s) < gap:
				ok = false
				break
		if ok:
			return s
	return null


func _release(g: Gull) -> void:
	var p := g.perch
	if p == null:
		return
	p.gulls.erase(g)
	g.perch = null
	if p.kind == Kind.WATER and p.gulls.is_empty():
		_perches.erase(p)


func _seat_world(g: Gull) -> Vector3:
	return g.perch.to_world(g.seat) + Vector3.UP * _rest(g.perch)


## Mostly into the wind, give or take; the odd one any way at all.
func _pick_facing() -> float:
	return rng.randf() * TAU if rng.randf() < 0.12 else rng.randf_range(-0.8, 0.8)


func _new_raft(near: Vector3, radius: float) -> Perch:
	for attempt in 8:
		var a := rng.randf() * TAU
		var d := rng.randf_range(12.0, minf(radius, 70.0))
		var p := Vector3(near.x + cos(a) * d, 0.0, near.z + sin(a) * d)
		if absf(p.x) < _bound and absf(p.z) < _bound and sim.terrain.height_at(p.x, p.z) < -1.5 \
				and _ferry_near(p, 40.0) == null:
			return Perch.new(p, p, RAFT, Kind.WATER)
	return null


func _render() -> void:
	var k := 0
	for g in _gulls:
		var b := (Basis(Vector3.UP, g.yaw) * Basis(Vector3.RIGHT, -g.pitch) * Basis(Vector3.BACK, g.bank)).scaled(Vector3.ONE * SCALE * g.size)
		var o := k * 16
		_buf[o] = b.x.x
		_buf[o + 1] = b.y.x
		_buf[o + 2] = b.z.x
		_buf[o + 3] = g.pos.x
		_buf[o + 4] = b.x.y
		_buf[o + 5] = b.y.y
		_buf[o + 6] = b.z.y
		_buf[o + 7] = g.pos.y
		_buf[o + 8] = b.x.z
		_buf[o + 9] = b.y.z
		_buf[o + 10] = b.z.z
		_buf[o + 11] = g.pos.z
		_buf[o + 12] = g.flap_phase
		_buf[o + 13] = g.flap_amp
		_buf[o + 14] = g.fold
		_buf[o + 15] = 0.0
		k += 1
	_mm.buffer = _buf

