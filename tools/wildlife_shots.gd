extends SceneTree
## Renders the sea mammals for checking by eye: each whale and porpoise as it
## surfaces (a short burst of frames), and the seals and sea lions hauled out on a
## beach, a rock ledge and a marina float (from a few sides, close and further off).
##   godot --path . --resolution 1600x900 --script tools/wildlife_shots.gd -- --seed=N --out=DIR [--only=humpback,seal_beach]

var main: Node
var out := "user://"
var only := ""
var frames := 0
# [name, species, haul-out kind (-1: swims), shots]
var jobs := [
	["orca", "orca", -1],
	["humpback", "humpback", -1],
	["gray", "gray", -1],
	["dalls", "dalls_porpoise", -1],
	["harbor_porpoise", "harbor_porpoise", -1],
	["seal_beach", "harbor_seal", MapData.HaulOut.Kind.BEACH],
	["seal_rock", "harbor_seal", MapData.HaulOut.Kind.ROCK],
	["sealion_dock", "sea_lion", MapData.HaulOut.Kind.DOCK],
	["sealion_rock", "sea_lion", MapData.HaulOut.Kind.ROCK],
]
var job := -1
var visit: Wildlife.Visit
var _step := 0
var _wait := 0
var _shots: Array = []      # [yaw, pitch, dist] still to take
var _focus := Vector3.ZERO
var _yaw0 := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	var sim: Simulation = main.sim
	var w := sim.wildlife
	if visit == null:
		# Next job: clear the sea of everyone else, start this one in the late morning.
		job += 1
		while job < jobs.size() and only != "" and not jobs[job][0] in only.split(","):
			job += 1
		if job >= jobs.size():
			return true
		for v in w.active_visits():
			w._end(v)
		w._planned.clear()
		w._planned_day = sim.day
		sim.minutes = 10.5 * 60.0
		var sp := w.find_species(jobs[job][1])
		var kind: int = jobs[job][2]
		var saved := sp.haul
		if kind >= 0:
			sp.haul = Vector3(1.0 if kind == 0 else 0.0, 1.0 if kind == 1 else 0.0, 1.0 if kind == 2 else 0.0)
		visit = w.start_visit(sp)
		sp.haul = saved
		if visit == null or (kind >= 0 and (visit.site == null or visit.site.kind != kind)):
			print("%s: no visit" % jobs[job][0])
			if visit:
				w._end(visit)
			visit = null
			return false
		_step = 0
		_wait = 0
		Engine.time_scale = 8.0
		print("%s: %d %s at %s" % [jobs[job][0], visit.members.size(), sp.plural, visit.target.name])
		return false
	var rig: CameraRig = main.rig
	match _step:
		0:
			# Wait (fast) for them to get there and settle in.
			_wait += 1
			if not visit.active() or _wait > 30000:
				print("%s: gave up" % jobs[job][0])
				_finish()
				return false
			var ready := false
			if visit.site:
				ready = visit.phase == Wildlife.Phase.HAULED and visit.age > _arrived_age() + 90.0 \
					and _resting() >= mini(3, visit.members.size())
			else:
				ready = visit.phase == Wildlife.Phase.FORAGE or visit.phase == Wildlife.Phase.CIRCLE
			if ready:
				Engine.time_scale = 1.0
				_step = 1
				_wait = 0
				if visit.site:
					var site := visit.site
					var c := Vector3.ZERO
					for sp in site.spots:
						c += sp.at
					_focus = c / site.spots.size()
					_yaw0 = atan2(site.out.x, site.out.z)
					_shots = [[0.5, 0.35, 26.0], [1.6, 0.25, 22.0], [-0.9, 0.6, 50.0], [0.2, 1.1, 30.0]]
					sim.minutes = 11.0 * 60.0
		1:
			if visit.site:
				_shoot_site(rig)
			else:
				_shoot_surfacing(rig)
	return false


func _arrived_age() -> float:
	return 0.0


func _resting() -> int:
	var n := 0
	for p in main.pinnipeds._pods:
		if p.visit == visit:
			for o in p.animals:
				if o.state == Pinnipeds.State.REST:
					n += 1
	return n


func _shoot_site(rig: CameraRig) -> void:
	_wait += 1
	if _wait == 1:
		if _shots.is_empty():
			_finish()
			return
		var s: Array = _shots[0]
		rig.follow = null
		rig.target_pos = _focus
		rig.target_yaw = _yaw0 + s[0]
		rig.target_pitch = s[1]
		rig.target_dist = s[2]
		rig.snap()
	elif _wait == 8:
		var s: Array = _shots.pop_front()
		_save("%s_y%d_p%d" % [jobs[job][0], int(rad_to_deg(s[0])), int(rad_to_deg(s[1]))])
		_wait = 0


## Follows the first animal to start a breath, a frame every so often through it.
var _burst := 0
var _target: Cetaceans.Animal

func _shoot_surfacing(rig: CameraRig) -> void:
	_wait += 1
	if _target == null:
		if _wait > 4000:
			_finish()
			return
		for p in main.cetaceans._pods:
			if p.visit != visit:
				continue
			for o in p.animals:
				if o.state != Cetaceans.State.UNDER and o.t < 0.3:
					_target = o
					_burst = 0
					_wait = 0
					break
		return
	var o := _target
	rig.follow = null
	rig.target_pos = Vector3(o.pos.x, 0.0, o.pos.z)
	rig.target_yaw = o.yaw + PI * 0.5 + 0.4
	rig.target_pitch = 0.2
	rig.target_dist = maxf(o.length * 1.8, 14.0)
	rig.snap()
	var every := maxi(int(o.dur * 30.0 / 5.0), 6)
	if _wait % every == 0:
		_save("%s_%d_%s" % [jobs[job][0], _burst, Cetaceans.State.keys()[o.state].to_lower()])
		_burst += 1
		if _burst >= 6 or (o.state == Cetaceans.State.UNDER and _burst > 2):
			if _burst >= 6 or _shots.size() > 0:
				_finish()
				return
			# One more breath, with a different one if it comes.
			_shots = [1]
			_target = null


func _save(name: String) -> void:
	var path := "%s/%s.png" % [out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " ", main.sim.clock_text())


func _finish() -> void:
	if visit and visit.active():
		main.sim.wildlife._end(visit)
	visit = null
	_target = null
	_shots = []
	Engine.time_scale = 1.0
