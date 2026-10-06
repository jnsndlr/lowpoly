shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;

// Far mainland pines (Backdrop): a quad turned about its upright to face the camera,
// cut to a three-tier pine silhouette and painted in two tones, the half toward the
// sun lit and the other in shade, like the trees in a poster. Two triangles each
// instead of a modelled tree; past a few hundred metres nobody can tell.
// The instance transform's X and Y scale are the card's width and height (quad
// from y = 0 to 1); COLOR is a per-tree tint.

#include "res://shaders/haze.gdshaderinc"

global uniform vec3 sun_direction;
global uniform vec3 sun_light;

uniform vec3 foliage : source_color = vec3(0.16, 0.38, 0.2);
uniform vec3 trunk : source_color = vec3(0.3, 0.22, 0.16);

varying vec3 world_pos;
// Sunward-ness of the card's +x half: > 0 means the right half faces the sun.
varying float sun_side;
varying vec3 tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = normalize(to_cam + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	world_pos = origin + right * VERTEX.x * w + vec3(0.0, VERTEX.y * h, 0.0);
	sun_side = dot(right.xz, normalize(sun_direction.xz + vec2(1e-4)));
	tint = COLOR.rgb;
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(fwd, 0.0)).xyz;
}

void fragment() {
	// UV: x 0..1 across, y 0 at the top.
	float x = abs(UV.x - 0.5) * 2.0;
	float y = 1.0 - UV.y;
	bool tree = false;
	// Three stacked cones, each narrower and higher, overlapping.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float base = 0.1 + fk * 0.26;
		float top = base + 0.5 - fk * 0.06;
		float half_w = 1.0 - fk * 0.22;
		if (y >= base && y <= top && x <= half_w * (top - y) / (top - base)) {
			tree = true;
		}
	}
	bool stem = y < 0.12 && x < 0.1;
	if (!tree && !stem) {
		discard;
	}
	vec3 albedo = (tree ? foliage : trunk) * tint;
	float side = sign(UV.x - 0.5) * sun_side;
	float lit = smoothstep(-0.15, 0.15, side) * 0.8 + 0.2 * smoothstep(0.0, 1.0, y);
	vec3 ambient = mix(haze_sky, sky_zenith, 0.6) * 0.5;
	ALBEDO = albedo * (ambient + sun_light * 0.75 * lit);
	FOG = backdrop_haze(world_pos, length(VERTEX));
}
