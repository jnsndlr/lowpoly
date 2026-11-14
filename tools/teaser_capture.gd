extends SceneTree
## Records the teaser's shots from the running game as PNG sequences. Each shot
## fast-forwards until its moment comes, then plays a scripted camera move at exactly
## --fixed-fps, however long each frame takes to render, so the footage is always smooth.
## Use tools/teaser_capture.sh, which also encodes the shots and cuts them together:
##   godot --path . --resolution 1920x1080 --fixed-fps 60 --script tools/teaser_capture.gd --
##     --seed=N --out=DIR [--fps=60] [--only=name,name] [--first-frame] [--ferry-sizes=...]
## --first-frame saves one still per shot, to check the framing in seconds, not minutes.
##
## The camera poses are [yaw, pitch, distance, height of the point looked at], as on the
## CameraRig, with yaw measured from astern (vessels) or from seaward (terminals). A shot
## eases from `a` to `b`. Its anchor says what the look point does: "world" stays put,
## "track" follows the subject, "ride" also turns with it. "lead" looks that many seconds
## ahead of a moving subject, and "speed" overrides SLOW. The orca is staged: its pod is put beside a sailing ferry
## and one animal is made to breach on cue (see _stage_orcas).

const START_HOUR := 8.5        # let the morning's traffic build up
const FAST := 4.0              # fast-forward rate
const HUNT_LIMIT := 900.0      # game minutes to wait for a shot before giving up
const SETTLE := 45             # frames for temporal effects to catch up after a cut
const MIN_EYE := 1.6
const SLOW := 0.5              # the sim's speed while rolling: game time is quick, ships need weight
const ORCA_LEAD := 4.0         # seconds for the staged pod to rise and settle

# In edit order; capture runs the morning-only trawler first and the slow pilot job last.
# "cut" is [in, length], in seconds of footage.
var shots: Array[Dictionary] = [
	{"name": "01_dawn", "find": "ferry", "dur": 5.0, "cut": [1.0, 3.0], "hour": [6.1, 6.2], "anchor": "world", "lead": 1.0,
		"a": [1.4, 0.02, 240.0, 9.0], "b": [1.3, 0.02, 228.0, 9.0]},
	{"name": "02_queue", "find": "queue", "dur": 5.0, "cut": [1.0, 3.0], "hour": [7.2, 7.25], "anchor": "world",
		"a": [0.0, 0.06, 16.0, 4.5], "b": [0.0, 0.06, 10.0, 4.5]},
	{"name": "03_ramp", "find": "arrival", "dur": 30.0, "cut": [4.5, 3.0], "hour": [9.0, 9.1], "anchor": "world", "speed": 1.0,
		"a": [-2.55, 0.26, 60.0, 6.0], "b": [-2.45, 0.24, 54.0, 6.0]},
	{"name": "04_ride", "find": "ferry", "dur": 5.0, "cut": [1.0, 3.0], "hour": [10.5, 10.55], "anchor": "ride",
		"a": [0.5, 0.22, 135.0, 6.0], "b": [0.36, 0.2, 124.0, 6.0]},
	{"name": "05_traffic", "find": "sail_near", "dur": 4.0, "cut": [1.0, 2.0], "hour": [12.0, 12.05], "anchor": "track",
		"a": [2.3, 0.32, 210.0, 3.0], "b": [2.15, 0.3, 190.0, 3.0]},
	{"name": "06_pilot", "find": "pilot", "dur": 4.0, "cut": [1.0, 2.0], "hour": [13.0, 13.05], "anchor": "track", "last": true,
		"a": [1.7, 0.3, 90.0, 5.0], "b": [1.55, 0.28, 74.0, 6.0]},
	{"name": "07_trawler", "find": "trawler", "dur": 4.0, "cut": [1.0, 2.0], "hour": [14.5, 14.55], "anchor": "track",
		"first": true, "a": [0.95, 0.34, 120.0, 3.0], "b": [0.75, 0.3, 104.0, 3.0]},
	{"name": "08_orca", "find": "orcas", "dur": 6.0, "cut": [0.8, 3.0], "hour": [16.2, 16.25], "anchor": "world",
		"a": [0.1, 0.05, 36.0, 3.5], "b": [0.1, 0.05, 32.0, 3.5], "breach": 1.4, "speed": 0.8},
	{"name": "09_dusk", "find": "queue_wide", "dur": 6.0, "cut": [1.0, 4.0], "hour": [18.5, 20.6], "anchor": "world",
		"a": [0.9, 0.2, 250.0, 6.0], "b": [0.8, 0.16, 190.0, 6.0]},
	{"name": "10_pullback", "find": "ferry", "dur": 7.0, "cut": [1.0, 5.0], "hour": [21.5, 21.5], "anchor": "track",
		"a": [0.7, 0.2, 70.0, 6.0], "b": [1.3, 1.0, 3800.0, 0.0], "hud": 0.62},
]

var main: Node
var sim: Simulation
var rig: CameraRig
var out := "user://"
var fps := 60
var only: PackedStringArray = []
var first_frame := false

var _queue: Array[Dictionary] = []
var _s: Dictionary
var _step := 0                 # 0 warming up, 1 hunting, 2 orcas rising, 3 settling, 4 rolling
var _hunted := 0.0
var _wait := 0
var _frame := 0
var _frames := 0
var _dir := ""
var _ok := true
var _manifest: Array[String] = []

var _node: Node3D             # the subject, if it moves
var _look := Vector3.ZERO      # the look point, when it doesn't
var _yaw0 := 0.0
var _flip := 1.0               # mirrors the yaw when the first choice looks into a hill
var _hero: Cetaceans.Animal
var _pod: Cetaceans.Pod
var _ferry: Ferry
var _spot := Vector3.ZERO      # where the staged pod stays


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--fps="):
			fps = int(a.substr(6))
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--first-frame":
			first_frame = true
	for s in shots:
		if only.is_empty() or only.has(s["name"]):
			if s.has("first"):
				_queue.push_front(s)
			else:
				_queue.append(s)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return b.has("last") and not a.has("last"))
	main = load("res://scenes/sandbox.tscn").instantiate()
	main.set("uncapped", true)
	root.add_child(main)


func _process(delta: float) -> bool:
	if sim == null:
		sim = main.get("sim")
		rig = main.get("rig")
		rig.set_process(false)
		rig.set_process_unhandled_input(false)
		rig.follow = null
		_hud(0.0)
		Engine.time_scale = FAST
		return false
	match _step:
		0:
			if sim.hour() >= START_HOUR:
				return _next_shot()
		1:
			_hunted += delta
			if _find(str(_s["find"])):
				_hunted = 0.0
				Engine.time_scale = 1.0 if _hero else _speed()
				_wait = 0
				_step = 2 if _hero else 3
			elif _hunted > HUNT_LIMIT:
				print("GAVE UP on ", _s["name"], " at ", sim.clock_text())
				_ok = false
				return _next_shot()
		2:
			_hold_hero()
			_wait += 1
			if _wait >= int(ORCA_LEAD * fps):
				_wait = 0
				_step = 3
				Engine.time_scale = _speed()
				_aim_orca()
		3:
			_hold_hero()
			_camera(0.0)
			RenderingServer.force_draw(false)   # the reflected sky has to catch up too
			_wait += 1
			if _wait >= SETTLE:
				if absf(delta / Engine.time_scale - 1.0 / fps) > 1e-4:
					push_error("delta %f doesn't match --fps=%d: run with --fixed-fps %d" % [delta, fps, fps])
					_ok = false
					return true
				_step = 4
				_frame = 0
				_frames = 1 if first_frame else int(float(_s["dur"]) * fps)
		4:
			if _frame > 0:
				_save()
				if _frame >= _frames:
					print("done ", _s["name"], " ", sim.clock_text(), " ", _subject_text())
					_manifest.append("%s %f %f" % [_s["name"], float(_s["cut"][0]), float(_s["cut"][1])])
					return _next_shot()
			_hold_hero()
			if _hero and _s.has("breach") and _frame == int(float(_s["breach"]) * fps):
				_breach()
			_camera(float(_frame) / maxf(_frames - 1, 1))
			_frame += 1
	return false


func _speed() -> float:
	return float(_s.get("speed", SLOW))


func _next_shot() -> bool:
	_hero = null
	_pod = null
	_node = null
	_ferry = null
	_flip = 1.0
	_hud(0.0)
	if _queue.is_empty():
		# A partial run keeps the lines for the shots it didn't redo.
		var path := "%s/shots.txt" % out
		if FileAccess.file_exists(path):
			_manifest.append_array(FileAccess.get_file_as_string(path).split("\n", false))
		var f := FileAccess.open(path, FileAccess.WRITE)
		for s in shots:
			for line in _manifest:
				if line.begins_with(str(s["name"]) + " "):
					f.store_line(line)
					break
		print("TEASER DONE" if _ok else "TEASER INCOMPLETE")
		return true
	_s = _queue.pop_front()
	_dir = "%s/%s" % [out, _s["name"]]
	DirAccess.make_dir_recursive_absolute(_dir)
	_step = 1
	_hunted = 0.0
	Engine.time_scale = FAST
	print("hunting ", _s["name"], " at ", sim.clock_text())
	return false


func _save() -> void:
	# Godot stops drawing a window that's covered up; these frames must be drawn anyway.
	RenderingServer.force_draw(false)
	var img := root.get_viewport().get_texture().get_image()
	if _frame == 1:
		print("%s: %dx%d, %d frames" % [_s["name"], img.get_width(), img.get_height(), _frames])
	img.save_png("%s/%05d.png" % [_dir, _frame])


# --- The camera --------------------------------------------------------------------

func _pose(t: float) -> Array[float]:
	var a: Array = _s["a"]
	var b: Array = _s["b"]
	var k := smoothstep(0.0, 1.0, t)
	return [_flip * lerp_angle(float(a[0]), float(b[0]), k), lerpf(a[1], b[1], k),
		exp(lerpf(log(float(a[2])), log(float(b[2])), k)), lerpf(a[3], b[3], k)]


func _eye(look: Vector3, yaw: float, p: Array[float]) -> Vector3:
	return look + Basis(Vector3.UP, yaw + p[0]) * Basis(Vector3.RIGHT, -p[1]) * Vector3(0.0, 0.0, p[2])


## Where the shot looks and which way yaw 0 points now, as [look, yaw].
func _anchor() -> Array:
	var anchor := str(_s["anchor"])
	if _node == null or (anchor == "world" and _step >= 3):
		return [_look, _yaw0]
	var at := Vector3(_node.global_position.x, 0.0, _node.global_position.z)
	return [at, _vessel_yaw(_node as Vessel) if anchor == "ride" else _yaw0]


func _vessel_yaw(v: Vessel) -> float:
	var h := v.heading2()
	return atan2(-h.x, -h.y)


func _camera(t: float) -> void:
	var p := _pose(t)
	var at: Array = _anchor()
	var look: Vector3 = at[0]
	look.y = p[3]
	var eye := _eye(look, at[1], p)
	eye.y = maxf(eye.y, maxf(sim.terrain.height_at(eye.x, eye.z), 0.0) + MIN_EYE)
	var cam := rig.camera
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	# Fog, shadow cascades and focus are all set from the rig; keep them on this view.
	rig.position = look
	rig.distance = eye.distance_to(look)
	rig.target_pos = look
	rig.target_dist = rig.distance
	var h: Array = _s["hour"]
	var day: DayCycle = main.get("day_cycle")
	day.set_hour(lerpf(h[0], h[1], t))
	day.apply(day.hour())
	if _s.has("hud"):
		var from: float = _s["hud"]
		_hud(smoothstep(from, minf(from + 0.25, 1.0), t))


func _hud(a: float) -> void:
	var hud: Hud = main.get("hud")
	hud.visible = a > 0.0
	for c in hud.get_children():
		if c is CanvasItem:
			(c as CanvasItem).modulate.a = a


## Fixes the frame for a shot on its subject, mirrored if the view is blocked. False if
## it's blocked both ways, so the hunt goes on.
func _aim() -> bool:
	var at: Array = _anchor()
	_look = at[0]
	if str(_s["anchor"]) == "world" and _s.has("lead") and _node is Vessel:
		var v := _node as Vessel
		var h := v.heading2()
		_look += Vector3(h.x, 0.0, h.y) * v.speed * float(_s["lead"])
	_flip = 1.0
	if _blocked():
		_flip = -1.0
		return not _blocked()
	return true


func _blocked() -> bool:
	var p := _pose(0.0)
	var look := Vector3(_look.x, p[3], _look.z)
	var eye := _eye(look, _yaw0, p)
	for i in range(1, 15):
		var q := eye.lerp(look, i / 15.0)
		if sim.terrain.height_at(q.x, q.z) > q.y - 1.0:
			return true
	return false


# --- Finding the moment ---------------------------------------------------------------

func _find(what: String) -> bool:
	match what:
		"ferry":
			return _use(_big_ferry(450.0))
		"arrival":
			var f := _arriving_ferry()
			if f == null:
				return false
			var term := f.destination()
			var v: float = term.slip_v[f.route.id]
			return _set_terminal(term, term.to_global(Vector3(v, 0.0, 8.0)))
		"queue", "queue_wide":
			return _find_queue(what == "queue")
		"sail_near":
			return _use(_sail_near_traffic())
		"pilot":
			for b in sim.marine.pilotage.pilot_boats:
				if b.state == ShipTender.State.WORKING:
					return _use(b)
		"trawler":
			for b in sim.marine.fishing_boats:
				if b.fishing() and b.work == FishingBoat.Work.TOWING:
					return _use(b)
		"orcas":
			return _stage_orcas()
	return false


func _use(v: Vessel) -> bool:
	if v == null:
		return false
	_node = v
	_yaw0 = _vessel_yaw(v)
	return _aim()


## The biggest ferry well under way with at least `room` metres still to run.
func _big_ferry(room: float) -> Ferry:
	var best: Ferry = null
	for f in sim.ferries:
		if f.state != Ferry.State.SAILING or f.speed < f.fc.cruise * 0.8 or f.run_length() - f.traveled < room:
			continue
		if best == null or f.fc.size > best.fc.size:
			best = f
	return best


func _arriving_ferry() -> Ferry:
	var best: Ferry = null
	for f in sim.ferries:
		var rem := f.run_length() - f.traveled
		if f.state == Ferry.State.SAILING and rem < 220.0 and (best == null or f.fc.size > best.fc.size):
			best = f
	return best


func _sail_near_traffic() -> Sailboat:
	for s in sim.marine.sailboats:
		if s.state != Sailboat.State.SAILING:
			continue
		for f in sim.ferries:
			if f.state == Ferry.State.SAILING and s.pos2().distance_to(f.pos2()) < 300.0:
				return s
		for c in sim.marine.cargo_ships:
			if s.pos2().distance_to(c.pos2()) < 420.0:
				return s
	return null


func _find_queue(along_lane: bool) -> bool:
	var best: Terminal = null
	for term: Terminal in sim.terminals.values():
		if best == null or term.total_queued() > best.total_queued():
			best = term
	if best == null or best.total_queued() < 6:
		return false
	var v := 0.0
	var most := -1
	for rid in best.lanes:
		for lane: Dictionary in best.lanes[rid]:
			if (lane["queue"] as Array).size() > most:
				most = (lane["queue"] as Array).size()
				v = lane["v"]
	# Between the fullest lane and the next, from its seaward head, or the whole lot from further off.
	var at := Vector3(v + Layout.LANE_WIDTH * 0.5, 0.0, -26.0) if along_lane else Vector3(0.0, 0.0, -30.0)
	return _set_terminal(best, best.to_global(at))


func _set_terminal(term: Terminal, at: Vector3) -> bool:
	_node = null
	var sea := term.global_transform.basis.z
	_yaw0 = atan2(sea.x, sea.z)
	_look = Vector3(at.x, 0.0, at.z)
	return _aim()


## Starts an orca visit with the pod placed so one animal surfaces abeam of a sailing
## ferry at the moment of the breach, and the rest of the pod breathing around it.
func _stage_orcas() -> bool:
	var f := _big_ferry(600.0)
	if f == null:
		return false
	var at := _ferry_after(f, ORCA_LEAD + _to_breach())
	var along := _ferry_after(f, ORCA_LEAD + _to_breach() + 1.0) - at
	var abeam := Vector3(-along.z, 0.0, along.x).normalized()
	var sp := sim.wildlife.find_species("orca")
	for side: float in [1.0, -1.0]:
		var spot := at + abeam * side * 95.0
		var eye := at + abeam * side * 190.0
		if sim.terrain.height_at(spot.x, spot.z) > sp.depth - 4.0 or sim.terrain.height_at(eye.x, eye.z) > -1.0:
			continue
		var v := sim.wildlife.start_visit(sp)
		if v == null:
			return false
		var cet: Cetaceans = main.get("cetaceans")
		for p in cet._pods:
			if p.visit == v:
				_pod = p
		if _pod == null:
			return false
		_ferry = f
		_pod.dive = 0.0
		for o in _pod.animals:
			if o.mother == null and (_hero == null or o.length > _hero.length):
				_hero = o
		_spot = spot - Basis(Vector3.UP, v.heading) * _hero.offset
		for o in _pod.animals:
			var base := _spot if o.mother == null else o.mother.pos
			o.pos = base + Basis(Vector3.UP, o.yaw) * o.offset
			o.state = Cetaceans.State.UNDER
			o.y = -2.0
			o.breaths = 3
			o.wait = randf_range(0.5, 5.0)
		_hold_hero()
		return true
	return false


## Game seconds from the settle starting to the breach.
func _to_breach() -> float:
	return (float(SETTLE) / fps + float(_s["breach"])) * _speed()


func _ferry_after(f: Ferry, t: float) -> Vector3:
	var p := f.route_point(f._route_s(f.traveled + f.speed * t))
	return Vector3(p.x, 0.0, p.z)


## The pod stays put, and the hero just under the surface until its cue.
func _hold_hero() -> void:
	if _hero == null:
		return
	_pod.visit.pos = _spot
	if _hero.state == Cetaceans.State.UNDER and _hero.breaths > 0:
		_hero.wait = 99.0


func _aim_orca() -> void:
	var away := _hero.pos - _ferry_after(_ferry, _to_breach())
	_look = Vector3(_hero.pos.x, 0.0, _hero.pos.z)
	_yaw0 = atan2(away.x, away.z)
	_flip = 1.0


func _breach() -> void:
	var o := _hero
	o.state = Cetaceans.State.BREACH
	o.t = 0.0
	o.y0 = o.y
	o.blown = false
	o.dur = 2.4 + 0.05 * o.length


func _subject_text() -> String:
	if _hero:
		return "orca %.0f m from %s" % [Vector2(_hero.pos.x, _hero.pos.z).distance_to(_ferry.pos2()), _ferry.ferry_name]
	return (_node as Vessel).status_text() if _node is Vessel else ""
