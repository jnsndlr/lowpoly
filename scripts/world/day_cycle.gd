class_name DayCycle
extends Node
## Time-of-day lighting: moves the sun (or moon) across the sky and blends sky, fog,
## ambient, haze, glow and exposure between night, twilight, sunset, golden-hour and
## daytime palettes.
##
## Follows the simulation clock by default; set_hour() pins a fixed time instead and
## follow_clock() hands control back to the clock.

const SUNRISE := 5.5
const SUNSET := 20.5
const MAX_ELEVATION := 62.0
const NOON_YAW := -35.0

# Palettes keyed by sun elevation in degrees. Night applies below the first key,
# day above the last; in between they blend. "haze" is volumetric fog density,
# "sun_glow" the size of the sun's halo in the sky (degrees).
const KEYS := [
	{"elev": -10.0, # night (moonlight)
		"light": Color(0.52, 0.64, 1.0), "energy": 0.26,
		"top": Color(0.012, 0.025, 0.07), "horizon": Color(0.05, 0.08, 0.16),
		"ambient": Color(0.2, 0.26, 0.44), "ambient_energy": 0.45,
		"fog": Color(0.05, 0.08, 0.14), "exposure": 1.0,
		"haze": 0.00006, "glow": 0.35, "saturation": 1.0, "sun_glow": 20.0},
	{"elev": 0.0, # twilight: sun just gone, sky still burning
		"light": Color(1.0, 0.36, 0.2), "energy": 0.0,
		"top": Color(0.12, 0.13, 0.34), "horizon": Color(1.0, 0.42, 0.26),
		"ambient": Color(0.4, 0.4, 0.66), "ambient_energy": 0.5,
		"fog": Color(0.7, 0.38, 0.4), "exposure": 1.05,
		"haze": 0.00012, "glow": 0.6, "saturation": 1.25, "sun_glow": 70.0},
	{"elev": 4.0, # sunset: low, deep orange, long shadows
		"light": Color(1.0, 0.46, 0.2), "energy": 1.9,
		"top": Color(0.2, 0.24, 0.52), "horizon": Color(1.0, 0.5, 0.26),
		"ambient": Color(0.42, 0.5, 0.75), "ambient_energy": 0.55,
		"fog": Color(0.98, 0.56, 0.38), "exposure": 1.05,
		"haze": 0.00014, "glow": 0.65, "saturation": 1.3, "sun_glow": 60.0},
	{"elev": 14.0, # golden hour
		"light": Color(1.0, 0.7, 0.42), "energy": 1.6,
		"top": Color(0.3, 0.44, 0.72), "horizon": Color(0.98, 0.74, 0.54),
		"ambient": Color(0.52, 0.6, 0.8), "ambient_energy": 0.58,
		"fog": Color(0.92, 0.76, 0.64), "exposure": 1.0,
		"haze": 0.00009, "glow": 0.4, "saturation": 1.18, "sun_glow": 40.0},
	{"elev": 30.0, # day
		"light": Color(1.0, 0.95, 0.86), "energy": 1.3,
		"top": Color(0.36, 0.56, 0.8), "horizon": Color(0.74, 0.83, 0.9),
		"ambient": Color(0.62, 0.72, 0.86), "ambient_energy": 0.6,
		"fog": Color(0.74, 0.82, 0.88), "exposure": 1.0,
		"haze": 0.00004, "glow": 0.25, "saturation": 1.12, "sun_glow": 30.0},
]

var sim: Simulation
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var water_mat: ShaderMaterial

var override_hour := -1.0
var _applied := -100.0


func set_hour(h: float) -> void:
	override_hour = fposmod(h, 24.0)


func follow_clock() -> void:
	override_hour = -1.0


func is_following_clock() -> bool:
	return override_hour < 0.0


func hour() -> float:
	return sim.hour() if override_hour < 0.0 else override_hour


func _process(_delta: float) -> void:
	var h := hour()
	# Re-applying the sky forces a radiance update, so skip sub-minute changes.
	if absf(h - _applied) > 0.02:
		apply(h)


func apply(h: float) -> void:
	_applied = h
	var day_t := (h - SUNRISE) / (SUNSET - SUNRISE)
	var elev := sin(day_t * PI) * MAX_ELEVATION
	if day_t <= 0.0 or day_t >= 1.0:
		# Sink below the horizon over ~1.5 h of dusk / dawn.
		var from_horizon := minf(fposmod(h - SUNSET, 24.0), fposmod(SUNRISE - h, 24.0))
		elev = -12.0 * clampf(from_horizon / 1.5, 0.0, 1.0)
	var p := _palette(elev)

	# Above the horizon the light is the sun sweeping east to west; below it, a moon
	# riding high opposite. Energy is zero at the horizon so the swap never pops.
	if elev > 0.0:
		var yaw := NOON_YAW + (day_t - 0.5) * 190.0
		sun.rotation_degrees = Vector3(-maxf(elev, 9.0), yaw, 0.0)
	else:
		var night_t := fposmod(h - SUNSET, 24.0) / (24.0 - SUNSET + SUNRISE)
		sun.rotation_degrees = Vector3(-(20.0 + sin(night_t * PI) * 35.0), NOON_YAW + 180.0 + (night_t - 0.5) * 120.0, 0.0)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.global_transform.basis.z)
	sun.light_color = p.light
	sun.light_energy = p.energy
	sun.shadow_enabled = p.energy > 0.02

	sky_mat.sky_top_color = p.top
	sky_mat.sky_horizon_color = p.horizon
	sky_mat.ground_horizon_color = p.horizon
	sky_mat.ground_bottom_color = p.top.lerp(Color(0.05, 0.16, 0.24), 0.6)
	env.ambient_light_color = p.ambient
	env.ambient_light_energy = p.ambient_energy
	env.fog_light_color = p.fog
	env.tonemap_exposure = p.exposure
	env.volumetric_fog_density = p.haze
	env.volumetric_fog_albedo = p.fog.lerp(Color.WHITE, 0.7)
	env.glow_intensity = p.glow
	env.adjustment_saturation = p.saturation
	sky_mat.sun_angle_max = p.sun_glow
	if water_mat:
		water_mat.set_shader_parameter("daylight", clampf(elev / 20.0, 0.0, 1.0))


func _palette(elev: float) -> Dictionary:
	if elev <= KEYS[0].elev:
		return KEYS[0]
	for i in range(1, KEYS.size()):
		var b: Dictionary = KEYS[i]
		if elev <= b.elev:
			var a: Dictionary = KEYS[i - 1]
			var t := smoothstep(a.elev, b.elev, elev)
			var out := {}
			for k in a:
				out[k] = lerp(a[k], b[k], t)
			return out
	return KEYS[KEYS.size() - 1]
