# Builds the mid-poly bald eagle in Blender (run inside Blender: exec(open(path).read()))
# and exports assets/models/eagle_mid.glb. An adult bald eagle at life size: white
# head and tail, chocolate-brown body and wings, a deep hooked yellow bill, brown
# feathered trousers over yellow feet with black talons, and broad plank wings whose
# outer primaries splay into six slotted "fingers" that curl up at the tips.
# Game frame: +Z forward, +Y up (Blender: forward -Y, Z up). Bill tip z = 0.415,
# tail tip z = -0.46, wingtips |x| ~ 1.05 (2.1 m span), feet at y = -0.2.
# eagle.gdshader conventions (as seagull.gdshader's):
#  - vertex alpha 1 = body, 0.97 = tail (closed up perched), 0.93 = legs (tucked away
#    in flight, swung forward to strike), 0.5 = wing;
#  - wing vertices hinge at |x| = SHOULDER (0.09) and ELBOW (0.5) about y = WING_Y;
#  - each wing vertex carries its folded (perched) position: UV = (x, y), UV2.x = z.
import bpy, bmesh, math, os
from mathutils import Vector


def G(x, y, z): return Vector((x, -z, y))


WHITE = (0.94, 0.93, 0.9); BODY = (0.24, 0.16, 0.1); COVERT = (0.34, 0.24, 0.15)
FLIGHT = (0.17, 0.12, 0.085); FINGER = (0.11, 0.085, 0.07); UNDER = (0.2, 0.14, 0.1)
TROUSER = (0.29, 0.2, 0.13)
BILL = (0.96, 0.8, 0.24); FOOT = (0.95, 0.78, 0.26); TALON = (0.08, 0.07, 0.07)
EYE = (0.93, 0.86, 0.45); PUPIL = (0.05, 0.05, 0.05)
A_BODY, A_TAIL, A_LEG, A_WING = 1.0, 0.97, 0.93, 0.5
WING_Y = 0.05
N = 10   # facets round the body

if not bpy.data.filepath.endswith("eagle_mid.blend"):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.wm.save_as_mainfile(filepath="/Users/jon/Documents/GitHub/lowpoly/art/eagle_mid.blend")
coll = bpy.data.collections.get("Eagle") or bpy.data.collections.new("Eagle")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_nt.links.new(_attr.outputs["Color"], _nt.nodes["Principled BSDF"].inputs["Base Color"])
for _n in ("Eagle",):
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


def smooth(t): t = min(max(t, 0.0), 1.0); return t * t * (3 - 2 * t)


def table(xs, ys, x):
    if x <= xs[0]: return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]: return lerp(ys[i], ys[i + 1], (x - xs[i]) / (xs[i + 1] - xs[i]))
    return ys[-1]


# --- Body, head and bill: lofted sections (z, centre y, half-width, half-height) ----
SECT = [(-0.24, 0.03, 0.0, 0.0),
        (-0.2, 0.026, 0.042, 0.036), (-0.13, 0.016, 0.082, 0.074), (-0.04, 0.006, 0.106, 0.098),
        (0.05, 0.006, 0.112, 0.104), (0.13, 0.024, 0.1, 0.096), (0.18, 0.05, 0.086, 0.084),
        (0.22, 0.078, 0.07, 0.07), (0.26, 0.096, 0.062, 0.066), (0.3, 0.1, 0.055, 0.06),
        (0.328, 0.094, 0.034, 0.046),
        # bill: deep at the cere, narrow, hooked down at the tip
        (0.345, 0.089, 0.017, 0.035), (0.367, 0.087, 0.014, 0.03), (0.387, 0.082, 0.01, 0.024),
        (0.402, 0.07, 0.006, 0.018), (0.41, 0.051, 0.0, 0.0)]
HEAD_FROM = 0.18
BILL_FROM = 0.328


def ring(s):
    z, cy, hw, hh = s
    out = []
    for k in range(N):
        a = 2 * math.pi * k / N
        # A little flatter underneath, fuller over the back.
        h = hh * (1.0 if math.cos(a) > 0 else 0.9)
        out.append(Vector((hw * math.sin(a), cy + h * math.cos(a), z)))
    return out


rings = [ring(s) for s in SECT]
for i in range(len(SECT) - 1):
    z0, z1 = SECT[i][0], SECT[i + 1][0]
    axis = Vector((0, (SECT[i][1] + SECT[i + 1][1]) / 2, (z0 + z1) / 2))
    for k in range(N):
        a, b = rings[i][k], rings[i][(k + 1) % N]
        c, d = rings[i + 1][(k + 1) % N], rings[i + 1][k]
        mid = (a + b + c + d) / 4
        if z0 >= BILL_FROM: col = BILL
        elif z0 >= HEAD_FROM: col = WHITE
        else: col = BODY
        pts = [a, b, c, d]
        if (a - d).length < 1e-9: pts = [a, b, c]
        elif (b - c).length < 1e-9: pts = [a, b, d]
        face(pts, col, out=mid - axis)

# Eyes: pale yellow under a jutting white brow, with a dark pupil.
for side in (1, -1):
    c = Vector((0.05 * side, 0.108, 0.29)); n = Vector((side, 0.15, 0.35)).normalized()
    c += n * 0.004
    u = Vector((0, 0, 1)); v = n.cross(u).normalized()
    r = 0.011
    face([c + u * r, c + v * r * 0.8, c - u * r, c - v * r * 0.8], EYE, out=n)
    cp = c + n * 0.0015 + u * 0.002
    face([cp + u * 0.004, cp + v * 0.004, cp - u * 0.004, cp - v * 0.004], PUPIL, out=n)
    # The brow: a white shelf over the eye, giving the scowl.
    b0 = Vector((0.044 * side, 0.124, 0.272)); b1 = Vector((0.046 * side, 0.124, 0.312))
    b2 = Vector((0.058 * side, 0.118, 0.308)); b3 = Vector((0.058 * side, 0.118, 0.27))
    face([b0, b1, b2, b3], WHITE, out=Vector((side * 0.3, 1, 0)))

# --- Tail: a broad white wedge, rounded at the end ----------------------------------
TAIL = [(-0.17, 0.03, 0.06), (-0.3, 0.034, 0.095), (-0.42, 0.036, 0.11)]   # z, y, half-width
TIP = (-0.46, 0.037)
TT = 0.008
for i in range(len(TAIL) - 1):
    (z0, y0, w0), (z1, y1, w1) = TAIL[i], TAIL[i + 1]
    for s, oy in ((1, TT), (-1, -TT)):
        face([Vector((-w0, y0 + oy, z0)), Vector((w0, y0 + oy, z0)), Vector((w1, y1 + oy, z1)), Vector((-w1, y1 + oy, z1))],
             WHITE, A_TAIL, out=Vector((0, s, 0)))
    for s in (1, -1):
        face([Vector((s * w0, y0 + TT, z0)), Vector((s * w1, y1 + TT, z1)), Vector((s * w1, y1 - TT, z1)), Vector((s * w0, y0 - TT, z0))],
             WHITE, A_TAIL, out=Vector((s, 0, 0)))
z1, y1, w1 = TAIL[-1]
end = [Vector((-w1, y1, z1)), Vector((-w1 * 0.55, TIP[1], TIP[0] + 0.012)), Vector((0, TIP[1], TIP[0])),
       Vector((w1 * 0.55, TIP[1], TIP[0] + 0.012)), Vector((w1, y1, z1))]
for k in range(len(end) - 1):
    a, b = end[k], end[k + 1]
    for s, oy in ((1, TT), (-1, -TT)):
        face([Vector((0, y1 + oy, z1)), a + Vector((0, oy, 0)), b + Vector((0, oy, 0))], WHITE, A_TAIL, out=Vector((0, s, 0)))
    face([a + Vector((0, TT, 0)), b + Vector((0, TT, 0)), b - Vector((0, TT, 0)), a - Vector((0, TT, 0))],
         WHITE, A_TAIL, out=(a + b) * 0.5 - Vector((0, y1, z1)))

# --- Legs: feathered trousers, yellow tarsi, four toes with black talons -----------
def prism(top, bot, wt, wb, col, alpha):
    ct = [Vector((-wt, 0, -wt)), Vector((wt, 0, -wt)), Vector((wt, 0, wt)), Vector((-wt, 0, wt))]
    cb = [Vector((-wb, 0, -wb)), Vector((wb, 0, -wb)), Vector((wb, 0, wb)), Vector((-wb, 0, wb))]
    for k in range(4):
        face([top + ct[k], top + ct[(k + 1) % 4], bot + cb[(k + 1) % 4], bot + cb[k]], col, alpha,
             out=ct[k] + ct[(k + 1) % 4])


for side in (1, -1):
    hip = Vector((0.05 * side, -0.05, 0.03)); knee = Vector((0.055 * side, -0.135, 0.04))
    ankle = Vector((0.055 * side, -0.185, 0.045))
    prism(hip, knee, 0.034, 0.024, TROUSER, A_LEG)
    prism(knee, ankle, 0.012, 0.011, FOOT, A_LEG)
    fy = -0.2
    h = Vector((ankle.x, fy, ankle.z))
    for dx, dz, ln in ((0.03, 0.05, 1.0), (0.0, 0.065, 1.0), (-0.025, 0.05, 0.9), (0.0, -0.05, 0.8)):
        tip = h + Vector((dx * side, 0, dz))
        across = Vector((dz, 0, -dx * side)).normalized() * 0.008
        face([h + across, tip + across * 0.5, tip - across * 0.5, h - across], FOOT, A_LEG, out=Vector((0, 1, 0)))
        face([h + across, tip + across * 0.5, tip - across * 0.5, h - across], FOOT, A_LEG, out=Vector((0, -1, 0)))
        # Talon: a hooked black spur curling down off the toe tip.
        dirn = Vector((dx * side, 0, dz)).normalized()
        claw = tip + dirn * 0.018 + Vector((0, -0.012, 0))
        face([tip + across * 0.5, claw, tip - across * 0.5], TALON, A_LEG, out=Vector((0, 1, 0)))
        face([tip + across * 0.5, claw, tip - across * 0.5], TALON, A_LEG, out=Vector((0, -1, 0)))

# --- Wings ---------------------------------------------------------------------------
# The arm and hand: span stations |x| with leading/trailing edge z; the wrist (ELBOW)
# at 0.5. Past 0.77 the six fingered primaries take over.
SPAN = [0.08, 0.2, 0.32, 0.44, 0.5, 0.6, 0.7, 0.77]
LE   = [0.12, 0.13, 0.132, 0.126, 0.12, 0.108, 0.094, 0.08]
TE   = [-0.21, -0.29, -0.31, -0.305, -0.29, -0.255, -0.21, -0.17]
CH = [0.0, 0.2, 0.45, 0.75, 1.0]      # chordwise samples, leading to trailing edge
BULGE_TOP = [0.0, 1.0, 0.65, 0.25, 0.0]
BULGE_BOT = [0.0, 0.35, 0.2, 0.08, 0.0]
REACH = 1.05


def thick(s): return 0.03 * (1 - (s - 0.08) / 0.75) + 0.004


def folded(u, c, d, side):
    """Perched pose (u 0..1 along the span, c 0..1 across the chord, d thickness
    offset): the arm folds short at the shoulder, the hand lies back along the flank,
    leading edge low, trailing edge up over the back, primaries reaching most of the
    way down the tail."""
    zf = table([0.0, 0.45, 1.0], [0.15, 0.05, -0.39], u)
    h = smooth((u - 0.4) / 0.6)
    le = Vector((lerp(0.118, 0.052, h), lerp(-0.02, 0.025, h)))
    te = Vector((lerp(0.05, 0.016, h), lerp(0.122, 0.066, h)))
    p = le.lerp(te, c)
    nrm = Vector((te.y - le.y, -(te.x - le.x))).normalized()   # outward, away from the body
    if nrm.x < 0: nrm = -nrm
    p += nrm * (0.008 + 0.012 * math.sin(math.pi * c) * (1 - 0.6 * h) + d * 0.7)
    return Vector((side * p.x, p.y + (0.006 if side < 0 else 0.0) * h, zf))


def span_u(x): return (x - SPAN[0]) / (REACH - SPAN[0])


def wing_colour(i, j, top):
    s0 = SPAN[i]
    if not top:
        return FLIGHT if (j >= 2 or s0 >= 0.6) else UNDER
    if s0 < 0.5 and j < 2: return COVERT
    return FLIGHT


for side in (1, -1):
    grid_top, grid_bot, fold_top, fold_bot = [], [], [], []
    for i, s in enumerate(SPAN):
        t = thick(s)
        rt, rb, ft, fb = [], [], [], []
        for j, c in enumerate(CH):
            z = lerp(LE[i], TE[i], c)
            dt, db = t * BULGE_TOP[j], -t * BULGE_BOT[j]
            rt.append(Vector((side * s, WING_Y + dt, z))); rb.append(Vector((side * s, WING_Y + db, z)))
            ft.append(folded(span_u(s), c, dt, side)); fb.append(folded(span_u(s), c, db, side))
        grid_top.append(rt); grid_bot.append(rb); fold_top.append(ft); fold_bot.append(fb)
    for i in range(len(SPAN) - 1):
        for j in range(len(CH) - 1):
            for top, grid, fg in ((True, grid_top, fold_top), (False, grid_bot, fold_bot)):
                pts = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                fp = [fg[i][j], fg[i + 1][j], fg[i + 1][j + 1], fg[i][j + 1]]
                face(pts, wing_colour(i, j, top), A_WING, out=Vector((0, 1 if top else -1, 0)), fold=fp)
    # Close the hand's outer edge (the fingers spring from it).
    i = len(SPAN) - 1
    for j in range(len(CH) - 1):
        pts = [grid_top[i][j], grid_top[i][j + 1], grid_bot[i][j + 1], grid_bot[i][j]]
        fp = [fold_top[i][j], fold_top[i][j + 1], fold_bot[i][j + 1], fold_bot[i][j]]
        if (pts[0] - pts[3]).length < 1e-9: pts, fp = pts[:3], fp[:3]
        elif (pts[1] - pts[2]).length < 1e-9: pts, fp = [pts[0], pts[1], pts[3]], [fp[0], fp[1], fp[3]]
        face(pts, FLIGHT, A_WING, out=Vector((side, 0, 0)), fold=fp)

    # The fingers: six primaries fanning from the hand's edge, slotted apart at the
    # tips, longest in the middle (a rounded, "fingered" wingtip), tips curled up.
    NF = 6
    x0 = SPAN[-1] - 0.015
    for f in range(NF):
        q = f / (NF - 1)
        base = Vector((side * x0, WING_Y, lerp(LE[-1] - 0.012, TE[-1] + 0.03, q)))
        ang = lerp(0.12, -0.55, q)                           # fanned: front ones forward
        dirn = Vector((side * math.cos(ang), 0.0, math.sin(ang)))
        ln = table([0.0, 0.35, 0.6, 1.0], [0.22, 0.27, 0.26, 0.15], q)
        across = Vector((-dirn.z * side, 0, dirn.x * side)).normalized()
        if across.z < 0: across = -across
        stations = [(0.0, 0.036, 0.0), (0.55, 0.031, 0.012), (1.0, 0.014, 0.036)]   # t, width, curl
        tt = 0.004
        top_pts, bot_pts, ftop, fbot = [], [], [], []
        for t, w, curl in stations:
            centre = base + dirn * (ln * t) + Vector((0, curl, 0))
            u = span_u(abs(centre.x))
            row_t, row_b, rf_t, rf_b = [], [], [], []
            for e in (1, -1):
                p = centre + across * (w * 0.5 * e)
                row_t.append(p + Vector((0, tt, 0))); row_b.append(p - Vector((0, tt, 0)))
                # Folded, the fingers stack along the hand, front one outermost.
                c = min(max(0.35 + 0.3 * q + 0.03 * e, 0.0), 1.0)
                rf_t.append(folded(min(u, 1.0), c, tt, side)); rf_b.append(folded(min(u, 1.0), c, -tt, side))
            top_pts.append(row_t); bot_pts.append(row_b); ftop.append(rf_t); fbot.append(rf_b)
        for k in range(len(stations) - 1):
            for grid, fg, up in ((top_pts, ftop, 1), (bot_pts, fbot, -1)):
                face([grid[k][0], grid[k + 1][0], grid[k + 1][1], grid[k][1]], FINGER, A_WING,
                     out=Vector((0, up, 0)), fold=[fg[k][0], fg[k + 1][0], fg[k + 1][1], fg[k][1]])
            for e in (0, 1):
                face([top_pts[k][e], top_pts[k + 1][e], bot_pts[k + 1][e], bot_pts[k][e]], FINGER, A_WING,
                     out=across * (1 if e == 0 else -1), fold=[ftop[k][e], ftop[k + 1][e], fbot[k + 1][e], fbot[k][e]])

me = bpy.data.meshes.new("Eagle"); bm.to_mesh(me); bm.free(); me.materials.append(mat)
me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
ob = bpy.data.objects.new("Eagle", me); coll.objects.link(ob)

_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "assets", "models", "eagle_mid.glb"))
for o in bpy.data.objects: o.select_set(o == ob)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True, export_normals=True,
                          export_texcoords=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
bpy.ops.wm.save_mainfile()
result = {"tris": sum(len(p.vertices) - 2 for p in me.polygons), "glb": _glb}
