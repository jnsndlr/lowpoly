extends SceneTree
## Renders a trawler at work (by day and by night, close up and from further off)
## and the fish quays, for checking by eye.
##   godot --path . --resolution 1600x900 --script tools/fishing_shots.gd -- --seed=123 --out=/some/dir

var main: Node
var frames := 0
var out := "user://"
# [what, hour, yaw (from astern, or from the quay's seaward side), pitch, distance]
var shots := [
	["boat", 10.0, 0.9, 0.42, 135.0],
	["boat", 10.0, 2.6, 0.3, 96.0],
	["boat", 10.0, 0.4, 0.95, 360.0],
	["boat", 4.8, 0.9, 0.42, 135.0],
	["boat", 4.8, 2.2, 0.75, 330.0],
	["quay", 11.0, 0.6, 0.55, 210.0],
	["quay", 22.5, 0.6, 0.5, 210.0],
	["crabbing", -1.0, 0.6, 0.6, 225.0],
	["alongside", -1.0, 0.6, 0.55, 210.0],
]
const WARM_UP := 900
var shot := 0
var _wait := 0
var _boat: FishingBoat


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	# Let the gulls find the boats first.
	if frames == 5:
		Engine.time_scale = 3.0
	if frames < WARM_UP:
		return false
	Engine.time_scale = 1.0
	if shot >= shots.size():
		return true
	var s: Array = shots[shot]
	var rig: CameraRig = main.rig
	# Wait (fast) for a boat to come in, then to have been alongside a while.
	if (s[0] == "crabbing" or s[0] == "alongside") and _wait == 0:
		var b := _boat_doing(s[0])
		if b == null:
			Engine.time_scale = 8.0
			if frames > 60000:
				return true
			return false
		Engine.time_scale = 1.0
		_boat = b
		rig.follow = null
		rig.target_pos = Vector3(b.global_position.x, 0.0, b.global_position.z)
		var y: float = atan2(-b.quay.dir.x, -b.quay.dir.z) + s[2]
		rig.target_yaw = y
		rig.yaw = y
		rig.target_pitch = s[3]
		rig.pitch = s[3]
		rig.target_dist = s[4]
		rig.distance = s[4]
		_wait = 1
		return false
	if _wait == 0:
		var yaw: float = s[2]
		if s[0] == "boat":
			_boat = _working_boat()
			if _boat == null:
				print("no trawler at work")
				shot += 1
				return false
			if shot == 0:
				main.hud.select_vessel(_boat)
			elif shot == 1:
				main.hud.clear_selection()
			rig.follow = _boat
			var h := _boat.heading2()
			yaw += atan2(-h.x, -h.y)
		else:
			if main.sim.map.quays.is_empty():
				shot += 1
				return false
			var q: MapData.FishQuay = main.sim.map.quays[0]
			rig.follow = null
			rig.target_pos = q.at(Layout.QUAY_FACE_U, 0.0)
			yaw += atan2(-q.dir.x, -q.dir.z)
		if s[0] == "quay" or s[1] < 6.0:
			main.sim.minutes = s[1] * 60.0
		rig.target_yaw = yaw
		rig.yaw = yaw
		rig.target_pitch = s[3]
		rig.pitch = s[3]
		rig.target_dist = s[4]
		rig.distance = s[4]
	_wait += 1
	if _wait < 90:
		return false
	_wait = 0
	var path := "%s/fish_%d.png" % [out, shot]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " ", s[0], " ", main.sim.clock_text(), " ", _boat.status_text() if s[0] != "quay" and _boat else "")
	shot += 1
	return false


func _working_boat() -> FishingBoat:
	for f in main.sim.marine.fishing_boats:
		if f.fishing() and f.work == FishingBoat.Work.TOWING:
			return f
	for f in main.sim.marine.fishing_boats:
		if f.wants_to_move():
			return f
	return null


var _alongside_since := {}

func _boat_doing(what: String) -> FishingBoat:
	for f in main.sim.marine.fishing_boats:
		if what == "crabbing" and f.crabbing() and f.state == FishingBoat.State.ARRIVING:
			return f
		if what == "alongside":
			if f.state != FishingBoat.State.ALONGSIDE:
				_alongside_since.erase(f)
			elif not _alongside_since.has(f):
				_alongside_since[f] = frames
			elif frames - int(_alongside_since[f]) > 900:
				return f
	return null
