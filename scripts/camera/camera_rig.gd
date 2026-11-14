class_name CameraRig
extends Node3D
## RTS-style orbit camera around a point on the water plane.
##   Left-drag / two-finger swipe / WASD: pan      Right- or middle-drag, Q/E: rotate
##   Right-drag vertical, R/F: tilt                Wheel / pinch / Z/X: zoom (toward cursor)
## Touch screens (iPad): one finger pans and taps select; two fingers pan, pinch to zoom
## and twist to rotate; three fingers dragged up/down tilt.
## Uses real time, so it keeps working while the simulation is paused.

signal ground_clicked(screen_pos: Vector2)

const MIN_DIST := 42.0
const MAX_DIST := 4400.0
const MIN_PITCH := 0.06   # ~3.5°: down near the water, looking up the passage
## The camera never goes lower than this above the water or ground.
const MIN_EYE := 7.5
const MAX_PITCH := 1.50   # ~86°

var camera: Camera3D
var terrain: Terrain
var bounds := 780.0
var follow: Node3D = null

var yaw := -0.6
var pitch := 0.95
var distance := 1500.0
var target_yaw := yaw
var target_pitch := pitch
var target_dist := distance
var target_pos := Vector3.ZERO

var _pan_drag := false
var _rot_drag := false
var _press_pos := Vector2.ZERO
var _moved := false
var _last_ticks := 0
var _last_magnify := 0        # ticks (usec) of the latest pinch event
var _follow_pan := Vector2.ZERO   # swipe accumulated while following, before it breaks the follow
var _touches := {}                # finger index -> screen position
## Set once a second finger lands; the emulated mouse stays muted until every finger lifts,
## so a pinch never turns into a one-finger pan or a tap on release.
var _multi_touch := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 1.5
	camera.far = 45000.0 # the mainland's far peaks, seen across the map
	add_child(camera)
	_last_ticks = Time.get_ticks_usec()
	_update_camera()


func snap() -> void:
	position = target_pos
	yaw = target_yaw
	pitch = target_pitch
	distance = target_dist
	_update_camera()


func focus_on(p: Vector3, dist := -1.0) -> void:
	follow = null
	target_pos = Vector3(p.x, 0.0, p.z)
	if dist > 0.0:
		target_dist = clampf(dist, MIN_DIST, MAX_DIST)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	# One-finger touches arrive as emulated mouse events; ignore them mid-gesture.
	if _multi_touch and (event is InputEventMouseButton or event is InputEventMouseMotion):
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			_pan_drag = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(0.87, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 0.87, mb.position)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pan_drag = true
					_moved = false
					_press_pos = mb.position
				else:
					if _pan_drag and not _moved:
						ground_clicked.emit(mb.position)
					_pan_drag = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_rot_drag = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_drag:
			if not _moved and mm.position.distance_to(_press_pos) > 4.0:
				_moved = true
				follow = null
			if _moved:
				_drag_pan(mm.position - mm.relative, mm.position)
		if _rot_drag:
			target_yaw -= mm.relative.x * 0.006
			target_pitch = clampf(target_pitch + mm.relative.y * 0.004, MIN_PITCH, MAX_PITCH)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if follow != null:
			# Trackpad pinches leak small swipe events; only a deliberate swipe away from
			# a pinch stops following.
			if Time.get_ticks_usec() - _last_magnify < 300000:
				_follow_pan = Vector2.ZERO
				return
			_follow_pan += pg.delta
			if _follow_pan.length() < 3.0:
				return
			follow = null
		_follow_pan = Vector2.ZERO
		_pan_screen(pg.delta * 0.02 * distance / 10.0)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_last_magnify = Time.get_ticks_usec()
		_zoom(1.0 / mg.factor, mg.position)


func _touch_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() >= 2:
				_multi_touch = true
				_pan_drag = false
				_follow_pan = Vector2.ZERO
		else:
			_touches.erase(st.index)
			if _touches.is_empty():
				_multi_touch = false
		return
	var sd := event as InputEventScreenDrag
	if not _touches.has(sd.index):
		return
	var before := _touches.duplicate()
	_touches[sd.index] = sd.position
	var n := _touches.size()
	if n < 2:
		return
	var keys := _touches.keys()
	keys.sort()
	if n >= 3:
		# Three-finger vertical drag tilts, like right-drag.
		target_pitch = clampf(target_pitch + sd.relative.y * 0.004 / n, MIN_PITCH, MAX_PITCH)
		return
	var a0: Vector2 = before[keys[0]]
	var b0: Vector2 = before[keys[1]]
	var a1: Vector2 = _touches[keys[0]]
	var b1: Vector2 = _touches[keys[1]]
	var c0 := (a0 + b0) * 0.5
	var c1 := (a1 + b1) * 0.5
	# Pinch: zoom toward the midpoint between the fingers.
	var d0 := a0.distance_to(b0)
	var d1 := a1.distance_to(b1)
	if d0 > 1.0 and d1 > 1.0:
		_zoom(d0 / d1, c1)
	# Twist: the map turns with the fingers.
	var turn := wrapf((b1 - a1).angle() - (b0 - a0).angle(), -PI, PI)
	target_yaw += turn
	# Two-finger swipe pans; while following, only a deliberate swipe breaks the follow.
	if follow != null:
		_follow_pan += c1 - c0
		if _follow_pan.length() < 24.0:
			return
		follow = null
		_follow_pan = Vector2.ZERO
	_drag_pan(c0, c1)


func ground_at(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if d.y > -0.001:
		return null
	return o + d * (-o.y / d.y)


## Marches the view ray against the terrain (water counts as ground at y = 0).
func pick_terrain(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if d.y > -0.001 or terrain == null:
		return ground_at(screen)
	var t_end := (o.y + 3.0) / -d.y
	var steps := 500
	for i in range(1, steps + 1):
		var p := o + d * (t_end * i / steps)
		var h := maxf(terrain.height_at(p.x, p.z), 0.0)
		if p.y <= h:
			return Vector3(p.x, h, p.z)
	return null


func _drag_pan(from: Vector2, to: Vector2) -> void:
	var a: Variant = ground_at(from)
	var b: Variant = ground_at(to)
	if a == null or b == null:
		return
	position += (a as Vector3) - (b as Vector3)
	position = _clamp(position)
	target_pos = position
	_update_camera()


func _pan_screen(delta: Vector2) -> void:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	target_pos = _clamp(target_pos + right * delta.x - fwd * delta.y)


func _zoom(factor: float, screen: Vector2) -> void:
	var old := target_dist
	target_dist = clampf(target_dist * factor, MIN_DIST, MAX_DIST)
	var g: Variant = ground_at(screen)
	if g != null and follow == null:
		var gp: Vector3 = g
		target_pos = _clamp(target_pos + (gp - target_pos) * (1.0 - target_dist / old))


func _clamp(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -bounds, bounds), 0.0, clampf(p.z, -bounds, bounds))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_ticks) / 1e6, 0.1)
	_last_ticks = now

	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if move != Vector2.ZERO:
		follow = null
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		target_pos = _clamp(target_pos + (right * move.x + fwd * move.y) * distance * 0.9 * dt)
	if Input.is_physical_key_pressed(KEY_Q):
		target_yaw += 1.6 * dt
	if Input.is_physical_key_pressed(KEY_E):
		target_yaw -= 1.6 * dt
	if Input.is_physical_key_pressed(KEY_R):
		target_pitch = clampf(target_pitch + 0.9 * dt, MIN_PITCH, MAX_PITCH)
	if Input.is_physical_key_pressed(KEY_F):
		target_pitch = clampf(target_pitch - 0.9 * dt, MIN_PITCH, MAX_PITCH)
	if Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_EQUAL):
		target_dist = clampf(target_dist * (1.0 - 1.5 * dt), MIN_DIST, MAX_DIST)
	if Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_MINUS):
		target_dist = clampf(target_dist * (1.0 + 1.5 * dt), MIN_DIST, MAX_DIST)

	if follow != null and is_instance_valid(follow):
		target_pos = Vector3(follow.global_position.x, 0.0, follow.global_position.z)

	var k := 1.0 - exp(-dt * 10.0)
	position = position.lerp(target_pos, k)
	yaw = lerp_angle(yaw, target_yaw, k)
	pitch = lerpf(pitch, target_pitch, k)
	distance = exp(lerpf(log(distance), log(target_dist), k))
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	var eye := position + b * Vector3(0.0, 0.0, distance)
	# At low pitch and close zoom, sit just above the water (or a hill) instead.
	var ground := maxf(terrain.height_at(eye.x, eye.z), 0.0) if terrain else 0.0
	eye.y = maxf(eye.y, ground + MIN_EYE)
	camera.global_position = eye
	camera.look_at(position, Vector3.UP)
