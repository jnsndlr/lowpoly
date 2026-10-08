# Builds the mid-poly escort tug in Blender (run inside Blender: exec(open(path).read()))
# and exports it to assets/models/tug_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# Game frame, like the code-built tug it replaces: +Z is the bow, +Y up, waterline at
# y = 0, about 14 m long and 5 m in the beam (Blender: bow to -Y, Z up).
# A lofted hull with sheer and bow flare, bulwarks with a white cap, a rubber belt all
# round and a big bow fender, tyres on the quarters; a deckhouse with the wheelhouse on
# it (raked windows all round, visor roof), mast with radar, towing lights and a fire
# monitor; twin raked stacks; towing winch, wire, staple and H-bitts aft.
# The livery is split into parts so Models can recolour them per variant: `hull`,
# `house` and `stack` are each painted in one colour; everything else is `fixed`.
# Glass is split out too, for the vertex alpha the game's shader reads: `glass` (the
# wheelhouse, lit at night), `window` (the deckhouse, some rooms lit) and `lens` (the
# stern light's glass).
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.1, 0.1, 0.11), "house": (0.94, 0.95, 0.94), "stack": (0.86, 0.33, 0.1),
    "antifoul": (0.55, 0.14, 0.12), "white": (0.92, 0.93, 0.92), "deck": (0.4, 0.46, 0.41),
    "fender": (0.06, 0.06, 0.07), "glass": (0.16, 0.22, 0.27), "window": (0.16, 0.22, 0.27), "steel": (0.25, 0.26, 0.28),
    "black": (0.07, 0.07, 0.07), "wire": (0.16, 0.15, 0.14), "bitt": (0.86, 0.68, 0.14),
    "orange": (0.95, 0.42, 0.1), "door": (0.78, 0.8, 0.8), "lamp": (0.12, 0.12, 0.13),
    "red": (0.8, 0.12, 0.1),
    "lens": (0.95, 0.95, 0.85), "lens_off": (0.85, 0.85, 0.8),
}
ROLES = ("hull", "house", "stack", "glass", "window", "lens")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def to_lin(c): return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


coll = bpy.data.collections.get("Tug") or bpy.data.collections.new("Tug")
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


def bm_for(key):
    role = key if key in ROLES else "fixed"
    if role not in BMS:
        bm = bmesh.new(); bm.loops.layers.color.new("Col"); BMS[role] = bm
    return BMS[role]


def face(pts, key):
    """One face in the given winding (callers orient it); colour by palette key."""
    q = [pts[0]]
    for p in pts[1:]:
        if (p - q[-1]).length > 1e-5: q.append(p)
    if len(q) > 2 and (q[0] - q[-1]).length < 1e-5: q.pop()
    if len(q) < 3: return
    bm = bm_for(key); cl = bm.loops.layers.color["Col"]
    try:
        f = bm.faces.new([bm.verts.new(G(p)) for p in q])
    except ValueError:
        return
    f.smooth = False
    for l in f.loops: l[cl] = (*to_lin(PAL[key]), 1.0)


def normal(pts):
    n = Vector()
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += a.cross(b)
    return n


def centre(pts): return sum(pts, Vector()) / len(pts)


def loft(rings, key, closed_ring=True, closed_path=False, caps=True, cap_key=None):
    """Quads between successive rings (same vertex count, same direction). `key` is a
    palette key or fn(i, j, centroid) -> key. The whole surface is wound outward from
    the rings' centres (by majority, so concave sections like bulwarks stay right)."""
    n, quads = len(rings[0]), []
    m = len(rings) if closed_path else len(rings) - 1
    for i in range(m):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        ax = (centre(a) + centre(b)) * 0.5
        for j in range(n if closed_ring else n - 1):
            k = (j + 1) % n
            quads.append((i, j, [a[j], a[k], b[k], b[j]], ax))
    s = sum(normal(q).dot(centre(q) - ax) for _, _, q, ax in quads)
    for i, j, q, _ in quads:
        c = key(i, j, centre(q)) if callable(key) else key
        face(q if s > 0 else q[::-1], c)
    if caps and not closed_path and closed_ring:
        ck = cap_key or (key if not callable(key) else "black")
        for r, o in ((rings[0], rings[1]), (rings[-1], rings[-2])):
            out = centre(r) - centre(o)
            face(r if normal(r).dot(out) > 0 else r[::-1], ck)


def rect(cx, y, cz, hw, hd, ch=0.0, chb=None):
    """Horizontal rectangle (optionally chamfered: `ch` front corners, `chb` back)."""
    chb = ch if chb is None else chb
    pts = [(cx + hw, cz - hd + chb), (cx + hw, cz + hd - ch), (cx + hw - ch, cz + hd), (cx - hw + ch, cz + hd),
           (cx - hw, cz + hd - ch), (cx - hw, cz - hd + chb), (cx - hw + chb, cz - hd), (cx + hw - chb, cz - hd)]
    return [V(x, y, z) for x, z in pts]


def box(c, size, key):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    loft([rect(c.x, c.y - hy, c.z, hx, hz), rect(c.x, c.y + hy, c.z, hx, hz)], key)


def frame(ax):
    e1 = ax.cross(V(0.3, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0)).normalized()
    return e1, ax.cross(e1).normalized()


def circle(c, ax, r, n, a0=0.0):
    e1, e2 = frame(ax)
    return [c + (e1 * math.cos(a0 + math.tau * i / n) + e2 * math.sin(a0 + math.tau * i / n)) * r for i in range(n)]


def cyl(a, b, r0, r1, n, key, a0=None):
    ax = (b - a).normalized()
    a0 = math.pi / n if a0 is None else a0
    loft([circle(a, ax, r0, n, a0), circle(b, ax, r1, n, a0)], key)


def tube(path, r, n, key, closed=False):
    """A round pipe along a polyline (rings square to the mean tangent)."""
    rings, prev = [], None
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        e1 = (prev - prev.dot(t) * t).normalized() if prev is not None else frame(t)[0]
        prev = e1; e2 = t.cross(e1)
        rings.append([p + (e1 * math.cos(math.tau * k / n) + e2 * math.sin(math.tau * k / n)) * r for k in range(n)])
    loft(rings, key, closed_path=closed)


def torus(c, ax, R, r, n1, n2, key):
    e1, e2 = frame(ax)
    rings = []
    for i in range(n1):
        a = math.tau * i / n1
        d = e1 * math.cos(a) + e2 * math.sin(a)
        rings.append([c + d * (R + r * math.cos(math.tau * k / n2)) + ax * (r * math.sin(math.tau * k / n2)) for k in range(n2)])
    # Lofted round the ring: wind each face away from the tube's own centreline.
    for i in range(n1):
        a, b = rings[i], rings[(i + 1) % n1]
        ca = c + (e1 * math.cos(math.tau * (i + 0.5) / n1) + e2 * math.sin(math.tau * (i + 0.5) / n1)) * R
        for k in range(n2):
            q = [a[k], a[(k + 1) % n2], b[(k + 1) % n2], b[k]]
            face(q if normal(q).dot(centre(q) - ca) > 0 else q[::-1], key)


# --- Hull ------------------------------------------------------------------------

STATIONS = [-7.0, -6.8, -6.4, -5.8, -5.0, -4.0, -2.5, -1.0, 0.5, 2.0, 3.2, 4.2, 5.0, 5.7, 6.3, 6.75, 7.05, 7.24]


def deck_y(z): return 1.3 + 0.5 * smooth(1.0, 7.0, z) + 0.12 * smooth(-5.5, -7.0, z)
def bulwark(z): return 0.72 + 0.25 * smooth(2.0, 7.0, z)
def keel_y(z): return -1.7 + 1.9 * smooth(2.5, 7.2, z) + 0.8 * smooth(-3.0, -7.0, z)


def beam(z):
    """Half beam at the deck edge: round stern in plan, fine bow."""
    if z < -4.5: return 2.5 * math.sqrt(max(0.0, 1 - ((z + 4.5) / 2.9) ** 2))
    if z > 1.5: return 2.5 * math.sqrt(max(0.0, 1 - ((z - 1.5) / 5.75) ** 2.2))
    return 2.5


def waterline(z):
    if z < -4.5: return beam(z) * 0.95
    if z > 1.0: return 2.38 * math.sqrt(max(0.0, 1 - ((z - 1.0) / 5.7) ** 1.8))
    return 2.38


def section(z):
    """Starboard half from the keel up the side, over the bulwark and in to the deck
    centre, as (x, y) pairs: A keel, B flat, C D bilge, E waterline, F G flare to the
    deck edge, H I bulwark top, J foot of the bulwark, K deck centre."""
    yk, w, b, d, bw = keel_y(z), max(waterline(z), 0.03), max(beam(z), 0.05), deck_y(z), bulwark(z)
    yw = max(0.0, yk + 0.1); dd = yw - yk
    return [(0.0, yk), (0.4 * w, yk), (0.78 * w, yk + 0.18 * dd), (0.96 * w, yk + 0.5 * dd), (w, yw),
            (lerp(w, b, 0.6), lerp(yw, d, 0.45)), (b, d), (b + 0.04, d + bw), (max(b - 0.1, 0.02), d + bw),
            (max(b - 0.1, 0.02), d), (0.0, d + 0.08)]


def hull_x(z, y):
    """Half width of the hull's outside at height y (keel to deck edge)."""
    s = section(z)[:7]
    if y <= s[0][1]: return s[0][0]
    for (x0, y0), (x1, y1) in zip(s, s[1:]):
        if y0 <= y <= y1 and y1 > y0: return lerp(x0, x1, (y - y0) / (y1 - y0))
    return s[-1][0]


def hull():
    rings = []
    for z in STATIONS:
        s = section(z)
        stb = [V(x, y, z) for x, y in s]
        rings.append(stb + [V(-x, y, z) for x, y in reversed(s[1:-1])])

    def col(i, j, c):
        s = j if j < 10 else 19 - j
        if s <= 5: return "antifoul" if c.y < 0.0 else "hull"
        return {6: "hull", 7: "white", 8: "hull", 9: "deck"}[s]
    loft(rings, col, cap_key="hull")


def transom_bulwark():
    """The bulwark across the stern (the hull's end section only reaches the deck
    there), with its white cap; the stern light sits on it."""
    z = STATIONS[0]; d, bw = deck_y(z), bulwark(z); hw = beam(z) + 0.03
    box(V(0, d + bw / 2, z + 0.06), (2 * hw, bw, 0.12), "hull")
    box(V(0, d + bw + 0.02, z + 0.06), (2 * hw + 0.04, 0.04, 0.16), "white")


def outline_path(y_of, zs, out=0.0):
    """Points round the deck outline (starboard aft to fore, then port back), at the
    height y_of(z) on the hull, pushed `out` along the horizontal normal."""
    pts = [V(hull_x(z, y_of(z)), y_of(z), z) for z in zs] + [V(-hull_x(z, y_of(z)), y_of(z), z) for z in reversed(zs)]
    return pts


def horiz_normals(pts, closed):
    ns = []
    for i, p in enumerate(pts):
        a = pts[(i - 1) % len(pts)] if closed or i > 0 else p
        b = pts[(i + 1) % len(pts)] if closed or i < len(pts) - 1 else p
        t = b - a; t.y = 0; t.normalize()
        nrm = V(t.z, 0, -t.x)
        if nrm.dot(V(p.x, 0, p.z)) < 0: nrm = -nrm
        ns.append(nrm)
    return ns


def belt():
    """The rubber belt round the sheer, across the transom too."""
    zs = STATIONS[:-1]
    y = lambda z: deck_y(z) - 0.22
    pts = outline_path(y, zs)
    # Across the transom, port to starboard.
    yt = y(STATIONS[0]); xt = hull_x(STATIONS[0], yt)
    pts += [V(lerp(-xt, xt, t), yt, STATIONS[0] - 0.02) for t in (0.25, 0.5, 0.75)]
    ns = horiz_normals(pts, True)
    prof = [(-0.05, -0.18), (0.26, -0.15), (0.3, 0.0), (0.26, 0.15), (-0.05, 0.18)]
    rings = [[p + n * u + UP * v for u, v in prof] for p, n in zip(pts, ns)]
    loft(rings, "fender", closed_ring=True, closed_path=True)


def bow_fender():
    """A thick block fender wrapped round the bow from the shoulders to the stem."""
    zs = [z for z in STATIONS if z >= 4.2]
    lo, hi = 0.55, lambda z: deck_y(z) + bulwark(z) - 0.15
    rings = []
    for side in (1, -1):
        for z in (zs if side == 1 else list(reversed(zs))):
            rings.append((side, z))
    # Drop the duplicated stem station so the fender runs straight round it.
    rings = rings[:len(zs)] + rings[len(zs) + 1:]
    tops = [V(s * hull_x(z, hi(z) - 0.1) + s * 0.04, hi(z), z) for s, z in rings]
    ns = horiz_normals(tops, False)
    out = []
    for (s, z), n in zip(rings, ns):
        xb, xt = s * hull_x(z, lo), s * (hull_x(z, hi(z) - 0.1) + 0.04)
        bot, top = V(xb, lo, z), V(xt, hi(z), z)
        if abs(xb) < 0.08: n = V(0, 0, 1)
        # Thickest at the stem, thinning to the shoulders; the outer face rounded.
        t = 0.2 + 0.2 * smooth(4.2, 6.8, z)
        out.append([bot - n * 0.05, bot + n * t * 0.6 + UP * -0.05, lerp(bot, top, 0.3) + n * t,
                    lerp(bot, top, 0.7) + n * t, top + n * t * 0.7 + UP * 0.05, top - n * 0.05])
    loft(out, "fender")


def tyres():
    for s in (1, -1):
        for z in (-1.6, -3.2, -4.8):
            y = deck_y(z) - 0.62
            x = s * (hull_x(z, y) + 0.17)
            torus(V(x, y, z), V(s, 0, 0.0), 0.34, 0.13, 10, 5, "fender")
            cyl(V(x, y + 0.42, z), V(s * (hull_x(z, deck_y(z) + 0.6) + 0.02), deck_y(z) + 0.62, z), 0.025, 0.025, 4, "wire")


# --- Superstructure -----------------------------------------------------------------

HOUSE = dict(z0=-1.7, z1=3.7, hw=1.85, y0=1.2, y1=3.4)
WH = dict(z0=0.5, z1=3.4, hw=1.5)


def deckhouse():
    h = HOUSE; cz, hd = (h["z0"] + h["z1"]) / 2, (h["z1"] - h["z0"]) / 2
    loft([rect(0, h["y0"], cz, h["hw"], hd, 0.65, 0.25), rect(0, h["y1"], cz, h["hw"] - 0.08, hd - 0.06, 0.62, 0.22)], "house")
    # Windows, doors and life rings on the sides; two windows forward.
    for s in (1, -1):
        x = s * (h["hw"] - 0.035)
        for z in (1.3, 2.3):
            box(V(x, 2.75, z), (0.06, 0.48, 0.62), "window")
        box(V(x, 2.25, 0.2), (0.05, 1.8, 0.72), "door")
        box(V(x + s * 0.02, 2.75, 0.2), (0.04, 0.32, 0.3), "window")
        torus(V(s * (h["hw"] - 0.02), 2.55, -1.0), V(s, 0, 0), 0.28, 0.07, 10, 4, "orange")
    for x in (-0.55, 0.55):
        box(V(x, 2.75, h["z1"] - 0.04), (0.6, 0.48, 0.06), "window")
    # Handrails round the top of the deckhouse.
    top = rect(0, h["y1"], cz, h["hw"] - 0.14, hd - 0.12, 0.6, 0.2)
    rail = [p + V(0, 0.95, 0) for p in top]
    tube(rail + rail[:1], 0.03, 4, "house")
    for p in top:
        cyl(p, p + V(0, 0.95, 0), 0.025, 0.025, 4, "house")
    for a, b in zip(top, top[1:] + top[:1]):
        m = (a + b) * 0.5
        if (b - a).length > 1.2: cyl(m, m + V(0, 0.95, 0), 0.025, 0.025, 4, "house")


def wheelhouse():
    w = WH; cz, hd = (w["z0"] + w["z1"]) / 2, (w["z1"] - w["z0"]) / 2
    base = rect(0, 3.4, cz, w["hw"], hd, 0.5, 0.15)
    sill = rect(0, 4.15, cz, w["hw"], hd, 0.5, 0.15)
    # Head of the windows: wider and pushed forward, the front windows raked out.
    head = rect(0, 5.15, cz + 0.16, w["hw"] + 0.12, hd + 0.16, 0.56, 0.15)
    roof = rect(0, 5.3, cz + 0.17, w["hw"] + 0.13, hd + 0.17, 0.56, 0.15)
    loft([base, sill, head, roof], lambda i, j, c: "glass" if i == 1 else "house", cap_key="house")
    for a, b in zip(sill, head):
        cyl(a, b, 0.045, 0.045, 4, "house")
    # Mid mullions on the long sides and the back.
    for a0, a1, b0, b1 in ((sill[0], sill[1], head[0], head[1]), (sill[4], sill[5], head[4], head[5]),
                           (sill[6], sill[7], head[6], head[7])):
        cyl((a0 + a1) * 0.5, (b0 + b1) * 0.5, 0.04, 0.04, 4, "house")
    # Visor roof, overhanging most at the front.
    vz = cz + 0.25
    loft([rect(0, 5.3, vz, w["hw"] + 0.25, hd + 0.33, 0.62, 0.2), rect(0, 5.44, vz, w["hw"] + 0.25, hd + 0.33, 0.62, 0.2)], "house")
    # (The sidelights are Models.add_sidelight lamps on the sides, below the windows.)


MAST = V(0, 8.05, 1.25)   # top of the pole: the masthead lantern sits here (Models adds it)


def mast_and_roof():
    r = 5.44
    cyl(V(0, r, MAST.z), MAST, 0.11, 0.065, 6, "house")
    # Struts aft to the roof, a yard with the towing lights, radar on its platform.
    for s in (1, -1):
        cyl(V(s * 0.7, r, MAST.z - 0.8), V(0, 6.9, MAST.z), 0.04, 0.04, 4, "house")
    box(V(0, 7.0, MAST.z), (2.3, 0.08, 0.18), "house")
    for y in (7.35, 7.7):
        box(V(0, y, MAST.z + 0.1), (0.14, 0.18, 0.12), "lamp")
        box(V(0, y, MAST.z + 0.17), (0.1, 0.12, 0.03), "lens_off")
    box(V(0, 6.2, MAST.z + 0.05), (0.9, 0.06, 0.9), "steel")
    cyl(V(0, 6.23, MAST.z + 0.05), V(0, 6.43, MAST.z + 0.05), 0.14, 0.11, 6, "lamp")
    box(V(0, 6.5, MAST.z + 0.05), (1.9, 0.08, 0.2), "house")
    # Fire monitor on a platform at the front of the roof, a searchlight beside it.
    fm = V(0, r, 2.9)
    cyl(fm, fm + V(0, 0.35, 0), 0.22, 0.2, 8, "steel")
    cyl(fm + V(0, 0.35, 0), fm + V(0, 0.55, 0), 0.16, 0.12, 8, "red")
    cyl(fm + V(0, 0.5, 0), fm + V(0, 0.68, 0.75), 0.08, 0.05, 6, "red")
    for s in (1, -1):
        sp = V(s * 0.95, r, 3.2)
        cyl(sp, sp + V(0, 0.25, 0), 0.05, 0.05, 4, "steel")
        cyl(sp + V(0, 0.38, -0.12), sp + V(0, 0.38, 0.14), 0.13, 0.15, 8, "lamp")
        box(sp + V(0, 0.38, 0.15), (0.2, 0.2, 0.02), "lens_off")
        # Whip aerials at the after corners, the horn on the port side.
        cyl(V(s * 1.35, r, 0.75), V(s * 1.45, r + 1.9, 0.7), 0.02, 0.01, 3, "lamp")
    cyl(V(-0.45, 6.62, MAST.z + 0.1), V(-0.45, 6.62, MAST.z + 0.5), 0.04, 0.12, 6, "steel")
    # Liferaft canister between the stacks.
    cyl(V(-0.55, 3.75, -0.9), V(0.55, 3.75, -0.9), 0.27, 0.27, 8, "white")
    for x in (-0.35, 0.35):
        box(V(x, 3.5, -0.9), (0.06, 0.2, 0.5), "steel")


def stacks():
    """Two raked stacks either side behind the wheelhouse: livery colour, a white band,
    black top, with exhaust pipes."""
    for s in (1, -1):
        cx, cz = s * 1.12, -0.85
        ys, keys = [3.4, 4.75, 4.98, 5.35, 5.62], ["stack", "white", "stack", "black"]
        rings = [rect(cx, y, cz - 0.22 * (y - 3.4), 0.3, 0.55, 0.22) for y in ys]
        loft(rings, lambda i, j, c: keys[i], cap_key="black")
        for dz in (-0.18, 0.18):
            p = V(cx, 5.5, cz - 0.22 * 2.1 + dz)
            cyl(p, p + V(0, 0.35, -0.06), 0.08, 0.08, 6, "black")


# --- Deck gear ----------------------------------------------------------------------

def bollard(x, z, h=0.42):
    y = deck_y(z)
    box(V(x, y + 0.05, z), (0.35, 0.1, 0.75), "steel")
    for dz in (-0.2, 0.2):
        cyl(V(x, y, z + dz), V(x, y + h, z + dz), 0.11, 0.11, 6, "steel")
        cyl(V(x, y + h, z + dz), V(x, y + h + 0.05, z + dz), 0.15, 0.15, 6, "steel")


def aft_deck():
    y = deck_y(-3.0)
    # Towing winch: frame cheeks, drum with wire wound on, motor housing.
    wz = -2.55
    for s in (1, -1):
        box(V(s * 0.95, y + 0.5, wz), (0.12, 1.0, 1.1), "steel")
    cyl(V(-0.9, y + 0.62, wz), V(0.9, y + 0.62, wz), 0.32, 0.32, 10, "wire")
    for x in (-0.82, 0.82):
        cyl(V(x - 0.05, y + 0.62, wz), V(x + 0.05, y + 0.62, wz), 0.5, 0.5, 10, "steel")
    box(V(1.3, y + 0.35, wz), (0.5, 0.7, 0.7), "bitt")
    # Tow wire led aft from the drum over the H-bitt and out over the stern.
    hz = -5.4; hy = deck_y(hz)
    tube([V(0, y + 0.92, wz - 0.05), V(0, y + 0.95, wz - 1.2), V(0, hy + 0.95, hz + 0.3), V(0, hy + 0.98, hz),
          V(0, hy + 0.85, hz - 0.45), V(0, hy + 0.35, hz - 0.6)], 0.04, 4, "wire")
    # H-bitt.
    for s in (1, -1):
        cyl(V(s * 0.45, hy, hz), V(s * 0.45, hy + 0.95, hz), 0.14, 0.14, 8, "bitt")
    box(V(0, hy + 0.8, hz), (0.9, 0.16, 0.16), "bitt")
    # The staple: an arch over the after deck so the tow wire clears it.
    sz = -4.2; sy = deck_y(sz)
    arch = [V(-2.15, sy + 0.4, sz), V(-2.05, sy + 1.6, sz)]
    for i in range(1, 8):
        a = math.pi * i / 8
        arch.append(V(-1.6 * math.cos(a) * 1.25, sy + 1.6 + 0.45 * math.sin(a), sz))
    arch += [V(2.05, sy + 1.6, sz), V(2.15, sy + 0.4, sz)]
    tube(arch, 0.11, 6, "stack")
    # Bollards on the quarters, a hatch, the stern light.
    for s in (1, -1):
        bollard(s * 1.55, -6.1)
        bollard(s * 1.85, 3.9)
    box(V(1.0, y + 0.15, -4.95), (0.9, 0.3, 0.7), "steel")
    st = V(0, deck_y(-7) + bulwark(-7) - 0.12, -7.04)
    box(st, (0.24, 0.2, 0.08), "lamp")
    box(st + V(0, 0, -0.04), (0.14, 0.1, 0.02), "lens")


def fore_deck():
    z = 5.4; y = deck_y(z)
    # Bow H-bitt and anchor windlass.
    for s in (1, -1):
        cyl(V(s * 0.4, y, z), V(s * 0.4, y + 0.75, z), 0.13, 0.13, 8, "bitt")
    box(V(0, y + 0.6, z), (0.8, 0.14, 0.14), "bitt")
    wz = 4.5; wy = deck_y(wz)
    box(V(0, wy + 0.25, wz), (1.3, 0.5, 0.6), "steel")
    for s in (1, -1):
        cyl(V(s * 0.65, wy + 0.35, wz), V(s * 0.95, wy + 0.35, wz), 0.25, 0.25, 8, "black")
    # Fairlead in the stem.
    fz = 6.75
    box(V(0, deck_y(fz) + bulwark(fz) - 0.05, fz), (0.5, 0.14, 0.35), "steel")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); transom_bulwark(); belt(); bow_fender(); tyres()
    deckhouse(); wheelhouse(); mast_and_roof(); stacks()
    aft_deck(); fore_deck()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("tug_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("tug_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "tug_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
