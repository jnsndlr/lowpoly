extends SceneTree
## Headless check for vehicles driving into each other: runs a map at 4x and counts
## pairs of vehicles (bumper-to-tail capsules a car wide) that overlap, printing a NEW
## line the first time each pair of models does, those that stay overlapped for 4+
## checks, and any vehicle under way held still for 150 checks (STALL, with what
## blocks it).
##
##   godot --headless --path . --fixed-fps 30 --script tools/vehicle_overlap_test.gd -- --seed=123 --frames=6000

const HALF_W := 0.9

var main: Node
var frames := 0
var max_frames := 6000
var pairs := {}
var hits := 0
var worst := 0.0
var vehicles_seen := 0
var _last_pos := {}
var _still := {}
var stalls := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			max_frames = int(a.substr(9))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Vehicle:
			out.append(c)
		elif c is Node3D:
			_collect(c, out)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		Engine.time_scale = 4.0
	if frames >= max_frames:
		print("stalls %d" % stalls)
		print("vehicles max %d, overlapping pairs %d, pair-frames %d, worst depth %.2f" % [vehicles_seen, pairs.size(), hits, worst])
		var lasting := 0
		for p in pairs.keys():
			if pairs[p] >= 4:
				lasting += 1
				print("  ", p, " x", pairs[p])
		print("lasting (>= 4 checks) %d" % lasting)
		return true
	if frames % 5 != 0:
		return false
	var vs: Array = []
	_collect(main.sim, vs)
	vehicles_seen = maxi(vehicles_seen, vs.size())
	for v: Vehicle in Vehicle._moving:
		var p := v.global_position
		if _last_pos.has(v) and p.distance_to(_last_pos[v]) < 0.01 and v.delay <= 0.0:
			_still[v] = _still.get(v, 0) + 1
			if _still[v] == 150:
				stalls += 1
				var why := ""
				for o: Vehicle in Vehicle._moving:
					if o != v and v._room_to(o) < 0.5:
						why += " %s(%s leader=%s d=%.1f fwd·=%.2f)" % [o.model, o.global_position, o == v.leader, o.global_position.distance_to(p), o._g_fwd.dot(v._g_fwd)]
				print("STALL %s at %s path %d blocked by:%s" % [v.model, p, v.path.size(), why])
		else:
			_still[v] = 0
		_last_pos[v] = p
	var seg := []
	for v: Vehicle in vs:
		var f := v._front()
		var t := v._tail()
		# (Pulled in by the half-width at each end: the capsule then ends at the bumpers.)
		var a := Vector2(f.x, f.z)
		var b := Vector2(t.x, t.z)
		var d := (b - a).normalized() * HALF_W
		seg.append([a + d, b - d, (f.y + t.y) * 0.5])
	for i in vs.size():
		for j in range(i + 1, vs.size()):
			if absf(seg[i][2] - seg[j][2]) > 1.5:
				continue
			if seg[i][0].distance_to(seg[j][0]) > 60.0:
				continue
			var cp := Geometry2D.get_closest_points_between_segments(seg[i][0], seg[i][1], seg[j][0], seg[j][1])
			var d: float = cp[0].distance_to(cp[1])
			if d < 2.0 * HALF_W:
				var a: Vehicle = vs[i]
				var b: Vehicle = vs[j]
				var key := "%s(%s)/%s(%s)" % [a.model, "m" if a.is_processing() else "p", b.model, "m" if b.is_processing() else "p"]
				if not pairs.has(key):
					var rel := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
					var fa := Vector2(a.global_transform.basis.z.x, a.global_transform.basis.z.z).normalized()
					print("NEW %s  in %s/%s  along %.1f lat %.1f  len %.1f/%.1f  slots %d/%d  leader %s  path %d/%d" % [key, a.get_parent().name, b.get_parent().name,
						rel.dot(fa), rel.cross(fa), a.length, b.length, a.slots, b.slots, a.leader == b or b.leader == a, a.path.size(), b.path.size()])
				pairs[key] = pairs.get(key, 0) + 1
				hits += 1
				worst = maxf(worst, 2.0 * HALF_W - d)
	return false
