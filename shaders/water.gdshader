shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Faceted low-poly water: shallow turquoise near shore, deep teal offshore,
// animated foam where the water meets land, hulls and pilings.

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec4 deep_color : source_color = vec4(0.07, 0.3, 0.38, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.52, 0.54, 1.0);
uniform vec4 foam_color : source_color = vec4(0.93, 0.97, 0.97, 1.0);
uniform float depth_fade = 3.5;
uniform float foam_width = 0.3;
uniform float wave_height = 0.14;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = sin(w.x * 0.06 + TIME * 0.7) * cos(w.z * 0.075 + TIME * 0.55);
	h += 0.5 * sin((w.x - w.z) * 0.13 + TIME * 1.2);
	VERTEX.y += h * wave_height;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;

	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;
	vec3 water_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = max(water_world.y - scene_world.y, 0.0);

	float t = smoothstep(0.0, depth_fade, depth);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);
	float edge = 1.0 - smoothstep(0.0, foam_width, depth);
	float ripple = step(0.6, fract(depth * 1.4 - TIME * 0.3)) * (1.0 - smoothstep(0.0, foam_width * 3.0, depth));
	float foam = clamp(edge + ripple * 0.25, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam);

	ALBEDO = col;
	ALPHA = clamp(mix(0.7, 0.97, t) + foam, 0.0, 1.0);
	ROUGHNESS = 0.2;
	SPECULAR = 0.35;
}
