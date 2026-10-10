class_name WakeField
extends Node
## Hands every vessel's wake trail (ferries, cargo ships, sailboats) to the water
## shader each frame, which draws the foam, aerated water and Kelvin waves itself.

# Must match WAKE_SLOTS / WAKE_PTS in water.gdshader.
const MAX_SLOTS := 16
const MAX_POINTS := 48
# Half-widths along each hull's waterline (WAKE_STATIONS in water.gdshader).
const STATIONS := 24
# Must match the shader's Kelvin wedge, so the bounds cover the whole wake.
const KELVIN_SPREAD := 0.354
const KELVIN_REACH := 540.0
# Furthest the shader's reverse-thrust wash reaches from the bow (with its spread).
const FRONT_WASH_REACH := 72.0
# The water shader's unit (water.gdshader's UNIT): everything goes over in it.
const UNIT := 3.0

var sim: Simulation
var water_mat: ShaderMaterial
var _pts := PackedVector4Array()
var _spd := PackedFloat32Array()
var _spd4 := PackedVector4Array()
var _box := PackedVector4Array()
var _info := PackedVector4Array()
var _hull := PackedVector4Array()
var _shape := PackedVector4Array()
var _prof := PackedVector4Array()


func _ready() -> void:
	# After the vessels have moved this frame.
	process_priority = 10
	_pts.resize(MAX_SLOTS * MAX_POINTS)
	_spd.resize(MAX_SLOTS * MAX_POINTS)
	_spd4.resize(MAX_SLOTS * MAX_POINTS / 4)
	_box.resize(MAX_SLOTS)
	_info.resize(MAX_SLOTS)
	_hull.resize(MAX_SLOTS)
	_shape.resize(MAX_SLOTS)
	_prof.resize(MAX_SLOTS * STATIONS / 4)


func _process(_delta: float) -> void:
	var fleet: Array[Vessel] = []
	for f in sim.ferries:
		if not f.wake.is_empty():
			fleet.append(f)
	for v in sim.marine.vessels:
		if is_instance_valid(v) and v.wake and not v.wake.is_empty():
			fleet.append(v)
	# There are more vessels than the shader has slots (and moored or docked ones
	# keep their trail for a while), so the nearest to the camera get them first.
	var cam := get_viewport().get_camera_3d()
	if cam and fleet.size() > MAX_SLOTS:
		var c := Vector2(cam.global_position.x, cam.global_position.z)
		fleet.sort_custom(func(a: Vessel, b: Vessel):
			return (a.pos2() - c).length_squared() < (b.pos2() - c).length_squared())
	var count := 0
	for v in fleet:
		if count >= MAX_SLOTS:
			break
		var tr := v.wake
		var hull := v.wake_hull()
		var at := count * MAX_POINTS
		var n := tr.pack(v.global_position, _pts, _spd, at, MAX_POINTS)
		if n < 2:
			continue
		var reach := KELVIN_REACH * hull.w
		var lo := Vector2(INF, INF)
		var hi := -lo
		for i in n:
			var p := _pts[at + i]
			var along := tr.odometer - p.z
			var wk := hull.x + clampf(along + hull.y, 0.0, reach) * KELVIN_SPREAD
			var r := wk * 1.1 + 12.0
			lo = lo.min(Vector2(p.x - r, p.y - r))
			hi = hi.max(Vector2(p.x + r, p.y + r))
		var thrust := v.front_thrust()
		if thrust > 0.0:
			# Room for the reverse-thrust wash thrown out ahead of the bow.
			var bow := Vector2(_pts[at].x, _pts[at].y)
			lo = lo.min(bow - Vector2.ONE * FRONT_WASH_REACH)
			hi = hi.max(bow + Vector2.ONE * FRONT_WASH_REACH)
		_box[count] = Vector4(lo.x, lo.y, hi.x, hi.y) / UNIT
		_info[count] = Vector4(tr.odometer / UNIT, n, tr.life, thrust)
		_hull[count] = Vector4(hull.x / UNIT, hull.y / UNIT, hull.z, hull.w)
		# The waterline: where it starts and how long it is, how far back from its stem
		# the bow fills out (to 97% of its widest) and its half-width at the stem.
		var wl := v.wake_waterline()
		var widest := 0.0
		for i in STATIONS:
			widest = maxf(widest, wl[2 + i])
		var run := 0
		while run < STATIONS - 1 and wl[2 + run] < widest * 0.97:
			run += 1
		var ds := wl[1] / (STATIONS - 1)
		_shape[count] = Vector4(wl[0], wl[1], run * ds, wl[2]) / UNIT
		for i in STATIONS / 4:
			var j := 2 + i * 4
			_prof[count * STATIONS / 4 + i] = Vector4(wl[j], wl[j + 1], wl[j + 2], wl[j + 3]) / UNIT
		for i in n:
			var q := _pts[at + i]
			_pts[at + i] = Vector4(q.x / UNIT, q.y / UNIT, q.z / UNIT, q.w)
		count += 1
	# Speeds go four to a vec4, which keeps the shader's uniforms compact.
	for i in _spd4.size():
		_spd4[i] = Vector4(_spd[i * 4], _spd[i * 4 + 1], _spd[i * 4 + 2], _spd[i * 4 + 3])
	water_mat.set_shader_parameter("wake_count", count)
	water_mat.set_shader_parameter("wake_pts", _pts)
	water_mat.set_shader_parameter("wake_speed", _spd4)
	water_mat.set_shader_parameter("wake_box", _box)
	water_mat.set_shader_parameter("wake_info", _info)
	water_mat.set_shader_parameter("wake_hull", _hull)
	water_mat.set_shader_parameter("wake_shape", _shape)
	water_mat.set_shader_parameter("wake_prof", _prof)
