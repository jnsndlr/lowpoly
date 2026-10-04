shader_type spatial;
render_mode cull_back;

// The shared vertex-coloured material for terrain, buildings, trees and boats.
// Same look as the StandardMaterial3D it replaces (sRGB vertex colours, matte
// Lambert), but direct sunlight is dimmed under passing clouds.
//
// Vertex alpha marks glass that lights up at night (Models.WINDOW*): 0 is always
// lit, 0.5 lit in some rooms and not others, picked per building, wall and floor,
// 0.15 (Models.LAMP_GLASS_ALPHA) the glass of a lamp, glowing in its own colour, and
// 0.7-0.95 the same flashing, with the phase in the alpha (Models.lamp_glass), and
// 0.3 (Models.NAV_GLASS_ALPHA) a ferry sidelight's lens, lit only at the bow end.

#include "res://shaders/clouds.gdshaderinc"

global uniform float night_lights;

uniform vec3 window_color : source_color = vec3(1.0, 0.68, 0.36);
uniform float window_energy = 2.6;
uniform float lamp_energy = 1.6;
// Must match Models.BLINK_PERIOD.
uniform float lamp_blink_period = 4.0;

// Which end of a ferry is the bow (+1: +Z), set per hull by NightLights.
instance uniform float nav_flip = 0.0;

varying vec3 world_pos;
varying float local_z;
varying vec3 room_key;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_z = VERTEX.z;
	// Instance origin, wall (normal) and storey: the same for a whole window. (Always-lit
	// glass ignores it, since it changes every frame on anything that moves.)
	room_key = MODEL_MATRIX[3].xyz + round(NORMAL * 2.0) * 17.0 + floor(VERTEX.y / 2.5) * 5.3;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.92;
	if (COLOR.a < 0.99 && night_lights > 0.0) {
		float h = hash13(room_key);
		// Always-lit glass comes on with the first lights; rooms one by one after.
		float on_at = COLOR.a < 0.25 ? 0.05 : 0.1 + h * 0.9;
		float lit = smoothstep(on_at, on_at + 0.08, night_lights) * step(COLOR.a < 0.25 ? 0.0 : 0.3, h);
		// The key moves with ferries, so only rooms that may go dark vary in brightness.
		float tint = COLOR.a < 0.25 ? 1.0 : mix(0.7, 1.15, fract(h * 7.1));
		bool lamp = COLOR.a > 0.1 && COLOR.a < 0.2;
		// Flashing lamp glass: the alpha holds its phase (Models.lamp_glass).
		bool flash = COLOR.a > 0.69 && COLOR.a < 0.96;
		bool nav = COLOR.a > 0.25 && COLOR.a < 0.35;
		if (lamp || flash || nav) {
			lit = smoothstep(0.05, 0.13, night_lights);
			if (nav) {
				lit *= local_z * nav_flip > 0.0 ? 2.0 : 0.0;
			}
			if (flash) {
				float k = fract(TIME / lamp_blink_period + (round(COLOR.a * 255.0) - 180.0) / 64.0);
				lit *= smoothstep(0.0, 0.04, k) * (1.0 - smoothstep(0.2, 0.32, k));
			}
			EMISSION = ALBEDO * lamp_energy * lit;
		} else {
			EMISSION = window_color * tint * window_energy * lit;
		}
	}
}

void light() {
	float shade = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		shade = 1.0 - cloud_shadow(world_pos, TIME);
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * shade;
}
