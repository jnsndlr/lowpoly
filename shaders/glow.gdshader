shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

// Night lights. GlowBuilder bakes every lamp, beacon, headlight and its reflection
// as a quad whose four vertices all sit at the light (UV holds the corner), and
// this shader opens each one up on screen:
//   GLOW / NAV    a camera-facing point light: a hot core in a soft halo, kept at
//                 least a pixel or two wide so distant shores still twinkle. Lights
//                 well beyond the camera's focus open into soft hexagonal bokeh
//                 discs, their brightness spread over their area. NAV lights pick
//                 red or green by which side of the hull they are on.
//   POOL / CONE   light thrown on the ground under a lamp / ahead of a car.
//   BEAM          a lighthouse's sweeping beam, billboarded around its axis.
//   REFLECT       a shimmering streak on the water where the mirrored light shows,
//                 pointing back toward the light.
// CUSTOM0 = (size, mode, switch-on threshold, blink period); CUSTOM1 = (direction or
// extent, energy). Everything fades in with the `night_lights` global, each light at
// its own threshold so towns come on a few windows at a time.

global uniform float night_lights;
global uniform float focus_distance;

uniform float min_pixels = 1.5;
// How much bigger than its lamp a point light looks: a lit lamp blooms well past
// its housing, so at true size the ones on boats are specks up close.
uniform float lamp_scale = 2.5;
// Bokeh circle radius (px) of a light far beyond focus, and its cap.
uniform float bokeh_aperture = 20.0;
uniform float bokeh_max = 12.0;
// Lights stay sharp out to this multiple of the focus distance, then start to blur.
uniform float bokeh_start = 1.8;
// Multimesh lights (cars): INSTANCE_CUSTOM.x gates the CONE pools, so only moving
// cars throw their headlights down the road.
uniform bool instance_gate = false;
// Which end is the bow for NAV lights (+1: +Z); double-ended ferries swap each
// crossing, and only the bow end's sidelights are lit.
instance uniform float nav_flip = 1.0;

const int GLOW = 0;
const int POOL = 1;
const int CONE = 2;
const int BEAM = 3;
const int NAV = 4;
const int REFLECT = 5;
const int NAV_REFLECT = 6;

varying flat int v_mode;
varying vec3 v_color;
varying vec3 v_shape;   // GLOW: core radius, bokeh radius (fractions of the quad), bokeh blend; REFLECT: blur
varying float v_phase;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float px_per_unit(float z, mat4 proj, vec2 vp) {
	return proj[1][1] * vp.y * 0.5 / max(z, 0.01);
}

void vertex() {
	int mode = int(CUSTOM0.y + 0.5);
	float size = CUSTOM0.x;
	vec3 wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Local position, so lights riding on cars and ferries keep their phase.
	v_phase = hash13(VERTEX * 1.37 + 0.5);
	float energy = CUSTOM1.w * smoothstep(CUSTOM0.z, CUSTOM0.z + 0.1, night_lights);
	if (CUSTOM0.w > 0.0) {
		// Whole seconds of period, and the phase as the fraction (Models.blink_of),
		// so the lamp glass in lit_vc.gdshader flashes in step.
		float k = fract(TIME / floor(CUSTOM0.w) + fract(CUSTOM0.w));
		energy *= smoothstep(0.0, 0.04, k) * (1.0 - smoothstep(0.2, 0.32, k));
	}
	if (instance_gate && mode == CONE) {
		energy *= INSTANCE_CUSTOM.x;
	}
	v_mode = mode;
	v_color = pow(COLOR.rgb, vec3(2.2));
	if (mode == NAV || mode == NAV_REFLECT) {
		// Heading +Z, port is +X: at the bow end, port is where x and z share a sign.
		v_color = VERTEX.x * VERTEX.z > 0.0 ? vec3(1.0, 0.05, 0.02) : vec3(0.05, 1.0, 0.25);
		energy *= VERTEX.z * nav_flip > 0.0 ? 1.0 : 0.0;
	}
	v_shape = vec3(1.0, 0.0, 0.0);
	vec3 pos = vec3(0.0);
	bool keep = energy > 1e-3;

	if (mode == GLOW || mode == NAV) {
		vec3 vc = (VIEW_MATRIX * vec4(wc, 1.0)).xyz;
		float z = -vc.z;
		keep = keep && z > 0.5;
		if (dot(CUSTOM1.xyz, CUSTOM1.xyz) > 0.0) {
			vec3 facing = normalize(mat3(MODEL_MATRIX) * CUSTOM1.xyz);
			energy *= mix(0.12, 1.0, smoothstep(-0.2, 0.6, dot(facing, normalize(CAMERA_POSITION_WORLD - wc))));
		}
		float ppu = px_per_unit(z, PROJECTION_MATRIX, VIEWPORT_SIZE);
		float true_px = size * lamp_scale * ppu;
		float core = max(true_px, min_pixels);
		// Sub-pixel lights keep a visible point but give up some brightness.
		energy *= clamp(true_px / min_pixels, 0.35, 1.0);
		energy *= mix(1.0, 0.4, smoothstep(700.0, 2200.0, z));
		float coc = min(bokeh_aperture * max(z - focus_distance * bokeh_start, 0.0) / z, bokeh_max);
		float r = max(core * 4.0, coc);
		float b = smoothstep(1.5, 4.0, coc / core);
		v_shape = vec3(core / r, coc / r, b);
		energy *= mix(1.0, clamp(pow(core * 1.6 / max(coc, 1e-3), 2.0), 0.035, 1.0), b);
		// Lift it toward the camera so its own lamp housing doesn't hide it.
		vc += normalize(-vc) * min(size * 2.0, 1.2);
		pos = vc + vec3(UV * r / ppu, 0.0);
	} else if (mode == POOL || mode == CONE) {
		vec3 axis = CUSTOM1.xyz;
		vec3 side = normalize(cross(axis, vec3(0.0, 1.0, 0.0))) * size;
		pos = (MODELVIEW_MATRIX * vec4(VERTEX + side * UV.x + axis * UV.y, 1.0)).xyz;
		pos += normalize(-pos) * 0.04;
	} else if (mode == BEAM) {
		float a = TIME * CUSTOM1.x + CUSTOM1.z;
		vec3 d = normalize(vec3(cos(a), -0.03, sin(a)));
		float t = UV.y * 0.5 + 0.5;
		vec3 p = wc + d * (t * CUSTOM1.y);
		p += normalize(cross(d, p - CAMERA_POSITION_WORLD)) * UV.x * size * (0.3 + t * 1.8);
		pos = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	} else {
		// Where the mirrored light shows: the view ray to it crosses the water here.
		vec3 cam = CAMERA_POSITION_WORLD;
		keep = keep && wc.y > 0.5 && cam.y > 1.0;
		// A lamp facing away (a ferry's far rail) is hidden by its hull, and so is the
		// light it would throw on the water toward us.
		if (dot(CUSTOM1.xyz, CUSTOM1.xyz) > 0.0) {
			vec2 facing = normalize((mat3(MODEL_MATRIX) * CUSTOM1.xyz).xz);
			vec2 to_cam = cam.xz - wc.xz;
			energy *= smoothstep(-0.05, 0.35, dot(facing, to_cam * inversesqrt(max(dot(to_cam, to_cam), 1e-4))));
		}
		vec3 m = vec3(wc.x, -wc.y, wc.z);
		vec3 q = cam + (m - cam) * (cam.y / (cam.y - m.y));
		q.y = 0.3;
		vec3 vq = (VIEW_MATRIX * vec4(q, 1.0)).xyz;
		vec3 vl = (VIEW_MATRIX * vec4(wc, 1.0)).xyz;
		float z = -vq.z;
		keep = keep && z > 0.5 && -vl.z > 0.5;
		float ppu = px_per_unit(z, PROJECTION_MATRIX, VIEWPORT_SIZE);
		vec2 axis = vl.xy / -vl.z - vq.xy / z;
		axis = dot(axis, axis) > 1e-10 ? normalize(axis) : vec2(0.0, 1.0);
		// Ripples smear the reflection along the view, more so at a glancing angle.
		float graze = 1.0 - abs(normalize(q - cam).y);
		float w_px = max(size * ppu * 5.0, min_pixels * 2.5);
		float l_px = clamp(size * ppu * 17.0 * (1.0 + 2.5 * graze), 10.0, 190.0);
		energy *= 0.18 * clamp(size * ppu / min_pixels, 0.35, 1.0);
		// Out of focus it scatters into a broad, faint smudge like the lights do.
		float coc = min(bokeh_aperture * max(z - focus_distance * bokeh_start, 0.0) / z, bokeh_max);
		float w0 = w_px;
		float l0 = l_px;
		w_px = max(w_px, coc * 1.1);
		l_px += coc * 2.0;
		energy *= clamp(w0 * l0 / (w_px * l_px), 0.06, 1.0);
		energy *= mix(1.0, 0.35, smoothstep(150.0, 700.0, z));
		v_shape = vec3(clamp(coc / 6.0, 0.0, 1.0), 0.0, 0.0);
		pos = vq + vec3((vec2(-axis.y, axis.x) * UV.x * w_px + axis * UV.y * l_px) / ppu, 0.0);
	}
	// Lights that are off collapse to a point, so nothing is drawn.
	VERTEX = keep ? pos : vec3(0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_color *= energy;
}

void fragment() {
	float r = length(UV);
	float f;
	if (v_mode == GLOW || v_mode == NAV) {
		float cf = v_shape.x;
		float rr = r * r / (cf * cf);
		float core = exp(-rr * 2.5);
		float glow = (core + 0.2 * exp(-sqrt(rr) * 1.1)) * (1.0 - smoothstep(0.6, 1.0, r));
		// Six aperture blades, rounded off.
		float a = atan(UV.y, UV.x);
		float hex = r * cos(PI / 6.0) / cos(mod(a, PI / 3.0) - PI / 6.0);
		float d = mix(r, hex, 0.5) / max(v_shape.y, 1e-3);
		// No core: a defocused point is an even disc with a slightly brighter rim.
		float disc = (1.0 - smoothstep(0.8, 1.0, d)) * (0.55 + 0.3 * smoothstep(0.5, 0.92, d));
		f = mix(glow, disc, v_shape.z);
	} else if (v_mode == POOL) {
		f = max(1.0 - r * r, 0.0);
		f *= f * f;
	} else if (v_mode == CONE) {
		float t = UV.y * 0.5 + 0.5;
		float w = mix(0.3, 1.0, t);
		f = (1.0 - smoothstep(0.35, 1.0, abs(UV.x) / w)) * pow(1.0 - t, 1.6) * smoothstep(0.0, 0.12, t);
	} else if (v_mode == BEAM) {
		float t = UV.y * 0.5 + 0.5;
		f = exp(-UV.x * UV.x * 3.0) * pow(1.0 - t, 1.4);
	} else {
		// Broken up by the ripples: bands drift along it and its centre line wobbles,
		// both washing out as it blurs.
		float blur = v_shape.x;
		float s = 0.6 + 0.4 * (1.0 - blur) * sin(UV.y * 7.0 - TIME * 2.4 + v_phase * 30.0) * sin(UV.y * 3.1 + TIME * 1.3 + v_phase * 12.0);
		float x = UV.x + 0.25 * (1.0 - blur) * sin(UV.y * 9.0 + TIME * 3.1 + v_phase * 20.0);
		f = exp(-x * x * mix(3.0, 2.0, blur)) * pow(max(1.0 - UV.y * UV.y, 0.0), mix(1.5, 1.0, blur)) * s;
	}
	ALBEDO = v_color * f;
}
