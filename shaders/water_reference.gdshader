shader_type spatial;
render_mode unshaded, cull_back;

// Reference-water study: two advected triangular slope fields, depth colour,
// broad sky reflections and narrow sun glints. Opaque; no screen-depth dependency.
#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D seabed_height : filter_nearest, repeat_disable;
uniform float terrain_half_size = 500.0;
uniform float terrain_cell = 2.5;
uniform float floor_height = -5.35;
uniform float swell_extent = 1000.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shallow_color : source_color = vec4(0.015, 0.65, 0.66, 1.0);
uniform vec4 deep_color : source_color = vec4(0.015, 0.36, 0.64, 1.0);
uniform vec4 sky_color : source_color = vec4(0.22, 0.66, 0.87, 1.0);
uniform vec4 glint_color : source_color = vec4(0.85, 0.98, 0.96, 1.0);
uniform float absorption : hint_range(0.01, 2.0) = 0.42;
uniform float facet_size : hint_range(0.2, 12.0) = 3.2;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.65;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.45;
uniform float wave_height : hint_range(0.0, 1.0) = 0.13;
uniform float highlight_strength : hint_range(0.0, 2.0) = 0.85;
varying vec3 world_pos;

float hash_water(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Piecewise linear height and its constant slope inside each triangle.
// Alternating diagonals and domain warping break up the regular lattice.
vec3 triangle_wave(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash_water(i);
    float b = hash_water(i + vec2(1.0, 0.0));
    float c = hash_water(i + vec2(0.0, 1.0));
    float d = hash_water(i + vec2(1.0));
    if (mod(i.x + i.y, 2.0) < 1.0) {
        if (f.x > f.y) return vec3(a + (b-a)*f.x + (d-b)*f.y, b-a, d-b);
        return vec3(a + (d-c)*f.x + (c-a)*f.y, d-c, c-a);
    }
    if (f.x + f.y < 1.0) return vec3(a + (b-a)*f.x + (c-a)*f.y, b-a, c-a);
    return vec3(d + (c-d)*(1.0-f.x) + (b-d)*(1.0-f.y), d-c, d-b);
}

// Same alternating triangulation as Terrain.height_at(), including texel centres.
float bottom_height(vec2 p) {
    vec2 grid = (p + terrain_half_size) / terrain_cell;
    float count = terrain_half_size * 2.0 / terrain_cell;
    if (min(grid.x, grid.y) < 0.0 || max(grid.x, grid.y) >= count) return floor_height;
    vec2 i = floor(grid);
    vec2 f = fract(grid);
    vec2 uv = (i + 0.5) / (count + 1.0);
    float step_uv = 1.0 / (count + 1.0);
    float a = texture(seabed_height, uv).r;
    float b = texture(seabed_height, uv + vec2(step_uv, 0.0)).r;
    float c = texture(seabed_height, uv + vec2(0.0, step_uv)).r;
    float d = texture(seabed_height, uv + vec2(step_uv)).r;
    float h;
    if (mod(i.x + i.y, 2.0) < 1.0) {
        h = f.x >= f.y ? a + (b-a)*f.x + (d-b)*f.y : a + (c-a)*f.y + (d-c)*f.x;
    } else {
        h = f.x + f.y <= 1.0 ? a + (b-a)*f.x + (c-a)*f.y : d + (c-d)*(1.0-f.x) + (b-d)*(1.0-f.y);
    }
    return max(h, floor_height);
}

void vertex() {
    vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float edge = max(abs(p.x), abs(p.z));
    float fade = 1.0 - smoothstep(swell_extent - 80.0, swell_extent - 10.0, edge);
    float h = sin(dot(p.xz, vec2(0.08, 0.045)) + TIME * 0.65);
    h += 0.45 * sin(dot(p.xz, vec2(-0.055, 0.12)) + TIME * 0.83);
    VERTEX.y += h * wave_height * fade;
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float t = TIME * wave_speed;
    vec2 p = world_pos.xz;
    vec2 warp = vec2(sin(p.y * 0.075 + t * 0.12), sin(p.x * 0.061 - t * 0.1)) * 3.5;
    mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
    vec2 q = (p + warp) / facet_size;
    vec3 broad = triangle_wave(q * vec2(0.8, 1.25) - vec2(t * 0.25, t * 0.11));
    vec3 fine = triangle_wave(rot * q * 2.3 + vec2(t * 0.19, -t * 0.3) + 17.3);
    float footprint = length(fwidth(q));
    float detail = 1.0 - smoothstep(0.12, 0.65, footprint);
    float fine_detail = 1.0 - smoothstep(0.06, 0.3, footprint);
    vec2 slope = broad.yz * vec2(0.8, 1.25) * detail;
    slope += transpose(rot) * fine.yz * 0.42 * fine_detail;
    vec3 n = normalize(vec3(-slope.x * normal_strength, 1.0, -slope.y * normal_strength));
    vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
    float depth = max(world_pos.y - bottom_height(p), 0.0);
    float deep = 1.0 - exp(-depth * absorption);
    vec3 col = mix(shallow_color.rgb, deep_color.rgb, deep);

    // Broad flat colour patches plus a smaller overlapping layer.
    float shade = clamp(0.5 + dot(n.xz, normalize(v.xz + vec2(0.001))) * 1.8, 0.0, 1.0);
    col *= mix(0.52, 1.3, shade);
    col *= 1.0 + (broad.x - 0.5) * 0.22 * detail;
    vec3 reflected = reflect(-v, n);
    float sky_patch = smoothstep(0.02, 0.55, reflected.y);
    float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
    col = mix(col, sky_color.rgb, (0.12 + 0.5 * fresnel) * sky_patch);

    // A narrow reflection band broken by the second wave layer; no cell outlines.
    float ridge = abs(broad.x + (fine.x - 0.5) * 0.3 - 0.57);
    float aa = max(fwidth(ridge), 0.008);
    float ribbon = 1.0 - smoothstep(0.022, 0.022 + aa, ridge);
    float catching_sky = mix(0.35, 1.0, smoothstep(-0.2, 0.55, reflected.y));
    float broken = smoothstep(0.3, 0.58, fine.x);
    float sun = pow(max(dot(n, normalize(normalize(sun_direction) + v)), 0.0), 160.0);
    float glint = clamp(ribbon * catching_sky * broken * detail * 0.95 + sun * ribbon, 0.0, 1.0);
    float cloud = cloud_shadow(world_pos, TIME);
    col = mix(col, glint_color.rgb, glint * highlight_strength * (1.0 - cloud));
    col *= (1.0 - cloud * 0.45) * mix(0.12, 1.0, daylight);
    ALBEDO = col;
}
