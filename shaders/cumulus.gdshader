shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// The cumulus banks over the horizon (Backdrop): smooth rounded puffs painted in
// two tones, sunlit white and a cool sky-coloured shadow side, with a soft step
// between them, greyer flat bases and the same aerial haze as the land below.
// Lit by hand from the day cycle's globals, so they blush at sunset and go dark
// blue under the moon.

#include "res://shaders/haze.gdshaderinc"

global uniform vec3 sun_direction;
global uniform vec3 sun_light;

// 0: fair-weather white .. 1: rain-grey (overcast days).
uniform float grey = 0.0;

varying vec3 world_n;
varying vec3 world_pos;

void vertex() {
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(world_n);
	float l = dot(n, normalize(sun_direction));
	float lit = smoothstep(-0.2, 0.3, l);
	vec3 shadow = mix(haze_sky, sky_zenith, 0.62) * 0.95 + sun_light * 0.06;
	vec3 sunlit = sun_light * 0.62 + haze_sky * 0.35;
	sunlit = mix(sunlit, shadow * 1.15, grey * 0.6);
	vec3 col = mix(shadow, sunlit, lit);
	// Skylight on the tops, a greyer base, and a little variety between clusters.
	col += sky_zenith * 0.12 * max(n.y, 0.0);
	col *= mix(0.8, 1.0, smoothstep(0.0, 0.35, COLOR.r)) * mix(0.95, 1.03, COLOR.g);
	ALBEDO = col;
	vec4 haze = backdrop_haze(world_pos, length(VERTEX));
	FOG = vec4(mix(haze.rgb, haze_sky, 0.5), haze.a * 0.7);
}
