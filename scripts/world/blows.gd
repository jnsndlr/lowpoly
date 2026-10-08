class_name Blows
extends Node3D
## Whale blows as particles: a column of soft mist shot up from the blowhole that
## billows out as it slows, hangs, and drifts off downwind, with a spatter of
## heavier drops falling back to the water. Cetaceans calls blow() at the top of a
## breath; a pool of one-shot emitters is reused round-robin.

const POOL := 24
const MIST := 220
const DROPS := 36
const MIST_COLOR := Color(0.93, 0.95, 0.97)
# How long the column takes to reach its full height.
const RISE := 0.55
# The breeze's push on hanging mist (m/s^2).
const DRIFT := 1.1

var _mist: Array[GPUParticles3D] = []
var _drops: Array[GPUParticles3D] = []
var _next := 0


func _init() -> void:
	name = "Blows"
	var mist_draw := _quad(_soft_texture(0.0))
	var drop_draw := _quad(_soft_texture(0.5))
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(0.2, 0.8))
	grow.add_point(Vector2(1.0, 2.2))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.06, 0.35, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	var drop_fade := Gradient.new()
	drop_fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	drop_fade.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	var drop_fade_tex := GradientTexture1D.new()
	drop_fade_tex.gradient = drop_fade
	for i in POOL:
		var m := _emitter(MIST, mist_draw)
		var pm: ParticleProcessMaterial = m.process_material
		pm.scale_curve = grow_tex
		pm.color_ramp = fade_tex
		pm.lifetime_randomness = 0.45
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_mist.append(m)
		var d := _emitter(DROPS, drop_draw)
		var dm: ParticleProcessMaterial = d.process_material
		dm.color_ramp = drop_fade_tex
		dm.lifetime_randomness = 0.3
		dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_drops.append(d)


## A blow `size.x` wide and `size.y` tall at `at` (on the water), lasting about
## `life` seconds. `lean` tips the column sideways (a gray whale's V); the mist
## drifts toward `downwind` (unit, horizontal).
func blow(at: Vector3, size: Vector3, life: float, lean := Vector3.ZERO, downwind := Vector3.ZERO) -> void:
	var m := _mist[_next]
	var d := _drops[_next]
	_next = (_next + 1) % POOL
	var w := size.x
	var h := size.y
	var up := (Vector3.UP + lean).normalized()
	var v0 := 2.0 * h / RISE
	var drift := downwind * DRIFT
	var reach := drift.length() * life * life * 0.8 + w * 2.0

	var pm: ParticleProcessMaterial = m.process_material
	pm.direction = up
	pm.spread = rad_to_deg(atan(w * 0.6 / h))
	pm.initial_velocity_min = v0 * 0.2
	pm.initial_velocity_max = v0
	# Damping brings each puff to rest at its own height, filling the column.
	pm.damping_min = v0 / RISE * 0.85
	pm.damping_max = v0 / RISE * 1.1
	pm.gravity = drift + Vector3(0.0, -0.12 * h, 0.0)
	pm.emission_sphere_radius = w * 0.1
	pm.scale_min = w * 0.35
	pm.scale_max = w * 0.75
	pm.color = MIST_COLOR
	m.lifetime = life * 1.6
	m.visibility_aabb = AABB(Vector3(-reach, -1.0, -reach), Vector3(reach * 2.0, h * 1.8 + 1.0, reach * 2.0))
	m.global_position = at
	m.restart()

	var dm: ParticleProcessMaterial = d.process_material
	dm.direction = up
	dm.spread = rad_to_deg(atan(w * 0.6 / h))
	dm.initial_velocity_min = v0 * 0.25
	dm.initial_velocity_max = v0 * 0.55
	dm.gravity = Vector3(0.0, -9.8, 0.0)
	dm.emission_sphere_radius = w * 0.06
	dm.scale_min = w * 0.04
	dm.scale_max = w * 0.09
	dm.color = MIST_COLOR
	d.lifetime = maxf(v0 * 0.55 / 9.8 * 2.2, 0.6)
	d.visibility_aabb = AABB(Vector3(-w * 2.0, -1.0, -w * 2.0), Vector3(w * 4.0, h * 1.5 + 1.0, w * 4.0))
	d.global_position = at
	d.restart()


func _emitter(amount: int, draw: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.75
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = ParticleProcessMaterial.new()
	p.draw_pass_1 = draw
	add_child(p)
	return p


## A camera-facing quad with a soft round sprite, its colour and fade from the particle.
func _quad(tex: Texture2D) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	# Fade out where a puff meets the water rather than cutting a hard line.
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.6
	var q := QuadMesh.new()
	q.material = mat
	return q


## A white disc fading to clear at its rim; `core` keeps more of it solid (drops).
func _soft_texture(core: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, core, 1.0]) if core > 0.0 else PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85 if core > 0.0 else 0.3), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t
