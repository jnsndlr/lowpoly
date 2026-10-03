shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

// Posterized sea: a smooth wave height field (two crossing wave trains that form a
// diamond lattice, plus finer chop) whose slope toward the camera is cut into a few
// flat colour bands. Slopes facing the viewer go dark, slopes tilted away go light,
// and shallow water lifts everything up the ramp and toward turquoise. On top sit
// hard-edged layers: squiggly glints on the light slopes, caustics on the shallow
// sea floor, and broken shore foam. Unlit on purpose: lighting would blur the bands.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// Colour ramp, darkest to lightest; the bands sample it at evenly spaced points.
uniform vec4 ramp_0 : source_color = vec4(0.04, 0.2, 0.45, 1.0);
uniform vec4 ramp_1 : source_color = vec4(0.07, 0.35, 0.66, 1.0);
uniform vec4 ramp_2 : source_color = vec4(0.1, 0.52, 0.78, 1.0);
uniform vec4 ramp_3 : source_color = vec4(0.16, 0.68, 0.78, 1.0);
uniform vec4 ramp_4 : source_color = vec4(0.45, 0.86, 0.82, 1.0);
uniform int bands : hint_range(2, 12) = 6;

// The two main wave trains: same wavelength, fanned either side of the wind so
// their crests cross into diamonds.
uniform float main_wavelength = 7.0;
uniform float cross_angle = 0.6;
// Peak slope of each main wave (rise over run).
uniform float main_steepness = 0.18;
// exp-sine sharpness: higher = narrower crests, broader troughs.
uniform float crest_sharpness = 1.4;
uniform float chop_strength = 0.3;
// Slow domain warp so the lattice wobbles instead of running in ruler lines.
uniform float warp_strength = 2.2;
uniform float wave_speed = 0.35;

// How hard slope pushes the shade across the ramp, and a small height term.
uniform float slope_contrast = 2.2;
uniform float height_light = 0.12;
// Shallow water sits further up the ramp (lighter); fades out by deep_depth.
uniform float depth_lift = 0.35;
uniform float deep_depth = 5.0;
// Where flat water sits on the ramp (0..1).
uniform float base_shade = 0.42;

// Shallow water also shifts toward this tint, in a couple of hard steps.
uniform vec4 shallow_tint : source_color = vec4(0.2, 0.78, 0.74, 1.0);
uniform float tint_strength = 0.45;
uniform int depth_steps : hint_range(1, 6) = 3;

// Glints: thin squiggly lines (ridges of fine noise) on the light side of the waves.
// A pale halo tier sits around a white core; they thicken toward the horizon into a
// glare band, and gather along the sun's reflection.
uniform vec4 glint_color : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform vec4 glint_halo_color : source_color = vec4(0.62, 0.9, 0.95, 1.0);
uniform float glint_scale = 0.7;
uniform float glint_width = 0.1;
uniform float glint_halo = 0.1;
// Shade (before posterizing) a slope needs to start catching glints.
uniform float glint_shade = 0.5;
uniform float glint_far_boost = 0.5;
uniform float glint_sun = 0.6;

// Caustics: a moving net of pale lines drawn on the sea floor under shallow water.
uniform vec4 caustic_color : source_color = vec4(0.55, 0.92, 0.86, 1.0);
uniform float caustic_scale = 0.55;
uniform float caustic_width = 0.13;
uniform float caustic_depth = 4.2;
uniform float caustic_speed = 0.5;

// Shore foam: a solid lip plus broken bands washing in.
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.98, 1.0);
uniform float foam_width = 0.45;

// 0 at night .. 1 in full sun; set by DayCycle.
uniform float daylight = 1.0;
// Half-size of the subdivided plane; swell flattens before its edge to meet the ring.
uniform float swell_extent = 100000.0;
uniform float wave_height = 0.22;

varying vec3 world_pos;

vec2 grad(vec2 i) {
	vec3 p3 = fract(vec3(i.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	vec2 g = fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
	return g * inversesqrt(max(dot(g, g), 1e-4));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n0 = dot(grad(i), f);
	float n1 = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n2 = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n3 = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

vec2 rotate(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// One exp-sine wave: peaked crests, broad troughs. Adds its height and gradient.
// Amplitude is set from the wanted peak slope so steepness holds at any length.
// `fade` (0..1) mutes it once it gets too small on screen to resolve.
void add_wave(vec2 p, vec2 dir, float len, float steep, float phase, float t, float fade,
		inout float h, inout vec2 dh) {
	float k = TAU / len;
	// Deep-water dispersion: longer waves travel faster.
	float x = k * (dot(dir, p) - sqrt(9.8 / k) * t) + phase;
	// Each train comes and goes in drifting patches so the lattice never tiles evenly.
	float env = 0.5 + 0.5 * gnoise(p * 0.018 - dir * t * 0.05 + phase * 7.3);
	float amp = steep / (k * crest_sharpness) * fade * mix(0.35, 1.5, env);
	float e = exp(crest_sharpness * (sin(x) - 1.0));
	h += amp * e;
	dh += amp * e * crest_sharpness * cos(x) * k * dir;
}

// Height (roughly -0.5..0.5 of a main amplitude) and its xz gradient.
vec3 waves(vec2 p, vec2 wind, float t, float px) {
	p += warp_strength * vec2(gnoise(p * 0.035 + t * 0.03), gnoise(p * 0.035 + 19.1 - t * 0.03));
	float h = 0.0;
	vec2 dh = vec2(0.0);
	// A wave fades once its wavelength drops under a few pixels.
	float L = main_wavelength;
	add_wave(p, rotate(wind, cross_angle), L, main_steepness, 0.0, t,
			1.0 - smoothstep(0.05, 0.12, px / L), h, dh);
	add_wave(p, rotate(wind, -cross_angle), L * 1.03, main_steepness, 2.1, t,
			1.0 - smoothstep(0.05, 0.12, px / L), h, dh);
	const float CHOP_ANGLE[3] = float[](1.25, -1.05, 0.15);
	const float CHOP_LEN[3] = float[](0.47, 0.36, 0.27);
	for (int i = 0; i < 3; i++) {
		float l = L * CHOP_LEN[i];
		add_wave(p, rotate(wind, CHOP_ANGLE[i]), l, main_steepness * chop_strength,
				float(i) * 1.7 + 0.5, t, 1.0 - smoothstep(0.05, 0.12, px / l), h, dh);
	}
	float a = main_steepness / (TAU / L * crest_sharpness);
	return vec3(h / max(a, 1e-4) - 0.5, dh);
}

float swell(vec2 p, float t) {
	float h = sin(p.x * 0.06 + t * 0.7) * cos(p.y * 0.075 + t * 0.55);
	h += 0.5 * sin((p.x - p.y) * 0.13 + t * 1.2);
	return h;
}

// Hard step at `edge`, anti-aliased over about a pixel.
float aa_step(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(edge - w * 0.5, edge + w * 0.5, x);
}

// Ridged noise: 1 along the zero lines of gradient noise, falling off either side.
// Thresholded it gives thin, meandering lines.
float ridge(vec2 p) {
	return 1.0 - abs(gnoise(p));
}

vec3 ramp(float v) {
	v = clamp(v, 0.0, 1.0) * 4.0;
	vec3 c = mix(ramp_0.rgb, ramp_1.rgb, clamp(v, 0.0, 1.0));
	c = mix(c, ramp_2.rgb, clamp(v - 1.0, 0.0, 1.0));
	c = mix(c, ramp_3.rgb, clamp(v - 2.0, 0.0, 1.0));
	return mix(c, ramp_4.rgb, clamp(v - 3.0, 0.0, 1.0));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge = max(abs(world_pos.x), abs(world_pos.z));
	VERTEX.y += swell(world_pos.xz, TIME) * wave_height * (1.0 - smoothstep(swell_extent - 80.0, swell_extent - 10.0, edge));
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;
	// Orthographic views (the minimap) get flat, calm water.
	float ortho = step(0.5, PROJECTION_MATRIX[3][3]);
	// World size of one pixel here, for fading waves that can't be resolved.
	float px = length(fwidth(p));

	float persp = 1.0 - ortho;
	vec2 wind = normalize(cloud_wind + vec2(1e-4, 0.0));
	vec3 w = waves(p, wind, t, px) * persp;

	// Slope rising away from the camera faces it (reflects the dark lower sky);
	// slope falling away tilts up to the bright sky.
	vec2 view_dir = normalize(p - CAMERA_POSITION_WORLD.xz + vec2(1e-4, 0.0));
	float shade = base_shade - slope_contrast * dot(w.yz, view_dir) + height_light * w.x;

	// Water column depth: shallow water reads lighter.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - scene_world.y, 0.0);
	float shallow = 1.0 - smoothstep(0.0, deep_depth, depth);
	float raw_shade = shade;
	shade += depth_lift * shallow;

	// Posterize into flat bands, anti-aliasing each edge over about a pixel.
	float n = float(bands);
	float q = clamp(shade, 0.0, 0.9999) * n;
	float fw = max(fwidth(q), 1e-4);
	float b = floor(q) + smoothstep(1.0 - fw, 1.0, fract(q));
	vec3 col = ramp(min(b, n - 1.0) / (n - 1.0));

	// Turquoise shallows, stepped the same way so they stay flat.
	float ds = float(depth_steps);
	float dq = shallow * ds;
	float dstep = (floor(dq) + smoothstep(1.0 - max(fwidth(dq), 1e-4), 1.0, fract(dq))) / ds;
	col = mix(col, shallow_tint.rgb, dstep * tint_strength);

	// Caustics on the sea floor under shallow water. Sampled at the floor point so
	// they sit below the surface with real parallax, and wobbled by the waves above.
	float floor_px = length(fwidth(scene_world.xz));
	float ct = TIME * caustic_speed;
	vec2 cp = scene_world.xz * caustic_scale + w.yz * 1.5;
	float c = min(ridge(cp + vec2(ct, -ct * 0.6)), ridge(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * cp * 1.3 - vec2(ct * 0.7, ct)));
	float cmask = (1.0 - smoothstep(caustic_depth * 0.5, caustic_depth, depth)) * step(0.02, depth)
			* (1.0 - smoothstep(0.08, 0.25, floor_px * caustic_scale)) * persp;
	col = mix(col, caustic_color.rgb, aa_step(1.0 - caustic_width, c) * cmask);

	// Glints: ridges of fine noise, kept to slopes tilted toward the sky. The width
	// grows with distance (glare band) and along the sun's reflection.
	float dist = length(VERTEX);
	vec3 n3 = normalize(vec3(-w.y, 1.0, -w.z));
	vec3 view_ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	float sun_hit = pow(clamp(dot(reflect(view_ray, n3), sun_direction), 0.0, 1.0), 24.0);
	vec2 gp = p * glint_scale + w.yz * 2.0 + wind * t * 0.6;
	float g = ridge(gp) * 0.6 + ridge(gp * 2.3 + 11.0) * 0.4;
	float slope_ok = smoothstep(glint_shade, glint_shade + 0.15, raw_shade);
	float widen = 1.0 + glint_far_boost * smoothstep(60.0, 400.0, dist) + glint_sun * sun_hit * 3.0;
	float gfade = (1.0 - smoothstep(0.15, 0.4, px * glint_scale * 2.3)) * persp;
	float gw = glint_width * widen * (slope_ok + sun_hit * 0.8);
	float halo = aa_step(1.0 - gw - glint_halo * gw * 6.0, g) * step(1e-3, gw);
	float core = aa_step(1.0 - gw, g) * step(1e-3, gw);

	// Shore foam: solid lip plus broken bands washing in, both hard-edged.
	float breakup = gnoise(p * 0.9 + vec2(t * 0.8, 0.0)) * 0.5 + 0.5;
	float lip = 1.0 - aa_step(foam_width * (0.5 + breakup), depth);
	float band_fade = 1.0 - smoothstep(0.0, foam_width * 5.0, depth);
	float bands_f = aa_step(0.65, fract(depth * 0.9 - t * 0.7 + breakup * 0.6)) * band_fade
			* aa_step(0.55, breakup);
	float foam = max(lip, bands_f * 0.85);

	float cloud = cloud_shadow(world_pos, TIME);
	float glint_vis = gfade * (1.0 - foam) * clamp(1.0 - cloud * 1.6, 0.0, 1.0);
	col = mix(col, glint_halo_color.rgb, halo * glint_vis);
	col = mix(col, glint_color.rgb, core * glint_vis);
	col = mix(col, foam_color.rgb, foam);

	col *= 1.0 - cloud * 0.6;
	ALBEDO = col * mix(0.3, 1.0, daylight);
	// Kept (opaque) so the material renders after the depth prepass it samples.
	ALPHA = 1.0;
}
