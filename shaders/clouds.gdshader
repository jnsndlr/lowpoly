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
	float coarse = cloud_octaves(p, TIME, 0, COARSE_OCTAVES);
	float d = 0.0;
	vec3 wn = vec3(0.0, 1.0, 0.0);
	// Clear sky (the fine octaves can't lift it past the threshold) needs no more work.
	if (coarse + CLOUD_FINE_RANGE >= cloud_threshold()) {
		float n = coarse + cloud_octaves(p, TIME, COARSE_OCTAVES, CLOUD_OCTAVES);
		d = cloud_coverage_curve(n);
		// The 12-unit finite difference smooths away the fine octaves anyway, so step
		// only the broad ones and shift the full-detail value by that change.
		float e = 12.0;
		float dx = cloud_coverage_curve(n + cloud_octaves(p + vec2(e, 0.0), TIME, 0, COARSE_OCTAVES) - coarse) - d;
		float dz = cloud_coverage_curve(n + cloud_octaves(p + vec2(0.0, e), TIME, 0, COARSE_OCTAVES) - coarse) - d;
		// Treat density as height so edges shade like rounded billows.
		wn = normalize(vec3(-dx * puff, 1.0, -dz * puff));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float near = mix(0.12, 1.0, smoothstep(near_fade_start, near_fade_end, length(VERTEX)));
	ALBEDO = mix(vec3(0.78, 0.8, 0.86), vec3(1.0), d);
	ALPHA = d * opacity * near;
}
