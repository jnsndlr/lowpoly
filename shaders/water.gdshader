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

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
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

group_uniforms swell;
uniform float swell_height = 0.2;
// Half-size of the subdivided plane; swell flattens out before its edge so it
// meets the flat horizon ring without cracks.
uniform float swell_extent = 100000.0;

group_uniforms wake;
// Ferry wakes. WakeField packs each ferry's trail every frame: points run from the
// bow, to the stern, then back along the breadcrumbs it has dropped, as
// (x, z, distance along the trail, age in seconds), with the ferry's speed at each
// as a fraction of cruise. wake_box is each trail's bounds (wake included) and
// wake_info.xyz its current odometer, point count and how long (s) breadcrumbs live.
uniform vec4 wake_aerated : source_color = vec4(0.1, 0.5, 0.47, 1.0);
// Seconds for the churned foam to break up and fade, and for the Kelvin waves.
uniform float wake_life = 10.0;
uniform float kelvin_life = 14.0;
uniform float kelvin_wavelength = 5.5;
uniform float kelvin_height = 0.2;
uniform int wake_count = 0;
uniform vec4 wake_box[8];
uniform vec4 wake_info[8];
uniform vec4 wake_pts[384];
uniform float wake_speed[384];
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

// One choppy octave, 0..1: sharp ridges along a warped grid with rounded troughs
// between them. The noise warp is at the same scale as the ridges, so they bend,
// split and merge instead of lining up.
float chop(vec2 uv, float choppy) {
	uv += gnoise(uv) * 0.9;
	vec2 wv = 1.0 - abs(sin(uv));
	vec2 swv = abs(cos(uv));
	wv = mix(wv, swv, wv);
	return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
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
// dropped octaves would have added.
float waves(vec2 p, vec2 wind, float t, float fp, float gust, out float crest, out float lost) {
	// Wind frame: x downwind, y across.
	vec2 q0 = vec2(dot(p, wind), dot(p, vec2(-wind.y, wind.x)));
	float len = wave_length;
	float amp = wave_amp;
	float choppy = choppiness;
	float h = 0.0;
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
			float d = chop(uv - vec2(travel, 0.0), choppy);
			d += chop(mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * uv + vec2(-0.8 * travel, 0.3 * travel) + 11.0, choppy);
			h += d * a * lod;
			if (i == 0) {
				crest = d * lod;
			}
		}
		len *= OCT_LEN;
		amp *= OCT_AMP;
		choppy = mix(choppy, 1.0, 0.25);
	}
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

// Marbled churn pattern, about -1..1, finer octaves faded out by `lod`.
float marble(vec2 q, float lod) {
	return gnoise(q * vec2(1.0, 0.55)) * 0.55 + gnoise(q * vec2(2.4, 1.5) + 4.0) * 0.3 * lod
			+ gnoise(q * vec2(5.5, 3.6) + 9.0) * 0.15 * lod;
}

const int WAKE_FERRIES = 8;
const int WAKE_PTS = 48;
// Ferry hull: half beam, and length from bow to stern.
const float HULL_HW = 4.2;
const float HULL_LEN = 30.0;
// tan(19.47°): the Kelvin wedge every ship's wake spreads in, drawn out to
// KELVIN_REACH metres behind the bow. Everything the wake draws lies within
// 1.1 × the wedge's half-width (+3 m), which WakeField's bounds also cover.
const float KELVIN_SPREAD = 0.354;
const float KELVIN_REACH = 180.0;

// Wakes at world xz `p`. Adds the wake waves' slope to `grad` and returns foam
// (0..1) and aeration (0..1, the turquoise of bubbly water).
// `ride` is the wind waves' slope here, which the foam is carried about on.
void wakes(vec2 p, float fp, float t, vec2 ride, inout vec2 grad, out float foam, out float aer) {
	foam = 0.0;
	aer = 0.0;
	float lod = clamp(0.5 / fp - 0.3, 0.0, 1.0);
	for (int f = 0; f < WAKE_FERRIES; f++) {
		if (f >= wake_count) {
			break;
		}
		vec4 box = wake_box[f];
		if (p.x < box.x || p.y < box.y || p.x > box.z || p.y > box.w) {
			continue;
		}
		int n = int(wake_info[f].y);
		int base = f * WAKE_PTS;
		// Nearest point on the trail.
		float best = 1e12;
		int bi = 0;
		float bt = 0.0;
		float braw = 0.0;
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
		}
		vec4 A = wake_pts[base + bi];
		vec4 B = wake_pts[base + bi + 1];
		// Points run backwards along the trail, so the ferry heads from B to A.
		vec2 dir = normalize(A.xy - B.xy + vec2(1e-5, 0.0));
		vec2 perp = vec2(-dir.y, dir.x);
		float side = dot(p - A.xy, perp) < 0.0 ? -1.0 : 1.0;
		float alat = sqrt(best);
		// Distance along the trail, carried on past the segment ends so it keeps
		// running around the outside of a bend (and past the bow and tail) instead
		// of freezing at the corner and smearing the foam outwards.
		float s = mix(A.z, B.z, clamp(braw, -0.5, 1.5));
		float age = mix(A.w, B.w, bt);
		float spd = mix(wake_speed[base + bi], wake_speed[base + bi + 1], bt);
		// Metres behind the stern (negative alongside the hull and ahead of the bow).
		float along = wake_info[f].x - s;
		// The wake fades out by age before its breadcrumbs expire, so nothing pops
		// when the oldest is dropped, and rounds off softly past the last one
		// (where every pixel is nearest the same point).
		float tail = 1.0 - smoothstep(0.6, 1.0, age / max(wake_info[f].z, 1.0));
		if (bi == n - 2 && braw > 1.0) {
			tail *= 1.0 - smoothstep(0.0, 5.0, (braw - 1.0) * length(B.xy - A.xy));
		}
		float from_bow = along + HULL_LEN;
		float wk = HULL_HW + clamp(from_bow, 0.0, KELVIN_REACH) * KELVIN_SPREAD;
		if (alat > wk * 1.1 + 3.0 || from_bow < -6.0 || spd <= 0.0 || tail <= 0.0) {
			continue;
		}
		// Trail frame, fixed in the world: across, and along the path travelled.
		vec2 c = vec2(side * alat, s);
		float behind = max(along, 0.0);

		// Kelvin waves: feathered divergent crests bunched along the edges of the
		// wedge (outer end trailing, ~55° to the track), and gentler transverse
		// crests across it. They hold their place relative to the ferry.
		float kel = spd * tail * exp(-age / kelvin_life) * smoothstep(-2.0, 4.0, from_bow)
				* (1.0 - smoothstep(KELVIN_REACH * 0.6, KELVIN_REACH, from_bow)) / (1.0 + from_bow * 0.012);
		float k = TAU / kelvin_wavelength;
		float x = alat / wk;
		float div_env = smoothstep(0.45, 0.92, x) * (1.0 - smoothstep(0.97, 1.08, x));
		float ph = k * (from_bow * 0.82 - alat * 0.57) - t * 0.6;
		float e = exp(1.6 * (sin(ph) - 1.0));
		vec2 dph = k * (-0.82 * dir - 0.57 * side * perp);
		grad += kelvin_height * kel * div_env * e * 1.6 * cos(ph) * dph;
		float tr_env = (1.0 - smoothstep(0.55, 0.9, x)) * smoothstep(0.0, 8.0, along);
		float pt = k * 0.75 * (from_bow + alat * alat * 0.015);
		grad += kelvin_height * 0.45 * kel * tr_env * cos(pt) * k * 0.75 * (-dir + side * perp * alat * 0.03);
		// Right at the edge of the wedge, near the ferry, the divergent crests break
		// into thin broken lines of white.
		float streak = gnoise(c * vec2(0.9, 0.3) + 21.0) * 0.5 + gnoise(c * vec2(2.3, 0.8) + 5.0) * 0.3 * lod;
		float crest_foam = smoothstep(0.88, 0.99, e) * smoothstep(0.8, 0.97, x) * (1.0 - smoothstep(1.0, 1.06, x))
				* smoothstep(0.05, 0.35, streak) * kel * exp(-age / 6.0);

		// Foam hugging the hull and piled up at the bow. The hull narrows at both
		// ends, and behind the stern this hands over to the prop wash.
		float hull_w = HULL_HW - 1.6 * smoothstep(HULL_LEN - 3.0, HULL_LEN, -along) - 1.6 * smoothstep(-3.0, 0.0, along);
		float bow = 1.0 - smoothstep(-2.0, 5.0, from_bow);
		float hn = (gnoise(c * vec2(1.4, 0.5) + vec2(0.0, -t * 2.0)) * 0.6 + gnoise(c * 3.1 + vec2(t * 0.7, 2.0)) * 0.4 * lod) * 0.5;
		// Ahead of the bow, measure from the blunt bow edge rather than its centre.
		float ahead = max(-from_bow, 0.0);
		float beam = sqrt(max(alat * alat - ahead * ahead, 0.0));
		float out_d = ahead > 0.0 ? length(vec2(max(beam - hull_w, 0.0), ahead)) : alat - hull_w;
		float near_hull = 1.0 - out_d / (0.6 + 0.9 * bow);
		float hug = smoothstep(0.4, 0.55, near_hull + hn) * (1.0 - smoothstep(-1.5, 0.0, along)) * spd;

		// Prop wash: a churned band from the stern that widens as it ages. Right
		// behind the stern it boils: the foam is carried round by a swirling flow,
		// upwellings burst up through it and spread, and the edges heave. Further
		// back the churn calms, holes open into drifting patches, then lace, then
		// nothing. Bubbly turquoise water shows through and spreads wider.
		float wc = HULL_HW * (0.75 + 0.13 * sqrt(behind));
		float energy = exp(-age / 5.0);
		float edge = gnoise(vec2(s * 0.07, side * 3.0 + t * 0.12)) * 0.3
				+ gnoise(vec2(s * 0.3 - t * 0.6, side * 7.0)) * 0.14 * lod;
		float start = smoothstep(-2.0, 1.5, along);
		float life = spd * tail * exp(-age / wake_life);
		float churn = (1.0 - smoothstep(0.45, 1.05, alat / wc + edge)) * start * life;
		// Foam frame: across in units of the band's width, so the pattern spreads
		// outwards as the band widens, and along in metres.
		vec2 q = vec2(side * alat / wc * 2.2, s * 0.32);
		// The foam rides the ripples: it slides about on their slopes.
		q += vec2(dot(ride, perp) * side, dot(ride, dir)) * 0.9;
		// Flow-mapped churn: the pattern is pushed along a swirling field, harder
		// the fresher the water; two copies half a cycle apart are cross-faded so
		// it keeps moving without ever smearing out.
		vec2 swirl = vec2(gnoise(q * 0.7 + vec2(3.1, t * 0.08)), gnoise(q * 0.7 + vec2(8.7, -t * 0.08))) * (0.4 + 2.2 * energy);
		float fp_ph = fract(t * 0.3);
		float w = abs(fp_ph * 2.0 - 1.0);
		vec2 qa = q + swirl * fp_ph;
		vec2 qb = q + swirl * fract(fp_ph + 0.5) + vec2(17.3, 5.1);
		float mn = mix(marble(qa, lod), marble(qb, lod), w) * 1.2;
		float fine = mix(gnoise(qa * vec2(5.0, 3.0) + 11.0), gnoise(qb * vec2(5.0, 3.0) + 11.0), w) * lod;
		// Upwellings: patches of fresh foam that well up and spread, each on its
		// own clock.
		vec2 bc = vec2(side * alat, s) / 3.2;
		vec2 bh = hash22(floor(bc));
		float bp = fract(t * (0.3 + 0.35 * bh.x) + bh.y);
		float bd = length(fract(bc) - 0.5 - (bh - 0.5) * 0.25);
		float boil = (1.0 - smoothstep(bp * 0.42 - 0.06, bp * 0.42, bd)) * (1.0 - bp) * energy * churn;
		// Foam mass in two layers: a thin, see-through sheet and thick white boil on
		// top. Holes open where the marbling dips as the churn thins, and fine
		// noise pocks both so the foam has texture rather than a flat fill.
		float v = churn * 1.05 + mn * 0.55 + boil * 0.5;
		float thin = smoothstep(0.36, 0.5, v + fine * 0.12);
		float thick = smoothstep(0.6, 0.72, v + fine * 0.28);
		float mass = thin * 0.5 + thick * 0.5;
		// Lace: cell borders drawn out into streaks, carried by the same flow,
		// strung between the masses and gone before the foam is.
		float ce = mix(cell_edge(qa * vec2(1.4, 0.42)), cell_edge(qb * vec2(1.4, 0.42)), w);
		float web = (1.0 - smoothstep(0.02, 0.02 + 0.12 * churn, ce)) * lod;
		float lace = web * smoothstep(0.18, 0.45, churn) * smoothstep(-0.2, 0.25, mn);
		float wash = max(mass, lace * 0.7);

		foam = max(foam, max(wash, max(hug, crest_foam)));
		float wide = (1.0 - smoothstep(0.6, 1.7, alat / wc + edge)) * start * spd * tail * exp(-age / (wake_life * 2.0));
		// Bubbles under and around each patch of foam: a soft, brighter halo that
		// ties the foam into the water instead of sitting on top of it.
		float halo = smoothstep(0.12, 0.45, v + fine * 0.1) * (1.0 - thick * 0.5) * smoothstep(0.0, 0.25, churn);
		aer = max(aer, max(wide * 0.6, max(halo, hug * 0.6)));
		// Churned water: an animated, confused chop, strongest where it's freshest,
		// so the water around the foam is visibly stirred up and catches the light.
		vec2 cc = c * 1.7;
		vec2 chop2 = vec2(gnoise(cc + vec2(0.0, t * 1.4)), gnoise(cc + vec2(t * 1.2, 9.0)))
				+ 0.5 * vec2(gnoise(cc * 2.3 - vec2(t * 2.0, 0.0)), gnoise(cc * 2.3 + vec2(4.0, t * 1.8))) * lod;
		float stir = max(wide, halo) * (0.35 + 0.65 * energy);
		grad += (perp * chop2.x + dir * chop2.y) * 0.4 * stir;
		// Churned water and foam are a jumble of little facets, heaving with the flow.
		vec2 jn = mix(vec2(gnoise(qa * 2.0 + 40.0), gnoise(qa * 2.0 + 57.0)),
				vec2(gnoise(qb * 2.0 + 40.0), gnoise(qb * 2.0 + 57.0)), w) * lod;
		grad += (perp * jn.x + dir * jn.y) * (0.3 * churn + 0.35 * wash);
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

	float crest, lost, c_, l_;
	float h0 = waves(p, wind, t, fp, gust, crest, lost);
	float eps = max(fp * 0.35, 0.004);
	float hx = waves(p + vec2(eps, 0.0), wind, t, fp, gust, c_, l_);
	float hz = waves(p + vec2(0.0, eps), wind, t, fp, gust, c_, l_);
	vec2 grad = vec2(hx - h0, hz - h0) / eps * normal_strength;
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
