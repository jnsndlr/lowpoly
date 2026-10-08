extends SceneTree
## Follows one sailboat under way from overhead at midday and saves a frame every
## couple of seconds, for checking its wake (turns included) by eye.
##   godot --path . --script tools/sail_wake_seq.gd -- --out=/some/dir

var main: Node
var frames := 0
var out := "user://"
var boat: Sailboat
var shots := 0
var next_at := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		main.sim.minutes = 10.0 * 60.0
		main.day_cycle.set_hour(12.0)
	if frames < 30:
		return false
	if boat == null or not is_instance_valid(boat) or boat.state != Sailboat.State.SAILING:
		boat = null
		for b in main.sim.marine.sailboats:
			if b.state == Sailboat.State.SAILING and not b.motoring and b.path_left() > 360.0:
				boat = b
				break
		if boat == null:
			Engine.time_scale = 4.0
			return frames > 6000
		Engine.time_scale = 1.0
		main.rig.follow = boat
		main.rig.target_dist = 135.0
		main.rig.distance = 135.0
		main.rig.target_pitch = 1.3
		main.rig.pitch = 1.3
		next_at = frames + 90
	if frames >= next_at:
		root.get_viewport().get_texture().get_image().save_png("%s/sail_%02d.png" % [out, shots])
		shots += 1
		next_at = frames + 60
	return shots >= 12
