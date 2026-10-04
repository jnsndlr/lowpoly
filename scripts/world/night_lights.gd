class_name NightLights
extends Node3D
## Switches the night lights on from dusk to dawn and keeps the moving ones in place.
## The map's fixed lights are one mesh (WorldBuilder), each ferry carries its own,
## and every car on the road is an instance of one multimesh refilled each frame
## from the traffic. The camera's focus distance goes to the glow shader for bokeh.

# Kept off the minimap, like the clouds.
const LAYER := 1 << (CloudLayer.VISUAL_LAYER - 1)

var sim: Simulation
var rig: CameraRig
var day_cycle: DayCycle
var static_lights: MeshInstance3D

var _cars: MultiMesh
var _car_mmi: MultiMeshInstance3D
var _ferry_lights: Array[MeshInstance3D] = []
var _buf := PackedFloat32Array()
var _on := true


func setup(s: Simulation, r: CameraRig, d: DayCycle, fixed: MeshInstance3D) -> void:
	name = "NightLights"
	sim = s
	rig = r
	day_cycle = d
	static_lights = fixed
	for f in sim.ferries:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.ferry_lights()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER
		f.add_child(mi)
		_ferry_lights.append(mi)

	var mat := GlowBuilder.material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("instance_gate", true)
	_cars = MultiMesh.new()
	_cars.transform_format = MultiMesh.TRANSFORM_3D
	_cars.use_custom_data = true
	_cars.mesh = Models.car_lights()
	_car_mmi = MultiMeshInstance3D.new()
	_car_mmi.multimesh = _cars
	_car_mmi.material_override = mat
	_car_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_car_mmi.layers = LAYER
	static_lights.layers = LAYER
	add_child(_car_mmi)
	_set_on(false)


func _set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	static_lights.visible = on
	_car_mmi.visible = on
	for mi in _ferry_lights:
		mi.visible = on
	if not on:
		_cars.visible_instance_count = 0


func _process(_delta: float) -> void:
	_set_on(day_cycle.night > 0.001)
	if not _on:
		return
	RenderingServer.global_shader_parameter_set("focus_distance", rig.distance)
	for i in sim.ferries.size():
		var f := sim.ferries[i]
		# Sidelights: only the bow end's pair is lit, +Z heading A → B, -Z on the way back.
		var flip := 1.0 if f.at_a else -1.0
		_ferry_lights[i].set_instance_shader_parameter("nav_flip", flip)
		f.hull.set_instance_shader_parameter("nav_flip", flip)
	_update_cars()


## Cars still on the road (not parked on a ferry deck): one instance each, with the
## custom x flag lighting the road ahead only for those actually driving.
func _update_cars() -> void:
	var traffic := sim.traffic.get_children()
	var n := traffic.size()
	if n == 0:
		_cars.visible_instance_count = 0
		return
	if _cars.instance_count < n:
		_cars.instance_count = n + 64
		_buf.resize(_cars.instance_count * 16)
	var k := 0
	for v: Vehicle in traffic:
		var t := v.transform
		var b := t.basis
		var o := k * 16
		_buf[o] = b.x.x
		_buf[o + 1] = b.y.x
		_buf[o + 2] = b.z.x
		_buf[o + 3] = t.origin.x
		_buf[o + 4] = b.x.y
		_buf[o + 5] = b.y.y
		_buf[o + 6] = b.z.y
		_buf[o + 7] = t.origin.y
		_buf[o + 8] = b.x.z
		_buf[o + 9] = b.y.z
		_buf[o + 10] = b.z.z
		_buf[o + 11] = t.origin.z
		_buf[o + 12] = 1.0 if v.is_processing() else 0.0
		k += 1
	_cars.buffer = _buf
	_cars.visible_instance_count = k
