# Builds the mid-poly stern trawler in Blender (run inside Blender, or headless:
# Blender -b --factory-startup --python art/trawler_mid.py) and exports it to
# assets/models/trawler_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# Game frame, like the code-built trawler it replaces (Models.trawler): +Z is the bow,
# +Y up, waterline at y = 0, 20 m long and 6.4 m in the beam (Blender: bow to -Y, Z up).
# A steel displacement hull with a wineglass section, a skeg, the screw in its aperture
# and a barn-door rudder; the sheer flat down the working deck, rising in a raked break
# to the foc'sle and on up to a flared bow. The deckhouse stands on the main deck with
# its front over the foc'sle break; the wheelhouse on top has windows all round (the
# skipper watches the deck astern) under a visored roof, and the mast stands at its
# after end: radar, crosstree floods, the trawling lights (green over white) on forward
# brackets, the cargo boom raked aft over the fish hatch. The working deck has the
# split trawl winch, the fish hatch and totes, the net reel and, over the open stern,
# the gantry with its towing blocks; the trawl doors hang in their gallows on the
# quarters. Tyres along the topsides, freeing ports, buoys, anchors in their pockets.
# Livery parts Models recolours per variant: `hull` (topsides and bulwarks outside),
# `gantry` (the gantry and the door gallows), `net` (the net on the reel), each one flat
# colour; everything else is `fixed`. Glass is split out for the vertex alpha the
# game's shader reads: `glass` (the wheelhouse, lit at night), `window` (the deckhouse's
# windows), `lens` (the stern light's glass).
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.12, 0.2, 0.36), "gantry": (0.92, 0.52, 0.12), "net": (0.2, 0.55, 0.35),
    "antifoul": (0.55, 0.14, 0.12), "boot": (0.92, 0.93, 0.92), "white": (0.92, 0.93, 0.92),
    "house": (0.93, 0.94, 0.92), "deck": (0.42, 0.43, 0.42), "steel": (0.55, 0.57, 0.58),
    "dark": (0.22, 0.23, 0.25), "black": (0.07, 0.07, 0.07), "door": (0.32, 0.2, 0.14),
    "orange": (0.95, 0.42, 0.1), "glass": (0.16, 0.22, 0.27), "window": (0.16, 0.22, 0.27),
    "lamp": (0.12, 0.12, 0.13), "lens": (0.95, 0.95, 0.85), "lens_off": (0.85, 0.85, 0.8),
    "rope": (0.75, 0.66, 0.48), "wire": (0.16, 0.16, 0.17), "tyre": (0.08, 0.08, 0.09),
    "bronze": (0.72, 0.52, 0.26), "tote": (0.22, 0.42, 0.66), "tote2": (0.85, 0.85, 0.82),
    "float": (0.95, 0.55, 0.12), "drum": (0.3, 0.32, 0.34), "rust": (0.42, 0.22, 0.13),
}
ROLES = ("hull", "gantry", "net", "glass", "window", "lens")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


coll = bpy.data.collections.get("Trawler") or bpy.data.collections.new("Trawler")
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
    if normal(q).length < 1e-7: return
    bm = bm_for(key); cl = bm.loops.layers.color["Col"]
    try:
        f = bm.faces.new([bm.verts.new(G(p)) for p in q])
    except ValueError:
        return
    f.smooth = False
    # (A bmesh `color` layer is bytes stored as sRGB and exported linear, so the palette
    # goes in as it is; Models turns the glTF's linear colours back into sRGB.)
    for l in f.loops: l[cl] = (*PAL[key], 1.0)


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


def bar(a, b, w, h, key, up=UP):
    """A rectangular section from a to b, `h` deep in the `up` direction, `w` wide."""
    d = (b - a).normalized()
    side = d.cross(up)
    if side.length < 1e-4: side = d.cross(V(1, 0, 0))
    side.normalize(); u = side.cross(d).normalized()
    def ring(p): return [p + side * sx * w / 2 + u * sy * h / 2 for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    loft([ring(a), ring(b)], key)


def plate(poly, n, t, key):
    """A flat polygon given a thickness `t` along its normal `n`."""
    n = n.normalized()
    loft([[p - n * t / 2 for p in poly], [p + n * t / 2 for p in poly]], key)


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
    for i in range(n1):
        a, b = rings[i], rings[(i + 1) % n1]
        ca = c + (e1 * math.cos(math.tau * (i + 0.5) / n1) + e2 * math.sin(math.tau * (i + 0.5) / n1)) * R
        for k in range(n2):
            q = [a[k], a[(k + 1) % n2], b[(k + 1) % n2], b[k]]
            face(q if normal(q).dot(centre(q) - ca) > 0 else q[::-1], key)


# --- Hull ------------------------------------------------------------------------

DECK = 1.6           # the main (working) deck
FC_DECK = 2.6        # the foc'sle deck
BREAK = 4.6          # the foc'sle break (and the deckhouse front over it)
RAIL = 2.48          # bulwark top down the working deck
STEM = (7.0, -1.75, 10.0, 3.85)   # forefoot (z, y) up to the stem head
Z0 = 1.5             # where the bow starts to fine


def stem_y(z):
    t = min(max((z - STEM[0]) / (STEM[2] - STEM[0]), 0.0), 1.0)
    return STEM[1] + (STEM[3] - STEM[1]) * t ** 1.6


def stem_z(y):
    if y <= STEM[1]: return STEM[0]
    t = min((y - STEM[1]) / (STEM[3] - STEM[1]), 1.0) ** (1 / 1.6)
    return STEM[0] + (STEM[2] - STEM[0]) * t


def keel_y(z):
    """The body's keel line: the stem forward, the run rising aft to the transom's foot."""
    if z >= STEM[0]: return stem_y(z)
    if z >= 5.0: return -1.9 + 0.15 * smooth(5.0, STEM[0], z)
    return -1.9 + 1.6 * smooth(-3.0, -10.0, z)


def sheer(z):
    if z <= 3.9: return RAIL
    if z <= BREAK: return lerp(RAIL, 3.45, smooth(3.9, BREAK, z))
    return 3.45 + 0.4 * ((z - BREAK) / (STEM[2] - BREAK)) ** 1.5


def deck_h(z): return FC_DECK if z > BREAK else DECK
def beam(z): return 3.2 - 0.25 * smooth(-7.5, -10.0, z)


def taper(z, y):
    zs = stem_z(y)
    if z <= Z0: return 1.0
    if z >= zs: return 0.0
    return math.sqrt(max(0.0, 1 - ((z - Z0) / (zs - Z0)) ** 2))


def outer(z):
    """Starboard outside of the hull, keel to sheer, as (x, y): keel, garboard, the
    turn of the bilge (two), waterline, boot top, deck edge, sheer."""
    ky, s, d, B = keel_y(z), sheer(z), deck_h(z), beam(z)
    bw = B - 0.14
    yb = lerp(ky, 0.0, 0.52)

    def top(y): return bw + (B - bw) * (max(y, 0.0) / s) ** 0.8
    raw = [(0.0, ky), (0.42 * bw, ky + 0.28 * (yb - ky)), (0.8 * bw, yb), (0.96 * bw, yb * 0.42),
           (bw, 0.0), (top(0.12), 0.12), (top(d), d), (B, s)]
    out, prev = [], -99.0
    for x, y in raw:
        y = max(y, ky, prev); prev = y
        out.append((x * taper(z, y) if y > ky + 1e-6 else 0.0, y))
    return out


def section(z):
    o = outer(z)
    xs, s, d = o[-1][0], o[-1][1], deck_h(z)
    xi = max(xs - 0.12, 0.0)
    return o + [(xi, s), (xi, min(d, s)), (0.0, min(d, s))]


def hull_x(z, y):
    """Half width of the hull's outside at height y."""
    s = outer(z)
    if y <= s[0][1]: return s[0][0]
    for (x0, y0), (x1, y1) in zip(s, s[1:]):
        if y0 <= y <= y1 and y1 > y0: return lerp(x0, x1, (y - y0) / (y1 - y0))
    return s[-1][0]


STATIONS = [-10.0, -9.9, -9.4, -8.5, -7.5, -6.0, -4.5, -3.0, -1.5, 0.0, 1.5, 2.8, 3.9, 4.25, 4.55, 4.65,
            5.3, 6.0, 6.7, 7.4, 8.0, 8.5, 8.9, 9.25, 9.55, 9.78, 9.92, 10.0]


def hull():
    rings = []
    for z in STATIONS:
        s = section(z)
        rings.append([V(x, y, z) for x, y in s] + [V(-x, y, z) for x, y in reversed(s[1:-1])])

    def col(i, j, c):
        s = j if j <= 9 else 19 - j
        if s <= 3: return "antifoul"
        if s == 4: return "boot"
        if s in (5, 6): return "hull"
        if s == 9 and BREAK - 0.1 < c.z < BREAK + 0.1: return "white"
        return "white" if s in (7, 8) else "deck"
    loft(rings, col, caps=False)
    # The transom up to the deck, and the bulwarks' after ends.
    z = STATIONS[0]
    s = section(z)
    t = [V(x, y, z) for x, y in s[:7]] + [V(-x, y, z) for x, y in reversed(s[1:7])]
    face(t if normal(t).z < 0 else t[::-1], "hull")
    for sx in (1, -1):
        q = [V(sx * x, y, z) for x, y in (s[6], s[7], s[8], s[9])]
        face(q if normal(q).z < 0 else q[::-1], "hull")
    # The transom's bulwark either side of the stern opening, capped white.
    xt = s[9][0]
    for sx in (1, -1):
        box(V(sx * (1.15 + xt) / 2, (DECK + RAIL) / 2, z + 0.07), (xt - 1.15, RAIL - DECK, 0.14), "hull")
        box(V(sx * (1.1 + xt + 0.06) / 2, RAIL + 0.03, z + 0.07), (xt + 0.06 - 1.1, 0.06, 0.2), "white")
    # The rub rail along deck level, a half round, and a white sheer line over it.
    zs = [z for z in STATIONS if z < 9.6]
    for sx in (1, -1):
        y = DECK - 0.04
        path = [V(sx * (hull_x(z, y) + 0.02), y, z) for z in zs if hull_x(z, y) > 0.15]
        tube(path, 0.07, 5, "white")


def under_body():
    """Skeg, the screw in its aperture, the shoe and the rudder."""
    sk = [V(0, keel_y(-1.5) + 0.05, -1.5), V(0, -1.97, -3.2), V(0, -1.97, -8.45), V(0, keel_y(-8.45) + 0.05, -8.45)]
    plate(sk, V(1, 0, 0), 0.22, "antifoul")
    box(V(0, -1.94, -9.1), (0.14, 0.08, 1.3), "antifoul")
    # The rudder: stock up into the counter, the blade with a little balance forward.
    rz0, rz1 = -9.95, -9.25
    rd = [V(0, -1.86, rz0), V(0, -1.86, rz1), V(0, keel_y(rz1) + 0.03, rz1), V(0, keel_y(rz0) + 0.03, rz0)]
    plate(rd, V(1, 0, 0), 0.12, "antifoul")
    # The screw: shaft from the skeg, hub, four blades.
    pc = V(0, -1.2, -8.85)
    cyl(V(0, -1.2, -8.45), pc, 0.09, 0.09, 6, "bronze")
    cyl(pc + V(0, 0, 0.12), pc + V(0, 0, -0.22), 0.16, 0.1, 8, "bronze")
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        r = V(math.cos(a), math.sin(a), 0)
        tng = V(-math.sin(a), math.cos(a), 0)
        root, tip = pc + r * 0.14, pc + r * 0.66
        ch = (tng * 0.22 + V(0, 0, 0.14))
        face([root - ch * 0.6, root + ch * 0.6, tip + ch * 0.35, tip - ch * 0.35], "bronze")
        face([root - ch * 0.6, tip - ch * 0.35, tip + ch * 0.35, root + ch * 0.6], "bronze")


def topside_gear():
    """Tyres slung along the topsides, freeing ports, anchors in their pockets."""
    for sx in (1, -1):
        for z in (-6.5, -3.0, 0.5, 3.6):
            y = 0.95
            x = hull_x(z, y) + 0.12
            torus(V(sx * x, y, z), V(sx, 0, 0), 0.34, 0.12, 10, 4, "tyre")
            cyl(V(sx * x, y + 0.42, z), V(sx * (hull_x(z, RAIL) - 0.02), RAIL + 0.02, z), 0.02, 0.02, 3, "rope")
        # Freeing ports at deck level down the working deck.
        for z in (-8.4, -6.9, -5.4, -3.9, -2.4, -0.9, 0.6, 2.1):
            x = hull_x(z, DECK + 0.15)
            box(V(sx * (x - 0.07), DECK + 0.15, z), (0.2, 0.22, 0.55), "black")
        # Anchor in its pocket on each bow, the hawse pipe above it.
        z, y = 8.55, 2.15
        x = hull_x(z, y)
        n = V(sx * 1.0, 0, 0.35).normalized()
        p = V(sx * x, y, z)
        plate([p + V(0, 0.3, 0.32), p + V(0, 0.3, -0.32), p + V(0, -0.42, -0.24), p + V(0, -0.42, 0.24)],
              n, 0.06, "black")
        a = p + n * 0.08
        bar(a + V(0, 0.25, 0), a + V(0, -0.45, 0), 0.1, 0.09, "black", n)
        plate([a + V(0, -0.38, -0.34), a + V(0, -0.38, 0.34), a + V(0, -0.56, 0.2), a + V(0, -0.56, -0.2)],
              n, 0.12, "black")


# --- Deckhouse and wheelhouse --------------------------------------------------------

HOUSE = dict(z0=-0.6, z1=4.9, hw=2.45, y0=DECK, top=3.6)
WH = dict(z0=0.5, z1=4.9, hw=2.2, y0=3.6, sill=4.25, head=5.15, roof=5.45)
MAST_Z = 0.8
LANTERN_Z = 1.3     # the trawling lights' brackets reach forward to here (Models adds them)


def deckhouse():
    h = HOUSE
    cz, hd = (h["z0"] + h["z1"]) / 2, (h["z1"] - h["z0"]) / 2
    loft([rect(0, h["y0"], cz, h["hw"], hd, 0.35, 0.1), rect(0, h["top"], cz, h["hw"], hd, 0.35, 0.1)], "house")
    # A white coaming lip at the top edge.
    loft([rect(0, h["top"] - 0.02, cz, h["hw"] + 0.04, hd + 0.04, 0.37, 0.12),
          rect(0, h["top"] + 0.06, cz, h["hw"] + 0.04, hd + 0.04, 0.37, 0.12)], "white")
    for sx in (1, -1):
        x = sx * (h["hw"] + 0.012)
        # Galley windows forward of the door, the weathertight door aft.
        for z in (1.6, 2.6, 3.6):
            box(V(x, 2.85, z), (0.03, 0.5, 0.62), "window")
        box(V(sx * (h["hw"] + 0.02), 2.45, 0.2), (0.05, 1.6, 0.78), "door")
        box(V(sx * (h["hw"] + 0.05), 2.4, 0.48), (0.05, 0.05, 0.12), "steel")
        # Handrails along the house sides.
        tube([V(sx * (h["hw"] + 0.08), 2.65, z) for z in (-0.3, 0.75, 4.3)], 0.022, 4, "steel")
        # Front windows over the foc'sle.
        box(V(sx * 1.0, 3.1, h["z1"] + 0.012), (0.7, 0.42, 0.03), "window")
    # The door aft onto the working deck.
    box(V(0.9, 2.45, h["z0"] - 0.02), (0.78, 1.6, 0.05), "door")
    box(V(0.62, 2.4, h["z0"] - 0.06), (0.12, 0.05, 0.05), "steel")
    box(V(0.9, 2.95, h["z0"] - 0.05), (0.32, 0.32, 0.02), "window")
    # Ladder up the after face to the house top, beside it.
    lx = -1.0
    for s in (-0.22, 0.22):
        cyl(V(lx + s, DECK, h["z0"] - 0.12), V(lx + s, h["top"] + 0.9, h["z0"] - 0.12), 0.025, 0.025, 4, "steel")
    for k in range(7):
        y = DECK + 0.3 + k * 0.3
        cyl(V(lx - 0.22, y, h["z0"] - 0.12), V(lx + 0.22, y, h["z0"] - 0.12), 0.018, 0.018, 4, "steel")
    # Rail round the open house top aft of the wheelhouse, a gap at the ladder.
    t = h["top"]
    rail([V(-2.35, t, WH["z0"] + 0.1), V(-2.35, t, -0.5), V(-1.3, t, -0.5)])
    rail([V(-0.7, t, -0.5), V(2.35, t, -0.5), V(2.35, t, WH["z0"] + 0.1)])
    # Liferaft in its cradle, a life ring on the rail, the EPIRB.
    cyl(V(-1.75, t + 0.4, -0.35), V(-1.75, t + 0.4, 0.45), 0.3, 0.3, 10, "white")
    for z in (-0.35, 0.45):
        cyl(V(-1.75, t + 0.4, z), V(-1.75, t + 0.4, z + (0.04 if z < 0 else -0.04)), 0.31, 0.31, 10, "dark")
        box(V(-1.75, t + 0.06, z + (0.1 if z < 0 else -0.1)), (0.5, 0.12, 0.06), "steel")
    torus(V(1.2, t + 0.5, -0.53), V(0, 0, 1), 0.24, 0.06, 10, 4, "orange")
    box(V(2.2, t + 0.25, -0.35), (0.12, 0.3, 0.12), "orange")


def wheelhouse():
    w = WH
    cz, hd, hw = (w["z0"] + w["z1"]) / 2, (w["z1"] - w["z0"]) / 2, w["hw"]
    base = rect(0, w["y0"], cz, hw, hd, 0.55, 0.1)
    sill = rect(0, w["sill"], cz, hw, hd, 0.55, 0.1)
    # Reverse-raked windscreen: the head of the windows pushed forward.
    head = rect(0, w["head"], cz + 0.12, hw + 0.04, hd + 0.12, 0.6, 0.1)
    top = rect(0, w["head"] + 0.06, cz + 0.13, hw + 0.05, hd + 0.13, 0.6, 0.1)
    loft([base, sill, head, top], lambda i, j, c: "glass" if i == 1 else "house", cap_key="house")
    for a, b in zip(sill, head):
        cyl(a, b, 0.04, 0.04, 4, "house")
    # Mullions: three down each long side, two in each of the front and back.
    for t in (0.25, 0.5, 0.75):
        for a0, a1, b0, b1 in ((sill[0], sill[1], head[0], head[1]), (sill[4], sill[5], head[4], head[5])):
            cyl(lerp(a0, a1, t), lerp(b0, b1, t), 0.035, 0.035, 4, "house")
    for t in (0.33, 0.66):
        cyl(lerp(sill[2], sill[3], t), lerp(head[2], head[3], t), 0.035, 0.035, 4, "house")
        cyl(lerp(sill[6], sill[7], t), lerp(head[6], head[7], t), 0.035, 0.035, 4, "house")
    # The roof with its visor out over the windscreen.
    rz = cz + 0.2
    loft([rect(0, w["head"] + 0.06, rz, hw + 0.15, hd + 0.3, 0.7, 0.12),
          rect(0, w["roof"], rz, hw + 0.15, hd + 0.3, 0.7, 0.12)], "house")
    # Door aft to the house top, port side, by the ladder.
    box(V(-1.3, 4.35, w["z0"] - 0.03), (0.7, 1.5, 0.05), "door")
    box(V(-1.3, 4.75, w["z0"] - 0.06), (0.36, 0.4, 0.02), "glass")
    # Wipers on the windscreen.
    for x in (-1.0, 0.0, 1.0):
        p = lerp(lerp(sill[2], sill[3], 0.5), lerp(head[2], head[3], 0.5), 0.1) + V(x, 0, 0.03)
        cyl(p, p + V(0.15, 0.5, 0.06), 0.014, 0.014, 3, "black")


def rail(path, h=0.9, key="steel"):
    """Guard rail: stanchions at each point of `path` (on deck), top and mid rails."""
    tube([p + V(0, h, 0) for p in path], 0.026, 4, key)
    tube([p + V(0, h * 0.5, 0) for p in path], 0.02, 4, key)
    pts = []
    for a, b in zip(path, path[1:]):
        k = max(1, round((b - a).length / 1.0))
        pts += [lerp(a, b, i / k) for i in range(k)]
    for p in pts + [path[-1]]:
        cyl(p, p + V(0, h, 0), 0.022, 0.022, 4, key)


def roof():
    """The wheelhouse roof (its centreline kept clear: gulls perch there): rail, mast,
    radar, floods, the trawling lights' brackets,
    searchlight, horn, domes and aerials, the sidelight boards (Models adds the lamps)."""
    w = WH
    r = w["roof"]
    cz, hd, hw = (w["z0"] + w["z1"]) / 2 + 0.2, (w["z1"] - w["z0"]) / 2 + 0.3, w["hw"] + 0.15
    edge = rect(0, r, cz, hw - 0.05, hd - 0.05, 0.66, 0.1)
    # Rail round the after part of the roof only (the forward part is the visor).
    rail([edge[1] + V(0, 0, -1.6), edge[0], edge[7], edge[6], edge[5], edge[4] + V(0, 0, -1.6)], 0.55)
    # The mast: a tapered pole from the roof's after end, raked struts either side.
    mz = MAST_Z
    cyl(V(0, r, mz), V(0, 10.15, mz), 0.12, 0.07, 8, "white")
    for sx in (1, -1):
        cyl(V(sx * 1.0, r, mz - 0.15), V(0, 7.1, mz), 0.045, 0.04, 5, "white")
    # Radar platform and scanner.
    box(V(0, 6.55, mz + 0.35), (0.9, 0.07, 0.8), "white")
    cyl(V(0, 6.59, mz + 0.45), V(0, 6.78, mz + 0.45), 0.14, 0.11, 8, "lamp")
    box(V(0, 6.84, mz + 0.45), (2.0, 0.1, 0.16), "dark")
    # The crosstree with deck floods facing aft at its ends, a halyard block each side.
    box(V(0, 7.6, mz), (2.6, 0.1, 0.12), "white")
    for sx in (1, -1):
        f = V(sx * 1.15, 7.48, mz - 0.1)
        box(f, (0.26, 0.2, 0.14), "lamp")
        box(f + V(0, 0, -0.08), (0.2, 0.15, 0.02), "lens_off")
    # The trawling lights' brackets: green (9.6) over white (8.6), forward of the pole.
    for y in (8.6, 9.6):
        box(V(0, y - 0.04, (mz + LANTERN_Z) / 2), (0.07, 0.07, LANTERN_Z - mz + 0.15), "white")
        cyl(V(0, y - 0.08, LANTERN_Z), V(0, y, LANTERN_Z), 0.1, 0.1, 6, "white")
    # Whip aerial at the truck.
    cyl(V(0, 10.15, mz), V(0, 11.4, mz), 0.025, 0.01, 3, "lamp")
    # Floods on the roof's after edge, over the working deck.
    for sx in (1, -1):
        f = V(sx * 0.7, r + 0.2, w["z0"] - 0.05)
        cyl(V(f.x, r, f.z + 0.15), V(f.x, f.y, f.z + 0.15), 0.03, 0.03, 4, "steel")
        box(f, (0.3, 0.22, 0.16), "lamp")
        box(f + V(0, 0, -0.09), (0.24, 0.16, 0.02), "lens_off")
    # Searchlight, horn, domes, whips.
    sp = V(-1.25, r, 4.2)
    cyl(sp, sp + V(0, 0.22, 0), 0.04, 0.04, 4, "dark")
    cyl(sp + V(0, 0.33, -0.12), sp + V(0, 0.33, 0.14), 0.12, 0.14, 8, "lamp")
    box(sp + V(0, 0.33, 0.15), (0.2, 0.2, 0.02), "lens_off")
    cyl(V(1.2, r + 0.12, 4.0), V(1.2, r + 0.12, 4.45), 0.03, 0.11, 6, "steel")
    rd = V(1.1, r, 1.6)
    cyl(rd, rd + V(0, 0.15, 0), 0.08, 0.08, 6, "white")
    cyl(rd + V(0, 0.15, 0), rd + V(0, 0.4, 0), 0.32, 0.32, 10, "white")
    cyl(rd + V(0, 0.4, 0), rd + V(0, 0.5, 0), 0.32, 0.17, 10, "white")
    for x in (-0.9, -0.5):
        g = V(x, r, 1.4)
        cyl(g, g + V(0, 0.2, 0), 0.02, 0.02, 3, "steel")
        cyl(g + V(0, 0.2, 0), g + V(0, 0.3, 0), 0.07, 0.04, 6, "white")
    for sx in (1, -1):
        cyl(V(sx * 2.1, r, w["z0"] + 0.15), V(sx * 2.2, r + 2.2, w["z0"] + 0.1), 0.02, 0.008, 3, "lamp")


def stack():
    """The exhaust: a casing on the house top, the pipe up past the wheelhouse roof."""
    x, z, t = 1.45, -0.05, HOUSE["top"]
    box(V(x, t + 0.35, z), (0.66, 0.7, 0.8), "white")
    cyl(V(x, t + 0.7, z), V(x, 7.0, z), 0.2, 0.2, 8, "white")
    cyl(V(x, 7.0, z), V(x, 7.3, z), 0.2, 0.2, 8, "black")
    cyl(V(x, 7.3, z), V(x, 7.38, z - 0.12), 0.2, 0.2, 8, "black")
    # Stays to the wheelhouse.
    cyl(V(x, 6.2, z), V(x - 0.15, WH["roof"], WH["z0"] + 0.1), 0.02, 0.02, 3, "steel")


def boom():
    """The cargo boom off the mast, raked aft over the fish hatch, the topping lift,
    the runner and its hook."""
    g = V(0, 5.95, MAST_Z - 0.12)
    tip = V(0, 7.15, -4.1)
    cyl(g, tip, 0.1, 0.065, 6, "white")
    box(g + V(0, 0, 0.06), (0.22, 0.22, 0.18), "dark")
    cyl(V(0, 9.15, MAST_Z - 0.06), tip + V(0, 0.05, 0), 0.016, 0.016, 3, "wire")
    box(tip + V(0, -0.2, 0), (0.12, 0.28, 0.16), "dark")
    hk = tip + V(0, -1.6, 0)
    cyl(tip + V(0, -0.34, 0), hk, 0.014, 0.014, 3, "wire")
    box(hk + V(0, -0.1, 0), (0.1, 0.2, 0.06), "orange")


# --- Working deck ---------------------------------------------------------------------

GANTRY_Z = -9.3
GANTRY_TOP = 6.6
GANTRY_X = 2.7
WARP_X = 1.4        # the towing blocks: warps leave at y 5.9 (Models.trawler_warps)


def winch():
    """The split trawl winch abaft the house: two drums of warp either side of the
    gearbox, brake bands, the hydraulic motor, all on a bedplate."""
    z, y = -1.55, DECK + 0.72
    box(V(0, DECK + 0.08, z), (3.7, 0.16, 1.1), "dark")
    for sx in (1, -1):
        c = V(sx * 1.05, y, z)
        a, b = c + V(-0.55, 0, 0), c + V(0.55, 0, 0)
        cyl(a, b, 0.42, 0.42, 10, "wire")
        for e in (a, b):
            cyl(e + V(-0.04, 0, 0), e + V(0.04, 0, 0), 0.62, 0.62, 10, "drum")
        # Standards either end of the drum.
        for e in (a + V(-0.12, 0, 0), b + V(0.12, 0, 0)):
            box(V(e.x, (DECK + 0.16 + y) / 2, z), (0.14, y - DECK - 0.16, 0.5), "drum")
        box(c + V(sx * 0.0, 0.45, -0.25), (1.0, 0.06, 0.06), "black")
        # The warp leads aft from the top of the drum to the gantry's towing block.
        tube([c + V(0, 0.42, -0.1), V(sx * WARP_X, GANTRY_TOP - 0.5, GANTRY_Z + 0.12)], 0.025, 3, "wire")
    box(V(0, y, z), (0.7, 0.9, 0.8), "dark")
    cyl(V(0, y, z - 0.4), V(0, y, z - 0.75), 0.18, 0.18, 8, "gantry")
    # Control stand by the house door.
    box(V(1.95, DECK + 0.55, -0.95), (0.3, 1.1, 0.3), "dark")
    box(V(1.95, DECK + 1.15, -0.95), (0.4, 0.1, 0.35), "dark")


def hatch():
    """The fish hatch amidships with its coaming and lid, totes stacked by it."""
    z = -3.7
    box(V(0, DECK + 0.2, z), (1.5, 0.4, 1.5), "steel")
    box(V(0, DECK + 0.44, z), (1.3, 0.08, 1.3), "steel")
    for dz in (-0.35, 0.35):
        box(V(0.69, DECK + 0.44, z + dz), (0.08, 0.06, 0.16), "dark")
    # Stacked fish totes.
    for (x, zz, n, k) in ((-1.95, -3.3, 3, "tote"), (-1.95, -4.35, 2, "tote2"), (1.9, -4.6, 2, "tote")):
        for i in range(n):
            box(V(x, DECK + 0.21 + i * 0.4, zz), (0.85, 0.36, 0.95), k)
            box(V(x, DECK + 0.4 + i * 0.4, zz), (0.9, 0.04, 1.0), k)
    # A deck hose coiled by the bulwark.
    torus(V(2.6, DECK + 0.06, -5.6), V(0, 1, 0), 0.32, 0.04, 10, 3, "orange")


def net_reel():
    """The net reel: the net wound on (a band of floats near the head rope), the
    flanges, pedestals and the hydraulic drive."""
    z, y = -7.05, DECK + 1.3
    a, b = V(-1.75, y, z), V(1.75, y, z)
    # The net, a little lumpy: alternate rings swell.
    rings = []
    for i in range(7):
        x = lerp(-1.72, 1.72, i / 6)
        r = 0.88 + (0.06 if i % 2 else 0.0)
        rings.append(circle(V(x, y, z), V(1, 0, 0), r, 12, 0.13))
    loft(rings, "net")
    for x in (-0.95, 0.35):
        loft([circle(V(x, y, z), V(1, 0, 0), 0.97, 12, 0.13), circle(V(x + 0.16, y, z), V(1, 0, 0), 0.97, 12, 0.13)],
             "float")
    for e in (a, b):
        cyl(e + V(-0.05, 0, 0), e + V(0.05, 0, 0), 1.2, 1.2, 14, "drum")
        cyl(e, e + V(e.x * 0.12, 0, 0), 0.2, 0.2, 8, "dark")
        x = e.x * 1.1
        plate([V(x, DECK, z - 0.6), V(x, DECK, z + 0.6), V(x, y + 0.1, z + 0.18), V(x, y + 0.1, z - 0.18)],
              V(1, 0, 0), 0.16, "dark")
    cyl(V(2.0, y, z), V(2.32, y, z), 0.22, 0.22, 8, "gantry")


def gantry():
    """The stern gantry: tapered legs, knee braces, the crossbar with the towing
    blocks, the net block on the centreline, floods; the stern light under the bar."""
    z, t = GANTRY_Z, GANTRY_TOP
    for sx in (1, -1):
        x = sx * GANTRY_X
        loft([rect(x, DECK, z, 0.22, 0.24), rect(x, t, z, 0.16, 0.18)], "gantry")
        box(V(x, DECK + 0.04, z), (0.6, 0.08, 0.62), "dark")
        # Knee braces under the crossbar.
        bar(V(x - sx * 0.1, t - 1.1, z), V(x - sx * 0.95, t - 0.15, z), 0.16, 0.16, "gantry", V(0, 0, 1))
        # Towing block: cheek plates either side of the sheave, hung from a lug.
        bx = sx * WARP_X
        box(V(bx, t - 0.22, z), (0.1, 0.16, 0.12), "dark")
        cyl(V(bx - 0.08, t - 0.55, z), V(bx + 0.08, t - 0.55, z), 0.28, 0.28, 10, "dark")
        cyl(V(bx - 0.11, t - 0.55, z), V(bx - 0.08, t - 0.55, z), 0.22, 0.22, 10, "gantry")
        # Floods on the forward face, looking down on the deck.
        f = V(sx * 2.05, t - 0.05, z + 0.3)
        box(f, (0.32, 0.22, 0.18), "lamp")
        box(f + V(0, -0.04, 0.1), (0.26, 0.15, 0.02), "lens_off")
    loft([rect(0, t - 0.17, z, GANTRY_X + 0.18, 0.2), rect(0, t + 0.17, z, GANTRY_X + 0.18, 0.2)], "gantry")
    # The net block on the centreline.
    box(V(0, t - 0.25, z + 0.05), (0.14, 0.18, 0.14), "dark")
    cyl(V(-0.35, t - 0.75, z + 0.05), V(0.35, t - 0.75, z + 0.05), 0.32, 0.32, 10, "black")
    for sx in (1, -1):
        plate([V(sx * 0.38, t - 0.3, z - 0.1), V(sx * 0.38, t - 0.3, z + 0.2), V(sx * 0.38, t - 1.1, z + 0.3),
               V(sx * 0.38, t - 1.1, z - 0.2)], V(1, 0, 0), 0.05, "dark")
    # The stern light under the bar, facing aft.
    box(V(0, t - 0.32, z - 0.25), (0.18, 0.16, 0.1), "lamp")
    box(V(0, t - 0.32, z - 0.31), (0.12, 0.09, 0.02), "lens")
    # The stern roller across the opening.
    cyl(V(-1.05, DECK + 0.22, -9.9), V(1.05, DECK + 0.22, -9.9), 0.2, 0.2, 10, "steel")
    for sx in (1, -1):
        box(V(sx * 1.1, DECK + 0.25, -9.9), (0.1, 0.5, 0.34), "dark")


def gallows():
    """Door gallows on the quarters, the trawl doors hung in them outside the hull."""
    z = -8.2
    for sx in (1, -1):
        xi = hull_x(z, RAIL) - 0.06
        top = V(sx * xi, 4.0, z)
        loft([rect(sx * xi, RAIL, z, 0.11, 0.13), rect(sx * xi, 4.0, z, 0.11, 0.13)], "gantry")
        arm = V(sx * (xi + 0.85), 4.0, z)
        bar(top + V(-sx * 0.1, 0, 0), arm, 0.22, 0.24, "gantry")
        bar(V(sx * xi, 3.2, z), arm + V(-sx * 0.25, -0.05, 0), 0.12, 0.12, "gantry", V(0, 0, 1))
        cyl(arm + V(0, -0.28, -0.06), arm + V(0, -0.28, 0.06), 0.2, 0.2, 8, "dark")
        # The door: a cambered oval steel plate with a shoe, hung by its chain.
        dx = hull_x(z, 2.0) + 0.38
        c = V(sx * dx, 2.15, z)
        n = V(sx, 0, 0)
        oval = [c + V(0, 0.55 * math.sin(a), 0.95 * math.cos(a)) for a in [math.tau * i / 12 for i in range(12)]]
        plate(oval, n, 0.12, "door")
        box(c + V(0, -0.52, 0), (0.16, 0.08, 1.5), "black")
        box(c + n * 0.1, (0.06, 0.08, 1.4), "black")
        box(c + n * 0.1 + V(0, 0.3, 0), (0.06, 0.06, 1.0), "black")
        cyl(arm + V(0, -0.45, 0), c + V(0, 0.52, 0), 0.03, 0.03, 3, "black")
        box(arm + V(0, -0.5, 0) + (c + V(0, 0.52, 0) - arm - V(0, -0.5, 0)) * 0.5, (0.04, 0.04, 0.04), "black")


def bulwark_gear():
    """Bitts and fairleads on the bulwarks, buoys tied on aft."""
    for sx in (1, -1):
        for z in (-5.0, 2.3):
            x = hull_x(z, DECK) - 0.45
            box(V(sx * x, DECK + 0.04, z), (0.3, 0.08, 0.7), "dark")
            for dz in (-0.2, 0.2):
                cyl(V(sx * x, DECK, z + dz), V(sx * x, DECK + 0.45, z + dz), 0.09, 0.09, 6, "dark")
                cyl(V(sx * x, DECK + 0.45, z + dz), V(sx * x, DECK + 0.5, z + dz), 0.12, 0.12, 6, "dark")
        # Polyform buoys tied on the rail aft of the bitts.
        for z in (-6.0,):
            x = hull_x(z, RAIL) - 0.38
            cyl(V(sx * x, RAIL - 0.55, z), V(sx * x, RAIL + 0.05, z), 0.26, 0.26, 10, "float")
            cyl(V(sx * x, RAIL + 0.05, z), V(sx * x, RAIL + 0.2, z), 0.26, 0.1, 10, "float")


def foredeck():
    """Windlass with its chain to the hawse pipes, the bow fairlead, a hatch, bitts."""
    y = FC_DECK
    z = 8.0
    box(V(0, y + 0.18, z), (0.75, 0.36, 0.5), "dark")
    cyl(V(-0.55, y + 0.25, z), V(0.55, y + 0.25, z), 0.14, 0.14, 8, "black")
    for sx in (1, -1):
        cyl(V(sx * 0.45, y + 0.25, z), V(sx * 0.6, y + 0.25, z), 0.22, 0.22, 8, "black")
        hp = V(sx * (hull_x(8.55, 2.6) - 0.3), y, 8.55)
        cyl(hp, hp + V(0, 0.08, 0), 0.16, 0.16, 8, "dark")
        tube([V(sx * 0.52, y + 0.2, z), hp + V(0, 0.05, 0)], 0.04, 4, "black")
        # Bitts on the foc'sle.
        for dz in (-0.2, 0.2):
            bx = sx * (hull_x(6.2, 3.0) - 0.5)
            cyl(V(bx, y, 6.2 + dz), V(bx, y + 0.4, 6.2 + dz), 0.08, 0.08, 6, "dark")
    # Bow fairlead at the stem head.
    zs = 9.55
    xs = hull_x(zs, sheer(zs)) - 0.1
    box(V(0, sheer(zs) + 0.06, zs), (2 * xs + 0.1, 0.12, 0.3), "dark")
    # Foc'sle hatch.
    box(V(1.2, y + 0.15, 5.6), (0.8, 0.3, 0.8), "steel")
    # A life ring on the foc'sle bulwark.
    zr = 5.4
    torus(V(-(hull_x(zr, 3.0) - 0.16), 3.05, zr), V(1, 0, 0), 0.24, 0.06, 10, 4, "orange")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); under_body(); topside_gear()
    deckhouse(); wheelhouse(); roof(); stack(); boom()
    winch(); hatch(); net_reel(); gantry(); gallows(); bulwark_gear(); foredeck()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("trawler_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("trawler_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


_here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    (os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art")
built = build()
_glb = os.path.normpath(os.path.join(_here, "..", "assets", "models", "trawler_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("trawler_mid:", result, "total", sum(result.values()))
if bpy.app.background and not bpy.data.filepath:
    for o in list(bpy.data.objects):
        if o not in built: bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(_here, "trawler_mid.blend"))
