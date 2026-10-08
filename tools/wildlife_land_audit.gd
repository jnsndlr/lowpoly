extends SceneTree
## Runs whale, orca and porpoise visits start to finish (headless, stepping the sim
## by hand) and counts how often a group's centre gets into water shallower than it
## swims in, and how often an animal is drawn over land (its middle or its nose).
##   godot --headless --path . --script tools/wildlife_land_audit.gd -- --seed=N [--visits=20] [--species=orca,humpback]

const DT := 0.25

var main: Node
var frames := 0
var visits := 20
var only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--visits="):
			visits = int(a.substr(9))
		elif a.begins_with("--species="):
			only = a.substr(10)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	var sim: Simulation = main.sim
	var w := sim.wildlife
	var cet: Cetaceans = main.cetaceans
	w.process_mode = Node.PROCESS_MODE_DISABLED
	cet.process_mode = Node.PROCESS_MODE_DISABLED
	var t := sim.terrain
	var bad := false
	for sp in w.species:
		if sp.behavior == Wildlife.Behavior.HAUL_OUT or (only != "" and not sp.id in only.split(",")):
			continue
		var shallow := 0
		var aground := 0
		var nose := 0
		var steps := 0
		var worst := -INF
		for i in visits:
			for v in w.active_visits():
				w._end(v)
			cet._pods.clear()
			var v := w.start_visit(sp)
			if v == null:
				continue
			var p: Cetaceans.Pod = cet._pods.back()
			var was_bad := false
			while v.active():
				w._tick(v, DT)
				cet._tick_pod(p, DT)
				steps += 1
				if t.height_at(v.pos.x, v.pos.z) > sp.depth + 1.2:
					shallow += 1
				for o in p.animals:
					var h := t.height_at(o.pos.x, o.pos.z)
					var f := o.pos + Vector3(sin(o.yaw), 0.0, cos(o.yaw)) * o.length * 0.5
					var hn := t.height_at(f.x, f.z)
					worst = maxf(worst, maxf(h, hn))
					if h > -0.9:
						aground += 1
						if not was_bad:
							was_bad = true
							print("  %s visit %d at %s: %s over land (h %.1f) phase %s" % [sp.id, i, v.target.name,
								Vector2(o.pos.x, o.pos.z), h, Wildlife.Phase.keys()[v.phase]])
					elif hn > -0.9:
						nose += 1
		print("%s: %d visits, %d steps; centre in shallows %d, animal over land %d, nose over land %d, highest ground under one %.2f" % [
			sp.id, visits, steps, shallow, aground, nose, worst])
		bad = bad or aground > 0
	print("DONE %s" % ("LAND" if bad else "clean"))
	return true
