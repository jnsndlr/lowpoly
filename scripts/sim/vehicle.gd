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
## Radius (game units) the corners of a driven path are rounded to; long rigs swing
## wider. Each corner gives up at most half of either leg, so tight doglegs stay tight.
const TURN_RADIUS := 6.0
## Bumper-to-bumper gap (game units) a vehicle keeps behind its leader, and how far
## to the side of its own line the leader's tail can be and still be in its way.
const FOLLOW_GAP := 2.0
const FOLLOW_WIDTH := 2.4
## Held up this long (a knot of traffic waiting on itself), it edges on regardless
## for a second.
const MAX_HOLD := 4.0
## Any other vehicle under way within this much of its heading (cos) it also keeps
## behind: traffic on the same road, whoever sent it.
const SAME_WAY := 0.7

## Every vehicle under way (each looks for one ahead of it among these).
static var _moving: Array[Vehicle] = []

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
## The vehicle it follows (the one sent off just before it, or the one ahead in its
## queue): while that is on the move it holds back behind its tail.
var leader: Vehicle
var _g_front := Vector3.ZERO   # global bumper, tail and heading as of its last move
var _g_tail := Vector3.ZERO
var _g_fwd := Vector3.FORWARD
var _held := 0.0               # seconds held up behind traffic
var _creep := 0.0              # seconds left edging on regardless


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
	_set_moving(not path.is_empty())


func drive(points: PackedVector3Array, on_arrive := Callable(), start_delay := 0.0) -> void:
	path = _round_corners(points)
	_on_arrive = on_arrive
	delay = start_delay
	if trailer:
		_reset_trailer()
	_set_moving(not path.is_empty())


## The global point at the front of the bumper.
func _front() -> Vector3:
	var g := global_transform
	return g * Vector3(0.0, 0.0, (center_offset + length * 0.5) / scale.z)


## The global point at the tail (the trailer's, for a rig).
func _tail() -> Vector3:
	var p := get_parent() as Node3D
	var t := p.global_transform if p else Transform3D()
	if trailer:
		var td: Dictionary = VehicleData.VARIANTS[trailer_model]
		return t * trailer_xform() * Vector3(0.0, 0.0, -td.size.z * 0.5)
	return t * transform * Vector3(0.0, 0.0, (center_offset - length * 0.5) / scale.z)


## Caches where its bumper, tail and heading lie (globally) for others to follow.
func _cache_ends() -> void:
	_g_front = _front()
	_g_tail = _tail()
	var f := global_transform.basis.z
	f.y = 0.0
	_g_fwd = f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD


## How far its bumper can go before closing within FOLLOW_GAP of `o`'s tail (INF when
## `o` is off its line or not ahead of it). Which is ahead goes by their middles, so of
## two that overlap (spawned together, say) the one behind waits.
func _room_to(o: Vehicle) -> float:
	var right := _g_fwd.cross(Vector3.UP)
	var rel := o._g_tail - _g_front
	var mid := (o._g_front + o._g_tail - _g_front - _g_tail) * 0.5
	if minf(absf(rel.dot(right)), absf(mid.dot(right))) > FOLLOW_WIDTH:
		return INF
	# Ahead of it, and (side by side at a merge, each might look ahead of the other)
	# not also behind it as `o` sees it, or else the older one goes first.
	if mid.dot(_g_fwd) <= 0.0:
		return INF
	if mid.dot(o._g_fwd) <= 0.0 and o.get_instance_id() > get_instance_id():
		return INF
	return maxf(0.0, rel.dot(_g_fwd) - FOLLOW_GAP)


## How far it can go before closing on the vehicle in front: its leader (whichever
## way that is heading) or anything else under way heading its way.
func _room_ahead() -> float:
	var room := INF
	if leader != null:
		if is_instance_valid(leader) and leader.is_processing() and leader.is_inside_tree():
			room = _room_to(leader)
		else:
			leader = null
	var reach := room if room < INF else 60.0
	for o in _moving:
		if o == self or o == leader or o._g_fwd.dot(_g_fwd) < SAME_WAY:
			continue
		var d := o._g_tail - _g_front
		if d.x * d.x + d.z * d.z > reach * reach + 900.0:
			continue
		room = minf(room, _room_to(o))
	return room


func _set_moving(on: bool) -> void:
	set_process(on)
	_list(on and is_inside_tree())


func _list(on: bool) -> void:
	var i := _moving.find(self)
	if on and i < 0:
		_cache_ends()
		_moving.append(self)
	elif not on and i >= 0:
		_moving.remove_at(i)


# (Reparenting takes it out of the tree and back.)
func _enter_tree() -> void:
	_list(not path.is_empty())


func _exit_tree() -> void:
	_list(false)


## The waypoints with each corner (the start included) eased into a curve, so the
## vehicle steers round it instead of pivoting on the spot. The end point is kept.
func _round_corners(points: PackedVector3Array) -> PackedVector3Array:
	var pts := PackedVector3Array([position])
	for p in points:
		if p.distance_squared_to(pts[pts.size() - 1]) > 1e-6:
			pts.append(p)
	var out := PackedVector3Array()
	var radius := maxf(TURN_RADIUS, length * 0.5)
	for i in range(1, pts.size()):
		var p := pts[i]
		if i == pts.size() - 1:
			out.append(p)
			break
		var a := pts[i - 1] - p
		var b := pts[i + 1] - p
		var la := a.length()
		var lb := b.length()
		a /= la
		b /= lb
		var turn := PI - a.angle_to(b)
		var r := minf(radius, minf(la, lb) * 0.5)
		if turn < 0.05 or r < 0.1:
			out.append(p)
			continue
		# A quadratic Bezier from one leg to the other with the corner as its control.
		var p0 := p + a * r
		var p2 := p + b * r
		var n := maxi(2, ceili(turn / (PI / 16.0)))
		for k in range(n + 1):
			var t := float(k) / n
			out.append(p0.lerp(p, t).lerp(p.lerp(p2, t), t))
	if out.is_empty() and not points.is_empty():
		out.append(points[points.size() - 1])  # (already there: still arrive)
	return out


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		return
	var step := speed * delta
	if _creep > 0.0:
		_creep -= delta
	else:
		var room := _room_ahead()
		_held = _held + delta if room < step * 0.25 else 0.0
		if _held > MAX_HOLD:
			_held = 0.0
			_creep = 1.0
		step = minf(step, room)
	while step > 0.0 and not path.is_empty():
		var target := path[0]
		var to := target - position
		var dist := to.length()
		if dist <= step:
			position = target
			step -= dist
			path.remove_at(0)
			if path.is_empty():
				_set_moving(false)  # before the callback, which may drive() again
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
	_cache_ends()
