class_name NightLights
extends Node3D
## Switches the night lights on from dusk to dawn and keeps the moving ones in place.
## The map's fixed lights are one mesh (WorldBuilder), each vessel carries its own,
## and every car on the road is an instance of a multimesh (one per model's lamp
## layout) refilled each frame from the traffic. The camera's focus distance goes to the glow shader for bokeh.

# Kept off the minimap, like the clouds.
const LAYER := 1 << (CloudLayer.VISUAL_LAYER - 1)
# The ferries' car deck lights (FerryClass.deck_lights): warm, like her ceiling lights.
const DECK_LIGHT_COLOR := Color(1.0, 0.8, 0.52)
const DECK_LIGHT_ENERGY := 10.0
const DECK_LIGHT_RANGE := 12.0

var sim: Simulation
var rig: CameraRig
var day_cycle: DayCycle
var static_lights: MeshInstance3D

var _car_mat: ShaderMaterial
var _cars := {}            # Vehicle.model -> MultiMesh of its lights
var _car_mmis: Array[MultiMeshInstance3D] = []
var _ferry_lights: Array[MeshInstance3D] = []
var _deck_lights: Array[OmniLight3D] = []
var _bufs := {}            # Vehicle.model -> its MultiMesh's buffer
var _on := true


func setup(s: Simulation, r: CameraRig, d: DayCycle, fixed: MeshInstance3D) -> void:
	name = "NightLights"
	sim = s
	rig = r
	day_cycle = d
	static_lights = fixed
	for f in sim.ferries:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.ferry_lights(f.fc)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER
		f.add_child(mi)
		_ferry_lights.append(mi)
		# Real lights in the enclosed car deck, so its floor, walls, deckhead and the
		# cars aboard all show lit (shadowless: they stay short enough not to reach
		# the water past the hull).
		for p in f.fc.deck_lights:
			var l := OmniLight3D.new()
			l.position = p
			l.light_color = DECK_LIGHT_COLOR
			l.omni_range = DECK_LIGHT_RANGE
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.light_specular = 0.2
			l.distance_fade_enabled = true
			l.distance_fade_begin = 700.0
			l.distance_fade_length = 150.0
			l.layers = LAYER
			f.add_child(l)
			_deck_lights.append(l)

	_car_mat = GlowBuilder.material().duplicate() as ShaderMaterial
	_car_mat.set_shader_parameter("instance_gate", true)
	static_lights.layers = LAYER
	_set_on(false)


## The multimesh drawing the lights of every car of `model`, made the first time one turns up.
func _car_lights(model: String) -> MultiMesh:
	if _cars.has(model):
		return _cars[model]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Models.vehicle_lights(model)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _car_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = LAYER
	mmi.visible = _on
	add_child(mmi)
	_cars[model] = mm
	_bufs[model] = PackedFloat32Array()
	_car_mmis.append(mmi)
	return mm


func _set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	static_lights.visible = on
	for mmi in _car_mmis:
		mmi.visible = on
	for mi in _ferry_lights:
		mi.visible = on
	for l in _deck_lights:
		l.visible = on
	_vessel_lights(on)
	if not on:
		for mm: MultiMesh in _cars.values():
			mm.visible_instance_count = 0


func _process(_delta: float) -> void:
	_set_on(day_cycle.night > 0.001)
	if not _on:
		return
	RenderingServer.global_shader_parameter_set("focus_distance", rig.distance)
	# Up with the lamp glass (Models.LAMP_ON_AT).
	var deck := DECK_LIGHT_ENERGY * smoothstep(Models.LAMP_ON_AT, Models.LAMP_ON_AT + 0.08, day_cycle.night)
	for l in _deck_lights:
		l.light_energy = deck
	# Cargo ships come and go through the night.
	_vessel_lights(true)
	for i in sim.ferries.size():
		var f := sim.ferries[i]
		# Sidelights: only the bow end's pair is lit, +Z heading A → B, -Z on the way back.
		var flip := 1.0 if f.at_a else -1.0
		_ferry_lights[i].set_instance_shader_parameter("nav_flip", flip)
		f.hull.set_instance_shader_parameter("nav_flip", flip)
	_update_cars()


## Sailboats' and cargo ships' own lights.
func _vessel_lights(on: bool) -> void:
	for v in sim.marine.vessels:
		if v.lights:
			v.lights.visible = on


## Cars still on the road (not parked on a ferry deck): one instance each, with the
## custom x flag lighting the road ahead only for those actually driving.
func _update_cars() -> void:
	var groups := {}
	for v: Vehicle in sim.traffic.get_children():
		if not groups.has(v.model):
			groups[v.model] = []
		groups[v.model].append(v)
		if v.trailer:
			if not groups.has(v.trailer_model):
				groups[v.trailer_model] = []
			groups[v.trailer_model].append(v)
	for model: String in _cars:
		if not groups.has(model):
			(_cars[model] as MultiMesh).visible_instance_count = 0
	for model: String in groups:
		var cars: Array = groups[model]
		var mm := _car_lights(model)
		var buf: PackedFloat32Array = _bufs[model]
		if mm.instance_count < cars.size():
			mm.instance_count = cars.size() + 64
			buf.resize(mm.instance_count * 16)
		var k := 0
		for v: Vehicle in cars:
			var t := v.transform if v.model == model else v.trailer_xform()
			var b := t.basis
			var o := k * 16
			buf[o] = b.x.x
			buf[o + 1] = b.y.x
			buf[o + 2] = b.z.x
			buf[o + 3] = t.origin.x
			buf[o + 4] = b.x.y
			buf[o + 5] = b.y.y
			buf[o + 6] = b.z.y
			buf[o + 7] = t.origin.y
			buf[o + 8] = b.x.z
			buf[o + 9] = b.y.z
			buf[o + 10] = b.z.z
			buf[o + 11] = t.origin.z
			buf[o + 12] = 1.0 if v.is_processing() else 0.0
			k += 1
		_bufs[model] = buf
		mm.buffer = buf
		mm.visible_instance_count = k
