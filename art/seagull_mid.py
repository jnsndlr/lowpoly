# Builds the mid-poly seagull in Blender (run inside Blender: exec(open(path).read()))
# and exports assets/models/seagull_mid.glb. An adult Western gull: white head and
# body, slate-grey mantle, black wingtips with white mirrors, a white trailing edge,
# yellow bill with a red gonys spot, pink legs.
# Game frame: +Z forward, +Y up (Blender: forward -Y, Z up), same size as the old
# Models.seagull: bill tip at z = 0.36, wingtips at |x| = 0.72, feet at y = -0.1.
# seagull.gdshader conventions:
#  - vertex alpha 1 = body, 0.97 = tail (closed up perched), 0.93 = legs (tucked away
#    in flight), 0.5 = wing;
#  - wing vertices hinge at |x| = SHOULDER and ELBOW about the line y = WING_Y;
#  - each wing vertex carries its folded (perched) position: UV = (x, y), UV2.x = z.
import bpy, bmesh, math, os
from mathutils import Vector


def G(x, y, z): return Vector((x, -z, y))


WHITE = (0.95, 0.95, 0.93); MANTLE = (0.56, 0.6, 0.66); BLACK = (0.09, 0.09, 0.1)
UNDER = (0.86, 0.87, 0.88); UNDER_TIP = (0.32, 0.32, 0.34)
BILL = (0.96, 0.78, 0.22); GONYS = (0.86, 0.22, 0.14); EYE = (0.08, 0.08, 0.08)
LEG = (0.88, 0.64, 0.6)
A_BODY, A_TAIL, A_LEG, A_WING = 1.0, 0.97, 0.93, 0.5
WING_Y = 0.04
N = 10   # facets round the body

if not bpy.data.filepath.endswith("seagull_mid.blend"):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.wm.save_as_mainfile(filepath="/Users/jon/Documents/GitHub/lowpoly/art/seagull_mid.blend")
coll = bpy.data.collections.get("Seagull") or bpy.data.collections.new("Seagull")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_nt.links.new(_attr.outputs["Color"], _nt.nodes["Principled BSDF"].inputs["Base Color"])
for _n in ("Seagull",):
    _o = bpy.data.objects.get(_n)
    if _o: bpy.data.objects.remove(_o, do_unlink=True)
    _m = bpy.data.meshes.get(_n)
    if _m: bpy.data.meshes.remove(_m)

bm = bmesh.new()
cl = bm.loops.layers.color.new("Col")
uv1 = bm.loops.layers.uv.new("UVMap")
uv2 = bm.loops.layers.uv.new("UV2")


def face(pts, col, alpha=A_BODY, out=None, fold=None):
    """One flat face from game-frame points, wound so its normal points along `out`
    (a game-frame direction) when given. `fold` lists each point's folded position."""
    pts = list(pts); fold = list(fold) if fold else None
    if out is not None:
        a, b, c = pts[0], pts[1], pts[2]
        n = (b - a).cross(c - a)
        if n.length < 1e-12 and len(pts) > 3: n = (c - a).cross(pts[3] - a)
        if n.dot(out) < 0:
            pts.reverse()
            if fold: fold.reverse()
    vs = [bm.verts.new(G(*p)) for p in pts]
    try:
        f = bm.faces.new(vs)
    except ValueError:
        return None
    for i, l in enumerate(f.loops):
        l[cl] = (*col, alpha)
        q = fold[i] if fold else pts[i]
        # glTF flips v on export (v' = 1 - v), so store 1 - y to read y back in Godot.
        l[uv1].uv = (q[0], 1.0 - q[1]); l[uv2].uv = (q[2], 1.0)
    return f


def lerp(a, b, t): return a + (b - a) * t


def table(xs, ys, x):
    if x <= xs[0]: return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]: return lerp(ys[i], ys[i + 1], (x - xs[i]) / (xs[i + 1] - xs[i]))
    return ys[-1]


# --- Body, head and bill: lofted sections (z, centre y, half-width, half-height) ----
SECT = [(-0.2, 0.026, 0.0, 0.0),
        (-0.17, 0.022, 0.024, 0.02), (-0.12, 0.016, 0.046, 0.04), (-0.05, 0.01, 0.065, 0.058),
        (0.03, 0.006, 0.072, 0.066), (0.1, 0.014, 0.066, 0.062), (0.15, 0.034, 0.05, 0.05),
        (0.19, 0.064, 0.04, 0.041), (0.225, 0.08, 0.044, 0.045), (0.255, 0.081, 0.035, 0.036),
        (0.278, 0.074, 0.016, 0.02),
        # bill
        (0.3, 0.071, 0.011, 0.015), (0.325, 0.068, 0.009, 0.013), (0.345, 0.064, 0.006, 0.011),
        (0.362, 0.058, 0.0, 0.0)]
BILL_FROM = 0.278


def ring(s):
    z, cy, hw, hh = s
    out = []
    for k in range(N):
        a = 2 * math.pi * k / N
        # A little flatter underneath, fuller over the back.
        h = hh * (1.0 if math.cos(a) > 0 else 0.92)
        out.append(Vector((hw * math.sin(a), cy + h * math.cos(a), z)))
    return out


rings = [ring(s) for s in SECT]
for i in range(len(SECT) - 1):
    z0, z1 = SECT[i][0], SECT[i + 1][0]
    zc = (z0 + z1) / 2
    axis = Vector((0, (SECT[i][1] + SECT[i + 1][1]) / 2, zc))
    for k in range(N):
        a, b = rings[i][k], rings[i][(k + 1) % N]
        c, d = rings[i + 1][(k + 1) % N], rings[i + 1][k]
        mid = (a + b + c + d) / 4
        col = WHITE
        if z0 >= BILL_FROM:
            col = BILL
            # The gonys spot: underside of the lower mandible near its angle.
            if z0 >= 0.3 and z1 <= 0.345 and k in (4, 5): col = GONYS
            if z0 >= 0.325 and k in (4, 5): col = GONYS
        elif k in (0, N - 1) and -0.13 < zc < 0.13:
            col = MANTLE
        elif k in (1, N - 2) and -0.06 < zc < 0.1:
            col = MANTLE
        pts = [a, b, c, d]
        if (a - d).length < 1e-9: pts = [a, b, c]
        elif (b - c).length < 1e-9: pts = [a, b, d]
        face(pts, col, out=mid - axis)

# Eyes: small dark diamonds just proud of the head.
for side in (1, -1):
    c = Vector((0.0405 * side, 0.094, 0.236)); n = Vector((side, 0.25, 0.1)).normalized()
    c += n * 0.004
    u = Vector((0, 0, 1)); v = n.cross(u).normalized()
    r = 0.0065
    face([c + u * r, c + v * r * 0.8, c - u * r, c - v * r * 0.8], EYE, out=n)

# --- Tail: a white slab fanning out behind -----------------------------------------
TAIL = [(-0.15, 0.03, 0.045), (-0.24, 0.032, 0.062), (-0.31, 0.034, 0.07)]   # z, y, half-width
TT = 0.006
for i in range(len(TAIL) - 1):
    (z0, y0, w0), (z1, y1, w1) = TAIL[i], TAIL[i + 1]
    face([Vector((-w0, y0 + TT, z0)), Vector((w0, y0 + TT, z0)), Vector((w1, y1 + TT, z1)), Vector((-w1, y1 + TT, z1))],
         WHITE, A_TAIL, out=Vector((0, 1, 0)))
    face([Vector((-w0, y0 - TT, z0)), Vector((w0, y0 - TT, z0)), Vector((w1, y1 - TT, z1)), Vector((-w1, y1 - TT, z1))],
         WHITE, A_TAIL, out=Vector((0, -1, 0)))
    for s in (1, -1):
        face([Vector((s * w0, y0 + TT, z0)), Vector((s * w1, y1 + TT, z1)), Vector((s * w1, y1 - TT, z1)), Vector((s * w0, y0 - TT, z0))],
             WHITE, A_TAIL, out=Vector((s, 0, 0)))
z1, y1, w1 = TAIL[-1]
face([Vector((-w1, y1 + TT, z1)), Vector((w1, y1 + TT, z1)), Vector((w1, y1 - TT, z1)), Vector((-w1, y1 - TT, z1))],
     WHITE, A_TAIL, out=Vector((0, 0, -1)))

# --- Legs and webbed feet ------------------------------------------------------------
for side in (1, -1):
    top = Vector((0.024 * side, -0.035, 0.015)); heel = Vector((0.026 * side, -0.098, 0.022))
    w = 0.0045
    corners = [Vector((-w, 0, -w)), Vector((w, 0, -w)), Vector((w, 0, w)), Vector((-w, 0, w))]
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        face([top + a, top + b, heel + b, heel + a], LEG, A_LEG, out=(a + b))
    # Three toes splayed forward, webbed between.
    fy = -0.1
    toes = [Vector((heel.x + 0.02 * side, fy, heel.z + 0.038)), Vector((heel.x, fy, heel.z + 0.046)),
            Vector((heel.x - 0.017 * side, fy, heel.z + 0.036))]
    h = Vector((heel.x, fy, heel.z - 0.004))
    for k in range(2):
        face([h, toes[k], toes[k + 1]], LEG, A_LEG, out=Vector((0, 1, 0)))
        face([h, toes[k], toes[k + 1]], LEG, A_LEG, out=Vector((0, -1, 0)))

# --- Wings ---------------------------------------------------------------------------
# Span stations |x|, leading and trailing edge z at each; a crank at the wrist (0.4).
SPAN = [0.05, 0.12, 0.22, 0.32, 0.4, 0.48, 0.56, 0.62, 0.67, 0.72]
LE   = [0.11, 0.115, 0.115, 0.11, 0.1, 0.078, 0.046, 0.012, -0.04, -0.118]
TE   = [-0.08, -0.1, -0.1, -0.096, -0.09, -0.098, -0.108, -0.115, -0.122, -0.128]
CH = [0.0, 0.22, 0.55, 0.84, 1.0]     # chordwise samples, leading to trailing edge
BULGE_TOP = [0.0, 1.0, 0.6, 0.25, 0.0]
BULGE_BOT = [0.0, 0.3, 0.2, 0.08, 0.0]
ELBOW_I = SPAN.index(0.4)


def thick(s): return 0.017 * (1 - (s - 0.05) / 0.7) + 0.0015


def smooth(t): t = min(max(t, 0.0), 1.0); return t * t * (3 - 2 * t)


def folded(s, c, d, side):
    """Perched pose: the arm folds up short at the shoulder, the hand lies back along
    the body's side and over the back, tips crossing above the tail. Leading edge low
    on the flank, trailing edge up on the back; d (thickness offset) points outward."""
    u = (s - 0.05) / 0.67
    zf = table([0.0, 0.52, 1.0], [0.115, 0.03, -0.355], u)
    h = smooth((u - 0.45) / 0.55)
    le = Vector((lerp(0.08, 0.004, h), lerp(0.002, 0.03, h)))
    te = Vector((lerp(0.032, 0.0, h), lerp(0.082, 0.046, h)))
    p = le.lerp(te, c)
    nrm = Vector((te.y - le.y, -(te.x - le.x))).normalized()   # outward, away from the body
    if nrm.x < 0: nrm = -nrm
    p += nrm * (0.007 + 0.01 * math.sin(math.pi * c) * (1 - 0.6 * h) + d * 0.7)
    # Tips cross: the left wing's over the right's.
    x = side * p.x - side * 0.012 * smooth((u - 0.8) / 0.2)
    y = p.y + (0.007 if side < 0 else 0.0) * h
    return Vector((x, y, zf))


def wing_colour(i, j, top):
    s0, s1 = SPAN[i], SPAN[i + 1]
    if not top:
        if s0 >= 0.62: return BLACK
        if s0 >= 0.56: return UNDER_TIP if j < 2 else UNDER
        return UNDER
    if s0 >= 0.62:
        return WHITE if (s0 >= 0.67 and j == 1) else BLACK   # the mirror
    if s0 >= 0.56: return BLACK
    if j == 3: return WHITE if s0 < 0.56 else MANTLE         # white trailing edge
    return MANTLE


for side in (1, -1):
    grid_top, grid_bot, fold_top, fold_bot = [], [], [], []
    for i, s in enumerate(SPAN):
        t = thick(s)
        rt, rb, ft, fb = [], [], [], []
        for j, c in enumerate(CH):
            z = lerp(LE[i], TE[i], c)
            dt, db = t * BULGE_TOP[j], -t * BULGE_BOT[j]
            rt.append(Vector((side * s, WING_Y + dt, z))); rb.append(Vector((side * s, WING_Y + db, z)))
            ft.append(folded(s, c, dt, side)); fb.append(folded(s, c, db, side))
        grid_top.append(rt); grid_bot.append(rb); fold_top.append(ft); fold_bot.append(fb)
    for i in range(len(SPAN) - 1):
        for j in range(len(CH) - 1):
            for top, grid, fg in ((True, grid_top, fold_top), (False, grid_bot, fold_bot)):
                pts = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                fp = [fg[i][j], fg[i + 1][j], fg[i + 1][j + 1], fg[i][j + 1]]
                face(pts, wing_colour(i, j, top), A_WING, out=Vector((0, 1 if top else -1, 0)), fold=fp)
    # Close the wingtip.
    i = len(SPAN) - 1
    for j in range(len(CH) - 1):
        pts = [grid_top[i][j], grid_top[i][j + 1], grid_bot[i][j + 1], grid_bot[i][j]]
        fp = [fold_top[i][j], fold_top[i][j + 1], fold_bot[i][j + 1], fold_bot[i][j]]
        if (pts[0] - pts[3]).length < 1e-9: pts, fp = pts[:3], fp[:3]
        elif (pts[1] - pts[2]).length < 1e-9: pts, fp = [pts[0], pts[1], pts[3]], [fp[0], fp[1], fp[3]]
        face(pts, BLACK, A_WING, out=Vector((side, 0, 0)), fold=fp)

me = bpy.data.meshes.new("Seagull"); bm.to_mesh(me); bm.free(); me.materials.append(mat)
me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
ob = bpy.data.objects.new("Seagull", me); coll.objects.link(ob)

_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "assets", "models", "seagull_mid.glb"))
for o in bpy.data.objects: o.select_set(o == ob)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True, export_normals=True,
                          export_texcoords=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
bpy.ops.wm.save_mainfile()
result = {"tris": sum(len(p.vertices) - 2 for p in me.polygons), "glb": _glb}
