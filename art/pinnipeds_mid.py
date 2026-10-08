# Builds the mid-poly harbor seal and California sea lion in Blender (run inside
# Blender: exec(open(path).read())) and exports assets/models/pinnipeds_mid.glb with
# objects "HarborSeal" and "SeaLion".
# Game frame, as Models' code-built ones: one unit long, +Z forward, nose at z = 0.5,
# lying on its belly with the bottom of the belly at y = 0, +Y up (Blender: forward -Y,
# Z up). pinniped.gdshader bends the head up past neck_z and the hind flippers up
# behind hip_z (Pinnipeds' Kind), about y = 0.08, so the shapes keep the old stations.
# Coats are pale and tinted per animal by the instance colour.
import bpy, bmesh, math, os, random
from mathutils import Vector


def G(x, y, z): return Vector((x, -z, y))


NR = 16        # facets round the body
NS = 30        # rings nose to tail
EYE = (0.03, 0.03, 0.035)

if not bpy.data.filepath.endswith("pinnipeds_mid.blend"):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.wm.save_as_mainfile(filepath="/Users/jon/Documents/GitHub/lowpoly/art/pinnipeds_mid.blend")
coll = bpy.data.collections.get("Pinnipeds") or bpy.data.collections.new("Pinnipeds")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_nt.links.new(_attr.outputs["Color"], _nt.nodes["Principled BSDF"].inputs["Base Color"])
for _n in ("HarborSeal", "SeaLion"):
    _o = bpy.data.objects.get(_n)
    if _o: bpy.data.objects.remove(_o, do_unlink=True)
    _m = bpy.data.meshes.get(_n)
    if _m: bpy.data.meshes.remove(_m)


def interp(S, tab, s):
    s = min(max(s, S[0]), S[-1])
    for i in range(len(S) - 1):
        if S[i] <= s <= S[i + 1]:
            t = (s - S[i]) / (S[i + 1] - S[i])
            p0 = tab[max(i - 1, 0)]; p1 = tab[i]; p2 = tab[i + 1]; p3 = tab[min(i + 2, len(S) - 1)]
            return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def lens(c, w, thk, M, yaw, tip_dz=None, roll=0.0):
    """A thin flat section across a flipper: M + 1 points along the top edge, back
    along the bottom, centred on c, its width turned `yaw` from +X and banked `roll`."""
    ax = Vector((math.cos(yaw), 0, -math.sin(yaw)))
    up = Vector((-ax.x * math.sin(roll), math.cos(roll), -ax.z * math.sin(roll)))
    top, bot = [], []
    for j in range(M + 1):
        f = 2 * j / M - 1
        h = thk * math.sqrt(max(1 - f * f, 0.0)) + 0.0008
        dz = tip_dz(f) if tip_dz else 0.0
        p = c + ax * (f * w / 2) + Vector((0, 0, dz))
        top.append(p + up * h); bot.append(p - up * h)
    return top + list(reversed(bot))[1:-1]


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.cl = self.bm.loops.layers.color.new("Col")

    def paint(self, f, col):
        for l in f.loops: l[self.cl] = (col[0], col[1], col[2], 1.0)

    def loft(self, sections, col, cap0=True, cap1=True):
        """Sections are closed loops of game-space points, the same count each."""
        bm = self.bm
        vr = [[bm.verts.new(G(*p)) for p in sec] for sec in sections]; n = len(sections[0]); out = []
        for i in range(len(vr) - 1):
            for j in range(n):
                out.append(bm.faces.new([vr[i][j], vr[i][(j + 1) % n], vr[i + 1][(j + 1) % n], vr[i + 1][j]]))
        if cap0: out.append(bm.faces.new(list(reversed(vr[0]))))
        if cap1: out.append(bm.faces.new(vr[-1]))
        for f in out: self.paint(f, col(f) if callable(col) else col)
        return vr

    def eye(self, c, normal, r, col=EYE):
        """A little dark dome sitting on the surface at c, facing `normal`."""
        n = normal.normalized()
        a = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized()
        b = n.cross(a)
        ring = [c + (a * math.cos(2 * math.pi * k / 8) + b * math.sin(2 * math.pi * k / 8)) * r for k in range(8)]
        mid = [c + n * (r * 0.35) + (a * math.cos(2 * math.pi * k / 8) + b * math.sin(2 * math.pi * k / 8)) * r * 0.6 for k in range(8)]
        top = c + n * (r * 0.5)
        bm = self.bm
        rv = [bm.verts.new(G(*p)) for p in ring]; mv = [bm.verts.new(G(*p)) for p in mid]; tv = bm.verts.new(G(*top))
        for k in range(8):
            k1 = (k + 1) % 8
            self.paint(bm.faces.new([rv[k], rv[k1], mv[k1], mv[k]]), col)
            self.paint(bm.faces.new([mv[k], mv[k1], tv]), col)

    def finish(self, name):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        for p in me.polygons: p.use_smooth = True
        ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
        return ob


def body(b, S, TOP, BOT, HW, colour, nose, nose_col, ex_top=2.3, ex_bot=3.6):
    """The trunk lofted nose to tail through the profile tables (keyed on s = distance
    back from the nose): round over the back, flatter under the belly. Each vertex is
    painted `colour`(s, theta, side) (theta 0 on the back, pi the belly), so markings
    blend across faces; faces within `nose` of the tip are the nose pad."""
    end = S[-1]
    sl = [end * (i / (NS - 1)) ** 1.25 for i in range(NS)]
    secs, at = [], []
    for s in sl:
        secs.append([surface(S, TOP, BOT, HW, s, 2 * math.pi * k / NR, ex_top, ex_bot) for k in range(NR)])
        at.append([(s, min(a, 2 * math.pi - a), 1 if a <= math.pi else -1) for a in (2 * math.pi * k / NR for k in range(NR))])
    vr = b.loft(secs, nose_col)
    vcol = {v: colour(*at[i][k]) for i, ring in enumerate(vr) for k, v in enumerate(ring)}
    for f in {f for ring in vr for v in ring for f in v.link_faces}:
        if 0.5 + f.calc_center_median().y < nose:   # s = 0.5 - game z = 0.5 + Blender y
            continue
        for l in f.loops:
            c = vcol[l.vert]
            l[b.cl] = (c[0], c[1], c[2], 1.0)
    return lambda s, a: surface(S, TOP, BOT, HW, s, a, ex_top, ex_bot)


def surface(S, TOP, BOT, HW, s, a, ex_top, ex_bot):
    t_, b_, w_ = interp(S, TOP, s), interp(S, BOT, s), interp(S, HW, s)
    c, h = (t_ + b_) / 2, (t_ - b_) / 2
    sa, ca = math.sin(a), math.cos(a)
    ex = ex_top if ca >= 0 else ex_bot
    return Vector((w_ * math.copysign(abs(sa) ** (2 / ex), sa), c + h * math.copysign(abs(ca) ** (2 / ex), ca), 0.5 - s))


def flipper(b, root, tip, chords, thk, yaw, col, roll=0.0, M=4, tip_dz=None, drop=None):
    """A flipper lofted root to tip through len(chords) sections."""
    secs = []
    n = len(chords)
    for i, ch in enumerate(chords):
        u = i / (n - 1)
        c = root.lerp(tip, u)
        if drop: c.y += drop(u)
        secs.append(lens(c, ch, thk * (1 - 0.6 * u), M, yaw, tip_dz if i == n - 1 else None, roll))
    b.loft(secs, col)


def spots(seed, n, s_range, th_max, r_range):
    rnd = random.Random(seed)
    return [(rnd.uniform(*s_range), rnd.uniform(-th_max, th_max), rnd.uniform(*r_range)) for _ in range(n)]


# --- Harbor seal ------------------------------------------------------------------
# Rotund and neckless, a short broad dog-like muzzle, a round forehead and big eyes,
# short clawed fore flippers held to the chest, a short fan of hind flippers.
# Pale grey, darker along the back, softly dappled, paler underneath.
COAT = (0.86, 0.85, 0.82); BACK = (0.72, 0.71, 0.69); SPOT = (0.4, 0.39, 0.38)
BELLY = (0.95, 0.94, 0.9); MUZZLE = (0.92, 0.91, 0.88); NOSE = (0.1, 0.1, 0.11)
FLIP = (0.5, 0.49, 0.47)

S   = [0.0,   0.012, 0.03,  0.055, 0.085, 0.12,  0.165, 0.22,  0.3,   0.4,   0.5,   0.6,   0.7,   0.78,  0.84,  0.875]
TOP = [0.08,  0.092, 0.108, 0.128, 0.142, 0.148, 0.152, 0.162, 0.188, 0.21,  0.214, 0.196, 0.15,  0.11,  0.086, 0.076]
BOT = [0.058, 0.048, 0.04,  0.034, 0.032, 0.03,  0.024, 0.014, 0.004, 0.0,   0.0,   0.004, 0.018, 0.032, 0.042, 0.048]
HW  = [0.016, 0.03,  0.043, 0.055, 0.066, 0.072, 0.078, 0.088, 0.106, 0.12,  0.124, 0.11,  0.078, 0.048, 0.03,  0.022]
SPOTS = spots(11, 40, (0.07, 0.86), 2.5, (0.03, 0.05))


def mix(a, b, t):
    t = min(max(t, 0.0), 1.0)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def seal_colour(s, theta, side):
    c = mix(COAT, BACK, (1 - theta / 1.6) ** 2 if theta < 1.6 else 0.0)
    c = mix(c, BELLY, smooth(1.9, 2.5, theta) * smooth(0.14, 0.22, s))
    dots = 0.0
    for ss, st, r in SPOTS:
        d2 = (s - ss) ** 2 + ((theta * side - st) * 0.075) ** 2
        dots = max(dots, math.exp(-d2 / (r * r)))
    c = mix(c, SPOT, 0.6 * dots * (1 - 0.6 * smooth(1.9, 2.6, theta)))
    return mix(c, MUZZLE, smooth(0.06, 0.03, s))


b = Builder()
surf = body(b, S, TOP, BOT, HW, seal_colour, 0.004, NOSE)
for side in (1, -1):
    # Big dark eyes high on the sides of the head, looking a little forward.
    p = surf(0.075, side * 0.95); b.eye(p, Vector((side * 0.85, 0.35, 0.45)), 0.0125)
    # Fore flippers: short, flat against the flank, claws to the rear.
    flipper(b, Vector((side * 0.104, 0.034, 0.205)), Vector((side * 0.146, 0.01, 0.125)),
            [0.06, 0.058, 0.048, 0.028], 0.009, side * -1.1, FLIP, roll=side * 0.5)
    # Hind flippers: webbed fans from the tail end, outer toes longest.
    flipper(b, Vector((side * 0.014, 0.05, -0.355)), Vector((side * 0.04, 0.045, -0.455)),
            [0.024, 0.04, 0.06, 0.07], 0.008, side * 0.3, FLIP, roll=side * 0.25, M=6,
            tip_dz=lambda f: -0.018 * f * f)
seal = b.finish("HarborSeal")


# --- California sea lion ----------------------------------------------------------
# Longer and sleeker: a pointed snout with a step up to the forehead, little ear
# flaps laid back, a real neck, a deep chest, and long dark fore flippers it props
# itself on. Brown (tinted), darker along the back, the muzzle paler.
COAT = (0.86, 0.84, 0.8); BACK = (0.7, 0.68, 0.65); BELLY = (0.9, 0.88, 0.84); MUZZLE = (0.95, 0.93, 0.88)
FLIP = (0.36, 0.34, 0.33); NOSE = (0.12, 0.11, 0.11)

S   = [0.0,   0.015, 0.04,  0.07,  0.1,   0.135, 0.18,  0.23,  0.3,   0.38,  0.47,  0.57,  0.67,  0.76,  0.82,  0.86]
TOP = [0.13,  0.138, 0.148, 0.164, 0.176, 0.176, 0.168, 0.172, 0.194, 0.208, 0.204, 0.18,  0.138, 0.096, 0.07,  0.062]
BOT = [0.112, 0.106, 0.1,   0.098, 0.098, 0.094, 0.08,  0.058, 0.026, 0.006, 0.0,   0.003, 0.014, 0.028, 0.036, 0.04]
HW  = [0.014, 0.025, 0.033, 0.04,  0.046, 0.049, 0.05,  0.06,  0.088, 0.108, 0.112, 0.1,   0.07,  0.04,  0.026, 0.02]


def lion_colour(s, theta, side):
    c = mix(COAT, BACK, smooth(1.3, 0.4, theta) * smooth(0.1, 0.2, s))
    c = mix(c, BELLY, smooth(2.0, 2.6, theta))
    return mix(c, MUZZLE, smooth(0.075, 0.045, s))


b = Builder()
surf = body(b, S, TOP, BOT, HW, lion_colour, 0.004, NOSE, ex_top=2.2, ex_bot=3.0)
for side in (1, -1):
    b.eye(surf(0.085, side * 1.0), Vector((side * 0.9, 0.3, 0.4)), 0.0095)
    # Ear flaps: little rolled tabs laid back along the head.
    e = surf(0.13, side * 0.85)
    flipper(b, e, e + Vector((side * 0.006, 0.002, -0.02)), [0.009, 0.007, 0.002], 0.003,
            0.0, FLIP, roll=side * 1.4, M=2)
    # Long fore flippers, out to the side and back, palms flat on the ground.
    flipper(b, Vector((side * 0.09, 0.05, 0.17)), Vector((side * 0.25, 0.006, -0.02)),
            [0.075, 0.08, 0.072, 0.058, 0.03], 0.01, side * -0.85, FLIP,
            drop=lambda u: -0.02 * math.sin(math.pi * u), tip_dz=lambda f: 0.008 * f)
    # Hind flippers: long and narrow, the toes running out into flaps.
    flipper(b, Vector((side * 0.013, 0.036, -0.335)), Vector((side * 0.05, 0.03, -0.455)),
            [0.028, 0.04, 0.052, 0.058], 0.007, side * 0.33, FLIP, roll=side * 0.2, M=6,
            tip_dz=lambda f: -0.016 * f * f)
lion = b.finish("SeaLion")

seal.location.x = -0.3; lion.location.x = 0.3
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "assets", "models", "pinnipeds_mid.glb"))
for o in bpy.data.objects: o.select_set(o in (seal, lion))
seal.location.x = lion.location.x = 0.0
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True, export_normals=True,
                          export_texcoords=False, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
seal.location.x = -0.3; lion.location.x = 0.3
bpy.ops.wm.save_mainfile()
result = {"tris": {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (seal, lion)}, "glb": _glb}
