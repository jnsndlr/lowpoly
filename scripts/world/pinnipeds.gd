class_name Pinnipeds
extends Node3D
## Draws the seals and sea lions of Wildlife's visits and takes them in and out of
## the water at their haul-out (MapData.HaulOut), one multimesh per kind.
##
## Arriving, the group swims in, heads bobbing up between dives. Once it's at the
## haul-out (Visit.phase HAULED) each animal in its own time takes a free spot
## (the nearest one to the water on a free line in), swims to it, comes out (up
## the beach humping along, or with a lunge up onto the rock or float) and lies
## up: asleep mostly, harbor seals often bent like a banana and sea lions sprawled
## on their sides or propped up on their flippers, now and then looking about or
## scratching. Some stay in the water instead, resting at the surface: harbor
## seals upright with just their noses out ("bottling"), sea lions on their sides
## with a flipper held up ("jughandling"). Harbor seals come out more at low tide.
## A boat under way too close flushes them: heads up first, then a scramble into
## the water (seals are skittish; sea lions on a dock hardly look up). As the
## visit draws to an end they all go back in and swim off with the group.

enum State { SWIM, RAFT, CLIMB, REST, LEAVE }
enum Pose { SLEEP, LOOK, SIT, SCRATCH }

const MAX_PER_KIND := 64
const MAX_SPLASHES := 24
# Must match seal_body[] in water.gdshader: animals in the water nearest the
# camera (within FOAM_RANGE) that the water draws no contact foam round.
const MAX_FOAM_CLEAR := 32
const FOAM_RANGE := 750.0
# How long after its head went under an animal can still be clicked (real ms).
const CLICK_GRACE := 1500


## How a species looks and behaves ashore.
class Kind:
	var id := ""
	var mesh: ArrayMesh
	var scale := 1.3                    # bigger than life, so they read
	var neck_z := 0.3                   # pinniped.gdshader's bend points
	var hip_z := -0.2
	var tints: Array[Color] = []
	var crawl := 0.45                   # m per game minute on land
	var swim := 7.5                    # in the water
	var alert := 180.0                  # a boat under way this close: heads up
	var flush := 90.0                   # this close: into the water
	var tide := 1.0                     # how much more it hauls out at low tide
	var mm: MultiMesh
	var buf := PackedFloat32Array()

	func _init(i: String, m: ArrayMesh, fields := {}) -> void:
		id = i
		mesh = m
		for k: String in fields:
			set(k, fields[k])


class Animal:
	var visit: Wildlife.Visit
	var kind: Kind
	var mother: Animal
	var length := 1.6           # metres, as drawn
	var tint := Color.WHITE
	var bull := false
	var state := State.SWIM
	var pose := Pose.SLEEP
	var offset := Vector3.ZERO  # slot about the group, in the water
	var pos := Vector3.ZERO
	var y := 0.0
	var yaw := 0.0
	var pitch := 0.0
	var roll := 0.0
	var head := 0.0
	var tail := 0.0
	var phase := 0.0
	var sway := 0.0             # pinniped.gdshader's w: > 0 swimming sway, < 0 arch
	var under := false          # dived, between breaths
	var breath := 0.0           # until it next dives or comes up
	var timer := 0.0            # in the current state / pose
	var spot := -1              # index into the site's spots, while it has one
	var path: Array[Vector3] = []
	var leg := 0
	var hop := -1.0             # 0..1 through a lunge onto (or a dive off) a ledge or float
	var banana := false         # likes to lie with head and tail up
	var sleep_roll := 0.0       # on its side, asleep
	var hurry := false          # flushed
	var shown_ms := -100000


class Pod:
	var visit: Wildlife.Visit
	var kind: Kind
	var animals: Array[Animal] = []
	var taken: Array = []       # spot index -> the Animal there (or heading there)
	var disturbed := INF        # how close the nearest boat under way is
	var gone := 0.0


class Splash:
	var pos := Vector3.ZERO
	var size := 1.0
	var t := 0.0


var wildlife: Wildlife
var terrain: Terrain
var water_mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var kinds := {}
var _pods: Array[Pod] = []
var _splashes: Array[Splash] = []
var _splash_mm: MultiMesh
var _splash_buf := PackedFloat32Array()
var _foam_clear := PackedVector4Array()


func setup(w: Wildlife, t: Terrain, water: ShaderMaterial = null) -> void:
	name = "Pinnipeds"
	wildlife = w
	terrain = t
	water_mat = water
	rng.seed = w.sim.map.map_seed * 43 + 17
	for k: Kind in [
		Kind.new("harbor_seal", Models.harbor_seal(), {"neck_z": 0.33, "hip_z": -0.22,
			"tints": [Color(0.78, 0.8, 0.8), Color(0.62, 0.6, 0.56), Color(0.45, 0.44, 0.43), Color(0.82, 0.76, 0.64)] as Array[Color],
			"crawl": 0.45, "swim": 6.6, "alert": 210.0, "flush": 96.0, "tide": 2.5}),
		Kind.new("sea_lion", Models.sea_lion(), {"scale": 1.15, "neck_z": 0.27, "hip_z": -0.24,
			"tints": [Color(0.42, 0.3, 0.2), Color(0.5, 0.36, 0.24), Color(0.3, 0.22, 0.16), Color(0.66, 0.5, 0.32)] as Array[Color],
			"crawl": 0.8, "swim": 9.0, "alert": 66.0, "flush": 21.0, "tide": 0.0}),
	]:
		kinds[k.id] = k
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/pinniped.gdshader")
		mat.set_shader_parameter("neck_z", k.neck_z)
		mat.set_shader_parameter("hip_z", k.hip_z)
		k.mm = MultiMesh.new()
		k.mm.transform_format = MultiMesh.TRANSFORM_3D
		k.mm.use_colors = true
		k.mm.use_custom_data = true
		k.mm.mesh = k.mesh
		k.mm.instance_count = MAX_PER_KIND
		k.mm.visible_instance_count = 0
		k.buf.resize(MAX_PER_KIND * 20)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = k.id
		mmi.multimesh = k.mm
		mmi.material_override = mat
		add_child(mmi)
	_splash_mm = MultiMesh.new()
	_splash_mm.transform_format = MultiMesh.TRANSFORM_3D
	_splash_mm.use_colors = true
	_splash_mm.mesh = Models.spout()
	_splash_mm.instance_count = MAX_SPLASHES
	_splash_mm.visible_instance_count = 0
	_splash_buf.resize(MAX_SPLASHES * 16)
	_foam_clear.resize(MAX_FOAM_CLEAR)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _splash_mm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	w.visit_started.connect(_on_visit)
	for v in w.active_visits():
		_on_visit(v)


func _on_visit(v: Wildlife.Visit) -> void:
	if not kinds.has(v.species.id) or v.site == null:
		return
	var k: Kind = kinds[v.species.id]
	var p := Pod.new()
	p.visit = v
	p.kind = k
	p.taken.resize(v.site.spots.size())
	for m in v.members:
		var o := Animal.new()
		o.visit = v
		o.kind = k
		o.length = m.length * k.scale
		o.bull = m.role == Wildlife.Role.BULL
		o.tint = k.tints[rng.randi() % k.tints.size()]
		if o.bull:
			o.tint = o.tint.darkened(0.25)
		elif m.role == Wildlife.Role.COW and k.id == "sea_lion":
			o.tint = k.tints[3]
		o.banana = k.id == "harbor_seal" and rng.randf() < 0.6
		if m.mother >= 0 and m.mother < p.animals.size():
			o.mother = p.animals[m.mother]
			o.tint = o.mother.tint.lightened(0.1)
		var a := rng.randf() * TAU
		o.offset = Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.0, 9.0)
		o.pos = v.pos + o.offset
		o.yaw = v.heading
		o.under = rng.randf() < 0.6
		o.breath = rng.randf_range(0.0, 8.0)
		o.y = _swim_y(o)
		o.phase = rng.randf() * TAU
		p.animals.append(o)
	# Already lying up when we first see them (Wildlife's residents at the start):
	# most of them out on the haul-out, the rest milling about off it.
	if v.phase == Wildlife.Phase.HAULED:
		for o in p.animals:
			if rng.randf() < 0.8 and (o.mother == null or o.mother.state == State.REST) and _take_spot(o, p):
				var sp := v.site.spots[o.spot]
				o.pos = sp.at
				o.yaw = sp.yaw
				o.state = State.REST
				_next_pose(o)
				o.timer *= rng.randf()
				_rest(o, p, 0.0)
				o.roll = o.sleep_roll if o.pose == Pose.SLEEP else 0.0
	_pods.append(p)


func _process(delta: float) -> void:
	if delta > 0.0:
		for i in range(_pods.size() - 1, -1, -1):
			if not _tick_pod(_pods[i], delta):
				_pods.remove_at(i)
		for i in range(_splashes.size() - 1, -1, -1):
			_splashes[i].t += delta
			if _splashes[i].t >= 1.0:
				_splashes.remove_at(i)
	_render()


## False once the group has gone for good.
func _tick_pod(p: Pod, dt: float) -> bool:
	var v := p.visit
	if not v.active():
		p.gone += dt
		if p.gone > 40.0:
			return false
	p.disturbed = _nearest_boat(v.site)
	for o in p.animals:
		_tick_animal(o, p, dt)
	return true


## How close the nearest boat under way is to the haul-out. Ships and ferries
## keep to their lanes and the animals are used to them; it's small craft coming
## in close that put them up.
func _nearest_boat(site: MapData.HaulOut) -> float:
	var sim := wildlife.sim
	if sim.marine == null:
		return INF
	var c := Vector2(site.spots[0].at.x, site.spots[0].at.z) if not site.spots.is_empty() else Vector2(site.water.x, site.water.z)
	var best := INF
	for b in sim.marine.vessels:
		if b.speed < 3.0 or b is Ferry or b is CargoShip:
			continue
		best = minf(best, b.pos2().distance_to(c) - b.half_seg)
	return best


func _tick_animal(o: Animal, p: Pod, dt: float) -> void:
	var v := o.visit
	var k := o.kind
	var leaving := v.phase == Wildlife.Phase.DEPART or not v.active()
	o.timer -= dt
	match o.state:
		State.SWIM, State.RAFT:
			_swim(o, p, dt, leaving)
		State.CLIMB:
			if leaving:
				_leave(o, p, false)
			else:
				_follow_path(o, p, dt)
		State.REST:
			if leaving and o.timer > 8.0:
				o.timer = rng.randf_range(0.0, 8.0)
			if p.disturbed < k.flush and v.site.kind != MapData.HaulOut.Kind.DOCK or p.disturbed < k.flush * 0.5:
				_leave(o, p, true)
			elif o.timer <= 0.0:
				if leaving or rng.randf() < 0.01:
					_leave(o, p, false)
				else:
					_next_pose(o)
			_rest(o, p, dt)
		State.LEAVE:
			_follow_path(o, p, dt)
	if o.state == State.REST or o.state == State.CLIMB or o.state == State.LEAVE or not o.under:
		o.shown_ms = Time.get_ticks_msec()


# --- In the water ------------------------------------------------------------------

## Low in the water, just the head and a bit of back showing.
func _swim_y(o: Animal) -> float:
	return -0.25 * o.length


func _swim(o: Animal, p: Pod, dt: float, leaving: bool) -> void:
	var v := o.visit
	var k := o.kind
	var L := o.length
	# Hold a slot about the group (a pup at its mother's side), milling about
	# when the group's waiting off the haul-out.
	var mill := v.phase == Wildlife.Phase.HAULED
	if mill:
		o.offset = Basis(Vector3.UP, dt * 0.02) * o.offset
	var slot := v.pos + Basis(Vector3.UP, v.heading) * o.offset
	if o.mother and o.mother.state != State.REST:
		slot = o.mother.pos + Vector3(sin(o.mother.yaw + 1.6), 0.0, cos(o.mother.yaw + 1.6)) * L * 0.6
	if terrain.height_at(slot.x, slot.z) > -2.7:
		slot = v.pos
	var to := slot - o.pos
	to.y = 0.0
	var want := to * 0.4 + Vector3(sin(v.heading), 0.0, cos(v.heading)) * (0.0 if mill else v.speed)
	if o.state == State.RAFT:
		want = to * 0.05
	var spd := minf(want.length(), v.speed * 1.6 + k.swim)
	if spd > 0.05:
		var ny := atan2(want.x, want.z)
		o.yaw = lerp_angle(o.yaw, ny, 1.0 - exp(-dt * 1.5))
		o.pos += Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * spd * dt
	o.phase += dt * (2.0 + spd * 0.4)
	o.roll = move_toward(o.roll, 0.0, dt * 0.8)
	# Breathe: up for a while, head out looking about, then down again.
	o.breath -= dt
	if o.breath <= 0.0:
		o.under = not o.under
		o.breath = rng.randf_range(12.0, 35.0) if o.under else rng.randf_range(5.0, 14.0)
		if o.under and o.state == State.RAFT:
			o.under = false
	if not v.active():
		o.under = true
		o.state = State.SWIM
	var target_y := -0.9 * L if o.under else _swim_y(o)
	var head := 0.7
	var pitch := 0.0
	var roll := 0.0
	var sway := 0.035 * clampf(spd / 6.0, 0.2, 1.0)
	if o.state == State.RAFT:
		sway = 0.0
		if k.id == "harbor_seal":
			# Bottling: upright, asleep with just its nose out.
			pitch = 1.25
			head = 0.15
			target_y = -0.49 * L
		else:
			# Jughandling: on its side, a fore flipper and the hind flippers up out of the water.
			roll = 1.35
			head = 0.25
			target_y = -0.13 * L
		if o.timer <= 0.0 or leaving or mill == false:
			o.state = State.SWIM
			o.timer = rng.randf_range(10.0, 40.0)
	o.y = move_toward(o.y, target_y, dt * 0.8)
	o.pitch = move_toward(o.pitch, pitch, dt * 0.8)
	o.roll = move_toward(o.roll, roll, dt * 1.0) if roll != 0.0 else o.roll
	o.head = move_toward(o.head, head, dt * 0.8)
	o.tail = move_toward(o.tail, 0.0, dt)
	o.sway = sway
	if o.state != State.SWIM or not mill or leaving or o.timer > 0.0:
		return
	# Off the haul-out: come out, lie at the surface for a while, or swim on.
	o.timer = rng.randf_range(4.0, 30.0)
	var tide := wildlife.sim.tide().x / 1.6          # -1 low .. 1 high
	var keen := 0.5 - 0.25 * k.tide * tide
	if p.disturbed < k.alert:
		keen = 0.0
	if rng.randf() < keen and not o.under and (o.mother == null or o.mother.state == State.REST or o.mother.state == State.CLIMB):
		if _take_spot(o, p):
			return
	if rng.randf() < 0.25:
		o.state = State.RAFT
		o.under = false
		o.timer = rng.randf_range(30.0, 120.0)


## Claims the free spot nearest the water on a free line in (and nearest to it);
## false if the haul-out's full.
func _take_spot(o: Animal, p: Pod) -> bool:
	var site := o.visit.site
	var seen := {}
	var best := -1
	var best_d := INF
	for i in site.spots.size():
		var sp := site.spots[i]
		var line := Vector2i(roundi(sp.entry.x * 2.0), roundi(sp.entry.z * 2.0))
		if p.taken[i] != null:
			continue
		# Only the first free spot along each line in, so nobody climbs over anybody.
		if seen.has(line):
			continue
		seen[line] = true
		if o.kind.id == "sea_lion" and not sp.big:
			continue
		var d := o.pos.distance_to(sp.entry)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	var sp := site.spots[best]
	p.taken[best] = o
	o.spot = best
	o.state = State.CLIMB
	o.path = [sp.entry, sp.edge, sp.at]
	o.leg = 0
	o.hop = -1.0
	o.hurry = false
	o.under = false
	return true


# --- Coming out, going back in -------------------------------------------------------

func _leave(o: Animal, p: Pod, hurry: bool) -> void:
	if o.spot < 0 or (o.state == State.CLIMB and o.leg == 0):
		# Not out of the water yet: just don't.
		if o.spot >= 0:
			p.taken[o.spot] = null
		o.spot = -1
		o.state = State.SWIM
		return
	var sp := o.visit.site.spots[o.spot]
	var climbing_out := o.state == State.CLIMB and o.leg == 1
	o.state = State.LEAVE
	o.hurry = hurry
	o.path = [Vector3(o.pos.x, o.y, o.pos.z), sp.edge, sp.entry + (sp.entry - sp.edge).normalized() * 2.0]
	if climbing_out:
		# Still on the way out of the water: straight back in from where it is.
		o.path[1] = o.pos
		o.leg = 2
	else:
		o.leg = 1 if o.pos.distance_to(Vector3(sp.edge.x, o.pos.y, sp.edge.z)) > 0.3 else 2
	o.hop = -1.0
	o.timer = 0.0


## Along the path: swimming to the line in, out of the water (or into it), then
## along the ground or the top of the rock or float.
func _follow_path(o: Animal, p: Pod, dt: float) -> void:
	var site := o.visit.site
	var k := o.kind
	var L := o.length
	var flat := site.kind != MapData.HaulOut.Kind.BEACH
	var out := o.state == State.LEAVE
	var leg_to: Vector3 = o.path[mini(o.leg, o.path.size() - 1)]
	var speed := k.crawl * (2.2 if o.hurry else 1.0)
	# The step between the water and the edge: a lunge up out of the water onto a
	# ledge or float (or a dive off it), a shuffle up or down the beach.
	var water_step := (not out and o.leg == 1) or (out and o.leg == 2)
	if water_step and flat:
		if o.hop < 0.0:
			o.hop = 0.0
			if out:
				o.pos = Vector3(o.path[1].x, 0.0, o.path[1].z)
		o.hop = minf(o.hop + dt / (0.9 if out else 1.3), 1.0)
		var from: Vector3 = o.path[0] if not out else o.path[1]
		var s := o.hop
		var top := site.top
		var p0 := Vector3(from.x, 0.0, from.z)
		var p1 := Vector3(leg_to.x, 0.0, leg_to.z)
		o.pos = p0.lerp(p1, smoothstep(0.0, 1.0, s))
		if out:
			o.y = lerpf(top, _swim_y(o) - 0.3 * L, smoothstep(0.0, 1.0, s)) + 0.18 * L * sin(PI * s * 0.6)
			o.pitch = -0.7 * sin(PI * s)
		else:
			o.y = lerpf(_swim_y(o) - 0.1 * L, top, smoothstep(0.1, 0.8, s)) + 0.12 * L * sin(PI * s)
			o.pitch = 0.6 * sin(PI * minf(s * 1.3, 1.0))
		o.yaw = lerp_angle(o.yaw, atan2(p1.x - p0.x, p1.z - p0.z), 1.0 - exp(-dt * 6.0))
		o.head = move_toward(o.head, 0.4, dt * 2.0)
		o.tail = move_toward(o.tail, 0.2, dt)
		o.sway = 0.0
		if (s > 0.3 and not out) or (s > 0.75 and out):
			if o.timer > -100.0:
				_splash(Vector3(p0.x if not out else p1.x, 0.0, p0.z if not out else p1.z), L * 0.5)
				o.timer = -1000.0
		if s >= 1.0:
			o.hop = -1.0
			o.timer = 0.0
			o.leg += 1
		_arrived(o, p)
		return
	var to := leg_to - o.pos
	to.y = 0.0
	var d := to.length()
	var in_water := (not out and o.leg == 0) or (out and o.leg >= 3)
	if in_water:
		speed = k.swim
	if d > 0.05:
		var ny := atan2(to.x, to.z)
		o.yaw = lerp_angle(o.yaw, ny, 1.0 - exp(-dt * (5.0 if not in_water else 2.0)))
		o.pos += to / d * minf(speed * dt, d)
	o.phase += dt * (6.0 if not in_water else 3.0) * (1.6 if o.hurry else 1.0)
	var ground := site.top if flat else terrain.height_at(o.pos.x, o.pos.z)
	if in_water or (not flat and ground < _swim_y(o) + 0.1 * L):
		o.y = move_toward(o.y, maxf(_swim_y(o), ground) if not in_water else _swim_y(o), dt * 1.5)
		o.sway = 0.035
		o.head = move_toward(o.head, 0.45, dt)
		o.pitch = move_toward(o.pitch, 0.0, dt)
	else:
		o.y = ground
		o.sway = -0.03 if k.id == "harbor_seal" else -0.012
		o.head = move_toward(o.head, 0.3, dt)
		o.tail = move_toward(o.tail, 0.15, dt)
		if not flat:
			var f := Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * L * 0.4
			o.pitch = atan2(terrain.height_v(o.pos + f) - terrain.height_v(o.pos - f), L * 0.8)
		else:
			o.pitch = move_toward(o.pitch, 0.0, dt * 2.0)
	o.roll = move_toward(o.roll, 0.0, dt * 2.0)
	if d < 0.08:
		o.leg += 1
		o.timer = 0.0
	_arrived(o, p)


func _arrived(o: Animal, p: Pod) -> void:
	if o.leg < o.path.size():
		return
	if o.state == State.CLIMB:
		o.state = State.REST
		o.pose = Pose.LOOK
		o.timer = rng.randf_range(3.0, 8.0)
		o.sway = 0.0
		return
	# Back in the water.
	if o.spot >= 0:
		p.taken[o.spot] = null
	o.spot = -1
	o.state = State.SWIM
	o.under = o.hurry or rng.randf() < 0.5
	o.breath = rng.randf_range(5.0, 15.0)
	o.timer = rng.randf_range(20.0, 60.0) if o.hurry else rng.randf_range(5.0, 30.0)
	o.hurry = false


# --- Lying up --------------------------------------------------------------------------

func _next_pose(o: Animal) -> void:
	var r := rng.randf()
	var sea_lion := o.kind.id == "sea_lion"
	if r < 0.62:
		o.pose = Pose.SLEEP
		o.timer = rng.randf_range(25.0, 90.0)
		# Sprawled on its side, now and then.
		o.sleep_roll = 0.0
		if sea_lion and rng.randf() < 0.5:
			o.sleep_roll = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.9, 1.3)
		elif not sea_lion and rng.randf() < 0.2:
			o.sleep_roll = (1.0 if rng.randf() < 0.5 else -1.0) * 0.8
	elif r < 0.82:
		o.pose = Pose.LOOK
		o.timer = rng.randf_range(3.0, 9.0)
	elif r < 0.92 and sea_lion:
		o.pose = Pose.SIT
		o.timer = rng.randf_range(10.0, 40.0)
	else:
		o.pose = Pose.SCRATCH
		o.timer = rng.randf_range(2.0, 4.0)
		o.phase = 0.0
	# A shuffle round, now and then.
	if rng.randf() < 0.25:
		o.yaw += rng.randf_range(-0.35, 0.35)


func _rest(o: Animal, p: Pod, dt: float) -> void:
	var k := o.kind
	var site := o.visit.site
	var sp := site.spots[o.spot]
	var L := o.length
	var pose := o.pose
	if p.disturbed < k.alert:
		pose = Pose.LOOK
	var head := 0.05
	var tail := 0.1
	var pitch := 0.0
	var roll := o.sleep_roll if pose == Pose.SLEEP else 0.0
	match pose:
		Pose.SLEEP:
			if o.banana:
				head = 0.4
				tail = 0.5
			# Breathing.
			head += 0.02 * sin(o.phase)
		Pose.LOOK:
			head = 0.75 if k.id == "harbor_seal" else 0.6
			tail = 0.25
		Pose.SIT:
			pitch = 0.45
			head = 0.55
			tail = 0.0
		Pose.SCRATCH:
			roll = 0.5 * sin(o.phase * 1.5)
			tail = 0.6 + 0.3 * sin(o.phase * 9.0)
			head = 0.25
	o.phase += dt * 0.6
	o.yaw = lerp_angle(o.yaw, sp.yaw if absf(angle_difference(o.yaw, sp.yaw)) > 0.4 else o.yaw, 1.0 - exp(-dt * 0.8))
	o.head = move_toward(o.head, head, dt * (2.0 if pose == Pose.LOOK else 0.6))
	o.tail = move_toward(o.tail, tail, dt * 0.8)
	o.pitch = move_toward(o.pitch, pitch, dt * 0.6)
	o.roll = move_toward(o.roll, roll, dt * (0.3 if pose == Pose.SLEEP else 0.7))
	o.sway = 0.0
	var ground := site.top if site.kind != MapData.HaulOut.Kind.BEACH else terrain.height_at(o.pos.x, o.pos.z)
	# Propped up on its fore flippers, the hips stay on the ground.
	o.y = ground + 0.25 * L * sin(maxf(o.pitch, 0.0)) + 0.05 * L * absf(sin(o.roll))
	if site.kind == MapData.HaulOut.Kind.BEACH and pose != Pose.SIT:
		var f := Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * L * 0.4
		o.pitch = atan2(terrain.height_v(o.pos + f) - terrain.height_v(o.pos - f), L * 0.8)


func _splash(at: Vector3, size: float) -> void:
	if _splashes.size() >= MAX_SPLASHES:
		return
	var s := Splash.new()
	s.pos = at
	s.size = size
	_splashes.append(s)


## The visit of the animal nearest `screen` that's showing (or only just went under).
func pick(screen: Vector2, cam: Camera3D) -> Wildlife.Visit:
	var now := Time.get_ticks_msec()
	var best: Wildlife.Visit = null
	var best_d := INF
	for p in _pods:
		if not p.visit.active():
			continue
		for o in p.animals:
			if now - o.shown_ms > CLICK_GRACE:
				continue
			var wp := Vector3(o.pos.x, maxf(o.y, 0.0) + 0.3, o.pos.z)
			if cam.is_position_behind(wp):
				continue
			var reach := maxf(26.0, o.length * 900.0 / cam.global_position.distance_to(wp))
			var d := cam.unproject_position(wp).distance_to(screen)
			if d < reach and d < best_d:
				best_d = d
				best = p.visit
	return best


func _render() -> void:
	var counts := {}
	for p in _pods:
		var kd := p.kind
		var n: int = counts.get(kd.id, 0)
		for o in p.animals:
			if n >= MAX_PER_KIND:
				break
			var b := Basis(Vector3.UP, o.yaw) * Basis(Vector3.RIGHT, -o.pitch) * Basis(Vector3.BACK, o.roll) \
				* Basis.from_scale(Vector3(1.12 if o.bull else 1.0, 1.0, 1.0) * o.length)
			var buf := kd.buf
			var i := n * 20
			buf[i] = b.x.x
			buf[i + 1] = b.y.x
			buf[i + 2] = b.z.x
			buf[i + 3] = o.pos.x
			buf[i + 4] = b.x.y
			buf[i + 5] = b.y.y
			buf[i + 6] = b.z.y
			buf[i + 7] = o.y
			buf[i + 8] = b.x.z
			buf[i + 9] = b.y.z
			buf[i + 10] = b.z.z
			buf[i + 11] = o.pos.z
			buf[i + 12] = o.tint.r
			buf[i + 13] = o.tint.g
			buf[i + 14] = o.tint.b
			buf[i + 15] = 1.0
			buf[i + 16] = o.head
			buf[i + 17] = o.tail
			buf[i + 18] = o.phase
			buf[i + 19] = o.sway
			n += 1
		counts[kd.id] = n
	for kd: Kind in kinds.values():
		var n: int = counts.get(kd.id, 0)
		if n > 0:
			kd.mm.buffer = kd.buf
		kd.mm.visible_instance_count = n
	var k := 0
	for s in _splashes:
		var grow := Vector3(0.5 + s.t, sqrt(s.t) * 0.8 + 0.1, 0.5 + s.t) * s.size
		var i := k * 16
		_splash_buf[i] = grow.x
		_splash_buf[i + 1] = 0.0
		_splash_buf[i + 2] = 0.0
		_splash_buf[i + 3] = s.pos.x
		_splash_buf[i + 4] = 0.0
		_splash_buf[i + 5] = grow.y
		_splash_buf[i + 6] = 0.0
		_splash_buf[i + 7] = 0.0
		_splash_buf[i + 8] = 0.0
		_splash_buf[i + 9] = 0.0
		_splash_buf[i + 10] = grow.z
		_splash_buf[i + 11] = s.pos.z
		_splash_buf[i + 12] = 1.0
		_splash_buf[i + 13] = 1.0
		_splash_buf[i + 14] = 1.0
		_splash_buf[i + 15] = (1.0 - s.t) * (1.0 - s.t)
		k += 1
	_splash_mm.visible_instance_count = k
	if k > 0:
		_splash_mm.buffer = _splash_buf
	if water_mat:
		_clear_foam()


## Tells the water which animals are in it, so it leaves off the lip of foam it
## draws where anything meets the surface: on a back just awash it reads as white
## fur rather than water.
func _clear_foam() -> void:
	var cam := get_viewport().get_camera_3d()
	var bodies: Array = []
	if cam:
		var c := Vector2(cam.global_position.x, cam.global_position.z)
		for p in _pods:
			for o in p.animals:
				if o.y > 0.05 and o.state == State.REST:
					continue
				var d := Vector2(o.pos.x, o.pos.z).distance_squared_to(c)
				if d < FOAM_RANGE * FOAM_RANGE:
					bodies.append([d, o])
	if bodies.size() > MAX_FOAM_CLEAR:
		bodies.sort_custom(func(a: Array, b: Array): return a[0] < b[0])
		bodies.resize(MAX_FOAM_CLEAR)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in bodies.size():
		var o: Animal = bodies[i][1]
		var f := Vector2(sin(o.yaw), cos(o.yaw)) * o.length * 0.5 * cos(o.pitch)
		var at := Vector2(o.pos.x, o.pos.z)
		_foam_clear[i] = Vector4(at.x, at.y, f.x, f.y) / WakeField.UNIT
		var r := f.length() * 1.3 + 1.0
		lo = lo.min(at - Vector2(r, r))
		hi = hi.max(at + Vector2(r, r))
	water_mat.set_shader_parameter("seal_count", bodies.size())
	if not bodies.is_empty():
		water_mat.set_shader_parameter("seal_body", _foam_clear)
		water_mat.set_shader_parameter("seal_bounds", Vector4(lo.x, lo.y, hi.x, hi.y) / WakeField.UNIT)
