class_name Simulation
extends Node3D
## Owns the game clock, demand model, economy and all terminals/ferries/vehicles.
## One real second = one game minute at 1x speed (Engine.time_scale scales it).

const FARE_CAR := 18.5
const FARE_TRUCK := 42.0
const FERRY_NAMES := ["Cedar Star", "Orca Spirit", "Madrona Belle", "Tidewater", "Salish Dawn",
	"Heron", "Sea Lark", "Kelp Runner", "Evergreen", "Cormorant", "Island Pride", "Driftwood Queen"]

var map: MapData
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var minutes := 6.0 * 60.0
var day := 12
var terminals := {}             # island id -> Terminal
var ferries: Array[Ferry] = []
var traffic: Node3D
var revenue_today := 0.0
var revenue_total := 0.0
var cars_today := 0
var weather := "Partly Cloudy"
var wind_dir := "SW"
var wind_speed := 12
var _tide_phase := 0.0


func setup(m: MapData, t: Terrain) -> void:
	map = m
	terrain = t
	rng.seed = m.map_seed + 99
	wind_dir = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][rng.randi_range(0, 7)]
	wind_speed = rng.randi_range(4, 24)
	weather = ["Partly Cloudy", "Sunny", "Overcast", "Light Breeze"][rng.randi_range(0, 3)]
	_tide_phase = rng.randf() * TAU
	traffic = Node3D.new()
	traffic.name = "Traffic"
	add_child(traffic)
	for isl in map.islands:
		if isl.has_terminal:
			var term := Terminal.new()
			add_child(term)
			term.setup(self, isl)
			terminals[isl.id] = term
	for r in map.routes:
		var f := Ferry.new()
		add_child(f)
		f.setup(self, r, FERRY_NAMES[r.id % FERRY_NAMES.size()])
		ferries.append(f)
	for term: Terminal in terminals.values():
		term.prefill()
	for i in ferries.size():
		ferries[i].start_staggered(i)


func _process(delta: float) -> void:
	minutes += delta
	if minutes >= 24.0 * 60.0:
		minutes -= 24.0 * 60.0
		day += 1
		revenue_today = 0.0
		cars_today = 0
		for term: Terminal in terminals.values():
			term.served_today = 0


func make_vehicle(parent: Node3D = null) -> Vehicle:
	var v := Vehicle.new()
	var truck := rng.randf() < 0.12
	var col := rng.randi_range(0, Models.CAR_COLORS.size() - 1)
	v.setup(Models.truck(col) if truck else Models.car(col), truck)
	(parent if parent else traffic).add_child(v)
	return v


func collect_fare(car: Vehicle) -> void:
	var fare := FARE_TRUCK if car.is_truck else FARE_CAR
	revenue_today += fare
	revenue_total += fare
	cars_today += 1


func hour() -> float:
	return fmod(minutes / 60.0, 24.0)


## Commuter-shaped demand: morning and evening peaks, quiet nights.
func demand_factor() -> float:
	var h := hour()
	var f := 0.18 + 1.25 * exp(-pow((h - 7.4) / 1.1, 2.0)) + 1.0 * exp(-pow((h - 17.3) / 1.3, 2.0)) \
		+ 0.45 * exp(-pow((h - 12.5) / 2.5, 2.0))
	if h < 5.0 or h > 22.5:
		f *= 0.3
	return f


## Cars per game minute arriving at an island's terminal.
func demand_rate(isl: MapData.Island) -> float:
	return isl.population / 5200.0 * demand_factor()


func demand_label(isl: MapData.Island) -> String:
	var r := demand_rate(isl)
	if r > 0.9:
		return "Very High"
	if r > 0.5:
		return "High"
	if r > 0.2:
		return "Medium"
	return "Low"


func satisfaction() -> float:
	var total := 0.0
	var weight := 0.0
	for term: Terminal in terminals.values():
		total += term.satisfaction() * term.island.population
		weight += term.island.population
	return total / weight if weight > 0.0 else 0.0


func total_queued() -> int:
	var total := 0
	for term: Terminal in terminals.values():
		total += term.total_queued()
	return total


func clock_text(m: float = -1.0) -> String:
	if m < 0.0:
		m = minutes
	var total := int(m) % 1440
	var h := floori(total / 60.0)
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, total % 60, "AM" if h < 12 else "PM"]


func date_text() -> String:
	return "May %d, Year 8" % day


func temperature() -> int:
	return roundi(12.0 + 5.0 * sin((hour() - 9.0) / 24.0 * TAU))


func tide() -> Vector2:
	var t := minutes / (12.42 * 60.0) * TAU + _tide_phase
	return Vector2(1.6 * sin(t), cos(t))  # level (m), rising if y > 0
