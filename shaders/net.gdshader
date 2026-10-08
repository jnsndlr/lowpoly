shader_type spatial;
render_mode cull_back;

// lit_vc.gdshader for the ferries' car deck nets (Models.ferry_net), which blow in the
// wind (net_flap in lit_vc.gdshaderinc).
#define NET
#include "res://shaders/lit_vc.gdshaderinc"
