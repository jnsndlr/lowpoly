class_name WakeTrail
extends RefCounted
## A vessel's wake trail: a breadcrumb is dropped at the stern every `spacing`
## metres (or sooner once the heading has swung TURN, so bends stay smooth) and
## kept for `life` seconds. WakeField hands the trail to the water shader.

const TURN := 0.07

var half_length := 15.0
var spacing := 8.0
var life := 24.0
var max_crumbs := 46
var odometer := 0.0
var heading := Vector3.FORWARD
var speed_frac := 0.0   # how hard it is churning now, as a fraction of cruise

var _clock := 0.0
var _crumbs: Array[Vector4] = []   # (x, z, odometer, time dropped), newest first
var _crumb_speed: Array[float] = []
var _crumb_heading := Vector3.FORWARD
var _stern := Vector3.INF


func _init(half_len: float, gap: float, secs: float, crumbs: int) -> void:
	half_length = half_len
	spacing = gap
	life = secs
	max_crumbs = crumbs


## Advances the trail. `dir` is the way the bow points (flat, unit length, or zero
## to keep the last one), `travel` how far it moved and `frac` how hard it is
## churning. Crumbs are only dropped while `dropping`.
## While dropping, distance along the trail is measured at the stern: a boat
## coming about swings its stern across the water much further than its centre
## moves, and the trail has to keep up with it there. Otherwise the stretch from
## the last crumb to the stern would sweep round with the hull, dragging the
## freshest foam with it.
func update(delta: float, pos: Vector3, dir: Vector3, travel: float, frac: float, dropping: bool) -> void:
	_clock += delta
	if dir.length_squared() > 1e-8:
		heading = dir
	speed_frac = frac
	var stern_now := pos - heading * half_length
	var swept := 0.0 if _stern == Vector3.INF else Vector2(stern_now.x - _stern.x, stern_now.z - _stern.z).length()
	_stern = stern_now
	# (A double-ended ferry's stern jumps a hull length when it reverses.)
	odometer += maxf(travel, swept) if dropping and swept < half_length else travel
	var gap := INF if _crumbs.is_empty() else odometer - _crumbs[0].z
	var turned := heading.angle_to(_crumb_heading) >= TURN and gap >= minf(1.5, spacing * 0.5)
	if dropping and (gap >= spacing or turned):
		_crumb_heading = heading
		_crumbs.push_front(Vector4(stern_now.x, stern_now.z, odometer, _clock))
		_crumb_speed.push_front(frac)
	while not _crumbs.is_empty() and _clock - _crumbs.back().w > life:
		_crumbs.pop_back()
		_crumb_speed.pop_back()
	# Tight turns drop crumbs quickly. Rather than cutting off the oldest while
	# its foam is still showing (which loses a whole stretch at once), thin out
	# whichever crumb least changes the trail's shape.
	while _crumbs.size() > max_crumbs:
		_thin_crumbs()


## Starts a fresh trail.
func clear() -> void:
	odometer = 0.0
	_crumbs.clear()
	_crumb_speed.clear()


func is_empty() -> bool:
	return _crumbs.is_empty()


## Drops the interior crumb whose removal moves the trail least (the smallest
## triangle it makes with its neighbours).
func _thin_crumbs() -> void:
	var best := 1
	var best_area := INF
	for i in range(1, _crumbs.size() - 1):
		var a := _crumbs[i - 1]
		var b := _crumbs[i]
		var c := _crumbs[i + 1]
		var area := absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
		if area < best_area:
			best_area = area
			best = i
	_crumbs.remove_at(best)
	_crumb_speed.remove_at(best)


## Appends the trail to `pts` as (x, z, distance along, age) from bow to stern
## and back along the breadcrumbs, with speed fractions in `spd`, writing at most
## `room` points. `pos` is the vessel's centre. Returns the number of points
## written (0 when there is no wake).
func pack(pos: Vector3, pts: PackedVector4Array, spd: PackedFloat32Array, at: int, room: int) -> int:
	if _crumbs.is_empty():
		return 0
	var bow := pos + heading * half_length
	var stern := pos - heading * half_length
	pts[at] = Vector4(bow.x, bow.z, odometer + half_length * 2.0, 0.0)
	pts[at + 1] = Vector4(stern.x, stern.z, odometer, 0.0)
	spd[at] = speed_frac
	spd[at + 1] = speed_frac
	var n := 2
	for i in _crumbs.size():
		if n >= room:
			break
		var c := _crumbs[i]
		# The newest crumb can sit right at the stern; skip it to avoid a zero-length segment.
		if odometer - c.z < 1.0:
			continue
		pts[at + n] = Vector4(c.x, c.y, c.z, _clock - c.w)
		spd[at + n] = _crumb_speed[i]
		n += 1
	return n
