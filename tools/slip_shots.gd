extends SceneTree
## Watches one ferry come in to a slip and leave again, saving a frame every so often
## from a fixed camera on the slip: the span coming down, the apron landing, cars
## crossing, the apron lifting. For checking SlipRamp by eye.
##   godot --path . --script tools/slip_shots.gd -- --seed=N --out=DIR [--ferry=I] [--every=F]
##   [--yaw=RAD] [--pitch=RAD] [--dist=M] [--at=U] [--up=Y] [--side=V] [--time=H]
## Camera looks at (slip v + side, up, u = at) in the terminal frame; yaw is relative to
## looking straight in along the slip from the sea.
##   godot --path . --script tools/slip_shots.gd -- --poses --out=DIR
## renders just the slip (towers and SlipRamp) raised, part way and down, from all round,
## without the game.

var main: Node
var frames := 0
var out := "user://"
var ferry_i := 0
var every := 45
var yaw_off := 2.2
var pitch := 0.32
var dist := 62.0
var at_u := 24.0
var up := 5.0
var side := 0.0
var _f: Ferry
var _term: Terminal
var _next := -1
var _shot := 0
var _left_at := -1
var _poses := false
var _ramp: SlipRamp
var _pose_jobs: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"--out": out = kv[1]
			"--ferry": ferry_i = int(kv[1])
			"--every": every = int(kv[1])
			"--yaw": yaw_off = float(kv[1])
			"--pitch": pitch = float(kv[1])
			"--dist": dist = float(kv[1])
			"--at": at_u = float(kv[1])
			"--up": up = float(kv[1])
			"--side": side = float(kv[1])
			"--poses": _poses = true
	if _poses:
		_setup_poses()
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _setup_poses() -> void:
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
	var towers := MeshInstance3D.new()
	towers.mesh = Models.slip_mesh("towers")
	root.add_child(towers)
	_ramp = SlipRamp.new(0.0)
	_ramp.set_process(false)
	root.add_child(_ramp)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	water.mesh = plane
	water.position = Vector3(0, 0, 20)
	root.add_child(water)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	# [name, span_t, apron_t, camera, look at]
	for p in [["raised", 1.0, 1.0], ["mid", 0.5, 1.0], ["down", 0.0, 0.0]]:
		_pose_jobs.append([p[0] + "_quarter", p[1], p[2], Vector3(26, 14, 44), Vector3(0, 6, 22)])
		_pose_jobs.append([p[0] + "_side", p[1], p[2], Vector3(34, 6, 18), Vector3(0, 5, 22)])
		_pose_jobs.append([p[0] + "_tower", p[1], p[2], Vector3(18, 12, 33), Vector3(10, 9, 27)])
		_pose_jobs.append([p[0] + "_head", p[1], p[2], Vector3(4, 9, 31), Vector3(9.6, 11, 27)])
		_pose_jobs.append([p[0] + "_apron", p[1], p[2], Vector3(9, 7, 36), Vector3(0, 3.5, 27)])
	frames = 0


func _pose_shots() -> bool:
	if frames % 6 != 0:
		return false
	var k := frames / 6 - 2
	if k >= 0:
		var path := "%s/pose_%s.png" % [out, _pose_jobs[k][0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("shot ", path)
	if k + 1 >= _pose_jobs.size():
		return true
	var j: Array = _pose_jobs[k + 1]
	_ramp._span_t = j[1]
	_ramp._apron_t = j[2]
	_ramp._pose()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	cam.position = j[3]
	cam.look_at(j[4])
	return false


func _process(_delta: float) -> bool:
	frames += 1
	if _poses:
		return _pose_shots()
	if frames < 30:
		return false
	if _f == null:
		_f = main.sim.ferries[ferry_i]
	if _term == null:
		# Fast on until she is coming in, near enough.
		var rem := _f.run_length() - _f.traveled
		if _f.state != Ferry.State.SAILING or rem > 220.0:
			Engine.time_scale = 8.0
			return false
		Engine.time_scale = 1.0
		_term = _f.destination()
		var v: float = _term.slip_v[_f.route.id]
		main.rig.follow = null
		main.rig.target_pos = _term.to_global(Vector3(v + side, up, at_u))
		main.rig.target_dist = dist
		main.rig.target_pitch = pitch
		var dock := -_term.global_transform.basis.z
		main.rig.target_yaw = atan2(dock.x, dock.z) + yaw_off
		main.rig.snap()
		_next = frames + 10
		print("ferry ", _f.ferry_name, " size ", _f.fc.size, " into ", _term.name)
		return false
	if frames < _next:
		return false
	_next = frames + every
	var path := "%s/slip_%02d.png" % [out, _shot]
	root.get_viewport().get_texture().get_image().save_png(path)
	var ramp: SlipRamp = _term.ramps.get(_f.route.id)
	print("shot ", path, " ", Ferry.State.keys()[_f.state], " ", _f.status_text(),
		" span ", ramp._span_t if ramp else -1.0, " apron ", ramp._apron_t if ramp else -1.0)
	_shot += 1
	if _left_at < 0 and _f.state == Ferry.State.SAILING and _f.here() == _term:
		_left_at = _shot
	return _shot > 60 or (_left_at > 0 and _shot > _left_at + 4)
