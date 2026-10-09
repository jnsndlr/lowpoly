extends SceneTree
## Renders bald eagles in the world for checking by eye: one on a shoreline treetop,
## a pair on neighbouring trees, one on a terminal dolphin and one on a ramp lift
## (each set down there, gulls about), then one soaring and one going down on a fish
## (a few frames each). First runs the eagles for a while at speed and prints where
## they went (lookout kinds, states, pairs sitting together).
##   godot --path . --resolution 1600x900 --script tools/eagle_world_shots.gd -- --seed=N --out=DIR [--only=tree,pair,dolphin,lift,soar,strike] [--time=11.0]

var main: Node
var out := "user://"
var only := ""
var hour := 11.0
var frames := 0
var jobs := ["tree", "pair", "dolphin", "lift", "soar", "strike"]
var job := -1
var _wait := 0
var _shots: Array = []
var _bird: Eagles.Bird
var _stats := {}
var _together := 0
var _pair_checks := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--time="):
			hour = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var eg: Eagles = main.eagles
	if frames == 5:
		main.sim.minutes = hour * 60.0
		var kinds := {}
		for p in eg._perches:
			kinds[Eagles.Kind.keys()[p.kind]] = kinds.get(Eagles.Kind.keys()[p.kind], 0) + 1
		print("lookouts: ", kinds, "  eagles: ", eg._birds.size())
		print("running the eagles at 6x for ~25 s (following one) before the shots...")
		Engine.time_scale = 6.0
	if frames < 5 or frames < 1500:
		if frames > 30 and frames % 15 == 0:
			_tally(eg)
		# Something to watch meanwhile: follow the first eagle about.
		if frames > 5 and not eg._birds.is_empty():
			var rig: CameraRig = main.rig
			rig.follow = null
			rig.target_pos = eg._birds[0].pos
			rig.target_dist = 45.0
			rig.target_pitch = 0.35
		return false
	if frames == 1500:
		Engine.time_scale = 1.0
		main.sim.minutes = hour * 60.0
		print("states over the run: ", _stats)
		print("pair checks: %d, sitting within %d m: %d" % [_pair_checks, int(Eagles.PAIR_RANGE), _together])
	if _bird == null:
		job += 1
		while job < jobs.size() and only != "" and not jobs[job] in only.split(","):
			job += 1
		if job >= jobs.size():
			print("done: shots in ", out)
			return true
		_bird = _setup(eg, jobs[job])
		_wait = 0
		if _bird == null:
			print("%s: nothing to shoot" % jobs[job])
		return false
	_shoot(eg)
	return false


func _tally(eg: Eagles) -> void:
	for b in eg._birds:
		var k: String = Eagles.State.keys()[b.state]
		if b.state == Eagles.State.PERCHED:
			k += "_" + Eagles.Kind.keys()[b.perch.kind]
		_stats[k] = _stats.get(k, 0) + 1
		if b.mate and b.state == Eagles.State.PERCHED and b.mate.state == Eagles.State.PERCHED:
			_pair_checks += 1
			if b.pos.distance_to(b.mate.pos) < Eagles.PAIR_RANGE:
				_together += 1


## Sets an eagle up for the job; the shots to take go in _shots as [yaw offset, pitch, dist].
func _setup(eg: Eagles, what: String) -> Eagles.Bird:
	var b: Eagles.Bird = null
	for o in eg._birds:
		if o.state != Eagles.State.AWAY and (what != "pair" or o.mate != null):
			b = o
			break
	if b == null:
		return null
	match what:
		"tree", "pair", "dolphin", "lift":
			var kind: int = {"tree": Eagles.Kind.TREE, "pair": Eagles.Kind.TREE,
				"dolphin": Eagles.Kind.DOLPHIN, "lift": Eagles.Kind.LIFT}[what]
			var p := _free(eg, kind, b.pos)
			if p == null:
				return null
			_sit(eg, b, p)
			if what == "pair" and b.mate:
				if eg._claim(b.mate, p.at, Eagles.TERRITORY, p, true):
					_sit(eg, b.mate, b.mate.perch)
			_shots = [[0.0, 0.22, 13.0], [0.8, 0.35, 20.0], [-0.3, 0.45, 60.0]]
		"soar":
			eg._release(b)
			b.fold = 0.0
			b.vel = Vector3(sin(b.yaw), 0.0, cos(b.yaw)) * Eagles.SOAR_SPEED
			b.pos.y = maxf(b.pos.y, 80.0)
			eg._start_soar(b)
			_shots = [[1.4, 0.15, 26.0], [1.4, 0.15, 26.0], [1.4, 0.15, 26.0], [0.0, 0.9, 40.0]]
		"strike":
			eg._release(b)
			b.fold = 0.0
			b.pos.y = maxf(b.pos.y, 40.0)
			b.vel = Vector3(sin(b.yaw), 0.0, cos(b.yaw)) * Eagles.SPEED
			if not eg._start_fishing(b):
				return null
			_shots = []
	print("%s: eagle (age %d, %s) at %s" % [what, b.age, "paired" if b.mate else "alone", b.visit.target.name])
	return b


func _free(eg: Eagles, kind: int, near: Vector3) -> Eagles.Perch:
	var best: Eagles.Perch = null
	var best_d := INF
	for p in eg._perches:
		if p.kind == kind and p.bird == null:
			var d := p.at.distance_to(near)
			if d < best_d:
				best_d = d
				best = p
	return best


func _sit(eg: Eagles, b: Eagles.Bird, p: Eagles.Perch) -> void:
	eg._take(b, p)
	b.state = Eagles.State.PERCHED
	b.pos = eg._seat(p)
	b.yaw = eg._look_yaw(b)
	b.fold = 1.0
	b.vel = Vector3.ZERO
	b.timer = 9999.0
	b.leader = null
	if eg.gulls:
		eg.gulls.flush(p.at, Eagles.GULL_CLEAR + 2.0)


func _shoot(eg: Eagles) -> void:
	var rig: CameraRig = main.rig
	var b := _bird
	_wait += 1
	if jobs[job] == "strike":
		# A frame every few through the end of the glide and the climb away.
		rig.follow = null
		rig.target_pos = b.pos
		rig.target_yaw = b.yaw + PI * 0.5
		rig.target_pitch = 0.12
		rig.target_dist = 24.0
		rig.snap()
		if b.state == Eagles.State.STRIKE and b.glide_t / b.glide_time > 0.6 and _wait % 6 == 0:
			_save("strike_%03d" % _wait)
		elif b.state != Eagles.State.STRIKE and _wait % 6 == 0 and _wait < 400:
			_save("strike_after_%03d" % _wait)
		if _wait > 600 or (b.state != Eagles.State.STRIKE and b.state != Eagles.State.FLY):
			_bird = null
		return
	if _wait == 1:
		if _shots.is_empty():
			if jobs[job] != "soar":
				b.timer = 1.0
			_bird = null
			return
		var s: Array = _shots[0]
		rig.follow = null
		rig.target_pos = b.pos
		rig.target_yaw = b.yaw + s[0]
		rig.target_pitch = s[1]
		rig.target_dist = s[2]
		rig.snap()
	elif _wait == 10:
		if jobs[job] == "soar":
			rig.target_pos = b.pos
			rig.snap()
	elif _wait == 12:
		var s: Array = _shots.pop_front()
		_save("%s_%d" % [jobs[job], _shots.size()])
		_wait = 0 if jobs[job] != "soar" else -30


func _save(n: String) -> void:
	var path := "%s/eagle_%s.png" % [out, n]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " ", main.sim.clock_text())
