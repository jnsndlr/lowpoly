// Aerial perspective for everything past the map (Backdrop: land, tree cards and
// cumulus). Near the map it matches the engine's depth fog on the water; further
// out each layer sinks toward the blue of distance, with a thin band of haze lying
// on the water at the foot of the far shores, and high ground stands clear of it.
// Written to FOG, which replaces the engine's fog for these materials.

global uniform vec3 haze_fog;
global uniform vec3 haze_sky;
global uniform vec3 sky_zenith;
global uniform vec2 fog_range;

vec4 backdrop_haze(vec3 world, float depth) {
	float r = length(world.xz);
	float y = world.y;
	// A lighter take on the engine's depth fog, only on low ground near the map.
	float a = smoothstep(fog_range.x, fog_range.y, depth) * 0.6
		* (1.0 - smoothstep(10.0, 300.0, y)) * (1.0 - smoothstep(1200.0, 2600.0, r));
	vec3 col = haze_fog;
	// The blue of distance, deepening with each layer out.
	float far = smoothstep(600.0, 9000.0, r);
	far = pow(far, 0.75) * 0.78;
	col = mix(col, mix(haze_sky, sky_zenith, 0.5), far / max(far + a, 1e-4));
	a = max(a, far);
	// Thin haze on the water at the foot of the far shores.
	float low = smoothstep(1500.0, 6000.0, r) * (1.0 - smoothstep(0.0, 120.0, y)) * 0.4;
	col = mix(col, haze_sky, low / max(low + a, 1e-4));
	a = max(a, low);
	return vec4(col, a);
}
