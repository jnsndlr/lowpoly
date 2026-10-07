shader_type spatial;
render_mode cull_disabled;

// Whales, orcas and porpoises (Models.orca, Models.humpback, ..., drawn per animal by
// Cetaceans' multimeshes, one unit long, +Z forward). Dorsal fin vertices (vertex
// alpha < 0.95) rise from the back to the animal's fin height, the tip swept back
// by its curve; the tail stock and flukes beat up and down.
// INSTANCE_CUSTOM: x fin height (body lengths), y fin sweep 0..1, z tail phase (rad),
// w tail amplitude (body lengths).

const float FIN_BASE = 0.085;
// The tail flexes behind this point, more toward the flukes.
const float FLEX_FROM = -0.12;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	if (COLOR.a < 0.95) {
		float t = (1.0 - COLOR.a) * 2.0;
		VERTEX.y = FIN_BASE + t * INSTANCE_CUSTOM.x;
		VERTEX.z -= INSTANCE_CUSTOM.y * t * t * 0.09;
	}
	float back = clamp((FLEX_FROM - VERTEX.z) / (0.52 + FLEX_FROM), 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.z - back * 2.2;
	VERTEX.y += INSTANCE_CUSTOM.w * sin(phase) * back * back;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	// Wet skin: smooth, with a sheen.
	ROUGHNESS = 0.6;
	SPECULAR = 0.25;
}
