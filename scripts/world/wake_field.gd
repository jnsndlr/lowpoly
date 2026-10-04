class_name WakeField
extends Node
## Hands every ferry's wake trail to the water shader each frame, which draws the
## foam, aerated water and Kelvin waves itself.

# Must match WAKE_FERRIES / WAKE_PTS in water.gdshader.
const MAX_FERRIES := 8
const MAX_POINTS := 48
# Must match the shader's hull and Kelvin wedge, so the bounds cover the whole wake.
const HULL_HW := 4.2
const KELVIN_SPREAD := 0.354
const KELVIN_REACH := 180.0
# Furthest the shader's reverse-thrust wash reaches from the bow (with its spread).
const FRONT_WASH_REACH := 32.0

var sim: Simulation
var water_mat: ShaderMaterial
var _pts := PackedVector4Array()
var _spd := PackedFloat32Array()
var _box := PackedVector4Array()
var _info := PackedVector4Array()


func _ready() -> void:
	# After the ferries have moved this frame.
	process_priority = 10
	_pts.resize(MAX_FERRIES * MAX_POINTS)
	_spd.resize(MAX_FERRIES * MAX_POINTS)
	_box.resize(MAX_FERRIES)
	_info.resize(MAX_FERRIES)


func _process(_delta: float) -> void:
	var count := 0
	# The fleet can outnumber the shader's slots (and docked ferries keep their
	# trail for a while), so the nearest ferries to the camera get them first.
	var fleet := sim.ferries.duplicate()
	var cam := get_viewport().get_camera_3d()
	if cam and fleet.size() > MAX_FERRIES:
		var c := cam.global_position
		fleet.sort_custom(func(a: Ferry, b: Ferry):
			return Vector2(a.position.x - c.x, a.position.z - c.z).length_squared() \
				< Vector2(b.position.x - c.x, b.position.z - c.z).length_squared())
	for f: Ferry in fleet:
		if count >= MAX_FERRIES:
			break
		var at := count * MAX_POINTS
		var n := f.pack_wake(_pts, _spd, at)
		if n < 2:
			continue
		var lo := Vector2(INF, INF)
		var hi := -lo
		for i in n:
			var p := _pts[at + i]
			var along := f.odometer - p.z
			var wk := HULL_HW + clampf(along + Ferry.HULL_HALF_LENGTH * 2.0, 0.0, KELVIN_REACH) * KELVIN_SPREAD
			var r := wk * 1.1 + 4.0
			lo = lo.min(Vector2(p.x - r, p.y - r))
			hi = hi.max(Vector2(p.x + r, p.y + r))
		var thrust := f.front_thrust()
		if thrust > 0.0:
			# Room for the reverse-thrust wash thrown out ahead of the bow.
			var bow := Vector2(_pts[at].x, _pts[at].y)
			lo = lo.min(bow - Vector2.ONE * FRONT_WASH_REACH)
			hi = hi.max(bow + Vector2.ONE * FRONT_WASH_REACH)
		_box[count] = Vector4(lo.x, lo.y, hi.x, hi.y)
		_info[count] = Vector4(f.odometer, n, Ferry.WAKE_LIFE, thrust)
		count += 1
	water_mat.set_shader_parameter("wake_count", count)
	water_mat.set_shader_parameter("wake_pts", _pts)
	water_mat.set_shader_parameter("wake_speed", _spd)
	water_mat.set_shader_parameter("wake_box", _box)
	water_mat.set_shader_parameter("wake_info", _info)
