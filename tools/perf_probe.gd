extends SceneTree
## Measures frame and GPU time with render features switched off, to see what each
## costs. GPU timings need Vulkan on macOS (Metal has no timestamp queries); a game
## running at the same time skews the numbers, so compare runs made back to back.
##   godot --path . --rendering-driver vulkan --resolution 3200x1920 --script tools/perf_probe.gd \
##     -- --seed=9164 [--off=ssao,vfog,glow,shadow,shadow2,aa,msaa,water,clouds,backdrop,mtrees,scale75,census]
var main: Node
var frames := 0
var off := ""
var t0 := 0
var n := 0
var gpu := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--off="):
			off = a.substr(6)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("uncapped", true)
	Engine.max_fps = 0

func _apply() -> void:
	var env: Environment = main.env
	for o in off.split(","):
		match o:
			"ssao": env.ssao_enabled = false
			"vfog": env.volumetric_fog_enabled = false
			"glow": env.glow_enabled = false
			"shadow": main.sun.shadow_enabled = false
			"shadow2": main.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			"aa": root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"msaa":
				# The old setting, for comparison: MSAA 2x instead of SMAA.
				root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				root.msaa_3d = Viewport.MSAA_2X
			"water": _hide(main, "Water")
			"scale75": root.scaling_3d_scale = 0.75
			"clouds": _hide(main, "Clouds")
			"backdrop": _hide(main, "Backdrop")
			"mtrees": _hide(main, "MainlandPines*")
			"cards": _hide(main, "TreeCards*")
			"mland": _hide(main, "Mainland")
			"cumulus": _hide(main, "Cumulus")

func _hide(n: Node, nm: String) -> void:
	for c in n.find_children(nm, "", true, false):
		c.visible = false

func _process(_d: float) -> bool:
	frames += 1
	if frames == 60:
		_apply()
		if "census" in off:
			_census()
	if frames == 180:
		t0 = Time.get_ticks_usec()
	if frames > 180:
		n += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	if "shadow" in off.split(","):
		main.sun.shadow_enabled = false
	if frames == 600:
		var rs := RenderingServer
		print("PROBE %-12s frame %.2f ms | gpu %.2f ms | px %s | prims %d | draws %d" % [off if off != "" else "baseline",
			(Time.get_ticks_usec() - t0) / 1000.0 / n, gpu / n, root.get_visible_rect().size,
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		return true
	return false

func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		var idx = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t

func _census() -> void:
	print("scale ", DisplayServer.screen_get_scale(), " tex ", root.get_texture().get_size())
	var rows := {}
	for n in main.find_children("*", "GeometryInstance3D", true, false):
		var k := ""
		var t := 0
		if n is MeshInstance3D:
			t = _tris(n.mesh)
			k = String(n.name).rstrip("0123456789@")
			if n.get_parent() is Vessel or n.get_parent().get_parent() is Vessel:
				k = "vessel:" + k
		elif n is MultiMeshInstance3D and n.multimesh:
			t = _tris(n.multimesh.mesh) * n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else _tris(n.multimesh.mesh) * n.multimesh.instance_count
			k = "MM:" + String(n.name)
		else:
			continue
		if not rows.has(k):
			rows[k] = [0, 0, 0]
		rows[k][0] += 1
		rows[k][1] += t
		if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			rows[k][2] += t
	var ks := rows.keys()
	ks.sort_custom(func(a, b): return rows[a][1] > rows[b][1])
	for k in ks.slice(0, 30):
		print("CENSUS %-30s n=%4d tris=%8d shadowtris=%8d" % [k, rows[k][0], rows[k][1], rows[k][2]])
