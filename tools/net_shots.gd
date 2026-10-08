extends SceneTree
## Renders a short sequence of each ferry's car deck nets (Models.ferry_net) blowing
## in the wind, from a camera riding off the end of the hull, once the ferry is under way.
##   godot --path . --script tools/net_shots.gd -- --seed=N --ferry-sizes=1,2,3,4,5 --out=DIR
##   [--frames=8] [--every=5] (frames per ferry, and rendered frames between them)
##   [--top] (look straight down on the net, which shows its billow best)

var main: Node
var frames := 0
var out := "user://"
var count := 8
var every := 5
var shot := 0
var seq := 0
var _next := -1
var cam: Camera3D
var top := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--frames="):
			count = int(a.substr(9))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a == "--top":
			top = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	var ferries: Array = main.sim.ferries
	if shot >= ferries.size():
		return true
	var f: Ferry = ferries[shot]
	if f.state != Ferry.State.SAILING or f.speed < f.fc.cruise * 0.8:
		# Run on until it's well under way.
		Engine.time_scale = 8.0
		return false
	Engine.time_scale = 1.0
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 50.0
		f.add_child(cam)
		var w := f.fc.net_half_w
		var target := Vector3(0, Layout.DECK_Y + 1.2, f.fc.net_z)
		cam.position = Vector3(0.7 * w, Layout.DECK_Y + 6.0, f.fc.net_z + 11.0)
		var up := Vector3.UP
		if top:
			cam.position = Vector3(0, Layout.DECK_Y + 2.2 * w, f.fc.net_z)
			target = Vector3(0, Layout.DECK_Y, f.fc.net_z)
			up = f.global_basis.z
		cam.look_at(f.to_global(target), up)
		cam.make_current()
		_next = frames + 10
		return false
	if frames < _next:
		return false
	var path := "%s/net_size%d_%02d.png" % [out, f.fc.size, seq]
	root.get_viewport().get_texture().get_image().save_png(path)
	seq += 1
	_next = frames + every
	if seq >= count:
		print("shot ", f.ferry_name, " size ", f.fc.size, " net wind ", f._net_wind)
		cam.queue_free()
		cam = null
		seq = 0
		shot += 1
	return false
