class_name Vehicle
extends Node3D
## A car or truck that follows a list of waypoints (in its parent's space) and calls
## back when it arrives. Terminals and ferries decide where it goes next.

var path := PackedVector3Array()
var speed := 24.0
var delay := 0.0
var is_truck := false
var lane_v := 0.0          # lateral lane position while queued at a terminal
var lot_arrival := 0.0     # sim minutes when it joined the queue
var _on_arrive := Callable()


func setup(mesh: Mesh, truck: bool) -> void:
	is_truck = truck
	# (Its lights, drawn by NightLights from its transform, scale with it.)
	scale = Vector3.ONE * Models.LEGACY_SCALE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _ready() -> void:
	# Parked and queued cars are most of the traffic; only moving ones need a tick.
	set_process(not path.is_empty())


func drive(points: PackedVector3Array, on_arrive := Callable(), start_delay := 0.0) -> void:
	path = points
	_on_arrive = on_arrive
	delay = start_delay
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
