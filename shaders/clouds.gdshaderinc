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

float cl_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a0 = cl_hash(i) * TAU;
	float a1 = cl_hash(i + vec2(1.0, 0.0)) * TAU;
	float a2 = cl_hash(i + vec2(0.0, 1.0)) * TAU;
	float a3 = cl_hash(i + vec2(1.0, 1.0)) * TAU;
	float n0 = dot(vec2(cos(a0), sin(a0)), f);
	float n1 = dot(vec2(cos(a1), sin(a1)), f - vec2(1.0, 0.0));
	float n2 = dot(vec2(cos(a2), sin(a2)), f - vec2(0.0, 1.0));
	float n3 = dot(vec2(cos(a3), sin(a3)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

// 0..1 cloud density at a world-space xz position.
float cloud_density(vec2 xz, float t) {
	vec2 p = (xz - cloud_wind * t) * CLOUD_SCALE;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float n = 0.0;
	float a = 0.55;
	for (int i = 0; i < 5; i++) {
		n += a * cl_noise(p + float(i) * 7.3 + t * 0.004 * float(i));
		p = rot * p * 2.1;
		a *= 0.48;
	}
	n = n * 0.5 + 0.5;
	float lo = 1.0 - cloud_coverage * 0.75 - 0.18;
	return smoothstep(lo, lo + 0.22, n);
}

// 0 (clear sun) .. cloud_shadow_strength (under thick cloud) for a world position:
// follow the ray toward the sun up to the cloud deck and sample it there.
float cloud_shadow(vec3 world, float t) {
	vec3 sd = normalize(sun_direction);
	vec2 at = world.xz + sd.xz * (CLOUD_ALTITUDE - world.y) / max(sd.y, 0.12);
	return cloud_density(at, t) * cloud_shadow_strength;
}
