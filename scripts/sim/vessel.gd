class_name Vessel
extends Node3D
## Anything afloat that gets under way: ferries, sailboats and cargo ships. Each hull
## is a capsule on the water plane (a segment of ±half_seg along the heading,
## widened by hull_radius). Every frame MarineTraffic looks along each moving
## vessel's path and sets `clear`, how far its centre may still go before it would
## touch another hull or cut across the path ahead of a higher-ranked vessel; the
## vessel then keeps its speed low enough to stop within it. A vessel steering its
## own way (free_nav) keeps clear of others' paths itself, so for it this is only
## the last-resort check against touching another hull.

var vessel_name := ""
var spec: VesselSpec      # its type (ferries don't have one)
var speed := 0.0
var cruise := 1.0
var yield_decel := 1.0    # braking used to stop short of a conflict
var rank := 0             # higher ranks keep their course; lower ones give way
var half_seg := 1.0
var hull_radius := 1.0
var claim_step := 2.0     # spacing of the points MarineTraffic samples ahead
var hold := INF           # how far it means to go for now (short of a channel or berth it is waiting for)
var lights: MeshInstance3D
var wake: WakeTrail       # its trail on the water, if it leaves one
var free_nav := false     # steering its own way (a Helm), not along a fixed path

# Set by MarineTraffic each frame.
var clear := INF
var blocker: Vessel = null
var blocked_by_hull := false   # (rather than by giving way to another's path)


## Whether it is trying to get somewhere (moored or docked vessels aren't).
func wants_to_move() -> bool:
	return false


## Where the centre will be after advancing `d` further along its path.
func ahead(_d: float) -> Vector2:
	return pos2()


## Distance left along its current path.
func path_left() -> float:
	return 0.0


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func heading2() -> Vector2:
	var z := global_transform.basis.z
	var h := Vector2(z.x, z.z)
	return h.normalized() if h.length_squared() > 1e-8 else Vector2.DOWN


## How far ahead it checks for conflicts: always enough to stop from cruise.
func self_look() -> float:
	return cruise * cruise / (2.0 * yield_decel) + half_seg + 4.0


## How much of its path ahead it shows others (who must stay out of it if they
## rank lower): grows with speed, never less than it needs to stop from cruise,
## but no further than it may actually go now (so a vessel that is itself held
## up doesn't hold up the one it is waiting for).
func shown_look() -> float:
	var look := maxf(speed * 6.0 + speed * speed / (2.0 * yield_decel) + half_seg + 3.0, self_look())
	return minf(look, minf(clear, hold))


## Fastest it may go and still stop within `clear`.
func yield_speed() -> float:
	return sqrt(2.0 * yield_decel * maxf(clear - 0.5, 0.0))


## Whether it is held up waiting on `v` (its hull or path, or something `v` holds).
func waits_for(v: Vessel) -> bool:
	return blocker == v


## Its hull and wake as the water shader draws them: half beam, length, how hard
## its props churn the water astern (0 for none, 1 for a ferry's) and the size of
## its Kelvin waves relative to a ferry's.
func wake_hull() -> Vector4:
	if spec:
		return spec.wake_hull()
	return Vector4(hull_radius, (half_seg + hull_radius) * 2.0, 0.0, 1.0)


## Its outline as the water shader draws it: how far back from the stem the bow
## narrows, the half-width at the stem (as a fraction of the half beam), and the
## same for the stern.
func wake_shape() -> Vector4:
	if spec:
		return spec.shape
	return Vector4((half_seg + hull_radius) * 0.4, 0.2, 1.0, 0.8)


## Reverse thrust thrown out ahead of the bow, 0..1.
func front_thrust() -> float:
	return 0.0


# --- Helm hooks (for vessels steering their own way; see Helm) ---------------------

func helm_yaw() -> float:
	var h := heading2()
	return atan2(h.x, h.y)


## Headings it could steer to make good `bearing`, as [[yaw, extra cost], ...].
func helm_courses(bearing: float) -> Array:
	return [[bearing, 0.0]]


## Best speed on heading `yaw`.
func helm_speed(_yaw: float) -> float:
	return cruise


## Why it must keep clear of `other` (a Vessel or a Wildlife.Visit), or "" if it
## is the stand-on vessel.
func helm_role(_other: Variant) -> String:
	return "Keeping clear"


func kind_text() -> String:
	return spec.kind if spec else "Vessel"


## Its type, if it has one ("Cruising yacht").
func type_text() -> String:
	return spec.type_name if spec else kind_text()


## Takes on `s`: its hull, handling, wake and look. `variant` picks among the
## type's model variants.
func apply_spec(s: VesselSpec, variant := 0) -> MeshInstance3D:
	spec = s
	cruise = s.cruise
	yield_decel = s.decel
	half_seg = s.half_seg()
	hull_radius = s.radius()
	claim_step = clampf(s.half_length, 2.0, 5.0)
	wake = s.make_wake()
	var hull := MeshInstance3D.new()
	hull.mesh = s.model.call(variant)
	hull.scale = Vector3.ONE * s.scale
	add_child(hull)
	lights = MeshInstance3D.new()
	lights.mesh = s.lights.call(variant)
	lights.scale = Vector3.ONE * s.scale
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights.layers = NightLights.LAYER
	lights.visible = false
	add_child(lights)
	return hull


func status_text() -> String:
	return ""


## The blocking vessel's name for status lines, if it is holding for one.
func holding_text() -> String:
	if wants_to_move() and speed < 0.2 and clear < 2.0 and is_instance_valid(blocker):
		return "Holding for " + blocker.vessel_name
	return ""
