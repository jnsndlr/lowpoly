class_name Orcas
extends Node3D
## Draws the orca pods of Wildlife's visits, every orca in one multimesh.
##
## Wildlife steers each pod (Visit.pos / heading); every orca keeps a loose slot
## around it, calves tucked in at their mother's flank. The pod breathes together:
## a few rolling breaths each, staggered, with a blow at the top of each, then
## everyone dives for a while. Any roll may turn into a breach (with a splash) or,
## now and then, a spyhop. When the visit ends they dive and don't come back up.

enum State { UNDER, ROLL, BREACH, SPYHOP }

# Bigger than life so they read next to the ferries.
const SCALE := 1.3
const MAX_ORCAS := 32
const MAX_PUFFS := 32
const BREATHS := Vector2i(2, 5)
const BREATH_GAP := Vector2(2.5, 5.0)
const DIVE_TIME := Vector2(14.0, 30.0)
const BREACH_CHANCE := 0.06
const SPYHOP_CHANCE := 0.035
# Below this (and the water's opaque) they're out of sight; the sea floor is at -5.5.
const DIVE_Y := -5.0
# How long after going under an orca can still be clicked (real ms).
const CLICK_GRACE := 1500


class Orca:
	var visit: Wildlife.Visit
	var mother: Orca
	var length := 6.0           # metres, as drawn
	var fin := 0.12             # dorsal fin height, body lengths
	var sweep := 1.0            # 0 upright .. 1 curved back
	var offset := Vector3.ZERO  # slot in the pod's frame (calves: in the mother's)
	var pos := Vector3.ZERO     # x, z used; height in `y`
	var vel := Vector3.ZERO
	var y := DIVE_Y
	var y0 := 0.0               # height when the current move began
	var yaw := 0.0
	var pitch := 0.0
	var bank := 0.0
	var side := 1.0             # which way it rolls when breaching
	var state := State.UNDER
	var t := 0.0
	var dur := 1.0
	var wait := 0.0             # under: until the next breath
	var breaths := 0
	var blown := false
	var tail := 0.0
	var shown_ms := -100000     # last time any of it was above water


class Pod:
	var visit: Wildlife.Visit
	var orcas: Array[Orca] = []
	var dive := 0.5             # > 0: everyone's down, for this long
	var gone := 0.0             # after the visit ends


class Puff:
	var pos := Vector3.ZERO
	var size := Vector3.ONE
	var t := 0.0
	var life := 1.4


var wildlife: Wildlife
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var _pods: Array[Pod] = []
var _puffs: Array[Puff] = []
var _mm: MultiMesh
var _puff_mm: MultiMesh
var _buf := PackedFloat32Array()
var _puff_buf := PackedFloat32Array()


func setup(w: Wildlife, t: Terrain) -> void:
	name = "Orcas"
	wildlife = w
	terrain = t
	rng.seed = w.sim.map.map_seed * 29 + 3
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/orca.gdshader")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = Models.orca()
	_mm.instance_count = MAX_ORCAS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	add_child(mmi)
	_buf.resize(MAX_ORCAS * 16)

	_puff_mm = MultiMesh.new()
	_puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	_puff_mm.use_colors = true
	_puff_mm.mesh = Models.spout()
	_puff_mm.instance_count = MAX_PUFFS
	_puff_mm.visible_instance_count = 0
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = _puff_mm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pmi)
	_puff_buf.resize(MAX_PUFFS * 16)

	w.visit_started.connect(_on_visit)
	for v in w.active_visits():
		_on_visit(v)


func _on_visit(v: Wildlife.Visit) -> void:
	if v.species.id != "orca":
		return
	var p := Pod.new()
	p.visit = v
	var used: Array[Vector3] = []
	for m in v.members:
		var o := Orca.new()
		o.visit = v
		o.length = m.length * SCALE
		o.side = 1.0 if rng.randf() < 0.5 else -1.0
		match m.role:
			Wildlife.Role.BULL:
				o.fin = 0.21
				o.sweep = 0.1
			Wildlife.Role.COW:
				o.fin = 0.12
			Wildlife.Role.JUVENILE:
				o.fin = 0.11
				o.sweep = 0.7
			_:
				o.fin = 0.09
		if m.mother >= 0 and m.mother < p.orcas.size():
			o.mother = p.orcas[m.mother]
			o.offset = Vector3(o.side * rng.randf_range(2.2, 3.2), 0.0, rng.randf_range(-1.8, 0.0))
		else:
			# Spread out, but not on top of one another; a bull often off to one side.
			var spread := 18.0 if m.role == Wildlife.Role.BULL else 11.0
			for attempt in 12:
				o.offset = Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-14.0, 10.0))
				var ok := true
				for u in used:
					if u.distance_to(o.offset) < 7.0:
						ok = false
						break
				if ok:
					break
			used.append(o.offset)
		var base := v.pos if o.mother == null else o.mother.pos
		o.yaw = v.heading
		o.pos = base + Basis(Vector3.UP, o.yaw) * o.offset
		o.vel = Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * v.speed
		o.y = DIVE_Y
		p.orcas.append(o)
	_pods.append(p)


func _process(delta: float) -> void:
	if delta > 0.0:
		for i in range(_pods.size() - 1, -1, -1):
			if not _tick_pod(_pods[i], delta):
				_pods.remove_at(i)
		for i in range(_puffs.size() - 1, -1, -1):
			_puffs[i].t += delta
			if _puffs[i].t >= _puffs[i].life:
				_puffs.remove_at(i)
	_render()


## False once the pod has gone for good.
func _tick_pod(p: Pod, dt: float) -> bool:
	var ending := not p.visit.active()
	if ending:
		p.gone += dt
		if p.gone > 8.0:
			return false
	elif p.dive > 0.0:
		p.dive -= dt
		if p.dive <= 0.0:
			for o in p.orcas:
				o.breaths = rng.randi_range(BREATHS.x, BREATHS.y)
				o.wait = rng.randf_range(0.0, 3.5)
	else:
		var done := true
		for o in p.orcas:
			if o.breaths > 0 or o.state != State.UNDER:
				done = false
				break
		if done:
			p.dive = rng.randf_range(DIVE_TIME.x, DIVE_TIME.y)
	for o in p.orcas:
		_tick_orca(o, p, dt, ending)
	return true


func _tick_orca(o: Orca, p: Pod, dt: float, ending: bool) -> void:
	var v := o.visit
	var L := o.length
	var under_y := maxf(-0.42 * L, DIVE_Y + 0.4)
	# Swim: hold the slot, nudged back toward the pod's track if the shallows are ahead.
	var fwd := Vector3(sin(v.heading), 0.0, cos(v.heading))
	var slot := (o.mother.pos + Basis(Vector3.UP, o.mother.yaw) * o.offset) if o.mother \
		else v.pos + Basis(Vector3.UP, v.heading) * o.offset
	var want := fwd * v.speed + (slot - o.pos) * 0.35
	want.y = 0.0
	if want.length_squared() > 0.01:
		var ahead := o.pos + want.normalized() * 6.0
		if terrain.height_at(ahead.x, ahead.z) > -2.0:
			var back := v.pos - o.pos
			back.y = 0.0
			want += back.normalized() * v.speed * 1.5
	if o.state == State.SPYHOP:
		want = Vector3.ZERO
	o.vel = o.vel.move_toward(want.limit_length(v.speed * 1.7 + 1.0), 2.5 * dt)
	o.pos += o.vel * dt
	var spd := Vector2(o.vel.x, o.vel.z).length()
	if spd > 0.3:
		var ny := atan2(o.vel.x, o.vel.z)
		var turn := angle_difference(o.yaw, ny)
		o.yaw = lerp_angle(o.yaw, ny, 1.0 - exp(-dt * 2.0))
		if o.state == State.UNDER or o.state == State.ROLL:
			o.bank = lerpf(o.bank, clampf(-turn * 0.8, -0.4, 0.4), 1.0 - exp(-dt * 2.0))
	o.tail += dt * TAU * (0.45 + spd * 0.12)

	match o.state:
		State.UNDER:
			var down := ending or p.dive > 0.0
			var target := DIVE_Y if down else under_y
			o.y = move_toward(o.y, target, dt * (1.2 if down else 2.0))
			o.pitch = move_toward(o.pitch, -0.25 if o.y > target + 0.2 else 0.0, dt * 0.8)
			o.bank = move_toward(o.bank, 0.0, dt * 1.5)
			if not down and o.breaths > 0:
				o.wait -= dt
				if o.wait <= 0.0:
					_surface(o)
		State.ROLL:
			var s := _advance(o, dt)
			o.y = lerpf(o.y0 if s < 0.5 else under_y, -0.04 * L, sin(PI * s))
			o.pitch = 0.35 * sin(TAU * s)
			if not o.blown and s > 0.3:
				o.blown = true
				_puff(o.pos + Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * L * 0.38, Vector3(1.0, 3.2, 1.0) * L / 8.0, 1.6)
			if s >= 1.0:
				_breathed(o, under_y)
		State.BREACH:
			var s := _advance(o, dt)
			o.y = lerpf(o.y0 if s < 0.5 else under_y, 0.5 * L, sin(PI * s))
			o.pitch = 1.2 * cos(PI * s)
			o.bank = o.side * 1.7 * smoothstep(0.3, 0.9, s)
			if not o.blown and s > 0.82:
				o.blown = true
				_puff(o.pos, Vector3(3.0, 1.6, 3.0) * L / 8.0, 1.2)
			if s >= 1.0:
				_breathed(o, under_y)
		State.SPYHOP:
			var s := _advance(o, dt)
			var up := smoothstep(0.0, 0.25, s) * (1.0 - smoothstep(0.75, 1.0, s))
			o.pitch = 1.45 * up
			o.y = lerpf(o.y0 if s < 0.5 else under_y, -0.27 * L, up)
			o.yaw += 0.25 * dt * o.side
			if s >= 1.0:
				_breathed(o, under_y)
	# Anything showing above the surface (fin, back or more)?
	if o.y + (0.09 + o.fin) * L > 0.0 or o.state != State.UNDER:
		o.shown_ms = Time.get_ticks_msec()


func _advance(o: Orca, dt: float) -> float:
	o.t += dt
	return minf(o.t / o.dur, 1.0)


func _surface(o: Orca) -> void:
	var r := rng.randf()
	o.t = 0.0
	o.y0 = o.y
	o.blown = false
	var calf := o.mother != null
	if r < BREACH_CHANCE * (1.5 if calf else 1.0):
		o.state = State.BREACH
		o.dur = 2.4 + 0.05 * o.length
	elif r < BREACH_CHANCE + SPYHOP_CHANCE and not calf:
		o.state = State.SPYHOP
		o.dur = rng.randf_range(4.5, 6.5)
	else:
		o.state = State.ROLL
		o.dur = 1.6 + 0.12 * o.length


func _breathed(o: Orca, under_y: float) -> void:
	o.state = State.UNDER
	o.y = under_y
	o.breaths -= 1
	o.wait = rng.randf_range(BREATH_GAP.x, BREATH_GAP.y)


func _puff(at: Vector3, size: Vector3, life: float) -> void:
	if _puffs.size() >= MAX_PUFFS:
		return
	var pf := Puff.new()
	pf.pos = Vector3(at.x, 0.0, at.z)
	pf.size = size
	pf.life = life
	_puffs.append(pf)


## The visit of the orca nearest `screen` that's showing (or only just went under).
func pick(screen: Vector2, cam: Camera3D) -> Wildlife.Visit:
	var now := Time.get_ticks_msec()
	var best: Wildlife.Visit = null
	var best_d := INF
	for p in _pods:
		if not p.visit.active():
			continue
		for o in p.orcas:
			if now - o.shown_ms > CLICK_GRACE:
				continue
			var wp := Vector3(o.pos.x, maxf(o.y, 0.0) + 0.5, o.pos.z)
			if cam.is_position_behind(wp):
				continue
			var reach := maxf(30.0, o.length * 900.0 / cam.global_position.distance_to(wp))
			var d := cam.unproject_position(wp).distance_to(screen)
			if d < reach and d < best_d:
				best_d = d
				best = p.visit
	return best


func _render() -> void:
	var k := 0
	for p in _pods:
		for o in p.orcas:
			if k >= MAX_ORCAS:
				break
			var b := (Basis(Vector3.UP, o.yaw) * Basis(Vector3.RIGHT, -o.pitch) * Basis(Vector3.BACK, o.bank)).scaled(Vector3.ONE * o.length)
			var i := k * 16
			_buf[i] = b.x.x
			_buf[i + 1] = b.y.x
			_buf[i + 2] = b.z.x
			_buf[i + 3] = o.pos.x
			_buf[i + 4] = b.x.y
			_buf[i + 5] = b.y.y
			_buf[i + 6] = b.z.y
			_buf[i + 7] = o.y
			_buf[i + 8] = b.x.z
			_buf[i + 9] = b.y.z
			_buf[i + 10] = b.z.z
			_buf[i + 11] = o.pos.z
			_buf[i + 12] = o.fin
			_buf[i + 13] = o.sweep
			_buf[i + 14] = o.tail
			_buf[i + 15] = 0.035
			k += 1
	_mm.buffer = _buf
	_mm.visible_instance_count = k
	# Blows and splashes: shoot up, spread, fade.
	k = 0
	for pf in _puffs:
		var s := pf.t / pf.life
		var grow := Vector3(0.5 + s * 0.8, sqrt(s) * 1.1 + 0.1, 0.5 + s * 0.8) * pf.size
		var i := k * 16
		_puff_buf[i] = grow.x
		_puff_buf[i + 1] = 0.0
		_puff_buf[i + 2] = 0.0
		_puff_buf[i + 3] = pf.pos.x
		_puff_buf[i + 4] = 0.0
		_puff_buf[i + 5] = grow.y
		_puff_buf[i + 6] = 0.0
		_puff_buf[i + 7] = pf.pos.y
		_puff_buf[i + 8] = 0.0
		_puff_buf[i + 9] = 0.0
		_puff_buf[i + 10] = grow.z
		_puff_buf[i + 11] = pf.pos.z
		var a := (1.0 - s) * (1.0 - s)
		_puff_buf[i + 12] = 1.0
		_puff_buf[i + 13] = 1.0
		_puff_buf[i + 14] = 1.0
		_puff_buf[i + 15] = a
		k += 1
	_puff_mm.visible_instance_count = k
	if k > 0:
		_puff_mm.buffer = _puff_buf
