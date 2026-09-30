shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled, diffuse_lambert_wrap;

// Visible cloud layer: soft billows lit by the sun (so they blush at sunset),
// faded out near the camera so they never block the view when zoomed in.

#include "res://shaders/clouds.gdshaderinc"

uniform float opacity = 0.85;
uniform float near_fade_start = 180.0;
uniform float near_fade_end = 520.0;
uniform float puff = 5.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float d = cloud_density(p, TIME);
	float e = 12.0;
	float dx = cloud_density(p + vec2(e, 0.0), TIME) - d;
	float dz = cloud_density(p + vec2(0.0, e), TIME) - d;
	// Treat density as height so edges shade like rounded billows.
	vec3 wn = normalize(vec3(-dx * puff, 1.0, -dz * puff));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float near = mix(0.12, 1.0, smoothstep(near_fade_start, near_fade_end, length(VERTEX)));
	ALBEDO = mix(vec3(0.78, 0.8, 0.86), vec3(1.0), d);
	ALPHA = d * opacity * near;
}
