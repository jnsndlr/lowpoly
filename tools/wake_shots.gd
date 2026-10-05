extends SceneTree
## Renders close-ups of a cargo ship's and a sailboat's wakes for checking by eye.
##   godot --path . --script tools/wake_shots.gd -- --out=/some/dir

var main: Node
var frames := 0
var out := "user://"
var shots := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _pick(kind: String) -> Vessel:
	var all: Array = []
	all.append_array(main.sim.ferries)
	all.append_array(main.sim.marine.vessels)
	for v in all:
		if is_instance_valid(v) and v.kind_text() == kind and v.wants_to_move() and v.speed > 0.5 * v.cruise:
			return v
	return null


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		Engine.time_scale = 4.0
	if frames < 400:
		return false
	Engine.time_scale = 1.0
	var kinds := ["Cargo ship", "Sailboat", "Cargo ship", "Ferry"]
	var dists := [140.0, 60.0, 75.0, 70.0]
	var yaws := [0.5, 1.4, 2.4, 2.4]
	if shots >= kinds.size():
		return true
	var v := _pick(kinds[shots])
	if v == null:
		if frames > 4000:
			return true
		Engine.time_scale = 4.0
		return false
	main.rig.follow = v
	main.rig.target_dist = dists[shots]
	main.rig.distance = dists[shots]
	main.rig.target_pitch = 0.7
	main.rig.pitch = 0.7
	main.rig.target_yaw = atan2(-v.heading2().x, -v.heading2().y) + yaws[shots]
	main.rig.yaw = main.rig.target_yaw
	if not has_meta("wait"):
		set_meta("wait", frames)
	if frames - int(get_meta("wait")) < 60:
		return false
	remove_meta("wait")
	root.get_viewport().get_texture().get_image().save_png("%s/wake_%d.png" % [out, shots])
	print("shot ", kinds[shots], " ", v.vessel_name)
	shots += 1
	return false
