extends SceneTree
## Generates maps for a range of seeds and reports each ferry route's shape: how
## far it turns in all, how long it is against the dock-to-dock distance, whether
## it loops over itself, and whether it sweeps through another slip.
##   godot --headless --path . --script tools/route_audit.gd -- --from=1 --count=200 [--verbose]

func _initialize() -> void:
	var from := 1
	var count := 100
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			from = int(a.substr(7))
		if a.begins_with("--count="):
			count = int(a.substr(8))
		if a == "--verbose":
			verbose = true
	var n_routes := 0
	var bad := 0
	var maps_bad := 0
	var islands := 0
	var unlinked := 0
	var split := 0
	for seed in range(from, from + count):
		var gen := MapGenerator.new()
		var map := gen.generate(seed)
		var map_bad := false
		for isl in map.islands:
			if isl.inhabited and not isl.is_mainland:
				islands += 1
				if not isl.has_terminal:
					unlinked += 1
		for r in map.routes:
			n_routes += 1
			var info := audit(gen, r)
			var flagged: bool = not gen._route_sensible(r.curve) or info.loops or not info.slips_clear
			if flagged:
				bad += 1
				map_bad = true
			if flagged or verbose:
				print("seed %d route %d (%s-%s): turn %.0f°, len %.0f, chord %.0f, ratio %.2f%s%s" % [seed, r.id,
					map.islands[r.a].name, map.islands[r.b].name, info.turn, r.length, info.chord, r.length / maxf(info.chord, 1.0),
					"  LOOPS" if info.loops else "", "  THROUGH SLIP" if not info.slips_clear else ""])
		if map_bad:
			maps_bad += 1
		if components(map) > 1:
			split += 1
	print("DONE %d maps, %d routes, %d flagged (%d maps); %d of %d islands without a terminal; %d maps with a split network" % [count, n_routes, bad, maps_bad, unlinked, islands, split])
	quit()


static func audit(gen: MapGenerator, r: MapData.Route) -> Dictionary:
	var pts := r.curve.get_baked_points()
	var turn := 0.0
	var prev := Vector2.ZERO
	var flat := PackedVector2Array()
	for i in range(0, pts.size(), 2):
		flat.append(Vector2(pts[i].x, pts[i].z))
	for i in range(1, flat.size()):
		var h := (flat[i] - flat[i - 1]).normalized()
		if prev != Vector2.ZERO:
			turn += absf(prev.angle_to(h))
		prev = h
	var loops := false
	for i in range(0, flat.size() - 1):
		for j in range(i + 4, flat.size() - 1):
			if Geometry2D.segment_intersects_segment(flat[i], flat[i + 1], flat[j], flat[j + 1]) != null:
				loops = true
				break
		if loops:
			break
	return {
		"turn": rad_to_deg(turn),
		"chord": pts[0].distance_to(pts[pts.size() - 1]),
		"loops": loops,
		"slips_clear": gen._clear_of_slips(r.curve, r.id),
	}


## How many separate ferry networks the map has.
static func components(map: MapData) -> int:
	var parent := {}
	for isl in map.islands:
		if isl.has_terminal:
			parent[isl.id] = isl.id
	var find := func(f: Callable, i: int) -> int: return i if parent[i] == i else f.call(f, parent[i])
	for r in map.routes:
		parent[find.call(find, r.a)] = find.call(find, r.b)
	var roots := {}
	for i in parent:
		roots[find.call(find, i)] = true
	return roots.size()
