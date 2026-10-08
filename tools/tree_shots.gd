extends SceneTree
## Renders an island forest close up, mid and far (across the tree LOD switch) for
## checking the trees by eye. Add --classic-trees to compare with the old ones.
##   godot --path . --script tools/tree_shots.gd -- --seed=9164 --out=DIR

var main: Node
var frames := 0
var out := "user://"
var shots := 0
var spot := Vector3.ZERO
# [distance, pitch, yaw offset]
const VIEWS := [[40.0, 0.3, 0.0], [60.0, 0.65, 1.2], [120.0, 0.55, 2.0], [260.0, 0.75, 0.5], [450.0, 0.85, 0.5]]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


## The middle of the busiest pine tile.
func _find_spot() -> Vector3:
	var best: MultiMeshInstance3D = null
	for n in main.find_children("Pines*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if best == null or mmi.multimesh.instance_count > best.multimesh.instance_count:
			best = mmi
	var mm := best.multimesh
	return mm.get_instance_transform(mm.instance_count / 2).origin


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		spot = _find_spot()
		print("forest spot ", spot)
	if frames < 60:
		return false
	if shots >= VIEWS.size():
		return true
	var v: Array = VIEWS[shots]
	main.rig.focus_on(spot, v[0])
	main.rig.distance = v[0]
	main.rig.target_pitch = v[1]
	main.rig.pitch = v[1]
	main.rig.target_yaw = v[2]
	main.rig.yaw = v[2]
	if not has_meta("wait"):
		set_meta("wait", frames)
	if frames - int(get_meta("wait")) < 40:
		return false
	remove_meta("wait")
	root.get_viewport().get_texture().get_image().save_png("%s/trees_%d.png" % [out, shots])
	shots += 1
	return false
