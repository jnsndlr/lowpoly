shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Seagulls (Models.seagull, drawn per gull by Seagulls' multimesh). Wing vertices
// (vertex alpha < 0.9) hinge at the shoulder and again at the elbow about the line
// y = WING_Y, so a flap whips the outer wing after the inner one. Folded, they take
// the perched pose baked into the model (UV, UV2.x; art/seagull_mid.py) or, for the
// classic mesh, one worked out here. Leg vertices (alpha 0.9..0.95) tuck into the
// belly in flight; the tail (0.95..0.99) closes up at rest. Perched, the bird stands
// breast up and head raised, pivoting over its feet. Faces are lit flat, by their
// screen-space normal.
// INSTANCE_CUSTOM: x flap phase (rad), y flap amplitude (rad), z fold 0..1,
// w plumage age (0 adult, 1 first-year: mottled brown with a dark bill).

uniform bool baked_fold = true;

const float SHOULDER = 0.06;
const float ELBOW = 0.4;
const float WING_Y = 0.04;
// Wings held in a shallow V while gliding.
const float DIHEDRAL = 0.12;
// Standing: body tilt (rad) about the hip, and how far the head is drawn up.
const float STANCE = 0.32;
const vec3 HIP = vec3(0.0, -0.035, 0.015);
const float NECK_UP = 0.022;

varying float age;
varying flat vec3 facet;

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
	age = INSTANCE_CUSTOM.w;
	facet = VERTEX;
	if (COLOR.a < 0.9) {
		float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
		float ax = abs(VERTEX.x);
		float phase = INSTANCE_CUSTOM.x;
		float amp = INSTANCE_CUSTOM.y;
		float a1 = DIHEDRAL + amp * sin(phase);
		float a2 = a1 + amp * 0.7 * sin(phase - 0.9);
		float t1 = min(ax, ELBOW) - SHOULDER;
		float t2 = max(ax - ELBOW, 0.0);
		float a = ax > ELBOW ? a2 : a1;
		// Thickness off the hinge line turns with its segment.
		vec2 xy = vec2(SHOULDER, WING_Y) + t1 * vec2(cos(a1), sin(a1)) + t2 * vec2(cos(a2), sin(a2))
			+ (VERTEX.y - WING_Y) * vec2(-sin(a), cos(a));
		vec3 open_pos = vec3(side * xy.x, xy.y, VERTEX.z);
		vec3 n = NORMAL;
		n.xy = rot(n.xy, side * a);
		vec3 folded;
		if (baked_fold) {
			folded = vec3(UV.x, UV.y, UV2.x);
		} else {
			// The span swings back along the body, tips just past the tail, and the
			// chord drapes over the back like a roof, grey side up.
			float c = clamp(VERTEX.z + 0.1, 0.0, 0.22);
			folded = vec3(side * (0.08 - c * 0.28), 0.03 + c * 0.38, 0.1 - (ax - SHOULDER) * 0.62);
		}
		VERTEX = mix(open_pos, folded, fold);
		NORMAL = normalize(mix(n, vec3(side * 0.6, 1.0, 0.0), fold));
	} else if (COLOR.a < 0.95) {
		// Legs: drawn up into the belly feathers in flight.
		VERTEX = mix(vec3(VERTEX.x * 0.5, -0.02, 0.0), VERTEX, fold);
	} else if (COLOR.a < 0.99) {
		VERTEX.x *= 1.0 - 0.45 * fold;
	}
	if (COLOR.a < 0.9 || COLOR.a > 0.95) {
		VERTEX.y += NECK_UP * fold * smoothstep(0.13, 0.2, VERTEX.z);
		vec2 yz = rot(vec2(VERTEX.z - HIP.z, VERTEX.y - HIP.y), STANCE * fold);
		VERTEX.yz = vec2(yz.y + HIP.y, yz.x + HIP.z);
	}
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (!baked_fold && !FRONT_FACING && COLOR.a < 0.9 && COLOR.r > 0.3) {
		// Classic mesh: pale undersides, but the black wingtips stay black.
		col = mix(col, vec3(0.8), 0.75);
	}
	if (age > 0.0) {
		// Immatures: browner and mottled facet by facet, the bill dark.
		float l = dot(col, vec3(0.3, 0.55, 0.15));
		bool bill = col.r > 0.8 && col.b < 0.3;
		bool leg = COLOR.a > 0.9 && COLOR.a < 0.95;
		float m = hash(floor(facet * 60.0)) * 0.22 - 0.11;
		vec3 brown = mix(vec3(0.24, 0.2, 0.17), vec3(0.72, 0.65, 0.57), smoothstep(0.1, 0.95, l)) * (1.0 + m);
		if (bill) brown = vec3(0.16, 0.14, 0.13);
		if (!leg) col = mix(col, brown, age);
	}
	ALBEDO = srgb_to_linear(col);
	// Flat facets whatever the pose: the face normal, turned to the camera.
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = fn.z < 0.0 ? -fn : fn;
	ROUGHNESS = 0.9;
}
