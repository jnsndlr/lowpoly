class_name Scenes
## Scene paths and switching between the menu, the main map and the sandbox.

const MENU := "res://scenes/menu.tscn"
const MAIN_MAP := "res://scenes/main_map.tscn"
const SANDBOX := "res://scenes/sandbox.tscn"


static func go(tree: SceneTree, path: String) -> void:
	Engine.time_scale = 1.0
	tree.change_scene_to_file(path)
