shader_type spatial;
render_mode cull_disabled;

// Seals and sea lions (Models.harbor_seal, Models.sea_lion, drawn per animal by
// Pinnipeds' multimeshes, one unit long, +Z forward, belly at y = 0). The head
// bends up past `neck_z` and the hind flippers up behind `hip_z`; swimming sways
// the rear from side to side, and a seal humping along on land arches its back.
// INSTANCE_CUSTOM: x head lift (rad), y hind flippers lift (rad), z gait/swim
// phase (rad), w swimming sway (> 0, body lengths) or arch (< 0, body lengths).
// The instance colour tints the coat.

uniform float neck_z = 0.3;
uniform float hip_z = -0.2;
uniform float pivot_y = 0.08;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// Rotates `v` (y, z) about (pivot_y, z0) by `a`, the bend coming in over `ramp`.
vec2 bend(vec2 yz, float z0, float a) {
	vec2 rel = yz - vec2(pivot_y, z0);
	float c = cos(a);
	float s = sin(a);
	return vec2(pivot_y + rel.x * c + rel.y * s, z0 + rel.y * c - rel.x * s);
}

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float w = INSTANCE_CUSTOM.w;
	float phase = INSTANCE_CUSTOM.z;
	if (w < 0.0) {
		v.y += -w * (0.5 - 0.5 * cos(phase)) * max(1.0 - 5.0 * v.z * v.z, 0.0);
	} else {
		float back = clamp((hip_z + 0.1 - v.z) / 0.35, 0.0, 1.0);
		v.x += w * sin(phase - v.z * 5.0) * back * back;
	}
	if (v.z > neck_z) {
		float a = INSTANCE_CUSTOM.x * smoothstep(neck_z, neck_z + 0.1, v.z);
		v.yz = bend(v.yz, neck_z, a);
		n.yz = bend(n.yz + vec2(pivot_y, neck_z), neck_z, a) - vec2(pivot_y, neck_z);
	} else if (v.z < hip_z) {
		float a = -INSTANCE_CUSTOM.y * smoothstep(hip_z, hip_z - 0.12, v.z);
		v.yz = bend(v.yz, hip_z, a);
		n.yz = bend(n.yz + vec2(pivot_y, hip_z), hip_z, a) - vec2(pivot_y, hip_z);
	}
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	// Fur, sleek when wet.
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
