extends SceneTree
## Renders each ferry close up, once early on and again later (so some are docked
## and some under way), for checking the ferry sizes by eye. Pass
## --ferry-sizes=1,2,3,4,5 to force sizes; --terminals renders each terminal's
## slips from above instead, every so often for a while.
##   godot --path . --script tools/ferry_shots.gd -- --seed=N [--ferry-sizes=1,2,3,4,5] --out=DIR [--time=H] [--terminals]
##   [--yaw=RAD] [--pitch=RAD] [--dist=K]  (camera about each ferry; default 2.3, 0.55, 1)

var main: Node
var frames := 0
var out := "user://"
var shot := 0
var pass_no := 0
var _wait := -1
var terminals := false
var yaw_off := 2.3
var pitch := 0.55
var dist_k := 1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--yaw="):
			yaw_off = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--dist="):
			dist_k = float(a.substr(7))
		elif a == "--terminals":
			terminals = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	if terminals:
		return _terminal_shots()
	var ferries: Array = main.sim.ferries
	if shot >= ferries.size():
		pass_no += 1
		if pass_no >= 2:
			return true
		shot = 0
		# Run on a while so the fleet is somewhere else.
		Engine.time_scale = 8.0
		_wait = frames + 300
		return false
	if _wait > frames and Engine.time_scale > 1.0:
		return false
	Engine.time_scale = 1.0
	var f: Ferry = ferries[shot]
	if _wait < 0 or Engine.time_scale > 1.0 or main.rig.follow != f:
		main.rig.follow = f
		var d := (22.0 + f.fc.half_length * 2.2) * dist_k
		main.rig.target_dist = d
		main.rig.distance = d
		main.rig.target_pitch = pitch
		main.rig.pitch = pitch
		var fwd := f.global_transform.basis.z
		main.rig.target_yaw = atan2(fwd.x, fwd.z) + yaw_off
		main.rig.yaw = main.rig.target_yaw
		_wait = frames + 40
		return false
	if frames < _wait:
		return false
	var path := "%s/ferry_%d_size%d_%s.png" % [out, pass_no, f.fc.size, "sailing" if f.state == Ferry.State.SAILING else "docked"]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " ", f.ferry_name, " ", f.status_text())
	shot += 1
	_wait = -1
	return false


func _terminal_shots() -> bool:
	var terms: Array = main.sim.terminals.values()
	if pass_no >= 3:
		return true
	if shot >= terms.size():
		pass_no += 1
		shot = 0
		Engine.time_scale = 8.0
		_wait = frames + 200
		return false
	if _wait > frames and Engine.time_scale > 1.0:
		return false
	Engine.time_scale = 1.0
	var isl: MapData.Island = (terms[shot] as Terminal).island
	if _wait < 0 or frames > _wait + 1:
		main.rig.follow = null
		main.rig.target_pos = isl.shore + isl.dock_dir * 24.0
		main.rig.target_dist = 75.0 + isl.slips.size() * 15.0
		main.rig.target_pitch = 1.15
		main.rig.target_yaw = atan2(-isl.dock_dir.x, -isl.dock_dir.z) + 0.5
		main.rig.snap()
		_wait = frames + 20
		return false
	if frames < _wait:
		return false
	var path := "%s/terminal_%d_%s.png" % [out, pass_no, isl.name.replace(" ", "_")]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	shot += 1
	_wait = -1
	return false
