shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Open water.
//
// Surface: a stack of choppy wave octaves (sharp crests, broad troughs) from the
// longest wind chop down to capillary ripples. Each octave is domain-warped by
// gradient noise and turned to its own angle around the wind, so no lattice or
// tiling shows when zoomed out. Octaves fade out as they shrink below a few pixels
// and the slope they would have added goes into roughness instead, so distant water
// turns into a smooth, broad sun glare rather than shimmering. Broad gust patches
// vary how rough the sea is from place to place.
//
// Colour: the sea floor is seen through the water (refracted by the waves) and
// absorbed along the length of water the light crosses, so shallows over sand go
// turquoise and deep water goes to the scattered body colour. Sky reflection comes
// from the environment by Fresnel; the sun glints off the rippled normal.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

group_uniforms waves;
// Crest spacing of the longest octave (world units); each next octave is ~half.
uniform float wave_length = 6.0;
// Height of the longest octave; each next octave is ~half, so slopes stay similar
// at every scale and ripples read up close.
uniform float wave_amp = 0.13;
// Crest sharpness of the longest octave (finer octaves are progressively rounder).
uniform float choppiness = 3.5;
uniform float wave_speed = 0.42;
uniform float normal_strength = 1.0;
// Gust patches: size (world units) and how much they swing the roughness.
uniform float gust_size = 180.0;
uniform float gust_strength = 0.55;

group_uniforms water;
// Light absorbed per unit of water crossed (red goes first, then green).
uniform vec3 absorption = vec3(0.5, 0.15, 0.09);
// Body colour that light scattered inside the water brings back, and how quickly
// it hides the floor.
uniform vec4 scatter_color : source_color = vec4(0.02, 0.15, 0.24, 1.0);
uniform float turbidity = 0.22;
uniform float refraction = 0.035;
uniform float roughness = 0.05;

group_uniforms foam;
uniform vec4 foam_color : source_color = vec4(0.93, 0.97, 0.98, 1.0);
uniform float foam_width = 0.35;

// Seals and sea lions in the water (Pinnipeds hands them over): no lip of foam
// round them, which would whiten a back just under the surface. Each is the
// body's middle (xy) and half its length forward (zw); `seal_bounds` holds them all.
uniform int seal_count = 0;
uniform vec4 seal_body[32];
uniform vec4 seal_bounds = vec4(0.0);

group_uniforms swell;
uniform float swell_height = 0.2;
// Half-size of the subdivided plane; swell flattens out before its edge so it
// meets the flat horizon ring without cracks.
uniform float swell_extent = 100000.0;

group_uniforms wake;
// Vessel wakes. WakeField packs each vessel's trail every frame: points run from the
// bow, to the stern, then back along the breadcrumbs it has dropped, as
// (x, z, distance along the trail, age in seconds), with its speed at each as a
// fraction of cruise (four to a vec4). wake_box is each trail's bounds (wake
// included), wake_info its current odometer, point count, how long (s)
// breadcrumbs live, and how hard a forward prop is reverse-thrusting (0..1) to
// brake for the dock, and wake_hull its half beam, length, prop wash strength
// (0 = none, 1 = a ferry's) and Kelvin wave scale (1 = a ferry's). wake_shape is
// its outline: how far back from the stem the bow narrows, the half-width at the
// stem (as a fraction of the half beam), and the same for the stern.
uniform vec4 wake_aerated : source_color = vec4(0.1, 0.5, 0.47, 1.0);
// Seconds for the churned foam to break up and fade, and for the Kelvin waves.
uniform float wake_life = 10.0;
uniform float kelvin_life = 14.0;
uniform float kelvin_wavelength = 5.5;
uniform float kelvin_height = 0.2;
uniform int wake_count = 0;
uniform vec4 wake_box[16];
uniform vec4 wake_info[16];
uniform vec4 wake_hull[16];
uniform vec4 wake_shape[16];
uniform vec4 wake_pts[768];
uniform vec4 wake_speed[192];
group_uniforms;

varying vec3 world_pos;
// Handed from fragment() to light().
varying vec3 flat_normal;
varying float cloud_lit;
varying float glint_vis;
varying float foam_amt;

vec2 grad(vec2 i) {
	vec3 p3 = fract(vec3(i.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	vec2 g = fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
	return g * inversesqrt(max(dot(g, g), 1e-4));
}

// Gradient noise, about -1..1.
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n0 = dot(grad(i), f);
	float n1 = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n2 = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n3 = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 1.5;
}

// gnoise() and its gradient `d`.
float gnoise_d(vec2 p, out vec2 d) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 g0 = grad(i);
	vec2 g1 = grad(i + vec2(1.0, 0.0));
	vec2 g2 = grad(i + vec2(0.0, 1.0));
	vec2 g3 = grad(i + vec2(1.0, 1.0));
	float n0 = dot(g0, f);
	float n1 = dot(g1, f - vec2(1.0, 0.0));
	float n2 = dot(g2, f - vec2(0.0, 1.0));
	float n3 = dot(g3, f - vec2(1.0, 1.0));
	float k = n0 - n1 - n2 + n3;
	d = (g0 + u.x * (g1 - g0) + u.y * (g2 - g0) + u.x * u.y * (g0 - g1 - g2 + g3)
			+ du * (vec2(n1 - n0, n2 - n0) + u.yx * k)) * 1.5;
	return (n0 + u.x * (n1 - n0) + u.y * (n2 - n0) + u.x * u.y * k) * 1.5;
}

// One choppy octave, 0..1: sharp ridges along a warped grid with rounded troughs
// between them. The noise warp is at the same scale as the ridges, so they bend,
// split and merge instead of lining up. Also outputs its gradient `d` (worked out
// exactly, so the surface normal costs one pass over the octaves, not three).
float chop_d(vec2 uv, float choppy, out vec2 d) {
	vec2 nd;
	vec2 v = uv + gnoise_d(uv, nd) * 0.9;
	vec2 sv = sin(v);
	vec2 cv = cos(v);
	vec2 a = 1.0 - abs(sv);
	vec2 b = abs(cv);
	vec2 da = -sign(sv) * cv;
	vec2 db = -sign(cv) * sv;
	vec2 m = a + (b - a) * a;
	vec2 dm = da * (1.0 + b - 2.0 * a) + a * db;
	float x = max(m.x * m.y, 1e-6);
	float y = pow(x, 0.65);
	float r = max(1.0 - y, 1e-6);
	float c = pow(r, choppy);
	// dc/dv, per component of v.
	vec2 dv = -choppy * pow(r, choppy - 1.0) * 0.65 * y / x * vec2(dm.x * m.y, m.x * dm.y);
	// Both components of v carry the same warp.
	d = dv + 0.9 * (dv.x + dv.y) * nd;
	return c;
}

const int OCTAVES = 6;
// Each octave's heading relative to the wind: the long chop runs with it, the
// finer ripples fan out further.
const float OCT_ANGLE[OCTAVES] = float[](0.0, 0.62, -0.5, 1.15, -0.95, 0.3);
const float OCT_LEN = 0.48;
const float OCT_AMP = 0.44;

// Height of the wave field at world xz `p`. `fp` is the world size of a pixel
// here; octaves under ~4 px are dropped. `wind` is the unit wind direction,
// `gust` 0..1. Outputs the longest octave's crest value (0..2) and the slope the
// dropped octaves would have added, and the height's gradient over world xz.
float waves(vec2 p, vec2 wind, float t, float fp, float gust, out float crest, out float lost, out vec2 slope) {
	// Wind frame: x downwind, y across.
	vec2 q0 = vec2(dot(p, wind), dot(p, vec2(-wind.y, wind.x)));
	float len = wave_length;
	float amp = wave_amp;
	float choppy = choppiness;
	float h = 0.0;
	// Gradient in the wind frame (q0).
	vec2 gq = vec2(0.0);
	crest = 0.0;
	lost = 0.0;
	for (int i = 0; i < OCTAVES; i++) {
		float lod = clamp(len / fp * 0.25 - 1.0, 0.0, 1.0);
		// Gusts roughen the finer octaves most.
		float g = mix(1.0 - gust_strength, 1.0 + gust_strength, gust);
		float a = amp * (i == 0 ? mix(1.0, g, 0.4) : g);
		lost += (1.0 - lod) * a / len;
		if (lod > 0.0) {
			float ang = OCT_ANGLE[i];
			vec2 cs = vec2(cos(ang), sin(ang));
			vec2 q = vec2(q0.x * cs.x + q0.y * cs.y, q0.y * cs.x - q0.x * cs.y);
			// Crests longer across the wind than along it.
			q.y *= 0.72;
			float k = PI / len;
			// Deep-water dispersion: longer waves travel faster.
			float travel = wave_speed * 1.25 * sqrt(len) * t * k;
			vec2 uv = q * k + vec2(float(i) * 3.7, float(i) * -5.3);
			// Two trains at slightly different speeds and headings, so the pattern
			// keeps re-forming instead of scrolling.
			vec2 d1, d2;
			const mat2 TRAIN2 = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96));
			float d = chop_d(uv - vec2(travel, 0.0), choppy, d1);
			d += chop_d(TRAIN2 * uv + vec2(-0.8 * travel, 0.3 * travel) + 11.0, choppy, d2);
			h += d * a * lod;
			// Back through the second train's turn, the stretch and the octave's heading.
			vec2 gu = (d1 + d2 * TRAIN2) * vec2(k, k * 0.72) * a * lod;
			gq += vec2(cs.x * gu.x - cs.y * gu.y, cs.y * gu.x + cs.x * gu.y);
			if (i == 0) {
				crest = d * lod;
			}
		}
		len *= OCT_LEN;
		amp *= OCT_AMP;
		choppy = mix(choppy, 1.0, 0.25);
	}
	slope = vec2(wind.x * gq.x - wind.y * gq.y, wind.y * gq.x + wind.x * gq.y);
	return h;
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Gap between the nearest and second-nearest cell points: near zero along cell
// borders, so thresholding it draws a web of lines.
float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = g + hash22(i + g) - f;
			float d = dot(o, o);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

// Flecks of foam: a dot in some cells of a jittered grid, sized per cell.
// `density` (0..1) is the share of cells that carry one. Returns 0..1 coverage.
float flecks(vec2 p, float density, float aa) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float m = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 h = hash22(i + g);
			float r = (0.15 + 0.35 * h.y) * smoothstep(1.0 - density, 1.0 - density * 0.6, h.x);
			float d = length(g + h - f);
			m = max(m, 1.0 - smoothstep(r - aa, r + aa, d));
		}
	}
	return m;
}

// Marbled churn pattern, about -1..1, finer octaves faded out by `lod`.
float marble(vec2 q, float lod) {
	return gnoise(q * vec2(1.0, 0.55)) * 0.55 + gnoise(q * vec2(2.4, 1.5) + 4.0) * 0.3 * lod
			+ gnoise(q * vec2(5.5, 3.6) + 9.0) * 0.15 * lod;
}

const int WAKE_SLOTS = 16;
const int WAKE_PTS = 48;
// tan(19.47°): the Kelvin wedge every ship's wake spreads in, drawn out to
// KELVIN_REACH metres behind the bow. Everything the wake draws lies within
// 1.1 × the wedge's half-width (+3 m), which WakeField's bounds also cover.
// The reach scales with the vessel's Kelvin wave scale.
const float KELVIN_SPREAD = 0.354;
const float KELVIN_REACH = 180.0;

float wake_spd(int i) {
	vec4 v = wake_speed[i / 4];
	int c = i % 4;
	return c == 0 ? v.x : (c == 1 ? v.y : (c == 2 ? v.z : v.w));
}

// Prop wash: a churned band streaming away from a propeller that widens as it
// ages. Used for the stern props' wake and, mirrored, the forward prop's reverse
// thrust into the dock. `alat`/`side` are the distance and side across the band,
// `s` a position along it anchored to the water, `behind` the distance from the
// prop, `along` the same but signed (for the start fade), `age` how long ago that
// water was churned and `strength` 0..1. `dir` points back towards the prop. `gw`
// scales how much it roughens the surface, for when two stretches cross-fade.
// `vio` scales how violently the water moves within the wash (1 = stern props).
// `hw` is the vessel's half beam, which sets how wide the band starts.
void prop_wash(float hw, float alat, float side, float s, float behind, float along, float age, float strength,
		vec2 perp, vec2 dir, vec2 ride, float t, float lod, float gw, float vio, inout float foam, inout float aer, inout vec2 grad) {
	// Behind the source it boils: the foam is carried round by a swirling flow,
	// upwellings burst up through it and spread, and the edges heave. Further
	// back the churn calms, holes open into drifting patches, then lace, then
	// nothing. Bubbly turquoise water shows through and spreads wider.
	float wc = hw * (0.75 + 0.13 * sqrt(behind));
	float energy = exp(-age / 5.0);
	float edge = gnoise(vec2(s * 0.07, side * 3.0 + t * 0.12)) * 0.3
			+ gnoise(vec2(s * 0.3 - t * 0.6, side * 7.0)) * 0.14 * lod;
	float start = smoothstep(-2.0, 1.5, along);
	float life = strength * exp(-age / wake_life);
	float churn = (1.0 - smoothstep(0.45, 1.05, alat / wc + edge)) * start * life;
	// Foam frame: across in units of the band's width, so the pattern spreads
	// outwards as the band widens, and along in metres.
	vec2 q = vec2(side * alat / wc * 2.2, s * 0.32);
	// The foam rides the ripples: it slides about on their slopes.
	q += vec2(dot(ride, perp) * side, dot(ride, dir)) * 0.9;
	// Flow-mapped churn: the pattern is pushed along a swirling field, harder
	// the fresher the water; two copies half a cycle apart are cross-faded so
	// it keeps moving without ever smearing out.
	vec2 swirl = vec2(gnoise(q * 0.7 + vec2(3.1, t * 0.08 * vio)), gnoise(q * 0.7 + vec2(8.7, -t * 0.08 * vio))) * (0.4 + 2.2 * energy) * vio;
	float fp_ph = fract(t * 0.3 * vio);
	float w = abs(fp_ph * 2.0 - 1.0);
	vec2 qa = q + swirl * fp_ph;
	vec2 qb = q + swirl * fract(fp_ph + 0.5) + vec2(17.3, 5.1);
	float mn = mix(marble(qa, lod), marble(qb, lod), w) * 1.2;
	float fine = mix(gnoise(qa * vec2(5.0, 3.0) + 11.0), gnoise(qb * vec2(5.0, 3.0) + 11.0), w) * lod;
	// Upwellings: patches of fresh foam that well up and spread, each on its
	// own clock.
	vec2 bc = vec2(side * alat, s) / 3.2;
	vec2 bh = hash22(floor(bc));
	float bp = fract(t * (0.3 + 0.35 * bh.x) * vio + bh.y);
	float bd = length(fract(bc) - 0.5 - (bh - 0.5) * 0.25);
	float boil = (1.0 - smoothstep(bp * 0.42 - 0.06, bp * 0.42, bd)) * (1.0 - bp) * energy * churn;
	// Foam mass in two layers: a thin, see-through sheet and thick white boil on
	// top. Holes open where the marbling dips as the churn thins, and fine
	// noise pocks both so the foam has texture rather than a flat fill. The
	// marbling only shapes foam that the churn put there: its peaks alone would
	// cross the threshold, leaving foam out to wherever the wash is drawn at all,
	// cut off sharply where it stops.
	float v = churn * 1.05 + mn * 0.55 * smoothstep(0.0, 0.35, churn) + boil * 0.5;
	float thin = smoothstep(0.36, 0.5, v + fine * 0.12);
	float thick = smoothstep(0.6, 0.72, v + fine * 0.28);
	float mass = thin * 0.5 + thick * 0.5;
	// Lace: cell borders drawn out into streaks, carried by the same flow,
	// strung between the masses and gone before the foam is.
	float ce = mix(cell_edge(qa * vec2(1.4, 0.42)), cell_edge(qb * vec2(1.4, 0.42)), w);
	float web = (1.0 - smoothstep(0.02, 0.02 + 0.12 * churn, ce)) * lod;
	float lace = web * smoothstep(0.18, 0.45, churn) * smoothstep(-0.2, 0.25, mn);
	float wash = max(mass, lace * 0.7);
	// Scum: crisp flecks and threads of foam floating on the surface, drawn out
	// along the track and carried by the same flow, so the wake has a top and
	// doesn't read as all under water. Thickest where it's freshest.
	float scum_d = clamp(churn * (1.3 + mn * 0.8), 0.0, 1.0) * (0.45 + 0.55 * energy);
	float faa = 0.12;
	float scum = mix(flecks(qa * vec2(4.0, 1.6) + 31.0, scum_d, faa), flecks(qb * vec2(4.0, 1.6) + 31.0, scum_d, faa), w)
			* 0.85 + 0.5 * mix(flecks(qa * vec2(9.0, 3.5), scum_d, faa), flecks(qb * vec2(9.0, 3.5), scum_d, faa), w);
	wash = max(wash, clamp(scum, 0.0, 1.0) * lod);

	foam = max(foam, wash);
	float wide = (1.0 - smoothstep(0.6, 1.35, alat / wc + edge)) * start * strength * exp(-age / (wake_life * 2.0));
	// Bubbles under and around each patch of foam: a soft, brighter halo that
	// ties the foam into the water instead of sitting on top of it.
	float halo = smoothstep(0.12, 0.45, v + fine * 0.1) * (1.0 - thick * 0.5) * smoothstep(0.0, 0.25, churn);
	aer = max(aer, max(wide * 0.6, halo));
	// Churned water: an animated, confused chop, strongest where it's freshest,
	// so the water around the foam is visibly stirred up and catches the light.
	vec2 cc = vec2(side * alat, s) * 1.7;
	float tc = t * vio;
	vec2 chop2 = vec2(gnoise(cc + vec2(0.0, tc * 1.4)), gnoise(cc + vec2(tc * 1.2, 9.0)))
			+ 0.5 * vec2(gnoise(cc * 2.3 - vec2(tc * 2.0, 0.0)), gnoise(cc * 2.3 + vec2(4.0, tc * 1.8))) * lod;
	float stir = max(wide, halo) * (0.35 + 0.65 * energy);
	grad += (perp * chop2.x + dir * chop2.y) * 0.4 * stir * gw * sqrt(vio);
	// Churned water and foam are a jumble of little facets, heaving with the flow.
	vec2 jn = mix(vec2(gnoise(qa * 2.0 + 40.0), gnoise(qa * 2.0 + 57.0)),
			vec2(gnoise(qb * 2.0 + 40.0), gnoise(qb * 2.0 + 57.0)), w) * lod;
	grad += (perp * jn.x + dir * jn.y) * (0.3 * churn + 0.35 * wash) * gw * sqrt(vio);
}

// Trail values at segment `i`, `raw` of the way from its newer end to its older:
// distance along the trail (carried on past the ends, so it keeps running round
// the outside of a bend), age, speed fraction and the fade towards the trail's
// end. The wake fades out by age before its breadcrumbs expire, so nothing pops
// when the oldest is dropped, and rounds off softly past the last one.
void trail_at(int base, int i, int n, float raw, float span, out float s, out float age, out float spd, out float tail) {
	vec4 A = wake_pts[base + i];
	vec4 B = wake_pts[base + i + 1];
	float tt = clamp(raw, 0.0, 1.0);
	s = mix(A.z, B.z, clamp(raw, -0.5, 1.5));
	age = mix(A.w, B.w, tt);
	spd = mix(wake_spd(base + i), wake_spd(base + i + 1), tt);
	tail = 1.0 - smoothstep(0.6, 1.0, age / span);
	if (i == n - 2 && raw > 1.0) {
		tail *= 1.0 - smoothstep(0.0, 5.0, (raw - 1.0) * length(B.xy - A.xy));
	}
}

// How strongly a stretch of prop wash reaches `alat` metres to its side: its
// widest, longest-lived layer (the aerated water in prop_wash), out to as far as
// its noisy edge can reach.
float wash_reach(float hw, float alat, float along, float age, float strength) {
	float wc = hw * (0.75 + 0.13 * sqrt(max(along, 0.0)));
	return (1.0 - smoothstep(0.6, 1.85, alat / wc)) * smoothstep(-2.0, 1.5, along) * strength * exp(-age / (wake_life * 2.0));
}

// How much of a stretch of prop wash still shows `raw` of the way along its
// segment (of length `seg`): all of it between the ends, fading out a little way
// past them. Short segments reach less far past their ends, or the tight arc a
// boat leaves coming about would fan out into spokes.
float end_fade(float raw, float seg, float hw) {
	float over = max(-raw, raw - 1.0) * seg;
	return 1.0 - smoothstep(0.0, min(1.5 + hw, seg * 0.5 + 0.4), over);
}

// Wakes at world xz `p`. Adds the wake waves' slope to `grad` and returns foam
// (0..1) and aeration (0..1, the turquoise of bubbly water).
// `ride` is the wind waves' slope here, which the foam is carried about on.
void wakes(vec2 p, float fp, float t, vec2 ride, inout vec2 grad, out float foam, out float aer) {
	foam = 0.0;
	aer = 0.0;
	float lod = clamp(0.5 / fp - 0.3, 0.0, 1.0);
	for (int f = 0; f < WAKE_SLOTS; f++) {
		if (f >= wake_count) {
			break;
		}
		vec4 box = wake_box[f];
		if (p.x < box.x || p.y < box.y || p.x > box.z || p.y > box.w) {
			continue;
		}
		int n = int(wake_info[f].y);
		int base = f * WAKE_PTS;
		vec4 hull = wake_hull[f];
		float hw = hull.x;
		float hull_len = hull.y;
		float wash_str = hull.z;
		float ks = hull.w;
		vec4 shape = wake_shape[f];

		// Reverse thrust: from the outer dolphins in, the forward prop throws the
		// same churned wash out ahead of the bow, streaming forwards into the slip.
		float thrust = wake_info[f].w;
		if (thrust > 0.0) {
			vec2 bow_p = wake_pts[base].xy;
			vec2 fdir = normalize(bow_p - wake_pts[base + 1].xy + vec2(1e-5, 0.0));
			vec2 fperp = vec2(-fdir.y, fdir.x);
			vec2 rel = p - bow_p;
			float ah = dot(rel, fdir);
			float fl = dot(rel, fperp);
			// Reaches further the longer the prop has been running.
			float reach = 3.0 + 9.0 * thrust;
			if (ah > -3.0 && ah < reach + 4.0 && abs(fl) < 16.0) {
				// The wash creeps out slowly but boils hard within: its foam drifts
				// forwards at JET_SPEED, while it ages as if thrown out at JET_AGE
				// so it stays fresh and violent all the way out.
				const float JET_SPEED = 0.9;
				const float JET_AGE = 2.5;
				const float JET_VIO = 2.2;
				float fstr = thrust * (1.0 - smoothstep(reach * 0.55, reach, ah));
				// Fans out into a cone: ~50% wider at the far end than at the bow.
				float cone = 1.0 + 0.5 * clamp(ah / reach, 0.0, 1.0);
				prop_wash(hw, abs(fl) / cone, fl < 0.0 ? -1.0 : 1.0, dot(p, fdir) - t * JET_SPEED, max(ah, 0.0), ah,
						max(ah, 0.0) / JET_AGE, fstr, fperp, -fdir, ride, t, lod, 1.0, JET_VIO, foam, aer, grad);
			}
		}

		float odo = wake_info[f].x;
		float span = max(wake_info[f].z, 1.0);
		// The nearest point on the trail places the ferry's own hull foam and Kelvin
		// waves. The prop wash instead comes from whichever stretches of trail reach
		// here strongest: old foam spreads wide, so where the ferry has slowed down
		// (or turned back on itself) the older, wider foam still shows past the
		// newer stretch instead of being cut off along the line where it's nearer.
		float best = 1e12;
		int bi = 0;
		float bt = 0.0;
		float braw = 0.0;
		float c1 = 0.0;
		int i1 = -1;
		float r1 = 0.0;
		float c2 = 0.0;
		int i2 = -1;
		float r2 = 0.0;
		for (int i = 0; i < WAKE_PTS - 1; i++) {
			if (i >= n - 1) {
				break;
			}
			vec2 a = wake_pts[base + i].xy;
			vec2 ab = wake_pts[base + i + 1].xy - a;
			vec2 ap = p - a;
			float raw = dot(ap, ab) / max(dot(ab, ab), 1e-4);
			float tt = clamp(raw, 0.0, 1.0);
			vec2 d = ap - ab * tt;
			float dd = dot(d, d);
			if (dd < best) {
				best = dd;
				bi = i;
				bt = tt;
				braw = raw;
			}
			// Measured straight across the segment's line rather than to its
			// nearest point, so neighbouring segments overlap and blend at their
			// joints, and only reaching a little past its ends. (Measured to the
			// nearest point, an older, wider segment's rounded end pokes out past
			// the joint into the next one, leaving a ring of foam at every crumb.)
			float seg = sqrt(max(dot(ab, ab), 1e-6));
			float lat = abs(ap.x * ab.y - ap.y * ab.x) / seg;
			float ts, tage, tspd, ttail;
			trail_at(base, i, n, raw, span, ts, tage, tspd, ttail);
			float cov = wash_reach(hw, lat, odo - ts, tage, tspd * ttail * wash_str) * end_fade(raw, seg, hw);
			if (cov > c1) {
				c2 = c1;
				i2 = i1;
				r2 = r1;
				c1 = cov;
				i1 = i;
				r1 = raw;
			} else if (cov > c2) {
				c2 = cov;
				i2 = i;
				r2 = raw;
			}
		}

		// Prop wash from the strongest stretch, and where a second one reaches
		// nearly as far, from that too, so the two cross-fade instead of meeting
		// in a seam.
		float w2 = c2 > 0.0 ? 0.5 * smoothstep(0.4, 1.0, c2 / c1) : 0.0;
		for (int k = 0; k < 2; k++) {
			int wi = k == 0 ? i1 : i2;
			float wr = k == 0 ? r1 : r2;
			if (wi < 0 || (k == 1 && w2 <= 0.0)) {
				continue;
			}
			vec4 WA = wake_pts[base + wi];
			vec4 WB = wake_pts[base + wi + 1];
			vec2 wab = WB.xy - WA.xy;
			vec2 wdir = normalize(-wab + vec2(1e-5, 0.0));
			vec2 wperp = vec2(-wdir.y, wdir.x);
			float wlat = dot(p - WA.xy, wperp);
			float wfade = end_fade(wr, length(wab), hw);
			float ws, wage, wspd, wtail;
			trail_at(base, wi, n, wr, span, ws, wage, wspd, wtail);
			float walong = odo - ws;
			// Gentler wash churns more calmly too.
			prop_wash(hw, abs(wlat), wlat < 0.0 ? -1.0 : 1.0, ws, max(walong, 0.0), walong, wage,
					wspd * wtail * wash_str * wfade, wperp, wdir, ride, t, lod, k == 0 ? 1.0 - w2 : w2, max(wash_str, 0.3), foam, aer, grad);
		}

		vec4 A = wake_pts[base + bi];
		vec4 B = wake_pts[base + bi + 1];
		// Points run backwards along the trail, so the ferry heads from B to A.
		vec2 dir = normalize(A.xy - B.xy + vec2(1e-5, 0.0));
		vec2 perp = vec2(-dir.y, dir.x);
		float side = dot(p - A.xy, perp) < 0.0 ? -1.0 : 1.0;
		float alat = sqrt(best);
		float s, age, spd, tail;
		trail_at(base, bi, n, braw, span, s, age, spd, tail);
		// Where the nearest segment switches on a bend, the two segments disagree
		// a little about s, which would leave a seam in the Kelvin waves. Blend
		// towards the neighbouring segment's answer near the switch.
		int nb = braw < 0.5 ? bi - 1 : bi + 1;
		if (nb >= 0 && nb < n - 1) {
			vec4 C = wake_pts[base + nb];
			vec4 D = wake_pts[base + nb + 1];
			vec2 cd = D.xy - C.xy;
			float nraw = dot(p - C.xy, cd) / max(dot(cd, cd), 1e-4);
			float nd = length(p - C.xy - cd * clamp(nraw, 0.0, 1.0));
			float ns = mix(C.z, D.z, clamp(nraw, -0.5, 1.5));
			s = mix(ns, s, 0.5 + 0.5 * smoothstep(0.0, 4.0, nd - alat));
		}
		// Metres behind the stern (negative alongside the hull and ahead of the bow).
		float along = odo - s;
		float from_bow = along + hull_len;
		float reach = KELVIN_REACH * ks;
		float wk = hw + clamp(from_bow, 0.0, reach) * KELVIN_SPREAD;
		if (alat > wk * 1.1 + 3.0 || from_bow < -6.0 || spd <= 0.0 || tail <= 0.0) {
			continue;
		}
		// Trail frame, fixed in the world: across, and along the path travelled.
		vec2 c = vec2(side * alat, s);

		// Kelvin waves: feathered divergent crests bunched along the edges of the
		// wedge (outer end trailing, ~55° to the track), and gentler transverse
		// crests across it. They hold their place relative to the vessel. Bigger
		// hulls make longer, taller waves; small ones shorter and gentler ones.
		float kel = spd * tail * exp(-age / kelvin_life) * smoothstep(-2.0, 4.0, from_bow)
				* (1.0 - smoothstep(reach * 0.6, reach, from_bow)) / (1.0 + from_bow * 0.012 / ks);
		float k = TAU / (kelvin_wavelength * ks);
		float kh = kelvin_height * ks * sqrt(ks);
		float x = alat / wk;
		float div_env = smoothstep(0.45, 0.92, x) * (1.0 - smoothstep(0.97, 1.08, x));
		float ph = k * (from_bow * 0.82 - alat * 0.57) - t * 0.6;
		float e = exp(1.6 * (sin(ph) - 1.0));
		vec2 dph = k * (-0.82 * dir - 0.57 * side * perp);
		grad += kh * kel * div_env * e * 1.6 * cos(ph) * dph;
		float tr_env = (1.0 - smoothstep(0.55, 0.9, x)) * smoothstep(0.0, 8.0, along);
		float pt = k * 0.75 * (from_bow + alat * alat * 0.015 / ks);
		grad += kh * 0.45 * kel * tr_env * cos(pt) * k * 0.75 * (-dir + side * perp * alat * 0.03 / ks);
		// Right at the edge of the wedge, near the vessel, the divergent crests break
		// into thin broken lines of white.
		float streak = gnoise(c * vec2(0.9, 0.3) + 21.0) * 0.5 + gnoise(c * vec2(2.3, 0.8) + 5.0) * 0.3 * lod;
		float crest_foam = smoothstep(0.88, 0.99, e) * smoothstep(0.8, 0.97, x) * (1.0 - smoothstep(1.0, 1.06, x))
				* smoothstep(0.05, 0.35, streak) * kel * exp(-age / 6.0) * (1.0 - smoothstep(25.0 * ks, 50.0 * ks, from_bow));

		// The hull's outline: full beam amidships, narrowing to the stem and stern.
		float sc = clamp(hw / 4.2, 0.2, 1.0);
		float fb = from_bow;
		float bu = clamp(1.0 - fb / shape.x, 0.0, 1.0);
		float su = clamp(1.0 - (hull_len - fb) / max(shape.z, 0.1), 0.0, 1.0);
		float hull_w = hw * mix(1.0, shape.y, pow(bu, 2.5)) * mix(1.0, shape.w, su * su);
		float stem_w = hw * shape.y;
		// Distance out from the hull's side (rounded round the stem ahead of it).
		float out_d = fb < 0.0 ? length(vec2(max(alat - stem_w, 0.0), fb)) : alat - hull_w;
		float hn = (gnoise(c * vec2(1.4, 0.5) + vec2(0.0, -t * 2.0)) * 0.6 + gnoise(c * 3.1 + vec2(t * 0.7, 2.0)) * 0.4 * lod) * 0.5;

		// Water heaped up against the stem: a thin, bright cushion right ahead
		// of it, thickest at the stem and thinning along the flare of the bow.
		float at_bow = 1.0 - smoothstep(0.0, shape.x * 0.9 + 1.0, fb);
		// Pocked with holes along the flanks, so it reads as foam, not a sheet.
		float thick = (0.3 + (0.6 + 0.9 * spd) * at_bow) * sc;
		float pock = gnoise(c * vec2(2.6, 1.1) + vec2(0.0, -t * 1.5)) * lod * (1.0 - at_bow * 0.7);
		float hug = smoothstep(0.4, 0.55, 1.0 - out_d / thick + hn + pock * 0.35) * (1.0 - smoothstep(-1.5 * sc, 0.0, along));

		// The bow wave proper: a breaking crest thrown off each side of the stem
		// that runs out and back at a steeper angle than the hull flares, so it
		// leaves the side where the bow meets the parallel body, then spreads,
		// breaks up into patches and fades: the bow's "moustache".
		float fade = hull_len * 0.3 + 6.0 * sc;
		float ridge_x = max(hull_w + 0.3 * sc, stem_w + max(fb, 0.0) * 0.7);
		float rw = (0.6 + 0.08 * max(fb, 0.0)) * sc;
		float rn = gnoise(c * vec2(0.8, 0.35) + vec2(3.0, -t * 0.4)) * 0.6 + gnoise(c * vec2(2.2, 1.0) + vec2(t * 0.5, 7.0)) * 0.4 * lod;
		float rlife = (1.0 - smoothstep(fade * 0.4, fade, fb)) * smoothstep(-1.0 * sc, 0.5 * sc, fb);
		float ridge = (1.0 - smoothstep(0.0, rw, abs(alat - ridge_x) + rn * rw * 0.6)) * rlife;
		// Breaks into patches as it ages: more of it drops out further back.
		ridge *= smoothstep(0.15 + 0.55 * fb / fade, 0.35 + 0.55 * fb / fade, rn * 0.5 + 0.55);
		// Between the crest and the hull: churned, bubbly water with a little
		// broken foam, filling the V the crest opens up.
		float inside = smoothstep(-0.3 * sc, 0.4 * sc, out_d) * (1.0 - smoothstep(-0.5 * rw, 0.3 * rw, alat - ridge_x));
		float fill = inside * rlife * (1.0 - smoothstep(0.0, fade * 0.6, fb));
		float bubbles = fill * smoothstep(0.55, 0.75, rn * 0.5 + 0.5 + fill * 0.2);
		float bw = max(ridge, bubbles * 0.7) * spd;
		hug = max(hug * spd * mix(0.3, 1.0, sc), bw * mix(0.3, 1.0, sc));
		aer = max(aer, fill * spd * 0.5);

		foam = max(foam, max(hug, crest_foam));
		aer = max(aer, hug * 0.6);
	}
}

float swell(vec2 p, float t) {
	return gnoise(p * 0.011 + vec2(0.05, 0.02) * t) + 0.5 * gnoise(p * 0.027 - vec2(0.03, 0.07) * t + 7.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge = max(abs(world_pos.x), abs(world_pos.z));
	float h = swell(world_pos.xz, TIME) * swell_height * (1.0 - smoothstep(swell_extent - 80.0, swell_extent - 10.0, edge));
	VERTEX.y += h;
	world_pos.y += h;
}

vec3 view_to_world(vec2 uv, float raw_depth, mat4 inv_proj, mat4 inv_view) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	return (inv_view * vec4(v.xyz / v.w, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float dist = length(VERTEX);
	// Orthographic views (the minimap) get flat, calm water.
	float ortho = step(0.5, PROJECTION_MATRIX[3][3]);
	vec2 wind = normalize(cloud_wind + vec2(1e-4, 0.0));
	float fp = mix(max(length(fwidth(p)), 1e-4), 1e4, ortho);

	float gust = gnoise(p / gust_size + wind * t * 0.01) * 0.5
			+ gnoise(p / (gust_size * 0.37) - wind.yx * t * 0.015 + 5.0) * 0.25;
	gust = clamp(0.5 + gust * 0.8, 0.0, 1.0);

	float crest, lost;
	vec2 grad;
	waves(p, wind, t, fp, gust, crest, lost, grad);
	grad *= normal_strength;
	float wake_foam, aer;
	vec2 wake_grad = vec2(0.0);
	wakes(p, fp, t, grad, wake_grad, wake_foam, aer);
	// The wake's own churn takes over from the wind chop.
	grad = grad * (1.0 - 0.4 * aer) + wake_grad;
	vec3 wn = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	flat_normal = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	// What lies under the water here: vertical depth for foam, and the path length
	// the light crosses for absorption.
	vec3 floor_pos = view_to_world(SCREEN_UV, texture(depth_texture, SCREEN_UV).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float depth = max(world_pos.y - floor_pos.y, 0.0);

	// Refract the view of the floor by the ripples (less with distance, none where
	// the water is too thin to bend anything). If the bent ray lands on something
	// above the water, fall back to the straight view.
	vec2 bend = (NORMAL.xy - flat_normal.xy) * refraction * clamp(depth, 0.0, 2.0) * (30.0 / (30.0 + dist));
	vec2 ruv = SCREEN_UV + bend;
	vec3 rpos = view_to_world(ruv, texture(depth_texture, ruv).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (rpos.y > world_pos.y - 0.02) {
		ruv = SCREEN_UV;
		rpos = floor_pos;
	}
	float path = min(distance(rpos, world_pos), 500.0);
	vec3 trans = exp(-absorption * path);
	float scatter = 1.0 - exp(-turbidity * path);
	vec3 floor_col = textureLod(screen_texture, ruv, 0.0).rgb;

	// Foam: a crisp, lacy lip on everything the water touches, and broken bands
	// washing in behind it.
	float foam_lod = clamp(0.6 / fp - 0.5, 0.0, 1.0);
	float fn = (gnoise(p * 1.2 + wind * t * 0.17) * 0.6 + gnoise(p * 2.9 - wind * t * 0.28 + 3.0) * 0.3) * foam_lod;
	float lip = 1.0 - smoothstep(0.0, foam_width, depth);
	float band = (0.5 + 0.5 * sin(depth * 5.0 + t * 1.0 + fn * 2.5)) * (1.0 - smoothstep(0.0, foam_width * 3.5, depth)) * 0.75;
	float cover = max(lip * lip, band) * 1.1 + fn * 0.8 + (crest - 1.0) * 0.12;
	float aa = max(fwidth(cover), 0.02);
	float foam = smoothstep(0.55 - aa, 0.55 + aa, cover) * (1.0 - ortho);
	if (seal_count > 0 && all(greaterThan(p, seal_bounds.xy)) && all(lessThan(p, seal_bounds.zw))) {
		float clear = 0.0;
		for (int i = 0; i < seal_count; i++) {
			vec4 b = seal_body[i];
			vec2 rel = p - b.xy;
			float h = clamp(dot(rel, b.zw) / max(dot(b.zw, b.zw), 1e-4), -1.0, 1.0);
			float r = 0.3 * length(b.zw) + 0.12;
			clear = max(clear, 1.0 - smoothstep(r, r + 0.4, length(rel - b.zw * h)));
		}
		foam *= 1.0 - clear;
	}
	foam = max(foam, wake_foam);

	float cloud = cloud_shadow(world_pos, TIME);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - nv, 5.0);

	// Rougher gust patches catch a little more light, so open water isn't flat from afar.
	vec3 body = mix(scatter_color.rgb * scatter * mix(0.88, 1.12, gust), wake_aerated.rgb, aer * 0.8);
	// Thin foam is a little greyer than thick.
	ALBEDO = mix(body, foam_color.rgb * mix(0.8, 1.0, foam), foam);
	// The floor was already lit when it was drawn, so it goes in as emission.
	EMISSION = floor_col * trans * (1.0 - fresnel) * (1.0 - foam) * (1.0 - aer * 0.7);
	ALPHA = 1.0;
	// Slope lost to dropped octaves widens the highlight instead.
	float r = sqrt(roughness * roughness + lost * lost * 6.0);
	ROUGHNESS = mix(mix(r, 1.0, foam), 1.0, ortho);
	SPECULAR = 0.5 * (1.0 - foam) * (1.0 - ortho);
	cloud_lit = 1.0 - cloud * 0.8;
	foam_amt = foam;
	glint_vis = clamp(1.0 - cloud * 1.2, 0.0, 1.0) * (1.0 - foam) * (1.0 - ortho);
}

void light() {
	vec3 lit = ATTENUATION * LIGHT_COLOR;
	// The water body scatters light from within; shading it by the ripples is what
	// makes a liquid read as plastic. Foam sits on the surface, so it does catch
	// the light on its lumps and the slopes of the waves it rides.
	vec3 dn = normalize(mix(flat_normal, NORMAL, foam_amt * 0.8));
	DIFFUSE_LIGHT += clamp(dot(dn, LIGHT), 0.0, 1.0) * lit * cloud_lit / PI;
	// Sun glints: GGX on the rippled normal.
	vec3 hv = normalize(LIGHT + VIEW);
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float nv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = nh * nh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float V = 0.25 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k));
	float F = 0.02 + 0.98 * pow(1.0 - clamp(dot(VIEW, hv), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += D * V * F * nl * lit * glint_vis;
}
