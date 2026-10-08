extends SceneTree
## Renders single models on a plain backdrop from all round, for checking them by eye.
##   godot --path . --script tools/model_shots.gd -- --out=DIR [--only=house,trawler] [--dist=K]

var out := "user://"
var only := ""
var dist_k := 1.0
var cam: Camera3D
var holder: Node3D
var jobs: Array = []
var frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--dist="):
			dist_k = float(a.substr(7))
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
	holder = Node3D.new()
	root.add_child(holder)
	cam = Camera3D.new()
	root.add_child(cam)
	var models := {
		"house": [Models.house(Color(0.25, 0.4, 0.75), Color(0.8, 0.25, 0.2), 1), Vector3(0, 2.5, 0), 9.0],
		"house2": [Models.house(Color(0.25, 0.4, 0.75), Color(0.8, 0.25, 0.2), 2), Vector3(0, 3.0, 0), 11.0],
		"trawler": [Models.trawler(0), Vector3(0, 3, -4), 26.0],
		"pilot": [Models.pilot_boat(0), Vector3(0, 1.8, 0), 16.0],
		"pilot1": [Models.pilot_boat(1), Vector3(0, 1.8, 0), 16.0],
		"pilot2": [Models.pilot_boat(2), Vector3(0, 1.8, 0), 16.0],
		"cargo": [Models.cargo_ship(0), Vector3(0, 7, 0), 80.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo_bow": [Models.cargo_ship(0), Vector3(0, 3, 22), 22.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo_box": [Models.cargo_ship(0), Vector3(3, 8, -2), 13.0],
		"cargo_stern": [Models.cargo_ship(0), Vector3(0, 7, -27), 20.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo1": [Models.cargo_ship(1), Vector3(0, 7, 0), 80.0],
		"cargo2": [Models.cargo_ship(2), Vector3(0, 7, 0), 80.0],
		"tug": [Models.tug(0), Vector3(0, 3, 0), 24.0],
		"tug1": [Models.tug(1), Vector3(0, 3, 0), 24.0],
		"tug2": [Models.tug(2), Vector3(0, 3, 0), 24.0],
		"sailboat": [Models.sailboat(), Vector3(0, 1.8, 0), 11.0],
		"sailboat_furled": [Models.sailboat_furled(), Vector3(0, 1.5, 0), 9.0],
		# Unit-length animals (fins and poses need their own shaders, so they show flat).
		"humpback": [Models.humpback(), Vector3.ZERO, 1.4],
		"gray_whale": [Models.gray_whale(), Vector3.ZERO, 1.4],
		"dalls_porpoise": [Models.dalls_porpoise(), Vector3.ZERO, 1.4],
		"harbor_porpoise": [Models.harbor_porpoise(), Vector3.ZERO, 1.4],
		"harbor_seal": [Models.harbor_seal(), Vector3(0, 0.08, 0), 1.2],
		"sea_lion": [Models.sea_lion(), Vector3(0, 0.08, 0), 1.2],
	}
	for n: String in Models.PINE_VARIANTS + Models.BROAD_VARIANTS:
		models[n] = [Models._tree_part(n), Vector3(0, 4.6, 0), 13.0]
		models[n + "_lod"] = [Models._tree_part(n + "_lod"), Vector3(0, 3.6, 0), 13.0]
	for name: String in models:
		if only != "" and not name in only.split(","):
			continue
		for i in 8:
			for p: float in [0.05, 0.45]:
				jobs.append([name, models[name], i * TAU / 8.0, p])


func _process(_delta: float) -> bool:
	frames += 1
	if frames % 3 == 1:
		if jobs.is_empty():
			return true
		var j: Array = jobs[0]
		for c in holder.get_children():
			c.queue_free()
		var mi := MeshInstance3D.new()
		mi.mesh = j[1][0]
		mi.material_override = Models.vc_material()
		holder.add_child(mi)
		if j[1].size() > 3 and j[1][3] != null:
			var extra := MeshInstance3D.new()
			extra.mesh = j[1][3]
			extra.material_override = Models.vc_material()
			holder.add_child(extra)
		var target: Vector3 = j[1][1]
		var d: float = j[1][2] * dist_k
		var yaw: float = j[2]
		var pitch: float = j[3]
		cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
		cam.look_at(target)
	elif frames % 3 == 0:
		var j: Array = jobs.pop_front()
		root.get_viewport().get_texture().get_image().save_png("%s/%s_y%d_p%d.png" % [out, j[0], int(rad_to_deg(j[2])), int(rad_to_deg(j[3]))])
	return false
