class_name Backdrop
extends Node3D
## The world past the map: the mainland's shores, foothills and snowy ranges
## (Terrain.outer_height, i.e. Mainland) out to the horizon, and banks of chunky
## cumulus standing over them. Both are painted with their own aerial haze
## (backdrop.gdshader, cumulus.gdshader) so distant layers fade into the sky like a
## landscape painting instead of vanishing into the depth fog.
##
## The land is a ring of rings around the terrain grid: the first ring is the grid's
## own edge vertices (so the two meet without a crack), and each ring further out is
## a little larger, halving its samples twice so far ranges get broad facets.

const LAND_SHADER := "res://shaders/backdrop.gdshader"
const CLOUD_SHADER := "res://shaders/cumulus.gdshader"
const CLOUD_LAYER := 2 # CloudLayer.VISUAL_LAYER: kept off the minimap
const CLOUD_COUNT := {"Sunny": 12, "Light Breeze": 18, "Partly Cloudy": 26, "Overcast": 34}

const SAND := Color(0.8, 0.73, 0.54)
const CLIFF := Color(0.5, 0.43, 0.42)
const CLIFF_LIGHT := Color(0.63, 0.54, 0.49)
const FOREST := Color(0.12, 0.24, 0.15)
const FOREST_LIGHT := Color(0.19, 0.31, 0.17)
const FOREST_DARK := Color(0.1, 0.19, 0.15)
const ALPINE := Color(0.36, 0.4, 0.48)
const ALPINE_LIGHT := Color(0.46, 0.49, 0.56)
const SNOW := Color(0.94, 0.95, 0.98)

## Modelled trees where the mainland touches the map; flat cards (tree_card.gdshader)
## on the far shores, thinning out with distance.
const TREE_BAND := 120.0
const TREE_TILE := 128.0
const CARD_SHADER := "res://shaders/tree_card.gdshader"
const CARD_FAR := 1000.0
const CARD_TILE := 256.0

var terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _trees: Array[Transform3D] = []
var _tree_cols: Array[Color] = []
var _cards: Array[Transform3D] = []
var _card_cols: Array[Color] = []
# Cloud mesh arrays, filled by _puff.
var _cv := PackedVector3Array()
var _cn := PackedVector3Array()
var _cc := PackedColorArray()
var _ci := PackedInt32Array()


func setup(t: Terrain, weather: String) -> void:
	name = "Backdrop"
	terrain = t
	_rng.seed = int(t.mainland.snowline * 1000.0)
	_build_land()
	_build_trees()
	_build_clouds(weather)


# --- Land ---------------------------------------------------------------------------

func _build_land() -> void:
	var hs := terrain.half_size
	var n := terrain.n
	var smax := Mainland.FAR / hs
	var mb := MeshBuilder.new()

	var inner := _edge_ring()
	# 5 m rings for the near shore, then 10 m samples on rings growing ~2% each.
	var d := 8.0
	var level := 1
	while true:
		var s := 1.0 + d / hs
		if s > smax:
			break
		var outer := _ring(s, n >> level)
		_stitch(mb, inner, outer)
		inner = outer
		if d < 140.0:
			d += 5.0
		else:
			level = 2
			d = (s * 1.022 - 1.0) * hs
	var mi := MeshInstance3D.new()
	mi.name = "Mainland"
	mi.mesh = mb.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load(LAND_SHADER)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The terrain grid's boundary vertices, clockwise from the (-x, -z) corner.
func _edge_ring() -> PackedVector3Array:
	var n := terrain.n
	var hs := terrain.half_size
	var pts := PackedVector3Array()
	for k in 4 * n:
		var t := k % n
		var i: int
		var j: int
		match k / n:
			0:
				i = t
				j = 0
			1:
				i = n
				j = t
			2:
				i = n - t
				j = n
			_:
				i = 0
				j = n - t
		pts.append(Vector3(-hs + i * Terrain.CELL, terrain.h_index(i, j), -hs + j * Terrain.CELL))
	return pts


## `m` samples per side of the square `s` times the grid's size, in the same order.
func _ring(s: float, m: int) -> PackedVector3Array:
	var e := terrain.half_size * s
	var pts := PackedVector3Array()
	for k in 4 * m:
		var f := float(k % m) / m * 2.0 - 1.0
		var p: Vector2
		match k / m:
			0:
				p = Vector2(f, -1.0)
			1:
				p = Vector2(1.0, f)
			2:
				p = Vector2(-f, 1.0)
			_:
				p = Vector2(-1.0, -f)
		p *= e
		pts.append(Vector3(p.x, terrain.outer_height(p.x, p.y), p.y))
	return pts


## Joins two rings; the inner one has the same number of samples or twice as many.
func _stitch(mb: MeshBuilder, a: PackedVector3Array, b: PackedVector3Array) -> void:
	var na := a.size()
	var nb := b.size()
	if na == nb:
		for k in na:
			var k1 := (k + 1) % na
			if k % 2 == 0:
				_tri(mb, a[k], a[k1], b[k1])
				_tri(mb, a[k], b[k1], b[k])
			else:
				_tri(mb, a[k], a[k1], b[k])
				_tri(mb, a[k1], b[k1], b[k])
	else:
		for c in nb:
			var f0 := a[2 * c]
			var f1 := a[2 * c + 1]
			var f2 := a[(2 * c + 2) % na]
			var c0 := b[c]
			var c1 := b[(c + 1) % nb]
			_tri(mb, f0, f1, c0)
			_tri(mb, f1, c1, c0)
			_tri(mb, f1, f2, c1)


func _tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3) -> void:
	if a.y < -5.2 and b.y < -5.2 and c.y < -5.2:
		return
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		return
	nrm = nrm.normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var p := (a + b + c) / 3.0
	mb.tri(a, b, c, _color(p, nrm.y), Vector3.UP)
	# Forest on gentle ground near the map gets real trees, as on the islands.
	var out := maxf(absf(p.x), absf(p.z)) - terrain.half_size
	if out < CARD_FAR and p.y > 1.6 and nrm.y > 0.72 and p.y < _treeline(p) - 60.0:
		var area := (b - a).cross(c - a).length() * 0.5
		if out >= TREE_BAND - 10.0:
			_scatter_cards(a, b, c, area / 42.0 * (1.0 - smoothstep(350.0, CARD_FAR, out)))
		var want := area / 9.0 * (1.0 - smoothstep(TREE_BAND - 30.0, TREE_BAND, out))
		while want > 0.0:
			if _rng.randf() < want:
				var u := _rng.randf()
				var v := _rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var at := a + (b - a) * u + (c - a) * v
				var s := _rng.randf_range(0.8, 1.45)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.25), s))
				_trees.append(Transform3D(basis, at - Vector3(0, 0.1, 0)))
				_tree_cols.append(Color(_rng.randf_range(0.75, 0.95), _rng.randf_range(0.8, 0.95), _rng.randf_range(0.8, 0.95)))
			want -= 1.0


## Island colours on the shore, forest on the hills, bare rock above the trees and
## snow on the tops (what faces up, at least; the shader's haze does the rest).
func _color(p: Vector3, ny: float) -> Color:
	var r := _hash(p.x, p.z)
	var h := p.y
	var snow := _snowline(p)
	var treeline := _treeline(p)
	var col: Color
	if h < -0.3:
		col = SAND.darkened(clampf(-h * 0.07, 0.0, 0.45))
	elif h < 1.15 and ny >= 0.72:
		col = SAND
	elif h > snow and ny > 0.42:
		col = SNOW
	elif h > treeline:
		col = ALPINE.lerp(ALPINE_LIGHT, r * 0.5)
	elif ny < 0.72 and h < 25.0:
		col = CLIFF.lerp(CLIFF_LIGHT, r)
	elif ny < 0.72:
		# Steep forest: darker, and bare rock showing through high up.
		col = FOREST_DARK.lerp(ALPINE, smoothstep(treeline - 200.0, treeline, h) * r)
	else:
		col = FOREST.lerp(FOREST_LIGHT, r)
	return col.darkened(r * 0.06)


func _scatter_cards(a: Vector3, b: Vector3, c: Vector3, want: float) -> void:
	while want > 0.0:
		if _rng.randf() < want:
			var u := _rng.randf()
			var v := _rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var h := _rng.randf_range(7.0, 11.0)
			var basis := Basis.from_scale(Vector3(h * _rng.randf_range(0.5, 0.62), h, 1.0))
			_cards.append(Transform3D(basis, a + (b - a) * u + (c - a) * v - Vector3(0, 0.3, 0)))
			var k := _rng.randf_range(0.8, 1.15)
			_card_cols.append(Color(k * _rng.randf_range(0.9, 1.05), k, k * _rng.randf_range(0.9, 1.05)))
		want -= 1.0


## Snowline and treeline wander smoothly along the ranges (no per-facet speckle).
func _snowline(p: Vector3) -> float:
	return terrain.mainland.snowline + sin(p.x * 0.0031 + 1.7) * sin(p.z * 0.0027 + 0.4) * 90.0


func _treeline(p: Vector3) -> float:
	return _snowline(p) - 220.0 + sin(p.x * 0.007 + p.z * 0.005) * 40.0


## Tiled like WorldBuilder's forests so the camera culls what it can't see.
func _build_trees() -> void:
	var tiles := {}
	for i in _trees.size():
		var o := _trees[i].origin
		var key := Vector2i(floori(o.x / TREE_TILE), floori(o.z / TREE_TILE))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	for key: Vector2i in tiles:
		var idx: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Models.pine_tree()
		mm.instance_count = idx.size()
		for j in idx.size():
			mm.set_instance_transform(j, _trees[idx[j]])
			mm.set_instance_color(j, _tree_cols[idx[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# Dense forest hides its own floor; their shadows aren't worth the cascades.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "MainlandPines_%d_%d" % [key.x, key.y]
		add_child(mmi)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load(CARD_SHADER)
	quad.material = mat
	tiles = {}
	for i in _cards.size():
		var o := _cards[i].origin
		var key := Vector2i(floori(o.x / CARD_TILE), floori(o.z / CARD_TILE))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	for key: Vector2i in tiles:
		var idx: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = idx.size()
		for j in idx.size():
			mm.set_instance_transform(j, _cards[idx[j]])
			mm.set_instance_color(j, _card_cols[idx[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The cards turn to face the camera, past the quad's flat bounds.
		mmi.extra_cull_margin = 8.0
		mmi.name = "TreeCards_%d_%d" % [key.x, key.y]
		add_child(mmi)
	print("Backdrop: %d mainland trees, %d tree cards" % [_trees.size(), _cards.size()])


static func _hash(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - floorf(v)


# --- Clouds -------------------------------------------------------------------------

## Banks of cumulus all round the horizon: clusters of squashed, flat-bottomed
## icospheres, big rounded heads in the middle and smaller ones at the ends.
func _build_clouds(weather: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(terrain.mainland.snowline * 1000.0) + 1 # differs per map, independent of the sim
	var ico := _icosphere(2)
	var count: int = CLOUD_COUNT.get(weather, 22)
	for c in count:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(5500.0, 10500.0)
		var centre := Vector2(cos(ang), sin(ang)) * dist
		var along := Vector2(-sin(ang), cos(ang))
		var base := rng.randf_range(1100.0, 1800.0)
		var width := rng.randf_range(900.0, 2600.0)
		var puffs := int(width / 220.0) + rng.randi_range(0, 3)
		var tint := rng.randf()
		for k in puffs:
			var t := rng.randf_range(-1.0, 1.0)
			var big := 1.0 - absf(t) * 0.55
			var rad := rng.randf_range(200.0, 420.0) * big * (width / 1900.0 + 0.5)
			var p := centre + along * t * width * 0.5 + Vector2(cos(ang), sin(ang)) * rng.randf_range(-280.0, 280.0)
			var lift := rad * rng.randf_range(0.2, 0.75) * big
			_puff(ico, Vector3(p.x, base + lift, p.y), Vector3(rad, rad * rng.randf_range(0.7, 0.9), rad), base,
				base + rad * 1.6, tint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _cv
	arrays[Mesh.ARRAY_NORMAL] = _cn
	arrays[Mesh.ARRAY_COLOR] = _cc
	arrays[Mesh.ARRAY_INDEX] = _ci
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load(CLOUD_SHADER)
	mat.set_shader_parameter("grey", 0.35 if weather == "Overcast" else 0.0)
	var mi := MeshInstance3D.new()
	mi.name = "Cumulus"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 << (CLOUD_LAYER - 1)
	add_child(mi)


## One puff, its underside flattened onto the cloud base. Colour: r = height up the
## cloud (0 at the base), g = the cluster's tint.
func _puff(ico: Array, at: Vector3, scale: Vector3, base: float, top: float, tint: float) -> void:
	var first := _cv.size()
	for u: Vector3 in ico[0]:
		var p := at + u * scale
		var nrm := (u / scale).normalized()
		if p.y < base:
			p.y = base
			nrm = nrm.lerp(Vector3.DOWN, 0.7).normalized()
		_cv.append(p)
		_cn.append(nrm)
		_cc.append(Color(clampf((p.y - base) / (top - base), 0.0, 1.0), tint, 0.0))
	for i: int in ico[1]:
		_ci.append(first + i)


## [unit vertices, indices] of an icosphere subdivided `levels` times, wound for Godot.
static func _icosphere(levels: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	# An Array (not packed) so _mid can append to it.
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
		2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for l in levels:
		var mid := {}
		var nf := PackedInt32Array()
		for k in range(0, f.size(), 3):
			var a := f[k]
			var b := f[k + 1]
			var c := f[k + 2]
			var ab := _mid(v, mid, a, b)
			var bc := _mid(v, mid, b, c)
			var ca := _mid(v, mid, c, a)
			nf.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		f = nf
	# The table is counter-clockwise from outside; Godot's front faces are clockwise.
	for k in range(0, f.size(), 3):
		var tmp := f[k + 1]
		f[k + 1] = f[k + 2]
		f[k + 2] = tmp
	return [v, f]


static func _mid(v: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	cache[key] = v.size() - 1
	return v.size() - 1
