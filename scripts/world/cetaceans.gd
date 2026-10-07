class_name Cetaceans
extends Node3D
## Draws the orcas, whales and porpoises of Wildlife's visits, one multimesh per kind.
##
## Wildlife steers each group (Visit.pos / heading); every animal keeps a loose
## slot around it, calves tucked in at their mother's flank. Each kind breathes
## its own way (Kind): a run of rolling breaths, a blow at the top of each, then a
## dive. Orcas and whales breathe and dive together, porpoises each on their own.
## Any roll may turn into a breach (with a splash) or, now and then, a spyhop; a
## humpback or gray whale going down for a long dive often lifts its flukes clear
## of the water. Gray whales feeding on the bottom come up in a cloud of mud, and
## Dall's porpoises going fast throw up a rooster tail of spray. When the visit
## ends they dive and don't come back up.

enum State { UNDER, ROLL, BREACH, SPYHOP, FLUKE }

const MAX_PER_KIND := 32
const MAX_PUFFS := 64
# Below this (and the water's opaque) they're out of sight; the sea floor is at -5.5.
const DIVE_Y := -5.0
# How long after going under an animal can still be clicked (real ms).
const CLICK_GRACE := 1500
const MUD := Color(0.47, 0.42, 0.32, 0.55)
const SPRAY := Color(0.95, 0.97, 1.0, 0.8)


## How a species looks and breathes.
class Kind:
	var id := ""
	var mesh: ArrayMesh
	var scale := 1.0                    # drawn this much bigger than life
	var breaths := Vector2i(2, 5)       # breaths between dives
	var gap := Vector2(2.5, 5.0)        # under between breaths
	var dive := Vector2(14.0, 30.0)
	var together := true                # the group breathes and dives as one
	var breach := 0.06                  # chance a breath is a breach
	var spyhop := 0.035
	var fluke := 0.0                    # chance the last breath before a dive shows the flukes
	var blow := Vector3(1.0, 3.2, 1.0)  # size of the blow, per 8 m of animal (zero: none to see)
	var blow_life := 1.6
	var heart := false                  # a gray whale's V-shaped blow, from both blowholes
	var roll := Vector2(1.6, 0.12)      # a breath's roll takes x + y * length
	var spread := Vector2(11.0, 14.0)   # how far about the group's centre they swim
	var spacing := 7.0                  # and kept apart
	var fin := 0.12                     # dorsal fin height (body lengths), as cetacean.gdshader takes it
	var sweep := 1.0
	var tail := 0.035                   # tail beat (body lengths)
	var spray := false
	var mud := false
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
	var length := 6.0           # metres, as drawn
	var fin := 0.12             # dorsal fin height, body lengths
	var sweep := 1.0            # 0 upright .. 1 curved back
	var offset := Vector3.ZERO  # slot in the group's frame (calves: in the mother's)
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
	var down := 0.0             # on its own dive (kinds that don't dive together)
	var blown := false
	var tail := 0.0
	var tail_amp := 0.035
	var spray_t := 0.0
	var shown_ms := -100000     # last time any of it was above water


class Pod:
	var visit: Wildlife.Visit
	var kind: Kind
	var animals: Array[Animal] = []
	var dive := 0.5             # > 0: everyone's down, for this long
	var gone := 0.0             # after the visit ends


class Puff:
	var pos := Vector3.ZERO
	var size := Vector3.ONE
	var color := Color.WHITE
	var flat := false           # a patch on the water (mud), not a plume
	var t := 0.0
	var life := 1.4


var wildlife: Wildlife
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var kinds := {}                 # species id -> Kind
var _pods: Array[Pod] = []
var _puffs: Array[Puff] = []
var _puff_mm: MultiMesh
var _puff_buf := PackedFloat32Array()


func setup(w: Wildlife, t: Terrain) -> void:
	name = "Cetaceans"
	wildlife = w
	terrain = t
	rng.seed = w.sim.map.map_seed * 29 + 3
	# Bigger than life (orcas and porpoises) so they read next to the ferries.
	for k: Kind in [
		Kind.new("orca", Models.orca(), {"scale": 1.3}),
		Kind.new("humpback", Models.humpback(), {"breaths": Vector2i(3, 6), "gap": Vector2(4.0, 7.0),
			"dive": Vector2(25.0, 45.0), "breach": 0.03, "spyhop": 0.0, "fluke": 0.75,
			"blow": Vector3(2.0, 3.4, 2.0), "blow_life": 2.4, "roll": Vector2(2.4, 0.16),
			"spread": Vector2(22.0, 26.0), "spacing": 18.0, "fin": 0.025, "sweep": 0.6, "tail": 0.025}),
		Kind.new("gray", Models.gray_whale(), {"breaths": Vector2i(3, 5), "gap": Vector2(3.0, 5.0),
			"dive": Vector2(18.0, 32.0), "breach": 0.01, "spyhop": 0.02, "fluke": 0.35,
			"blow": Vector3(0.7, 2.3, 0.7), "blow_life": 2.0, "heart": true, "roll": Vector2(2.2, 0.15),
			"spread": Vector2(18.0, 20.0), "spacing": 16.0, "fin": 0.012, "sweep": 0.3, "tail": 0.025,
			"mud": true}),
		Kind.new("dalls_porpoise", Models.dalls_porpoise(), {"scale": 1.4, "breaths": Vector2i(3, 6),
			"gap": Vector2(0.7, 1.4), "dive": Vector2(5.0, 12.0), "together": false, "breach": 0.0,
			"spyhop": 0.0, "blow": Vector3.ZERO, "roll": Vector2(0.55, 0.08), "spread": Vector2(4.0, 5.0),
			"spacing": 2.5, "fin": 0.09, "sweep": 0.25, "tail": 0.05, "spray": true}),
		Kind.new("harbor_porpoise", Models.harbor_porpoise(), {"scale": 1.5, "breaths": Vector2i(2, 4),
			"gap": Vector2(1.4, 2.8), "dive": Vector2(8.0, 20.0), "together": false, "breach": 0.0,
			"spyhop": 0.0, "blow": Vector3.ZERO, "roll": Vector2(0.9, 0.14), "spread": Vector2(9.0, 10.0),
			"spacing": 4.0, "fin": 0.06, "sweep": 0.15, "tail": 0.04}),
	]:
		kinds[k.id] = k
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cetacean.gdshader")
		k.mm = MultiMesh.new()
		k.mm.transform_format = MultiMesh.TRANSFORM_3D
		k.mm.use_custom_data = true
		k.mm.mesh = k.mesh
		k.mm.instance_count = MAX_PER_KIND
		k.mm.visible_instance_count = 0
		k.buf.resize(MAX_PER_KIND * 16)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = k.id
		mmi.multimesh = k.mm
		mmi.material_override = mat
		add_child(mmi)

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
	if not kinds.has(v.species.id):
		return
	var k: Kind = kinds[v.species.id]
	var p := Pod.new()
	p.visit = v
	p.kind = k
	var used: Array[Vector3] = []
	for m in v.members:
		var o := Animal.new()
		o.visit = v
		o.kind = k
		o.length = m.length * k.scale
		o.side = 1.0 if rng.randf() < 0.5 else -1.0
		o.fin = k.fin
		o.sweep = k.sweep
		o.tail_amp = k.tail
		if k.id == "orca":
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
		if m.mother >= 0 and m.mother < p.animals.size():
			o.mother = p.animals[m.mother]
			var f := o.mother.length / 7.5
			o.offset = Vector3(o.side * rng.randf_range(2.2, 3.2) * f, 0.0, rng.randf_range(-1.8, 0.0) * f)
		else:
			# Spread out, but not on top of one another; a bull often off to one side.
			var spread := k.spread.x * (1.6 if m.role == Wildlife.Role.BULL else 1.0)
			for attempt in 12:
				o.offset = Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-k.spread.y, k.spread.y * 0.7))
				var ok := true
				for u in used:
					if u.distance_to(o.offset) < k.spacing:
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
		if not k.together:
			o.down = rng.randf_range(0.2, k.dive.x * 0.5)
		p.animals.append(o)
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
	var k := p.kind
	if ending:
		p.gone += dt
		if p.gone > 8.0:
			return false
	elif not k.together:
		for o in p.animals:
			if o.down > 0.0:
				o.down -= dt
				if o.down <= 0.0:
					o.breaths = rng.randi_range(k.breaths.x, k.breaths.y)
					o.wait = rng.randf_range(0.0, 0.6)
			elif o.breaths <= 0 and o.state == State.UNDER:
				o.down = rng.randf_range(k.dive.x, k.dive.y)
	elif p.dive > 0.0:
		p.dive -= dt
		if p.dive <= 0.0:
			for o in p.animals:
				o.breaths = rng.randi_range(k.breaths.x, k.breaths.y)
				o.wait = rng.randf_range(0.0, 3.5)
				# Up from feeding on the bottom, in a cloud of mud.
				if k.mud and p.visit.phase == Wildlife.Phase.FORAGE and rng.randf() < 0.7:
					_puff(o.pos, Vector3(0.55, 0.02, 0.55) * o.length, rng.randf_range(25.0, 40.0), MUD, true)
	else:
		var done := true
		for o in p.animals:
			if o.breaths > 0 or o.state != State.UNDER:
				done = false
				break
		if done:
			p.dive = rng.randf_range(k.dive.x, k.dive.y)
	for o in p.animals:
		_tick_animal(o, p, dt, ending)
	return true


func _tick_animal(o: Animal, p: Pod, dt: float, ending: bool) -> void:
	var v := o.visit
	var k := o.kind
	var L := o.length
	var under_y := maxf(-0.42 * L, DIVE_Y + 0.4)
	# Swim: hold the slot, nudged back toward the group's track if the shallows are ahead.
	var fwd := Vector3(sin(v.heading), 0.0, cos(v.heading))
	var slot := (o.mother.pos + Basis(Vector3.UP, o.mother.yaw) * o.offset) if o.mother \
		else v.pos + Basis(Vector3.UP, v.heading) * o.offset
	# Close up toward the middle of the group (which keeps to water deep enough)
	# where the slot is in the shallows.
	for i in 5:
		if terrain.height_at(slot.x, slot.z) <= v.species.depth:
			break
		slot = slot.lerp(v.pos, 0.4)
	var want := fwd * v.speed + (slot - o.pos) * 0.35
	want.y = 0.0
	if want.length_squared() > 0.01:
		var ahead := o.pos + want.normalized() * maxf(6.0, L * 0.6)
		if terrain.height_at(ahead.x, ahead.z) > v.species.depth + 0.6:
			var back := v.pos - o.pos
			back.y = 0.0
			want += back.normalized() * v.speed * 1.5
	if o.state == State.SPYHOP:
		want = Vector3.ZERO
	o.vel = o.vel.move_toward(want.limit_length(v.speed * 1.7 + 1.0), 2.5 * dt)
	if _shoaling(o, o.vel, dt):
		# Never on into the shallows: slide off along the shore, turning back
		# toward open water if need be, or (boxed in) stop.
		var vel := o.vel
		o.vel = Vector3.ZERO
		for i in range(1, 13):
			var turned := Basis(Vector3.UP, (1.0 if i % 2 == 0 else -1.0) * ceili(i / 2.0) * 0.45) * vel
			if not _shoaling(o, turned, dt):
				o.vel = turned * (1.0 - i * 0.05)
				break
	o.pos += o.vel * dt
	var spd := Vector2(o.vel.x, o.vel.z).length()
	if spd > 0.3:
		var ny := atan2(o.vel.x, o.vel.z)
		var turn := angle_difference(o.yaw, ny)
		o.yaw = lerp_angle(o.yaw, ny, 1.0 - exp(-dt * 2.0))
		if o.state == State.UNDER or o.state == State.ROLL:
			o.bank = lerpf(o.bank, clampf(-turn * 0.8, -0.4, 0.4), 1.0 - exp(-dt * 2.0))
	o.tail += dt * TAU * (0.45 + spd * 0.12) * (8.0 / maxf(L, 2.0)) ** 0.5
	o.tail_amp = move_toward(o.tail_amp, 0.0 if o.state == State.FLUKE else k.tail, dt * 0.1)

	match o.state:
		State.UNDER:
			var down := ending or (p.dive > 0.0 if k.together else o.down > 0.0)
			var target := minf(DIVE_Y, -0.55 * L) if down else under_y
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
				_blow(o)
			if s >= 1.0:
				_breathed(o, under_y)
		State.FLUKE:
			# A last breath, the back arching over, then the flukes up and straight down.
			var s := _advance(o, dt)
			var rise := smoothstep(0.0, 0.2, s)
			o.y = lerpf(lerpf(o.y0, -0.04 * L, rise), -0.55 * L, smoothstep(0.3, 1.0, s))
			o.pitch = 0.15 * sin(PI * clampf(s / 0.3, 0.0, 1.0)) - 1.35 * smoothstep(0.3, 0.9, s)
			o.bank = move_toward(o.bank, 0.0, dt * 1.5)
			if not o.blown and s > 0.12:
				o.blown = true
				_blow(o)
			if s >= 1.0:
				o.state = State.UNDER
				o.breaths = 0
		State.BREACH:
			var s := _advance(o, dt)
			o.y = lerpf(o.y0 if s < 0.5 else under_y, 0.5 * L, sin(PI * s))
			o.pitch = 1.2 * cos(PI * s)
			o.bank = o.side * 1.7 * smoothstep(0.3, 0.9, s)
			if not o.blown and s > 0.82:
				o.blown = true
				_puff(o.pos, Vector3(3.0, 1.6, 3.0) * L / 8.0, 1.2 + L * 0.05)
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
	# A rooster tail of spray off a porpoise going flat out at the surface.
	if k.spray and spd > 6.0 and o.y > -0.15 * L:
		o.spray_t -= dt
		if o.spray_t <= 0.0:
			o.spray_t = 0.18
			var back := Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * -L * 0.25
			_puff(o.pos + back, Vector3(0.5, 1.1, 0.5) * L * 0.5, 0.6, SPRAY)
	# Anything showing above the surface (fin, back or more)?
	if o.y + (0.09 + o.fin) * L > 0.0 or o.state != State.UNDER:
		o.shown_ms = Time.get_ticks_msec()


## Whether moving at `vel` takes the animal (its middle or its nose) into water
## shallower than its kind swims in, and shallower than where it is now.
func _shoaling(o: Animal, vel: Vector3, dt: float) -> bool:
	if vel.length_squared() < 0.0001:
		return false
	var depth := o.visit.species.depth
	var ahead := vel.normalized() * o.length * 0.5
	var q := o.pos + vel * dt
	var g := terrain.height_at(q.x, q.z)
	if g > depth and g > terrain.height_at(o.pos.x, o.pos.z):
		return true
	# The nose may go a little shallower than the body.
	var n := terrain.height_at(q.x + ahead.x, q.z + ahead.z)
	return n > depth + 1.5 and n > terrain.height_at(o.pos.x + ahead.x, o.pos.z + ahead.z)


func _advance(o: Animal, dt: float) -> float:
	o.t += dt
	return minf(o.t / o.dur, 1.0)


func _surface(o: Animal) -> void:
	var k := o.kind
	var r := rng.randf()
	o.t = 0.0
	o.y0 = o.y
	o.blown = false
	var calf := o.mother != null
	if o.breaths == 1 and rng.randf() < k.fluke and not calf:
		o.state = State.FLUKE
		o.dur = 3.0 + 0.14 * o.length
	elif r < k.breach * (1.5 if calf else 1.0):
		o.state = State.BREACH
		o.dur = 2.4 + 0.05 * o.length
	elif r < k.breach + k.spyhop and not calf:
		o.state = State.SPYHOP
		o.dur = rng.randf_range(4.5, 6.5)
	else:
		o.state = State.ROLL
		o.dur = k.roll.x + k.roll.y * o.length


func _breathed(o: Animal, under_y: float) -> void:
	o.state = State.UNDER
	o.y = under_y
	o.breaths -= 1
	o.wait = rng.randf_range(o.kind.gap.x, o.kind.gap.y)


## The blow, from the blowhole, as big as the animal (two side by side for a gray whale).
func _blow(o: Animal) -> void:
	var k := o.kind
	if k.blow == Vector3.ZERO:
		return
	var fwd := Vector3(sin(o.yaw), 0.0, cos(o.yaw))
	var at := o.pos + fwd * o.length * 0.32
	var size := k.blow * o.length / 8.0
	if k.heart:
		var lat := Vector3(fwd.z, 0.0, -fwd.x) * o.length * 0.035
		_puff(at + lat, size, k.blow_life)
		_puff(at - lat, size, k.blow_life)
	else:
		_puff(at, size, k.blow_life)


func _puff(at: Vector3, size: Vector3, life: float, color := Color.WHITE, flat := false) -> void:
	if _puffs.size() >= MAX_PUFFS:
		return
	var pf := Puff.new()
	pf.pos = Vector3(at.x, 0.03 if flat else 0.0, at.z)
	pf.size = size
	pf.life = life
	pf.color = color
	pf.flat = flat
	_puffs.append(pf)


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
	var counts := {}
	for p in _pods:
		var kd := p.kind
		var n: int = counts.get(kd.id, 0)
		for o in p.animals:
			if n >= MAX_PER_KIND:
				break
			var b := (Basis(Vector3.UP, o.yaw) * Basis(Vector3.RIGHT, -o.pitch) * Basis(Vector3.BACK, o.bank)).scaled(Vector3.ONE * o.length)
			var buf := kd.buf
			var i := n * 16
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
			buf[i + 12] = o.fin
			buf[i + 13] = o.sweep
			buf[i + 14] = o.tail
			buf[i + 15] = o.tail_amp
			n += 1
		counts[kd.id] = n
	for kd: Kind in kinds.values():
		var n: int = counts.get(kd.id, 0)
		if n > 0:
			kd.mm.buffer = kd.buf
		kd.mm.visible_instance_count = n
	# Blows and splashes: shoot up, spread, fade. Mud spreads slowly on the water.
	var k := 0
	for pf in _puffs:
		var s := pf.t / pf.life
		var grow := Vector3(0.6 + s * 0.7, 1.0, 0.6 + s * 0.7) * pf.size if pf.flat \
			else Vector3(0.5 + s * 0.8, sqrt(s) * 1.1 + 0.1, 0.5 + s * 0.8) * pf.size
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
		var a := (1.0 - s) * (1.0 - s) if not pf.flat else smoothstep(0.0, 0.08, s) * (1.0 - s)
		_puff_buf[i + 12] = pf.color.r
		_puff_buf[i + 13] = pf.color.g
		_puff_buf[i + 14] = pf.color.b
		_puff_buf[i + 15] = a * pf.color.a
		k += 1
	_puff_mm.visible_instance_count = k
	if k > 0:
		_puff_mm.buffer = _puff_buf
