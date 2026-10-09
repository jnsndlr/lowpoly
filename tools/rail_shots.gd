extends SceneTree
## Renders a run of consecutive frames of a ferry's upper deck from a camera riding
## abeam and above it, once it's under way, for checking how the rail shadows hold up
## (thin casters break into dashes that crawl as the ship moves).
##   godot --path . --script tools/rail_shots.gd -- --seed=N --ferry-sizes=4 --out=DIR
##   [--time=H] [--frames=6] [--every=2] [--side=K] [--up=K] (camera offset, metres)

var main: Node
var frames := 0
var out := "user://"
var count := 6
var every := 2
var side := 28.0
var up := 34.0
var seq := 0
var _next := -1
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--frames="):
			count = int(a.substr(9))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--side="):
			side = float(a.substr(7))
		elif a.begins_with("--up="):
			up = float(a.substr(5))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	var f: Ferry = main.sim.ferries[0]
	if f.state != Ferry.State.SAILING or f.speed < f.fc.cruise * 0.8:
		Engine.time_scale = 8.0
		return false
	Engine.time_scale = 1.0
	if cam == null:
		# Zoomed in, as a player looking at her would be (main.gd sizes the shadows by it).
		main.rig.target_dist = 60.0
		main.rig.snap()
		cam = Camera3D.new()
		cam.fov = 40.0
		f.add_child(cam)
		cam.position = Vector3(f.fc.half_beam + side, Layout.DECK_Y + up, 6.0)
		cam.look_at(f.to_global(Vector3(0, Layout.DECK_Y + 9.0, 0)))
		cam.make_current()
		_next = frames + 20
		return false
	if frames < _next:
		return false
	root.get_viewport().get_texture().get_image().save_png("%s/rails_size%d_%02d.png" % [out, f.fc.size, seq])
	seq += 1
	_next = frames + every
	return seq >= count
