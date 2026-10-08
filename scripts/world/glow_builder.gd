class_name GlowBuilder
extends RefCounted
## Accumulates night lights (point glows, light pools, beacon beams and their water
## reflections) as quads for glow.gdshader. Every vertex of a quad sits at the
## light itself and the shader opens it up on screen, so a whole model's (or the
## whole map's) lights are one cheap draw. Helpers take local coordinates, which
## are transformed by `xform`.

enum { GLOW, POOL, CONE, BEAM, NAV, REFLECT, NAV_REFLECT }

const WARM := Color(1.0, 0.7, 0.4)
const SODIUM := Color(1.0, 0.56, 0.24)
const LED := Color(1.0, 0.9, 0.76)
const HEADLIGHT := Color(1.0, 0.94, 0.82)
const TAIL := Color(1.0, 0.06, 0.04)
const RED := Color(1.0, 0.1, 0.06)
const GREEN := Color(0.1, 1.0, 0.35)

static var _mat: ShaderMaterial

var xform := Transform3D.IDENTITY
var _v := PackedVector3Array()
var _uv := PackedVector2Array()
var _col := PackedColorArray()
var _c0 := PackedFloat32Array()
var _c1 := PackedFloat32Array()
var _idx := PackedInt32Array()


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/glow.gdshader")
		# After the water and clouds, which are transparent too.
		_mat.render_priority = 10
	return _mat


## A point light of world radius `size`. `on_at` is the night_lights level it
## switches on at (< 0 picks one at random); `blink` is a flash period in whole
## seconds plus the flash's phase as its fraction (Models.blink_of);
## a non-zero `facing` makes it directional (headlights).
func glow(p: Vector3, col: Color, size: float, energy: float, reflect := false, blink := 0.0,
		facing := Vector3.ZERO, on_at := -1.0) -> void:
	var c := xform * p
	on_at = _on_at(c, on_at)
	_quad(c, col, GLOW, size, on_at, blink, xform.basis * facing, energy)
	if reflect:
		_quad(c, col, REFLECT, size, on_at, blink, xform.basis * facing, energy)


## Only the reflection, for something lit that isn't a lamp of its own (a row of
## windows): it shows on the water on the side `facing` points.
func reflection(p: Vector3, col: Color, size: float, energy: float, facing := Vector3.ZERO) -> void:
	var c := xform * p
	_quad(c, col, REFLECT, size, _on_at(c, -1.0) * 0.1, 0.0, xform.basis * facing, energy)


## Red / green sidelight at one end of a double-ended hull, shining along `facing`:
## the shader lights only the bow end's pair (nav_flip) and picks red for port.
func nav(p: Vector3, size: float, energy: float, facing := Vector3.ZERO) -> void:
	var c := xform * p
	if facing == Vector3.ZERO:
		facing = Vector3(signf(p.x), 0, 0)
	facing = xform.basis * facing
	_quad(c, Color.WHITE, NAV, size, 0.0, 0.0, facing, energy)
	_quad(c, Color.WHITE, NAV_REFLECT, size, 0.0, 0.0, facing, energy)


## A soft round pool of light on the ground (or water).
func pool(p: Vector3, col: Color, radius: float, energy: float, on_at := -1.0) -> void:
	var c := xform * p
	_quad(c, col, POOL, radius, _on_at(c, on_at), 0.0, Vector3(0, 0, radius), energy)


## A headlight cone on the road from `p` along `dir` for `length`.
func cone(p: Vector3, dir: Vector3, length: float, half_width: float, col: Color, energy: float) -> void:
	var axis := xform.basis * dir.normalized() * length * 0.5
	_quad(xform * p + axis, col, CONE, half_width, 0.0, 0.0, axis, energy)


## A pair of opposed beams sweeping round at `speed` radians per second.
func beam(p: Vector3, col: Color, width: float, length: float, speed: float, energy: float, phase := 0.0) -> void:
	var c := xform * p
	for k in 2:
		_quad(c, col, BEAM, width, 0.0, 0.0, Vector3(speed, length, phase + PI * k), energy)


func _on_at(c: Vector3, on_at: float) -> float:
	if on_at >= 0.0:
		return on_at
	return 0.02 + fposmod(sin(c.x * 12.9898 + c.z * 78.233 + c.y * 3.17) * 43758.5453, 1.0) * 0.6


func _quad(c: Vector3, col: Color, mode: int, size: float, on_at: float, blink: float, vec: Vector3, energy: float) -> void:
	var base := _v.size()
	for uv: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_v.append(c)
		_uv.append(uv)
		_col.append(col)
		_c0.append_array([size, float(mode), on_at, blink])
		_c1.append_array([vec.x, vec.y, vec.z, energy])
	_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func is_empty() -> bool:
	return _v.is_empty()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_COLOR] = _col
	arr[Mesh.ARRAY_CUSTOM0] = _c0
	arr[Mesh.ARRAY_CUSTOM1] = _c1
	arr[Mesh.ARRAY_INDEX] = _idx
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh.surface_set_material(0, material())
	# The shader moves every vertex (and reflections land far from their lights),
	# so the mesh's own bounds mean nothing.
	mesh.custom_aabb = AABB(Vector3(-12000, -600, -12000), Vector3(24000, 2400, 24000))
	return mesh
