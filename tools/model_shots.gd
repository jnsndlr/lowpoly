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
		"trawler1": [Models.trawler(1), Vector3(0, 3, -4), 26.0],
		"trawler2": [Models.trawler(2), Vector3(0, 3, -4), 26.0],
		"trawler_deck": [Models.trawler(0), Vector3(0, 3, -5), 13.0],
		"trawler_house": [Models.trawler(0), Vector3(0, 5, 2.5), 11.0],
		"pilot": [Models.pilot_boat(0), Vector3(0, 1.8, 0), 16.0],
		"pilot1": [Models.pilot_boat(1), Vector3(0, 1.8, 0), 16.0],
		"pilot2": [Models.pilot_boat(2), Vector3(0, 1.8, 0), 16.0],
		"cargo": [Models.cargo_ship(0), Vector3(0, 7, 0), 80.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo_bow": [Models.cargo_ship(0), Vector3(0, 3, 22), 22.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo_box": [Models.cargo_ship(0), Vector3(3, 8, -2), 13.0],
		"cargo_stern": [Models.cargo_ship(0), Vector3(0, 7, -27), 20.0, Models.cargo_name_plate("Cascade Carrier")],
		"cargo1": [Models.cargo_ship(1), Vector3(0, 7, 0), 80.0],
		"cargo2": [Models.cargo_ship(2), Vector3(0, 7, 0), 80.0],
		"tanker": [Models.tanker(0), Vector3(0, 7, 0), 80.0, Models.cargo_name_plate("Strait Venture")],
		"tanker_deck": [Models.tanker(0), Vector3(0, 5, 0), 18.0],
		"tanker_house": [Models.tanker(0), Vector3(0, 7, -16), 16.0],
		"tanker1": [Models.tanker(1), Vector3(0, 7, 0), 80.0],
		"tanker2": [Models.tanker(2), Vector3(0, 7, 0), 80.0],
		"bulker": [Models.bulk_carrier(0), Vector3(0, 7, 0), 80.0, Models.cargo_name_plate("Haro Pioneer")],
		"bulker_deck": [Models.bulk_carrier(0), Vector3(0, 6, 2), 18.0],
		"bulker1": [Models.bulk_carrier(1), Vector3(0, 7, 0), 80.0],
		"bulker2": [Models.bulk_carrier(2), Vector3(0, 7, 0), 80.0],
		"tug": [Models.tug(0), Vector3(0, 3, 0), 24.0],
		"tug1": [Models.tug(1), Vector3(0, 3, 0), 24.0],
		"tug2": [Models.tug(2), Vector3(0, 3, 0), 24.0],
		"sailboat": [Models.sailboat(), Vector3(0, 1.8, 0), 11.0],
		"sailboat_furled": [Models.sailboat_furled(), Vector3(0, 1.5, 0), 9.0],
		# Sedans (real size), each in a paint off the reference sheet.
		"sedan_modern": [Models.vehicle("sedan_modern", 1), Vector3(0, 0.7, 0), 6.5],
		"sedan_sport": [Models.vehicle("sedan_sport", 5), Vector3(0, 0.7, 0), 6.5],
		"sedan_boxy": [Models.vehicle("sedan_boxy", 7), Vector3(0, 0.7, 0), 6.5],
		"sedan_nineties": [Models.vehicle("sedan_nineties", 9), Vector3(0, 0.7, 0), 6.5],
		"sedan_luxury": [Models.vehicle("sedan_luxury", 10), Vector3(0, 0.7, 0), 7.0],
		"sedan_ev": [Models.vehicle("sedan_ev", 12), Vector3(0, 0.7, 0), 6.5],
		"sedan_compact": [Models.vehicle("sedan_compact", 11), Vector3(0, 0.7, 0), 6.0],
		"sedan_exec": [Models.vehicle("sedan_exec", 2), Vector3(0, 0.7, 0), 6.5],
		# SUVs, likewise.
		"suv_crossover": [Models.vehicle("suv_crossover", 1), Vector3(0, 0.85, 0), 6.5],
		"suv_threerow": [Models.vehicle("suv_threerow", 7), Vector3(0, 0.85, 0), 7.0],
		"suv_luxury": [Models.vehicle("suv_luxury", 4), Vector3(0, 0.95, 0), 7.5],
		"suv_coupe": [Models.vehicle("suv_coupe", 12), Vector3(0, 0.8, 0), 7.0],
		"suv_ev": [Models.vehicle("suv_ev", 3), Vector3(0, 0.85, 0), 7.0],
		"suv_cherokee": [Models.vehicle("suv_cherokee", 5), Vector3(0, 0.85, 0), 6.0],
		"suv_offroad": [Models.vehicle("suv_offroad", 9), Vector3(0, 0.95, 0), 7.0],
		"suv_nineties": [Models.vehicle("suv_nineties", 11), Vector3(0, 0.85, 0), 6.5],
		# Unit-length animals (fins and poses need their own shaders, so they show flat).
		"humpback": [Models.humpback(), Vector3.ZERO, 1.4],
		"gray_whale": [Models.gray_whale(), Vector3.ZERO, 1.4],
		"dalls_porpoise": [Models.dalls_porpoise(), Vector3.ZERO, 1.4],
		"harbor_porpoise": [Models.harbor_porpoise(), Vector3.ZERO, 1.4],
		"harbor_seal": [Models.harbor_seal(), Vector3(0, 0.08, 0), 1.2],
		"sea_lion": [Models.sea_lion(), Vector3(0, 0.08, 0), 1.2],
	}
	if ResourceLoader.exists("res://assets/models/ferry_mid.glb"):
		var ferry: ArrayMesh = Models._gltf_parts("res://assets/models/ferry_mid.glb", ["fixed", "glass", "window"]).commit()
		models["ferry_mid"] = [ferry, Vector3(0, 7, 0), 115.0]
		models["ferry_end"] = [ferry, Vector3(0, 5, 40), 34.0]
		models["ferry_top"] = [ferry, Vector3(0, 12, 18), 34.0]
		models["ferry_boat"] = [ferry, Vector3(4, 9, -33), 22.0]
		models["ferry_deck"] = [ferry, Vector3(0, 4, 30), 16.0]
		models["ferry_ports"] = [ferry, Vector3(10.8, 5, -2), 10.0]
		models["ferry_wing"] = [ferry, Vector3(8.4, 4.6, 6), 4.5]
		models["ferry_fork"] = [ferry, Vector3(7, 6, 37), 15.0]
		models["ferry_stair"] = [ferry, Vector3(4.5, 4.5, 25.5), 8.0]
	if ResourceLoader.exists("res://assets/models/guemes_mid.glb"):
		var guemes: ArrayMesh = Models._gltf_parts("res://assets/models/guemes_mid.glb", ["fixed", "glass", "window"]).commit()
		models["guemes"] = [guemes, Vector3(0, 3, 0), 48.0]
		models["guemes_end"] = [guemes, Vector3(0, 3, 14), 18.0]
		models["guemes_house"] = [guemes, Vector3(5.5, 6.5, 0), 14.0]
		models["guemes_hull"] = [guemes, Vector3(0, 0.5, 8), 30.0]
	if ResourceLoader.exists("res://assets/models/hiyu_mid.glb"):
		var hiyu: ArrayMesh = Models._gltf_parts("res://assets/models/hiyu_mid.glb", ["fixed", "glass", "window"]).commit()
		models["hiyu"] = [hiyu, Vector3(0, 5, 0), 62.0]
		models["hiyu_end"] = [hiyu, Vector3(0, 5, 16), 24.0]
		models["hiyu_tunnel"] = [hiyu, Vector3(0, 4.5, 14), 9.0]
		models["hiyu_top"] = [hiyu, Vector3(0, 9, 0), 18.0]
		models["hiyu_hull"] = [hiyu, Vector3(0, 1.5, 24), 14.0]
		models["hiyu_gusset"] = [hiyu, Vector3(8.0, 4.5, 15.5), 9.0]
	if ResourceLoader.exists("res://assets/models/rib_mid.glb"):
		var rib: ArrayMesh = Models._gltf_parts("res://assets/models/rib_mid.glb", ["fixed", "sling"]).commit()
		models["rib"] = [rib, Vector3(0, 0.6, -0.2), 7.5]
		models["rib_helm"] = [rib, Vector3(0, 0.8, -0.6), 3.2]
		# Each mid-poly ferry with it in her cradle (the full game mesh, at MID_SCALE).
		models["hiyu_rib"] = [Models.ferry(FerryClass.of(2)), Vector3(8.3, 12.0, -5.0), 13.0]
		models["evergreen_rib"] = [Models.ferry(FerryClass.of(4)), Vector3(9.1, 10.6, -43.6), 13.0]
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
