class_name VesselSpec
extends RefCounted
## What a type of vessel is like: its hull, how it handles, the wake it leaves and
## how it is drawn. Sailboats and cargo ships are built from one, so a new size or
## type is a few lines in VesselTypes (plus a model, if it looks different)
## rather than a new script. Lengths are metres, speeds metres per second.

var id := ""
var kind := ""                  # its class, for the HUD ("Sailboat")
var type_name := ""             # this type of it ("Cruising yacht")
var weight := 1.0               # how often it turns up among its class

# The hull itself, and the clearance kept round it (the capsule other vessels keep
# out of stands `pad` proud of it).
var half_length := 1.8
var half_beam := 0.62
var pad := 0.0
var draft := 1.0                # depth of water it floats in

# Handling. A sailboat's `cruise` is on a beam reach in a moderate breeze; it
# motors at `motor_speed`.
var cruise := 3.0
var motor_speed := 2.0
var accel := 0.35
var decel := 0.6
var turn := 0.45                # rad/s (under sail, for a sailboat)
var motor_turn := 0.8

# Wake: breadcrumbs dropped every `wake_spacing` metres and kept `wake_life`
# seconds (at most `wake_crumbs`), how hard its props churn the water (1 = a
# ferry's), the size of its Kelvin waves (1 = a ferry's), and its outline (see
# Vessel.wake_shape).
var wake_spacing := 2.0
var wake_life := 14.0
var wake_crumbs := 44
var wash := 0.3
var kelvin := 0.28
var shape := Vector4(1.4, 0.0, 0.3, 0.9)

# Drawing: model builders (each takes a variant number and returns an ArrayMesh)
# drawn `scale` times their built size. `model_alt` is a sailboat's look with
# its sails stowed.
var model: Callable
var model_alt: Callable
var lights: Callable
var name_plate: Callable        # fn(name) -> ArrayMesh or null: its name painted on, if it has one
var scale := 1.0
var variants := 1               # how many variants `model` has


## Radius of the capsule other vessels keep out of.
func radius() -> float:
	return half_beam + pad


## Half the length of the capsule's spine.
func half_seg() -> float:
	return maxf(half_length + pad - radius(), 0.0)


func wake_hull() -> Vector4:
	return Vector4(half_beam, half_length * 2.0, wash, kelvin)


func make_wake() -> WakeTrail:
	return WakeTrail.new(half_length, wake_spacing, wake_life, wake_crumbs)


## The same type built `f` times the size, as `new_id` / `new_name`. Lengths scale
## with it; speeds with its square root (a longer hull is a faster one), and it
## turns more slowly the bigger it is.
func scaled(f: float, new_id: String, new_name: String) -> VesselSpec:
	var s := copy()
	s.id = new_id
	s.type_name = new_name
	s.half_length *= f
	s.half_beam *= f
	s.pad *= f
	s.draft *= f
	s.cruise *= sqrt(f)
	s.motor_speed *= sqrt(f)
	s.turn /= sqrt(f)
	s.motor_turn /= sqrt(f)
	s.wake_spacing *= f
	s.kelvin *= f
	s.shape = Vector4(shape.x * f, shape.y, shape.z * f, shape.w)
	s.scale *= f
	return s


func copy() -> VesselSpec:
	var s := VesselSpec.new()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			s.set(p.name, get(p.name))
	return s
