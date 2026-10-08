# Builds the mid-poly container feeder in Blender (run inside Blender: exec(open(path).read()))
# and exports it to assets/models/cargo_mid.glb (glTF, +Y up, vertex colours, flat shaded),
# plus scripts/world/cargo_mid_data.gd (the glyph advances, the bow's surface where the
# name goes and the container slots, for Models).
# Game frame, like the code-built container ship it replaces: +Z is the bow, +Y up, the
# waterline at y = 0, 64 m long and 11.2 m in the beam, the main deck at y = 3.2
# (Blender: bow to -Y, Z up).
# The hull is lofted from sections: a flat bottom and round bilges amidships, a fine
# entrance with flare under a raised forecastle, a raked stem and a bulb; aft the run
# lifts to a transom over a skeg, rudder and propeller. Three hatches on deck (each
# takes a 40 ft bay or two 20 ft ones, four rows across) under pontoon covers; the
# accommodation aft, four decks and the bridge with open wings, the funnel behind it,
# the radar mast, external stairs, a free-fall lifeboat on its ramp over the stern.
# The livery is split into parts so Models can recolour them per variant: `hull` (the
# topsides) and `funnel` (its band), each one flat colour; everything else is `fixed`.
# Glass: `glass` (the bridge, lit at night), `window` (cabins, some lit), `lens`.
# Containers are parts of their own, `c20_<line>` / `c40_<line>` (`c40r_<line>` for
# reefers), each in its own frame (bottom centre at the origin, doors to +Z), with
# corrugated sides, ends and roof and the line's name painted over the ribs; Models
# stacks them. `gl_<c>` are the glyphs of the hull's lettering (pen at the origin,
# facing +Z, cap height 1), which Models sets the ship's own name in.
import bpy, bmesh, json, math, os
from mathutils import Vector

PAL = {
    "hull": (0.12, 0.16, 0.24), "funnel": (0.85, 0.55, 0.12), "house": (0.93, 0.94, 0.93),
    "antifoul": (0.55, 0.14, 0.12), "white": (0.92, 0.93, 0.92), "deck": (0.34, 0.4, 0.36),
    "hatch": (0.33, 0.37, 0.41), "edge": (0.8, 0.82, 0.82), "glass": (0.16, 0.22, 0.27),
    "window": (0.16, 0.22, 0.27), "steel": (0.6, 0.62, 0.63), "dark": (0.24, 0.25, 0.27),
    "black": (0.07, 0.07, 0.07), "orange": (0.95, 0.42, 0.1), "lamp": (0.12, 0.12, 0.13),
    "lens": (0.95, 0.95, 0.85), "yellow": (0.88, 0.72, 0.18), "chain": (0.18, 0.17, 0.16),
    "prop": (0.72, 0.56, 0.3), "rope": (0.75, 0.66, 0.48), "door": (0.8, 0.82, 0.82),
}
ROLES = ("hull", "funnel", "glass", "window", "lens")
UP = Vector((0, 1, 0))
ART = os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art"


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t
def clamp(x, a=0.0, b=1.0): return min(max(x, a), b)


def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


coll = bpy.data.collections.get("Cargo") or bpy.data.collections.new("Cargo")
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
PART = [None]   # when set, every face goes into this part (containers, glyphs)


def bm_for(key):
    role = PART[0] or (key if key in ROLES else "fixed")
    if role not in BMS:
        bm = bmesh.new(); bm.loops.layers.color.new("Col"); BMS[role] = bm
    return BMS[role]


def face(pts, key):
    """One face in the given winding (callers orient it); colour by palette key or an
    (r, g, b) tuple."""
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
    # (A bmesh `color` layer is bytes stored as sRGB and exported linear, so the palette
    # goes in as it is; Models turns the glTF's linear colours back into sRGB.)
    c = PAL[key] if isinstance(key, str) else key
    for l in f.loops: l[cl] = (*c, 1.0)


def normal(pts):
    n = Vector()
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += a.cross(b)
    return n


def centre(pts): return sum(pts, Vector()) / len(pts)


def oriented(pts, out):
    """`pts` wound so the face looks along `out`."""
    return pts if normal(pts).dot(out) > 0 else pts[::-1]


def loft(rings, key, closed_ring=True, closed_path=False, caps=True, cap_key=None):
    """Quads between successive rings (same vertex count, same direction). `key` is a
    palette key or fn(i, j, centroid) -> key. The whole surface is wound outward from
    the rings' centres (by majority, so concave sections stay right)."""
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
            face(oriented(r, centre(r) - centre(o)), ck)


def rect(cx, y, cz, hw, hd, ch=0.0, chb=None):
    """Horizontal rectangle (optionally chamfered: `ch` front corners, `chb` back)."""
    chb = ch if chb is None else chb
    pts = [(cx + hw, cz - hd + chb), (cx + hw, cz + hd - ch), (cx + hw - ch, cz + hd), (cx - hw + ch, cz + hd),
           (cx - hw, cz + hd - ch), (cx - hw, cz - hd + chb), (cx - hw + chb, cz - hd), (cx + hw - chb, cz - hd)]
    return [V(x, y, z) for x, z in pts]


def box(c, size, key):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    loft([rect(c.x, c.y - hy, c.z, hx, hz), rect(c.x, c.y + hy, c.z, hx, hz)], key)


def box6(c, size, key, skip=()):
    """An axis-aligned box as six quads (12 triangles), leaving out the faces named
    in `skip` ('-y', '+x', ...)."""
    h = Vector(size) / 2
    for ax in range(3):
        for s in (-1, 1):
            if ("+" if s > 0 else "-") + "xyz"[ax] in skip: continue
            u, w = [(1, 2), (2, 0), (0, 1)][ax]
            n = Vector(); n[ax] = s
            pts = []
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                p = Vector(); p[ax] = s * h[ax]; p[u] = a * h[u]; p[w] = b * h[w]
                pts.append(c + p)
            face(oriented(pts, n), key)


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


def prism(profile, x0, x1, key):
    """A plate: the (z, y) outline `profile` extruded across from x0 to x1."""
    loft([[V(x0, y, z) for z, y in profile], [V(x1, y, z) for z, y in profile]], key)


def beam_between(a, b, w, h, key):
    """A rectangular member from a to b, `w` wide (horizontal) and `h` deep."""
    d = (b - a).normalized()
    side = d.cross(UP)
    side = side.normalized() if side.length > 1e-4 else V(1, 0, 0)
    up = side.cross(d).normalized()
    ring = lambda p: [p + side * sx * w / 2 + up * sy * h / 2 for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    loft([ring(a), ring(b)], key)


# --- Hull ------------------------------------------------------------------------

FC_Z = 24.6            # the forecastle's after end
DECK = 3.2
ENTRANCE = 14.0        # where the bow starts to fine away
STATIONS = [-32.0, -31.4, -30.0, -28.0, -26.0, -24.0, -21.5, -18.5, -15.0, -8.0, 0.0, 8.0, 14.0, 16.5,
            18.5, 20.5, 22.5, FC_Z - 0.02, FC_Z, 25.6, 26.6, 27.5, 28.3, 29.0, 29.6, 30.2, 30.7, 31.15, 31.55, 32.0]


def deck_y(z):
    if z >= FC_Z: return 5.4 + 0.35 * smooth(FC_Z, 32.0, z) ** 1.5
    return DECK


def stem_z(y):
    """The stem line: the forefoot curving up to the waterline, then raked out."""
    if y < 0.25: return 26.2 + 3.4 * math.sqrt(clamp((y + 2.6) / 2.85))
    return 29.6 + (y - 0.25) * 0.436


def mid_params(z):
    """Keel height, half breadth at the bilge top and at the deck edge, bilge radius,
    before the bow is shaped: the run lifts and narrows aft to the transom."""
    yk = -2.6 + 3.1 * smooth(-17.0, -32.0, z) ** 1.4
    W = 5.6 - 1.3 * smooth(-20.0, -32.0, z)
    b = 5.6 - 0.5 * smooth(-24.0, -32.0, z)
    r = 1.0 - 0.5 * smooth(-18.0, -32.0, z)
    return yk, W, b, r


def bow_shape(z, y):
    """How much of its midship half breadth the hull keeps at (z, y) in the entrance,
    and the z it's pulled back to on the stem: fine low down, full (flared) high up."""
    if z <= ENTRANCE: return 1.0, z
    zs = stem_z(y)
    s = (z - ENTRANCE) / (zs - ENTRANCE)
    if s >= 1.0: return 0.0, zs
    p = 1.7 + 1.2 * clamp((y + 2.6) / 8.0)
    return (1.0 - s ** p) ** 0.55, z


def section_raw(z):
    """Starboard half from the keel to the deck centre at station z, as (x, y): keel
    centre, the flat's edge, the bilge (30, 60 degrees, top), the boot top (y 0.25), a
    two points up the side, the deck edge, the deck centre."""
    yk, W, b, r = mid_params(z)
    d = deck_y(z)
    bx = max(W - r, 0.05)
    pts = [(0.0, yk), (bx, yk)]
    for a in (30, 60):
        ar = math.radians(a)
        pts.append((bx + r * math.sin(ar), yk + r - r * math.cos(ar)))
    yt = yk + r
    pts.append((W, yt))

    def side(y): return lerp(W, b, clamp((y - yt) / (d - yt)) ** 0.8)
    y5 = max(0.25, yt + 0.05); y6 = max(1.6, y5 + 0.05); y7 = max(3.0, y6 + 0.05)
    pts += [(side(y5), y5), (side(y6), y6), (side(y7), y7), (b, d), (0.0, d + 0.12)]
    return pts


def section(z):
    """section_raw shaped by the bow, as 3D points (z may be pulled back to the stem)."""
    out = []
    for x, y in section_raw(z):
        k, zz = bow_shape(z, y)
        out.append(V(x * k, y, zz))
    return out


def hull_x(z, y):
    """Half breadth of the hull's outside at (z, y), keel to deck edge."""
    s = [(p.x, p.y) for p in section(z)][:9]
    if y <= s[0][1]: return s[0][0]
    for (x0, y0), (x1, y1) in zip(s, s[1:]):
        if y0 <= y <= y1 and y1 > y0: return lerp(x0, x1, (y - y0) / (y1 - y0))
    return s[-1][0]


def hull_at(z, y, sx=1):
    """Point on the hull's side at (z, y) on side sx, and the outward normal there."""
    e = 0.05
    p = V(sx * hull_x(z, y), y, z)
    dz = V(sx * hull_x(z + e, y), y, z + e) - V(sx * hull_x(z - e, y), y, z - e)
    dy = V(sx * hull_x(z, y + e), y + e, z) - V(sx * hull_x(z, y - e), y - e, z)
    n = dz.cross(dy).normalized()
    if n.x * sx < 0: n = -n
    return p, n


def hull():
    rings = []
    for z in STATIONS:
        s = section(z)
        rings.append(s + [V(-p.x, p.y, p.z) for p in reversed(s[1:-1])])
    step = STATIONS.index(FC_Z - 0.02)

    def col(i, j, c):
        s = j if j <= 8 else 17 - j
        if s <= 4: return "antifoul"
        if s == 8: return "white" if i == step else "deck"
        return "hull"
    loft(rings, col, caps=False)
    # The transom (all above the waterline): a flat face, the hull's colour.
    face(oriented(rings[0], V(0, 0, -1)), "hull")


def bulb():
    rings = []
    for z, k in ((25.0, 1.0), (27.0, 1.0), (28.6, 0.96), (29.8, 0.84), (30.6, 0.62), (31.05, 0.36), (31.25, 0.12)):
        rings.append([V(0.9 * k * math.cos(a), -1.45 + 1.0 * k * math.sin(a), z)
                      for a in (math.tau * i / 10 for i in range(10))])
    loft(rings, "antifoul")


def stern_gear():
    """Skeg, rudder (on its horn) and the four-bladed propeller."""
    prism([(-12.0, -2.6), (-26.4, -2.6), (-26.4, -1.6), (-22.0, -0.4), (-12.0, -2.2)], -0.3, 0.3, "antifoul")
    hub_z = -27.2
    cyl(V(0, -1.45, -26.4), V(0, -1.45, hub_z - 0.45), 0.32, 0.22, 8, "prop")
    for i in range(4):
        a = math.tau * i / 4 + 0.4
        d = V(math.cos(a), math.sin(a), 0)
        t = V(-math.sin(a), math.cos(a), 0)
        c = V(0, -1.45, hub_z)
        root, tip = c + d * 0.25, c + d * 1.05
        face([root + t * 0.32 + V(0, 0, 0.12), tip + t * 0.18 + V(0, 0, 0.05), tip - t * 0.18 - V(0, 0, 0.05),
              root - t * 0.32 - V(0, 0, 0.12)], "prop")
        face([root - t * 0.32 - V(0, 0, 0.12), tip - t * 0.18 - V(0, 0, 0.05), tip + t * 0.18 + V(0, 0, 0.05),
              root + t * 0.32 + V(0, 0, 0.12)], "prop")
    prism([(-28.5, -2.4), (-30.6, -2.4), (-30.7, 0.2), (-28.4, 0.2)], -0.22, 0.22, "antifoul")
    cyl(V(0, 0.15, -29.5), V(0, 1.0, -29.5), 0.25, 0.25, 6, "antifoul")


def bulwark(path, h, mid, key_out="hull", key_in="white", t=0.12):
    """A bulwark along the polyline `path` (on deck, outboard edge): outside, inside, cap."""
    ns = []
    for i, p in enumerate(path):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        tg = b - a; tg.y = 0; tg.normalize()
        n = V(tg.z, 0, -tg.x)
        o = p - mid; o.y = 0
        if n.dot(o) < 0: n = -n
        ns.append(n)
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        ia, ib = a - ns[i] * t, b - ns[i + 1] * t
        top = V(0, h, 0)
        face(oriented([a, b, b + top, a + top], ns[i] + ns[i + 1]), key_out)
        face(oriented([ia, ib, ib + top, ia + top], -(ns[i] + ns[i + 1])), key_in)
        face(oriented([a + top, b + top, ib + top, ia + top], UP), "white")


def deck_edge(z, inset=0.0, sx=1):
    y = deck_y(z)
    return V(sx * (hull_x(z, y) - inset), y, z)


def forecastle():
    zs = [FC_Z + 0.02, 25.6, 26.6, 27.5, 28.3, 29.0, 29.6, 30.2, 30.7, 31.15]
    path = [deck_edge(z, 0.0, -1) for z in zs] + [V(0, deck_y(31.6), 31.6)] + [deck_edge(z, 0.0, 1) for z in reversed(zs)]
    bulwark(path, 1.1, V(0, 0, 27.0))
    # The breakwater: a V across the forecastle, stiffened behind.
    y = deck_y(25.4)
    for sx in (1, -1):
        a, b = V(0, y, 26.6), V(sx * 4.9, y, 25.2)
        top = V(0, 2.0, 0)
        face(oriented([a, b, b + top, a + top], V(sx * 0.3, 0, 1)), "white")
        face(oriented([a - V(0, 0, 0.1), b - V(0, 0, 0.1), b + top - V(0, 0, 0.1), a + top - V(0, 0, 0.1)],
                      V(-sx * 0.3, 0, -1)), "white")
        for t in (0.25, 0.5, 0.75):
            p = lerp(a, b, t) - V(0, 0, 0.1)
            prism([(p.z, y), (p.z - 0.9, y), (p.z, y + 1.9)], p.x - 0.04, p.x + 0.04, "white")
    # Windlasses, their chain to the hawse pipes, bollards and the foremast.
    for sx in (1, -1):
        w = V(sx * 1.5, deck_y(27.6), 27.6)
        box(w + V(0, 0.35, 0), (1.0, 0.7, 1.2), "dark")
        cyl(w + V(-sx * 0.55, 0.5, 0), w + V(-sx * 0.15, 0.5, 0), 0.42, 0.42, 10, "black")
        cyl(w + V(sx * 0.55, 0.45, 0), w + V(sx * 0.85, 0.45, 0), 0.32, 0.32, 8, "steel")
        hp = V(sx * 2.2, deck_y(29.2) + 0.02, 29.2)
        cyl(hp, hp + V(0, 0.18, 0), 0.32, 0.32, 8, "dark")
        tube([w + V(-sx * 0.35, 0.55, 0.35), hp + V(0, 0.2, -0.1)], 0.07, 4, "chain")
        for z in (26.2, 30.0):
            bp = deck_edge(z, 0.9, sx)
            for dz in (-0.25, 0.25):
                cyl(bp + V(0, 0, dz), bp + V(0, 0.5, dz), 0.14, 0.14, 6, "black")
    foremast()


FORE_MAST = V(0, 11.0, 29.0)   # top of the foremast: Models stands the masthead lantern here


def foremast():
    y = deck_y(FORE_MAST.z)
    cyl(V(0, y, FORE_MAST.z), FORE_MAST, 0.18, 0.12, 8, "yellow")
    box(V(0, 8.6, FORE_MAST.z), (1.6, 0.1, 0.1), "yellow")
    box(V(0, 8.55, FORE_MAST.z + 0.1), (0.3, 0.3, 0.06), "black")       # anchor ball's hoist
    cyl(V(0, 6.2, FORE_MAST.z + 0.15), V(0, 6.2, FORE_MAST.z + 0.55), 0.12, 0.25, 6, "steel")   # horn


def anchors():
    """Anchors drawn up in pockets either side of the bow, the hawse holes above."""
    for sx in (1, -1):
        p, n = hull_at(28.6, 4.1, sx)
        t = V(n.z, 0, -n.x).normalized()
        up = n.cross(t).normalized()
        if up.y < 0: up = -up
        c = p + n * 0.02
        ring = [c + t * (0.55 * math.cos(a)) + up * (0.55 * math.sin(a)) for a in (math.tau * i / 8 for i in range(8))]
        face(oriented(ring, n), "black")
        a = c + n * 0.08
        face(oriented([a + up * 0.3 + t * 0.12, a + up * 0.3 - t * 0.12, a - up * 0.8 - t * 0.12, a - up * 0.8 + t * 0.12], n),
             "dark")
        face(oriented([a - up * 0.5 + t * 0.6, a - up * 0.5 - t * 0.6, a - up * 1.0 - t * 0.2, a - up * 1.0 + t * 0.2], n),
             "dark")


def decal(points2d, z, y, sx, key, eps=0.025):
    """A flat shape on the hull's side, around (z, y) on side sx: points (u, v) in
    metres, u toward the bow."""
    p, n = hull_at(z, y, sx)
    t = V(0, 0, 1) - n * n.z; t.normalize()
    up = n.cross(t).normalized()
    if up.y < 0: up = -up
    face(oriented([p + n * eps + t * u + up * v for u, v in points2d], n), key)


def bar(u0, v0, u1, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def hull_marks():
    """Load line (Plimsoll) amidships, draft marks fore and aft, the bow thruster sign."""
    for sx in (1, -1):
        z0 = -2.0
        ring = [(0.45 * math.cos(a), 0.45 * math.sin(a)) for a in (math.tau * i / 12 for i in range(12))]
        inner = [(0.37 * math.cos(a), 0.37 * math.sin(a)) for a in (math.tau * i / 12 for i in range(12))]
        for i in range(12):
            k = (i + 1) % 12
            decal([ring[i], ring[k], inner[k], inner[i]], z0, 0.9, sx, "white")
        decal(bar(-0.65, -0.04, 0.65, 0.04), z0, 0.9, sx, "white")
        decal(bar(-1.4, 1.0, -1.0, 1.06), z0, 0.9, sx, "white")           # the deck line's mark
        decal(bar(0.8, -0.04, 1.6, 0.04), z0, 0.9, sx, "white")
        decal(bar(0.8, -0.6, 0.86, 0.9), z0, 0.9, sx, "white")
        for z in (-31.0, 27.4):
            for k in range(5):
                decal(bar(-0.15, -0.05, 0.15, 0.05), z, 0.4 + k * 0.4, sx, "white")
                if k % 2 == 0: decal(bar(0.2, -0.12, 0.26, 0.12), z, 0.4 + k * 0.4, sx, "white")
        # Bow thruster: a circle with a cross, above where the tunnel is.
        for i in range(12):
            k = (i + 1) % 12
            o = [(0.42 * math.cos(a), 0.42 * math.sin(a)) for a in (math.tau * j / 12 for j in (i, k))]
            m = [(0.35 * math.cos(a), 0.35 * math.sin(a)) for a in (math.tau * j / 12 for j in (i, k))]
            decal([o[0], o[1], m[1], m[0]], 25.0, 1.2, sx, "white")
        for a in (0.785, -0.785):
            c, s = math.cos(a), math.sin(a)
            decal([(c * -0.35 - s * 0.03, s * -0.35 + c * 0.03), (c * 0.35 - s * 0.03, s * 0.35 + c * 0.03),
                   (c * 0.35 + s * 0.03, s * 0.35 - c * 0.03), (c * -0.35 + s * 0.03, s * -0.35 - c * 0.03)],
                  25.0, 1.2, sx, "white")


# --- Deck: hatches and rails ------------------------------------------------------

HATCH_Z = (-13.26, 0.0, 13.26)
HATCH_LEN = 12.0
COAMING_HW = 4.7
COVER_TOP = 4.3        # containers stand here
BAY_PITCH = 6.26       # 20 ft slots: a 40 ft hatch takes two, either side of its middle
COL_X = (-3.69, -1.23, 1.23, 3.69)


def hatches():
    for zc in HATCH_Z:
        z0, z1 = zc - HATCH_LEN / 2, zc + HATCH_LEN / 2
        box(V(0, 3.62, zc), (COAMING_HW * 2, 0.9, HATCH_LEN), "hatch")
        # Stays down the coaming's sides and ends.
        for sx in (1, -1):
            for i in range(9):
                z = lerp(z0 + 0.6, z1 - 0.6, i / 8)
                tri = lambda zz: [V(sx * COAMING_HW, 3.2, zz), V(sx * (COAMING_HW + 0.35), 3.2, zz),
                                  V(sx * COAMING_HW, 3.95, zz)]
                loft([tri(z - 0.04), tri(z + 0.04)], "hatch")
        # Two pontoon covers, each with a raised panel and the seam between them.
        for half in (-1, 1):
            c = V(0, 4.17, zc + half * HATCH_LEN / 4)
            box(c, (COAMING_HW * 2 - 0.1, 0.26, HATCH_LEN / 2 - 0.08), "hatch")
            for dz in (-1.5, 0.0, 1.5):
                box(c + V(0, 0.15, dz), (COAMING_HW * 2 - 0.5, 0.04, 0.12), "dark")
        # Container sockets (dark) on the cover under each corner.
        for x in COL_X:
            for z in (zc - 6.09, zc + 6.09, zc - 0.07, zc + 0.07):
                box(V(x - 1.12, COVER_TOP + 0.01, z), (0.18, 0.02, 0.12), "black")
                box(V(x + 1.12, COVER_TOP + 0.01, z), (0.18, 0.02, 0.12), "black")


def rail(path, h=1.0, key="steel", every=1.6):
    """Guard rail on the deck points `path`: top and mid rails, stanchions about
    `every` metres apart."""
    tube([p + V(0, h, 0) for p in path], 0.03, 4, key)
    tube([p + V(0, h * 0.5, 0) for p in path], 0.022, 4, key)
    for a, b in zip(path, path[1:]):
        n = max(1, round((b - a).length / every))
        for i in range(n):
            p = lerp(a, b, i / n)
            cyl(p, p + V(0, h, 0), 0.025, 0.025, 4, key)
    cyl(path[-1], path[-1] + V(0, h, 0), 0.025, 0.025, 4, key)


def deck_rails():
    zs = [-20.0, -14.0, -8.0, -2.0, 4.0, 10.0, 14.0, 16.5, 18.5, 20.5, 22.5, FC_Z - 0.2]
    for sx in (1, -1):
        rail([deck_edge(z, 0.08, sx) for z in zs])
    # The forecastle's after end: a rail on the step, ladders down to the main deck.
    for sx in (1, -1):
        rail([V(sx * 0.9, deck_y(FC_Z + 0.05), FC_Z + 0.05), deck_edge(FC_Z + 0.05, 0.2, sx)])
        lx = sx * 3.0
        a, b = V(lx, DECK, FC_Z - 2.2), V(lx, deck_y(FC_Z), FC_Z - 0.05)
        for dx in (-0.4, 0.4):
            beam_between(a + V(dx, 0, 0), b + V(dx, 0, 0), 0.06, 0.25, "steel")
            tube([a + V(dx, 1.0, 0), b + V(dx, 1.0, 0)], 0.025, 4, "steel")
        for i in range(1, 8):
            p = lerp(a, b, i / 8)
            box(p, (0.8, 0.04, 0.22), "steel")
    # The forecastle's after bulkhead: doors, a store's hatch.
    for sx in (1, -1):
        box(V(sx * 1.6, DECK + 0.95, FC_Z - 0.03), (0.8, 1.9, 0.05), "door")
    # Cross-deck walkways between the hatches, lashing-gear bins.
    for z in (-6.63, 6.63):
        for sx in (1, -1):
            box(V(sx * 3.0, DECK + 0.3, z), (0.9, 0.6, 0.6), "yellow")


# --- Accommodation ----------------------------------------------------------------

HOUSE_Z = (-27.2, -20.0)
HOUSE_HW = 4.6
LEVELS = (3.2, 5.7, 8.2, 10.7, 13.2)
BRIDGE = dict(z0=-23.6, z1=-20.0, hw=4.3, sill=14.25, head=15.4, roof=15.8)
WING_HW = 6.3
SIDELIGHT = V(6.38, 14.25, -20.55)   # outboard face of the port (+X) wing's end (starboard: -x)
AFT_MAST = V(0, 19.4, -22.2)        # radar mast's top: the after masthead lantern stands here
STERN_LIGHT = V(0, 4.55, -32.12)


def house():
    z0, z1 = HOUSE_Z
    zc, hd = (z0 + z1) / 2, (z1 - z0) / 2
    for k in range(4):
        y0, y1 = LEVELS[k], LEVELS[k + 1]
        box(V(0, (y0 + y1) / 2, zc), (HOUSE_HW * 2, y1 - y0, z1 - z0), "house")
        # The deck's edge, standing a little proud all round.
        box(V(0, y1 - 0.06, zc), (HOUSE_HW * 2 + 0.24, 0.16, z1 - z0 + 0.24), "edge")
        wy = y0 + 1.35
        # Windows: forward, down the sides, aft.
        fw = (-3.5, -2.1, -0.7, 0.7, 2.1, 3.5) if k > 0 else (-3.5, -2.1, 2.1, 3.5)
        for x in fw:
            box(V(x, wy, z1 + 0.01), (0.75, 0.85, 0.04), "window")
        for sx in (1, -1):
            for z in (-25.8, -24.2, -22.6, -21.1):
                box(V(sx * (HOUSE_HW + 0.01), wy, z), (0.04, 0.85, 0.75), "window")
        for x in (-2.2, 2.2):
            box(V(x, wy, z0 - 0.01), (0.75, 0.85, 0.04), "window")
        if k == 0:
            box(V(0, y0 + 1.0, z1 + 0.02), (0.9, 2.0, 0.04), "door")
            box(V(0, y0 + 1.0, z0 - 0.02), (0.9, 2.0, 0.04), "door")
        else:
            box(V(0, y0 + 1.0, z0 - 0.02), (0.9, 2.0, 0.04), "door")
    # Air intakes / vents on the sides of the ground floor.
    for sx in (1, -1):
        box(V(sx * (HOUSE_HW + 0.03), 4.2, -26.6), (0.06, 1.2, 0.8), "dark")
    bridge()
    stairs()
    funnel()
    lifeboat()
    # Rail round the bridge deck (the top of the house) behind the wheelhouse.
    y = LEVELS[4]
    path = [V(HOUSE_HW, y, BRIDGE["z0"] - 0.1), V(HOUSE_HW, y, z0 + 0.05), V(-HOUSE_HW, y, z0 + 0.05),
            V(-HOUSE_HW, y, BRIDGE["z0"] - 0.1)]
    rail(path, 1.0, "white", 1.4)


def bridge():
    b = BRIDGE
    z0, z1, hw = b["z0"], b["z1"], b["hw"]
    zc, hd = (z0 + z1) / 2, (z1 - z0) / 2
    base = rect(0, LEVELS[4], zc, hw, hd, 0.35, 0.0)
    sill = rect(0, b["sill"], zc, hw, hd, 0.35, 0.0)
    head = rect(0, b["head"], zc + 0.18, hw + 0.04, hd + 0.18, 0.4, 0.0)
    top = rect(0, b["head"] + 0.08, zc + 0.19, hw + 0.05, hd + 0.19, 0.4, 0.0)
    loft([base, sill, head, top], lambda i, j, c: "glass" if i == 1 and c.z > z0 + 0.05 else "house", cap_key="house")
    for a, c in zip(sill, head):
        cyl(a, c, 0.04, 0.04, 4, "house")
    for i in range(1, 8):
        t = i / 8
        cyl(lerp(sill[2], sill[3], t), lerp(head[2], head[3], t), 0.035, 0.035, 4, "house")
    for sx, (a0, a1) in ((1, (0, 1)), (-1, (5, 4))):
        for t in (0.33, 0.66):
            cyl(lerp(sill[a0], sill[a1], t), lerp(head[a0], head[a1], t), 0.035, 0.035, 4, "house")
    # The roof, a visor forward; the wings either side, open, with dodgers.
    loft([rect(0, b["head"] + 0.08, zc + 0.3, hw + 0.15, hd + 0.3, 0.45, 0.0),
          rect(0, b["roof"], zc + 0.3, hw + 0.15, hd + 0.3, 0.45, 0.0)], "house")
    for sx in (1, -1):
        wz0, wz1 = -21.7, -20.0
        box(V(sx * (hw + WING_HW) / 2, LEVELS[4] - 0.1, (wz0 + wz1) / 2), (WING_HW - hw + 0.2, 0.2, wz1 - wz0), "edge")
        # Brackets under the wing, out past the house side.
        for z in (wz0 + 0.2, wz1 - 0.2):
            a, c = V(sx * HOUSE_HW, LEVELS[4] - 1.5, z), V(sx * (WING_HW - 0.2), LEVELS[4] - 0.2, z)
            beam_between(a, c, 0.1, 0.18, "edge")
        # Dodger along the front and round the end (the sidelight on it), rail aft.
        f0, f1 = V(sx * hw, LEVELS[4], wz1 - 0.05), V(sx * WING_HW, LEVELS[4], wz1 - 0.05)
        e1 = V(sx * WING_HW, LEVELS[4], wz0 + 0.6)
        for a, c in ((f0, f1), (f1, e1)):
            n = (c - a).cross(UP)
            n = n if n.dot(V(sx, 0, 1)) > 0 else -n
            face(oriented([a, c, c + V(0, 1.15, 0), a + V(0, 1.15, 0)], n), "house")
            face(oriented([a - n.normalized() * 0.06, c - n.normalized() * 0.06, c + V(0, 1.15, 0) - n.normalized() * 0.06,
                           a + V(0, 1.15, 0) - n.normalized() * 0.06], -n), "house")
            face(oriented([a + V(0, 1.15, 0), c + V(0, 1.15, 0), c + V(0, 1.15, 0) - n.normalized() * 0.06,
                           a + V(0, 1.15, 0) - n.normalized() * 0.06], UP), "edge")
        rail([e1, V(sx * WING_HW, LEVELS[4], wz0 + 0.05), V(sx * hw, LEVELS[4], wz0 + 0.05)], 1.1, "white", 1.0)
        # The sidelight's housing and screen on the end of the dodger (Models adds the lamp).
        box(V(sx * (WING_HW + 0.02), SIDELIGHT.y + 0.1, SIDELIGHT.z), (0.08, 0.5, 0.6), "lamp")
        # Wing console and a repeater.
        box(V(sx * (WING_HW - 0.5), LEVELS[4] + 0.55, -20.4), (0.6, 1.1, 0.4), "dark")
    radar_mast()


def radar_mast():
    r = BRIDGE["roof"]
    m = AFT_MAST
    cyl(V(0, r, m.z), m, 0.2, 0.13, 8, "house")
    for sx in (1, -1):
        cyl(V(sx * 1.2, r, m.z - 1.0), V(0, 17.6, m.z), 0.06, 0.06, 4, "house")
    # Platform with the two radar scanners on their pedestals, the yard above.
    box(V(0, 17.6, m.z + 0.2), (3.6, 0.1, 1.0), "house")
    rail([V(1.8, 17.65, m.z - 0.3), V(1.8, 17.65, m.z + 0.7), V(-1.8, 17.65, m.z + 0.7), V(-1.8, 17.65, m.z - 0.3)],
         0.6, "white", 0.9)
    for sx, length in ((1, 2.6), (-1, 1.8)):
        p = V(sx * 1.0, 17.65, m.z + 0.35)
        cyl(p, p + V(0, 0.35, 0), 0.16, 0.13, 6, "white")
        box(p + V(0, 0.45, 0), (length, 0.16, 0.22), "white")
    box(V(0, 18.6, m.z), (2.6, 0.08, 0.08), "white")
    for sx in (1, -1):
        box(V(sx * 1.3, 18.55, m.z), (0.12, 0.12, 0.12), "lamp")    # the NUC / signal lamps
    # Domes and whips on the wheelhouse roof.
    for x, z in ((2.2, -21.0), (-2.4, -21.2), (2.8, -23.0)):
        cyl(V(x, r, z), V(x, r + 0.3, z), 0.05, 0.05, 4, "white")
        cyl(V(x, r + 0.3, z), V(x, r + 0.45, z), 0.15, 0.08, 6, "white")
    for x in (-3.8, 3.8):
        cyl(V(x, r, -23.0), V(x * 1.05, r + 3.0, -23.1), 0.025, 0.012, 3, "black")
    rail([V(BRIDGE["hw"] + 0.1, r, -23.4), V(BRIDGE["hw"] + 0.1, r, -19.9), V(-BRIDGE["hw"] - 0.1, r, -19.9),
          V(-BRIDGE["hw"] - 0.1, r, -23.4)], 0.9, "white", 1.4)


def stairs():
    """External stairs up the aft end of the house sides, flight by flight, a landing
    at each deck."""
    for sx in (1, -1):
        x = sx * (HOUSE_HW + 0.36)
        for k in range(4):
            y0, y1 = LEVELS[k], LEVELS[k + 1]
            up_fwd = k % 2 == 0
            za, zb = (-26.9, -24.4) if up_fwd else (-24.4, -26.9)
            a, b = V(x, y0, za), V(x, y1, zb)
            for dx in (-0.3, 0.3):
                beam_between(a + V(dx, 0, 0), b + V(dx, 0, 0), 0.05, 0.22, "white")
            for i in range(1, 10):
                box(lerp(a, b, i / 10), (0.6, 0.04, 0.2), "white")
            tube([a + V(sx * 0.32, 1.0, 0), b + V(sx * 0.32, 1.0, 0)], 0.025, 4, "white")
            # The landing at the top.
            lz = zb + (0.5 if up_fwd else -0.5)
            box(V(x, y1 - 0.05, lz), (0.72, 0.08, 1.2), "edge")
            rail([V(x + sx * 0.34, y1, lz - 0.6), V(x + sx * 0.34, y1, lz + 0.6)], 1.0, "white", 1.0)


def funnel():
    """The funnel on the bridge deck behind the wheelhouse, raked aft: white, the
    line's band, a black top, two exhausts."""
    zc, y0, y1 = -25.2, LEVELS[4], 18.2
    rake = 0.12

    def ring(y, grow=0.0):
        c = V(0, y, zc - (y - y0) * rake)
        return rect(c.x, y, c.z, 1.45 + grow, 1.25 + grow, 0.55, 0.55)
    ys = [y0, 15.4, 16.9, 17.7, y1]
    keys = ["house", "funnel", "house", "black"]
    loft([ring(y) for y in ys], lambda i, j, c: keys[i], cap_key="black")
    for x in (-0.45, 0.45):
        c = V(x, y1, zc - (y1 - y0) * rake)
        cyl(c - V(0, 0.2, 0), c + V(0, 0.75, -0.08), 0.26, 0.26, 8, "black")
    # The whistle and a ladder up its after side.
    cyl(V(0, 16.5, zc + 1.25 - 0.4), V(0, 16.5, zc + 1.55), 0.08, 0.18, 6, "steel")


def lifeboat():
    """The free-fall lifeboat on its ramp off the aft end of the house, bow down over
    the stern; the rescue boat in its davit on the port quarter."""
    hi, lo = V(0, 7.9, -27.4), V(0, 5.0, -32.5)
    d = (lo - hi).normalized()
    side = V(1, 0, 0)
    up = side.cross(d).normalized()
    if up.y < 0: up = -up
    # Ramp: two rails, cross members, legs to the poop deck, brackets to the house.
    for sx in (1, -1):
        beam_between(hi + side * sx * 0.6, lo + side * sx * 0.6, 0.14, 0.3, "steel")
    for t in (0.1, 0.5, 0.9):
        p = lerp(hi, lo, t)
        beam_between(p - side * 0.7, p + side * 0.7, 0.14, 0.14, "steel")
    for t in (0.55, 0.92):
        p = lerp(hi, lo, t)
        for sx in (1, -1):
            beam_between(p + side * sx * 0.6, V(sx * 0.6, DECK, p.z), 0.12, 0.12, "steel")
    # The boat: a blunt stern up the ramp, the bow down aft, canopy all over.
    L = 5.6
    st = hi + up * 0.3 + d * 0.1
    rings = []
    for t, w, hb, ht in ((0.0, 0.7, 0.45, 0.95), (0.04, 0.95, 0.65, 1.2), (0.25, 1.05, 0.75, 1.35), (0.55, 1.0, 0.75, 1.35),
                         (0.8, 0.8, 0.62, 1.15), (0.94, 0.45, 0.42, 0.85), (1.0, 0.12, 0.2, 0.5)):
        c = st + d * (L * t)
        ring = []
        for i in range(12):
            a = math.tau * i / 12
            ca, sa = math.cos(a), math.sin(a)
            ring.append(c + side * (w * ca) + up * ((ht if sa > 0 else hb) * sa + 0.4))
        rings.append(ring)

    def col(i, j, c):
        a = math.tau * (j + 0.5) / 12
        if 0.15 < math.sin(a) < 0.55 and 1 <= i <= 4: return "black"     # window band
        return "orange"
    loft(rings, col, cap_key="orange")
    # Rescue boat on the port quarter, in its davit.
    rb = V(3.4, DECK + 0.9, -29.6)
    box(rb, (1.6, 0.6, 4.0), "orange")
    box(rb + V(0, 0.42, -0.3), (0.9, 0.4, 1.0), "white")
    box(rb + V(0, -0.4, 0), (1.2, 0.3, 3.4), "dark")
    dv = V(4.6, DECK, -29.6)
    cyl(dv, dv + V(0, 2.2, 0), 0.2, 0.16, 8, "white")
    beam_between(dv + V(0, 2.1, 0), dv + V(-1.3, 3.0, 0), 0.18, 0.22, "white")
    cyl(dv + V(-1.25, 2.95, 0), rb + V(0, 0.65, 0), 0.02, 0.02, 3, "black")
    # Liferafts in their cradles on the house's forward corners, a deck up.
    for sx in (1, -1):
        for z in (-20.6, -21.6):
            c = V(sx * (HOUSE_HW + 0.4), LEVELS[1] + 0.4, z)
            box(c - V(0, 0.32, 0), (0.6, 0.06, 0.8), "steel")
            cyl(c - V(0, 0, 0.42), c + V(0, 0, 0.42), 0.3, 0.3, 8, "white")


def poop():
    """The mooring deck aft: bulwark round the stern, winches, bollards, the stern light."""
    zs = [-27.0, -28.0, -30.0, -31.4]
    path = [deck_edge(z, 0.0, 1) for z in zs] + [V(x, DECK, -31.98) for x in (5.0, 2.5, 0.0, -2.5, -5.0)] + \
           [deck_edge(z, 0.0, -1) for z in reversed(zs)]
    path[4] = V(hull_x(-32.0, DECK) - 0.02, DECK, -31.98)
    path[8] = V(-hull_x(-32.0, DECK) + 0.02, DECK, -31.98)
    bulwark(path, 1.1, V(0, 0, -28.0))
    for sx in (1, -1):
        w = V(sx * 2.2, DECK, -30.0)
        box(w + V(0, 0.35, 0), (1.4, 0.7, 0.9), "dark")
        cyl(w + V(-0.6, 0.55, 0), w + V(0.6, 0.55, 0), 0.32, 0.32, 8, "black")
        for z in (-28.2, -31.2):
            bp = V(sx * 3.9, DECK, z)
            for dz in (-0.25, 0.25):
                cyl(bp + V(0, 0, dz), bp + V(0, 0.5, dz), 0.14, 0.14, 6, "black")
    # Stern light on the bulwark's centre, facing aft.
    box(STERN_LIGHT + V(0, 0, 0.06), (0.22, 0.26, 0.12), "lamp")
    box(STERN_LIGHT - V(0, 0, 0.01), (0.14, 0.14, 0.03), "lens")
    rail([deck_edge(-26.9, 0.1, 1), deck_edge(-20.1, 0.1, 1)], 1.0, "steel")
    rail([deck_edge(-26.9, 0.1, -1), deck_edge(-20.1, 0.1, -1)], 1.0, "steel")


# --- Lettering --------------------------------------------------------------------

def text_bm(body, cap, bold=0.0, res=2):
    """`body` set in the built-in font as a flat bmesh in (u, v), cap height `cap`,
    centred on u = 0 with its baseline at v = 0."""
    cu = bpy.data.curves.new("_txt", "FONT")
    cu.body = body; cu.resolution_u = res; cu.offset = bold; cu.align_x = "CENTER"
    ob = bpy.data.objects.new("_txt", cu); bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    ob.evaluated_get(dg).to_mesh_clear()
    bpy.data.objects.remove(ob); bpy.data.curves.remove(cu)
    k = cap / 0.69
    for v in bm.verts: v.co *= k; v.co.z = 0.0
    return bm


def text_width(bm):
    xs = [v.co.x for v in bm.verts]
    return max(xs) - min(xs) if xs else 0.0


def paint(bm, key, at, breaks=()):
    """Faces of the flat bmesh `bm` (u, v) mapped by `at(u, v)` (u along the surface,
    which is planar between the `breaks` in u), split at the breaks so each piece lies
    flat on its facet; wound to face `at`'s normal (third value)."""
    for u in breaks:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(u, 0, 0), plane_no=(1, 0, 0))
    for f in bm.faces:
        pts, ns = [], Vector()
        for v in f.verts:
            p, n = at(v.co.x, v.co.y)
            pts.append(p); ns += n
        face(oriented(pts, ns), key)
    bm.free()


# --- Containers -------------------------------------------------------------------

CW, CH = 2.44, 2.59                     # width and height (m); lengths 6.06 and 12.19
LINES = [
    # id, name painted on the sides, box colour, lettering, owner code
    ("kestrel", "KESTREL", (0.13, 0.43, 0.45), (0.95, 0.96, 0.95), "KSTU"),
    ("brant", "BRANT", (0.6, 0.2, 0.15), (0.95, 0.96, 0.95), "BRNU"),
    ("tideway", "TIDEWAY", (0.87, 0.5, 0.16), (0.1, 0.15, 0.3), "TDWU"),
    ("norvik", "NORVIK", (0.14, 0.25, 0.5), (0.95, 0.96, 0.95), "NRVU"),
    ("halcyon", "HALCYON", (0.46, 0.21, 0.4), (0.95, 0.96, 0.95), "HLCU"),
    ("alder", "ALDER", (0.2, 0.41, 0.27), (0.95, 0.96, 0.95), "ALDU"),
    ("skua", "SKUA", (0.86, 0.71, 0.2), (0.1, 0.1, 0.1), "SKAU"),
    ("zephyr", "ZEPHYR", (0.57, 0.59, 0.61), (0.13, 0.27, 0.52), "ZPRU"),
    # Leasing boxes: no line's name, only the lessor's code.
    ("grey", "", (0.48, 0.49, 0.48), (0.95, 0.96, 0.95), "CRNU"),
    ("beige", "", (0.72, 0.65, 0.52), (0.2, 0.2, 0.2), "TGHU"),
    ("rust", "", (0.46, 0.27, 0.19), (0.92, 0.92, 0.9), "SEGU"),
]
REEFERS = ["norvik", "kestrel", "alder"]
# Longer names on the forty-footers.
LONG_NAMES = {"alder": "ALDER LINE", "kestrel": "KESTREL", "tideway": "TIDEWAY"}


def corrugation(a, b, pitch, depth):
    """Breakpoints along [a, b] of a trapezoidal corrugation (flat on the face at both
    ends) and the inset at each: list of (s, inset)."""
    n = max(1, round((b - a) / pitch))
    p = (b - a) / n
    out = [(a, 0.0)]
    for i in range(n):
        s = a + i * p
        out += [(s + 0.2 * p, 0.0), (s + 0.35 * p, depth), (s + 0.65 * p, depth), (s + 0.8 * p, 0.0)]
    return out + [(b, 0.0)]


def inset_at(prof, s):
    for (s0, d0), (s1, d1) in zip(prof, prof[1:]):
        if s0 <= s <= s1: return lerp(d0, d1, (s - s0) / (s1 - s0)) if s1 > s0 else d0
    return 0.0


def corrugated(prof, at, key):
    """Strips between successive breakpoints of `prof`: at(s, inset, t) -> point, with
    t 0..1 across the strip."""
    for (s0, d0), (s1, d1) in zip(prof, prof[1:]):
        if s1 - s0 < 1e-4: continue
        q = [at(s0, d0, 0), at(s1, d1, 0), at(s1, d1, 1), at(s0, d0, 1)]
        face(q, key)


def container(tag, length, line, reefer=False):
    """One container's parts: `<tag>_side` (its +X side, with the name; Models turns it
    round for the other), `<tag>_roof`, and `<tag>_body` (ends, doors and frame)."""
    lid, name, body, ink, code = line
    # Reefers are white, lettered in the line's colour.
    if reefer: body, ink = (0.88, 0.89, 0.86), body
    hl, hw = length / 2, CW / 2
    post, rail_h, top_h = 0.12, 0.16, 0.12
    x_face = hw - 0.02
    # Sides: vertical corrugation (ridges run up and down), or the reefer's flat panels.
    zp0, zp1 = -hl + post, hl - post
    prof = corrugation(zp0, zp1, 0.5, 0.055) if not reefer else [(zp0, 0.0), (zp1, 0.0)]
    PART[0] = tag + "_side"
    for sx in (1,):
        def at(s, d, t, sx=sx):
            return V(sx * (x_face - d), lerp(rail_h, CH - top_h, t), s)
        pts_dir = V(sx, 0, 0)
        for (s0, d0), (s1, d1) in zip(prof, prof[1:]):
            if s1 - s0 < 1e-4: continue
            face(oriented([at(s0, d0, 0), at(s1, d1, 0), at(s1, d1, 1), at(s0, d0, 1)], pts_dir), body)
        if reefer:
            for i in range(1, 6):
                y = lerp(rail_h, CH - top_h, i / 6)
                box(V(sx * x_face, y, 0), (0.02, 0.03, length - 2 * post), tuple(c * 0.9 for c in body))
    label = LONG_NAMES.get(lid, name) if length > 10 else name
    if label:
        cap = 1.0 if length > 10 else 0.72
        for sx in (1,):
            bm = text_bm(label, cap, 0.025)
            w = text_width(bm)
            room = zp1 - zp0 - 0.8
            if w > room:
                for v in bm.verts: v.co *= room / w
            vy = CH * 0.5 - cap * 0.45
            for v in bm.verts: v.co.y += vy

            def at(u, v, sx=sx):
                z = -sx * u
                return V(sx * (x_face - inset_at(prof, z) + 0.012), v, z), V(sx, 0, 0)
            paint(bm, ink, at, [-sx * s for s, _ in prof if -sx * s > -w and -sx * s < w])
    PART[0] = tag + "_body"
    # Front end: vertical corrugation across; the reefer's machinery there instead.
    xp0, xp1 = -hw + post, hw - post
    zf = -hl + 0.02
    if reefer:
        face(oriented([V(-hw, 0, zf), V(hw, 0, zf), V(hw, CH, zf), V(-hw, CH, zf)], V(0, 0, -1)), (0.62, 0.64, 0.64))
        box(V(0, 1.55, zf - 0.03), (1.9, 1.2, 0.06), (0.3, 0.31, 0.32))
        for i in range(6):
            box(V(0, 1.1 + i * 0.18, zf - 0.07), (1.8, 0.04, 0.03), (0.5, 0.52, 0.53))
        box(V(0.55, 0.55, zf - 0.04), (0.6, 0.5, 0.08), (0.75, 0.77, 0.77))
    else:
        fprof = corrugation(xp0, xp1, 0.44, 0.05)
        for (s0, d0), (s1, d1) in zip(fprof, fprof[1:]):
            if s1 - s0 < 1e-4: continue
            q = [V(s0, rail_h, zf + d0), V(s1, rail_h, zf + d1), V(s1, CH - top_h, zf + d1), V(s0, CH - top_h, zf + d0)]
            face(oriented(q, V(0, 0, -1)), body)
    # Doors: two leaves, each corrugated across, the lock rods and handles over them.
    zd = hl - 0.02
    dprof = corrugation(xp0, xp1, 0.3, 0.03)
    for (s0, d0), (s1, d1) in zip(dprof, dprof[1:]):
        if s1 - s0 < 1e-4: continue
        q = [V(s0, 0.22, zd - d0), V(s1, 0.22, zd - d1), V(s1, CH - 0.2, zd - d1), V(s0, CH - 0.2, zd - d0)]
        face(oriented(q, V(0, 0, 1)), body)
    dark = tuple(c * 0.55 for c in body)
    box6(V(0, (0.22 + CH - 0.2) / 2, zd + 0.005), (0.03, CH - 0.42, 0.02), dark, skip=("-z",))
    for x in (-0.85, -0.3, 0.3, 0.85):
        box6(V(x, CH / 2, zd + 0.03), (0.04, CH - 0.3, 0.04), (0.5, 0.5, 0.48), skip=("-z",))
        box6(V(x + (0.12 if x > 0 else -0.12), 1.15, zd + 0.06), (0.22, 0.05, 0.04), (0.5, 0.5, 0.48), skip=("-z",))
    # Door header and sill.
    box6(V(0, CH - 0.1, zd), (CW - 2 * post, 0.2, 0.06), body)
    box6(V(0, 0.11, zd), (CW - 2 * post, 0.22, 0.06), body)
    # Roof: a shallow corrugation across, between the top rails.
    PART[0] = tag + "_roof"
    rprof = corrugation(-hl + 0.12, hl - 0.12, 0.62, 0.025)
    for (s0, d0), (s1, d1) in zip(rprof, rprof[1:]):
        if s1 - s0 < 1e-4: continue
        y0, y1 = CH - 0.01 - d0, CH - 0.01 - d1
        face(oriented([V(-hw + 0.1, y0, s0), V(hw - 0.1, y0, s0), V(hw - 0.1, y1, s1), V(-hw + 0.1, y1, s1)], UP), body)
    # Frame: top and bottom side rails, end rails, corner posts, the castings.
    PART[0] = tag + "_body"
    frame_c = tuple(c * 0.85 for c in body)
    for sx in (1, -1):
        box6(V(sx * (hw - 0.06), CH - top_h / 2, 0), (0.12, top_h, length - 2 * post), frame_c, skip=("-y",))
        box6(V(sx * (hw - 0.06), rail_h / 2, 0), (0.12, rail_h, length - 2 * post), frame_c, skip=("-y",))
    for sz in (1, -1):
        box6(V(0, CH - top_h / 2, sz * (hl - 0.06)), (CW - 2 * post, top_h, 0.12), frame_c, skip=("-y",))
        for sx in (1, -1):
            box6(V(sx * (hw - post / 2), CH / 2, sz * (hl - post / 2)), (post, CH - 0.24, post), frame_c,
                 skip=("-y", "+y"))
            for y in (0.06, CH - 0.06):
                box6(V(sx * (hw - 0.09), y, sz * (hl - 0.09)), (0.18, 0.12, 0.18), dark, skip=("-y",) if y < 1 else ())
    # The owner's code and number up on the door.
    serial = "%s %06d" % (code, 100000 + (sum(ord(c) * 7919 ** i for i, c in enumerate(lid)) + int(length * 37)) % 899999)
    bm = text_bm(serial, 0.11, res=1)
    w = text_width(bm)
    for v in bm.verts: v.co.x += 0.55 - 0.0; v.co.y += CH - 0.42

    def at_door(u, v):
        return V(u, v, zd - inset_at(dprof, u) + 0.008), V(0, 0, 1)
    paint(bm, ink if lid not in ("skua", "tideway", "zephyr", "beige") else (0.1, 0.1, 0.1), at_door,
          [s for s, _ in dprof if 0.55 - w / 2 < s < 0.55 + w / 2])


def containers():
    for line in LINES:
        for length, tag in ((6.06, "c20_"), (12.19, "c40_")):
            container(tag + line[0], length, line)
        if line[0] in REEFERS:
            container("c40r_" + line[0], 12.19, line, True)
    PART[0] = None


# --- Glyphs for the hull's lettering ----------------------------------------------

GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
ADVANCE = {}


def glyph_maxx(body):
    cu = bpy.data.curves.new("_g", "FONT"); cu.body = body; cu.resolution_u = 2
    ob = bpy.data.objects.new("_g", cu); bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    mx = max(v.co.x for v in me.vertices)
    ob.evaluated_get(dg).to_mesh_clear()
    bpy.data.objects.remove(ob); bpy.data.curves.remove(cu)
    return mx


def glyphs():
    """Each capital as its own part: pen at the origin, baseline y = 0, cap height 1,
    facing +Z; ADVANCE has each one's advance (and the space's) in the same units."""
    h = glyph_maxx("H")
    for c in GLYPHS + " ":
        ADVANCE[c] = (glyph_maxx(c + "H") - h) / 0.69
    for c in GLYPHS:
        PART[0] = "gl_" + c.lower()
        cu = bpy.data.curves.new("_g", "FONT"); cu.body = c; cu.resolution_u = 3; cu.offset = 0.012
        ob = bpy.data.objects.new("_g", cu); bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = ob.evaluated_get(dg).to_mesh()
        for p in me.polygons:
            face(oriented([V(me.vertices[i].co.x / 0.69, me.vertices[i].co.y / 0.69, 0) for i in p.vertices], V(0, 0, 1)),
                 "white")
        ob.evaluated_get(dg).to_mesh_clear()
        bpy.data.objects.remove(ob); bpy.data.curves.remove(cu)
    PART[0] = None


# --- Build and export -------------------------------------------------------------

NAME_Y = 2.35          # the bow's name: its middle this high, below the main deck
NAME_Z = (8.0, 27.6)


def v3(p): return "Vector3(%g, %g, %g)" % (round(p.x, 3), round(p.y, 3), round(p.z, 3))


def write_data():
    bow = []
    z = NAME_Z[0]
    while z <= NAME_Z[1] + 1e-6:
        p, n = hull_at(z, NAME_Y, 1)
        bow.append("[Vector3(%.3f, %.3f, %.3f), Vector3(%.4f, %.4f, %.4f)]" % (p.x, p.y, p.z, n.x, n.y, n.z))
        z += 0.4
    adv = ", ".join('"%s": %.4f' % (c, a) for c, a in ADVANCE.items())
    src = f'''class_name CargoMidData
extends RefCounted
## Generated by art/cargo_mid.py with assets/models/cargo_mid.glb: don't edit by hand.

## Glyph advances (cap height 1) for the gl_<c> parts.
const ADVANCE := {{{adv}}}
## [point, outward normal] down the port (+X) bow at the name's height, NAME_Y, every
## 0.4 m from z = {NAME_Z[0]} (starboard: mirror x).
const NAME_Y := {NAME_Y}
const BOW := [
	{(",\n\t").join(bow)},
]
## The transom's plane and its half breadth at the deck.
const TRANSOM_Z := -32.0
const TRANSOM_HW := {hull_x(-32.0, DECK):.3f}
## Container slots: hatch middles (each a 40 ft bay, or two 20 ft ones BAY_PITCH apart),
## the rows' x, and the covers' top the bottom tier stands on.
const HATCH_Z := {list(HATCH_Z)}
const BAY_PITCH := {BAY_PITCH}
const COL_X := {list(COL_X)}
const COVER_TOP := {COVER_TOP}
const CONTAINER_H := {CH}
const LINES := {json.dumps([l[0] for l in LINES])}
const REEFERS := {json.dumps(REEFERS)}
## Lights, in the ship's frame.
const FORE_MAST := {v3(FORE_MAST)}
const AFT_MAST := {v3(AFT_MAST)}
const SIDELIGHT := {v3(SIDELIGHT)}
const STERN_LIGHT := {v3(STERN_LIGHT)}
const BRIDGE_Z := Vector2({BRIDGE["z0"]}, {BRIDGE["z1"]})
const BRIDGE_HW := {BRIDGE["hw"]}
const BRIDGE_SILL := {BRIDGE["sill"]}
'''
    path = os.path.normpath(os.path.join(ART, "..", "scripts", "world", "cargo_mid_data.gd"))
    with open(path, "w") as f: f.write(src)


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); bulb(); stern_gear(); anchors(); hull_marks()
    forecastle(); hatches(); deck_rails(); house(); poop()
    containers(); glyphs()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("cargo_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("cargo_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
write_data()
_glb = os.path.normpath(os.path.join(ART, "..", "assets", "models", "cargo_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
