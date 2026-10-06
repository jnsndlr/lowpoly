extends Node3D
## Entry point: generate a map, build the 3D world, start the simulation, add the HUD.
##
## Debug args (after `--` on the command line):
##   --seed=N  --speed=0..3  --cam=x,z,dist,yaw_deg,pitch_deg  --select=K (Kth terminal island)
##   --follow=K (Kth ferry)  --time=H (pin time of day, e.g. 19.5)  --shot=path.png  --shot-delay=seconds
##   --bench=seconds (print frame/GPU time and render stats, then quit)
##   --orcas (start an orca visit now and follow it)
##   --vessel=cargo|sail|yacht|pilot|tug (follow a cargo ship, a sailboat under way, a
##     motor yacht, a pilot boat or a tug)

static var map_seed := 0

var map: MapData
var terrain: Terrain
var sim: Simulation
var rig: CameraRig
var hud: Hud
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var day_cycle: DayCycle
var water_mat: ShaderMaterial
var route_overlay: MeshInstance3D
var orcas: Orcas
var _args := {}


func _ready() -> void:
	_parse_args()
	if map_seed == 0:
		map_seed = int(_args["seed"]) if _args.has("seed") else randi_range(1, 99999)
	var t0 := Time.get_ticks_msec()
	var gen := MapGenerator.new()
	map = gen.generate(map_seed)
	terrain = gen.terrain
	_setup_environment()
	var builder := WorldBuilder.new(map, terrain)
	add_child(builder.build())
	route_overlay = builder.route_overlay
	var fixed_lights := builder.night_lights
	water_mat = builder.water_material
	print("Map %d built in %d ms: %d islands, %d routes" % [map_seed, Time.get_ticks_msec() - t0, map.islands.size(), map.routes.size()])

	rig = CameraRig.new()
	rig.terrain = terrain
	rig.bounds = map.half_size * 0.8
	add_child(rig)
	sim = Simulation.new()
	sim.name = "Simulation"
	add_child(sim)
	sim.setup(map, terrain)
	var clouds := CloudLayer.new()
	clouds.setup(sim.weather, sim.wind_dir, sim.wind_speed)
	add_child(clouds)
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	day_cycle.sim = sim
	day_cycle.sun = sun
	day_cycle.env = env
	day_cycle.sky_mat = sky_mat
	day_cycle.water_mat = water_mat
	add_child(day_cycle)
	var wakes := WakeField.new()
	wakes.name = "WakeField"
	wakes.sim = sim
	wakes.water_mat = water_mat
	add_child(wakes)
	var lights := NightLights.new()
	add_child(lights)
	lights.setup(sim, rig, day_cycle, fixed_lights)
	var gulls := Seagulls.new()
	add_child(gulls)
	gulls.setup(sim, day_cycle, builder.gull_perches)
	orcas = Orcas.new()
	add_child(orcas)
	orcas.setup(sim.wildlife, terrain)
	day_cycle.apply(sim.hour())
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_apply_debug_args()


func regenerate() -> void:
	Engine.time_scale = 1.0
	map_seed = randi_range(1, 99999)
	get_tree().reload_current_scene()


func _setup_environment() -> void:
	# Colours, ambient, fog and sun direction are driven per frame by DayCycle.
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.8)
	sky_mat.sky_horizon_color = Color(0.74, 0.83, 0.9)
	sky_mat.ground_horizon_color = Color(0.74, 0.83, 0.9)
	sky_mat.ground_bottom_color = Color(0.12, 0.28, 0.36)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 2.5
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.74, 0.82, 0.88)
	env.fog_density = 0.85
	env.fog_depth_begin = 600.0
	env.fog_depth_end = 1600.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	# Thin volumetric haze so sunlight scatters and cloud shadows read as shafts.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_temporal_reprojection_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)


func _process(_delta: float) -> void:
	# Keep shadows crisp and fog sensible at every zoom level.
	sun.directional_shadow_max_distance = clampf(rig.distance * 2.6, 120.0, 1200.0)
	env.fog_depth_begin = rig.distance * 1.6 + 200.0
	env.fog_depth_end = rig.distance * 4.0 + 700.0
	env.volumetric_fog_length = clampf(rig.distance * 2.4, 250.0, 1600.0)


# --- Debug / screenshot args ----------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _apply_debug_args() -> void:
	if _args.has("time"):
		day_cycle.set_hour(float(_args["time"]))
		day_cycle.apply(day_cycle.hour())
	if _args.has("speed"):
		hud.set_speed(int(_args["speed"]))
	if _args.has("cam"):
		var p: PackedStringArray = str(_args["cam"]).split(",")
		rig.target_pos = Vector3(float(p[0]), 0, float(p[1]))
		rig.target_dist = float(p[2])
		if p.size() > 3:
			rig.target_yaw = deg_to_rad(float(p[3]))
		if p.size() > 4:
			rig.target_pitch = deg_to_rad(float(p[4]))
		rig.snap()
	if _args.has("select"):
		var k := int(_args["select"])
		var terms: Array = sim.terminals.values()
		if k < terms.size():
			hud.select_island((terms[k] as Terminal).island, true)
			rig.snap()
	if _args.has("follow"):
		var k := int(_args["follow"])
		if k < sim.ferries.size():
			hud.select_ferry(sim.ferries[k])
	if _args.has("orcas"):
		var v := sim.wildlife.start_visit(sim.wildlife.find_species("orca"))
		if v:
			hud.follow_visit(v)
			rig.target_dist = 70.0
			rig.target_pitch = 0.55
			rig.snap()
	if _args.has("vessel"):
		var want := str(_args["vessel"])
		for v in sim.marine.vessels:
			if (want == "cargo" and v is CargoShip) or (want == "sail" and v is Sailboat and v.wants_to_move()) \
					or (want == "yacht" and v is MotorYacht) or (want == "pilot" and v is PilotBoat) or (want == "tug" and v is Tug):
				hud.select_vessel(v)
				rig.target_pos = v.global_position
				rig.snap()
				break
	if _args.has("shot"):
		_take_screenshot(str(_args["shot"]), float(_args.get("shot-delay", "3")))
	if _args.has("bench"):
		_bench(float(_args["bench"]))


## Prints averaged frame / GPU time and render stats after a warm-up, then quits.
## GPU time needs a driver with timestamp queries (e.g. --rendering-driver vulkan).
func _bench(seconds: float) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().create_timer(3.0, true, false, true).timeout
	var frames := 0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) / 1e6 < seconds:
		await get_tree().process_frame
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var rs := RenderingServer
	print("BENCH frame %.2f ms | gpu %.2f ms | draws %d | primitives %d | objects %d | nodes %d" % [
		(Time.get_ticks_usec() - t0) / 1000.0 / frames, gpu / frames,
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()


func _take_screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot to ", path)
	get_tree().quit()
