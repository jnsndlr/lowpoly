// Shared cloud field: the visible cloud layer draws it, and every lit surface
// samples it along the sun direction for soft, drifting cloud shadows, so the two
// always line up. Coverage, wind and sun come from project-wide shader globals set
// by CloudLayer and DayCycle.

global uniform float cloud_coverage;
global uniform vec2 cloud_wind;
global uniform float cloud_shadow_strength;
global uniform vec3 sun_direction;

const float CLOUD_ALTITUDE = 170.0;
const float CLOUD_SCALE = 0.0045;

// Random unit gradient per lattice cell (hash22 + normalise; no sin/cos).
vec2 cl_grad(vec2 i) {
	vec3 p3 = fract(vec3(i.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	vec2 g = fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
	return g * inversesqrt(max(dot(g, g), 1e-4));
}

float cl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n0 = dot(cl_grad(i), f);
	float n1 = dot(cl_grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n2 = dot(cl_grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n3 = dot(cl_grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

const int CLOUD_OCTAVES = 5;
const int COARSE_OCTAVES = 3;

// Sum of fbm octaves [first, last) at a world-space xz position; the full sum over
// 0..CLOUD_OCTAVES is about -1..1. Split so callers can test the broad shapes first.
float cloud_octaves(vec2 xz, float t, int first, int last) {
	vec2 p = (xz - cloud_wind * t) * CLOUD_SCALE;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float a = 0.55;
	for (int i = 0; i < first; i++) {
		p = rot * p * 2.1;
		a *= 0.48;
	}
	float n = 0.0;
	for (int i = first; i < last; i++) {
		n += a * cl_noise(p + float(i) * 7.3 + t * 0.004 * float(i));
		p = rot * p * 2.1;
		a *= 0.48;
	}
	return n;
}

// Raw fbm value below which the density is zero.
float cloud_threshold() {
	return (1.0 - cloud_coverage * 0.75 - 0.18) * 2.0 - 1.0;
}

float cloud_coverage_curve(float n) {
	n = n * 0.5 + 0.5;
	float lo = 1.0 - cloud_coverage * 0.75 - 0.18;
	return smoothstep(lo, lo + 0.22, n);
}

// Largest amount the octaves after COARSE_OCTAVES can add (|noise| <= ~1.06).
const float CLOUD_FINE_RANGE = (0.55 * 0.48 * 0.48 * 0.48 + 0.55 * 0.48 * 0.48 * 0.48 * 0.48) * 1.06;

// 0..1 cloud density at a world-space xz position.
float cloud_density(vec2 xz, float t) {
	return cloud_coverage_curve(cloud_octaves(xz, t, 0, CLOUD_OCTAVES));
}

// 0 (clear sun) .. cloud_shadow_strength (under thick cloud) for a world position:
// follow the ray toward the sun up to the cloud deck and sample it there.
float cloud_shadow(vec3 world, float t) {
	vec3 sd = normalize(sun_direction);
	vec2 at = world.xz + sd.xz * (CLOUD_ALTITUDE - world.y) / max(sd.y, 0.12);
	float n = cloud_octaves(at, t, 0, COARSE_OCTAVES);
	// Clear sky overhead: the remaining octaves can't make a shadow.
	if (n + CLOUD_FINE_RANGE < cloud_threshold()) {
		return 0.0;
	}
	// Shadows are soft, so the finest octave (amplitude ~0.03) is left out.
	n += cloud_octaves(at, t, COARSE_OCTAVES, CLOUD_OCTAVES - 1);
	return cloud_coverage_curve(n) * cloud_shadow_strength;
}
