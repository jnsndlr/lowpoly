shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Stylised sea: choppy noise ripples that catch the sun, a depth ramp from pale
// turquoise shallows through cyan to deep navy, broad swell/gust colour patches,
// and broken animated foam where the water meets land, hulls and pilings.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec4 deep_color : source_color = vec4(0.015, 0.115, 0.35, 1.0);
uniform vec4 mid_color : source_color = vec4(0.02, 0.27, 0.58, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.1, 0.66, 0.78, 1.0);
uniform vec4 shore_color : source_color = vec4(0.45, 0.9, 0.86, 1.0);
uniform vec4 crest_color : source_color = vec4(0.06, 0.3, 0.62, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.98, 1.0);
// The sea floor sits 5.5 below the surface, so the ramp has to finish before that.
uniform float shallow_depth = 1.4;
uniform float mid_depth = 3.4;
uniform float deep_depth = 5.3;
uniform float foam_width = 0.45;
uniform float wave_height = 0.22;
uniform float ripple_scale = 0.16;
uniform float ripple_strength = 0.7;
uniform float ripple_speed = 1.0;
uniform float sparkle = 0.55;
// 0 at night .. 1 in full sun; set by DayCycle so glints don't glow in the dark.
uniform float daylight = 1.0;
// Half-size of the subdivided plane; swell flattens out before its edge so it
// meets the flat horizon ring without cracks.
uniform float swell_extent = 100000.0;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Gradient noise in -1..1; unlike value noise it has no visible grid cells.
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a0 = hash(i) * TAU;
	float a1 = hash(i + vec2(1.0, 0.0)) * TAU;
	float a2 = hash(i + vec2(0.0, 1.0)) * TAU;
	float a3 = hash(i + vec2(1.0, 1.0)) * TAU;
	float n0 = dot(vec2(cos(a0), sin(a0)), f);
	float n1 = dot(vec2(cos(a1), sin(a1)), f - vec2(1.0, 0.0));
	float n2 = dot(vec2(cos(a2), sin(a2)), f - vec2(0.0, 1.0));
	float n3 = dot(vec2(cos(a3), sin(a3)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

// Wind-driven chop: the domain is warped and stretched across the wind so crests
// read as elongated wavelets rather than a repeating cell pattern, and the layers
// drift in different directions so the whole never visibly scrolls.
float chop(vec2 p, float t) {
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = rot * p;
	p += 0.45 * vec2(gnoise(p * 0.27 + t * 0.04), gnoise(p * 0.27 + 31.7 - t * 0.04));
	p.y *= 0.7;
	float h = 0.0;
	float a = 0.34;
	vec2 drift = vec2(0.35, 0.22);
	for (int i = 0; i < 4; i++) {
		float n = gnoise(p + drift * t);
		// Soft ridge: rounded at the top so crests don't shade as hard creases.
		h += a * (1.0 - 1.6 * sqrt(n * n + 0.02));
		p = rot * p * 1.87 + 17.1;
		drift = rot * drift * -1.35;
		a *= 0.72;
	}
	return clamp(h * 1.15 + 0.12, 0.0, 1.0);
}

float swell(vec2 p, float t) {
	float h = sin(p.x * 0.06 + t * 0.7) * cos(p.y * 0.075 + t * 0.55);
	h += 0.5 * sin((p.x - p.y) * 0.13 + t * 1.2);
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge = max(abs(world_pos.x), abs(world_pos.z));
	VERTEX.y += swell(world_pos.xz, TIME) * wave_height * (1.0 - smoothstep(swell_extent - 80.0, swell_extent - 10.0, edge));
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * ripple_speed;
	float dist = length(VERTEX);
	// Fade fine detail out with distance so it doesn't shimmer when zoomed out.
	float detail = 1.0 - smoothstep(220.0, 800.0, dist);
	// Orthographic views (the minimap) get flat, calm water.
	float ortho = step(0.5, PROJECTION_MATRIX[3][3]);
	detail *= 1.0 - ortho;

	// Broad gust patches modulate how rough the surface is.
	float gust = vnoise(p * 0.012 + vec2(t * 0.02, -t * 0.015));
	gust = mix(gust, vnoise(p * 0.035 - t * 0.02), 0.35);

	vec2 rp = p * ripple_scale;
	float e = 0.12;
	float h0 = chop(rp, t);
	float hx = chop(rp + vec2(e, 0.0), t);
	float hz = chop(rp + vec2(0.0, e), t);
	float strength = ripple_strength * detail * mix(0.45, 1.25, gust);
	vec3 wn = normalize(vec3(-(hx - h0) / e * strength, 1.0, -(hz - h0) / e * strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Water column depth under this fragment.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - scene_world.y, 0.0);
	// Wobble the depth bands a little so the shore halo isn't a perfect contour.
	float d = depth * mix(0.8, 1.25, vnoise(p * 0.09 + t * 0.05));

	vec3 col = mix(shore_color.rgb, shallow_color.rgb, smoothstep(0.0, shallow_depth, d));
	col = mix(col, mid_color.rgb, smoothstep(shallow_depth * 0.6, mid_depth, d));
	float deep_t = smoothstep(mid_depth * 0.7, deep_depth, d);
	col = mix(col, deep_color.rgb, deep_t);

	// Open-water variation: gust patches and lighter ripple crests.
	col *= mix(0.72, 1.22, gust);
	float crest = smoothstep(0.5, 0.95, h0) * detail;
	col = mix(col, crest_color.rgb, crest * 0.55 * mix(0.3, 1.0, deep_t));

	// Shore foam: solid lip plus broken bands washing in.
	float breakup = vnoise(p * 0.9 + vec2(t * 0.3, 0.0)) * 0.6 + h0 * 0.5;
	float lip = 1.0 - smoothstep(0.0, foam_width * (0.5 + breakup), depth);
	float band_fade = 1.0 - smoothstep(0.0, foam_width * 5.0, depth);
	float bands = smoothstep(0.55, 0.75, fract(depth * 0.9 - t * 0.25 + breakup * 0.6)) * band_fade;
	float foam = clamp(lip + bands * smoothstep(0.45, 0.8, breakup) * 0.7, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam);

	// Cloud shadows: dim the colour and kill the sun's glints and sheen underneath.
	float cloud = cloud_shadow(world_pos, TIME);
	col *= 1.0 - cloud * 0.8;

	// Dye the water down at night so it doesn't out-glow the moonlit land.
	ALBEDO = col * mix(0.55, 1.0, daylight);
	ALPHA = clamp(mix(0.62, 0.98, smoothstep(0.0, mid_depth, depth)) + foam, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.4, 0.28, detail), 1.0, ortho);
	SPECULAR = 0.25 * (1.0 - ortho) * (1.0 - cloud);
	// Sun glitter: twinkling specks on the sharpest crests, thicker in gusty patches.
	float twinkle = vnoise(p * 1.7 + vec2(t * 1.3, -t * 0.9));
	float glint = smoothstep(0.84, 0.95, h0) * smoothstep(0.6, 0.85, twinkle) * smoothstep(0.4, 0.8, gust);
	EMISSION = vec3(sparkle) * glint * detail * (1.0 - foam) * daylight * (1.0 - cloud * 1.5);
}
