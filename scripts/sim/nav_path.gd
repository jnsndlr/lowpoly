class_name NavPath
extends RefCounted
## A polyline on the water plane (x, z) walked by arc length.

var pts := PackedVector2Array()
var cum := PackedFloat32Array()   # distance from the start to each point
var length := 0.0


func _init(points: PackedVector2Array) -> void:
	pts = points
	cum.resize(pts.size())
	var total := 0.0
	for i in pts.size():
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		cum[i] = total
	length = total


func _segment(s: float) -> int:
	var lo := 0
	var hi := pts.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


func sample(s: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	s = clampf(s, 0.0, length)
	var i := _segment(s)
	var seg := cum[i + 1] - cum[i]
	if seg < 1e-6:
		return pts[i]
	return pts[i].lerp(pts[i + 1], (s - cum[i]) / seg)


## Direction of travel at s, averaged over `span` either side so corners read smoothly.
func tangent(s: float, span := 4.5) -> Vector2:
	var d := sample(s + span) - sample(s - span)
	if d.length_squared() < 1e-8:
		if pts.size() >= 2:
			return (pts[pts.size() - 1] - pts[0]).normalized()
		return Vector2.DOWN
	return d.normalized()
