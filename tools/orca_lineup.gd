extends SceneTree
## Renders a lineup of orcas with different markings (and a calf), side on and from
## above, for checking cetacean.gdshader's per-animal markings by eye.
##   godot --path . --script tools/orca_lineup.gd -- --out=DIR

var out := "user://"
var cam: Camera3D
var frames := 0
var views := [[Vector3(34, -2.5, 0), Vector3(0, -2.5, 0)], [Vector3(-12, 22, 0), Vector3(0, -2.5, 0)]]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Models.orca()
	mm.instance_count = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 8:
		var calf := i == 7
		var length := 4.0 if calf else 7.0
		# Four abreast, nose to tail along z, two rows (side on from +x).
		var z := (i % 4 - 1.5) * 8.5
		var y := -float(i / 4) * 5.0
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * length), Vector3(0, y, z)))
		var fin := 0.21 if i == 0 else 0.12
		var sweep := 0.1 if i == 0 else 1.0
		var marks := rng.randf() * 0.499 + (0.5 if calf else 0.0)
		mm.set_instance_custom_data(i, Color(fin, roundf(sweep * 100.0) + marks, 0.0, 0.0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cetacean.gdshader")
	mat.set_shader_parameter("orca_markings", true)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root.add_child(mmi)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)


func _process(_delta: float) -> bool:
	frames += 1
	var v := (frames - 5) / 5
	if frames % 5 != 0 or v < 0:
		return false
	# Each view is set up one step, saved the next.
	if v > 0:
		root.get_viewport().get_texture().get_image().save_png("%s/orca_lineup_%d.png" % [out, v - 1])
	if v >= views.size():
		return true
	cam.look_at_from_position(views[v][0], views[v][1])
	return false
