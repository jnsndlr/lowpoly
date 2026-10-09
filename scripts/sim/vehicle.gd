class_name Vehicle
extends Node3D
## A car or truck that follows a list of waypoints (in its parent's space) and calls
## back when it arrives. Terminals and ferries decide where it goes next. A tractor
## tows a trailer (attach_trailer) that pivots on its fifth wheel: the trailer's axles
## are dragged along after the hitch, so a rig cuts inside on the turns.

## Height (m, real size) over which a vehicle goes in the tall lanes (WSF's oversize
## line is 7'2").
const TALL := 2.2
## Spacing of queued and parked vehicles (ferry rows; terminal queues are a little
## roomier): a vehicle takes as many as its length needs.
const SLOT := FerryClass.ROW_SPACING

var path := PackedVector3Array()
var speed := 24.0
var delay := 0.0
var is_truck := false
var is_tall := false       # wants a ferry lane with headroom: trucks and high-roof vans
var model := ""            # VehicleData key ("" for the code-built car and truck)
var lane_v := 0.0          # lateral lane position while queued at a terminal
var lot_arrival := 0.0     # sim minutes when it joined the queue
var length := 0.0          # bumper to bumper, rig included (game units)
var slots := 1             # queue / deck slots it takes
var center_offset := 0.0   # where the middle of the whole rig lies along its own z
var trailer: Node3D        # pivots at the fifth wheel (null for anything else)
var trailer_model := ""
var _hitch := Vector3.ZERO     # the fifth wheel, in the tractor's frame (model units)
var _trailer_axle := Vector3.ZERO  # the trailer's axle centre, in the parent's space
var _trailer_reach := 0.0          # fifth wheel to that, in the parent's space
var _on_arrive := Callable()


func setup(mesh: Mesh, truck: bool, model_key := "", model_scale := Models.LEGACY_SCALE) -> void:
	is_truck = truck
	model = model_key
	is_tall = truck or (model_key != "" and VehicleData.VARIANTS[model_key].size.y > TALL)
	# (Its lights, drawn by NightLights from its transform, scale with it.)
	scale = Vector3.ONE * model_scale
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	if model_key != "":
		var size: Vector3 = VehicleData.VARIANTS[model_key].size
		_set_length(size.z * model_scale, 0.0)
	else:
		length = SLOT * 0.8  # (the code-built car and truck: a slot each)


## Hooks trailer `key` (a VehicleData trailer, painted `mesh`) on the fifth wheel.
func attach_trailer(key: String, mesh: Mesh) -> void:
	var td: Dictionary = VehicleData.VARIANTS[key]
	var vd: Dictionary = VehicleData.VARIANTS[model]
	trailer_model = key
	_hitch = vd.hitch
	trailer = Node3D.new()
	trailer.position = _hitch
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var pin: Vector3 = td.pin
	mi.position = Vector3(0, -pin.y, -pin.z)
	trailer.add_child(mi)
	add_child(trailer)
	# Front of the tractor to the back of the trailer.
	var front: float = vd.size.z * 0.5
	var back: float = _hitch.z - (pin.z + td.size.z * 0.5)
	_set_length((front - back) * scale.x, ((front + back) * 0.5) * scale.x)
	_reset_trailer()


func _set_length(l: float, offset: float) -> void:
	length = l
	center_offset = offset
	slots = maxi(1, ceili((l - 0.4) / SLOT))


## The trailer's frame in the parent's space (lights follow it).
func trailer_xform() -> Transform3D:
	var td: Dictionary = VehicleData.VARIANTS[trailer_model]
	var pin: Vector3 = td.pin
	return transform * trailer.transform * Transform3D(Basis(), Vector3(0, -pin.y, -pin.z))


## Lines the trailer up behind the tractor (placed, not driven).
func straighten() -> void:
	if trailer:
		trailer.rotation.y = 0.0
		_reset_trailer()


## Picks up the trailer's axle from where the trailer lies now (after being placed or
## moved to another parent).
func _reset_trailer() -> void:
	var td: Dictionary = VehicleData.VARIANTS[trailer_model]
	var axle: Vector3 = td.axle
	var pin: Vector3 = td.pin
	var t := transform * trailer.transform
	_trailer_axle = t * Vector3(0, 0, axle.z - pin.z)
	var h := transform * _hitch
	_trailer_reach = Vector2(h.x - _trailer_axle.x, h.z - _trailer_axle.z).length()


## Drags the trailer's axle after the fifth wheel (tractrix: the axle heads straight
## for the hitch), and turns the trailer to match.
func _drag_trailer() -> void:
	var h := transform * _hitch
	var d := Vector2(h.x - _trailer_axle.x, h.z - _trailer_axle.z)
	if d.length_squared() < 1e-8:
		return
	d = d.normalized()
	_trailer_axle = Vector3(h.x - d.x * _trailer_reach, _trailer_axle.y, h.z - d.y * _trailer_reach)
	trailer.rotation.y = wrapf(atan2(d.x, d.y) - rotation.y, -PI, PI)


func _ready() -> void:
	# Parked and queued cars are most of the traffic; only moving ones need a tick.
	set_process(not path.is_empty())


func drive(points: PackedVector3Array, on_arrive := Callable(), start_delay := 0.0) -> void:
	path = points
	_on_arrive = on_arrive
	delay = start_delay
	if trailer:
		_reset_trailer()
	set_process(not path.is_empty())


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		return
	var step := speed * delta
	while step > 0.0 and not path.is_empty():
		var target := path[0]
		var to := target - position
		var dist := to.length()
		if dist <= step:
			position = target
			step -= dist
			path.remove_at(0)
			if path.is_empty():
				set_process(false)  # before the callback, which may drive() again
				var cb := _on_arrive
				_on_arrive = Callable()
				if cb.is_valid():
					cb.call(self)
				return
		else:
			var dir := to / dist
			position += dir * step
			step = 0.0
			if dir.x * dir.x + dir.z * dir.z > 0.0001:
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 12.0))
	if trailer:
		_drag_trailer()
