extends SceneTree
## Counts the seal and sea lion haul-outs each generated map gets (headless, fast).
##   godot --headless --path . --script tools/haul_out_audit.gd -- --from=1 --count=50 [--verbose]


func _initialize() -> void:
	var from := 1
	var count := 20
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			from = int(a.substr(7))
		elif a.begins_with("--count="):
			count = int(a.substr(8))
		elif a == "--verbose":
			verbose = true
	var totals := [0, 0, 0]
	var spots := [0, 0, 0]
	var none := 0
	for s in range(from, from + count):
		var gen := MapGenerator.new()
		var map := gen.generate(s)
		var k := [0, 0, 0]
		for h in map.haul_outs:
			k[h.kind] += 1
			totals[h.kind] += 1
			spots[h.kind] += h.spots.size()
			if verbose:
				print("  %d %s on %s (near %s) spots %d at %s" % [s, h.kind_name(), map.islands[h.island].name,
					map.islands[h.near].name, h.spots.size(), h.water])
		if k[0] + k[1] == 0:
			none += 1
		print("seed %d: beaches %d rocks %d docks %d" % [s, k[0], k[1], k[2]])
	print("TOTAL beaches %d (%.1f spots) rocks %d (%.1f spots) docks %d (%.1f spots); maps with no beach/rock: %d" % [
		totals[0], spots[0] / maxf(totals[0], 1), totals[1], spots[1] / maxf(totals[1], 1), totals[2],
		spots[2] / maxf(totals[2], 1), none])
	quit()
