shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Clear sea drawn with sharp noise instead of facets. The surface is a smooth,
// wind-stretched, domain-warped noise wave field, but it is never shaded smoothly:
//   - the wave slopes give a continuous tone (faces toward the camera darker, away
//     lighter), which is then posterised into many small steps with crisp edges,
//     like a photo through a posterise filter: nested contours, low contrast;
//   - colour comes from real depth: the sea floor is refracted through the surface
//     and tinted by the length of water the light crosses (Beer absorption plus
//     in-scatter), so shallows read turquoise and deep / grazing views read blue;
//   - the floor carries sharp animated caustic lines that fade with depth;
//   - crests catch small, sparse, crisp glints, denser toward the horizon, plus
//     a sun path; the sky reflection comes from the engine via Fresnel.
// Every hard edge is anti-aliased by its own screen-space derivative, and each wave
// layer fades out once its features shrink under a few pixels, so distance goes
// calm instead of sparkling.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

// Wave field: wavelength of the biggest layer (the others are fractions of it),
// how much longer crests run across the wind than along it, how much the domain
// is warped (curls straight crests into lumpy diamonds), and time scale.
uniform float wave_length = 7.0;
uniform float crest_stretch = 1.8;
uniform float warp = 0.45;
uniform float wave_speed = 0.55;
// Slope used for the reflection / refraction normal (shading stays posterised).
uniform float normal_strength = 0.35;

// Posterised slope tone: how far the brightness swings either way, how many steps
// it is cut into across that range, and how much each layer contributes.
uniform float tone_range = 0.2;
uniform float tone_steps = 7.0;
uniform vec3 tone_layers = vec3(0.5, 0.35, 0.25);
// Colour the darker steps lean toward (deep blue shadows of wave backs).
uniform vec4 patch_tint : source_color = vec4(0.04, 0.2, 0.46, 1.0);

// Light through the water: absorption per metre (red goes first), in-scatter colour
// and how fast it builds with path length. Refraction bends the floor behind.
uniform vec3 absorption = vec3(0.42, 0.11, 0.045);
uniform vec4 scatter_color : source_color = vec4(0.0, 0.2, 0.46, 1.0);
uniform float scatter_density = 0.12;
uniform float refraction = 0.045;

// Caustics: cell size on the floor (m), line thickness (0..1), brightness, and the
// depth over which they fade out.
uniform float caustic_scale = 1.1;
uniform float caustic_width = 0.06;
uniform float caustic_strength = 0.45;
uniform float caustic_fade_depth = 6.0;

// Glints: small crest flecks from a fine two-octave noise (feature size in m,
// threshold near the camera and further out; lower = more), and the sun path.
uniform vec4 glint_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float glint_scale = 0.4;
uniform float glint_near = 1.42;
uniform float glint_far = 1.26;
// How far a glint goes toward glint_color (1 = solid white).
uniform float glint_strength = 0.6;
uniform float sun_size = 0.0015;

// Surface finish and sky reflection (0.5 = physical water).
uniform float roughness = 0.05;
uniform float reflectivity = 0.3;

// Shore foam: a solid lip plus broken bands washing in.
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.98, 1.0);
uniform float foam_width = 0.35;

// 0 at night .. 1 in full sun; set by DayCycle.
uniform float daylight = 1.0;
// Half-size of the subdivided plane; swell flattens before its edge to meet the ring.
uniform float swell_extent = 100000.0;
uniform float wave_height = 0.22;

varying vec3 world_pos;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 grad2(vec2 i) {
	vec2 g = hash22(i) * 2.0 - 1.0;
	return g * inversesqrt(max(dot(g, g), 1e-4));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n0 = dot(grad2(i), f);
	float n1 = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n2 = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n3 = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

// Gradient noise plus its analytic derivative: (value, d/dx, d/dy), roughly -1..1.
vec3 gnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = grad2(i);
	vec2 gb = grad2(i + vec2(1.0, 0.0));
	vec2 gc = grad2(i + vec2(0.0, 1.0));
	vec2 gd = grad2(i + vec2(1.0, 1.0));
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

vec2 rotate(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Hard step with a one-pixel anti-aliased edge.
float aastep(float th, float v) {
	float w = max(fwidth(v), 1e-4) * 0.7;
	return smoothstep(th - w, th + w, v);
}

// Deep-water dispersion: longer waves travel faster.
float travel(float len, float t) {
	return sqrt(9.8 * len / TAU) * t * 0.6;
}

// One wave layer of wavelength `len`, turned `ang` off the wind. Returns
// (value, slope.x, slope.z) with the slope made dimensionless (per wavelength), so
// every layer's slope has the same -1.5..1.5 range whatever its size. The domain
// warp is left out of the derivative: it only bends where the crests run.
vec3 wave_layer(vec2 p, vec2 wind, float len, float ang, float t, float salt) {
	vec2 w = rotate(wind, ang);
	vec2 c = vec2(-w.y, w.x);
	vec2 q = vec2((dot(p, w) - travel(len, t)) / len, dot(p, c) / (len * crest_stretch));
	q += warp * vec2(gnoise(q * 0.45 + salt + t * 0.05), gnoise(q * 0.45 + salt + 23.1 - t * 0.05));
	vec3 n = gnoise_d(q + salt);
	return vec3(n.x, n.y * w + n.z * c / crest_stretch);
}

// Sharp caustic network on the floor: two drifting, warped noise fields; light
// gathers where they cross (|a - b| small), giving thin bright lines that wander.
float caustics(vec2 p, float t) {
	vec2 q = p / caustic_scale;
	q += 0.35 * vec2(gnoise(q * 0.5 + t * 0.15), gnoise(q * 0.5 + 9.2 - t * 0.12));
	float a = gnoise(q + vec2(t * 0.35, t * 0.12));
	float b = gnoise(q * 1.13 + 5.7 - vec2(t * 0.1, t * 0.3));
	float v = 1.0 - abs(a - b);
	return aastep(1.0 - caustic_width, v);
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
	// World size of one pixel here; layers whose features drop under a few pixels fade.
	float px = max(length(fwidth(p)), 1e-4);

	// Three wave layers, each a fraction of the last and turned off the wind.
	float len0 = wave_length;
	float len1 = wave_length * 0.53;
	float len2 = wave_length * 0.29;
	vec3 w0 = wave_layer(p, wind, len0, 0.0, t, 0.0);
	vec3 w1 = wave_layer(p, wind, len1, 0.45, t, 17.3);
	vec3 w2 = wave_layer(p, wind, len2, -0.35, t, 41.9);
	float vis0 = smoothstep(4.0, 14.0, len0 / px) * persp;
	float vis1 = smoothstep(4.0, 14.0, len1 / px) * persp;
	float vis2 = smoothstep(4.0, 14.0, len2 / px) * persp;

	// Normal for refraction and the engine's sky reflection: smooth, world-space slope
	// is the dimensionless slope over the wavelength.
	vec2 g = w0.yz / len0 * vis0 + w1.yz / len1 * vis1 * 0.7 + w2.yz / len2 * vis2 * 0.45;
	g *= normal_strength * len0 * 0.25;
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

	float cloud = cloud_shadow(world_pos, TIME);
	float sun_up = smoothstep(0.0, 0.25, sun_direction.y) * daylight;
	float floor_depth = max(world_pos.y - seen.y, 0.0);
	// Caustics on the floor: sunlight that already crossed the water column down,
	// so they fade with depth, and vanish under cloud and in the far distance.
	float caus = caustics(seen.xz, t) * (1.0 - smoothstep(0.0, caustic_fade_depth, floor_depth))
			* smoothstep(0.05, 0.4, floor_depth) * sun_up * clamp(1.0 - cloud * 1.6, 0.0, 1.0)
			* smoothstep(caustic_scale * 0.05, caustic_scale * 0.02, length(fwidth(seen.xz))) * persp;
	floor_col *= 1.0 + caus * caustic_strength;

	// Length of water the light crosses on the way up to the eye.
	float path = min(length(seen - world_pos), 60.0);
	vec3 trans = exp(-absorption * path);
	vec3 water = floor_col * trans + scatter_color.rgb * (1.0 - exp(-scatter_density * path)) * mix(0.15, 1.0, daylight);

	// Slope tone: each layer's slope along the view. Positive = rises away from the
	// camera (faces it) -> darker; negative -> lighter (tilts toward the sky).
	vec2 view_h = normalize(p - CAMERA_POSITION_WORLD.xz + vec2(1e-4, 0.0));
	vec3 s = vec3(dot(w0.yz, view_h), dot(w1.yz, view_h), dot(w2.yz, view_h));
	vec3 vis = vec3(vis0, vis1, vis2);
	float tone = -dot(s * vis, tone_layers) / dot(tone_layers, vec3(1.0));
	// Posterise: cut into steps with a one-pixel edge. Where the steps would come
	// closer than a couple of pixels the edges just blend, so distance stays calm.
	float x = clamp(tone, -1.0, 1.0) * tone_steps * 0.5;
	float fx = fract(x);
	float wx = max(fwidth(x), 1e-4);
	float stepped = (floor(x) + clamp((fx - 1.0) / wx + 1.0, 0.0, 1.0)) / (tone_steps * 0.5);
	tone = mix(stepped, tone, smoothstep(0.3, 0.6, wx));
	tone *= vis0;
	// Darker steps also lean toward the tint, so they go deep blue rather than grey.
	water = mix(water, patch_tint.rgb * mix(0.2, 1.0, daylight), clamp(-tone * 0.45, 0.0, 0.35));
	water *= 1.0 + tone * tone_range * 2.0;

	// Crest glints: the peaks of a fine two-octave noise, kept only where the waves
	// beneath tilt away from the camera (toward the sky), so small irregular flecks
	// cluster on the wave backs. The threshold drops with distance, as the sea at a
	// grazing angle reflects more sky.
	vec2 gw = vec2(dot(p, wind) - travel(glint_scale * 3.0, t), dot(p, vec2(-wind.y, wind.x)) * 0.7) / glint_scale;
	float fine = gnoise(gw) * 0.65 + gnoise(gw * 2.3 + 11.0 - t * 0.6) * 0.35;
	float far = smoothstep(15.0, 120.0, dist);
	float ridge = fine * 0.75 + 0.6 - 0.3 * (s.x + s.y + s.z);
	float glint = aastep(mix(glint_near, glint_far, far), ridge)
			* smoothstep(3.0, 8.0, glint_scale / px) * persp;
	// Sun path: reflection of the sun off the rippled normal, hard edged.
	vec3 n_sun = normalize(vec3(-g.x * 2.5, 1.0, -g.y * 2.5));
	vec3 view_ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	float r = dot(reflect(view_ray, n_sun), normalize(sun_direction));
	float sun = smoothstep(1.0 - sun_size * 1.15, 1.0 - sun_size * 0.85, r) * persp;
	float cloud_lit = clamp(1.0 - cloud * 1.6, 0.0, 1.0);
	glint = max(glint * mix(0.25, 1.0, cloud_lit) * glint_strength, sun * cloud_lit * 0.9) * smoothstep(0.0, 0.2, sun_direction.y);

	// Shore foam: solid lip plus broken bands washing in, both hard-edged.
	float breakup = gnoise(p * 0.9 + vec2(t * 0.8, 0.0)) * 0.5 + 0.5;
	float lip = 1.0 - aastep(foam_width * (0.5 + breakup), depth);
	float band_fade = 1.0 - smoothstep(0.0, foam_width * 5.0, depth);
	float bands = aastep(0.7, fract(depth * 0.9 - t * 0.7 + breakup * 0.6)) * band_fade * step(0.55, breakup);
	float foam = max(lip, bands * 0.85) * persp;

	// The sky reflection (by Fresnel) is added by the engine on top of emission, so
	// the transmitted light gives up that share.
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = (0.02 + 0.98 * pow(1.0 - nv, 5.0)) * reflectivity * 2.0;
	EMISSION = water * (1.0 - fresnel) * (1.0 - foam);
	EMISSION = mix(EMISSION, glint_color.rgb * daylight, glint * (1.0 - foam));
	ALBEDO = foam_color.rgb * foam;
	ROUGHNESS = mix(roughness, 1.0, foam);
	SPECULAR = reflectivity * (1.0 - foam) * (1.0 - glint);
	ALPHA = 1.0;
}

void light() {
	vec3 lit = ATTENUATION * LIGHT_COLOR;
	// Only foam has albedo, so this only lights the foam.
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * lit / PI;
	// No direct specular: the sun shows up as the glints drawn in fragment().
}
