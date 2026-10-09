extends SceneTree
## Renders a line-up of bald eagles in their poses (perched adult / sub-adult /
## juvenile, half-folded, soaring, wings up, wings down, striking with the talons out)
## with the real eagle shader, from a few angles, for checking the model by eye.
##   godot --path . --script tools/eagle_shots.gd -- --out=DIR

var out := "user://"
var cam: Camera3D
var frames := 0
var views: Array = []

# fold, flap phase, flap amplitude, plumage + talons (eagle.gdshader's w); each row is one eagle.
const POSES := [[1.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 1.0], [1.0, 0.0, 0.0, 2.0],
	[0.5, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, PI / 2, 0.8, 0.0], [0.0, -PI / 2, 0.8, 0.0], [0.0, 0.0, 0.0, 0.9]]
const GAP := 3.8


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
	mat.shader = load("res://shaders/eagle.gdshader")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Models.eagle()
	mm.instance_count = POSES.size()
	for i in POSES.size():
		var p: Array = POSES[i]
		var x := (i - (POSES.size() - 1) * 0.5) * GAP
		var y := 0.0 if p[0] > 0.0 else 1.6
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * Eagles.SCALE), Vector3(x, y, 0)))
		mm.set_instance_custom_data(i, Color(p[1], p[2], p[0], p[3]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root.add_child(mmi)
	# A ground plane for the perched ones' feet and the shadows.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 16)
	ground.mesh = pm
	ground.position.y = -0.2 * Eagles.SCALE
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.45, 0.42)
	ground.material_override = gm
	root.add_child(ground)

	cam = Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	# name, camera position, target
	views = [["side", Vector3(-40, 4, 22), Vector3(0, 0.6, 0)],
		["front", Vector3(5, 5, 46), Vector3(0, 0.6, 0)],
		["above", Vector3(0, 46, 14), Vector3(0, 0.6, 0)],
		["below", Vector3(2, -7, 40), Vector3(0, 1.4, 0)],
		["close_perched", Vector3(-17.4, 1.2, 4.6), Vector3(-13.3, 0.2, 0)],
		["close_side", Vector3(-13.3, 0.6, 5.5), Vector3(-13.3, 0.3, 0)],
		["close_juveniles", Vector3(-7.6, 1.0, 6.5), Vector3(-7.6, 0.2, 0)],
		["close_back", Vector3(-9.9, 2.8, -4.5), Vector3(-13.3, 0.2, 0)],
		["close_fly", Vector3(4.0, 5.5, 6.0), Vector3(1.9, 1.6, 0)],
		["close_strike", Vector3(18.0, 1.4, 5.5), Vector3(13.3, 1.5, 0)]]


func _process(_delta: float) -> bool:
	frames += 1
	if frames % 3 == 1:
		if views.is_empty():
			return true
		cam.position = views[0][1]
		cam.look_at(views[0][2])
	elif frames % 3 == 0:
		var v: Array = views.pop_front()
		root.get_viewport().get_texture().get_image().save_png("%s/eagles_%s.png" % [out, v[0]])
	return false
