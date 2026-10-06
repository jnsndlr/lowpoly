class_name VesselTypes
extends RefCounted
## The catalogue of vessel types MarineTraffic puts on the water. Each class has a
## base type and its variants; a new size is one scaled() line, a new type (with
## its own model) a new function. `weight` sets how often each turns up.


static func sailboats() -> Array[VesselSpec]:
	var sloop := _sloop()
	var day_sailer := sloop.scaled(0.85, "day_sailer", "Day sailer")
	day_sailer.weight = 0.8
	var cruiser := sloop.scaled(1.3, "cruiser", "Cruising yacht")
	cruiser.weight = 0.5
	return [sloop, day_sailer, cruiser]


static func cargo_ships() -> Array[VesselSpec]:
	var container := _container_ship()
	var feeder := container.scaled(0.7, "feeder", "Feeder ship")
	feeder.weight = 0.6
	return [container, feeder, _tanker(container), _bulk_carrier(container)]


static func fishing_boats() -> Array[VesselSpec]:
	return [_trawler()]


static func motor_yachts() -> Array[VesselSpec]:
	var flybridge := _motor_yacht()
	var express := flybridge.scaled(0.85, "express", "Express cruiser")
	express.weight = 0.6
	return [flybridge, express]


static func pilot_boats() -> Array[VesselSpec]:
	return [_pilot_boat()]


static func tugs() -> Array[VesselSpec]:
	return [_tug()]


## One of `types`, picked by weight.
static func pick(types: Array[VesselSpec], rng: RandomNumberGenerator) -> VesselSpec:
	var total := 0.0
	for t in types:
		total += t.weight
	var r := rng.randf() * total
	for t in types:
		r -= t.weight
		if r <= 0.0:
			return t
	return types.back()


# --- Base types -----------------------------------------------------------------------

static func _sloop() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "sloop"
	s.kind = "Sailboat"
	s.type_name = "Sloop"
	s.half_length = 1.8
	s.half_beam = 0.62
	s.pad = 0.28
	s.cruise = 3.0
	s.motor_speed = 2.0
	s.accel = 0.35
	s.decel = 0.6
	s.turn = 0.45
	s.motor_turn = 0.8
	s.wake_spacing = 2.0
	s.wake_life = 14.0
	s.wake_crumbs = 44
	# No prop under sail: just a faint ribbon of disturbed water and little waves.
	s.wash = 0.3
	s.kelvin = 0.28
	# Pointed forward, a broad transom aft.
	s.shape = Vector4(1.4, 0.0, 0.3, 0.9)
	s.model = func(_v: int) -> ArrayMesh: return Models.sailboat()
	s.model_alt = func(_v: int) -> ArrayMesh: return Models.sailboat_furled()
	s.lights = func(_v: int) -> ArrayMesh: return Models.sailboat_lights()
	return s


static func _container_ship() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "container"
	s.kind = "Cargo ship"
	s.type_name = "Container ship"
	s.half_length = 32.0
	s.half_beam = 5.6
	s.cruise = 5.0
	s.accel = 0.12
	s.decel = 0.25
	s.turn = 0.08
	# A long, slow trail: the big single prop's wash lingers well astern, and
	# boils harder than a ferry's; its wake's waves run longer and taller.
	s.wake_spacing = 12.0
	s.wake_life = 40.0
	s.wake_crumbs = 46
	s.wash = 1.3
	s.kelvin = 1.6
	# A fine bow drawn to a point over its last 12 m, and a near-square transom.
	s.shape = Vector4(12.0, 0.0, 2.0, 0.86)
	s.model = func(v: int) -> ArrayMesh: return Models.cargo_ship(v)
	s.lights = func(_v: int) -> ArrayMesh: return Models.cargo_ship_lights()
	s.variants = 3
	return s


## A tanker on the container ship's hull, a little bigger and deep laden: she
## makes less way and pushes up a heavier wash.
static func _tanker(container: VesselSpec) -> VesselSpec:
	var s := container.scaled(1.15, "tanker", "Tanker")
	s.cruise = 4.4
	s.accel = 0.1
	s.wash = 1.5
	s.model = func(v: int) -> ArrayMesh: return Models.tanker(v)
	s.weight = 0.7
	return s


## A geared bulk carrier, also on the container ship's hull.
static func _bulk_carrier(container: VesselSpec) -> VesselSpec:
	var s := container.scaled(1.1, "bulk_carrier", "Bulk carrier")
	s.cruise = 4.6
	s.accel = 0.1
	s.wash = 1.4
	s.model = func(v: int) -> ArrayMesh: return Models.bulk_carrier(v)
	s.weight = 0.7
	return s


static func _trawler() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "trawler"
	s.kind = "Fishing boat"
	s.type_name = "Trawler"
	s.half_length = 10.0
	s.half_beam = 3.2
	s.pad = 0.5
	s.draft = 2.2
	s.cruise = 3.6
	s.motor_speed = 2.0
	s.accel = 0.16
	s.decel = 0.3
	s.turn = 0.2
	s.motor_turn = 0.18
	s.wake_spacing = 5.0
	s.wake_life = 26.0
	s.wake_crumbs = 44
	# A single big prop driving a heavy hull: more wash than a yacht, and a
	# full-bodied wave train for her size.
	s.wash = 0.6
	s.kelvin = 0.55
	# A bluff bow narrowing over its last 5 m, and a broad transom.
	s.shape = Vector4(5.5, 0.15, 1.5, 0.85)
	s.model = func(v: int) -> ArrayMesh: return Models.trawler(v)
	s.lights = func(_v: int) -> ArrayMesh: return Models.trawler_lights()
	s.variants = 3
	return s


## A flybridge motor yacht of the sailboats' scale. `cruise` is its speed on the
## plane; `motor_speed` its no-wake speed, in harbour and among anchored boats.
static func _motor_yacht() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "flybridge"
	s.kind = "Motor yacht"
	s.type_name = "Flybridge cruiser"
	s.half_length = 2.75
	s.half_beam = 0.9
	s.pad = 0.3
	s.draft = 1.0
	s.cruise = 6.2
	s.motor_speed = 1.5
	s.accel = 0.5
	s.decel = 0.8
	s.turn = 0.5
	s.motor_turn = 0.75
	s.wake_spacing = 2.4
	s.wake_life = 18.0
	s.wake_crumbs = 44
	# (MotorYacht.wake_hull varies these with how it sits in the water.)
	s.wash = 0.8
	s.kelvin = 0.5
	# A fine entry over its forward 1.6 m, and a broad transom.
	s.shape = Vector4(1.6, 0.0, 0.3, 0.92)
	s.model = func(v: int) -> ArrayMesh: return Models.motor_yacht(v)
	s.lights = func(_v: int) -> ArrayMesh: return Models.motor_yacht_lights()
	s.variants = 3
	return s


## A fast, heavily fendered launch that runs the pilots out to the ships.
static func _pilot_boat() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "pilot"
	s.kind = "Pilot boat"
	s.type_name = "Pilot launch"
	s.half_length = 4.5
	s.half_beam = 1.5
	s.pad = 0.4
	s.draft = 1.4
	s.cruise = 7.5
	s.motor_speed = 3.0
	s.accel = 0.6
	s.decel = 0.9
	s.turn = 0.35
	s.motor_turn = 0.35
	s.wake_spacing = 3.5
	s.wake_life = 20.0
	s.wake_crumbs = 44
	s.wash = 1.0
	s.kelvin = 0.7
	s.shape = Vector4(2.5, 0.0, 0.8, 0.9)
	s.model = func(v: int) -> ArrayMesh: return Models.pilot_boat(v)
	s.lights = func(_v: int) -> ArrayMesh: return Models.pilot_boat_lights()
	s.variants = 3
	return s


## An escort tug: quick enough to keep up with a laden tanker and catch one up.
static func _tug() -> VesselSpec:
	var s := VesselSpec.new()
	s.id = "tug"
	s.kind = "Tug"
	s.type_name = "Escort tug"
	s.half_length = 7.0
	s.half_beam = 2.5
	s.pad = 0.4
	s.draft = 2.4
	s.cruise = 5.6
	s.motor_speed = 2.6
	s.accel = 0.3
	s.decel = 0.5
	s.turn = 0.3
	s.motor_turn = 0.3
	s.wake_spacing = 5.0
	s.wake_life = 26.0
	s.wake_crumbs = 44
	# Twin big props: a heavy wash for her length.
	s.wash = 1.1
	s.kelvin = 0.75
	s.shape = Vector4(3.0, 0.1, 1.2, 0.85)
	s.model = func(v: int) -> ArrayMesh: return Models.tug(v)
	s.lights = func(_v: int) -> ArrayMesh: return Models.tug_lights()
	s.variants = 3
	return s
