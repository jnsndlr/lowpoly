extends SceneTree

func _initialize() -> void:
	var demand: Array[float] = [40.0, 10.0, 30.0, 50.0, 20.0]
	var assignments := FerryClass.sizes_by_demand(demand)
	if assignments != [4, 1, 3, 5, 2]:
		push_error("Expected busier routes to receive larger ferries; got %s" % str(assignments))
		quit(1)
		return
	print("Ferry sizes follow route demand.")
	quit(0)
