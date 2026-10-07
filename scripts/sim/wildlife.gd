class_name Wildlife
extends Node3D
## Marine wildlife visits and the tourism draw they leave behind.
##
## Each species rolls for visits once a game day. A visiting group arrives from
## offshore, spends its time around one island (weighted by the island's
## wildlife_appeal and `island_attraction`), then leaves. How it spends that time
## is the species' Behavior: orcas circle the island; whales and porpoises forage
## over a patch of water off it (gray whales close inshore, Dall's porpoises
## breaking off to ride a passing boat's bow); seals and sea lions come to one of
## the map's haul-outs (MapData.HaulOut) and lie up there for hours. Moving the
## group along is done here; drawing the animals is up to the renderers
## (Cetaceans, Pinnipeds), which also take them in and out of the water.
##
## A visit only becomes a *sighting* for an island if people see it in daylight:
## the group passes within DOCK_RADIUS of that island's ferry dock, or within
## FERRY_RADIUS of a sailing ferry, which credits both ends of its route. Each
## credited island's reputation jumps by the species' draw, then eases back down
## toward a floor it keeps for the rest of the season. Clicking an animal during a
## visit (once per visit) adds PHOTO_BONUS on top for every island it's credited to.

signal visit_started(v: Visit)
signal sighted(v: Visit, isl: MapData.Island, seen_from: String)
signal photographed(v: Visit)
signal visit_ended(v: Visit)

enum Behavior { CIRCLE_ISLAND, HAUL_OUT, FORAGE, MIGRATE }
enum Phase { ARRIVE, CIRCLE, FORAGE, HAULED, DEPART, GONE }
enum Role { BULL, COW, JUVENILE, CALF, ADULT, PUP }

# A sighting counts within this of an island's ferry dock, or of a sailing ferry.
const DOCK_RADIUS := 150.0
const FERRY_RADIUS := 110.0
# Reputation: a sighting adds the species' draw (less as an island nears REP_CAP),
# which halves every REP_HALF_LIFE_DAYS down to a floor of SEASON_FLOOR times the
# best the island reached this season. The floor clears when the season turns.
const REP_CAP := 8.0
const REP_HALF_LIFE_DAYS := 6.0
const SEASON_FLOOR := 0.4
# Share of the draw a photo adds to each island a visit is credited to.
const PHOTO_BONUS := 0.5
const HISTORY := 12
# Water deeper than this is open to a group (the sea floor is Terrain.SEA_FLOOR).
const DEEP := -2.6
# Radians per game minute a group can swing its heading.
const TURN_RATE := 0.35
# A bow-riding group joins boats under way at least this fast within this range,
# rides for a few minutes, then won't again for a while.
const BOW_SPEED := 5.0
const BOW_RANGE := 90.0
const BOW_RIDE := Vector2(3.0, 7.0)
const BOW_REST := Vector2(10.0, 25.0)
# Game minutes before a resident seal or sea lion group leaves that the next sets off.
const RESIDENT_HANDOVER := 180.0


## What a species is like and how it behaves. Only `enabled` species visit.
class Species:
	var id := ""
	var name := ""
	var plural := ""
	var draw := 1.0                     # reputation per sighting
	var group := Vector2i(1, 1)         # group size range
	var hours := 3.0                    # length of a visit, game hours
	var daily_chance := 1.0             # visits per day (fractions roll)
	var window := Vector2(6.5, 18.0)    # hours of the day a visit can start in
	var behavior := Behavior.CIRCLE_ISLAND
	var speed := 4.5                    # cruising, m per game minute
	var enabled := false
	var keep := 0.0                     # how far boats keep off (0: they don't steer round it)
	var depth := DEEP                   # shallowest water it swims in
	var patch := Vector2(80.0, 200.0)   # FORAGE: how far off the island it feeds
	var roam := 60.0                    # FORAGE: how far it wanders about there
	var bow_rides := false
	var haul := Vector3(1.0, 1.0, 0.0)  # HAUL_OUT: liking for beach, rock, dock
	var resident := 0                   # HAUL_OUT: groups always lying up somewhere on the map

	func _init(i: String, n: String, p: String, d: float, g: Vector2i, h: float, c: float,
			b: Behavior, s: float, on := false) -> void:
		id = i
		name = n
		plural = p
		draw = d
		group = g
		hours = h
		daily_chance = c
		behavior = b
		speed = s
		enabled = on

	func with(fields: Dictionary) -> Species:
		for k: String in fields:
			set(k, fields[k])
		return self


class Member:
	var role := Role.ADULT
	var length := 5.0                   # metres
	var mother := -1                    # index of a calf's mother in the group


class Visit:
	var species: Species
	var members: Array[Member] = []
	var target: MapData.Island
	var day := 0
	var start := 0.0                    # minute of the day it began
	var age := 0.0                      # game minutes so far
	var length := 180.0
	var phase := Phase.ARRIVE
	var pos := Vector3.ZERO             # centre of the group, at the surface
	var heading := 0.0                  # yaw (+Z forward)
	var speed := 0.0
	var base_r := 60.0                  # circling radius around the target
	var orbit_r := 60.0
	var orbit_dir := 1.0
	var seed := 0.0
	var exit := Vector3.ZERO
	var site: MapData.HaulOut           # HAUL_OUT: where it lies up
	var patch := Vector3.ZERO           # FORAGE: centre of where it feeds
	var wander := Vector3.ZERO          # FORAGE: where it's heading in the patch
	var wander_t := 0.0
	var escort: Vessel                  # the boat whose bow it's riding
	var escort_t := 0.0                 # riding: time left; otherwise until it may again
	var seen := {}                      # island id -> who saw them ("Cedar Star", "the dock")
	var credited: Array[MapData.Island] = []
	var photographed := false
	var marker: Node3D                  # rides along with the group, for the camera

	func active() -> bool:
		return phase != Phase.GONE

	func title() -> String:
		var n := members.size()
		return "%s ×%d" % [species.plural, n] if n > 1 else species.name

	## How far boats keep off the group (0: they don't steer round it). Not while
	## it's lying up ashore, nor while it's riding someone's bow.
	func keep() -> float:
		if phase == Phase.HAULED or escort != null:
			return 0.0
		return species.keep


class Reputation:
	var value := 0.0
	var floor := 0.0
	var best := 0.0                     # highest value this season
	var sightings := 0                  # this season
	var last_day := -1
	var last_species := ""


var sim: Simulation
var rng := RandomNumberGenerator.new()
var species: Array[Species] = []
## Visits, oldest first; the last HISTORY are kept.
var visits: Array[Visit] = []
## Research / policy hooks: more visits overall, and per-island pull (island id -> x).
var attraction := 1.0
var island_attraction := {}
var _rep := {}                          # island id -> Reputation
var _planned: Array = []                # [Species, minute of day]
var _planned_day := -1
var _season := -1


func setup(s: Simulation) -> void:
	sim = s
	rng.seed = sim.map.map_seed * 53 + 11
	species = table()
	_season = sim.season()
	for isl in sim.map.islands:
		_rep[isl.id] = Reputation.new()
	_keep_residents(true)


## Tourism draw, best first. Seals, sea lions and porpoises come in big groups, so
## each sighting is worth little; seals and sea lions are about all the time, so
## hardly anything. They come in at any hour to lie up for most of a day (and the
## night), and there are always a few groups of them hauled out somewhere.
static func table() -> Array[Species]:
	var out: Array[Species] = [
		Species.new("orca", "Orca", "Orcas", 3.0, Vector2i(2, 8), 3.0, 1.0, Behavior.CIRCLE_ISLAND, 4.5, true).with(
			{"keep": 45.0}),
		Species.new("humpback", "Humpback whale", "Humpback whales", 2.4, Vector2i(1, 3), 4.0, 0.5, Behavior.FORAGE, 3.0, true).with(
			{"keep": 50.0, "patch": Vector2(90.0, 220.0), "roam": 80.0}),
		Species.new("gray", "Gray whale", "Gray whales", 1.8, Vector2i(1, 2), 5.0, 0.4, Behavior.FORAGE, 2.5, true).with(
			{"keep": 40.0, "depth": -2.0, "patch": Vector2(22.0, 50.0), "roam": 45.0}),
		Species.new("sea_lion", "Sea lion", "Sea lions", 0.08, Vector2i(3, 12), 10.0, 0.7, Behavior.HAUL_OUT, 3.5, true).with(
			{"window": Vector2(0.0, 24.0), "haul": Vector3(0.3, 1.0, 1.6), "resident": 2}),
		Species.new("dalls_porpoise", "Dall's porpoise", "Dall's porpoises", 0.15, Vector2i(3, 9), 1.5, 0.8, Behavior.FORAGE, 7.0, true).with(
			{"patch": Vector2(120.0, 260.0), "roam": 90.0, "bow_rides": true}),
		Species.new("harbor_porpoise", "Harbor porpoise", "Harbor porpoises", 0.15, Vector2i(2, 6), 2.0, 0.9, Behavior.FORAGE, 4.0, true).with(
			{"patch": Vector2(40.0, 120.0), "roam": 50.0}),
		Species.new("harbor_seal", "Harbor seal", "Harbor seals", 0.03, Vector2i(5, 18), 10.0, 0.9, Behavior.HAUL_OUT, 2.5, true).with(
			{"window": Vector2(0.0, 24.0), "haul": Vector3(1.0, 1.4, 0.08), "resident": 3}),
	]
	return out


func find_species(id: String) -> Species:
	for sp in species:
		if sp.id == id:
			return sp
	return null


func reputation(isl: MapData.Island) -> float:
	return (_rep[isl.id] as Reputation).value if _rep.has(isl.id) else 0.0


func standing(isl: MapData.Island) -> Reputation:
	return _rep.get(isl.id)


## How strongly an island pulls visits toward it.
func appeal(isl: MapData.Island) -> float:
	return isl.wildlife_appeal * float(island_attraction.get(isl.id, 1.0))


func active_visits() -> Array[Visit]:
	var out: Array[Visit] = []
	for v in visits:
		if v.active():
			out.append(v)
	return out


## Someone got a photo of this group: a bonus on top of every island it's credited
## to, now and later in the visit. Once per visit.
func photograph(v: Visit) -> bool:
	if v.photographed or not v.active():
		return false
	v.photographed = true
	for isl in v.credited:
		_spike(isl, v.species.draw * PHOTO_BONUS)
	photographed.emit(v)
	return true


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if sim.season() != _season:
		_season = sim.season()
		for r: Reputation in _rep.values():
			r.floor = 0.0
			r.best = r.value
			r.sightings = 0
	var k := pow(0.5, delta / (REP_HALF_LIFE_DAYS * 1440.0))
	for r: Reputation in _rep.values():
		r.value = r.floor + (r.value - r.floor) * k
	if sim.day != _planned_day:
		_plan_day()
	for i in range(_planned.size() - 1, -1, -1):
		if sim.minutes >= _planned[i][1]:
			start_visit(_planned[i][0])
			_planned.remove_at(i)
	_keep_residents(false)
	for v in visits:
		if v.active():
			_tick(v, delta)
			_look(v)


## Tops up each haul-out species to its `resident` groups: a few hours before
## one is due to leave, another sets off to take over (swimming in from offshore
## takes a while). At the start of the game they're already lying up
## (`settled`), part way through their visits.
func _keep_residents(settled: bool) -> void:
	for sp in species:
		if not sp.enabled or sp.resident <= 0:
			continue
		var n := 0
		for v in visits:
			if v.species == sp and v.active() and v.length - v.age > RESIDENT_HANDOVER:
				n += 1
		for i in sp.resident - n:
			var v := start_visit(sp, null, settled)
			if v == null or v.site == null:
				if v:
					_end(v)
				break


func _plan_day() -> void:
	_planned_day = sim.day
	_planned.clear()
	for sp in species:
		if not sp.enabled:
			continue
		var chance := sp.daily_chance * attraction
		var n := floori(chance) + (1 if rng.randf() < chance - floorf(chance) else 0)
		for i in n:
			_planned.append([sp, rng.randf_range(sp.window.x, sp.window.y) * 60.0])


## Starts a visit now, around `target` or an island picked by appeal (seals and
## sea lions: at a free haul-out, picked by its liking and the appeal of the
## island it's off; `settled`: already there, some way into the visit).
func start_visit(sp: Species, target: MapData.Island = null, settled := false) -> Visit:
	var site: MapData.HaulOut = null
	if sp.behavior == Behavior.HAUL_OUT:
		site = _pick_site(sp, target)
		if site:
			target = sim.map.islands[site.near]
	if target == null:
		target = _pick_target()
	if target == null:
		return null
	var v := Visit.new()
	v.species = sp
	v.target = target
	v.site = site
	v.day = sim.day
	v.start = sim.minutes
	v.length = sp.hours * 60.0 * rng.randf_range(0.75, 1.3)
	v.seed = rng.randf() * 100.0
	v.members = _members(sp)
	v.base_r = target.radius * 1.25 + 18.0
	v.orbit_r = v.base_r
	v.orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	var out := target.center.angle()
	if site:
		out = atan2(site.out.z, site.out.x)
	elif sp.behavior == Behavior.FORAGE:
		v.patch = _patch(sp, target)
		v.wander = v.patch
		out = Vector2(v.patch.x - target.center.x, v.patch.z - target.center.y).angle()
	v.pos = _offshore(target, out + rng.randf_range(-0.8, 0.8))
	v.exit = _offshore(target, out + rng.randf_range(0.9, 2.2) * (1.0 if rng.randf() < 0.5 else -1.0))
	var aim := Vector3(target.center.x, 0.0, target.center.y)
	if site:
		aim = site.water
	elif sp.behavior == Behavior.FORAGE:
		aim = v.patch
	v.heading = atan2(aim.x - v.pos.x, aim.z - v.pos.z)
	v.speed = sp.speed
	if settled and site:
		v.phase = Phase.HAULED
		v.pos = site.water
		v.age = rng.randf_range(0.0, 0.7) * v.length
	v.escort_t = rng.randf_range(0.0, BOW_REST.x)
	v.marker = Node3D.new()
	v.marker.name = "%s visit" % sp.name
	v.marker.position = v.pos
	add_child(v.marker)
	visits.append(v)
	while visits.size() > HISTORY and not visits[0].active():
		visits.remove_at(0)
	visit_started.emit(v)
	return v


## A free haul-out for `sp`, weighted by how much it likes that kind of place
## and by the appeal of the island it's off (only off `near`, if given).
func _pick_site(sp: Species, near: MapData.Island) -> MapData.HaulOut:
	var taken := {}
	for v in visits:
		if v.active() and v.site:
			taken[v.site.id] = true
	var picks: Array[MapData.HaulOut] = []
	var weights: Array[float] = []
	var total := 0.0
	for h in sim.map.haul_outs:
		if taken.has(h.id) or (near and h.near != near.id):
			continue
		var w: float = [sp.haul.x, sp.haul.y, sp.haul.z][h.kind] * appeal(sim.map.islands[h.near])
		if w <= 0.0:
			continue
		picks.append(h)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in picks.size():
		r -= weights[i]
		if r <= 0.0:
			return picks[i]
	return picks.back() if not picks.is_empty() else null


## Where a foraging group feeds: open water of its liking off `isl`.
func _patch(sp: Species, isl: MapData.Island) -> Vector3:
	var c := Vector3(isl.center.x, 0.0, isl.center.y)
	var bound := sim.map.half_size - 40.0
	for attempt in 40:
		var a := rng.randf() * TAU
		var d := isl.radius + rng.randf_range(sp.patch.x, sp.patch.y) * (1.0 + attempt * 0.02)
		var p := c + Vector3(cos(a), 0.0, sin(a)) * d
		if absf(p.x) < bound and absf(p.z) < bound and _open(p, 14.0, sp.depth):
			return p
	return _offshore(isl, rng.randf() * TAU)


func _pick_target() -> MapData.Island:
	var picks: Array[MapData.Island] = []
	var total := 0.0
	for isl in sim.map.islands:
		if isl.inhabited and not isl.is_mainland:
			picks.append(isl)
			total += appeal(isl)
	var r := rng.randf() * total
	for isl in picks:
		r -= appeal(isl)
		if r <= 0.0:
			return isl
	return picks.back() if not picks.is_empty() else null


func _members(sp: Species) -> Array[Member]:
	var n := rng.randi_range(sp.group.x, sp.group.y)
	var out: Array[Member] = []
	match sp.id:
		"orca":
			return _pod(n)
		"humpback", "gray":
			# Mostly lone animals or loose pairs; now and then a cow with her calf.
			var adult := Vector2(11.0, 14.0) if sp.id == "humpback" else Vector2(10.0, 13.0)
			for i in n:
				var m := Member.new()
				m.length = rng.randf_range(adult.x, adult.y)
				if i == 1 and rng.randf() < 0.4:
					m.role = Role.CALF
					m.length = rng.randf_range(5.0, 6.5)
					m.mother = 0
				out.append(m)
			return out
		"sea_lion":
			# Mostly males, as on the docks here; some big old bulls among them.
			for i in n:
				var m := Member.new()
				if rng.randf() < 0.3:
					m.role = Role.BULL
					m.length = rng.randf_range(2.3, 2.5)
				elif rng.randf() < 0.75:
					m.role = Role.ADULT
					m.length = rng.randf_range(1.95, 2.25)
				else:
					m.role = Role.COW
					m.length = rng.randf_range(1.7, 1.9)
				out.append(m)
			return out
		"harbor_seal":
			# Pups beside their mothers in spring and summer.
			var pupping := sim.season() % 4 <= 1
			for i in n:
				var m := Member.new()
				m.length = rng.randf_range(1.45, 1.8)
				if pupping and i > 0 and rng.randf() < 0.25 and out[i - 1].role == Role.ADULT:
					m.role = Role.PUP
					m.length = rng.randf_range(0.85, 1.0)
					m.mother = i - 1
				out.append(m)
			return out
		"dalls_porpoise":
			for i in n:
				var m := Member.new()
				m.length = rng.randf_range(1.8, 2.2)
				out.append(m)
			return out
		"harbor_porpoise":
			for i in n:
				var m := Member.new()
				m.length = rng.randf_range(1.4, 1.75)
				out.append(m)
			return out
	for i in n:
		var m := Member.new()
		m.length = rng.randf_range(0.85, 1.1)
		out.append(m)
	return out


## An orca pod: at most one big bull, mostly cows and their young, calves only beside a cow.
func _pod(n: int) -> Array[Member]:
	var out: Array[Member] = []
	var cows: Array[int] = []
	for i in n:
		var m := Member.new()
		if i == 0 and n >= 3 and rng.randf() < 0.65:
			m.role = Role.BULL
			m.length = rng.randf_range(7.4, 8.6)
		elif i == 0 or i == 1 or (cows.size() < 3 and rng.randf() < 0.4):
			m.role = Role.COW
			m.length = rng.randf_range(5.6, 6.6)
			cows.append(i)
		elif rng.randf() < 0.5 and cows.size() > 0:
			m.role = Role.CALF
			m.length = rng.randf_range(2.4, 3.3)
			m.mother = cows[rng.randi() % cows.size()]
		else:
			m.role = Role.JUVENILE
			m.length = rng.randf_range(3.8, 5.2)
		out.append(m)
	return out


## A deep-water spot a few hundred metres off `isl`, roughly in direction `ang`.
func _offshore(isl: MapData.Island, ang: float) -> Vector3:
	var bound := sim.map.half_size - 30.0
	var c := Vector3(isl.center.x, 0.0, isl.center.y)
	for attempt in 30:
		var a := ang + rng.randf_range(-0.5, 0.5) * (1.0 + attempt * 0.1)
		var p := c + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(isl.radius + 120.0, isl.radius + 300.0)
		if absf(p.x) < bound and absf(p.z) < bound and _open(p, 18.0):
			return p
	return c + Vector3(cos(ang), 0.0, sin(ang)) * (isl.radius + 110.0)


func _open(p: Vector3, r: float, depth := DEEP) -> bool:
	if sim.terrain.height_at(p.x, p.z) > depth:
		return false
	for i in 6:
		var a := TAU * i / 6.0
		if sim.terrain.height_at(p.x + cos(a) * r, p.z + sin(a) * r) > depth:
			return false
	return true


func _tick(v: Visit, dt: float) -> void:
	v.age += dt
	var c := Vector3(v.target.center.x, 0.0, v.target.center.y)
	var dist := Vector2(v.pos.x - c.x, v.pos.z - c.z).length()
	var aim := v.exit
	var cruise := v.species.speed
	var free := false               # heading straight for `aim`, no looking out for the shallows
	match v.phase:
		Phase.ARRIVE:
			if v.site:
				aim = v.site.water
				var d := v.pos.distance_to(aim)
				free = d < 45.0
				cruise *= clampf(d / 30.0, 0.25, 1.0)
				if d < 4.0:
					v.phase = Phase.HAULED
			elif v.species.behavior == Behavior.FORAGE:
				aim = v.patch
				if v.pos.distance_to(aim) < 30.0:
					v.phase = Phase.FORAGE
			else:
				aim = _orbit_aim(v, dt) if dist < v.orbit_r * 2.0 else c
				if dist < v.orbit_r + 25.0:
					v.phase = Phase.CIRCLE
		Phase.CIRCLE:
			aim = _orbit_aim(v, dt)
			cruise *= 0.8
			if v.age > v.length * 0.78:
				v.phase = Phase.DEPART
		Phase.FORAGE:
			aim = _forage_aim(v, dt)
			cruise *= 0.6
			if v.age > v.length * 0.85:
				_drop_escort(v)
				v.phase = Phase.DEPART
		Phase.HAULED:
			# Waiting about off the haul-out while they lie up (the renderer takes
			# them in and out of the water); time to go once it's nearly up.
			aim = v.site.water
			free = true
			cruise = 0.0
			if v.age > v.length - 20.0:
				v.phase = Phase.DEPART
	if v.escort:
		var boat_speed := v.escort.speed if is_instance_valid(v.escort) else cruise
		aim = _escort_aim(v, dt)
		cruise = boat_speed + 1.0 if v.escort else cruise
		free = false
	elif v.phase == Phase.DEPART and v.site and v.pos.distance_to(v.site.water) < 40.0:
		free = true
		cruise *= 0.5
	# Cruising speed drifts a little.
	var drift := 1.0 if v.escort else 0.85 + 0.3 * sin(v.age * 0.07 + v.seed)
	v.speed = move_toward(v.speed, cruise * drift, dt * (3.0 if v.escort else 0.5))
	var want := atan2(aim.x - v.pos.x, aim.z - v.pos.z)
	if not free:
		want = _clear_heading(v.pos, want, v.species.depth)
	v.heading = rotate_toward(v.heading, want, TURN_RATE * dt * (4.0 if v.escort else 1.0))
	var step := minf(v.speed * dt, v.pos.distance_to(aim)) if free else v.speed * dt
	if not free and step > 0.0:
		step = _hold_off(v, step)
	v.pos += Vector3(sin(v.heading), 0.0, cos(v.heading)) * step
	v.marker.position = v.pos
	if v.age >= v.length:
		_end(v)


## Ambling about the feeding patch: a new spot in it whenever it gets to the last,
## or after a while anyway. A bow-riding species looks out for boats going by.
func _forage_aim(v: Visit, dt: float) -> Vector3:
	v.wander_t -= dt
	if v.wander_t <= 0.0 or v.pos.distance_to(v.wander) < 12.0:
		v.wander_t = rng.randf_range(4.0, 12.0)
		for attempt in 12:
			var a := rng.randf() * TAU
			var p := v.patch + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, v.species.roam)
			if _open(p, 6.0, v.species.depth):
				v.wander = p
				break
	if v.species.bow_rides:
		v.escort_t -= dt
		if v.escort_t <= 0.0:
			v.escort_t = 2.0
			var boat := _bow_to_ride(v)
			if boat:
				v.escort = boat
				v.escort_t = rng.randf_range(BOW_RIDE.x, BOW_RIDE.y)
	return v.wander


## A boat under way close by, not heading into the shallows.
func _bow_to_ride(v: Visit) -> Vessel:
	if sim.marine == null:
		return null
	var p := Vector2(v.pos.x, v.pos.z)
	var best: Vessel = null
	var best_d := BOW_RANGE
	for b in sim.marine.vessels:
		if b.speed < BOW_SPEED:
			continue
		var d := b.pos2().distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best


## Just off the bow, riding the pressure wave; peels away when the time's up,
## the boat slows or it's heading into the shallows.
func _escort_aim(v: Visit, dt: float) -> Vector3:
	var b := v.escort
	if not is_instance_valid(b) or not sim.marine.vessels.has(b):
		v.escort = null
		v.escort_t = rng.randf_range(BOW_REST.x, BOW_REST.y)
		return v.wander
	v.escort_t -= dt
	var bow := b.pos2() + b.heading2() * (b.half_seg + b.hull_radius + 2.5)
	var ahead := bow + b.heading2() * 20.0
	if v.escort_t <= 0.0 or b.speed < BOW_SPEED * 0.6 \
			or sim.terrain.height_at(ahead.x, ahead.y) > v.species.depth:
		var at := Vector3(bow.x, 0.0, bow.y)
		_drop_escort(v)
		return at
	return Vector3(bow.x, 0.0, bow.y)


func _drop_escort(v: Visit) -> void:
	if v.escort:
		v.escort = null
		v.escort_t = rng.randf_range(BOW_REST.x, BOW_REST.y)
		# Feed on from wherever the ride left them.
		if v.phase == Phase.FORAGE and _open(v.pos, 14.0, v.species.depth):
			v.patch = v.pos
			v.wander = v.pos


## Ahead along the circle around the target, the radius wandering in and out. If
## that lands in the shallows (islands aren't round) the circle widens for a while.
func _orbit_aim(v: Visit, dt: float) -> Vector3:
	var c := Vector3(v.target.center.x, 0.0, v.target.center.y)
	var rel := Vector2(v.pos.x - c.x, v.pos.z - c.z)
	var r := v.orbit_r + 22.0 * sin(v.age * 0.045 + v.seed) + 10.0 * sin(v.age * 0.11 + v.seed * 2.3)
	r = maxf(r, v.target.radius + 12.0)
	var a := rel.angle() + v.orbit_dir * 0.5
	var aim := c + Vector3(cos(a), 0.0, sin(a)) * r
	if sim.terrain.height_at(aim.x, aim.z) > DEEP:
		v.orbit_r += 12.0 * dt
	else:
		v.orbit_r = move_toward(v.orbit_r, v.base_r, 2.0 * dt)
	return aim


## Never into water shallower than the species swims in (looking ahead only
## steers, and islands aren't round): if this step would take the group into the
## shallows, it slides off along the nearest heading that doesn't, or holds where
## it is (turning on) if there's none. Returns the step to take.
func _hold_off(v: Visit, step: float) -> float:
	var depth := v.species.depth
	var here := sim.terrain.height_at(v.pos.x, v.pos.z)
	for i in 7:
		for s: float in [1.0, -1.0]:
			var h := v.heading + s * i * 0.25
			var q := v.pos + Vector3(sin(h), 0.0, cos(h)) * step
			var g := sim.terrain.height_at(q.x, q.z)
			# Out of the shallows if it's ended up in them somehow.
			if g <= depth or g < here:
				v.heading = h
				return step
			if i == 0:
				break
	return 0.0


## The heading nearest `want` with open water ahead.
func _clear_heading(p: Vector3, want: float, depth := DEEP) -> float:
	for i in 10:
		for s: float in [1.0, -1.0]:
			var h := want + s * i * 0.3
			if _clear(p, h, depth):
				return h
			if i == 0:
				break
	return want


func _clear(p: Vector3, h: float, depth := DEEP) -> bool:
	var d := Vector3(sin(h), 0.0, cos(h))
	var bound := sim.map.half_size - 5.0
	for step: float in [10.0, 22.0, 36.0]:
		var q := p + d * step
		if absf(q.x) > bound or absf(q.z) > bound or sim.terrain.height_at(q.x, q.z) > depth:
			return false
	return true


## In daylight, credits the islands whose dock or passing ferries can see the group.
func _look(v: Visit) -> void:
	if not v.active():
		return
	var h := sim.hour()
	if h < DayCycle.SUNRISE or h > DayCycle.SUNSET:
		return
	var p := Vector2(v.pos.x, v.pos.z)
	for term: Terminal in sim.terminals.values():
		var isl := term.island
		if p.distance_to(Vector2(isl.shore.x, isl.shore.z)) < DOCK_RADIUS:
			_credit(v, isl, "the %s dock" % isl.name)
	if v.phase == Phase.HAULED and v.site.kind == MapData.HaulOut.Kind.DOCK:
		var m := sim.map.marinas[v.site.marina]
		_credit(v, sim.map.islands[m.island], "the %s marina" % sim.map.islands[m.island].name)
	for f in sim.ferries:
		if f.state == Ferry.State.SAILING \
				and p.distance_to(Vector2(f.global_position.x, f.global_position.z)) < FERRY_RADIUS:
			_credit(v, f.term_a.island, "the " + f.ferry_name)
			_credit(v, f.term_b.island, "the " + f.ferry_name)


func _credit(v: Visit, isl: MapData.Island, seen_from: String) -> void:
	if v.seen.has(isl.id):
		return
	v.seen[isl.id] = seen_from
	v.credited.append(isl)
	_spike(isl, v.species.draw * (1.0 + (PHOTO_BONUS if v.photographed else 0.0)))
	var r: Reputation = _rep[isl.id]
	r.sightings += 1
	r.last_day = sim.day
	r.last_species = v.species.name
	sighted.emit(v, isl, seen_from)


func _spike(isl: MapData.Island, amount: float) -> void:
	var r: Reputation = _rep[isl.id]
	r.value += amount * maxf(1.0 - r.value / REP_CAP, 0.0)
	r.best = maxf(r.best, r.value)
	r.floor = maxf(r.floor, r.best * SEASON_FLOOR)


func _end(v: Visit) -> void:
	v.phase = Phase.GONE
	v.escort = null
	if is_instance_valid(v.marker):
		v.marker.queue_free()
	visit_ended.emit(v)
