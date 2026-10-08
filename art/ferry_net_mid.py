# Builds the mid-poly car deck net every ferry hangs across each end of its car deck
# (Models.ferry_net), in Blender (run inside Blender: exec(open(path).read())), and
# exports it to assets/models/ferry_net_mid.glb (glTF, +Y up, vertex colours, flat
# shaded). Metres. Game frame: the net in the plane z = 0, +Y up, the car deck at y = 0
# (Blender: game z to -Y, Z up).
#
# A net spans the deck from wall to wall in three bays: its ends shackled to a bracket
# on each wall (or gunwale), two posts between, a third of the way across. Parts:
#   `post`    a yellow pipe stanchion on its foot plate at x = 0, POST_H tall.
#   `eye`     the wall bracket: a yellow flat bar on the wall face (x = 0, the net to
#             +x) with an eye at the head and foot ropes' height.
#   `bay_N`   one span of net N metres wide (BAYS), from x = 0 to N (the posts' centres
#             or the wall): a heavy head rope slung between with a little sag, a lighter
#             foot rope, a lashing up each side, and the diamond mesh of manila between,
#             its strands cut at every knot (their open ends overlapping there). The game
#             takes the width nearest its own, stretches it to fit and lets it billow and
#             flutter in the wind (net_flap in shaders/lit_vc.gdshaderinc), bending the
#             strands at the knots.
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "yellow": (0.9, 0.72, 0.1), "plate": (0.42, 0.4, 0.36), "rope": (0.72, 0.6, 0.4),
    "line": (0.56, 0.45, 0.3),
}
POST_H = 1.72
POST_R = 0.045
BAYS = (4, 5, 6)  # the bays' widths (m)
MESH = 0.32      # a diamond's width, about
TOP_Y = 1.6       # top rope at the posts
TOP_SAG = 0.11
FOOT_Y = 0.14
FOOT_SAG = 0.03
SIDE_X = 0.09     # the side lashings, in from the posts' centres
ROWS = 6          # knot rows between the foot rope and the top rope


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))


coll = bpy.data.collections.get("FerryNet") or bpy.data.collections.new("FerryNet")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
for o in list(coll.objects):
    bpy.data.objects.remove(o, do_unlink=True)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_nt.links.new(_attr.outputs["Color"], _nt.nodes["Principled BSDF"].inputs["Base Color"])

BMS = {}
PART = ["post"]


def face(pts, key):
    q = [pts[0]]
    for p in pts[1:]:
        if (p - q[-1]).length > 1e-6: q.append(p)
    if len(q) > 2 and (q[0] - q[-1]).length < 1e-6: q.pop()
    if len(q) < 3: return
    if PART[0] not in BMS:
        bm = bmesh.new(); bm.loops.layers.color.new("Col"); BMS[PART[0]] = bm
    bm = BMS[PART[0]]; cl = bm.loops.layers.color["Col"]
    try:
        f = bm.faces.new([bm.verts.new(G(p)) for p in q])
    except ValueError:
        return
    f.smooth = False
    for l in f.loops: l[cl] = (*PAL[key], 1.0)


def normal(pts):
    n = Vector()
    for i in range(len(pts)):
        n += pts[i].cross(pts[(i + 1) % len(pts)])
    return n


def centre(pts): return sum(pts, Vector()) / len(pts)


def loft(rings, key, caps=True):
    """Quads between successive closed rings, wound outward; capped at both ends."""
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        ax = (centre(a) + centre(b)) * 0.5
        for j in range(n):
            k = (j + 1) % n
            q = [a[j], a[k], b[k], b[j]]
            face(q if normal(q).dot(centre(q) - ax) > 0 else q[::-1], key)
    if caps:
        for r, o in ((rings[0], rings[1]), (rings[-1], rings[-2])):
            out = centre(r) - centre(o)
            face(r if normal(r).dot(out) > 0 else r[::-1], key)


def frame(ax):
    e1 = ax.cross(V(0.3, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0)).normalized()
    return e1, ax.cross(e1).normalized()


def circle(c, ax, r, n, a0=0.0):
    e1, e2 = frame(ax)
    return [c + (e1 * math.cos(a0 + math.tau * i / n) + e2 * math.sin(a0 + math.tau * i / n)) * r for i in range(n)]


def cyl(a, b, r0, r1, n, key):
    ax = (b - a).normalized()
    loft([circle(a, ax, r0, n, math.pi / n), circle(b, ax, r1, n, math.pi / n)], key)


def tube(path, r, n, key, caps=True):
    """A rope along a polyline, a ring at every point (so it bends there in game)."""
    rings, prev = [], None
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        e1 = (prev - prev.dot(t) * t).normalized() if prev is not None else frame(t)[0]
        prev = e1; e2 = t.cross(e1)
        rings.append([p + (e1 * math.cos(math.tau * k / n) + e2 * math.sin(math.tau * k / n)) * r for k in range(n)])
    loft(rings, key, caps)


def box(c, size, key):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    ring = lambda y: [V(c.x + hx, y, c.z - hz), V(c.x + hx, y, c.z + hz), V(c.x - hx, y, c.z + hz), V(c.x - hx, y, c.z - hz)]
    loft([ring(c.y - hy), ring(c.y + hy)], key)


def post():
    PART[0] = "post"
    box(V(0, 0.015, 0), (0.26, 0.03, 0.2), "plate")
    for x in (-0.09, 0.09):
        box(V(x, 0.075, 0), (0.012, 0.09, 0.14), "plate")     # gussets
    cyl(V(0, 0.03, 0), V(0, POST_H, 0), POST_R, POST_R, 8, "yellow")
    cyl(V(0, POST_H, 0), V(0, POST_H + 0.03, 0), POST_R + 0.012, POST_R * 0.6, 8, "yellow")
    # Eyes the top and foot ropes are shackled to, either side.
    for y in (TOP_Y, FOOT_Y):
        cyl(V(-0.075, y, 0), V(0.075, y, 0), 0.022, 0.022, 6, "plate")


def eye():
    PART[0] = "eye"
    box(V(0.006, (TOP_Y + 0.12) / 2, 0), (0.012, TOP_Y + 0.12, 0.1), "yellow")
    for y in (TOP_Y, FOOT_Y):
        cyl(V(0.0, y, 0), V(0.085, y, 0), 0.022, 0.022, 6, "plate")


def bay(bay_w):
    """The net's knots sit on a diamond lattice: row j's knots are offset half a diamond
    from row j-1's, and each strand runs from a knot to the two above it. Row 0 is
    seized to the foot rope and row ROWS to the top rope; the outermost half diamonds
    end on the side lashings."""
    PART[0] = "bay_%d" % bay_w
    cols = round(bay_w / MESH)
    top_y = lambda x: TOP_Y - TOP_SAG * (bay_w / 4.0) * 4.0 * (x / bay_w) * (1.0 - x / bay_w)
    foot_y = lambda x: FOOT_Y - FOOT_SAG * 4.0 * (x / bay_w) * (1.0 - x / bay_w)
    x0, x1 = SIDE_X, bay_w - SIDE_X
    xs = [x0 + (x1 - x0) * i / (2 * cols) for i in range(2 * cols + 1)]
    tops = [V(x, top_y(x), 0) for x in xs]
    feet = [V(x, foot_y(x), 0) for x in xs]
    # Head and foot ropes, end to end (a wider bay sags more).
    ends = [V(0.075, TOP_Y, 0)] + tops + [V(bay_w - 0.075, TOP_Y, 0)]
    tube(ends, 0.026, 5, "line")
    tube([V(0.075, FOOT_Y, 0)] + feet + [V(bay_w - 0.075, FOOT_Y, 0)], 0.018, 4, "line")

    def knot(i, j):
        # Half-diamond column i (0..2*cols) on row j (0..ROWS); a knot only where
        # i + j is even.
        t = j / ROWS
        return feet[i].lerp(tops[i], t)

    for x in (x0, x1):
        i = 0 if x == x0 else 2 * cols
        tube([knot(i, j) for j in range(ROWS + 1)], 0.016, 4, "line")
    for j in range(ROWS):
        for i in range(2 * cols + 1):
            if (i + j) % 2:
                continue
            for di in (-1, 1):
                if 0 <= i + di <= 2 * cols:
                    # Open ended: the strands' ends meet in the knots.
                    tube([knot(i, j), knot(i + di, j + 1)], 0.013, 3, "rope", caps=False)


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    post(); eye()
    for w in BAYS:
        bay(w)
    obs = []
    for part, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("ferry_net_" + part)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("ferry_net_" + part); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(part, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "ferry_net_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("FERRY NET", result)
