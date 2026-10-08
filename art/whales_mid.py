# Builds the mid-poly humpback and gray whale in Blender (run inside Blender:
# exec(open(path).read())) and exports assets/models/whales_mid.glb with objects
# "Humpback" and "GrayWhale".
# Game frame, as the orca's: one unit long, +Z forward, nose at z = 0.5, flukes back to
# z = -0.5, +Y up (Blender: forward -Y, Z up). cetacean.gdshader beats the tail behind
# z = -0.12 and raises dorsal fin vertices (alpha = 1 - t/2, t >= 0.1 the height
# fraction) to FIN_BASE + t * the kind's fin height, sweeping the tip back; the fin's
# base row (alpha 1) sits on the back where it's modelled. The humpback's small fin
# is built that way; the gray whale's low hump is part of its body. Colours are per vertex.
import bpy, bmesh, math, os, random
from mathutils import Vector


def G(x, y, z): return Vector((x, -z, y))


P = math.pi
FIN_BASE = 0.085

if not bpy.data.filepath.endswith("whales_mid.blend"):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.wm.save_as_mainfile(filepath="/Users/jon/Documents/GitHub/lowpoly/art/whales_mid.blend")
coll = bpy.data.collections.get("Whales") or bpy.data.collections.new("Whales")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
mat = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
mat.use_nodes = True
_nt = mat.node_tree
_attr = _nt.nodes.get("Attr") or _nt.nodes.new("ShaderNodeVertexColor")
_attr.name = "Attr"; _attr.layer_name = "Col"
_bsdf = _nt.nodes["Principled BSDF"]
_nt.links.new(_attr.outputs["Color"], _bsdf.inputs["Base Color"])
# Without the alpha linked the glTF exporter writes RGB colours and the fin heights are lost.
_nt.links.new(_attr.outputs["Alpha"], _bsdf.inputs["Alpha"])
for _n in ("Humpback", "GrayWhale"):
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


def lerp_tab(U, tab, u):
    for i in range(len(U) - 1):
        if U[i] <= u <= U[i + 1]:
            return tab[i] + (tab[i + 1] - tab[i]) * (u - U[i]) / (U[i + 1] - U[i])
    return tab[-1]


def mix(a, b, t):
    t = min(max(t, 0.0), 1.0)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def bump(x, c, w): return math.exp(-((x - c) / w) ** 2)


def spots(seed, n, s_range, th_range, r_range):
    rnd = random.Random(seed)
    return [(rnd.uniform(*s_range), rnd.choice((1, -1)) * rnd.uniform(*th_range), rnd.uniform(*r_range)) for _ in range(n)]


def dapple(SP, s, theta, side, R=0.085):
    """How close (0..1) (s, theta) on the `side` flank is to one of the spots SP."""
    d = 0.0
    for ss, st, r in SP:
        d2 = (s - ss) ** 2 + ((theta * side - st) * R) ** 2
        d = max(d, math.exp(-d2 / (r * r)))
    return d


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.cl = self.bm.loops.layers.color.new("Col")
        self.vc = {}
        self.knobs = []   # (faces, outward normal): open domes, oriented by hand

    def vert(self, p, col, a=1.0):
        v = self.bm.verts.new(G(*p)); self.vc[v] = (col[0], col[1], col[2], a)
        return v

    def face(self, vs):
        f = self.bm.faces.new(vs)
        for l in f.loops: l[self.cl] = self.vc[l.vert]
        return f

    def grid(self, rows):
        """Quads between successive closed rings of verts."""
        for i in range(len(rows) - 1):
            n = len(rows[i])
            for j in range(n):
                self.face([rows[i][j], rows[i][(j + 1) % n], rows[i + 1][(j + 1) % n], rows[i + 1][j]])

    def fan(self, ring, apex):
        return [self.face([ring[j], ring[(j + 1) % len(ring)], apex]) for j in range(len(ring))]

    def loft(self, sections, colour, alphas=None, cap0=True, cap1=True):
        """Closed sections of game-space points (same count each), vertex (i, j) painted
        colour(i, j); alphas per section."""
        rows = [[self.vert(p, colour(i, j), alphas[i] if alphas else 1.0) for j, p in enumerate(sec)]
                for i, sec in enumerate(sections)]
        self.grid(rows)
        if cap0: self.face(list(reversed(rows[0])))
        if cap1: self.face(rows[-1])
        return rows

    def knob(self, surf, s, a, r, h, col, apex_col=None, sides=6, stretch=1.0):
        """A little dome (a tubercle, barnacle, knuckle or eye) sunk into the surface at (s, a)."""
        c = surf(s, a); n = normal(surf, s, a)
        f = Vector((0, 0, 1)); ta = (f - n * f.dot(n)).normalized(); tb = n.cross(ta)
        ring = [self.vert(c - n * h * 0.4 + (ta * math.cos(2 * P * k / sides) * stretch + tb * math.sin(2 * P * k / sides)) * r, col)
                for k in range(sides)]
        self.knobs.append((self.fan(ring, self.vert(c + n * h, apex_col or col)), G(*n)))

    def finish(self, name):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
        loose = {f for fs, _ in self.knobs for f in fs}
        bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in loose])
        for fs, n in self.knobs:
            for f in fs:
                f.normal_update()
                if f.normal.dot(n) < 0:
                    f.normal_flip()
                    for l in f.loops: l[self.cl] = self.vc[l.vert]
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        for p in me.polygons: p.use_smooth = True
        ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
        return ob


class Body:
    """A trunk through profile tables keyed on s = distance back from the nose (TOP and
    BOT heights, HW half-width), superelliptic in section (ex_top over the back,
    ex_bot under the belly). Round each ring the angle goes 0 (back) to pi (belly)
    down one side in `thetas` and back up the other; vertex j is thetas[j]. `disp`(s,
    theta, side, j) pushes the surface out (or in) for creases, ridges and pleats."""

    def __init__(self, S, TOP, BOT, HW, thetas, ex_top, ex_bot, disp):
        self.S, self.TOP, self.BOT, self.HW = S, TOP, BOT, HW
        self.thetas, self.ex_top, self.ex_bot, self.disp = thetas, ex_top, ex_bot, disp

    def surf(self, s, a, j=None):
        S = self.S
        t_, b_, w_ = interp(S, self.TOP, s), interp(S, self.BOT, s), max(interp(S, self.HW, s), 0.0)
        c, h = (t_ + b_) / 2, (t_ - b_) / 2
        sa, ca = math.sin(a), math.cos(a)
        ex = self.ex_top if ca >= 0 else self.ex_bot
        x, y = w_ * math.copysign(abs(sa) ** (2 / ex), sa), h * math.copysign(abs(ca) ** (2 / ex), ca)
        p = Vector((x, c + y, 0.5 - s))
        a = a % (2 * P)
        theta, side = (a, 1) if a <= P else (2 * P - a, -1)
        dr = self.disp(s, theta, side, j)
        r = Vector((x, y, 0))
        if dr and r.length > 1e-6: p += r.normalized() * dr
        return p

    def build(self, b, sl, colour):
        m = len(self.thetas)
        ring = [(t, j) for j, t in enumerate(self.thetas)] + [(2 * P - self.thetas[j], j) for j in range(m - 2, 0, -1)]
        rows = []
        for s in sl:
            rows.append([b.vert(self.surf(s, a, j), colour(s, a if a <= P else 2 * P - a, 1 if a <= P else -1, j))
                         for a, j in ring])
        b.grid(rows)
        for s, row, dz in ((sl[0], rows[0], 0.004), (sl[-1], rows[-1], -0.008)):
            c = (interp(self.S, self.TOP, s) + interp(self.S, self.BOT, s)) / 2
            b.fan(row, b.vert((0, c, 0.5 - s + dz), colour(s, 0.0, 1, 0)))


def normal(surf, s, a, e=1e-3):
    p = surf(s, a)
    n = (surf(s, a + e) - surf(s, a - e)).cross(surf(s + e, a) - surf(s - e, a))
    if n.dot(Vector((p.x, p.y, 0))) < 0: n = -n
    return n.normalized()


def foil(c, d, n, lead, trail, thk):
    """A hydrofoil section through c: leading edge `lead` ahead along d, trailing edge
    `trail` behind, `thk` either side along n. Points 0 lead, 1-2 top, 3 trail, 4-5 under."""
    ch = lead + trail
    return [c + d * lead, c + d * (lead - 0.25 * ch) + n * thk, c + d * (lead - 0.62 * ch) + n * thk * 0.6,
            c - d * trail, c + d * (lead - 0.62 * ch) - n * thk * 0.6, c + d * (lead - 0.25 * ch) - n * thk]


def flipper(b, root, tip, U, CH, thk, colour, lead=0.45, scallop=0.0, arch=0.0, N=8):
    """A pectoral flipper lofted root to tip through N sections, chord CH at span
    fractions U; `scallop` pushes every other section's leading edge forward (a
    humpback's tubercles). colour(u, j)."""
    axis = (tip - root).normalized(); f = Vector((0, 0, 1))
    d = (f - axis * f.dot(axis)).normalized(); n = axis.cross(d)
    if n.y < 0: n = -n
    secs = []
    for i in range(N):
        u = i / (N - 1)
        ch = lerp_tab(U, CH, u)
        c = root.lerp(tip, u) + Vector((0, -arch * math.sin(P * u), -0.012 * u * u))
        bump_ = scallop * (1 - 0.4 * u) if (i % 2 == 1 and 0.08 < u < 0.95) else 0.0
        secs.append(foil(c, d, n, lead * ch + bump_, (1 - lead) * ch, thk * (1 - 0.75 * u) + 0.0012))
    b.loft(secs, lambda i, j: colour(i / (N - 1), j))


def flukes(b, span, le, te, thk, y0, colour, N=10):
    """Both flukes, from the notch out to the tips at +-span; le(u), te(u) give the edges'
    z at span fraction u (te gets i, the section, for serrations). colour(u, j, side)."""
    for side in (1, -1):
        secs = []
        for i in range(N):
            u = i / (N - 1)
            z0, z1 = le(u), te(u, i)
            c = Vector((span * u * side, y0 - 0.008 * u, (z0 + z1) / 2))
            h = (z0 - z1) / 2
            secs.append(foil(c, Vector((0, 0, 1)), Vector((0, 1, 0)), h, h, thk * (1 - 0.8 * u) + 0.0012))
        b.loft(secs, lambda i, j, side=side: colour(i / (N - 1), j, side), cap0=False)


def fin(b, body, rows, height, colour):
    """A dorsal fin (or hump) for cetacean.gdshader: rows of (t, le z, te z, half
    thickness); the t = 0 row sits on the back, the others get alpha 1 - t/2 and are
    drawn here at the shader's height for `height`."""
    secs, alphas = [], []
    for t, z0, z1, thk in rows:
        mid = (z0 + z1) / 2
        sec = foil(Vector((0, 0, mid)), Vector((0, 0, 1)), Vector((1, 0, 0)), z0 - mid, mid - z1, thk)
        for p in sec:
            p.y = body.surf(0.5 - p.z, math.asin(min(abs(p.x) / max(interp(body.S, body.HW, 0.5 - p.z), 1e-3), 1.0))).y - 0.004 \
                if t == 0 else FIN_BASE + t * height
        secs.append(sec); alphas.append(1.0 if t == 0 else 1.0 - t / 2)
    b.loft(secs, lambda i, j: colour(rows[i][0], j), alphas)


def side_thetas(n_back, n_belly, split):
    return [split * k / n_back for k in range(n_back)] + [split + (P - split) * k / n_belly for k in range(n_belly + 1)]


# --- Humpback ---------------------------------------------------------------------
# Long and robust: a broad flat rostrum studded with knobs (tubercles), a splash guard
# before the blowholes, the lower jaw jutting a little past the upper, ventral pleats
# from chin to navel, a small fin on a hump two thirds back, a knobbly keel to the
# flukes. Flippers a third of its length, white, their leading edges scalloped.
# Flukes black above, white below with a black trailing margin, the edge serrated.
NS_HB = 22                                     # rings nose to tail
TH_HB = side_thetas(6, 6, 1.95)                # down one side: back, then the pleated belly
HB_BLACK = (0.06, 0.065, 0.075); HB_FLANK = (0.13, 0.135, 0.15); HB_WHITE = (0.88, 0.88, 0.86)
HB_KNOB = (0.09, 0.095, 0.105); HB_BARN = (0.78, 0.77, 0.72)

S   = [0.0,   0.02,  0.06,  0.12,  0.2,   0.28,  0.36,  0.45,  0.54,  0.62,  0.7,   0.78,  0.85,  0.9]
TOP = [-0.006, 0.012, 0.03,  0.05,  0.071, 0.087, 0.095, 0.095, 0.088, 0.078, 0.066, 0.052, 0.038, 0.027]
BOT = [-0.034, -0.056, -0.076, -0.093, -0.105, -0.109, -0.105, -0.093, -0.077, -0.061, -0.047, -0.035, -0.025, -0.018]
HW  = [0.012, 0.034, 0.06,  0.082, 0.098, 0.108, 0.112, 0.107, 0.093, 0.072, 0.049, 0.029, 0.016, 0.009]
HB_BLOTS = spots(5, 22, (0.04, 0.48), (2.2, 3.14), (0.02, 0.045))


def hb_mouth(s): return 1.6 + 0.28 * smooth(0.08, 0.215, s)


def hb_disp(s, theta, side, j):
    dr = 0.0
    if s < 0.24:
        m = hb_mouth(s)
        # The lower jaw bulges out past the upper; a crease along the lip.
        dr += 0.0035 * smooth(m, m + 0.3, theta) * smooth(0.22, 0.16, s)
        dr -= 0.0028 * bump(theta, m, 0.13) * smooth(0.235, 0.2, s)
    # Splash guard, and the blowholes sunk just behind it.
    dr += 0.005 * bump(s, 0.188, 0.016) * smooth(0.6, 0.15, theta)
    dr -= 0.003 * bump(s, 0.212, 0.012) * bump(theta, 0.15, 0.12)
    if j is not None and theta > TH_HB[6]:
        amt = 0.0024 * smooth(TH_HB[6], TH_HB[6] + 0.3, theta) * smooth(0.02, 0.07, s) * smooth(0.52, 0.42, s)
        dr += amt if j % 2 == 0 else -amt
    return dr


def hb_colour(s, theta, side, j):
    c = mix(HB_BLACK, HB_FLANK, smooth(1.1, 2.0, theta) * smooth(0.04, 0.2, s))
    w = smooth(2.05, 2.55, theta) * smooth(0.0, 0.05, s) * smooth(0.52, 0.38, s)
    w *= 1 - 0.85 * dapple(HB_BLOTS, s, theta, side, 0.1)
    c = mix(c, HB_WHITE, w)
    if j is not None and j % 2 == 1 and theta > TH_HB[6]:
        c = mix(c, HB_BLACK, 0.3 * w)      # the grooves between the pleats
    return c


b = Builder()
hb = Body(S, TOP, BOT, HW, TH_HB, 2.3, 2.0, hb_disp)
hb.build(b, [0.9 * (i / (NS_HB - 1)) ** 1.2 for i in range(NS_HB)], hb_colour)
# Tubercles: a row each side of the midline and one lower down the rostrum, a row
# along each side of the lower jaw, a cluster at the chin (some barnacled).
for s in (0.035, 0.075, 0.115, 0.155):
    b.knob(hb.surf, s, 0.0, 0.009, 0.0045, HB_KNOB)
for side in (1, -1):
    for s in (0.03, 0.065, 0.1, 0.135, 0.17):
        b.knob(hb.surf, s, side * 0.42, 0.0095, 0.005, HB_KNOB)
        b.knob(hb.surf, s + 0.015, side * 0.95, 0.009, 0.0045, HB_KNOB)
    for s in (0.04, 0.08, 0.12, 0.16):
        b.knob(hb.surf, s, side * (hb_mouth(s) + 0.42), 0.0095, 0.005, HB_KNOB, HB_BARN)
    b.knob(hb.surf, 0.022, side * 2.7, 0.009, 0.008, HB_KNOB, HB_BARN)
    # A small eye just above the corner of the mouth.
    b.knob(hb.surf, 0.218, side * (hb_mouth(0.218) - 0.12), 0.0065, 0.003, (0.02, 0.02, 0.025), sides=6, stretch=1.3)
b.knob(hb.surf, 0.012, P, 0.011, 0.009, HB_KNOB, HB_BARN)
# Knobs down the keel from the fin to the flukes.
for i, s in enumerate((0.72, 0.76, 0.8, 0.84)):
    b.knob(hb.surf, s, 0.0, 0.009 - 0.0012 * i, 0.005 - 0.0007 * i, HB_BLACK, stretch=1.6)
fin(b, hb, [(0.0, -0.08, -0.195, 0.022), (0.35, -0.11, -0.178, 0.013), (0.7, -0.125, -0.162, 0.007),
            (1.0, -0.132, -0.148, 0.0025)], 0.025, lambda t, j: HB_BLACK)


def hb_flipper_colour(u, j):
    if j >= 4 or j == 0:
        return HB_WHITE if u > 0.04 else HB_FLANK
    c = mix(HB_FLANK, HB_WHITE, smooth(0.1, 0.5, u))
    return mix(c, HB_BARN, 0.6) if u > 0.9 else c


for side in (1, -1):
    root = hb.surf(0.3, side * 2.0) * 0.85
    root.z = 0.2
    tip = Vector((0.3 * side, -0.13, -0.04))
    flipper(b, root, tip, [0, 0.2, 0.4, 0.6, 0.8, 0.92, 1.0], [0.064, 0.07, 0.068, 0.058, 0.042, 0.028, 0.01],
            0.012, hb_flipper_colour, lead=0.45, scallop=0.006, arch=0.015, N=9)


def hb_le(u): return -0.385 - 0.12 * u ** 2.2


def hb_te(u, i):
    z = -0.432 - 0.058 * smooth(0.0, 0.45, u) - 0.015 * u
    return z + (0.005 if i % 2 and 0.12 < u < 0.9 else 0.0)


def hb_fluke_colour(u, j, side):
    if j in (0, 1, 2) or u > 0.9:
        return HB_BLACK
    if j == 3 or u < 0.08:
        return HB_FLANK
    # Underside: white, splashed black toward the notch and along the trailing third.
    return mix(HB_WHITE, HB_BLACK, 0.8 * smooth(0.18, 0.08, u) + (0.7 if j == 4 and 0.35 < u < 0.55 and side > 0 else 0.0))


flukes(b, 0.175, hb_le, hb_te, 0.014, 0.008, hb_fluke_colour, N=11)
humpback = b.finish("Humpback")


# --- Gray whale -------------------------------------------------------------------
# Slimmer, with a narrow, slightly arched head, an arched mouth line and a couple of
# throat grooves, no fin but a low hump and a row of knuckles down the tail stock,
# small pointed paddle flippers. Mottled grey, crusted with barnacles (white, ringed
# with orange whale lice) mostly about the head, scarred pale where they've dropped off.
NS_GR = 24
TH_GR = side_thetas(6, 5, 2.0)
GR_DARK = (0.33, 0.35, 0.37); GR_BASE = (0.45, 0.47, 0.48); GR_LIGHT = (0.64, 0.65, 0.64)
GR_SCAR = (0.84, 0.83, 0.79); LICE = (0.8, 0.6, 0.4); BARN = (0.9, 0.89, 0.84)

S   = [0.0,   0.02,  0.06,  0.12,  0.2,   0.3,   0.4,   0.5,   0.6,   0.68,  0.76,  0.83,  0.89]
TOP = [-0.022, -0.005, 0.014, 0.038, 0.062, 0.08,  0.087, 0.085, 0.077, 0.066, 0.05,  0.034, 0.023]
BOT = [-0.03, -0.042, -0.056, -0.07, -0.082, -0.09, -0.092, -0.086, -0.07, -0.054, -0.038, -0.024, -0.015]
HW  = [0.006, 0.019, 0.036, 0.055, 0.073, 0.087, 0.093, 0.089, 0.075, 0.056, 0.036, 0.02,  0.01]
GR_PATCH = spots(21, 26, (0.02, 0.86), (0.0, 3.1), (0.04, 0.075))
GR_SCARS = spots(22, 34, (0.02, 0.8), (0.0, 2.4), (0.022, 0.035))


def gr_mouth(s): return 1.72 - 0.16 * math.sin(P * min(s / 0.19, 1.0))


def gr_disp(s, theta, side, j):
    dr = 0.0
    if s < 0.21:
        dr -= 0.0025 * bump(theta, gr_mouth(s), 0.12) * smooth(0.21, 0.17, s)
    # The hump: too low to build as a fin (cetacean.gdshader lifts those to FIN_BASE and up).
    dr += 0.012 * bump(s, 0.655, 0.045) * smooth(0.75, 0.0, theta)
    if j is not None and j in (8, 10):
        dr -= 0.003 * smooth(0.05, 0.09, s) * smooth(0.22, 0.17, s)   # throat grooves
    return dr


def gr_colour(s, theta, side, j):
    c = mix(GR_DARK, GR_BASE, smooth(0.2, 1.7, theta))
    c = mix(c, GR_LIGHT, 0.4 * smooth(2.2, 2.9, theta))
    c = mix(c, GR_LIGHT, 0.75 * dapple(GR_PATCH, s, theta, side))
    c = mix(c, GR_SCAR, 0.85 * dapple(GR_SCARS, s, theta, side))
    return c


b = Builder()
gr = Body(S, TOP, BOT, HW, TH_GR, 2.2, 2.2, gr_disp)
gr.build(b, [0.89 * (i / (NS_GR - 1)) ** 1.15 for i in range(NS_GR)], gr_colour)
rnd = random.Random(23)
# Barnacles: crowded on the rostrum and round the blowholes, scattered down the back.
for n, s_r, th_r, r_r in ((14, (0.01, 0.2), (0.0, 1.5), (0.008, 0.016)), (7, (0.25, 0.6), (0.15, 1.3), (0.007, 0.012)),
                          (4, (0.03, 0.16), (1.9, 2.5), (0.007, 0.011))):
    for _ in range(n):
        s = rnd.uniform(*s_r); a = rnd.choice((1, -1)) * rnd.uniform(*th_r); r = rnd.uniform(*r_r)
        b.knob(gr.surf, s, a, r, r * 0.5, mix(BARN, LICE, 0.45), BARN, stretch=rnd.uniform(0.8, 1.5))
for side in (1, -1):
    b.knob(gr.surf, 0.2, side * (gr_mouth(0.2) - 0.1), 0.006, 0.003, (0.03, 0.03, 0.035), stretch=1.3)
# The knuckles, shrinking toward the flukes.
for i in range(8):
    s = 0.71 + 0.022 * i
    b.knob(gr.surf, s, 0.0, 0.0105 - 0.0008 * i, 0.0065 - 0.0005 * i, GR_DARK, GR_BASE, stretch=1.3)
for side in (1, -1):
    root = gr.surf(0.27, side * 2.05) * 0.85
    root.z = 0.23
    tip = Vector((0.17 * side, -0.115, 0.12))
    flipper(b, root, tip, [0, 0.3, 0.6, 0.85, 1.0], [0.045, 0.06, 0.052, 0.03, 0.008], 0.011,
            lambda u, j: mix(GR_BASE, GR_LIGHT, 0.5 if j >= 4 else 0.15 * u), lead=0.4, N=7)


def gr_le(u): return -0.39 - 0.1 * u ** 2.0


def gr_te(u, i): return -0.43 - 0.05 * smooth(0.0, 0.4, u) - 0.03 * smooth(0.6, 1.0, u) + 0.008 * math.sin(P * u)


flukes(b, 0.135, gr_le, gr_te, 0.013, 0.008,
       lambda u, j, side: mix(GR_DARK, GR_LIGHT, 0.45 if j >= 3 else 0.1), N=9)
gray = b.finish("GrayWhale")

humpback.location.x = -0.4; gray.location.x = 0.4
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "assets", "models", "whales_mid.glb"))
for o in bpy.data.objects: o.select_set(o in (humpback, gray))
humpback.location.x = gray.location.x = 0.0
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True, export_normals=True,
                          export_texcoords=False, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
humpback.location.x = -0.4; gray.location.x = 0.4
bpy.ops.wm.save_mainfile()
result = {"tris": {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (humpback, gray)}, "glb": _glb}
