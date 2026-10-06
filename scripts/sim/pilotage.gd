class_name Pilotage
extends RefCounted
## The pilot station's work: a pilot boat runs a pilot out to every ship coming
## in, to board it on its boarding ground just inside the map, and fetches the
## pilot off again on its way out; a tug meets every laden tanker and escorts it
## through. Each second it hands out what needs doing to whichever boat is free
## and nearest (see PilotBoat, Tug), timing the run out to fetch a pilot off so
## the boat is there as the ship comes up. The station only serves the
## approaches within REACH of it: a ship coming in from further off has had its
## pilot put aboard offshore, and one going out that way keeps its pilot on to
## its next port.

const PILOT_NAMES := ["Pacific Pilot", "Salish Pilot", "Haro Pilot", "Strait Pilot"]
const TUG_NAMES := ["Sea Bear", "Tenacious", "Saturna", "Kodiak", "Valiant", "Ocean Ranger"]
const RANK_TENDER := 1600
const LAND_LEAD := 45.0        # seconds early a boat aims to be for a pilot coming off
const REACH := 620.0
const SHORT_PASSAGE := 350.0

var traffic: MarineTraffic
var station: MapData.PilotStation
var pilot_boats: Array[PilotBoat] = []
var tugs: Array[Tug] = []
var boarded := 0
var landed := 0
var escorts := 0
var missed := 0
var _timer := 0.0
var _missed := {}
var _seen := {}


func _init(t: MarineTraffic) -> void:
	traffic = t
	if t.sim.map.stations.is_empty():
		return
	station = t.sim.map.stations[0]
	var k := t.sim.map.map_seed
	# Two pilot boats either side of a tug.
	for b in station.berths():
		if b == 1:
			var tug := Tug.new()
			t.sim.add_child(tug)
			var sp := VesselTypes.pick(VesselTypes.tugs(), t.rng)
			tug.setup(t, TUG_NAMES[k % TUG_NAMES.size()], sp, station, b, t.rng.randi_range(0, sp.variants - 1))
			tugs.append(tug)
			t.register(tug, RANK_TENDER)
		else:
			var boat := PilotBoat.new()
			t.sim.add_child(boat)
			var sp := VesselTypes.pick(VesselTypes.pilot_boats(), t.rng)
			# A station's boats wear its colours.
			boat.setup(t, PILOT_NAMES[(k + b) % PILOT_NAMES.size()], sp, station, b, k % sp.variants)
			pilot_boats.append(boat)
			t.register(boat, RANK_TENDER)


func remove(v: Vessel) -> void:
	if v is PilotBoat:
		pilot_boats.erase(v)
	elif v is Tug:
		tugs.erase(v)


func update(delta: float) -> void:
	if station == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	for ship in traffic.cargo_ships:
		if not is_instance_valid(ship):
			continue
		if not _seen.has(ship):
			_seen[ship] = true
			_first_sight(ship)
		_board(ship)
		_land(ship)
		_escort(ship)


## Whether its boarding and landing grounds are this station's to serve (not if
## it only clips a corner of the map).
func _first_sight(ship: CargoShip) -> void:
	if ship.land_s - ship.board_s < SHORT_PASSAGE:
		ship.pilot_aboard = true
		ship.land_here = false
		return
	var st := station.at(Layout.QUAY_LANE_U, 0.0)
	var home := Vector2(st.x, st.z)
	if not ship.pilot_aboard and ship.path.sample(ship.board_s).distance_to(home) > REACH:
		ship.pilot_aboard = true
	ship.land_here = ship.path.sample(ship.land_s).distance_to(home) <= REACH


## A ship coming in with no pilot yet: the free boat that can get out to it
## soonest takes the job.
func _board(ship: CargoShip) -> void:
	if ship.pilot_aboard or _has_boat(ship):
		return
	if ship.s > ship.land_s - 250.0:
		if not _missed.has(ship):
			_missed[ship] = true
			missed += 1

		return
	var meet := ship.path.sample(clampf(ship.s + 200.0, ship.board_s, ship.land_s))
	var boat := _nearest(meet)
	if boat:
		boat.assign_job(ship, PilotBoat.Job.BOARD, meet)


## A ship with its pilot aboard nearing its landing ground: a boat sets off in
## time to be there as it comes up.
func _land(ship: CargoShip) -> void:
	if not ship.pilot_aboard or not ship.land_here or ship.pilot_landed or _has_boat(ship) or ship.s > ship.land_s:
		return
	var meet := ship.path.sample(ship.land_s)
	var boat := _nearest(meet)
	if boat == null:
		return
	var ship_eta := (ship.land_s - ship.s) / maxf(ship.speed, 1.0)
	if ship_eta <= boat.eta(meet) + LAND_LEAD:
		boat.assign_job(ship, PilotBoat.Job.LAND, meet)


## A laden tanker with no escort: the free tug goes out to meet it.
func _escort(ship: CargoShip) -> void:
	if not ship.needs_escort() or ship.escorted or (ship.escort != null and is_instance_valid(ship.escort)):
		return
	if ship.s > ship.land_s - 350.0:
		return
	for tug in tugs:
		if tug.available():
			tug.escort(ship, ship.path.sample(clampf(ship.s + 250.0, ship.board_s, ship.land_s)))
			return


func _has_boat(ship: CargoShip) -> bool:
	return ship.pilot_boat != null and is_instance_valid(ship.pilot_boat) and ship.pilot_boat.ship == ship


## The free pilot boat that could get to `p` soonest.
func _nearest(p: Vector2) -> PilotBoat:
	var best: PilotBoat = null
	var best_t := INF
	for b in pilot_boats:
		if not b.available():
			continue
		var t := b.eta(p)
		if t < best_t:
			best_t = t
			best = b
	return best
