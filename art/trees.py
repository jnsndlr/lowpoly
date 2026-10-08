# Builds the faceted trees in Blender (run inside Blender: exec(open(path).read())) and
# exports them to assets/models/trees.glb (glTF, +Y up, vertex colours).
# Modelled on the two tree study sheets (pines and broadleaves): pine tiers made of broad
# flat branch paddles, each creased down the middle so one half takes the sun and the
# other is in shade, with a serrated tip and a dark underside; broadleaf crowns of
# clustered leaf rosettes on a trunk that forks into visible limbs.
# Every tree stands on the origin, ground at z = 0 (Godot y = 0), trunk running down to
# z = -0.4 so it never floats on a slope. Faces are flat-shaded.
# Each variant has a cheap stand-in named <name>_lod (same outline, few faces) that
# Models swaps in past Models.TREE_LOD_DIST; spruces also have <name>_mid, drawn from
# Models.TREE_NEAR_DIST to TREE_MID_DIST, where their stand-in takes over.
import bpy, bmesh, math, random, os
from mathutils import Vector

UP = Vector((0, 0, 1))
BARK = (0.42, 0.26, 0.16)
BIRCH = (0.86, 0.84, 0.77)
BIRCH_MARK = (0.28, 0.27, 0.25)
# Foliage palettes: shade (under / facing down), mid (side-on), lit (facing up).
NEEDLES = ((0.09, 0.25, 0.17), (0.2, 0.44, 0.2), (0.5, 0.64, 0.2))
LEAVES = ((0.13, 0.32, 0.16), (0.32, 0.53, 0.18), (0.64, 0.73, 0.22))
# Spruce boughs are coloured by part, as in the studies: their backs light green at the
# bottom of the tree to yellow-green at the top, the slab sides darker, underneath dark.
SPRUCE_BACK_LOW = (0.3, 0.5, 0.2)
SPRUCE_BACK_HIGH = (0.66, 0.74, 0.28)
SPRUCE_SIDE = 0.6
SPRUCE_UNDER = (0.08, 0.2, 0.13)

# Pines: h height, r radius of the lowest tier, space between tiers (x the tier's
# radius), k paddles per tier, base the height of the lowest tier (bare trunk below),
# droop of the paddles, gap (fraction of paddles missing), wide (paddle width
# multiplier), lean (m at the top), sweep (paddles longer downwind, the lean side), seed.
PINES = {
    "pine_full":    dict(h=7.0, r=2.0, space=0.5, k=8, base=0.7, droop=0.35, gap=0.0, wide=1.0, lean=0.0, sweep=0.0, seed=1),
    "pine_sparse":  dict(h=7.4, r=1.9, space=0.7, k=6, base=1.4, droop=0.3, gap=0.18, wide=0.85, lean=0.15, sweep=0.0, seed=2),
    "pine_broad":   dict(h=6.4, r=2.3, space=0.45, k=9, base=0.5, droop=0.4, gap=0.0, wide=1.1, lean=0.0, sweep=0.0, seed=3),
    "pine_slender": dict(h=7.2, r=1.5, space=0.62, k=6, base=1.0, droop=0.3, gap=0.1, wide=0.9, lean=0.1, sweep=0.0, seed=4),
    "pine_lean":    dict(h=6.8, r=1.9, space=0.55, k=7, base=1.0, droop=0.4, gap=0.05, wide=1.0, lean=0.9, sweep=0.35, seed=5),
    "pine_young":   dict(h=3.6, r=1.3, space=0.5, k=6, base=0.35, droop=0.25, gap=0.0, wide=1.0, lean=0.0, sweep=0.0, seed=6),
}
# Broadleaves: crown centre height cz and radii (rx across, rz up), clumps and their
# radius, limbs, fork height, trunk radius, lean (m the crown sits off the base), seed.
# `stems` > 1 makes a clump of thin birches, each with its own small crown.
BROADS = {
    "oak":       dict(cz=4.2, rx=2.4, rz=1.9, clumps=14, cr=1.1, limbs=4, fork=2.0, tr=0.3, lean=0.0, seed=11),
    "poplar":    dict(cz=4.6, rx=1.1, rz=3.0, clumps=13, cr=0.75, limbs=2, fork=2.0, tr=0.2, lean=0.0, seed=12),
    "spreading": dict(cz=4.0, rx=2.8, rz=1.7, clumps=15, cr=1.1, limbs=5, fork=1.7, tr=0.34, lean=0.2, seed=13),
    "leaning":   dict(cz=4.1, rx=2.0, rz=1.6, clumps=11, cr=1.0, limbs=3, fork=2.4, tr=0.24, lean=1.3, seed=14),
    "round":     dict(cz=3.0, rx=1.8, rz=1.5, clumps=9, cr=0.95, limbs=3, fork=1.5, tr=0.22, lean=0.0, seed=15),
    "birches":   dict(cz=4.6, rx=1.0, rz=1.9, clumps=6, cr=0.75, limbs=1, fork=3.2, tr=0.13, lean=0.0, seed=16, stems=3),
}

coll = bpy.data.collections.get("Trees") or bpy.data.collections.new("Trees")
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


def lerp3(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def to_lin(c): return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def frame(up):
    """Two unit vectors square to `up` and each other."""
    e1 = up.cross(Vector((0.3, 1, 0)) if abs(up.x) < 0.9 else Vector((0, 1, 0))).normalized()
    return e1, up.cross(e1).normalized()


class Builder:
    def __init__(self, rng):
        self.bm = bmesh.new(); self.rng = rng
        self.cl = self.bm.loops.layers.color.new("Col")

    def face(self, pts, col, out):
        """A face wound so its normal points along `out` (these shells are open, so
        recalc_face_normals can't be trusted, and the game culls back faces)."""
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if n.length < 1e-9: return
        if n.dot(out) < 0: pts = list(reversed(pts))
        try:
            f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        except ValueError:
            return
        f.smooth = False
        for l in f.loops: l[self.cl] = (*to_lin(col), 1.0)

    def foliage(self, pts, out, lift, pal):
        """Coloured by how much the face looks up (once wound along `out`) and how
        high in the crown it is (lift 0..1)."""
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if n.length < 1e-9: return
        if n.dot(out) < 0: n = -n
        nz = n.normalized().z
        c = lerp3(pal[0], pal[1], smooth(-0.5, 0.1, nz))
        c = lerp3(c, pal[2], smooth(0.1, 0.85, nz) * (0.45 + 0.55 * lift))
        j = self.rng.uniform(0.92, 1.07)
        self.face(pts, tuple(min(x * j, 1.0) for x in c), out)

    def limb(self, a, b, ra, rb, sides, col, marks=0.0, a0=None):
        """A tapered prism from a to b; birch bark gets dark marks on some faces.
        Pieces of one trunk share `a0` so their faces line up at the joints."""
        ax = (b - a).normalized()
        e1, e2 = frame(UP if ax.z > 0.7 else ax) if a0 is not None else frame(ax)
        if a0 is None: a0 = self.rng.uniform(0, math.tau)
        ring = lambda c, r: [c + (e1 * math.cos(a0 + math.tau * i / sides) + e2 * math.sin(a0 + math.tau * i / sides)) * r for i in range(sides)]
        lo, hi = ring(a, ra), ring(b, rb)
        for i in range(sides):
            j = (i + 1) % sides
            c = col if i % 2 else tuple(x * 0.78 for x in col)
            if marks and self.rng.random() < marks: c = BIRCH_MARK
            self.face([lo[i], lo[j], hi[j], hi[i]], c, lo[i] + lo[j] - 2 * a)

    def paddle(self, root, fwd, up, L, W, droop, rise, tips, lift, pal, under=3):
        """One flat branch (or leaf lobe): from `root` out along `fwd` for L, W wide,
        bending down by `droop`, creased along its length, ending in two or three
        points. `under` dark facets close it underneath (3, or 1 where it's hidden)."""
        side = fwd.cross(up).normalized()
        def P(t, s, ridge=0.0):
            return root + fwd * (t * L) + side * (s * W) + up * (rise * L * t - droop * L * t * t + ridge)
        R = P(0, 0); Lw = P(0.5, -0.5); Rw = P(0.5, 0.5); M = P(0.55, 0, 0.1 * L)
        if tips == 3:
            TL = P(0.92, -0.42); N1 = P(0.76, -0.17); TC = P(1.0, 0); N2 = P(0.76, 0.17); TR = P(0.92, 0.42)
            top = [(R, Lw, M), (R, M, Rw), (Lw, TL, N1), (Lw, N1, M), (M, N1, TC), (M, TC, N2), (M, N2, Rw), (Rw, N2, TR)]
        else:
            TL = P(0.97, -0.34); N1 = P(0.78, 0); TR = P(0.97, 0.34)
            top = [(R, Lw, M), (R, M, Rw), (Lw, TL, N1), (Lw, N1, M), (M, N1, Rw), (Rw, N1, TR)]
        for tri in top: self.foliage(list(tri), up, lift, pal)
        U = root - up * (0.14 * L) + fwd * (0.12 * L)
        tris = [(U, Lw, TL), (U, TL, TR), (U, TR, Rw)] if under == 3 else [(U, TL, TR)]
        for tri in tris: self.foliage(list(tri), -up, 0.0, pal)

    def finish(self, name):
        old = bpy.data.meshes.get(name)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new(name); self.bm.to_mesh(me); self.bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
        return ob


# --- Pines -----------------------------------------------------------------------

def pine_tiers(p, rng):
    """The tiers as (root height, radius, paddle count, droop, u), shared by the tree
    and its stand-in so the outlines match. Each tier sits `space` x its own radius
    above the last, so the small ones near the top crowd together and the cone stays
    full (a bigger `space` lets the trunk show between them)."""
    H, R = p["h"], p["r"]
    top = H - 0.9
    out = []
    z = p["base"]
    while z < top - 0.2:
        u = (z - p["base"]) / (top - p["base"])
        r = (R * (1.0 - 0.82 * u) + 0.12) * rng.uniform(0.92, 1.06)
        out.append((z, r, max(4, round(p["k"] * (1.0 - 0.4 * u))), p["droop"] * (1.0 - 0.3 * u), u))
        z += max(p["space"] * r, 0.32)
    return out


def pine(name, p):
    rng = random.Random(p["seed"])
    b = Builder(rng)
    H = p["h"]
    axis = lambda z: Vector((p["lean"] * (max(z, 0.0) / H) ** 1.5, 0, z))
    # Trunk in three pieces so the lean bends it, flared at the foot.
    zs = [-0.4, 0.3, H * 0.45, H * 0.92]
    rs = [0.3, 0.22, 0.14, 0.04]
    for i in range(3):
        b.limb(axis(zs[i]), axis(zs[i + 1]), rs[i], rs[i + 1], 5, BARK, a0=0.3)
    for z, r, k, droop, u in pine_tiers(p, rng):
        a0 = rng.uniform(0, math.tau)
        for i in range(k):
            a = a0 + math.tau * (i + rng.uniform(-0.2, 0.2)) / k
            if rng.random() < p["gap"] * (0.5 + u):
                # A dead stub where a branch has gone.
                if rng.random() < 0.5:
                    d = Vector((math.cos(a), math.sin(a), -0.2)).normalized()
                    b.limb(axis(z), axis(z) + d * r * 0.35, 0.05, 0.015, 3, BARK)
                continue
            out = Vector((math.cos(a), math.sin(a), 0))
            L = r * rng.uniform(0.85, 1.12) * (1.0 + p["sweep"] * math.cos(a))
            fwd = (out - UP * 0.62).normalized()
            W = math.tau * r * 0.5 / k * 1.8 * p["wide"]
            root = axis(z) + out * 0.08
            b.paddle(root, fwd, UP, L, W, droop * rng.uniform(0.8, 1.2), 0.22, 3 if u < 0.6 else 2, 0.25 + 0.75 * u, NEEDLES)
    # The leader: a small spire of steep paddles and a point.
    tip = axis(H)
    zt = H - 0.9
    a0 = rng.uniform(0, math.tau)
    for i in range(4):
        a = a0 + math.tau * i / 4
        out = Vector((math.cos(a), math.sin(a), 0))
        b.paddle(axis(zt + 0.35), (out - UP * 0.9).normalized(), UP, 0.55, 0.35, 0.1, 0.0, 2, 1.0, NEEDLES, under=1)
    ring = [axis(zt) + Vector((0.16 * math.cos(math.tau * i / 4), 0.16 * math.sin(math.tau * i / 4), 0)) for i in range(4)]
    for i in range(4):
        j = (i + 1) % 4
        b.foliage([ring[i], ring[j], tip], ring[i] + ring[j] - 2 * axis(zt) + UP * 0.1, 1.0, NEEDLES)
    return b.finish(name)


def pine_lod(name, p):
    """Stacked six-sided cones on the same tiers: one cone per two tiers."""
    rng = random.Random(p["seed"])
    b = Builder(rng)
    H = p["h"]
    axis = lambda z: Vector((p["lean"] * (max(z, 0.0) / H) ** 1.5, 0, z))
    b.limb(axis(-0.4), axis(H * 0.6), 0.26, 0.1, 4, BARK)
    tiers = pine_tiers(p, rng)[::2]
    span = (H - 0.9 - p["base"]) / max(len(tiers) - 0.5, 1)
    for z, r, k, droop, u in tiers:
        s = 6
        a0 = rng.uniform(0, math.tau)
        lo = z - r * (0.28 + droop * 0.8)
        apex = axis(z + span * 1.5)
        rim = [axis(lo) + Vector((r * math.cos(a0 + math.tau * i / s), r * math.sin(a0 + math.tau * i / s), 0)) for i in range(s)]
        under = axis(z)
        for i in range(s):
            j = (i + 1) % s
            o = rim[i] + rim[j] - 2 * axis(lo)
            b.foliage([apex, rim[i], rim[j]], o + UP * r, 0.25 + 0.75 * u, NEEDLES)
            b.foliage([under, rim[j], rim[i]], -UP, 0.0, NEEDLES)
    tip = axis(H)
    ring = [axis(H - 1.2) + Vector((0.4 * math.cos(math.tau * i / 3), 0.4 * math.sin(math.tau * i / 3), 0)) for i in range(3)]
    for i in range(3):
        j = (i + 1) % 3
        b.foliage([ring[i], ring[j], tip], ring[i] + ring[j] - 2 * axis(H - 1.2), 1.0, NEEDLES)
    return b.finish(name)


# --- Broadleaves -----------------------------------------------------------------

def crown_clumps(p, rng, centre):
    """Clump centres spread over the crown (an ellipsoid round `centre`), most on its
    upper and outer surface, with their radii."""
    n, rx, rz = p["clumps"], p["rx"], p["rz"]
    pts = [(centre + Vector((0, 0, rz * 0.62)), p["cr"] * 1.05)]
    ga = math.pi * (3 - 5 ** 0.5)
    for i in range(n - 1):
        z = 0.8 - 1.45 * (i + 0.5) / (n - 1)         # from near the top to below the middle
        rr = math.sqrt(max(1 - z * z, 0.0))
        a = i * ga + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.72, 0.86)
        pts.append((centre + Vector((rx * rr * math.cos(a) * d, rx * rr * math.sin(a) * d, rz * z * d)),
                    p["cr"] * rng.uniform(0.82, 1.08)))
    return pts


def rosette(b, c, up, r, lift, rng, lobes=5):
    """One clump of leaves: lobes fanning out and down from a raised middle, facing `up`."""
    e1, e2 = frame(up)
    apex = c + up * (r * 0.55)
    a0 = rng.uniform(0, math.tau)
    for i in range(lobes):
        a = a0 + math.tau * (i + rng.uniform(-0.15, 0.15)) / lobes
        fwd = ((e1 * math.cos(a) + e2 * math.sin(a)) - up * 0.45).normalized()
        b.paddle(apex, fwd, up, r * rng.uniform(0.95, 1.1), math.tau * r * 0.55 / lobes * 1.9, 0.45, 0.25,
                 3 if i % 2 == 0 else 2, lift, LEAVES, under=1)


def lump(b, c, r, lift, rng, sz=1.0):
    vs = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    fs = [(4, 0, 2), (4, 2, 1), (4, 1, 3), (4, 3, 0), (5, 2, 0), (5, 1, 2), (5, 3, 1), (5, 0, 3)]
    rot = rng.uniform(0, math.tau)
    pts = []
    for v in vs:
        v = Vector((v.x * math.cos(rot) - v.y * math.sin(rot), v.x * math.sin(rot) + v.y * math.cos(rot), v.z))
        pts.append(c + Vector((v.x, v.y, v.z * (0.6 if v.z < 0 else 0.85) * sz)) * r * rng.uniform(0.9, 1.1))
    for f in fs:
        q = [pts[i] for i in f]
        b.foliage(q, (q[0] + q[1] + q[2]) / 3 - c, lift, LEAVES)


def crown(b, p, rng, base, lean, lod):
    centre = base + Vector((lean, 0, p["cz"]))
    clumps = crown_clumps(p, rng, centre)
    fork = base + Vector((lean * p["fork"] / p["cz"], 0, p["fork"]))
    birch = p.get("stems", 1) > 1
    col = BIRCH if birch else BARK
    marks = 0.3 if birch else 0.0
    # Trunk, bending toward the lean through a midpoint.
    mid = base + Vector((lean * 0.25 * p["fork"] / p["cz"], 0, p["fork"] * 0.5))
    sides = 4 if lod else 5
    b.limb(base - Vector((0, 0, 0.4)), mid, p["tr"] * 1.2, p["tr"], sides, col, marks, a0=0.3)
    b.limb(mid, fork, p["tr"], p["tr"] * 0.8, sides, col, marks, a0=0.3)
    zs = [c.z for c, _ in clumps]
    z0, z1 = min(zs), max(zs)
    if lod:
        # A few lumpy octahedra where the biggest clumps are.
        for c, r in [clumps[0]] + clumps[1::max(1, len(clumps) // 4)][:4]:
            lump(b, c, r * 1.45, (c.z - z0) / max(z1 - z0, 0.01), rng)
        b.limb(fork, centre, p["tr"] * 0.8, p["tr"] * 0.4, 4, col)
        return
    # Limbs from the fork out to some of the lower clumps, with a branch on each.
    lower = sorted(clumps[1:], key=lambda cr: cr[0].z)[:max(p["limbs"], 1) * 2]
    rng.shuffle(lower)
    for c, r in lower[:p["limbs"]]:
        end = fork.lerp(c, 0.85)
        b.limb(fork, end, p["tr"] * 0.6, p["tr"] * 0.22, 4, col, marks)
        twig = end + (c - fork).normalized() * (r * 0.3) + Vector((0, 0, r * 0.4))
        b.limb(end.lerp(fork, 0.35), twig, p["tr"] * 0.25, 0.03, 3, col)
    b.limb(fork, centre + Vector((0, 0, p["rz"] * 0.3)), p["tr"] * 0.7, p["tr"] * 0.2, 4, col, marks)
    # A dark core fills the crown, so gaps between clumps show shade, not sky.
    lump(b, centre, p["rx"] * 0.82, 0.0, rng, p["rz"] / p["rx"])
    for c, r in clumps:
        out = c - centre
        up = (Vector((out.x / p["rx"], out.y / p["rx"], out.z / p["rz"])).normalized() + UP * 0.55).normalized()
        rosette(b, c, up, r, (c.z - z0) / max(z1 - z0, 0.01), rng)


def broad(name, p, lod):
    rng = random.Random(p["seed"])
    b = Builder(rng)
    stems = p.get("stems", 1)
    if stems == 1:
        crown(b, p, rng, Vector((0, 0, 0)), p["lean"], lod)
    else:
        # A clump of birches leaning a little apart, the first one tallest.
        for s in range(stems):
            a = math.tau * s / stems + 0.4
            q = dict(p)
            q["cz"] = p["cz"] * (1.15 if s == 0 else rng.uniform(0.8, 0.95))
            q["fork"] = q["cz"] - p["rz"] * 0.5
            base = Vector((math.cos(a), math.sin(a), 0)) * 0.55
            crown(b, q, rng, base, 0.0 if s == 0 else 0.5, lod)
    return b.finish(name)


# --- Spruce ----------------------------------------------------------------------
# Modelled on the spruce studies: tiers of thick boughs, each a slab with a ridge down
# its back, visible sides and a notched end, drooping as it goes out. Tiers are built
# from the top down, each hanging from partway down the skirt above, so they step out
# into a cone of distinct skirts, deeper toward the bottom; a thick flared trunk on
# root buttresses shows below. Each is kept under about 1500 triangles.
# r radius of the lowest skirt, tiers, k boughs on the lowest tier (k_top on the
# highest), overlap (how far down the skirt above the next tier hangs from, 0..1; more
# opens gaps that show the trunk), edge0 height of the lowest skirt's edge, pitch
# (added to the boughs' angle all along: less spreads the tree wider for its height),
# droop (extra pitch at the bough ends), stem (bare branch before the bough, x the tier's
# radius, on some boughs), lean (m the top sits off the base, the trunk curving into
# it), sweep (boughs longer away from the lean), wide (bough width, 1 = boughs just
# meet round the tier), seg bough segments, h the height the finished tree is scaled
# to, seed.
SPRUCES = {
    "spruce":        dict(r=2.8, tiers=7, k=7, k_top=4, overlap=0.5, edge0=1.0, pitch=0.0, droop=0.0, stem=0.0, lean=0.0, sweep=0.0, wide=1.0, seg=2, h=6.2, seed=21),
    "spruce_open":   dict(r=4.3, tiers=7, k=5, k_top=3, overlap=0.75, edge0=1.8, pitch=-0.2, droop=0.25, stem=0.3, lean=0.2, sweep=0.0, wide=0.62, seg=2, h=7.0, seed=22),
    "spruce_lean":   dict(r=3.4, tiers=7, k=6, k_top=3, overlap=0.55, edge0=1.4, pitch=-0.12, droop=0.12, stem=0.18, lean=3.8, sweep=0.35, wide=0.8, seg=2, h=6.2, seed=23),
    "spruce_broad":  dict(r=3.2, tiers=6, k=8, k_top=5, overlap=0.42, edge0=0.8, pitch=-0.05, droop=0.05, stem=0.0, lean=0.0, sweep=0.0, wide=1.05, seg=2, h=5.0, seed=24),
    "spruce_tall":   dict(r=2.1, tiers=8, k=5, k_top=3, overlap=0.58, edge0=1.3, pitch=0.08, droop=0.1, stem=0.12, lean=0.4, sweep=0.0, wide=0.9, seg=2, h=7.4, seed=25),
    "spruce_young":  dict(r=1.4, tiers=5, k=6, k_top=3, overlap=0.5, edge0=0.4, pitch=0.0, droop=0.0, stem=0.0, lean=0.0, sweep=0.0, wide=1.0, seg=2, h=3.2, seed=26),
}
# Boughs leave the trunk BOUGH_A0 below horizontal and droop to BOUGH_A1 at the end,
# both steeper by BOUGH_STEEP toward the top so the crown comes to a point.
BOUGH_A0, BOUGH_A1, BOUGH_STEEP = 0.35, 1.2, 0.55


def bough_pitch(u):
    """(a0, a1) for a tier at u (0 bottom, 1 top)."""
    return BOUGH_A0 + BOUGH_STEEP * u ** 1.5, BOUGH_A1 + BOUGH_STEEP * 0.35 * u ** 1.5


def bough_reach(a0, a1):
    """How far out and down, per unit length, a bough pitched a0 -> a1 reaches."""
    a = [a0 + (a1 - a0) * (i + 0.5) / 12 for i in range(12)]
    return sum(math.cos(x) for x in a) / 12, sum(math.sin(x) for x in a) / 12
# The leader above the top tier.
LEADER = 0.7


def spruce_tiers(p):
    """(tiers, height): tiers bottom first as (root height, skirt radius, boughs, skirt
    edge height, u), u = 0 at the bottom and 1 at the top."""
    n, R = p["tiers"], p["r"]
    rel = []
    z = 0.0
    for t in range(n):                       # top down, apex of the top tier at 0
        v = t / (n - 1)
        r = 0.5 + (R - 0.5) * v ** 0.95
        p0, p1 = bough_pitch(1.0 - v)
        ro, rd = bough_reach(p0 + p["pitch"], p1 + p["pitch"] + p["droop"])
        d = r / ro * rd
        rel.append((z, r, round(p["k_top"] + (p["k"] - p["k_top"]) * v), z - d, 1.0 - v))
        z -= d * p["overlap"]
    shift = p["edge0"] - rel[-1][3]
    tiers = [(z + shift, r, k, e + shift, u) for z, r, k, e, u in reversed(rel)]
    return tiers, shift + LEADER


def bough(b, root, out, L, w0, w1, thk, seg, lift, tone, a0, a1):
    """A thick bough from `root` out along horizontal `out`: L long, widening from w0
    to w1, leaving at a0 below horizontal and drooping to a1. Its section is a slab
    with a ridge along the top (so one side takes the sun and the other doesn't),
    `thk` thick at the root and thinner toward the end, which is cut in two teeth.
    `tone` scales its colour."""
    side = UP.cross(out).normalized()
    back = tuple(min(c * tone, 1.0) for c in lerp3(SPRUCE_BACK_LOW, SPRUCE_BACK_HIGH, lift))
    flank = tuple(c * SPRUCE_SIDE for c in back)
    under = SPRUCE_UNDER

    def tri(pts, col, hint):
        j = b.rng.uniform(0.95, 1.04)
        b.face(pts, tuple(min(c * j, 1.0) for c in col), hint)
    cs, ds = [root], []
    for i in range(seg):
        a = a0 + (a1 - a0) * (i + 0.5) / seg
        ds.append((out * math.cos(a) - UP * math.sin(a)).normalized())
        cs.append(cs[-1] + ds[-1] * (L / seg))
    rings, ns = [], []
    for i, c in enumerate(cs):
        t = i / seg
        w = w0 + (w1 - w0) * t ** 0.6
        d = ds[min(i, seg - 1)] if i < seg else ds[-1]
        n = side.cross(d).normalized()
        if n.z < 0: n = -n
        h = thk * (1.0 - 0.45 * t)
        ridge = w * 0.13
        # Ring: left, ridge, right along the top; right, middle, left underneath.
        rings.append([c - side * (w / 2), c + n * ridge, c + side * (w / 2),
                      c + side * (w * 0.45) - n * h, c + n * (ridge * 0.4) - n * h, c - side * (w * 0.45) - n * h])
        ns.append(n)
    hints = lambda n: [n + side * -0.3, n + side * 0.3, side, -n, -n, -side]
    for i in range(seg):
        a, c_ = rings[i], rings[i + 1]
        for f, hint in enumerate(hints(ns[i])):
            g = (f + 1) % 6
            q = [a[f], a[g], c_[g], c_[f]]
            col = back if f < 2 else (flank if f in (2, 5) else under)
            tri([q[0], q[1], q[2]], col, hint); tri([q[0], q[2], q[3]], col, hint)
    # The end: two teeth either side of the ridge, each a wedge closing to a point.
    e = rings[-1]; d = ds[-1]; n = ns[-1]; w = w1
    for (ta, tb, ba, bb), k in (((e[0], e[1], e[5], e[4]), 0.17), ((e[1], e[2], e[4], e[3]), 0.13)):
        tip = ta.lerp(tb, 0.5).lerp(ba.lerp(bb, 0.5), 0.3) + d * (w * k)
        tri([ta, tip, tb], back, n)
        tri([ba, bb, tip], under, -n)
        tri([ta, ba, tip], flank, d - side)
        tri([tb, tip, bb], flank, d + side)


def spruce_axis(p, H):
    """The trunk's line: up from the origin, curving over to sit `lean` off at the top."""
    return lambda z: Vector((p["lean"] * (max(z, 0.0) / H) ** 1.6, 0, z))


def spruce_lod(name, p):
    """A five-sided cone per tier, from its root down to its skirt edge, each turned
    against the one above so the tiers still read as stepped skirts."""
    rng = random.Random(p["seed"])
    b = Builder(rng)
    tiers, H = spruce_tiers(p)
    axis = spruce_axis(p, H)
    b.limb(axis(-0.4), axis(H * 0.5), 0.45, 0.15, 4, BARK)
    for t, (z, r, k, e, u) in enumerate(tiers + [(H, 0.5, 0, tiers[-1][3], 1.0)]):
        s = 5
        a0 = t * math.pi / 5
        apex = axis(z)
        c = axis(e)
        rim = [c + Vector((r * math.cos(a0 + math.tau * i / s), r * math.sin(a0 + math.tau * i / s), 0)) for i in range(s)]
        under = axis(e + (z - e) * 0.35)
        for i in range(s):
            j = (i + 1) % s
            b.face([apex, rim[i], rim[j]], lerp3(SPRUCE_BACK_LOW, SPRUCE_BACK_HIGH, u), rim[i] + rim[j] - 2 * c + UP * r)
            b.face([under, rim[j], rim[i]], SPRUCE_UNDER, -UP)
    return spruce_finish(b, p, H, name)


def spruce(name, p, mid=False):
    """The spruce; `mid` builds its middle-distance version (Models swaps it in past
    Models.TREE_NEAR_DIST): single-segment boughs, a quarter fewer and as much wider,
    no bare stems, a plainer trunk; same tiers and outline, about half the faces."""
    rng = random.Random(p["seed"])
    b = Builder(rng)
    tiers, H = spruce_tiers(p)
    axis = spruce_axis(p, H)
    # Trunk: flared foot on root buttresses, tapering up into the crown along its curve.
    zs = [-0.4, 0.25, 1.1, H * 0.35, H * 0.6, H * 0.93]
    rs = [0.5, 0.36, 0.28, 0.2, 0.13, 0.04]
    for i in range(len(zs) - 1):
        b.limb(axis(zs[i]), axis(zs[i + 1]), rs[i], rs[i + 1], 4 if mid else (6 if i < 2 else 5), BARK, a0=0.2)
    for i in range(4):
        a = 0.6 + math.tau * i / 4 + rng.uniform(-0.3, 0.3)
        o = Vector((math.cos(a), math.sin(a), 0))
        b.limb(Vector((0, 0, 0.5)) + o * 0.15, o * 0.7 + Vector((0, 0, -0.2)), 0.15, 0.04, 3, BARK)
    lean_dir = Vector((1, 0, 0))
    for z, r, k, e, u in tiers:
        p0, p1 = bough_pitch(u)
        p0 += p["pitch"]
        p1 += p["pitch"] + p["droop"]
        reach = bough_reach(p0, p1)[0]
        a0 = rng.uniform(0, math.tau)
        k_full = k
        if mid:
            k = max(3, round(k * 0.75))
        for i in range(k):
            a = a0 + math.tau * (i + rng.uniform(-0.2, 0.2)) / k
            out = Vector((math.cos(a), math.sin(a), 0))
            # Alternate boughs sit a touch higher, so neighbours overlap rather than
            # fight for the same plane.
            lay = 0.5 if i % 2 else -0.5
            w1 = math.tau * r / k_full * 0.95 * p["wide"] * rng.uniform(0.9, 1.1) * (k_full / k) ** 0.8
            # Wind-swept: longer away from the lean.
            sw = 1.0 - p["sweep"] * out.dot(lean_dir)
            root = axis(z + 0.06 * lay) + out * 0.1
            reach_r = r
            if p["stem"] > 0 and rng.random() < 0.75 and not mid:
                # A bare branch out from the trunk before the foliage starts.
                sl = p["stem"] * r * rng.uniform(0.7, 1.2)
                end = root + (out - UP * 0.25).normalized() * sl
                b.limb(root, end, 0.08, 0.045, 3, BARK)
                root = end
                reach_r = r - sl * 0.95
            L = (reach_r - 0.1) * rng.uniform(0.86, 1.1) * sw / reach
            bough(b, root, out, L, w1 * 0.4, w1, max(0.1, w1 * 0.13), 1 if mid else p["seg"], 0.3 + 0.7 * u,
                  rng.uniform(0.9, 1.1), p0 + 0.05 * lay + rng.uniform(-0.08, 0.08),
                  p1 + 0.05 * lay + rng.uniform(-0.15, 0.15))
    # The leader: a short spike of four steep boughs to a point.
    zt = tiers[-1][0]
    a0 = rng.uniform(0, math.tau)
    for i in range(4):
        out = Vector((math.cos(a0 + math.tau * i / 4), math.sin(a0 + math.tau * i / 4), 0))
        bough(b, axis(H), out, (H - zt + 0.3) * 1.05, 0.02, 0.45, 0.07, 1 if mid else 2, 1.0, 1.0, 1.35, 1.3)
    return spruce_finish(b, p, H, name)


def spruce_finish(b, p, H, name):
    """Scale the built tree (and its stand-in) to the variant's height `h`."""
    f = p["h"] / H
    bmesh.ops.scale(b.bm, vec=(f, f, f), verts=list(b.bm.verts))
    return b.finish(name)


built = []
for name, p in PINES.items():
    built.append(pine(name, p)); built.append(pine_lod(name + "_lod", p))
for name, p in SPRUCES.items():
    built.append(spruce(name, p)); built.append(spruce(name + "_mid", p, True)); built.append(spruce_lod(name + "_lod", p))
for name, p in BROADS.items():
    built.append(broad(name, p, False)); built.append(broad(name + "_lod", p, True))
# Lay them out in two rows for looking at (the export keeps each at its own origin).
for i, ob in enumerate(built):
    ob.location = (i // 2 * 6.5, (i % 2) * 8.0, 0)

# Export the trees.
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "trees.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
