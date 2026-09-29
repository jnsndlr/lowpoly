class_name MeshBuilder
extends RefCounted
## Accumulates flat-shaded, vertex-coloured triangles and bakes them into an ArrayMesh.
## All helpers take local coordinates, which are transformed by `xform`.

var xform := Transform3D.IDENTITY
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()


## Adds a triangle. `outward` (local space) picks which side is the front face.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, outward := Vector3.ZERO) -> void:
	tri3(a, b, c, col, col, col, outward)


func tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward := Vector3.ZERO) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if outward != Vector3.ZERO and n.dot(xform.basis * outward) < 0.0:
		n = -n
		var tb := b
		b = c
		c = tb
		var tcol := cb
		cb = cc
		cc = tcol
	# Godot treats clockwise winding as front-facing: emit in reverse of the right-hand order.
	verts.append(a)
	verts.append(c)
	verts.append(b)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(ca)
	colors.append(cc)
	colors.append(cb)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward := Vector3.ZERO) -> void:
	tri(a, b, c, col, outward)
	tri(a, c, d, col, outward)


func box(center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for i in 8:
		c.append(center + Vector3(
			h.x if i & 1 else -h.x,
			h.y if i & 2 else -h.y,
			h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		quad(a, b, cc, d, col, (a + b + cc + d) * 0.25 - center)


## Frustum / cone (r1 = 0) standing on `base`, with `sides` facets.
func cylinder(base: Vector3, r0: float, r1: float, height: float, sides: int, col: Color, top_col := Color(-1, 0, 0), angle := 0.0) -> void:
	var cap_col := col if top_col.r < 0.0 else top_col
	var top := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := angle + TAU * i / sides
		var a1 := angle + TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var mid := (d0 + d1).normalized()
		var p0 := base + d0 * r0
		var p1 := base + d1 * r0
		if r1 > 0.001:
			var q0 := top + d0 * r1
			var q1 := top + d1 * r1
			quad(p0, p1, q1, q0, col, mid)
			tri(top, q0, q1, cap_col, Vector3.UP)
		else:
			tri(p0, p1, top, col, mid + Vector3.UP * 0.1)


## Extrudes a convex outline (x, z pairs) between y0 and y1. `bottom_scale` tapers the base.
func extrude(outline: PackedVector2Array, y0: float, y1: float, col: Color, top_col := Color(-1, 0, 0), bottom_scale := 1.0) -> void:
	var cap_col := col if top_col.r < 0.0 else top_col
	var centroid := Vector2.ZERO
	for p in outline:
		centroid += p
	centroid /= outline.size()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var ab := centroid + (a - centroid) * bottom_scale
		var bb := centroid + (b - centroid) * bottom_scale
		var mid := (a + b) * 0.5 - centroid
		quad(Vector3(ab.x, y0, ab.y), Vector3(bb.x, y0, bb.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), col, Vector3(mid.x, 0, mid.y))
		if cap_col.a > 0.0:
			tri(Vector3(centroid.x, y1, centroid.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), cap_col, Vector3.UP)


## A flat strip following `points`, with shallow skirts so it never looks like it floats.
func ribbon(points: PackedVector3Array, width: float, col: Color, skirt := 0.5) -> void:
	var side_col := col.darkened(0.25)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var d := b - a
		d.y = 0.0
		if d.length_squared() < 0.0001:
			continue
		var lat := d.normalized().cross(Vector3.UP) * width * 0.5
		var down := Vector3(0, -skirt, 0)
		quad(a - lat, a + lat, b + lat, b - lat, col, Vector3.UP)
		quad(a + lat, b + lat, b + lat + down, a + lat + down, side_col, lat)
		quad(a - lat, b - lat, b - lat + down, a - lat + down, side_col, -lat)


func is_empty() -> bool:
	return verts.is_empty()


func commit(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material if material else Models.vc_material())
	return mesh
