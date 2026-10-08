extends SceneTree
## Renders a line-up of seagulls in their poses (perched adult / second-year / first-year,
## half-folded, gliding, wings up, wings down) with the real seagull shader, from a few
## angles, for checking the model by eye.
##   godot --path . --script tools/gull_shots.gd -- --out=DIR [--classic-gull]

var out := "user://"
var cam: Camera3D
var frames := 0
var views: Array = []

# fold, flap phase, flap amplitude, age; each row is one gull.
const POSES := [[1.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 0.5], [1.0, 0.0, 0.0, 1.0],
	[0.5, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, PI / 2, 1.0, 0.0], [0.0, -PI / 2, 1.0, 0.0]]
const GAP := 2.6


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
	sun.shadow_enabled = true
	root.add_child(sun)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/seagull.gdshader")
	mat.set_shader_parameter("baked_fold", Models.mid_seagull)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Models.seagull()
	mm.instance_count = POSES.size()
	for i in POSES.size():
		var p: Array = POSES[i]
		var x := (i - (POSES.size() - 1) * 0.5) * GAP
		var y := 0.0 if p[0] > 0.0 else 1.2
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * Seagulls.SCALE), Vector3(x, y, 0)))
		mm.set_instance_custom_data(i, Color(p[1], p[2], p[0], p[3]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root.add_child(mmi)
	# A ground plane for the perched ones' feet and the shadows.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	ground.mesh = pm
	ground.position.y = -0.1 * Seagulls.SCALE
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.45, 0.42)
	ground.material_override = gm
	root.add_child(ground)

	cam = Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	# name, camera position, target
	views = [["side", Vector3(-26, 3, 14), Vector3(0, 0.4, 0)],
		["front", Vector3(4, 4, 30), Vector3(0, 0.4, 0)],
		["above", Vector3(0, 30, 10), Vector3(0, 0.4, 0)],
		["below", Vector3(2, -5, 26), Vector3(0, 1.0, 0)],
		["close_perched", Vector3(-9.5, 1.6, 3.2), Vector3(-6.5, 0.0, 0)],
		["close_back", Vector3(-4.5, 2.4, -3.2), Vector3(-6.5, 0.0, 0)],
		["close_fly", Vector3(3.5, 3.5, 4.0), Vector3(2.6, 1.2, 0)]]


func _process(_delta: float) -> bool:
	frames += 1
	if frames % 3 == 1:
		if views.is_empty():
			return true
		cam.position = views[0][1]
		cam.look_at(views[0][2])
	elif frames % 3 == 0:
		var v: Array = views.pop_front()
		root.get_viewport().get_texture().get_image().save_png("%s/gulls_%s.png" % [out, v[0]])
	return false
