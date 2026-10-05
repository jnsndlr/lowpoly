extends SceneTree
## Headless soak test for traffic afloat: runs a map at 4x for many game hours and
## reports any two hulls touching, any vessel aground, and any vessel held up for
## more than STALL game minutes (with what it is waiting for). For sailboats it also
## counts how often they come to a stop out on the water (and what they were
## doing), how long the last-resort hull check held them back, and their closest
## pass to another hull. Fishing boats' comings and goings are logged (FISH lines),
## and any time one touches water shallower than its draft (SHOAL).
##
##   godot --headless --path . --fixed-fps 30 --script tools/vessel_soak_test.gd -- --seed=123 --frames=20000

const STALL := 45.0

var main: Node
var frames := 0
var max_frames := 20000
var overlaps := {}
var aground := {}
var stall := {}
var reported := {}
var closest := INF
var stop_why := {}
var sail_stops := 0
var fish_stops := 0
var fish_closest := INF
var shoal := {}
var _was_stopped := {}
var _fish_state := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			max_frames = int(a.substr(9))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	frames += 1
	if frames == 5:
		Engine.time_scale = 4.0
	if frames < 5:
		return false
	var sim: Simulation = main.sim
	var vs: Array[Vessel] = sim.marine.vessels
	for i in vs.size():
		var a := vs[i]
		var pa := a.pos2()
		var ha := a.heading2() * a.half_seg
		for j in range(i + 1, vs.size()):
			var b := vs[j]
			var pb := b.pos2()
			if pa.distance_to(pb) > a.half_seg + b.half_seg + a.hull_radius + b.hull_radius + 2.0:
				continue
			var hb := b.heading2() * b.half_seg
			var gap := MarineTraffic._seg_dist(pa - ha, pa + ha, pb - hb, pb + hb) - a.hull_radius - b.hull_radius
			if a is Sailboat or b is Sailboat:
				closest = minf(closest, gap)
			if a is FishingBoat or b is FishingBoat:
				fish_closest = minf(fish_closest, gap)
			var key := a.vessel_name + " / " + b.vessel_name
			if gap < 0.0 and not overlaps.has(key):
				overlaps[key] = true
				print("OVERLAP %.2f m at %s: %s (%s) / %s (%s)" % [gap, sim.clock_text(), a.vessel_name, a.status_text(),
					b.vessel_name, b.status_text()])
		if not (a is Ferry):
			for e in [pa - ha, pa + ha, pa]:
				if sim.terrain.height_at(e.x, e.y) > -0.6 and not aground.has(a.vessel_name):
					aground[a.vessel_name] = true
					print("AGROUND %s at %s: %s" % [a.vessel_name, e, a.status_text()])
		if a is FishingBoat:
			var f := a as FishingBoat
			var st := "%s/%s" % [FishingBoat.State.keys()[f.state], FishingBoat.Work.keys()[f.work]] if f.fishing() \
					else str(FishingBoat.State.keys()[f.state])
			if _fish_state.get(f, "") != st:
				_fish_state[f] = st
				print("FISH %s %s %s · %s · hold %d%%" % [sim.clock_text(), f.vessel_name, st, f.status_text(), roundi(f.fish_hold * 100.0)])
			if f.free_nav:
				for e in [pa - ha * (f.spec.half_length / f.half_seg), pa]:
					if sim.terrain.height_at(e.x, e.y) > -f.spec.draft and not shoal.has(f.vessel_name):
						shoal[f.vessel_name] = true
						print("SHOAL %s at %s (%.2f m): %s" % [f.vessel_name, e, sim.terrain.height_at(e.x, e.y), f.status_text()])
				var stopped: bool = f.speed < 0.2
				var steaming: bool = f.state == FishingBoat.State.STEAMING or f.state == FishingBoat.State.HOMEWARD
				if stopped and steaming and not _was_stopped.get(f, true):
					fish_stops += 1
					var why: String = f.status_text()
					stop_why["(fishing) " + why] = stop_why.get("(fishing) " + why, 0) + 1
				_was_stopped[f] = stopped
		# A sailboat brought to a stop out on the water.
		if a is Sailboat and a.state == Sailboat.State.SAILING:
			var stopped: bool = a.speed < 0.2
			if stopped and not _was_stopped.get(a, false):
				sail_stops += 1
				var st: String = a.status_text().split(" ·")[0]
				stop_why[st] = stop_why.get(st, 0) + 1
			_was_stopped[a] = stopped
		# (A trawler hauling its net lies stopped on purpose.)
		var hauling: bool = a is FishingBoat and a.fishing() and a.work == FishingBoat.Work.HAULING
		if a.wants_to_move() and a.speed < 0.05 and not hauling:
			stall[a] = stall.get(a, 0.0) + delta
			if stall[a] > STALL and not reported.has(a):
				reported[a] = true
				var extra := ""
				if a is Sailboat and a.dest:
					var h: Vessel = sim.marine.lock_holder(a.dest)
					extra = " [lock: %s]" % ("none" if h == null else "%s %s at %s" % [h.vessel_name, h.status_text(), h.pos2()])
					if a.helm:
						var hm: Helm = a.helm
						extra += " [helm: heading %.2f, wants %.2f at %.1f m/s, aiming at %s, land ahead %s]" % [
							a.helm_yaw(), hm.want_yaw, hm.want_speed, hm.aim(), hm.blocked_land]
				print("STALL %s (%s) at %s: %s%s" % [a.vessel_name, a.kind_text(), pa, a.status_text(), extra])
		else:
			stall[a] = 0.0
			reported.erase(a)
	if frames < max_frames:
		return false
	var sail := 0
	for b in sim.marine.sailboats:
		sail += b.trips
	var ferry := 0
	for f in sim.ferries:
		ferry += f.trips
	var brake := 0.0
	for b in sim.marine.sailboats:
		brake += b.brake_time
	print("DONE day %d %s: sail trips %d, ferry trips %d, overlaps %d, aground %d" % [
		sim.day, sim.clock_text(), sail, ferry, overlaps.size(), aground.size()])
	print("     sailboats: stops under way %d, hull-check braking %.0f s, closest pass %.2f m" % [
		sail_stops, brake, closest])
	var fbrake := 0.0
	var ftrips := 0
	var fhauls := 0
	for f in sim.marine.fishing_boats:
		fbrake += f.brake_time
		ftrips += f.trips
		fhauls += f.hauls
	print("     fishing boats: %d, trips %d, hauls %d, stops steaming %d, hull-check braking %.0f s, closest pass %.2f m, shoal %d" % [
		sim.marine.fishing_boats.size(), ftrips, fhauls, fish_stops, fbrake, fish_closest, shoal.size()])
	for k in stop_why:
		print("       stopped while: %s (%d)" % [k, stop_why[k]])
	return true
