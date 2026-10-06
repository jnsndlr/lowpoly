shader_type spatial;
render_mode cull_back, specular_disabled;

// The mainland past the map (Backdrop): vertex-coloured flat facets lit like the
// terrain, with its own aerial perspective (haze.gdshaderinc) instead of the depth
// fog, so the ranges read as flat painted layers fading into the distance.

#include "res://shaders/clouds.gdshaderinc"

#include "res://shaders/haze.gdshaderinc"

// The visible cloud deck (and so its shadows) thins out past this radius
// (keep in sync with clouds.gdshader).
const float DECK_FADE_START = 900.0;
const float DECK_FADE_END = 1600.0;

const float WRAP = 0.3;

varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.95;
	FOG = backdrop_haze(world_pos, length(VERTEX));
}

void light() {
	float shade = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		float r = length(world_pos.xz);
		if (r < DECK_FADE_END) {
			shade = 1.0 - cloud_shadow(world_pos, TIME) * (1.0 - smoothstep(DECK_FADE_START, DECK_FADE_END, r));
		}
	}
	// A little wrap softens facet-to-facet contrast into broad painted planes.
	DIFFUSE_LIGHT += clamp((dot(NORMAL, LIGHT) + WRAP) / (1.0 + WRAP), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * shade;
}
