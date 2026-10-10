class_name SlipRamp
extends Node3D
## One slip's transfer span and apron (art/slip_mid.py), which the ferry using it works.
## Waiting for a boat the span's tip hangs RAISED above the car deck and the apron is
## folded up. As a ferry comes in the span is lowered to the deck's height on its hoist
## cables, the counterweights in the towers rising as it goes; once the boat is in, the
## rams let the apron down onto her car deck and the cars can cross. Before she leaves
## the apron comes up, then the span lifts clear again.
## The node sits in the terminal frame at the slip's lateral offset (the slip frame of
## the model); the towers themselves are static scenery (WorldBuilder).

# Dimensions, as art/slip_mid.py has them.
const HINGE_U := 2.0
const SPAN_L := 26.5
const APRON_L := 7.0
const APRON_T := 0.12                   # the plate's thickness past its deep heel
const APRON_HEEL := 1.0
const LIFT_Z := 25.0
const LUG := Vector2(9.0, -0.5)        # cable lugs on the lifting beam (x, y in the span's frame)
const LUG_TOP := 0.75                   # the cable's socket above the lug
const TOWER_X := 9.6
const SHEAVE_Y := 14.6
const SHEAVE_R := 0.6
const RAM_X := 5.9
const RAM_A := Vector2(0.5, 23.5)       # ram cylinder's eye on the span (y, z)
const RAM_B := Vector2(0.5, 1.2)        # rod's eye on the apron (y, z)

# How high the span's tip waits above the deck, how high it sits down at the deck (for
# the apron's plate to slope down onto it, lying on her deck rather than in it), and how
# far the apron folds up.
const RAISED := 1.5
const LAND := 0.35
const APRON_UP := deg_to_rad(18.0)
# Seconds to lower (or raise) the span, and the apron.
const SPAN_TIME := 5.0
const APRON_TIME := 3.0
# The counterweights' eyes with the span down at the deck.
const CW_TOP_DOWN := 10.6
# The apron lying on the deck, toe down: how far it slopes below the horizontal, and where
# along the slip (u) the span's tip and the apron's toe come.
static var LAND_DIP := asin((LAND - APRON_T - 0.01) / APRON_L)
static var TIP_U := HINGE_U + sqrt(SPAN_L * SPAN_L - LAND * LAND)
static var TOE_U := TIP_U + APRON_L * cos(LAND_DIP)

var _span: Node3D
var _apron: Node3D
var _weights: Array[Node3D] = []
var _span_cables: Array[Node3D] = []
var _weight_cables: Array[Node3D] = []
var _bodies: Array[Node3D] = []
var _rods: Array[Node3D] = []
var _span_t := 1.0     # 0 down at the deck .. 1 raised
var _apron_t := 1.0    # 0 lying on the deck .. 1 folded up
var _span_down := false
var _apron_down := false
var _lug_y_down := 0.0


static func available() -> bool:
	return Models.mid_slip


## Where along the slip (u) a ferry's end lies docked, `gap` short of where the apron's toe
## should land on her deck (her apron line), but never in under the span or the apron's heel.
static func dock_end(gap: float) -> float:
	return maxf(TOE_U - gap, TIP_U + APRON_HEEL)


## The height above the lot of the span and apron's top, lying on a ferry, at `u` along the
## slip (0 off the end of the apron), for the cars crossing it.
static func lift_at(u: float) -> float:
	if u <= HINGE_U or u >= TOE_U:
		return 0.0
	if u <= TIP_U:
		return LAND * (u - HINGE_U) / (TIP_U - HINGE_U)
	return lerpf(LAND, APRON_T + 0.01, (u - TIP_U) / (TOE_U - TIP_U))


## The crossing between the lot and the span's tip at lateral offset `dv`, shore end first
## (terminal frame).
func crossing(dv: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(position.x + dv, Layout.LOT_Y, HINGE_U),
		Vector3(position.x + dv, Layout.LOT_Y + LAND, TIP_U)])


func _init(v: float) -> void:
	name = "SlipRamp"
	position.x = v
	_span = _part("span", self)
	_span.position = Vector3(0.0, Layout.LOT_Y, HINGE_U)
	_apron = _part("apron", _span)
	_apron.position = Vector3(0.0, 0.0, SPAN_L)
	for s: float in [-1.0, 1.0]:
		_weights.append(_part("counterweight", self))
		_span_cables.append(_part("cable", self))
		_weight_cables.append(_part("cable", self))
		var body := _part("rambody", _span)
		body.position = Vector3(s * RAM_X, RAM_A.x, RAM_A.y)
		_bodies.append(body)
		var rod := _part("ramrod", _apron)
		rod.position = Vector3(s * RAM_X, RAM_B.x, RAM_B.y)
		_rods.append(rod)
	_lug_y_down = Layout.LOT_Y + LAND * LIFT_Z / SPAN_L + LUG.y + LUG_TOP
	_pose()


func _part(part: String, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.slip_mesh(part)
	parent.add_child(mi)
	return mi


## A ferry is coming in: lower the span to the deck.
func lower() -> void:
	_span_down = true


## The ferry is in: lower the span (if it isn't already) and let the apron down onto her.
func land() -> void:
	_span_down = true
	_apron_down = true


## The ferry is about to leave: the apron comes up, then the span lifts clear.
func lift() -> void:
	_span_down = false
	_apron_down = false


## Down and lying on the ferry's deck, as it is for a boat already in at the start.
func snap_down() -> void:
	land()
	_span_t = 0.0
	_apron_t = 0.0
	_pose()


## Cars may cross.
func is_down() -> bool:
	return _span_t <= 0.0 and _apron_t <= 0.0


## The apron is folded up clear of the ferry's deck: she may leave.
func is_clear() -> bool:
	return _apron_t >= 1.0


func _process(delta: float) -> void:
	var was := Vector2(_span_t, _apron_t)
	# The apron only comes down onto a span already at the deck, and the span only
	# lifts with the apron folded up.
	if _apron_down and _span_t <= 0.0:
		_apron_t = maxf(_apron_t - delta / APRON_TIME, 0.0)
	else:
		_apron_t = minf(_apron_t + delta / APRON_TIME, 1.0)
	if _span_down:
		_span_t = maxf(_span_t - delta / SPAN_TIME, 0.0)
	elif _apron_t >= 1.0:
		_span_t = minf(_span_t + delta / SPAN_TIME, 1.0)
	if Vector2(_span_t, _apron_t) != was:
		_pose()


func _pose() -> void:
	var tilt := asin(lerpf(LAND, RAISED, smoothstep(0.0, 1.0, _span_t)) / SPAN_L)
	_span.rotation.x = -tilt
	# The apron's angle is to the horizontal, whatever the span's.
	_apron.rotation.x = tilt + lerpf(LAND_DIP, -APRON_UP, smoothstep(0.0, 1.0, _apron_t))
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		# The hoist cable from the sheave down to the lug, and the counterweight on the
		# other side of the sheave taking up what the span lets out.
		var lug := _span.transform * Vector3(s * LUG.x, LUG.y + LUG_TOP, LIFT_Z)
		_hang(_span_cables[i], Vector3(s * (TOWER_X - SHEAVE_R), SHEAVE_Y, lug.z), lug)
		var cw := Vector3(s * (TOWER_X + SHEAVE_R), CW_TOP_DOWN - (lug.y - _lug_y_down), lug.z)
		_weights[i].position = cw
		_hang(_weight_cables[i], Vector3(cw.x, SHEAVE_Y, cw.z), cw)
		# The ram between the span and the apron: the cylinder aims at the rod's eye,
		# the rod back at the cylinder's.
		var a := _bodies[i].position
		var b := _apron.transform * _rods[i].position
		_bodies[i].basis = Basis.looking_at(b - a, Vector3.UP, true)
		_rods[i].basis = Basis.looking_at(_apron.transform.affine_inverse() * a - _rods[i].position, Vector3.UP, true)


## Stretches a cable (1 m down -Y from its origin) from `top` down to `bottom`.
static func _hang(cable: Node3D, top: Vector3, bottom: Vector3) -> void:
	var d := top - bottom
	var x := Vector3.RIGHT
	var z := x.cross(d).normalized()
	cable.transform = Transform3D(Basis(x, d, z), top)
