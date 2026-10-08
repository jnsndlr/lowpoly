# Builds the mid-poly orca in Blender (run inside Blender: exec(open(path).read())).
# Game frame: one unit long, +Z forward, nose at z = 0.5, +Y up (Blender: bow to -Y, Z up).
# The body is plain black: its markings are drawn per animal by cetacean.gdshader
# (orca_markings) from UV = (s, theta / pi), s = distance back from the nose, theta
# round the body from the back (0) to the belly (pi). Fins, flippers and flukes have
# UV.x = -1 and keep their vertex colours.
# Dorsal fin vertices carry alpha = 1 - t/2 (t = height fraction) for cetacean.gdshader,
# which raises them to each animal's fin height above FIN_BASE.
import bpy, bmesh, math
from mathutils import Vector


def G(x, y, z): return Vector((x, -z, y))


BLACK = (0.05, 0.055, 0.065, 1); WHITE = (0.92, 0.93, 0.92, 1); SADDLE = (0.55, 0.57, 0.6, 1); UNDER = (0.86, 0.87, 0.86, 1)
COLS = [BLACK, WHITE, SADDLE]
FIN_BASE, FIN_H = 0.085, 0.18
P = math.pi
# Resolution: body rings x segments round, and the fin/flipper/fluke sections (~1k tris).
NS, NR = 24, 18
FIN_T = (0.0, 0.3, 0.65, 0.88, 1.0)
FLIPPER_U = (0.0, 0.45, 0.8, 1.0)
FLUKE_U = (0.0, 0.3, 0.6, 0.85, 1.0)

coll = bpy.data.collections.get("Orca") or bpy.data.collections.new("Orca")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_nt.links.new(_attr.outputs["Color"], _nt.nodes["Principled BSDF"].inputs["Base Color"])
_o = bpy.data.objects.get("Orca")
if _o: bpy.data.objects.remove(_o, do_unlink=True)

# Body profile keyed on s = distance back from the nose.
S   = [0.0,   0.015, 0.05,  0.1,   0.17,  0.26,  0.38,  0.5,   0.62,  0.72,  0.8,   0.87,  0.925]
TOP = [-0.012, 0.018, 0.046, 0.068, 0.082, 0.09,  0.092, 0.084, 0.064, 0.047, 0.035, 0.026, 0.018]
BOT = [-0.03, -0.045, -0.062, -0.078, -0.089, -0.096, -0.096, -0.086, -0.06, -0.04, -0.026, -0.016, -0.008]
HW  = [0.0,   0.028, 0.052, 0.072, 0.088, 0.098, 0.099, 0.088, 0.062, 0.038, 0.022, 0.012, 0.007]


def interp(tab, s):
    s = min(max(s, S[0]), S[-1])
    for i in range(len(S) - 1):
        if S[i] <= s <= S[i + 1]:
            t = (s - S[i]) / (S[i + 1] - S[i])
            p0 = tab[max(i - 1, 0)]; p1 = tab[i]; p2 = tab[i + 1]; p3 = tab[min(i + 2, len(S) - 1)]
            return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


EX = 2.25


def surf(s, a):
    t_, b_, w_ = interp(TOP, s), interp(BOT, s), max(interp(HW, s), 0.0)
    c, h = (t_ + b_) / 2, (t_ - b_) / 2
    sa, ca = math.sin(a), math.cos(a)
    return G(w_ * math.copysign(abs(sa) ** (2 / EX), sa), c + h * math.copysign(abs(ca) ** (2 / EX), ca), 0.5 - s)


bm = bmesh.new(); cl = bm.loops.layers.color.new("Col"); uvl = bm.loops.layers.uv.new("UVMap")


def paint(f, col):
    for l in f.loops: l[cl] = col


sl = [0.925 * (i / (NS - 1)) ** 1.15 for i in range(NS)]
body_uv = {}
rings = []
for s_ in sl:
    ring = []
    for k in range(NR):
        a = 2 * P * k / NR
        v = bm.verts.new(surf(s_, a))
        body_uv[v] = (s_, min(a, 2 * P - a) / P)
        ring.append(v)
    rings.append(ring)
for i in range(NS - 1):
    for k in range(NR):
        paint(bm.faces.new([rings[i][k], rings[i][(k + 1) % NR], rings[i + 1][(k + 1) % NR], rings[i + 1][k]]), BLACK)
paint(bm.faces.new(rings[-1]), BLACK)


def loft(sections, col):
    vr = [[bm.verts.new(p) for p in sec] for sec in sections]; n = len(sections[0]); out = []
    for i in range(len(vr) - 1):
        for j in range(n): out.append(bm.faces.new([vr[i][j], vr[i][(j + 1) % n], vr[i + 1][(j + 1) % n], vr[i + 1][j]]))
    out.append(bm.faces.new(list(reversed(vr[0])))); out.append(bm.faces.new(vr[-1]))
    for f in out: paint(f, col)
    return vr


# Dorsal fin (a bull's: tall, nearly straight; the shader curves a cow's).
rows = []
for t in FIN_T:
    le = 0.075 + (-0.04 - 0.075) * t ** 0.85
    te = -0.105 + (-0.052 + 0.105) * t + 0.012 * math.sin(P * t)
    if t == 1.0: le, te = -0.038, -0.046
    thk = 0.017 * (1 - 0.85 * t) + 0.0015; ch = le - te
    pts = [(0.0, le), (thk, le - 0.25 * ch), (thk * 0.6, le - 0.65 * ch), (0.0, te), (-thk * 0.6, le - 0.65 * ch), (-thk, le - 0.25 * ch)]
    rows.append(([G(x, (interp(TOP, 0.5 - z) - 0.006) if t == 0 else FIN_BASE + t * FIN_H, z) for x, z in pts], t))
for row, (_, t) in zip(loft([r for r, _ in rows], BLACK), rows):
    for v in row:
        for l in v.link_loops: l[cl] = (BLACK[0], BLACK[1], BLACK[2], 1.0 - t / 2)

# Pectoral flippers: broad rounded paddles.
for side in (1, -1):
    root = Vector((0.072 * side, -0.06, 0.29)); tip = Vector((0.205 * side, -0.135, 0.15)); secs = []
    for u in FLIPPER_U:
        p = root.lerp(tip, u)
        ch = 0.115 * math.sqrt(max(1 - u ** 2.4, 0.0)) * (1 - 0.1 * u) + 0.004
        thk = 0.012 * (1 - 0.6 * u) + 0.001
        pts = [(0, ch * 0.45), (thk, ch * 0.2), (thk * 0.6, -ch * 0.25), (0, -ch * 0.55), (-thk * 0.6, -ch * 0.25), (-thk, ch * 0.2)]
        secs.append([G(p.x, p.y + dy, p.z - 0.012 * u + dz) for dy, dz in pts])
    loft(secs, BLACK)

# Flukes, notched, white underneath.
for side in (1, -1):
    secs = []
    for u in FLUKE_U:
        x = 0.155 * u * side; le = -0.405 - 0.075 * u ** 1.25; te = -0.47 - 0.05 * u ** 0.7
        if u == 1.0: le, te = -0.512, -0.518
        thk = 0.012 * (1 - 0.85 * u) + 0.001; ch = le - te; y0 = 0.01 - 0.006 * u
        pts = [(0, le), (thk, le - 0.3 * ch), (thk * 0.5, le - 0.75 * ch), (0, te), (-thk * 0.5, le - 0.75 * ch), (-thk, le - 0.3 * ch)]
        secs.append([G(x, y0 + dy, z) for dy, z in pts])
    loft(secs, BLACK)

bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
for f in bm.faces:
    c = f.calc_center_median()
    if c.y > 0.395 and abs(c.x) > 0.01 and f.normal.z < -0.3: paint(f, UNDER)
for f in bm.faces:
    for l in f.loops:
        l[uvl].uv = body_uv.get(l.vert, (-1.0, 0.0))
me = bpy.data.meshes.new("Orca"); bm.to_mesh(me); bm.free(); me.materials.append(mat)
for p in me.polygons: p.use_smooth = True
coll.objects.link(bpy.data.objects.new("Orca", me))
