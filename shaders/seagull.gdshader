shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Seagulls (Models.seagull, drawn per gull by Seagulls' multimesh). Wing vertices
// (vertex alpha < 0.9) hinge at the shoulder and again at the elbow, so a flap
// whips the outer wing after the inner one; folded, they tuck back along the body.
// INSTANCE_CUSTOM: x flap phase (rad), y flap amplitude (rad), z fold 0..1.

const float SHOULDER = 0.06;
const float ELBOW = 0.4;
// Wings held in a shallow V while gliding.
const float DIHEDRAL = 0.12;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	if (COLOR.a < 0.9) {
		float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
		float ax = abs(VERTEX.x);
		float phase = INSTANCE_CUSTOM.x;
		float amp = INSTANCE_CUSTOM.y;
		float fold = INSTANCE_CUSTOM.z;
		float a1 = DIHEDRAL + amp * sin(phase);
		float a2 = a1 + amp * 0.7 * sin(phase - 0.9);
		float t1 = min(ax, ELBOW) - SHOULDER;
		float t2 = max(ax - ELBOW, 0.0);
		vec2 xy = vec2(SHOULDER, VERTEX.y) + t1 * vec2(cos(a1), sin(a1)) + t2 * vec2(cos(a2), sin(a2));
		vec3 open_pos = vec3(side * xy.x, xy.y, VERTEX.z);
		vec3 n = NORMAL;
		n.xy = rot(n.xy, side * (ax > ELBOW ? a2 : a1));
		// Folded: the span swings back along the body, tips just past the tail, and
		// the chord drapes over the back like a roof, grey side up.
		float c = clamp(VERTEX.z + 0.1, 0.0, 0.22);
		vec3 folded = vec3(side * (0.08 - c * 0.28), 0.03 + c * 0.38, 0.1 - (ax - SHOULDER) * 0.62);
		VERTEX = mix(open_pos, folded, fold);
		NORMAL = normalize(mix(n, vec3(side * 0.6, 1.0, 0.0), fold));
	}
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	// Pale undersides, but the black wingtips stay black.
	if (!FRONT_FACING && COLOR.a < 0.9 && COLOR.r > 0.3) {
		ALBEDO = mix(ALBEDO, vec3(0.8), 0.75);
	}
	ROUGHNESS = 0.9;
}
