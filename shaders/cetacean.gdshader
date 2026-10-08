shader_type spatial;
render_mode cull_disabled;

// Whales, orcas and porpoises (Models.orca, Models.humpback, ..., drawn per animal by
// Cetaceans' multimeshes, one unit long, +Z forward). Dorsal fin vertices (vertex
// alpha < 0.95) rise from the back to the animal's fin height, the tip swept back
// by its curve; the tail stock and flukes beat up and down.
// INSTANCE_CUSTOM: x fin height (body lengths), y fin sweep 0..1 in hundredths plus,
// in its fraction, the animal's markings 0..1, z tail phase (rad), w tail amplitude
// (body lengths).
//
// With orca_markings the orca's body (UV.x >= 0) is painted here, each animal its
// own: UV is (s, 1 - theta / pi), s the distance back from the nose (body lengths),
// theta round the body from the back (0) to the belly (pi). A markings value of 0.5
// and up is a calf, whose white is still peachy.

const float FIN_BASE = 0.085;
// The tail flexes behind this point, more toward the flukes.
const float FLEX_FROM = -0.12;

uniform bool orca_markings = false;

varying flat float markings;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float hash(float seed, float k) {
	return fract(sin(seed * 127.1 + k * 311.7) * 43758.5453);
}

// An orca's colour at (s, th) on its body (sRGB), the white patches and grey saddle
// varied per animal by `m`; `black` where there's no patch.
vec3 orca_colour(float s, float th, float m, vec3 black) {
	bool calf = m >= 0.5;
	float seed = fract(m * 2.0) + 0.37;
	vec3 white = calf ? vec3(0.94, 0.8, 0.66) : vec3(0.92, 0.93, 0.92);
	// Eye patch: a tilted oval above and behind the eye.
	float es = 0.2 + (hash(seed, 1.0) - 0.5) * 0.024;
	float ers = 0.062 + hash(seed, 2.0) * 0.024;
	float ert = (0.04 + hash(seed, 3.0) * 0.018) * PI;
	float tilt = (0.03 + hash(seed, 4.0) * 0.06) * PI;
	float ec = 0.37 * PI - tilt * (s - es) / ers;
	float e = (s - es) / ers;
	float f = (th - ec) / ert;
	if (e * e + f * f < 1.0) return white;
	// Chin and throat, narrowing to a strip between the flippers.
	if (s < 0.33) {
		if (th > 0.6 * PI + 0.27 * PI * pow(max(0.0, (s - 0.06) / 0.27), 1.3)) return white;
	} else if (s < 0.5 && th > (0.85 + hash(seed, 5.0) * 0.04) * PI) {
		return white;
	}
	// Flank patch sweeping up behind the dorsal fin.
	float f0 = 0.45 + hash(seed, 6.0) * 0.04;
	float f1 = 0.77 + hash(seed, 7.0) * 0.05;
	if (s > f0 && s < f1) {
		float u = (s - f0) / (f1 - f0);
		float lift = (0.4 + hash(seed, 8.0) * 0.16) * PI;
		if (th > 0.87 * PI - lift * pow(sin(PI * pow(u, 0.6 + hash(seed, 9.0) * 0.3)), 1.4) * (1.0 - 0.3 * u)) return white;
	}
	// Grey saddle behind the fin; an "open" one has a black notch running into it.
	float s0 = 0.55 + hash(seed, 10.0) * 0.025;
	float s1 = s0 + 0.15 + hash(seed, 11.0) * 0.05;
	if (s > s0 && s < s1) {
		float u = (s - s0) / (s1 - s0);
		float w = (0.13 + hash(seed, 12.0) * 0.12) * PI * pow(sin(PI * u), 0.7);
		if (th < w) {
			bool open = hash(seed, 13.0) > 0.65;
			float notch = (0.35 + hash(seed, 14.0) * 0.4) * w;
			float reach = 0.35 + hash(seed, 15.0) * 0.35;
			if (open && u < reach && th > notch * 0.6 && th < notch) return black;
			float grey = 0.42 + hash(seed, 16.0) * 0.22;
			return calf ? mix(black, white, 0.35) : vec3(grey, grey + 0.02, grey + 0.05);
		}
	}
	return black;
}

void vertex() {
	markings = fract(INSTANCE_CUSTOM.y);
	if (COLOR.a < 0.95) {
		float t = (1.0 - COLOR.a) * 2.0;
		VERTEX.y = FIN_BASE + t * INSTANCE_CUSTOM.x;
		VERTEX.z -= floor(INSTANCE_CUSTOM.y) * 0.01 * t * t * 0.09;
	}
	float back = clamp((FLEX_FROM - VERTEX.z) / (0.52 + FLEX_FROM), 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.z - back * 2.2;
	VERTEX.y += INSTANCE_CUSTOM.w * sin(phase) * back * back;
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (orca_markings && UV.x >= 0.0) {
		col = orca_colour(UV.x, (1.0 - UV.y) * PI, markings, col);
	}
	ALBEDO = srgb_to_linear(col);
	// Wet skin: smooth, with a sheen.
	ROUGHNESS = 0.6;
	SPECULAR = 0.25;
}
