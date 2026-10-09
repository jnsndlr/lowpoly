# Builds the mid-poly pilot launch in Blender (run inside Blender: exec(open(path).read()))
# and exports it to assets/models/pilot_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# Game frame, like the code-built pilot boat it replaces: +Z is the bow, +Y up, waterline
# at y = 0, about 9 m long and 3 m in the beam (Blender: bow to -Y, Z up).
# A hard-chined deep-V planing hull with spray rails and a raked stem, the big D-section
# fender collar all round the sheer; the deckhouse a little aft of amidships with a band
# of dark glass all round (the windscreen raked out, for glare), PILOT on its sides, a
# railed roof with the mast (radar, the pilot's white-over-red lanterns' brackets),
# radome, searchlight and liferafts; a railed foredeck with boarding gates either side
# abreast of where the ship's ladder hangs; a rescue davit and life rings aft.
# The livery is split into parts so Models can recolour them per variant: `hull` (the
# topsides) and `trim` (the lettering and the sheer stripe), each one flat colour;
# everything else is `fixed`. Glass is split out for the vertex alpha the game's shader
# reads: `glass` (the wheelhouse, lit at night) and `lens` (the stern light's glass).
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.78, 0.13, 0.1), "trim": (0.78, 0.13, 0.1), "house": (0.94, 0.95, 0.94),
    "antifoul": (0.14, 0.15, 0.16), "white": (0.92, 0.93, 0.92), "deck": (0.42, 0.44, 0.44),
    "fender": (0.07, 0.07, 0.08), "glass": (0.16, 0.22, 0.27), "steel": (0.62, 0.64, 0.66),
    "dark": (0.25, 0.26, 0.28), "black": (0.07, 0.07, 0.07), "orange": (0.95, 0.42, 0.1),
    "lamp": (0.12, 0.12, 0.13), "lens": (0.95, 0.95, 0.85), "lens_off": (0.85, 0.85, 0.8),
    "rope": (0.75, 0.66, 0.48),
}
ROLES = ("hull", "trim", "glass", "lens")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


coll = bpy.data.collections.get("Pilot") or bpy.data.collections.new("Pilot")
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

STATIONS = [-4.5, -4.42, -3.8, -2.8, -1.6, -0.4, 0.8, 1.8, 2.6, 3.2, 3.7, 4.05, 4.3, 4.45, 4.53]


def deck_y(z): return 0.95 + 0.3 * smooth(0.5, 4.5, z)
def keel_y(z): return -0.6 + 0.08 * smooth(-2.5, -4.5, z) + 0.95 * smooth(1.2, 4.53, z)
def chine_y(z): return -0.12 + 0.55 * smooth(0.3, 4.4, z)


def beam(z):
    """Half beam at the deck edge: a broad transom, parallel sides, a fine bow."""
    if z > 0.6: return 1.5 * math.sqrt(max(0.0, 1 - ((z - 0.6) / 3.95) ** 2.2))
    return 1.5 - 0.06 * smooth(-3.8, -4.5, z)


def chine_x(z):
    if z > 0.3: return 1.32 * math.sqrt(max(0.0, 1 - ((z - 0.3) / 4.08) ** 2))
    return 1.32 - 0.04 * smooth(-3.8, -4.5, z)


def section(z):
    """Starboard half from the keel to the deck centre, as (x, y) pairs: A keel, B the
    V bottom, C the chine, D its flat (the spray rail), E F the boot top, S the sheer
    stripe, Fy the foot of the fender, H the deck edge, the toe rail, K deck centre."""
    yk, cx, cy = keel_y(z), max(chine_x(z), 0.02), chine_y(z)
    b, d = max(beam(z), cx + 0.08), deck_y(z)
    lx = cx + 0.07
    y0 = max(cy + 0.04, 0.0); y1 = max(cy + 0.08, 0.14)
    yf = max(d - 0.3, y1 + 0.04); ys = max(yf - 0.1, y1 + 0.02)

    def side(y): return lerp(lx, b, ((y - cy) / (d - cy)) ** 0.7)
    return [(0.0, yk), (0.5 * cx, lerp(yk, cy, 0.47)), (cx, cy), (lx, cy + 0.015),
            (side(y0), y0), (side(y1), y1), (side(ys), ys), (side(yf), yf), (b, d),
            (b - 0.02, d + 0.07), (b - 0.07, d + 0.07), (b - 0.07, d), (0.0, d + 0.03)]


def hull_x(z, y):
    """Half width of the hull's outside at height y (keel to deck edge)."""
    s = section(z)[:9]
    if y <= s[0][1]: return s[0][0]
    for (x0, y0), (x1, y1) in zip(s, s[1:]):
        if y0 <= y <= y1 and y1 > y0: return lerp(x0, x1, (y - y0) / (y1 - y0))
    return s[-1][0]


def hull():
    rings = []
    for z in STATIONS:
        s = section(z)
        rings.append([V(x, y, z) for x, y in s] + [V(-x, y, z) for x, y in reversed(s[1:-1])])

    def col(i, j, c):
        s = j if j <= 11 else 23 - j
        if s <= 2: return "antifoul"
        if s == 3: return "antifoul" if c.y < 0.04 else "hull"
        if s == 4: return "white" if c.y < 0.3 else "hull"
        if s == 6: return "trim"
        return "deck" if s == 11 else "hull"
    loft(rings, col, cap_key="hull")


def outline_path(y_of, zs):
    """Points round the deck outline (starboard aft to fore, then port back), at the
    height y_of(z) on the hull."""
    return [V(-hull_x(z, y_of(z)), y_of(z), z) for z in zs] + [V(hull_x(z, y_of(z)), y_of(z), z) for z in reversed(zs)]


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


def fender():
    """The heavy D-section fender collar round the sheer, across the transom too: what
    she lies against the ship's side on."""
    zs = STATIONS[:-2]
    y = lambda z: deck_y(z) - 0.11
    pts = outline_path(y, zs)
    yt = y(STATIONS[0]); xt = hull_x(STATIONS[0], yt)
    pts += [V(lerp(xt, -xt, t), yt, STATIONS[0] - 0.01) for t in (0.2, 0.4, 0.6, 0.8)]
    ns = horiz_normals(pts, True)
    prof = [(-0.04, -0.2), (0.17, -0.18), (0.25, -0.06), (0.25, 0.06), (0.18, 0.15), (-0.04, 0.18)]
    rings = [[p + n * u + UP * v for u, v in prof] for p, n in zip(pts, ns)]
    loft(rings, "fender", closed_ring=False, closed_path=True)


def transom():
    """Exhaust outlets and the two water-jet housings on the transom."""
    z = STATIONS[0] - 0.02
    for s in (1, -1):
        box(V(s * 0.75, 0.3, z), (0.22, 0.14, 0.04), "black")
        box(V(s * 0.5, -0.2, z - 0.1), (0.32, 0.26, 0.22), "dark")


# --- Superstructure -----------------------------------------------------------------

HOUSE = dict(z0=-1.5, z1=1.9, hw=1.1, y0=0.9, sill=1.55, head=2.28, roof=2.46)


def house_rects():
    h = HOUSE; cz, hd, hw = (h["z0"] + h["z1"]) / 2, (h["z1"] - h["z0"]) / 2, h["hw"]
    base = rect(0, h["y0"], cz, hw, hd, 0.5, 0.15)
    sill = rect(0, h["sill"], cz, hw, hd, 0.5, 0.15)
    # Head of the windows: a little wider and pushed forward, the windscreen raked out.
    head = rect(0, h["head"], cz + 0.12, hw + 0.05, hd + 0.12, 0.55, 0.15)
    top = rect(0, h["head"] + 0.06, cz + 0.13, hw + 0.06, hd + 0.13, 0.55, 0.15)
    return base, sill, head, top


def deckhouse():
    h = HOUSE; cz, hd, hw = (h["z0"] + h["z1"]) / 2, (h["z1"] - h["z0"]) / 2, h["hw"]
    base, sill, head, top = house_rects()
    loft([base, sill, head, top], lambda i, j, c: "glass" if i == 1 else "house", cap_key="house")
    for a, b in zip(sill, head):
        cyl(a, b, 0.035, 0.035, 4, "house")
    # Mullions down the long sides and either side of the door.
    for t in (0.33, 0.66):
        for a0, a1, b0, b1 in ((sill[0], sill[1], head[0], head[1]), (sill[4], sill[5], head[4], head[5])):
            cyl(lerp(a0, a1, t), lerp(b0, b1, t), 0.03, 0.03, 4, "house")
    for i in (2, 3):
        cyl(lerp(sill[2], sill[3], 0.5) + V((i - 2.5) * 0.24, 0, 0), lerp(head[2], head[3], 0.5) + V((i - 2.5) * 0.26, 0, 0.0),
            0.03, 0.03, 4, "house")
    # The roof, overhanging a little all round, most at the front.
    rz = cz + 0.17
    loft([rect(0, h["head"] + 0.06, rz, hw + 0.14, hd + 0.22, 0.62, 0.18),
          rect(0, h["roof"], rz, hw + 0.14, hd + 0.22, 0.62, 0.18)], "house")
    # The door aft onto the working deck, a window in it.
    dz = h["z0"] - 0.025
    box(V(0, 1.6, dz), (0.66, 1.3, 0.05), "house")
    box(V(0, 1.92, dz - 0.02), (0.4, 0.42, 0.03), "glass")
    box(V(0.24, 1.55, dz - 0.04), (0.04, 0.12, 0.04), "dark")
    # Wipers on the windscreen.
    for x in (-0.45, 0.45):
        p = lerp(lerp(sill[2], sill[3], 0.5), lerp(head[2], head[3], 0.5), 0.12) + V(x, 0, 0.03)
        cyl(p, p + V(0.12, 0.4, 0.06), 0.012, 0.012, 3, "black")
    lettering()


# Block letters on a 5-row grid: (col0, row0, col1, row1) strokes.
GLYPHS = {
    "P": [(0, 0, 1, 5), (1, 4, 2, 5), (2, 2, 3, 5), (1, 2, 2, 3)],
    "I": [(0, 0, 1, 5)],
    "L": [(0, 0, 1, 5), (1, 0, 3, 1)],
    "O": [(0, 0, 1, 5), (2, 0, 3, 5), (1, 0, 2, 1), (1, 4, 2, 5)],
    "T": [(0, 4, 3, 5), (1, 0, 2, 4)],
}


def lettering(text="PILOT", u=0.074, y0=1.08, zc=0.0):
    """PILOT down both sides of the deckhouse, reading bow to stern to starboard and
    stern to bow to port (left to right from outside either way)."""
    widths = [max(g[2] for g in GLYPHS[c]) for c in text]
    total = (sum(widths) + len(text) - 1) * u
    for sx in (1, -1):
        x = sx * (HOUSE["hw"] + 0.012)
        col = 0
        for c, w in zip(text, widths):
            for c0, r0, c1, r1 in GLYPHS[c]:
                # Columns run toward -sx in z (reading left to right from outside).
                za = sx * total / 2 - sx * (col + c0) * u
                zb = sx * total / 2 - sx * (col + c1) * u
                box(V(x, y0 + (r0 + r1) / 2 * u, zc + (za + zb) / 2), (0.02, (r1 - r0) * u, abs(zb - za)), "trim")
            col += w + 1


MAST = V(0, 3.95, 0.7)     # top of the pole: the pilot's white lantern (Models adds it)
RED = V(0, 3.5, 0.93)      # on a bracket forward: the red one below it


def roof():
    h = HOUSE; cz, hd, hw = (h["z0"] + h["z1"]) / 2, (h["z1"] - h["z0"]) / 2, h["hw"]
    r = h["roof"]
    # Rail round the roof.
    edge = rect(0, r, cz + 0.17, hw + 0.06, hd + 0.12, 0.55, 0.15)
    tube([p + V(0, 0.5, 0) for p in edge] + [edge[0] + V(0, 0.5, 0)], 0.022, 4, "steel")
    for p in edge:
        cyl(p, p + V(0, 0.5, 0), 0.02, 0.02, 4, "steel")
    for a, b in zip(edge, edge[1:] + edge[:1]):
        if (b - a).length > 1.4:
            for t in (0.33, 0.66):
                m = lerp(a, b, t); cyl(m, m + V(0, 0.5, 0), 0.02, 0.02, 4, "steel")
    # The mast, two struts aft; the radar scanner and the red lantern on brackets forward.
    cyl(V(0, r, MAST.z), MAST, 0.065, 0.045, 6, "house")
    for s in (1, -1):
        cyl(V(s * 0.45, r, MAST.z - 0.75), V(0, 3.15, MAST.z), 0.03, 0.03, 4, "house")
    box(V(0, 3.0, MAST.z + 0.2), (0.22, 0.05, 0.5), "house")
    cyl(V(0, 3.02, MAST.z + 0.35), V(0, 3.16, MAST.z + 0.35), 0.1, 0.08, 6, "lamp")
    box(V(0, 3.2, MAST.z + 0.35), (1.25, 0.08, 0.13), "dark")
    box(V(0, RED.y - 0.04, (MAST.z + RED.z) / 2), (0.05, 0.04, RED.z - MAST.z), "house")
    # Radome and GPS domes aft, the liferafts in their cradles at the after end.
    rd = V(0, r, -0.3)
    cyl(rd, rd + V(0, 0.14, 0), 0.08, 0.08, 6, "house")
    cyl(rd + V(0, 0.14, 0), rd + V(0, 0.34, 0), 0.3, 0.3, 10, "white")
    cyl(rd + V(0, 0.34, 0), rd + V(0, 0.44, 0), 0.3, 0.16, 10, "white")
    for s in (1, -1):
        g = V(s * 0.7, r, 0.2)
        cyl(g, g + V(0, 0.2, 0), 0.02, 0.02, 3, "steel")
        cyl(g + V(0, 0.2, 0), g + V(0, 0.28, 0), 0.07, 0.04, 6, "white")
        for z in (-1.35, -0.85):
            box(V(s * 0.55, r + 0.06, z), (0.36, 0.12, 0.08), "steel")
        # Body stops short of the end bands so their caps aren't coplanar (z-fighting).
        cyl(V(s * 0.55, r + 0.28, -1.48), V(s * 0.55, r + 0.28, -0.72), 0.19, 0.19, 8, "white")
        for z in (-1.5, -0.7):
            cyl(V(s * 0.55, r + 0.28, z), V(s * 0.55, r + 0.28, z + (0.04 if z < -1 else -0.04)), 0.2, 0.2, 8, "dark")
        # Whip aerials at the after corners.
        cyl(V(s * 1.0, r, -1.45), V(s * 1.08, r + 1.6, -1.5), 0.016, 0.008, 3, "lamp")
    # Searchlight and horn at the front of the roof.
    sp = V(-0.55, r, 1.75)
    cyl(sp, sp + V(0, 0.2, 0), 0.04, 0.04, 4, "dark")
    cyl(sp + V(0, 0.3, -0.1), sp + V(0, 0.3, 0.12), 0.1, 0.12, 8, "lamp")
    box(sp + V(0, 0.3, 0.13), (0.17, 0.17, 0.02), "lens_off")
    cyl(V(0.5, r + 0.1, 1.6), V(0.5, r + 0.1, 1.95), 0.03, 0.09, 6, "steel")


# --- Deck gear ----------------------------------------------------------------------

def rail(path, h=0.62, key="steel"):
    """Guard rail: stanchions at each point of `path` (on deck), top and mid rails."""
    top = [p + V(0, h, 0) for p in path]
    tube(top, 0.024, 4, key)
    tube([p + V(0, h * 0.5, 0) for p in path], 0.018, 4, key)
    for p in path:
        cyl(p, p + V(0, h, 0), 0.02, 0.02, 4, key)


def on_deck(s, z, inset=0.12):
    x = max(beam(z) - inset, 0.0)
    return V(s * x, deck_y(z) + 0.07 if x > 0.05 else deck_y(z), z)


def bollard(x, z, h=0.28):
    y = deck_y(z)
    box(V(x, y + 0.03, z), (0.2, 0.06, 0.5), "steel")
    for dz in (-0.13, 0.13):
        cyl(V(x, y, z + dz), V(x, y + h, z + dz), 0.065, 0.065, 6, "steel")
        cyl(V(x, y + h, z + dz), V(x, y + h + 0.03, z + dz), 0.09, 0.09, 6, "steel")


GATE = (2.45, 3.35)   # the boarding gates either side, abreast of the ship's ladder (z 2.9)


def fore_deck():
    for s in (1, -1):
        rail([on_deck(s, z) for z in (1.7, 2.1, GATE[0])])
        # Taller posts with grab handles at the gates.
        for z in GATE:
            p = on_deck(s, z)
            cyl(p, p + V(0, 0.95, 0), 0.025, 0.025, 4, "steel")
            tube([p + V(0, 0.62, 0), p + V(-s * 0.04, 0.95, 0), p + V(-s * 0.2, 0.95, 0)], 0.022, 4, "steel")
    fwd = [on_deck(-1, z) for z in (GATE[1], 3.75, 4.1)] + [V(0, deck_y(4.38) + 0.03, 4.38)] + \
          [on_deck(1, z) for z in (4.1, 3.75, GATE[1])]
    rail(fwd, 0.6)
    # Samson post, a pair of bollards, the anchor windlass and a hatch.
    z = 4.0; y = deck_y(z)
    cyl(V(0, y, z), V(0, y + 0.42, z), 0.08, 0.08, 6, "steel")
    box(V(0, y + 0.32, z), (0.36, 0.05, 0.05), "steel")
    for s in (1, -1):
        bollard(s * 0.55, 3.45)
    wy = deck_y(3.55)
    box(V(0, wy + 0.12, 3.55), (0.36, 0.24, 0.32), "dark")
    cyl(V(-0.2, wy + 0.15, 3.55), V(0.2, wy + 0.15, 3.55), 0.1, 0.1, 6, "black")
    box(V(0, deck_y(2.45) + 0.04, 2.45), (0.6, 0.08, 0.55), "steel")


def aft_deck():
    y = deck_y(-3.0)
    path = [on_deck(-1, z) for z in (-1.8, -2.6, -3.4, -4.1)] + [on_deck(-1, -4.38, 0.14)] + \
           [V(x, y + 0.07, -4.38) for x in (-0.6, 0.0, 0.6)] + [on_deck(1, -4.38, 0.14)] + \
           [on_deck(1, z) for z in (-4.1, -3.4, -2.6, -1.8)]
    rail(path, 0.62)
    # The stern light hangs under the top rail on the centreline, facing aft.
    st = V(0, y + 0.5, -4.4)
    box(st, (0.16, 0.13, 0.06), "lamp")
    box(st + V(0, 0, -0.035), (0.1, 0.07, 0.015), "lens")
    # Life rings on the after rail.
    for s in (1, -1):
        torus(V(s * 0.85, y + 0.42, -4.43), V(0, 0, 1), 0.2, 0.05, 10, 4, "orange")
    # Rescue davit on the port quarter: pedestal, boom raked up aft, the fall.
    dv = V(0.85, y, -3.3)
    cyl(dv, dv + V(0, 0.75, 0), 0.12, 0.1, 8, "dark")
    box(dv + V(0, 0.82, 0), (0.24, 0.16, 0.28), "dark")
    tip = dv + V(0.1, 1.65, -1.05)
    cyl(dv + V(0, 0.82, 0.08), tip, 0.06, 0.045, 6, "white")
    cyl(tip, tip + V(0, -0.65, 0), 0.01, 0.01, 3, "black")
    box(tip + V(0, -0.7, 0), (0.06, 0.08, 0.04), "orange")
    # Engine room hatch, bollards on the quarters, a liferaft-style rescue sling box.
    box(V(-0.15, y + 0.06, -2.7), (0.9, 0.12, 0.9), "steel")
    for s in (1, -1):
        bollard(s * 1.0, -4.0)
    box(V(-0.95, y + 0.25, -2.2), (0.35, 0.5, 0.5), "orange")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); fender(); transom()
    deckhouse(); roof()
    fore_deck(); aft_deck()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("pilot_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("pilot_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "pilot_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
