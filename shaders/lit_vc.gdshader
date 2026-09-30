shader_type spatial;
render_mode cull_back;

// The shared vertex-coloured material for terrain, buildings, trees and boats.
// Same look as the StandardMaterial3D it replaces (sRGB vertex colours, matte
// Lambert), but direct sunlight is dimmed under passing clouds.

#include "res://shaders/clouds.gdshaderinc"

varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.92;
}

void light() {
	float shade = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		shade = 1.0 - cloud_shadow(world_pos, TIME);
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * shade;
}
