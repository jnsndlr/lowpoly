class_name CloudLayer
extends Node3D
## Drifting cloud deck (hidden from the minimap). Coverage and drift come from the
## simulation's weather and wind and are published as shader globals, which the
## land and water shaders sample to draw matching cloud shadows.

const ALTITUDE := 170.0 # keep in sync with CLOUD_ALTITUDE in clouds.gdshaderinc
const SIZE := 7000.0
const VISUAL_LAYER := 2
const COVERAGE := {"Sunny": 0.18, "Light Breeze": 0.32, "Partly Cloudy": 0.48, "Overcast": 0.8}
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var visual_mat: ShaderMaterial


func setup(weather: String, wind_dir: String, wind_speed: float) -> void:
	name = "Clouds"
	visual_mat = ShaderMaterial.new()
	visual_mat.shader = load("res://shaders/clouds.gdshader")

	# Wind is named for where it blows from; clouds drift the other way (-Z is north).
	var a := DIRS.find(wind_dir) * TAU / 8.0
	var drift := Vector2(-sin(a), cos(a)) * wind_speed * 0.4
	var cov: float = COVERAGE.get(weather, 0.45)
	RenderingServer.global_shader_parameter_set("cloud_coverage", cov)
	RenderingServer.global_shader_parameter_set("cloud_wind", drift)
	# Overcast skies diffuse the light, so their shadows are broad but soft.
	RenderingServer.global_shader_parameter_set("cloud_shadow_strength", 0.4 if weather == "Overcast" else 0.65)
	if weather == "Overcast":
		visual_mat.set_shader_parameter("opacity", 0.7)

	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var visual := MeshInstance3D.new()
	visual.mesh = plane
	visual.material_override = visual_mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.layers = 1 << (VISUAL_LAYER - 1)
	visual.position.y = ALTITUDE
	add_child(visual)

