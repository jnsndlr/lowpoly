# Builds the mid-poly rescue boat in Blender (run inside Blender: exec(open(path).read()))
# and exports it to assets/models/rib_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# A Zodiac-style centre-console RIB, the fast rescue boat the ferries carry on their
# davits, meant to be placed as a sub model on each ferry. Game frame: +Z is the bow, +Y
# up, waterline at y = 0 afloat, origin amidships (Blender: bow to -Y, Z up); 5.05 m from
# the tube cones to the bow, 2.14 m in the beam, the outboard reaching 0.45 m further aft.
# An orange GRP deep-V hull under a hypalon tube that sweeps up at the bow and runs past
# the transom in cones; a black rubbing strake round the tube, dark grip pads and white
# reflective tape on its top, a lifeline in D-ring patches down its outside, grab handles
# inside, a painter coiled on the bow patch. Grey non-slip floor; a bow locker, a seat
# ahead of the console, the console (smoked windscreen, stainless hoop, wheel, throttle,
# instruments, a mast with the all-round white light) and a jockey seat; a white
# outboard on the transom.
# Parts: `fixed` (the boat) and `sling` (the four-leg lifting sling to the master link at
# HOOK, shown while she hangs on the davit, hidden afloat or stowed in her cradle).
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "tube": (0.92, 0.3, 0.12), "hull": (0.95, 0.37, 0.13), "deck": (0.4, 0.42, 0.44),
    "pad": (0.2, 0.21, 0.23), "black": (0.06, 0.06, 0.07), "tape": (0.92, 0.93, 0.9),
    "steel": (0.66, 0.68, 0.7), "dark": (0.18, 0.19, 0.2), "screen": (0.22, 0.25, 0.28),
    "motor": (0.84, 0.85, 0.86), "motor_dark": (0.2, 0.21, 0.22), "seat": (0.1, 0.1, 0.11),
    "rope": (0.78, 0.72, 0.6), "red": (0.8, 0.1, 0.08), "green": (0.1, 0.65, 0.2),
    "lens": (0.95, 0.95, 0.88), "gauge": (0.75, 0.77, 0.78),
}
ROLES = ("sling",)
UP = Vector((0, 1, 0))
HOOK = (0.0, 2.65, -0.4)   # the sling's master link, where the davit's hook takes her


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


coll = bpy.data.collections.get("RIB") or bpy.data.collections.new("RIB")
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


def bm_for(key, role=None):
    role = role or (key if key in ROLES else "fixed")
    if role not in BMS:
        bm = bmesh.new(); bm.loops.layers.color.new("Col"); BMS[role] = bm
    return BMS[role]


ROLE = [None]   # set while building the sling, so its faces go to their own part


def face(pts, key):
    """One face in the given winding (callers orient it); colour by palette key."""
    q = [pts[0]]
    for p in pts[1:]:
        if (p - q[-1]).length > 1e-5: q.append(p)
    if len(q) > 2 and (q[0] - q[-1]).length < 1e-5: q.pop()
    if len(q) < 3: return
    bm = bm_for(key, ROLE[0]); cl = bm.loops.layers.color["Col"]
    try:
        f = bm.faces.new([bm.verts.new(G(p)) for p in q])
    except ValueError:
        return
    f.smooth = False
    for l in f.loops: l[cl] = (*PAL[key], 1.0)


def normal(pts):
    n = Vector()
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += a.cross(b)
    return n


def centre(pts): return sum(pts, Vector()) / len(pts)


def oface(pts, key, out):
    """A face wound so its normal points along `out`."""
    face(pts if normal(pts).dot(out) > 0 else pts[::-1], key)


def loft(rings, key, closed_ring=True, closed_path=False, caps=True, cap_key=None):
    """Quads between successive rings (same vertex count, same direction). `key` is a
    palette key or fn(i, j, centroid) -> key. Wound outward from the rings' centres
    (by majority)."""
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
            oface(r, ck, centre(r) - centre(o))


def rect(cx, y, cz, hw, hd, ch=0.0):
    pts = [(cx + hw, cz - hd + ch), (cx + hw, cz + hd - ch), (cx + hw - ch, cz + hd), (cx - hw + ch, cz + hd),
           (cx - hw, cz + hd - ch), (cx - hw, cz - hd + ch), (cx - hw + ch, cz - hd), (cx + hw - ch, cz - hd)]
    return [V(x, y, z) for x, z in pts]


def box(c, size, key, ch=0.0):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    loft([rect(c.x, c.y - hy, c.z, hx, hz, ch), rect(c.x, c.y + hy, c.z, hx, hz, ch)], key)


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
    """A round pipe along a polyline, each quad wound away from the centreline."""
    rings, prev = [], None
    for i, p in enumerate(path):
        t = (path[(i + 1) % len(path)] if closed else path[min(i + 1, len(path) - 1)]) - \
            (path[(i - 1) % len(path)] if closed else path[max(i - 1, 0)])
        t.normalize()
        e1 = (prev - prev.dot(t) * t).normalized() if prev is not None else frame(t)[0]
        prev = e1; e2 = t.cross(e1)
        rings.append([p + (e1 * math.cos(math.tau * k / n) + e2 * math.sin(math.tau * k / n)) * r for k in range(n)])
    m = len(path) if closed else len(path) - 1
    for i in range(m):
        a, b = rings[i], rings[(i + 1) % len(path)]
        c = (path[i] + path[(i + 1) % len(path)]) * 0.5
        for k in range(n):
            q = [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]
            oface(q, key, centre(q) - c)


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
            oface(q, key, centre(q) - ca)


def prism(profile, x0, x1, key):
    """A side-view (z, y) outline extruded across x0..x1; `key` may be fn(edge index)."""
    a = [V(x0, y, z) for z, y in profile]; b = [V(x1, y, z) for z, y in profile]
    c = centre(a + b); n = len(profile)
    for j in range(n):
        k = (j + 1) % n
        q = [a[j], a[k], b[k], b[j]]
        oface(q, key(j) if callable(key) else key, centre(q) - c)
    cap = key(-1) if callable(key) else key
    oface(a, cap, V(-1, 0, 0)); oface(b, cap, V(1, 0, 0))


# --- The tube -------------------------------------------------------------------------

X_T = 0.8        # half width of the tube's centreline down the sides
Z_TR = -2.2      # the transom
Z1, ZB = 0.2, 2.3   # where the sides start to close in, the bow (centreline)
Z_TIP = -2.5     # the after tips of the cones


def tube_r(z): return 0.25 - 0.05 * smooth(-0.5, ZB, z)
def tube_y(z): return 0.4 + 0.3 * smooth(-0.2, ZB, z) ** 1.3


def tube_x(z):
    if z <= Z1: return X_T
    u = min((z - Z1) / (ZB - Z1), 1.0)
    return X_T * math.sqrt(max(0.0, 1 - u * u))


def tube_path():
    """(point, radius, region) along the centreline: starboard cone tip, forward round
    the bow, aft down the port side to its cone tip. Region: cone / side / bow."""
    aft = [(Z_TIP, 0.03), (-2.48, 0.11), (-2.44, 0.17), (-2.38, 0.215), (-2.3, 0.24)]
    sides = [Z_TR + i * 0.15 for i in range(int((Z1 - Z_TR) / 0.15) + 1)]
    pts = [(V(X_T, tube_y(z), z), r, "cone") for z, r in aft]
    pts += [(V(X_T, tube_y(z), z), tube_r(z), "side") for z in sides]
    for i in range(1, 12):
        th = math.pi / 2 * i / 12
        z = Z1 + (ZB - Z1) * math.sin(th)
        pts.append((V(X_T * math.cos(th), tube_y(z), z), tube_r(z), "bow"))
    pts.append((V(0, tube_y(ZB), ZB), tube_r(ZB), "bow"))
    port = [(V(-p.x, p.y, p.z), r, g) for p, r, g in reversed(pts[:-1])]
    return pts + port


def tube_frames(path):
    """At each point: tangent, outward (horizontal, away from the boat), and up."""
    out = []
    for i, (p, r, g) in enumerate(path):
        a = path[max(i - 1, 0)][0]; b = path[min(i + 1, len(path) - 1)][0]
        t = (b - a).normalized()
        e_out = UP.cross(t).normalized()
        out.append((t, e_out, t.cross(e_out).normalized()))
    return out


N_TUBE = 14


def pad_at(z):
    """Grip pads along the sides: 0.6 m on, 0.3 off, the gaps taped white."""
    if z < -2.05 or z > 0.9: return None
    return "pad" if (z + 2.05) % 0.9 < 0.6 else "tape"


def tube_hull():
    path = tube_path(); frames = tube_frames(path)
    rings = []
    for (p, r, g), (t, eo, eu) in zip(path, frames):
        rings.append([p + (eo * math.cos(math.tau * k / N_TUBE) + eu * math.sin(math.tau * k / N_TUBE)) * r
                      for k in range(N_TUBE)])
    for i in range(len(path) - 1):
        a, b = rings[i], rings[i + 1]
        c = (path[i][0] + path[i + 1][0]) * 0.5
        side = path[i][2] == "side" and path[i + 1][2] == "side"
        zc = c.z
        for k in range(N_TUBE):
            q = [a[k], a[(k + 1) % N_TUBE], b[(k + 1) % N_TUBE], b[k]]
            ang = (k + 0.5) / N_TUBE * 360.0     # 0 outboard, 90 up, 180 inboard
            key = "tube"
            if side and 35 < ang < 125:
                pk = pad_at(zc)
                if pk == "pad" or (pk == "tape" and 60 < ang < 105): key = pk
            # The patch round the bow fitting, where the painter lies.
            if path[i][0].z > ZB - 0.32 and 60 < ang < 120: key = "pad"
            oface(q, key, centre(q) - c)
    # Cone tips: close the ends.
    for ring, nxt in ((rings[0], rings[1]), (rings[-1], rings[-2])):
        oface(ring, "tube", centre(ring) - centre(nxt))
    return path, frames


def tube_fittings(path, frames):
    # The rubbing strake round the waist, below the widest point outboard.
    strake = []
    for (p, r, g), (t, eo, eu) in zip(path, frames):
        if g == "cone" and r < 0.2: continue
        strake.append(p + eo * (r * 0.93) - eu * (r * 0.33))
    tube(strake, 0.045, 6, "black")
    # Lifeline: D-ring patches every other point down the sides and round the bow, the
    # line sagging between them.
    anchors = [i for i, (p, r, g) in enumerate(path) if g != "cone" and abs(p.z) < 2.05 and p.z < 1.9]
    anchors = anchors[::3]
    for s in (1, -1):
        side = [i for i in anchors if path[i][0].x * s > 0.05]
        line = []
        for n, i in enumerate(side):
            p, r, g = path[i]; t, eo, eu = frames[i]
            at = p + (eo * math.cos(0.55) + eu * math.sin(0.55)) * (r + 0.012)
            oface([at + t * 0.05 + eu * 0.04, at - t * 0.05 + eu * 0.04, at - t * 0.05 - eu * 0.05, at + t * 0.05 - eu * 0.05],
                  "black", eo + eu)
            if line:
                j = side[n - 1]
                mp, mr, _ = path[(i + j) // 2]; mt, meo, meu = frames[(i + j) // 2]
                line.append(mp + (meo * math.cos(0.12) + meu * math.sin(0.12)) * (mr + 0.03))
            line.append(at + eo * 0.02)
        tube(line, 0.011, 4, "black")
    # Grab handles inside the tube, two a side.
    for s in (1, -1):
        for z in (-1.4, 0.5):
            p = V(s * X_T, tube_y(z), z); r = tube_r(z)
            base = p + V(-s * math.cos(0.9), math.sin(0.9), 0) * r
            tube([base + V(0, 0, -0.1), base + V(-s * 0.03, 0.05, -0.06), base + V(-s * 0.03, 0.05, 0.06),
                  base + V(0, 0, 0.1)], 0.014, 4, "black")
    # Painter coiled on the bow patch, its bow fitting.
    top = V(0, tube_y(ZB - 0.12) + tube_r(ZB - 0.12) * 0.95, ZB - 0.12)
    for k, rr in enumerate((0.1, 0.08, 0.06)):
        torus(top + V(0, 0.015 + 0.02 * k, -0.05), UP, rr, 0.016, 10, 4, "rope")
    box(top + V(0, 0.0, 0.08), (0.08, 0.05, 0.06), "steel")


# --- The hull -------------------------------------------------------------------------

DECK = 0.12
STATIONS = [Z_TR, -1.6, -0.8, -0.2, 0.4, 0.9, 1.3, 1.65, 1.95, 2.12, 2.22]


def keel_y(z):
    """Flat run aft, then a long rocker sweeping up to the stem tucked under the bow tube."""
    u = min(max((z + 0.6) / (2.24 + 0.6), 0.0), 1.0)
    return lerp(-0.33, tube_y(2.24) - 0.12, u ** 2.1)


def section(z):
    """Starboard half from the keel up to the sheer tucked inside the tube: keel, the
    V bottom, chine, its flat (spray rail), side, sheer."""
    xt, yt = tube_x(z), tube_y(z)
    sx, sy = max(xt - 0.1, 0.02), yt - 0.1
    yk = min(keel_y(z), sy - 0.02)
    cx = 0.82 * sx
    cy = min(yk + cx * (0.4 + 0.8 * smooth(0.3, 2.1, z)), sy - 0.05)
    return [(0.0, yk), (0.5 * cx, lerp(yk, cy, 0.48)), (cx, cy), (cx + 0.04, cy + 0.006),
            (lerp(cx + 0.04, sx, 0.55), lerp(cy, sy, 0.45)), (sx, sy)]


def hull_x(z, y):
    s = section(z)
    if y <= s[0][1]: return 0.0
    for (x0, y0), (x1, y1) in zip(s, s[1:]):
        if y0 <= y <= y1 and y1 > y0: return lerp(x0, x1, (y - y0) / (y1 - y0))
    return s[-1][0]


def hull():
    rings = []
    for z in STATIONS:
        s = section(z)
        if z == STATIONS[-1]: s = [(x * 0.08, y) for x, y in s]
        rings.append([V(-x, y, z) for x, y in reversed(s[1:])] + [V(x, y, z) for x, y in s])
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(n - 1):
            q = [a[j], a[j + 1], b[j + 1], b[j]]
            c = centre(q)
            # Outward: away from a line well above the tube.
            oface(q, "hull", c - V(0, tube_y(c.z) + 0.4, c.z))
    # Transom: the section's outline closed across the sheer, then the board up to the
    # engine's mounting height.
    t = rings[0]
    oface(t, "hull", V(0, 0, -1))
    hw = X_T - 0.22
    box(V(0, 0.25, Z_TR + 0.03), (2 * hw, 0.3, 0.06), "hull")
    box(V(0, 0.415, Z_TR + 0.03), (2 * hw + 0.02, 0.03, 0.08), "black")
    # Bow eye on the stem, low, for the trailer winch.
    ze = 2.0
    torus(V(0, keel_y(ze) + 0.08, ze + 0.05), V(1, 0, 0), 0.045, 0.012, 8, 3, "steel")


def deck():
    zs = [Z_TR + 0.02] + [z for z in (-1.8, -1.2, -0.6, 0.0, 0.6, 1.1, 1.45, 1.7, 1.85)]
    zs = [z for z in zs if hull_x(z, DECK) > 0.12]
    edge = [V(hull_x(z, DECK) - 0.01, DECK, z) for z in zs]
    ring = edge + [V(-p.x, p.y, p.z) for p in reversed(edge)]
    oface(ring, "deck", UP)
    # A low kerb up to inside the tube, so there's no slit under it seen from the cockpit.
    for s in (1, -1):
        for a, b in zip(edge, edge[1:]):
            a = V(s * a.x, DECK, a.z); b = V(s * b.x, DECK, b.z)
            oface([a, b, b + UP * (tube_y(b.z) - DECK), a + UP * (tube_y(a.z) - DECK)], "deck", V(-s, 0, 0))
    # Forward bulkhead where the floor stops under the bow.
    f = edge[-1]
    oface([V(f.x, DECK, f.z), V(-f.x, DECK, f.z), V(-f.x, tube_y(f.z), f.z), V(f.x, tube_y(f.z), f.z)], "deck", V(0, 0, -1))
    # Self-bailers at the transom.
    for s in (1, -1):
        box(V(s * 0.35, DECK + 0.005, Z_TR + 0.12), (0.12, 0.01, 0.08), "black")


# --- Fit-out --------------------------------------------------------------------------

def bow_locker():
    """The bow locker filling the vee under the bow tube, its lid a seat, a hatch and
    an anchor cleat. Its sides follow the hull's inside as the bottom rises."""
    rings = []
    for z in (0.78, 1.1, 1.4, 1.7, 1.95):
        yb = max(DECK, keel_y(z) + 0.04); yt = 0.45
        wb = max(hull_x(z, yb) - 0.03, 0.02); wt = min(0.42, max(hull_x(z, yt) - 0.03, 0.04))
        rings.append([V(wb, yb, z), V(wt, yt, z), V(-wt, yt, z), V(-wb, yb, z)])
    loft(rings, lambda i, j, c: "pad" if j == 1 and 0 < i < 3 else "hull", cap_key="hull")
    box(V(0, 0.455, 1.25), (0.3, 0.012, 0.03), "steel")
    cyl(V(0, 0.45, 1.75), V(0, 0.53, 1.75), 0.02, 0.02, 4, "steel")
    box(V(0, 0.54, 1.75), (0.16, 0.025, 0.035), "steel")


CON = dict(z0=-0.5, z1=0.12, hw=0.32)


def console():
    z0, z1, hw = CON["z0"], CON["z1"], CON["hw"]
    # Side profile: upright front, a short top, the dash sloping down toward the helm.
    prof = [(z1, DECK), (z1 - 0.04, 0.84), (z1 - 0.2, 0.98), (z0 + 0.1, 0.92), (z0, 0.76), (z0, DECK)]
    keys = {2: "dark"}   # the dash top
    prism(prof, -hw, hw, lambda j: keys.get(j, "hull"))
    # Seat ahead of the console, its back the console front.
    box(V(0, 0.33, z1 + 0.27), (0.62, 0.42, 0.5), "hull")
    box(V(0, 0.59, z1 + 0.27), (0.6, 0.1, 0.48), "seat", 0.03)
    box(V(0, 0.68, z1 + 0.04), (0.58, 0.26, 0.06), "seat", 0.02)
    # Windscreen: smoked acrylic raked aft, wings either side, both faces.
    sb = [V(hw + 0.02, 0.96, z1 - 0.18), V(-hw - 0.02, 0.96, z1 - 0.18)]
    st = [V(-hw + 0.04, 1.32, z1 - 0.36), V(hw - 0.04, 1.32, z1 - 0.36)]
    for q in ([sb[0], sb[1], st[0], st[1]],):
        face(q, "screen"); face(q[::-1], "screen")
    for s in (1, -1):
        q = [V(s * (hw + 0.02), 0.96, z1 - 0.18), V(s * (hw - 0.04), 1.32, z1 - 0.36),
             V(s * (hw - 0.02), 1.2, z1 - 0.5), V(s * (hw + 0.02), 0.94, z1 - 0.4)]
        face(q, "screen"); face(q[::-1], "screen")
    # The stainless hoop over the screen and grab rails down the console's sides.
    hoop = [V(0.4, 0.62, z0 - 0.02), V(0.42, 1.38, z0 + 0.02), V(0.32, 1.48, z0 + 0.12),
            V(-0.32, 1.48, z0 + 0.12), V(-0.42, 1.38, z0 + 0.02), V(-0.4, 0.62, z0 - 0.02)]
    tube(hoop, 0.018, 5, "steel")
    for s in (1, -1):
        tube([V(s * (hw + 0.07), 0.55, z1 - 0.05), V(s * (hw + 0.07), 0.9, z1 - 0.12),
              V(s * (hw + 0.07), 0.95, z0 + 0.25), V(s * (hw + 0.07), 0.62, z0 - 0.0)], 0.016, 4, "steel")
        for z in (z1 - 0.05, z0 + 0.0):
            cyl(V(s * hw, 0.6, z), V(s * (hw + 0.07), 0.6, z), 0.012, 0.012, 3, "steel")
    # The helm: the wheel on the sloping dash, instruments and a compass, the throttle.
    dash_a, dash_b = V(0, 0.92, z0 + 0.1), V(0, 0.98, z1 - 0.2)
    slope = (V(0, 0.76, z0) - V(0, 0.92, z0 + 0.1))
    nrm = V(0, -slope.z, slope.y).normalized()
    if nrm.z > 0: nrm = -nrm
    wc = V(0, 0.84, z0 + 0.02) + nrm * 0.12
    torus(wc, nrm, 0.17, 0.016, 12, 4, "black")
    cyl(V(0, 0.84, z0 + 0.04), wc, 0.025, 0.025, 6, "black")
    for a in (0, 2.1, 4.2):
        d = (frame(nrm)[0] * math.cos(a) + frame(nrm)[1] * math.sin(a))
        cyl(wc, wc + d * 0.17, 0.01, 0.01, 3, "black")
    top = lerp(dash_a, dash_b, 0.45)
    tn = V(0, (dash_b - dash_a).z, -(dash_b - dash_a).y).normalized()
    if tn.y < 0: tn = -tn
    for x in (-0.15, 0.15):
        cyl(top + V(x, 0, 0), top + V(x, 0, 0) + tn * 0.02, 0.06, 0.06, 8, "black")
        cyl(top + V(x, 0, 0) + tn * 0.02, top + V(x, 0, 0) + tn * 0.025, 0.045, 0.045, 8, "gauge")
    cyl(V(0, 0.97, z1 - 0.12), V(0, 1.03, z1 - 0.12), 0.06, 0.04, 8, "black")
    # Throttle box on the starboard side, its lever raked forward.
    tb = V(hw + 0.06, 0.78, z0 + 0.2)
    box(tb, (0.1, 0.16, 0.2), "black", 0.02)
    tube([tb + V(0.04, 0.02, 0), tb + V(0.06, 0.2, 0.08), tb + V(0.06, 0.24, 0.1)], 0.012, 4, "steel")
    box(tb + V(0.06, 0.26, 0.11), (0.05, 0.04, 0.04), "black")
    # Sidelights on the console front, the mast aft with the all-round white light.
    for s, key in ((1, "green"), (-1, "red")):
        box(V(s * 0.16, 0.86, z1 - 0.025), (0.12, 0.05, 0.03), key)
    mp = V(hw - 0.05, 0.76, z0 - 0.04)
    cyl(mp, mp + V(0, 1.1, 0), 0.02, 0.016, 5, "steel")
    cyl(mp + V(0, 1.1, 0), mp + V(0, 1.17, 0), 0.035, 0.035, 6, "lens")
    cyl(mp + V(0, 1.17, 0), mp + V(0, 1.19, 0), 0.04, 0.03, 6, "black")
    # VHF whip on the other quarter.
    cyl(V(-hw + 0.05, 0.9, z0 + 0.04), V(-hw + 0.08, 2.0, z0 - 0.02), 0.012, 0.006, 3, "seat")


def jockey_seat():
    zc = -1.1
    box(V(0, 0.37, zc), (0.44, 0.5, 0.56), "hull", 0.03)
    box(V(0, 0.67, zc), (0.42, 0.1, 0.54), "seat", 0.04)
    box(V(0, 0.82, zc - 0.25), (0.42, 0.22, 0.08), "seat", 0.03)
    # Grab rail round its front and sides, a fuel filler.
    tube([V(0.25, 0.62, zc - 0.2), V(0.27, 0.78, zc - 0.05), V(0.25, 0.78, zc + 0.27), V(-0.25, 0.78, zc + 0.27),
          V(-0.27, 0.78, zc - 0.05), V(-0.25, 0.62, zc - 0.2)], 0.016, 4, "steel")
    cyl(V(0.12, DECK, zc - 0.36), V(0.12, DECK + 0.01, zc - 0.36), 0.05, 0.05, 6, "steel")
    # Paddles lashed along the starboard floor edge.
    for dx in (0.0, 0.07):
        x = hull_x(-1.5, 0.3) - 0.1 - dx
        cyl(V(x, DECK + 0.03, -1.9), V(x, DECK + 0.03, -0.6), 0.016, 0.016, 4, "dark")
        box(V(x, DECK + 0.03, -1.88), (0.05, 0.015, 0.22), "dark")


def outboard():
    """A 50-90 hp four-stroke on the transom: clamp bracket, cowl, the leg, cavitation
    plate, gearcase, skeg and a three-bladed prop."""
    zt = Z_TR - 0.02
    box(V(0, 0.33, zt - 0.06), (0.24, 0.2, 0.1), "motor_dark")
    zc = zt - 0.33
    rings = []
    for y, hw, hd, ch in ((0.38, 0.16, 0.26, 0.06), (0.5, 0.21, 0.33, 0.09), (0.8, 0.22, 0.35, 0.1),
                          (0.94, 0.18, 0.3, 0.09), (0.99, 0.12, 0.22, 0.06)):
        rings.append(rect(0, y, zc - 0.03 * (y - 0.38), hw, hd, ch))
    loft(rings, lambda i, j, c: "motor_dark" if i == 0 else "motor", cap_key="motor")
    # A dark band and the vent slot round the cowl's top.
    for s in (1, -1):
        box(V(s * 0.221, 0.66, zc), (0.006, 0.05, 0.5), "motor_dark")
    box(V(0, 0.93, zc - 0.2), (0.16, 0.03, 0.06), "motor_dark")
    # Leg, plate, gearcase, skeg, prop.
    box(V(0, 0.08, zc + 0.02), (0.12, 0.6, 0.26), "motor", 0.03)
    box(V(0, -0.24, zc + 0.02), (0.3, 0.025, 0.42), "motor", 0.04)
    cyl(V(0, -0.33, zc + 0.2), V(0, -0.33, zc - 0.18), 0.04, 0.075, 8, "motor")
    cyl(V(0, -0.33, zc - 0.18), V(0, -0.33, zc - 0.26), 0.075, 0.05, 8, "motor")
    box(V(0, -0.29, zc + 0.02), (0.07, 0.1, 0.18), "motor")
    prism([(zc - 0.12, -0.38), (zc + 0.12, -0.38), (zc + 0.08, -0.52)], -0.015, 0.015, "motor")
    hub = V(0, -0.33, zc - 0.3)
    cyl(V(0, -0.33, zc - 0.26), hub, 0.045, 0.04, 6, "dark")
    for k in range(3):
        a = math.tau * k / 3
        d = V(math.cos(a), math.sin(a), 0); e = V(-math.sin(a), math.cos(a), 0)
        blade = [hub + d * 0.035 + e * 0.04 + V(0, 0, 0.02), hub + d * 0.16 + e * 0.05 + V(0, 0, -0.01),
                 hub + d * 0.17 - e * 0.02 + V(0, 0, -0.02), hub + d * 0.035 - e * 0.04 + V(0, 0, -0.03)]
        face(blade, "dark"); face(blade[::-1], "dark")
    # Steering ram and cables to the console, under the floor's edge.
    cyl(V(0.08, 0.36, zt + 0.02), V(0.2, 0.3, zt + 0.3), 0.025, 0.025, 4, "motor_dark")


# --- Lifting sling --------------------------------------------------------------------

EYES = [V(0.28, 0.5, 1.0), V(-0.28, 0.5, 1.0), V(X_T - 0.3, 0.43, Z_TR + 0.03), V(-(X_T - 0.3), 0.43, Z_TR + 0.03)]


def lifting_eyes():
    for e in EYES[:2]:   # on the bow locker's lid
        box(V(e.x, 0.455, e.z), (0.1, 0.012, 0.12), "steel")
        torus(V(e.x, 0.5, e.z), V(1, 0, 0), 0.04, 0.01, 8, 3, "steel")
    for e in EYES[2:]:
        torus(V(e.x, 0.45, e.z), V(1, 0, 0), 0.035, 0.01, 8, 3, "steel")


def sling():
    ROLE[0] = "sling"
    h = V(*HOOK)
    torus(h, V(1, 0, 0), 0.07, 0.014, 10, 4, "steel")
    for e in EYES:
        cyl(e + (h - e).normalized() * 0.03, h + (e - h).normalized() * 0.07, 0.011, 0.011, 4, "dark")
    ROLE[0] = None


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    path, frames = tube_hull(); tube_fittings(path, frames)
    hull(); deck(); bow_locker(); console(); jockey_seat(); outboard()
    lifting_eyes(); sling()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("rib_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("rib_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "rib_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("RIB", result)
