shader_type spatial;
render_mode cull_back;

// lit_vc.gdshader with its per-instance uniforms (room_seed, nav_flip), for the hulls
// of vessels and ferries (Models.hull_material()).
#define HULL
#include "res://shaders/lit_vc.gdshaderinc"
