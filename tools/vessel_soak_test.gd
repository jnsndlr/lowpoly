extends SceneTree
## Headless soak test for traffic afloat: runs a map at 4x for many game hours and
## reports any two hulls touching, any vessel aground, and any vessel held up for
## more than STALL game minutes (with what it is waiting for). For sailboats it also
## counts how often they come to a stop out on the water (and what they were
## doing), how long the last-resort hull check held them back, and their closest
## pass to another hull. Fishing boats' comings and goings are logged (FISH lines),
## and any time one touches water shallower than its draft (SHOAL); so are motor
## yachts', pilot boats' and tugs' (YACHT, PILOT and TUG lines).
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
var _state := {}
var trace := ""
var _trace_t := 0.0
var anchorings := 0
var yacht_closest := INF
var yacht_brake := 0.0
var ferry_held_in := 0.0      # ferries ready to leave, holding in at the dock
var ferry_stopped := 0.0      # ferries stopped under way
var ferry_stop_why := {}
var tender_loiter := 0.0     # pilot boats / tugs under way while standing by or waiting


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			max_frames = int(a.substr(9))
		if a.begins_with("--trace="):
			trace = a.substr(8)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	frames += 1
	if frames == 5:
		Engine.time_scale = 4.0
	if frames < 5:
		return false
	var sim: Simulation = main.sim
	_watch_wildlife(sim)
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
			if (a is MotorYacht or b is MotorYacht) and not Vessel.paired(a, b):
				yacht_closest = minf(yacht_closest, gap)
			var key := a.vessel_name + " / " + b.vessel_name
			if gap < 0.0 and not overlaps.has(key):
				overlaps[key] = true
				print("OVERLAP %.2f m at %s: %s (%s) / %s (%s)" % [gap, sim.clock_text(), a.vessel_name, a.status_text(),
					b.vessel_name, b.status_text()])
				for t in [a, b]:
					if t is ShipTender and is_instance_valid(t.ship):
						var sh: CargoShip = t.ship
						var rel: Vector2 = t.pos2() - sh.pos2()
						var hh := sh.heading2()
						print("    DBG %s rel along %.1f lat %.1f yaw diff %.2f locked %s gap %.2f speed %.2f ship %.2f" % [
							t.vessel_name, rel.dot(hh), rel.dot(Vector2(-hh.y, hh.x)), angle_difference(t.helm_yaw(), atan2(hh.x, hh.y)),
							t._locked, t._gap, t.speed, sh.speed])
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
		_log_state(sim, a)
		if a.vessel_name == trace and frames % 8 == 0:
			print("TRACE %s %s pos %s yaw %.2f speed %.2f clear %.1f: %s" % [sim.clock_text(), a.vessel_name, pa,
				atan2(a.heading2().x, a.heading2().y), a.speed, a.clear, a.status_text()])
		# A sailboat brought to a stop out on the water.
		if a is Sailboat and a.state == Sailboat.State.SAILING:
			var stopped: bool = a.speed < 0.2
			if stopped and not _was_stopped.get(a, false):
				sail_stops += 1
				var st: String = a.status_text().split(" ·")[0]
				stop_why[st] = stop_why.get(st, 0) + 1
			_was_stopped[a] = stopped
		if a is ShipTender and a.state in [ShipTender.State.STANDING_BY, ShipTender.State.WAITING] and a.speed > 1.5:
			tender_loiter += delta
		# (A trawler hauling its net, say, lies stopped on purpose.)
		if a.wants_to_move() and a.speed < 0.05 and not a.resting():
			stall[a] = stall.get(a, 0.0) + delta
			# (Waiting its turn to go in to a berth can take a while.)
			var limit := STALL * (4.0 if a.status_text().begins_with("Waiting") else 1.0)
			if stall[a] > limit and not reported.has(a):
				reported[a] = true
				var extra := ""
				if a is Sailboat and a.dest:
					var h: Vessel = sim.marine.lock_holder(a.dest)
					extra = " [lock: %s]" % ("none" if h == null else "%s %s at %s" % [h.vessel_name, h.status_text(), h.pos2()])
				if a is HelmVessel and a.helm:
					var hm: Helm = a.helm
					extra += " [helm: heading %.2f, wants %.2f at %.1f m/s, aiming at %s, land ahead %s, goal %s, depth %.1f]" % [
						a.helm_yaw(), hm.want_yaw, hm.want_speed, hm.aim(), hm.blocked_land, hm.goal,
						sim.terrain.height_at(pa.x, pa.y)]
				print("STALL %s (%s) at %s: %s%s" % [a.vessel_name, a.kind_text(), pa, a.status_text(), extra])
				for o in vs:
					if o != a and o.pos2().distance_to(pa) < 45.0:
						print("    near: %s (%s) at %s %.1f m/s: %s" % [o.vessel_name, o.kind_text(), o.pos2(), o.speed, o.status_text()])
		else:
			stall[a] = 0.0
			reported.erase(a)
	for f in sim.ferries:
		if f.state == Ferry.State.SAILING and f.speed < 0.2:
			if f.traveled < 0.5:
				ferry_held_in += delta
			else:
				ferry_stopped += delta
				var why := f.status_text()
				if not why.begins_with("En route"):
					why = "%s: %s" % [f.ferry_name, why]
					if not ferry_stop_why.has(why):
						var o: Ferry = f._waiting_for
						print("FERRY WAIT %s %s at %.0f of %.0f m to %s: %s%s" % [sim.clock_text(), f.ferry_name, f.traveled, f.run_length(),
							f.destination().island.name, why, "" if o == null else " [%s at %.0f of %.0f m to %s]" % [
								o.ferry_name, o.traveled, o.run_length(), o.destination().island.name]])
					ferry_stop_why[why] = ferry_stop_why.get(why, 0.0) + delta
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
	var sizes := []
	for f in sim.ferries:
		sizes.append("%s %d (%d trips)" % [f.ferry_name, f.fc.size, f.trips])
	print("     ferries: " + ", ".join(PackedStringArray(sizes)))
	print("     ferry waits: held in at the dock %.0f s, stopped under way %.0f s %s" % [ferry_held_in, ferry_stopped, ferry_stop_why])
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
	var ytrips := 0
	for y in sim.marine.motor_yachts:
		ytrips += y.trips
		yacht_brake += y.brake_time
	print("     motor yachts: %d, trips %d, anchorings %d, hull-check braking %.0f s, closest pass %.2f m" % [
		sim.marine.motor_yachts.size(), ytrips, anchorings, yacht_brake, yacht_closest])
	_extra_summary(sim)
	print("     wildlife: visits %s, hauled out at once %d..%d (groups %d..%d), flushed by boats %d, bow rides %d" % [
		wild_visits, wild_hauled_min, wild_hauled, wild_groups_min, wild_groups_max, wild_flushed, wild_bow_rides])
	for k in stop_why:
		print("       stopped while: %s (%d)" % [k, stop_why[k]])
	return true


## For the pilotage: what the pilot boats and tugs got done.
func _extra_summary(sim: Simulation) -> void:
	var p: Pilotage = sim.marine.pilotage
	if p == null:
		return
	print("     pilotage: %d pilot boats, %d tugs, boarded %d, landed %d, escorts %d, missed %d" % [
		p.pilot_boats.size(), p.tugs.size(), p.boarded, p.landed, p.escorts, p.missed])
	print("     tenders under way standing by / waiting: %.0f s" % tender_loiter)


## Logs each motor yacht's, pilot boat's and tug's changes of state.
func _log_state(sim: Simulation, v: Vessel) -> void:
	var tag := ""
	var st := ""
	if v is MotorYacht:
		tag = "YACHT"
		st = MotorYacht.State.keys()[(v as MotorYacht).state]
		if (v as MotorYacht).state == MotorYacht.State.ANCHORED and _state.get(v, "") != st:
			anchorings += 1
	elif v is PilotBoat:
		tag = "PILOT"
		st = ShipTender.State.keys()[(v as PilotBoat).state]
	elif v is Tug:
		tag = "TUG"
		st = ShipTender.State.keys()[(v as Tug).state]
	else:
		return
	if _state.get(v, "") != st:
		_state[v] = st
		print("%s %s %s %s · %s" % [tag, sim.clock_text(), v.vessel_name, st, v.status_text()])


var wild_visits := {}        # species id -> visits
var wild_hauled := 0
var wild_hauled_min := 1000000
var wild_groups_min := 1000000
var wild_groups_max := 0
var wild_flushed := 0
var wild_bow_rides := 0
var _wild_seen := {}
var _wild_riding := {}
var _wild_hurry := {}

## Counts the wildlife visits, how many seals and sea lions lie up at once, how
## often a boat flushes them and how often porpoises ride a bow.
func _watch_wildlife(sim: Simulation) -> void:
	for v in sim.wildlife.visits:
		if not _wild_seen.has(v):
			_wild_seen[v] = true
			wild_visits[v.species.id] = int(wild_visits.get(v.species.id, 0)) + 1
		if v.escort and not _wild_riding.get(v, false):
			wild_bow_rides += 1
		_wild_riding[v] = v.escort != null
	var resting := 0
	var groups := 0
	for p in main.pinnipeds._pods:
		var out := false
		for o in p.animals:
			if o.state == Pinnipeds.State.REST:
				resting += 1
				out = true
			var h: bool = o.state == Pinnipeds.State.LEAVE and o.hurry
			if h and not _wild_hurry.get(o, false):
				wild_flushed += 1
			_wild_hurry[o] = h
		groups += 1 if out else 0
	wild_hauled = maxi(wild_hauled, resting)
	wild_hauled_min = mini(wild_hauled_min, resting)
	wild_groups_min = mini(wild_groups_min, groups)
	wild_groups_max = maxi(wild_groups_max, groups)
