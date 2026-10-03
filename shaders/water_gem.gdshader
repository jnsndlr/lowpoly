shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Clear, gem-cut sea. The surface is cut into irregular Voronoi facets: each cell
// is a flat plane, so edges are straight and sharp, but cells vary in size and
// shape and drift and wobble with the wind, so nothing repeats. Each plane takes
// its tilt from a random wave field (wind-stretched, creased gradient noise, no
// periodic trains) sampled at the cell's seed. A second, finer layer of cells adds
// small-scale height variation, splitting the big facets into chips. Each facet:
//   - refracts the sea floor behind it (the screen, offset by its normal) and tints it
//     by the length of water the light crosses, so colour comes from the bottom and
//     its depth: sand in the shallows reads turquoise, deeper or grazing views blue;
//   - reflects the real sky by Fresnel (the engine's indirect specular);
//   - catches small sharp sun flecks from a fine ripple layer near its crests.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

// Facets: average cell width of the big and small layers (world units), how far
// seeds wobble (0..1 of a cell) and how fast, and regional cell-size variation.
uniform float facet_size = 0.9;
uniform float chip_size = 0.35;
uniform float cell_wobble = 0.8;
uniform float cell_speed = 0.6;
uniform float cell_size_var = 0.5;

// Wave field: wavelength of the main swell features, how much longer crests run
// across the wind than along it, slope of the big and small layers, how creased
// (sharp-crested) the noise is (0 = smooth, 1 = fully ridged), and time scale.
uniform float wave_length = 10.0;
uniform float crest_stretch = 2.2;
uniform float wave_steepness = 0.65;
uniform float chip_steepness = 0.3;
uniform float crease = 0.7;
uniform float wave_speed = 0.5;

// Light through the water. Absorption per metre (red goes first), the colour that
// in-scattering adds as the path grows, and how fast it builds.
uniform vec3 absorption = vec3(0.45, 0.13, 0.05);
uniform vec4 scatter_color : source_color = vec4(0.0, 0.15, 0.4, 1.0);
uniform float scatter_density = 0.1;
// Stylised slope shading on the light coming up through the water: faces tilted
// toward the camera darken, faces tilted away brighten. Looking down, Fresnel alone
// barely tells slopes apart, so without this close-up waves read as flat.
uniform float slope_shade = 1.2;
// Screen-space bend of the floor behind each facet.
uniform float refraction = 0.05;

// Surface finish and sun flecks: a fine ripple layer tilts the normal for the sun
// test only, and anything within `fleck_size` of the reflection goes white.
uniform float roughness = 0.04;
// Strength of the sky reflection (0.5 = physical water).
uniform float reflectivity = 0.35;
uniform vec4 fleck_color : source_color = vec4(1.0, 1.0, 0.97, 1.0);
uniform float fleck_size = 0.006;
uniform float fleck_ripple = 0.22;
uniform float fleck_scale = 2.2;

// Shore foam: a solid lip plus broken bands washing in.
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.98, 1.0);
uniform float foam_width = 0.35;

// 0 at night .. 1 in full sun; set by DayCycle.
uniform float daylight = 1.0;
// Half-size of the subdivided plane; swell flattens before its edge to meet the ring.
uniform float swell_extent = 100000.0;
uniform float wave_height = 0.22;

varying vec3 world_pos;

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

// Gradient noise plus its analytic derivative: (value, d/dx, d/dy), roughly -1..1.
vec3 gnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = normalize(hash22(i) * 2.0 - 1.0 + 1e-4);
	vec2 gb = normalize(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0 + 1e-4);
	vec2 gc = normalize(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0 + 1e-4);
	vec2 gd = normalize(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0 + 1e-4);
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float k = va - vb - vc + vd;
	float v = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
	vec2 d = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
			+ du * (u.yx * k + vec2(vb, vc) - va);
	return vec3(v, d) * 1.5;
}

// How far a noise octave of wavelength `len` has travelled downwind by time t
// (deep-water dispersion: longer waves travel faster). Facet cells use the same
// rule, so a cell rides along with the waves it samples instead of letting them
// race through it.
float travel(float len, float t) {
	return sqrt(9.8 * len / TAU) * t * 0.6;
}

// Random wind sea, as a slope (xz gradient). Octaves of gradient noise in a
// wind-aligned frame, stretched so crests run long across the wind, each drifting
// downwind at its own speed (longer = faster) and turned a little so the layers
// slide over each other. Creasing folds each octave about zero (|n|), giving sharp
// crest lines on random curves instead of periodic trains. `oct0`..`oct1` picks the
// octaves, so the big facets take the swell and the chips take the fine chop.
vec2 sea_grad(vec2 p, vec2 wind, float t, int oct0, int oct1, out float crest) {
	vec2 across = vec2(-wind.y, wind.x);
	vec2 g = vec2(0.0);
	crest = 0.0;
	float len = wave_length;
	float amp = 1.0;
	for (int o = 0; o < 5; o++) {
		if (o >= oct0 && o < oct1) {
			float a = 0.35 * float(o) - 0.3;
			vec2 w = rotate(wind, a);
			vec2 c = rotate(across, a);
			// Wind-frame coordinates in cycles; along-wind compressed by the stretch.
			vec2 q = vec2((dot(p, w) - travel(len, t)) / len, dot(p, c) / (len * crest_stretch));
			vec3 n = gnoise_d(q + float(o) * 17.3);
			// Back to world-space slope (chain rule through the frame).
			vec2 dn = (n.y * w / len + n.z * c / (len * crest_stretch)) * len;
			// Fold: smooth noise at crease 0, ridged at 1 (crests where n crosses 0).
			float fold = mix(1.0, -sign(n.x), crease);
			g += amp * fold * dn;
			crest = max(crest, amp * crease * (1.0 - smoothstep(0.0, 0.25, abs(n.x))));
		}
		len *= 0.52;
		amp *= 0.6;
	}
	return g;
}

// Voronoi cell under p (cells of width `size`) whose seeds ride downwind at the
// speed of waves of length `ride_len` and wobble on their own slow orbits. Returns the seed's world position: constant
// across the cell, so whatever is sampled there gives the cell one flat plane.
vec2 cell_seed(vec2 p, float size, float t, vec2 wind, float ride_len, float salt) {
	// Broad warp so some patches get bigger cells than others.
	vec2 wq = p * 0.02 + salt;
	vec2 warp = cell_size_var * 8.0 / size * vec2(gnoise(wq), gnoise(wq + 17.3));
	vec2 drift = wind * travel(ride_len, t);
	vec2 r = (p - drift) / size + warp;
	vec2 base = floor(r);
	vec2 f = r - base;
	float md = 8.0;
	vec2 best = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = base + vec2(float(i), float(j));
			vec2 h = hash22(cell + salt);
			vec2 o = 0.5 + 0.5 * cell_wobble * sin(t * cell_speed * (0.6 + 0.8 * h.yx) + TAU * h);
			vec2 rv = vec2(float(i), float(j)) + o - f;
			float d = dot(rv, rv);
			if (d < md) {
				md = d;
				best = cell + o;
			}
		}
	}
	// Back to world units (the warp is slow, so undoing it at p is close enough).
	return (best - warp) * size + drift;
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

	// World size of one pixel here, for anti-aliasing and fading the waves.
	float px = length(fwidth(p));
	// Big facets carry the swell, chips the fine chop. Each layer samples its octaves
	// at its own cell seed, and its cells travel at the speed of a middle octave of
	// the ones it samples, so the others only slide slowly past it; where cells shrink under a few pixels they sample at the
	// fragment instead, so distant water goes smooth rather than sparkling.
	float big_vis = smoothstep(3.0, 8.0, facet_size / px) * persp;
	float chip_vis = smoothstep(3.0, 8.0, chip_size / px) * persp;
	float crest = 0.0;
	float crest_chip = 0.0;
	vec2 sb = big_vis > 0.0 ? cell_seed(p, facet_size, t, wind, wave_length * 0.52, 0.0) : p;
	vec2 g = wave_steepness * sea_grad(mix(p, sb, big_vis), wind, t, 0, 3, crest);
	if (chip_vis > 0.0) {
		vec2 sc = cell_seed(p, chip_size, t, wind, wave_length * 0.52 * 0.52 * 0.52 * 0.7, 51.7);
		g += chip_steepness * chip_vis * sea_grad(sc, wind, t, 3, 5, crest_chip);
	}
	// Distant water calms down rather than averaging into noise.
	g *= mix(0.35, 1.0, big_vis) * persp;
	crest = max(crest, crest_chip) * chip_vis;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Refracted view of the floor. If the bent sample lands on something in front of
	// the water (a hull, the shore above the waterline), fall back to the straight one.
	vec3 straight = floor_point(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float depth = max(world_pos.y - straight.y, 0.0);
	vec2 bend = NORMAL.xy * refraction * clamp(depth * 0.5, 0.0, 1.0) / (1.0 + dist * 0.02) * persp;
	vec2 uv = SCREEN_UV + bend;
	vec3 seen = floor_point(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (seen.y > world_pos.y) {
		uv = SCREEN_UV;
		seen = straight;
	}
	vec3 floor_col = textureLod(screen_texture, uv, 0.0).rgb;
	// Length of water the light crosses on the way up to the eye.
	float path = min(length(seen - world_pos), 60.0);
	vec3 trans = exp(-absorption * path);
	vec3 water = floor_col * trans + scatter_color.rgb * (1.0 - exp(-scatter_density * path)) * mix(0.15, 1.0, daylight);
	vec2 view_h = normalize(p - CAMERA_POSITION_WORLD.xz + vec2(1e-4, 0.0));
	water *= clamp(1.0 - slope_shade * dot(g, view_h), 0.45, 1.7);

	// Shore foam: solid lip plus broken bands washing in, both hard-edged.
	float breakup = gnoise(p * 0.9 + vec2(t * 0.8, 0.0)) * 0.5 + 0.5;
	float lip = 1.0 - step(foam_width * (0.5 + breakup), depth);
	float band_fade = 1.0 - smoothstep(0.0, foam_width * 5.0, depth);
	float bands = step(0.7, fract(depth * 0.9 - t * 0.7 + breakup * 0.6)) * band_fade * step(0.55, breakup);
	float foam = max(lip, bands * 0.85) * persp;

	float cloud = cloud_shadow(world_pos, TIME);
	// What the surface reflects (sky, by Fresnel) is added by the engine on top of
	// emission, so the transmitted light gives up that share.
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = (0.02 + 0.98 * pow(1.0 - nv, 5.0)) * reflectivity * 2.0;
	EMISSION = water * (1.0 - fresnel) * (1.0 - foam);
	ALBEDO = foam_color.rgb * foam;
	ROUGHNESS = mix(roughness, 1.0, foam);
	SPECULAR = reflectivity * (1.0 - foam);

	// Sun flecks: a fine ripple layer tilts the normal for this test only, so small
	// sharp-edged white flecks gather near the crests along the sun's reflection.
	vec2 fp = p * fleck_scale + wind * t * 1.5;
	vec2 tilt = vec2(gnoise(fp), gnoise(fp * 1.3 + 41.0)) * fleck_ripple * (0.4 + crest);
	vec3 n_fleck = normalize(n_world + vec3(tilt.x, 0.0, tilt.y));
	vec3 view_ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	float r = dot(reflect(view_ray, n_fleck), normalize(sun_direction));
	// Fixed edge width: fwidth(r) spikes where the normal jumps at a crease, which
	// would light every facet edge.
	float fleck = smoothstep(1.0 - fleck_size * 1.15, 1.0 - fleck_size * 0.85, r)
			* persp * (1.0 - foam) * clamp(1.0 - cloud * 1.6, 0.0, 1.0) * smoothstep(0.0, 0.2, sun_direction.y);
	EMISSION = mix(EMISSION, fleck_color.rgb * 1.6 * daylight, fleck);
	ALPHA = 1.0;
}

void light() {
	vec3 lit = ATTENUATION * LIGHT_COLOR;
	// Only foam has albedo, so this only lights the foam.
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * lit / PI;
	// No direct specular: the sun shows up as the flecks drawn in fragment().
}
