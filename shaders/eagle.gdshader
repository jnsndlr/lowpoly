shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Bald eagles (Models.eagle, drawn per bird by Eagles' multimesh). Built like
// seagull.gdshader: wing vertices (vertex alpha < 0.9) hinge at the shoulder and again
// at the wrist about the line y = WING_Y, so a flap whips the hand after the arm;
// folded, they take the perched pose baked into the model (UV, UV2.x; art/eagle_mid.py).
// Legs (alpha 0.9..0.95) swing about the hip: hanging straight down perched, trailed
// back under the tail in flight, thrown forward to strike. The tail (0.95..0.99)
// closes up at rest. Perched, the bird sits very upright, pivoting over its feet.
// Faces are lit flat, by their screen-space normal.
// INSTANCE_CUSTOM: x flap phase (rad), y flap amplitude (rad), z fold 0..1,
// w plumage + talons: floor(w) = 0 adult, 1 sub-adult, 2 juvenile; fract(w) / 0.9 =
// how far the feet are thrown forward.

const float SHOULDER = 0.09;
const float ELBOW = 0.5;
const float WING_Y = 0.05;
// Soaring on flat wings, the hand lifted a touch.
const float DIHEDRAL = 0.04;
const float HAND_LIFT = 0.06;
// Perched: body tilt (rad) about the hip, and how far the head is drawn up.
const float STANCE = 0.5;
const vec3 HIP = vec3(0.0, -0.05, 0.03);
const float NECK_UP = 0.008;
// Leg swing about the hip (rad, + = feet forward).
const float TUCK = -1.5;
const float STRIKE = 1.05;

varying float age;
varying flat vec3 facet;
varying flat float under;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	float fold = INSTANCE_CUSTOM.z;
	float w = INSTANCE_CUSTOM.w;
	age = floor(w + 0.01) * 0.5;
	float talons = clamp(fract(w + 0.01) / 0.9, 0.0, 1.0);
	facet = VERTEX;
	under = COLOR.a < 0.9 && NORMAL.y < -0.5 ? 1.0 : 0.0;
	if (COLOR.a < 0.9) {
		float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
		float ax = abs(VERTEX.x);
		float phase = INSTANCE_CUSTOM.x;
		float amp = INSTANCE_CUSTOM.y;
		float a1 = DIHEDRAL + amp * sin(phase);
		float a2 = a1 + HAND_LIFT + amp * 0.55 * sin(phase - 0.8);
		float t1 = min(ax, ELBOW) - SHOULDER;
		float t2 = max(ax - ELBOW, 0.0);
		float a = ax > ELBOW ? a2 : a1;
		// Thickness off the hinge line turns with its segment.
		vec2 xy = vec2(SHOULDER, WING_Y) + t1 * vec2(cos(a1), sin(a1)) + t2 * vec2(cos(a2), sin(a2))
			+ (VERTEX.y - WING_Y) * vec2(-sin(a), cos(a));
		vec3 open_pos = vec3(side * xy.x, xy.y, VERTEX.z);
		vec3 n = NORMAL;
		n.xy = rot(n.xy, side * a);
		vec3 folded = vec3(UV.x, UV.y, UV2.x);
		VERTEX = mix(open_pos, folded, fold);
		NORMAL = normalize(mix(n, vec3(side * 0.6, 1.0, 0.0), fold));
	} else if (COLOR.a < 0.95) {
		float swing = mix(mix(TUCK, 0.0, fold), STRIKE, talons);
		vec2 zy = rot(vec2(VERTEX.z - HIP.z, VERTEX.y - HIP.y), swing);
		VERTEX.zy = zy + HIP.zy;
		// Tucked up, the legs draw in close under the body.
		VERTEX.x *= mix(0.7, 1.0, max(fold, talons));
	} else if (COLOR.a < 0.99) {
		VERTEX.x *= 1.0 - 0.4 * fold;
	}
	if (COLOR.a < 0.9 || COLOR.a > 0.95) {
		VERTEX.y += NECK_UP * fold * smoothstep(0.17, 0.25, VERTEX.z);
		vec2 yz = rot(vec2(VERTEX.z - HIP.z, VERTEX.y - HIP.y), STANCE * fold);
		VERTEX.yz = vec2(yz.y + HIP.y, yz.x + HIP.z);
	}
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (age > 0.0) {
		// Young eagles take five years to go white-headed: brown all over, mottled
		// facet by facet, with pale blotching under the wings and on the belly, the
		// bill dark. Sub-adults (age 0.5) are half way there, blotchy.
		float l = dot(col, vec3(0.3, 0.55, 0.15));
		bool bill = col.r > 0.8 && col.b < 0.3 && COLOR.a > 0.95;
		bool foot = COLOR.a > 0.9 && COLOR.a < 0.95 && col.r > 0.5;
		float hsh = hash(floor(facet * 45.0));
		float m = hsh * 0.24 - 0.12;
		vec3 brown = mix(vec3(0.2, 0.14, 0.095), vec3(0.4, 0.3, 0.2), smoothstep(0.1, 0.9, l)) * (1.0 + m);
		if (under > 0.5 && hsh > 0.55) brown = mix(brown, vec3(0.78, 0.74, 0.66), 0.7);
		if (l > 0.6 && hsh > 0.7) brown = mix(brown, vec3(0.86, 0.84, 0.8), 0.6);
		if (bill) brown = mix(vec3(0.2, 0.18, 0.16), col, 0.25);
		if (!foot) col = mix(col, brown, age);
	}
	ALBEDO = srgb_to_linear(col);
	// Flat facets whatever the pose: the face normal, turned to the camera.
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = fn.z < 0.0 ? -fn : fn;
	ROUGHNESS = 0.9;
}
