shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Folded sea: the surface is one continuous sheet creased like paper or a cut gem.
// Seed points are scattered over the water, and each carries a small cap: the
// plane touching a smooth wind-wave field at the seed, bent down slightly with
// distance from it. The surface is the highest cap at every point. A maximum of
// continuous pieces never tears, so neighbouring facets always meet along a shared
// crease; and since every cap bends the same way, the creases between them are
// straight lines that stop where they meet others: polygons of any number of
// sides. A second, finer set of seeds is only allowed to win near crests, which
// breaks the peaks into clusters of little facets. Each facet is shaded with its
// own seed's plane, so it reads perfectly flat.
//
// Shading follows the drawing:
//   - body colour comes from below: the sea floor seen through the water, tinted by
//     the length of water the light crosses (turquoise over shallow sand, blue over
//     deep water). Each facet bends that view by its own slope, so the floor and
//     its caustics break along the creases like through cut glass;
//   - reflection comes from each facet's angle: it mirrors the sky colour in the
//     direction it faces (pale horizon or blue zenith), by Fresnel, and a facet
//     that faces the sun lights up whole.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

// Wave field the facets follow: wavelength of the longest train (the others are
// fractions of it), height as a fraction of wavelength, how peaked the crests are,
// how much the crest lines bend, and time scale.
uniform float wave_length = 8.0;
uniform float steepness = 0.09;
uniform float crest_sharpness = 1.6;
uniform float crease_bend = 0.25;
uniform float wave_speed = 0.5;
// Facets: average width of the big and the crest facets (m), how strongly a cap
// bends away from its seed (higher = more even, Voronoi-like cells; lower = cells
// follow the waves more), how far up the crest the small facets start (0..1 of the
// wave height), and how hard they are held back elsewhere (m).
uniform float facet_size = 0.9;
uniform float chip_size = 0.35;
uniform float cap_bend = 1.2;
uniform float chip_from = 0.55;
uniform float chip_hold = 0.4;
// How fast the seeds drift downwind (m/s of wave time).
uniform float seed_drift = 0.8;

// Light through the water: absorption per metre (red goes first), in-scatter colour
// and how fast it builds with path length, and how far each facet bends the floor.
uniform vec3 absorption = vec3(0.42, 0.11, 0.045);
uniform vec4 scatter_color : source_color = vec4(0.0, 0.2, 0.46, 1.0);
uniform float scatter_density = 0.12;
uniform float refraction = 0.07;

// Reflection: sky colours (set by DayCycle), Fresnel at normal incidence and its
// falloff power (5 is physical; lower lets the facets show from a high camera), and
// overall strength.
uniform vec4 sky_top_color : source_color = vec4(0.36, 0.56, 0.8, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.74, 0.83, 0.9, 1.0);
uniform float fresnel_f0 = 0.03;
uniform float fresnel_power = 3.0;
uniform float reflection_strength = 0.75;

// Sun: facets whose reflection lands within this (1 - cos) of the sun go white.
uniform vec4 glint_color : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float sun_size = 0.006;
uniform float glint_strength = 0.85;

// Caustics on the floor: cell size (m), line thickness, brightness, fade depth.
uniform float caustic_scale = 1.2;
uniform float caustic_width = 0.07;
uniform float caustic_strength = 0.5;
uniform float caustic_fade_depth = 6.0;

// Shore foam: a solid lip plus broken bands washing in.
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.98, 1.0);
uniform float foam_width = 0.35;

// 0 at night .. 1 in full sun; set by DayCycle.
uniform float daylight = 1.0;
// Half-size of the subdivided plane; swell flattens before its edge to meet the ring.
uniform float swell_extent = 100000.0;
uniform float wave_height = 0.22;

varying vec3 world_pos;

// Wave trains: angle off the wind, wavelength and height (fractions of the first).
// The main pair crosses at about +-35 degrees, so their crests interfere into short
// diamonds; the rest break up the pattern.
const int TRAINS = 4;
const float T_ANGLE[TRAINS] = float[](0.6, -0.62, 0.1, -1.15);
const float T_LENGTH[TRAINS] = float[](1.0, 0.91, 0.63, 0.52);
const float T_AMP[TRAINS] = float[](1.0, 1.0, 0.5, 0.45);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 ga = normalize(hash22(i) * 2.0 - 1.0 + 1e-4);
	vec2 gb = normalize(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0 + 1e-4);
	vec2 gc = normalize(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0 + 1e-4);
	vec2 gd = normalize(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0 + 1e-4);
	float n0 = dot(ga, f);
	float n1 = dot(gb, f - vec2(1.0, 0.0));
	float n2 = dot(gc, f - vec2(0.0, 1.0));
	float n3 = dot(gd, f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

vec2 rotate(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

float aastep(float th, float v) {
	float w = max(fwidth(v), 1e-4) * 0.7;
	return smoothstep(th - w, th + w, v);
}

// Deep-water dispersion: longer waves travel faster.
float travel(float len, float t) {
	return sqrt(9.8 * len / TAU) * t * 0.6;
}

// Smooth wind-wave field: peaked crests, broad troughs (exp-sine profile), crest
// lines bent by a slow warp. Returns (height, dh/dx, dh/dz) in world units, plus
// the height as 0 (trough) .. 1 (highest possible crest) in `rel`.
vec3 wave(vec2 p, vec2 wind, float t, out float rel) {
	vec3 h = vec3(0.0);
	float total = 0.0;
	float s = crest_sharpness;
	for (int i = 0; i < TRAINS; i++) {
		vec2 dir = rotate(wind, T_ANGLE[i]);
		float len = wave_length * T_LENGTH[i];
		float k = TAU / len;
		float a = steepness * len * T_AMP[i];
		vec2 wq = p / (len * 2.7) + float(i) * 5.3;
		float x = k * (dot(p, dir) - travel(len, t)) + TAU * crease_bend * gnoise(wq + t * 0.03) + float(i) * 1.7;
		float e = exp(s * (sin(x) - 1.0));
		h += a * vec3(e, e * s * cos(x) * k * dir);
		total += a;
	}
	rel = h.x / total;
	return h;
}

// Raise `best` to the highest cap from one layer of seeds around p. Seeds sit one
// per cell (jittered) and drift downwind; `hold` lowers a seed's cap unless the
// wave is high there, so a layer can be kept to the crests.
void caps(vec2 p, vec2 wind, float t, float size, float salt, float hold, float bend,
		inout float best, inout vec2 best_g) {
	vec2 drift = wind * seed_drift * t;
	vec2 r = (p - drift) / size;
	vec2 base = floor(r);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = base + vec2(float(i), float(j));
			vec2 s = (cell + 0.1 + 0.8 * hash22(cell + salt)) * size + drift;
			float rel;
			vec3 w = wave(s, wind, t, rel);
			vec2 d = p - s;
			float v = w.x + dot(w.yz, d) - 0.5 * bend * dot(d, d)
					- hold * (1.0 - smoothstep(chip_from, chip_from + 0.25, rel));
			if (v > best) {
				best = v;
				best_g = w.yz;
			}
		}
	}
}

// Slope of the faceted sheet at p (world-space xz gradient). `px` is the world size
// of a pixel: once facets shrink to a few pixels the slope blends to the smooth wave
// field, so distance goes calm instead of sparkling.
vec2 facet_slope(vec2 p, vec2 wind, float t, float px) {
	float rel;
	vec2 smooth_g = wave(p, wind, t, rel).yz;
	float big_vis = smoothstep(2.0, 6.0, facet_size / px);
	if (big_vis <= 0.0) {
		return smooth_g;
	}
	// One bend for both layers keeps every crease straight; it has to beat the
	// crest curvature, or caps far from p would win and the search would miss them.
	float bend = cap_bend / facet_size;
	float best = -1e9;
	vec2 g = smooth_g;
	caps(p, wind, t, facet_size, 0.0, 0.0, bend, best, g);
	if (chip_size / px > 2.0) {
		caps(p, wind, t, chip_size, 37.1, chip_hold, bend, best, g);
	}
	return mix(smooth_g, g, big_vis);
}

// Sharp caustic network on the floor: two drifting, warped noise fields; light
// gathers where they cross (|a - b| small), giving thin bright lines that wander.
float caustics(vec2 p, float t) {
	vec2 q = p / caustic_scale;
	q += 0.35 * vec2(gnoise(q * 0.5 + t * 0.15), gnoise(q * 0.5 + 9.2 - t * 0.12));
	float a = gnoise(q + vec2(t * 0.35, t * 0.12));
	float b = gnoise(q * 1.13 + 5.7 - vec2(t * 0.1, t * 0.3));
	return aastep(1.0 - caustic_width, 1.0 - abs(a - b));
}

float swell(vec2 p, float t) {
	float h = sin(p.x * 0.06 + t * 0.7) * cos(p.y * 0.075 + t * 0.55);
	h += 0.5 * sin((p.x - p.y) * 0.13 + t * 1.2);
	return h;
}

vec3 floor_point(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	float raw = texture(depth_texture, uv).r;
	vec4 vp = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	vp.xyz /= vp.w;
	return (inv_view * vec4(vp.xyz, 1.0)).xyz;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge = max(abs(world_pos.x), abs(world_pos.z));
	VERTEX.y += swell(world_pos.xz, TIME) * wave_height * (1.0 - smoothstep(swell_extent - 80.0, swell_extent - 10.0, edge));
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;
	float dist = length(VERTEX);
	// Orthographic views (the minimap) get flat, calm water.
	float persp = 1.0 - step(0.5, PROJECTION_MATRIX[3][3]);
	vec2 wind = normalize(cloud_wind + vec2(1e-4, 0.0));
	float px = max(length(fwidth(p)), 1e-4);

	vec2 g = facet_slope(p, wind, t, px) * persp;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Body colour: the floor seen through this facet. If the bent sample lands on
	// something in front of the water (a hull, the shore), use the straight one.
	vec3 straight = floor_point(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float depth = max(world_pos.y - straight.y, 0.0);
	vec2 bend = NORMAL.xy * refraction * clamp(depth * 0.5, 0.0, 1.0) / (1.0 + dist * 0.015) * persp;
	vec2 uv = SCREEN_UV + bend;
	vec3 seen = floor_point(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (seen.y > world_pos.y) {
		uv = SCREEN_UV;
		seen = straight;
	}
	vec3 floor_col = textureLod(screen_texture, uv, 0.0).rgb;

	float cloud = cloud_shadow(world_pos, TIME);
	float cloud_lit = clamp(1.0 - cloud * 1.6, 0.0, 1.0);
	float sun_up = smoothstep(0.0, 0.2, sun_direction.y);
	float floor_depth = max(world_pos.y - seen.y, 0.0);
	float caus = caustics(seen.xz, t) * (1.0 - smoothstep(0.0, caustic_fade_depth, floor_depth))
			* smoothstep(0.05, 0.4, floor_depth) * sun_up * daylight * cloud_lit
			* smoothstep(caustic_scale * 0.05, caustic_scale * 0.02, length(fwidth(seen.xz))) * persp;
	floor_col *= 1.0 + caus * caustic_strength;

	float path = min(length(seen - world_pos), 60.0);
	vec3 body = floor_col * exp(-absorption * path)
			+ scatter_color.rgb * (1.0 - exp(-scatter_density * path)) * mix(0.15, 1.0, daylight);

	// Reflection: the sky in the direction this facet mirrors the view, by Fresnel.
	vec3 view_ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 r = reflect(view_ray, n_world);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, sqrt(clamp(r.y, 0.0, 1.0)));
	float nv = clamp(dot(n_world, -view_ray), 0.0, 1.0);
	float fresnel = (fresnel_f0 + (1.0 - fresnel_f0) * pow(1.0 - nv, fresnel_power)) * reflection_strength;
	fresnel *= mix(1.0, 0.6, cloud) * persp;
	vec3 water = mix(body, sky, clamp(fresnel, 0.0, 1.0));

	// Sun: a facet whose reflection lands on the sun lights up whole.
	float sun = step(1.0 - sun_size, dot(r, normalize(sun_direction))) * persp * cloud_lit * sun_up;
	water = mix(water, glint_color.rgb * mix(0.4, 1.0, daylight), sun * glint_strength);

	// Shore foam: solid lip plus broken bands washing in, both hard-edged.
	float breakup = gnoise(p * 0.9 + vec2(t * 0.8, 0.0)) * 0.5 + 0.5;
	float lip = 1.0 - aastep(foam_width * (0.5 + breakup), depth);
	float band_fade = 1.0 - smoothstep(0.0, foam_width * 5.0, depth);
	float bands = aastep(0.7, fract(depth * 0.9 - t * 0.7 + breakup * 0.6)) * band_fade * step(0.55, breakup);
	float foam = max(lip, bands * 0.85) * persp;

	EMISSION = water * (1.0 - foam);
	ALBEDO = foam_color.rgb * foam;
	// Reflection is drawn above, so the engine's own is off (except on the foam).
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = 1.0;
}

void light() {
	vec3 lit = ATTENUATION * LIGHT_COLOR;
	// Only foam has albedo, so this only lights the foam.
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * lit / PI;
}
