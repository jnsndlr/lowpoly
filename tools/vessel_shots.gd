extends SceneTree
## Renders the motor yachts, pilot boats and tugs at work (fast-forwarding until
## each thing happens), for checking by eye: a yacht on the plane and at anchor
## in a cove by day and night, a pilot boat running out to a ship and alongside
## it, a tug escorting a tanker, and the pilot station.
##   godot --path . --resolution 1600x900 --script tools/vessel_shots.gd -- --seed=123 --out=/some/dir [--only=name,name]

var main: Node
var frames := 0
var out := "user://"
var only: PackedStringArray = []
# [name, what to wait for, yaw (from astern, or the station's seaward side), pitch, distance, hour to show it at (-1: as it is)]
var shots := [
	["yacht_plane", "planing", 0.9, 0.3, 26.0, -1.0],
	["yacht_plane_side", "planing", 1.7, 0.18, 22.0, -1.0],
	["yacht_anchor", "anchored", 0.8, 0.35, 28.0, -1.0],
	["cove", "anchored", 0.6, 0.85, 140.0, -1.0],
	["yacht_anchor_night", "anchored", 0.8, 0.35, 30.0, 22.5],
	["pilot_out", "pilot_running", 0.8, 0.3, 30.0, -1.0],
	["pilot_closing", "pilot_closing", 2.0, 0.45, 70.0, -1.0],
	["pilot_alongside", "pilot_alongside", 1.7, 0.4, 45.0, -1.0],
	["pilot_alongside_b", "pilot_alongside", -1.7, 0.4, 45.0, -1.0],
	["pilot_ladder", "pilot_alongside", -1.45, 0.3, 20.0, -1.0],
	["pilot_ladder_b", "pilot_alongside", 1.45, 0.3, 20.0, -1.0],
	["pilot_alongside_high", "pilot_alongside", 1.2, 0.95, 90.0, -1.0],
	["pilot_night", "pilot_alongside", 1.9, 0.4, 50.0, 23.0],
	["tug_escort", "tug_escort", 0.5, 0.55, 120.0, -1.0],
	["tug_close", "tug_escort", 1.0, 0.3, 40.0, -1.0],
	["station", "station", 0.6, 0.55, 75.0, 11.0],
	["station_night", "station", 0.6, 0.5, 75.0, 22.0],
]
const WARM_UP := 300
const GIVE_UP := 40000
var shot := 0
var _wait := 0
var _v: Vessel
var _start := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		Engine.time_scale = 3.0
	if frames < WARM_UP:
		return false
	while shot < shots.size() and not only.is_empty() and not only.has(shots[shot][0]):
		shot += 1
	if shot >= shots.size():
		return true
	var s: Array = shots[shot]
	var rig: CameraRig = main.rig
	if _wait == 0:
		if _start == 0:
			_start = frames
		_v = _find(s[1])
		if _v == null and s[1] != "station":
			Engine.time_scale = 8.0
			if frames - _start > GIVE_UP:
				print("gave up on ", s[0])
				shot += 1
				_start = 0
			return false
		Engine.time_scale = 1.0
		_start = 0
		var yaw: float = s[2]
		if s[1] == "station":
			if main.sim.map.stations.is_empty():
				print("no pilot station")
				shot += 1
				return false
			var q: MapData.PilotStation = main.sim.map.stations[0]
			rig.follow = null
			rig.target_pos = q.at(Layout.QUAY_FACE_U, 0.0)
			yaw += atan2(-q.dir.x, -q.dir.z)
		else:
			# Framing the ship and its tender together for the wide shots.
			var target: Vessel = _v
			if s[1] == "tug_escort" and s[4] > 80.0:
				target = (_v as Tug).ship
			rig.follow = target
			var h := _v.heading2()
			yaw += atan2(-h.x, -h.y)
		if s[5] >= 0.0:
			main.sim.minutes = s[5] * 60.0
		rig.target_yaw = yaw
		rig.yaw = yaw
		rig.target_pitch = s[3]
		rig.pitch = s[3]
		rig.target_dist = s[4]
		rig.distance = s[4]
	_wait += 1
	if _wait < 75:
		return false
	_wait = 0
	var path := "%s/%s.png" % [out, s[0]]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " ", main.sim.clock_text(), " ", _v.vessel_name + ": " + _v.status_text() if _v else "")
	shot += 1
	return false


func _find(what: String) -> Vessel:
	var m: MarineTraffic = main.sim.marine
	match what:
		"planing":
			for y in m.motor_yachts:
				if y.state == MotorYacht.State.CRUISING and y.speed > y.cruise * 0.85:
					return y
		"anchored":
			for y in m.motor_yachts:
				if y.state == MotorYacht.State.ANCHORED:
					return y
		"pilot_running":
			for b in m.pilotage.pilot_boats:
				if b.state == ShipTender.State.OUTBOUND and b.speed > b.cruise * 0.8:
					return b
		"pilot_closing":
			for b in m.pilotage.pilot_boats:
				if b.state == ShipTender.State.CLOSING and b.pos2().distance_to(b.ship.pos2()) < 40.0:
					return b
		"pilot_alongside":
			for b in m.pilotage.pilot_boats:
				if b.state == ShipTender.State.WORKING:
					return b
		"tug_escort":
			for t in m.pilotage.tugs:
				if t.state == ShipTender.State.WORKING:
					return t
	return null
