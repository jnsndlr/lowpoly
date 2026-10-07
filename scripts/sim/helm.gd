class_name Helm
extends RefCounted
## Free navigation for a vessel with somewhere to be, steered the way a skipper
## would rather than along a fixed line. A rough route from the nav grid says
## which way round the islands to go; the helm heads for the furthest point of it
## it can see, and a few times a second weighs up the headings and speeds open to
## it against simple rules:
##   - get there: stay near the course the vessel wants (which for a sailboat may
##     be a tack upwind rather than straight at it),
##   - keep off the land,
##   - keep clear of other vessels and of wildlife, judged by where each will be
##     over the next HORIZON seconds and how close the two would pass,
##   - when the rules of the road make it the give-way vessel, act early and
##     clearly, preferring to turn to starboard and pass astern; when it is the
##     stand-on vessel, hold course and speed until it is nearly too late,
##   - don't dither: changing its mind costs a little.
## The vessel supplies what is particular to it (see the hooks below) and does
## its own turning and speeding up; MarineTraffic's hull check stays on as a last
## resort.
##
## Hooks on the vessel:
##   helm_yaw() -> float                  heading now (+Z is yaw 0, +X is yaw PI/2)
##   helm_courses(bearing) -> Array       [[yaw, extra cost], ...] it could steer to
##                                        make good `bearing`
##   helm_speed(yaw) -> float             best speed on that heading
##   helm_role(other) -> String           why it must keep clear of `other`
##                                        (a Vessel or a Wildlife.Visit), or "" if
##                                        it is the stand-on vessel
##   helm_turn_rate() -> float            how fast it swings round (rad/s)

const DECIDE_EVERY := 0.25
const HORIZON := 30.0
const STEP_T := 1.5
const SCAN := 140.0
const REPLAN_EVERY := 8.0
# Headings tried either side of each course, and the speeds tried when no
# heading at full speed keeps clear.
const OFFSETS := [0.0, 0.14, -0.14, 0.28, -0.28, 0.45, -0.45, 0.65, -0.65, 0.9, -0.9]
const SLOWER := [0.55, 0.2, 0.0]
const ESCAPES := 12
# Clear water kept: from small boats and from ships (more ahead of their bows).
# Wildlife sets its own (Wildlife.Visit.keep).
const KEEP_SMALL := 6.0
const KEEP_SHIP := 14.0
const KEEP_AHEAD_OF_SHIP := 16.0
const KEEP_MOORED := 4.0       # from boats lying at a berth or at anchor
const WILDLIFE_RADIUS := 15.0
# A stand-on vessel only acts once a pass is this close and this soon.
const STAND_ON_KEEP := 2.0
const STAND_ON_SOON := 8.0
# Water kept under the keel.
const UNDER_KEEL := 0.3

var v: Vessel
var traffic: MarineTraffic
var big := false
var goal := Vector2.INF
var route := PackedVector2Array()
var wp := 0
var want_yaw := 0.0
var want_speed := 0.0
var give_way_to: Variant = null    # what it is keeping clear of now, if anything
var give_way_why := ""
var blocked_land := false          # its course is closed by land just ahead

var _timer := 0.0
var _replan := 0.0
var _last := 0.0
var _slow := 0.0                   # how long it has been barely making way


func _init(vessel: Vessel, t: MarineTraffic, large := false) -> void:
	v = vessel
	traffic = t
	big = large
	_timer = t.rng.randf() * DECIDE_EVERY
	want_yaw = vessel.helm_yaw()
	_last = want_yaw


## Sets off for `p`. False if there is no way there.
func set_goal(p: Vector2, avoid: Array[Vector3] = []) -> bool:
	goal = p
	return _plan(avoid)


func distance_left() -> float:
	return v.pos2().distance_to(goal)


## Plans a new route to the goal round `avoid` (see NavGrid.find_path).
func replan(avoid: Array[Vector3] = []) -> bool:
	return _plan(avoid)


func _plan(avoid: Array[Vector3] = []) -> bool:
	_replan = REPLAN_EVERY
	var pts := traffic.nav.find_path(v.pos2(), goal, big, avoid)
	if pts.size() < 2:
		route = PackedVector2Array([v.pos2(), goal])
		wp = 1
		return false
	route = pts
	wp = 1
	return true


## Call every frame; re-decides every DECIDE_EVERY seconds.
func update(delta: float) -> void:
	_slow = _slow + delta if v.speed < 0.3 else 0.0
	_replan -= delta
	if _replan <= 0.0:
		_plan()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer += DECIDE_EVERY
	_advance()
	_decide()


## The furthest point of the route in plain sight is where it heads.
func _advance() -> void:
	var p := v.pos2()
	var nav := traffic.nav
	while wp < route.size() - 1 and (p.distance_to(route[wp]) < 12.0 or nav.clear_line(p, route[wp + 1], big)):
		wp += 1
	if wp < route.size() - 1 and not nav.clear_line(p, route[wp], big) and _replan < REPLAN_EVERY - 2.0:
		_plan()


func aim() -> Vector2:
	return route[mini(wp, route.size() - 1)] if not route.is_empty() else goal


# --- Deciding ----------------------------------------------------------------

class Threat:
	var what: Variant
	var why := ""            # the rule that makes us keep clear, "" if stand-on
	var keep := 0.0
	var ahead_keep := 0.0    # extra kept clear ahead of its bow
	var moored := false      # lying at a berth or at anchor: kept clear of though it is the stand-on vessel
	var radius := 0.0
	var a := PackedVector2Array()   # its hull (or centre) at each sample time
	var b := PackedVector2Array()
	var fwd := PackedVector2Array()


func _decide() -> void:
	var p := v.pos2()
	var yaw := v.helm_yaw()
	var to := aim() - p
	var bearing := atan2(to.x, to.y) if to.length_squared() > 1e-4 else yaw
	var courses: Array = v.helm_courses(bearing)
	var threats := _threats(p)
	var my_r := v.hull_radius + v.half_seg * 0.5
	var best_cost := INF
	var best_yaw := yaw
	var best_speed := 0.0
	var best_threat: Threat = null
	var base_yaw: float = courses[0][0]
	blocked_land = _land_cost(p, base_yaw, v.helm_speed(base_yaw)) > 1.0
	# Headings to weigh up: either side of each course it could steer, and (at a
	# price) every way round, so it can always turn away from trouble.
	var cands: Array = []
	for c in courses:
		for o: float in OFFSETS:
			cands.append([c[0] + o, c[1] + absf(o) * 1.2, o])
	for k in ESCAPES:
		var h := base_yaw + k * TAU / ESCAPES
		var o := angle_difference(base_yaw, h)
		if absf(o) > 1.0:
			cands.append([h, 2.0 + absf(o) * 0.5, o])
	# Hard up against another hull, it can only go where the hull check lets it
	# (MarineTraffic: no nearer than it is); and if that one is waiting for it to
	# get out of the way, sitting still settles nothing.
	var now_gap := traffic.hull_gap(v, p, v.heading2())
	var pinned := now_gap < 2.0
	var deadlock := v.blocked_by_hull and is_instance_valid(v.blocker) and v.blocker.waits_for(v)
	for round in 2:
		var factors := [1.0] if round == 0 else SLOWER
		for c: Array in cands:
			var h: float = c[0]
			var o: float = c[2]
			var top := v.helm_speed(h)
			var land := _land_cost(p, h, top)
			if pinned:
				var d := Vector2(sin(h), cos(h))
				if traffic.hull_gap(v, p + d, d) < minf(0.3, now_gap) - 0.001:
					land += 20.0
			for f: float in factors:
				var sp := top * f
				var cost: float = c[1] + (1.0 - f) * 1.5 + land
				cost += absf(angle_difference(h, _last)) * 0.5
				# Barely making way (in irons, say) is no way to get anywhere, and
				# the longer it goes on the more it is worth a big turn to get going.
				if sp < 0.4:
					cost += 1.5 + minf(_slow * 0.15, 4.0) + (6.0 if deadlock else 0.0)
				var worst := 0.0
				var worst_t: Threat = null
				for t: Threat in threats:
					var pen := _pass_cost(p, yaw, h, sp, my_r, t)
					if t.why != "" and o > 0.0 and pen > 0.0:
						# Give-way turns go to starboard.
						pen += 0.6
					if pen > worst:
						worst = pen
						worst_t = t
					cost += pen
				if cost < best_cost:
					best_cost = cost
					best_yaw = h
					best_speed = sp
					best_threat = worst_t if worst > 0.0 else null
		# Slowing down is only worth trying if every full-speed heading leaves
		# someone too close.
		if best_threat == null:
			break
	want_yaw = best_yaw
	want_speed = best_speed
	_last = best_yaw
	# Who it is keeping clear of: whatever would be too close on the course it
	# wanted, if it has turned or slowed for it.
	give_way_to = null
	give_way_why = ""
	var changed := absf(angle_difference(best_yaw, base_yaw)) > 0.1 or best_speed < v.helm_speed(base_yaw) * 0.8
	if changed:
		var worst := 0.0
		for t: Threat in threats:
			if t.why == "":
				continue
			var pen := _pass_cost(p, yaw, base_yaw, v.helm_speed(base_yaw), my_r, t)
			if pen > worst:
				worst = pen
				give_way_to = t.what
				give_way_why = t.why
	elif best_threat != null and best_threat.why != "":
		give_way_to = best_threat.what
		give_way_why = best_threat.why


## Everything near enough to matter, with where it will be at each sample time.
func _threats(p: Vector2) -> Array[Threat]:
	var out: Array[Threat] = []
	for o in traffic.vessels:
		if o == v or not is_instance_valid(o):
			continue
		# (Working alongside a ship, it is no threat to it, nor it to the ship.)
		if Vessel.paired(v, o) and (v.road() == Vessel.Road.RESTRICTED or o.road() == Vessel.Road.RESTRICTED):
			continue
		var reach := SCAN + o.half_seg + o.hull_radius
		var q := o.pos2()
		if absf(q.x - p.x) > reach or absf(q.y - p.y) > reach:
			continue
		var t := Threat.new()
		t.what = o
		t.why = v.helm_role(o)
		var ship := o.half_seg > 6.0
		t.keep = KEEP_SHIP if ship else KEEP_SMALL
		t.ahead_keep = KEEP_AHEAD_OF_SHIP if ship and o.speed > 0.3 else 0.0
		t.radius = o.hull_radius
		if o.road() == Vessel.Road.MOORED:
			t.moored = true
			t.keep = KEEP_MOORED
		# One that wants to get going is reckoned to be about to, even if it is
		# stopped (waiting for this one to get out of its way, perhaps).
		var moving := o.wants_to_move()
		var osp := maxf(o.speed, o.cruise * 0.4)
		for k in range(0, int(HORIZON / STEP_T) + 1):
			var d := osp * k * STEP_T if moving else 0.0
			var c := o.ahead(d) if moving else q
			var f := o.heading2()
			if moving and not o.crabbing():
				var g := o.ahead(d + 1.0) - o.ahead(maxf(d - 1.0, 0.0))
				if g.length_squared() > 1e-6:
					f = g.normalized() * signf(g.normalized().dot(f) + 1e-3)
			t.a.append(c - f * o.half_seg)
			t.b.append(c + f * o.half_seg)
			t.fwd.append(f)
		out.append(t)
	if traffic.sim.wildlife:
		for w: Wildlife.Visit in traffic.sim.wildlife.active_visits():
			var keep := w.keep()
			var q := Vector2(w.pos.x, w.pos.z)
			if keep <= 0.0 or q.distance_to(p) > SCAN + keep:
				continue
			var t := Threat.new()
			t.what = w
			t.why = v.helm_role(w)
			t.keep = keep
			t.radius = WILDLIFE_RADIUS
			var f := Vector2(sin(w.heading), cos(w.heading))
			for k in range(0, int(HORIZON / STEP_T) + 1):
				var c := q + f * w.speed * k * STEP_T
				t.a.append(c)
				t.b.append(c)
				t.fwd.append(f)
			out.append(t)
	return out


## Penalty for passing `t` on heading `h` at `sp` (0 if it keeps well clear).
## Turning takes time, so it reckons on holding its present heading for the first
## part of the turn.
func _pass_cost(p: Vector2, yaw: float, h: float, sp: float, my_r: float, t: Threat) -> float:
	var turn_t := absf(angle_difference(yaw, h)) / v.helm_turn_rate()
	var d0 := Vector2(sin(yaw), cos(yaw))
	var d1 := Vector2(sin(h), cos(h))
	var stand_on := t.why == ""
	var worst := 0.0
	var total := 0.0
	# (Now is the same whichever way it turns, so it doesn't count towards the
	# worst; the average still rewards getting further away when already close.)
	for k in t.a.size():
		var time := k * STEP_T
		if stand_on and time > STAND_ON_SOON and not t.moored:
			break
		var early := minf(time, turn_t * 0.5)
		var me := p + d0 * sp * early + d1 * sp * (time - early)
		var cp := Geometry2D.get_closest_point_to_segment(me, t.a[k], t.b[k])
		var gap := me.distance_to(cp) - t.radius - my_r
		var keep := STAND_ON_KEEP if stand_on and not t.moored else t.keep
		# Crossing ahead of a ship under way needs a lot more room than astern.
		if not stand_on and t.ahead_keep > 0.0 and (me - t.b[k]).dot(t.fwd[k]) > -2.0:
			keep += t.ahead_keep
		if gap < keep:
			var urgency := 1.6 - time / HORIZON
			var pen := (keep - gap) / keep * urgency * 6.0
			total += pen
			if k > 0:
				worst = maxf(worst, pen)
	return worst + total / t.a.size()


## How much land (or the edge of the map) closes the way ahead on heading `h`.
func _land_cost(p: Vector2, h: float, sp: float) -> float:
	var d := Vector2(sin(h), cos(h))
	var look := 10.0 + maxf(sp, 1.0) * 7.0
	var nav := traffic.nav
	var here := nav.cell(p)
	# (Its routes may run a little way off the edge of the map, round an island.)
	var bound := traffic.nav.ext - NavGrid.CELL * 2.0
	# Measured from just behind the bow, however long the hull.
	var lead := maxf(v.spec.half_length - 2.0, 0.0)
	var shoal := -v.spec.draft - UNDER_KEEL
	var s := 2.0
	while s <= look:
		var q := p + d * (s + lead)
		var blocked := absf(q.x) > bound or absf(q.y) > bound
		if not blocked and nav.cell(q) != here:
			blocked = not nav.open_at(q, big)
		# Rocks and shoals too small for the grid to see.
		if not blocked:
			blocked = nav.terrain.height_at(q.x, q.y) > shoal
		if blocked:
			# Right ahead, it's out of the question.
			return 4.0 * (1.0 - s / (look + 3.0)) + 0.5 + (30.0 if s <= 6.0 else 0.0)
		s += 2.0
	return 0.0
