// Body of lit_vc.gdshader and lit_vc_hull.gdshader (which defines HULL).

// The shared vertex-coloured material for terrain, buildings, trees and boats.
// Same look as the StandardMaterial3D it replaces (sRGB vertex colours, matte
// Lambert), but direct sunlight is dimmed under passing clouds.
//
// Vertex alpha marks glass that lights up at night (Models.WINDOW*): 0 is always
// lit, 0.5 lit in some rooms and not others, picked per building, wall and floor,
// 0.15 (Models.LAMP_GLASS_ALPHA) the glass of a lamp, glowing in its own colour, and
// 0.7-0.95 the same flashing, with the phase in the alpha (Models.lamp_glass), and
// 0.3 (Models.NAV_GLASS_ALPHA) a ferry sidelight's lens, lit only at the bow end.

#include "res://shaders/clouds.gdshaderinc"

global uniform float night_lights;
global uniform float focus_distance;

uniform vec3 window_color : source_color = vec3(1.0, 0.68, 0.36);
uniform float window_energy = 2.6;
uniform float lamp_energy = 1.6;
// Must match Models.BLINK_PERIOD.
uniform float lamp_blink_period = 4.0;
// glow.gdshader's bokeh: past focus a lamp's glow opens into a soft disc, so its glass
// fades out with it rather than leaving a sharp pixel in the middle. Must match there.
uniform float bokeh_aperture = 20.0;
uniform float bokeh_max = 12.0;
uniform float bokeh_start = 1.8;

#ifdef HULL
// Which end of a ferry is the bow (+1: +Z), set per hull by NightLights.
instance uniform float nav_flip = 0.0;
// Stands in for the instance origin in the room key on anything that moves (set per
// hull by Vessel), so its rooms don't change as it goes. 0: use the origin.
instance uniform float room_seed = 0.0;
#else
// Godot reserves room for every instance of a shader with instance uniforms (16
// slots each, in a buffer of 65536), and the scenery alone runs to thousands of
// instances: only hulls (lit_vc_hull.gdshader) get them.
const float nav_flip = 0.0;
const float room_seed = 0.0;
#endif

#ifdef NET
// The wind across the net (net.gdshader, Models.ferry_net), m/s in the net's frame:
// x along it, y through it (+: blowing towards +z). Set per net by Ferry: the true
// wind less the ferry's own way.
instance uniform vec2 wind = vec2(0.0);

// How far a net vertex is blown: its alpha holds how freely it moves (1 - alpha / 2).
// A steady billow downwind, swaying with the gusts, and ripples running along it that
// quicken and grow as the wind rises.
vec3 net_flap(vec3 v, float a, vec3 origin) {
	float free = (1.0 - a) * 2.0;
	if (free <= 0.0) {
		return v;
	}
	float seed = fract(dot(origin, vec3(0.013, 0.0, 0.029))) * 40.0;
	float strength = length(wind);
	float t = TIME + seed;
	float gust = 0.7 + 0.2 * sin(t * 0.63) + 0.1 * sin(t * 1.71 + v.x * 0.07);
	float billow = clamp(wind.y / 12.0, -1.0, 1.0) * 0.7 * gust;
	float f = 1.6 + 0.22 * strength;
	float along = wind.x >= 0.0 ? 1.0 : -1.0;
	float ripple = sin(t * f - along * v.x * 1.1 + v.y * 1.7) + 0.45 * sin(t * f * 1.83 + v.x * 2.7 - v.y * 1.3);
	float amp = min(0.03 + 0.009 * strength, 0.17);
	v.z += free * (billow + amp * ripple);
	// Bellied out, the net takes up its slack: the foot lifts a little.
	v.y += free * 0.1 * abs(billow);
	return v;
}
#endif

varying vec3 world_pos;
varying float local_z;
// Flat: a whole face takes its first vertex's key (MeshBuilder starts both of a quad's
// triangles there), so glass straddling a storey line doesn't hash per pixel.
varying flat vec3 room_key;
// 1 on walls, 0 on the top and bottom of glass: those key a room of their own, and
// a lit sliver over a dark window shimmers as the hull rocks.
varying flat float upright;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
#ifdef NET
	VERTEX = net_flap(VERTEX, COLOR.a, MODEL_MATRIX[3].xyz);
#endif
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_z = VERTEX.z;
	// Instance origin (or room_seed), wall (normal) and storey (in metres, however big
	// the mesh is drawn): the same for a whole window.
	vec3 origin = room_seed != 0.0 ? vec3(room_seed, room_seed * 1.7, room_seed * 2.3) : MODEL_MATRIX[3].xyz;
	room_key = origin + round(NORMAL * 2.0) * 17.0 + floor(VERTEX.y * length(MODEL_MATRIX[1].xyz) / 7.5) * 5.3;
	upright = step(abs(NORMAL.y), 0.5);
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.92;
#ifndef NET
	// (A net's alpha is its give in the wind, not glass.)
	if (COLOR.a < 0.99 && night_lights > 0.0) {
		float h = hash13(room_key);
		// Always-lit glass comes on with the first lights; rooms one by one after.
		float on_at = COLOR.a < 0.25 ? 0.05 : 0.1 + h * 0.9;
		float lit = smoothstep(on_at, on_at + 0.08, night_lights) * step(COLOR.a < 0.25 ? 0.0 : 0.3, h);
		if (COLOR.a >= 0.25) {
			lit *= upright;
		}
		// The key moves with ferries, so only rooms that may go dark vary in brightness.
		float tint = COLOR.a < 0.25 ? 1.0 : mix(0.7, 1.15, fract(h * 7.1));
		bool lamp = COLOR.a > 0.1 && COLOR.a < 0.2;
		// Flashing lamp glass: the alpha holds its phase (Models.lamp_glass).
		bool flash = COLOR.a > 0.69 && COLOR.a < 0.96;
		bool nav = COLOR.a > 0.25 && COLOR.a < 0.35;
		if (lamp || flash || nav) {
			lit = smoothstep(0.05, 0.13, night_lights);
			if (nav) {
				lit *= local_z * nav_flip > 0.0 ? 2.0 : 0.0;
			}
			if (flash) {
				float k = fract(TIME / lamp_blink_period + (round(COLOR.a * 255.0) - 180.0) / 64.0);
				lit *= smoothstep(0.0, 0.04, k) * (1.0 - smoothstep(0.2, 0.32, k));
			}
			float z = -VERTEX.z;
			float coc = min(bokeh_aperture * max(z - focus_distance * bokeh_start, 0.0) / z, bokeh_max);
			lit *= 1.0 - smoothstep(1.5, 5.0, coc);
			EMISSION = ALBEDO * lamp_energy * lit;
		} else {
			EMISSION = window_color * tint * window_energy * lit;
		}
	}
#endif
}

void light() {
	float shade = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		shade = 1.0 - cloud_shadow(world_pos, TIME);
	}
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * shade;
}
