extends Node3D
## The main game map. Empty for now: systems move over from the sandbox once they
## settle there. Esc returns to the menu.


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.8)
	sky_mat.sky_horizon_color = Color(0.74, 0.83, 0.9)
	sky_mat.ground_horizon_color = Color(0.74, 0.83, 0.9)
	sky_mat.ground_bottom_color = Color(0.12, 0.28, 0.36)
	sky.sky_material = sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.32, 0.42)
	mat.roughness = 0.2
	water.material_override = mat
	add_child(water)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 220, 320)
	cam.far = 5000
	add_child(cam)
	cam.look_at(Vector3.ZERO)

	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.text = "Main map — under construction.  Esc: menu"
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 20)
	ui.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Scenes.go(get_tree(), Scenes.MENU)
