# Builds the mid-poly M/V Hiyu (Washington State Ferries, 1967, the fleet's smallest) in
# Blender (run inside Blender: exec(open(path).read())) and exports it to
# assets/models/hiyu_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# Real scale, in metres. Game frame: double ended, the two ends at +Z and -Z alike, +Y
# up, waterline at y = 0 (Blender: +Z end to -Y, Z up). 53 m over the deck and 19.2 m
# in the beam (WSF gives 162 x 63 ft; the user wanted her a tad longer); 34 cars.
# After the user's photos: a black scow hull, football shaped in plan (the user's
# "Main Deck Shape.svg", stretched to 53 x 19.2 m: short straight sides, a long taper
# to rounded noses), its ends raking up from the bottom, the green
# bulwark down her sides, stopping short of the open aprons at the ends. The cars drive through her:
# a tall tunnel down the centreline between two stair casings, and a lane each side
# under the passenger cabins, which overhang it out to the hull's side on a white
# screen of paired ports (curving up into the cabins' ends). A bridge over the
# tunnel joins the cabins' roofs into one railed upper deck, and the double-ended
# pilothouse stands on it, its green-trimmed roof carrying two masts set diagonally;
# two small black stacks beside it, the rescue boat on its davit, liferaft canisters.
# Glass is split out for the vertex alpha the game's shader reads: `glass` (the
# pilothouse, lit at night) and `window` (the cabins' windows, some lit); the rest is
# `fixed`.
#
# Heights above her car deck: the cabins' undersides 2.75 (the wings' headroom; the
# real board says 7 ft 10 in), the tunnel's 4.65, the upper deck 5.6, the pilothouse
# roof 8.45, the mastheads 14. Her freeboard is raised to meet the game's piers
# (CAR_DECK), as the Guemes' is.
#
# Numbers the game wants (game frame, metres):
#   CAR_DECK 2.5; four lanes at x = LANES (-6.6, -2.0, 2.0, 6.6): the tunnel's two
#   (the tall lanes) in |x| < X_IN 3.6, the casings X_IN to CAS_X 4.9, the wings out to
#   the hull's side, the cabins |z| < Z_C 8.85 and their gussets out to Z_C + GUSSET_L;
#   eight rows 5.95 apart; the nets at NET_Z 23.6. The hull tapers too much for the
#   wings' end rows (|z| ~ 20.8), so those slots stay empty, and the wing lanes arc in
#   with the hull's side to the nose (FerryClass.HIYU_WING_INSET in from it); the
#   bulwark stops at BUL_Z, a metre short of the apron line (the nets), to let them.
#   Masts at (-+MAST_X, MAST_TOP, +-MAST_Z).
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.08, 0.08, 0.09), "antifoul": (0.36, 0.14, 0.11), "rub": (0.05, 0.05, 0.05),
    "green": (0.07, 0.36, 0.25), "white": (0.94, 0.95, 0.94), "deck": (0.42, 0.44, 0.46),
    "apron": (0.35, 0.36, 0.37), "yellow": (0.9, 0.74, 0.12), "red": (0.72, 0.13, 0.11),
    "grey": (0.5, 0.52, 0.54), "roof": (0.42, 0.44, 0.47), "dkwall": (0.24, 0.25, 0.27),
    "glass": (0.16, 0.22, 0.27), "window": (0.13, 0.16, 0.19), "dark": (0.1, 0.1, 0.11),
    "black": (0.07, 0.07, 0.07), "navy": (0.12, 0.16, 0.36), "steel": (0.6, 0.62, 0.64),
    "orange": (0.95, 0.42, 0.1), "stair": (0.33, 0.34, 0.36),
}
ROLES = ("glass", "window")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


coll = bpy.data.collections.get("Hiyu") or bpy.data.collections.new("Hiyu")
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
THIN_PART = [None]  # set while thin() draws: the part its faces go to


def bm_for(key):
    role = THIN_PART[0] or (key if key in ROLES else "fixed")
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


def hface(pts, key, up=True):
    """A horizontal face, wound to face up (or down)."""
    face(pts if (normal(pts).y > 0) == up else pts[::-1], key)


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
    if closed_ring:
        # A closed ring's own winding about the path settles it (a vote by the quads'
        # offsets from the axis can tie on thin plates).
        k = max(range(len(rings)), key=lambda i: normal(rings[i]).length)
        t = centre(rings[k + 1]) - centre(rings[k]) if k + 1 < len(rings) else centre(rings[k]) - centre(rings[k - 1])
        s = normal(rings[k]).dot(t)
    else:
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
    """Horizontal rectangle (optionally chamfered: `ch` the +z corners, `chb` the -z)."""
    chb = ch if chb is None else chb
    pts = [(cx + hw, cz - hd + chb), (cx + hw, cz + hd - ch), (cx + hw - ch, cz + hd), (cx - hw + ch, cz + hd),
           (cx - hw, cz + hd - ch), (cx - hw, cz - hd + chb), (cx - hw + chb, cz - hd), (cx + hw - chb, cz - hd)]
    return [V(x, y, z) for x, z in pts]


def box(c, size, key):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    loft([rect(c.x, c.y - hy, c.z, hx, hz), rect(c.x, c.y + hy, c.z, hx, hz)], key)


def box_between(a, b, w, key):
    """A square-section member from a to b, its sides square to the x axis."""
    ax = (b - a).normalized()
    e1 = V(1, 0, 0); e2 = ax.cross(e1).normalized()
    ring = lambda c: [c + (e1 * sx + e2 * sy) * (w / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    loft([ring(a), ring(b)], key)


def frame(ax):
    e1 = ax.cross(V(0.3, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0)).normalized()
    return e1, ax.cross(e1).normalized()


def circle(c, ax, r, n, a0=0.0):
    e1, e2 = frame(ax)
    return [c + (e1 * math.cos(a0 + math.tau * i / n) + e2 * math.sin(a0 + math.tau * i / n)) * r for i in range(n)]


THIN = 0.035  # least pipe radius (m) that casts a clean shadow: ~2 shadow map texels across


def thin(r, key, draw):
    """Draws a pipe of radius `r` by draw(k), its radii scaled by k. One thinner than
    THIN would cast a shadow of broken dashes that crawl as she moves, so it goes to
    the "thin" part (drawn, casting no shadow), and a copy thickened to THIN to
    "thinshadow" (casting its shadow, never drawn)."""
    if r >= THIN or key in ROLES or THIN_PART[0]:
        draw(1.0); return
    for part, k in (("thin", 1.0), ("thinshadow", THIN / r)):
        THIN_PART[0] = part; draw(k)
    THIN_PART[0] = None


def cyl(a, b, r0, r1, n, key, a0=None):
    thin(max(r0, r1), key, lambda k: _cyl(a, b, r0 * k, r1 * k, n, key, a0))


def _cyl(a, b, r0, r1, n, key, a0=None):
    ax = (b - a).normalized()
    a0 = math.pi / n if a0 is None else a0
    loft([circle(a, ax, r0, n, a0), circle(b, ax, r1, n, a0)], key)


def tube(path, r, n, key, closed=False):
    thin(r, key, lambda k: _tube(path, r * k, n, key, closed))


def _tube(path, r, n, key, closed=False):
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


def panel(c, n, w, h, d, key):
    """A flat box standing on a wall: centre `c` on its face, `n` the wall's outward
    (horizontal) normal, `w` along the wall, `h` tall, `d` proud of it."""
    t = V(n.z, 0, -n.x)
    ring = lambda o: [c + n * o + t * (sw * w / 2) + UP * (sh * h / 2) for sw, sh in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    loft([ring(-0.01), ring(d)], key)


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




def rail_loop(pts, h, key, step=2.4, closed=True, posts=True):
    """Guard rail on deck along `pts`: top and mid rails, stanchions about `step` apart."""
    path = []
    segs = list(zip(pts, pts[1:] + pts[:1])) if closed else list(zip(pts, pts[1:]))
    for a, b in segs:
        n = max(1, round((b - a).length / step))
        path += [lerp(a, b, i / n) for i in range(n)]
    path.append(pts[0] if closed else pts[-1])
    tube([p + UP * h for p in path], 0.035, 4, key)
    tube([p + UP * (h * 0.5) for p in path], 0.025, 4, key)
    if posts:
        for p in path[:-1] if closed else path:
            cyl(p, p + UP * h, 0.03, 0.03, 4, key)


def oface(pts, out, key):
    """A face wound so its normal points along `out`."""
    face(pts if normal(pts).dot(out) > 0 else pts[::-1], key)


def slab(x0, x1, y0, y1, z0, z1, key):
    """An axis-aligned box between the given bounds."""
    box(V((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), key)


# --- Dimensions (metres, game frame) ------------------------------------------------

HB = 9.6           # half beam at the deck
HZ = 26.5          # half length at the deck (a tad over her 49.4 m, for the cars)
CAR_DECK = 2.5     # raised to the game's pier height (Layout.DECK_Y 3.15 at MID_SCALE 1.26)
LANES = (-6.6, -2.0, 2.0, 6.6)     # wing, the tunnel's two, wing (the wings arc in with the hull)
NET_Z = 23.6       # the nets across the open ends (built by the game)
BUL_H = 1.1        # the green bulwark
BUL_Z = NET_Z - 1.0  # the bulwark stops a metre short of the apron line
X_IN, CAS_X, Z_C = 3.6, 4.9, 8.85   # tunnel, casings, cabins (a third of her length; out to the screens: cab_x)
SCREEN_T = 0.15
GUSSET_L = 2.4                       # the gussets' run out along the gunwale past the cabins' ends
STAIR_D = 2.0                        # the stair bays open in the casings' ends
CAB_BOT, CAB_TOP = CAR_DECK + 2.75, CAR_DECK + 5.45
UPPER = CAB_TOP + 0.15
BR_Z, BR_BOT = 4.6, CAR_DECK + 4.65  # the bridge over the tunnel
PH_HW, PH_HL = 3.9, 2.5
PH_SILL, PH_HEAD, PH_ROOF = UPPER + 1.35, UPPER + 2.55, UPPER + 2.85
MAST_X, MAST_Z, MAST_TOP = 1.4, 1.2, CAR_DECK + 14.0
STACK_X = PH_HW + 0.9
PORTS = (2.0, 6.0)             # the screen's port pairs and the cabin windows (|z|)
PORT_W, PORT_GAP = 0.8, 0.25
PORT_Y0, PORT_Y1 = CAR_DECK + 1.3, CAR_DECK + 2.2


# --- Plan outline -------------------------------------------------------------------
# The user's "Main Deck Shape.svg" (one quadrant: midships round to the nose), stretched
# to 53 x 19.2 m: straight sides for |z| < STRAIGHT_Z, then a long football
# taper in to a rounded nose.

_SVG_C, _SVG_H = (1270.94, 371.28), (1270.26, 370.28)   # its centre, half length and beam
_SVG = (((1455.77, 1), (1455.77, 1), (1802.34, 1), (2058.95, 79.7)),
        ((2058.95, 79.7), (2249.7, 138.2), (2482.88, 247.58), (2521.13, 306.19)),
        ((2521.13, 306.19), (2547.46, 346.55), (2547.46, 396.03), (2521.13, 436.39)))


def _outline():
    """(z, half width) as fractions of HZ and HB, from midships to the nose."""
    def bez(sg, t):
        u = 1 - t
        return [u ** 3 * sg[0][i] + 3 * u * u * t * sg[1][i] + 3 * u * t * t * sg[2][i] + t ** 3 * sg[3][i] for i in (0, 1)]
    pts = [(_SVG_C[0], 1.0)]
    for k, sg in enumerate(_SVG):
        n = 30 if k == 2 else 80
        pts += [bez(sg, i / n * (0.5 if k == 2 else 1.0)) for i in range(1, n + 1)]
    return [((x - _SVG_C[0]) / _SVG_H[0], (_SVG_C[1] - y) / _SVG_H[1]) for x, y in pts]


OUTLINE = _outline()
STRAIGHT_Z = (_SVG[0][0][0] - _SVG_C[0]) / _SVG_H[0] * HZ


def deck_x(z, hb=HB, hz=HZ):
    f = min(abs(z) / hz, 1.0)
    for (a, wa), (b, wb) in zip(OUTLINE, OUTLINE[1:]):
        if f <= b:
            return hb * min(1.0, (wa + (wb - wa) * (f - a) / max(b - a, 1e-9)))
    return 0.0


def cab_x(z):
    """The cabins' and the screens' outer face: just in from the deck edge."""
    return deck_x(z) - SCREEN_T


def oval(y, hb=HB, hz=HZ, n_end=24, n_side=4):
    """Closed plan ring at height y: up the starboard side, round the +z nose, down
    the port side and round the -z nose (same vertex count for any hb, hz)."""
    oz = STRAIGHT_Z * hz / HZ
    taper = [oz + (hz - oz) * (1 - math.cos(math.pi / 2 * i / n_end)) for i in range(n_end + 1)]
    x = lambda z: deck_x(z, hb, hz)
    pts = [(x(z), z) for z in (lerp(-oz, oz, i / n_side) for i in range(n_side))]
    pts += [(x(z), z) for z in taper]
    pts += [(-x(z), z) for z in list(reversed(taper))[1:]]
    pts += [(-x(z), z) for z in (lerp(oz, -oz, i / n_side) for i in range(1, n_side))]
    pts += [(-x(z), -z) for z in taper]
    pts += [(x(z), -z) for z in list(reversed(taper))[1:-1]]
    return [V(x, y, z) for x, z in pts]


def zs_between(z0, z1, step=0.6, extra=()):
    n = max(1, math.ceil(abs(z1 - z0) / step))
    zs = [lerp(z0, z1, i / n) for i in range(n + 1)]
    lo, hi = min(z0, z1), max(z0, z1)
    zs += [e for e in extra if lo + 0.05 < e < hi - 0.05]
    return sorted(set(round(z, 4) for z in zs), reverse=z1 < z0)


def side_strip(s, z0, z1, y0, y1, in0, in1, key, step=0.5, extra=()):
    """A strip along the side from z0 to z1, between in0 and in1 in from the deck edge,
    from y0 up to y1."""
    rings = []
    for z in zs_between(z0, z1, step, extra):
        a, b = s * (deck_x(z) - in0), s * (deck_x(z) - in1)
        rings.append([V(a, y0, z), V(a, y1, z), V(b, y1, z), V(b, y0, z)])
    loft(rings, key)


def side_normal(s, z):
    a, b = V(s * deck_x(z - 0.05), 0, z - 0.05), V(s * deck_x(z + 0.05), 0, z + 0.05)
    t = (b - a).normalized()
    n = V(t.z, 0, -t.x)
    return n if n.x * s > 0 else -n


# --- Hull ---------------------------------------------------------------------------

def hull():
    """A scow: flat bottom, the ends raking up long and shallow to the deck, the sides
    flaring out; black, with the green running from just under the deck up the
    bulwarks, and a heavy rubbing strake at the knuckle."""
    rings = [oval(-2.2, HB - 1.5, HZ - 7.0), oval(-1.5, HB - 0.9, HZ - 4.6),
             oval(-0.6, HB - 0.4, HZ - 2.4), oval(0.6, HB - 0.12, HZ - 0.9),
             oval(CAR_DECK - 0.75, HB - 0.02, HZ - 0.1), oval(CAR_DECK - 0.55, HB, HZ),
             oval(CAR_DECK, HB, HZ)]
    loft(rings, lambda i, j, c: "antifoul" if c.y < -0.05 else ("green" if i == 5 else "hull"), cap_key="hull")
    y0, y1 = CAR_DECK - 0.85, CAR_DECK - 0.6
    r = lambda y, o: oval(y, HB - 0.02 + o, HZ - 0.1 + o)
    loft([r(y0, 0), r(y0 + 0.05, 0.16), r(y1, 0.16), r(y1, 0)], "rub", caps=False)


def car_deck():
    """Bare steel at the ends, grey deck paint between the nets, yellow bands across
    the deck at the nets."""
    hface(oval(CAR_DECK), "apron")
    y = CAR_DECK + 0.01
    zs = zs_between(-NET_Z, NET_Z, 0.8, (-STRAIGHT_Z, STRAIGHT_Z))
    hface([V(deck_x(z) - 0.05, y, z) for z in zs] + [V(-deck_x(z) + 0.05, y, z) for z in reversed(zs)], "deck")
    for e in (1, -1):
        z0, z1 = e * NET_Z, e * (NET_Z + 0.35)
        hface([V(deck_x(z0) - 0.05, y, z0), V(deck_x(z1) - 0.05, y, z1),
               V(-deck_x(z1) + 0.05, y, z1), V(-deck_x(z0) + 0.05, y, z0)], "yellow")


# --- Bulwarks -------------------------------------------------------------------------

def bulwarks():
    """The green bulwark down each side, stopping a metre short of the apron line,
    painted dark inside where it walls the wings under the cabins, a yellow kerb at
    its foot there; a pipe rail on it beyond the cabins; her name on the corners."""
    for s in (1, -1):
        zs = zs_between(-BUL_Z, BUL_Z, 0.5, (-Z_C, Z_C, -STRAIGHT_Z, STRAIGHT_Z))
        path = [V(s * (deck_x(z) - 0.02), CAR_DECK, z) for z in zs]
        ns = horiz_normals(path, False)
        rings = []
        for p, n in zip(path, ns):
            q = p - n * SCREEN_T
            rings.append([p, p + UP * BUL_H, q + UP * BUL_H, q])
        loft(rings, lambda i, j, c: "dkwall" if j == 2 and abs(c.z) < Z_C else "green", cap_key="green")
        side_strip(s, -Z_C, Z_C, CAR_DECK, CAR_DECK + 0.14, 0.02 + SCREEN_T, 0.12 + SCREEN_T, "yellow")
        for e in (1, -1):
            top = [p + UP * BUL_H - n * (SCREEN_T / 2) for p, n, z in zip(path, ns, zs) if e * z >= Z_C + GUSSET_L - 0.01]
            rail_loop(top if e > 0 else top[::-1], 0.6, "steel", step=1.4, closed=False)
            # H I Y U on the green near the corner.
            z = e * 20.0
            n = side_normal(s, z)
            c = V(s * deck_x(z), CAR_DECK + 0.62, z) + n * 0.01
            t = V(n.z, 0, -n.x)
            for k in range(4):
                panel(c + t * ((k - 1.5) * 0.42), n, 0.09, 0.5, 0.02, "white")
            panel(c + UP * -0.38, n, 1.3, 0.08, 0.02, "white")


# --- The cabins, casings and screens ---------------------------------------------------

def screen(s):
    """The white screen from the bulwark to the cabin's underside over the wing, the
    cabin's length, with pairs of open ports; past each end a gusset sweeps up from
    the gunwale in a long concave slope to the cabin's lower corner."""
    yb = CAR_DECK + BUL_H
    t0, t1 = SCREEN_T, 2 * SCREEN_T
    edges = [-Z_C]
    for zc in sorted([-z for z in PORTS] + list(PORTS)):
        for d in (-PORT_GAP / 2 - PORT_W, -PORT_GAP / 2, PORT_GAP / 2, PORT_GAP / 2 + PORT_W):
            edges.append(zc + d)
    edges.append(Z_C)
    side_strip(s, -Z_C, Z_C, yb, PORT_Y0, t0, t1, "white", 1.0, edges)
    side_strip(s, -Z_C, Z_C, PORT_Y1, CAB_BOT, t0, t1, "white", 1.0, edges)
    for a, b in zip(edges[0::2], edges[1::2]):
        side_strip(s, a, b, PORT_Y0, PORT_Y1, t0, t1, "white", 1.0)
    for e in (1, -1):
        # Its top: a quarter ellipse from the cabin's lower corner down to the gunwale.
        rings = []
        for i in range(13):
            ang = math.pi / 2 * i / 12
            z = e * (Z_C + GUSSET_L * (1 - math.cos(ang)))
            h = max(CAB_BOT - (CAB_BOT - yb) * math.sin(ang), yb + 0.02)
            o, n = s * (deck_x(z) - t0), s * (deck_x(z) - t1)
            rings.append([V(o, yb, z), V(o, h, z), V(n, h, z), V(n, yb, z)])
        loft(rings, "white")


def stair_bay(s, e):
    """The casing's open end: its two walls, the flight rising into it from the deck
    (yellow nosings), the dark stairwell behind, and the yellow-and-red bumper round
    its foot."""
    zb = e * (Z_C - STAIR_D)
    for x in (X_IN, CAS_X - 0.15):
        slab(s * x, s * (x + 0.15), CAR_DECK, CAB_BOT, zb, e * Z_C, "white")
    panel(V(s * (X_IN + CAS_X) / 2, (CAR_DECK + CAB_BOT) / 2, zb), V(0, 0, e), CAS_X - X_IN - 0.3,
          CAB_BOT - CAR_DECK, 0.01, "dark")
    n = 8
    for i in range(n):
        z0 = e * (Z_C - 0.3 - STAIR_D * 0.8 * i / n)
        z1 = e * (Z_C - 0.3 - STAIR_D * 0.8 * (i + 1) / n)
        h = CAR_DECK + 0.22 * (i + 1)
        slab(s * (X_IN + 0.15), s * (CAS_X - 0.15), CAR_DECK, h, z0, zb, "stair")
        slab(s * (X_IN + 0.15), s * (CAS_X - 0.15), h, h + 0.02, z0, z0 - e * 0.06, "yellow")
    for x in (X_IN + 0.35, CAS_X - 0.35):
        a = V(s * x, CAR_DECK + 0.9, e * (Z_C - 0.3))
        cyl(a, a + V(0, 0.22 * n, -e * STAIR_D * 0.8), 0.03, 0.03, 4, "steel")
    cx, hw = s * (X_IN + CAS_X) / 2, (CAS_X - X_IN) / 2
    loft([rect(cx, CAR_DECK, e * (Z_C + 0.05), hw + 0.15, 0.45, 0.35), rect(cx, CAR_DECK + 0.12, e * (Z_C + 0.05), hw + 0.15, 0.45, 0.35)], "red")
    loft([rect(cx, CAR_DECK + 0.12, e * Z_C, hw + 0.06, 0.32, 0.25), rect(cx, CAR_DECK + 0.2, e * Z_C, hw + 0.06, 0.32, 0.25)], "yellow")


def cab_ring(s, y, g):
    """A cabin's plan at height y, grown g all round: square inboard and at the ends,
    its outboard side following the hull's curve."""
    zs = zs_between(-Z_C - g, Z_C + g, 1.0)
    return ([V(s * (X_IN - g), y, z) for z in (-Z_C - g, Z_C + g)] +
            [V(s * (cab_x(z) + g), y, z) for z in reversed(zs)])


def cabin(s):
    """One cabin block: the cabin over the wing lane out to the side, the stair casing
    under its inboard edge down to the deck, a lip round its foot; windows outboard
    and on the ends, boards on its fascia over the lanes."""
    loft([cab_ring(s, CAB_BOT, 0), cab_ring(s, CAB_TOP, 0)], "white")
    loft([cab_ring(s, CAB_BOT - 0.02, 0.05), cab_ring(s, CAB_BOT + 0.28, 0.05)], "white")
    ccx, chw = s * (X_IN + CAS_X) / 2, (CAS_X - X_IN) / 2
    loft([rect(ccx, CAR_DECK, 0, chw, Z_C - STAIR_D), rect(ccx, CAB_BOT, 0, chw, Z_C - STAIR_D)], "white")
    for x in (X_IN, CAS_X):     # kerbs along the casing's foot, both sides
        o = -1 if x == X_IN else 1
        slab(s * x, s * (x + o * 0.1), CAR_DECK, CAR_DECK + 0.14, -(Z_C - 0.3), Z_C - 0.3, "yellow")
    for e in (1, -1):
        stair_bay(s, e)
    screen(s)

    nin = V(-s, 0, 0)
    for z in sorted([-z for z in PORTS] + list(PORTS)):
        c, n = V(s * cab_x(z), CAB_BOT + 1.5, z), side_normal(s, z)
        panel(c, n, 2.5, 1.3, 0.02, "dkwall")
        panel(c, n, 2.3, 1.12, 0.035, "window")
    for e in (1, -1):
        ne = V(0, 0, e)
        for x in (5.3, 7.6):
            panel(V(s * x, CAB_BOT + 1.5, e * Z_C), ne, 2.0, 1.3, 0.02, "dkwall")
            panel(V(s * x, CAB_BOT + 1.5, e * Z_C), ne, 1.8, 1.12, 0.035, "window")
        # Fascia over the lanes: the hazard board by the tunnel, the clearance board
        # over the wing.
        fz = e * (Z_C + 0.05)
        panel(V(s * (X_IN + 0.9), CAB_BOT + 0.13, fz), ne, 1.4, 0.26, 0.02, "yellow")
        for k in range(4):
            panel(V(s * (X_IN + 0.38 + 0.35 * k), CAB_BOT + 0.13, fz), ne, 0.14, 0.26, 0.03, "black")
        panel(V(s * LANES[-1], CAB_BOT + 0.13, fz), ne, 1.6, 0.24, 0.02, "white")
        panel(V(s * LANES[-1], CAB_BOT + 0.13, fz), ne, 1.2, 0.08, 0.03, "dark")
        # The tunnel side: a door into the casing, a fire hose box.
        panel(V(s * X_IN, CAR_DECK + 1.05, e * (Z_C - STAIR_D - 1.6)), nin, 0.9, 2.05, 0.03, "grey")
        panel(V(s * X_IN, CAR_DECK + 1.4, e * (Z_C - STAIR_D - 3.4)), nin, 0.6, 0.8, 0.08, "red")
    # The no-smoking disc on the tunnel wall at one end (and the other, turned about).
    p = V(s * (X_IN - 0.03), CAB_BOT + 1.4, s * (Z_C - 1.6))
    panel(p + V(0.02 * s, 0, 0), nin, 1.0, 1.0, 0.01, "white")
    torus(p - V(0.01 * s, 0, 0), nin, 0.36, 0.05, 14, 4, "red")
    box_between(p + V(0, 0.24, -0.24), p + V(0, -0.24, 0.24), 0.07, "red")


def bridge_and_upper_deck():
    """The bridge over the tunnel, its name board and hazard board; the upper deck on
    the cabins and the bridge, railed round its H."""
    loft([rect(0, BR_BOT, 0, X_IN + 0.02, BR_Z), rect(0, CAB_TOP, 0, X_IN + 0.02, BR_Z)], "white")
    for e in (1, -1):
        ne = V(0, 0, e)
        panel(V(0, BR_BOT + 0.25, e * BR_Z), ne, 3.6, 0.32, 0.02, "yellow")
        for k in range(8):
            panel(V(-1.57 + k * 0.45, BR_BOT + 0.25, e * BR_Z), ne, 0.16, 0.32, 0.03, "black")
        panel(V(0, BR_BOT + 0.7, e * BR_Z), ne, 1.4, 0.38, 0.02, "orange")
        for k in range(4):
            panel(V(-0.42 + k * 0.28, BR_BOT + 0.7, e * BR_Z), ne, 0.07, 0.24, 0.03, "black")
    for s in (1, -1):
        loft([cab_ring(s, CAB_TOP, 0.08), cab_ring(s, UPPER, 0.08)], "white", cap_key="roof")
    loft([rect(0, CAB_TOP, 0, X_IN, BR_Z + 0.08), rect(0, UPPER, 0, X_IN, BR_Z + 0.08)], "white", cap_key="roof")
    i, z, b = X_IN + 0.06, Z_C - 0.02, BR_Z
    side = [(cab_x(zz) - 0.02, zz) for zz in zs_between(-z, z, 1.5)]
    loop = (side + [(i, z), (i, b), (-i, b), (-i, z)] + [(-x, zz) for x, zz in reversed(side)] +
            [(-i, -z), (-i, -b), (i, -b), (i, -z)])
    rail_loop([V(x, UPPER, zz) for x, zz in loop], 1.0, "white", step=1.5)
    # Life rings on the rails, outboard.
    for s in (1, -1):
        for zz in (-7.0, 7.0):
            n = side_normal(s, zz)
            torus(V(s * cab_x(zz), UPPER + 0.6, zz) + n * 0.08, n, 0.3, 0.07, 10, 4, "orange")


def pilothouse():
    """Double ended: a white base, windows all round (eight across each end), the
    roof's green fascia overhanging; searchlights and horns on the roof."""
    loft([rect(0, UPPER, 0, PH_HW, PH_HL, 0.4), rect(0, PH_SILL, 0, PH_HW, PH_HL, 0.4)], "white")
    lo = rect(0, PH_SILL, 0, PH_HW, PH_HL, 0.4)
    hi = rect(0, PH_HEAD, 0, PH_HW + 0.08, PH_HL + 0.08, 0.45)
    loft([lo, hi], "glass", caps=False)
    for k in range(8):
        a, b = lo[k], hi[k]
        box_between(a, b, 0.12, "white")
        a2, b2 = lo[(k + 1) % 8], hi[(k + 1) % 8]
        n = round((a - a2).length / 1.0)
        for t in range(1, n):
            box_between(lerp(a, a2, t / n), lerp(b, b2, t / n), 0.08, "white")
    loft([rect(0, PH_HEAD, 0, PH_HW + 0.08, PH_HL + 0.08, 0.45),
          rect(0, PH_HEAD + 0.06, 0, PH_HW + 0.08, PH_HL + 0.08, 0.45)], "white")
    loft([rect(0, PH_HEAD + 0.06, 0, PH_HW + 0.35, PH_HL + 0.35, 0.55),
          rect(0, PH_ROOF, 0, PH_HW + 0.35, PH_HL + 0.35, 0.55)], "green", cap_key="white")
    hface(rect(0, PH_ROOF + 0.005, 0, PH_HW + 0.25, PH_HL + 0.25, 0.5), "roof")
    for e in (1, -1):
        for s in (1, -1):
            p = V(s * (PH_HW - 0.4), PH_ROOF, e * (PH_HL - 0.3))
            cyl(p, p + UP * 0.25, 0.05, 0.05, 4, "steel")
            cyl(p + UP * 0.35 + V(0, 0, -e * 0.15), p + UP * 0.35 + V(0, 0, e * 0.2), 0.14, 0.16, 8, "steel")
        # A door from the walkway, each end, off centre.
        panel(V(e * 2.6, UPPER + 1.0, e * PH_HL), V(0, 0, e), 0.8, 2.0, 0.02, "grey")


def masts():
    """Two pole masts on the roof, set diagonally: each with a yard, the masthead
    light, and a radar scanner on a pedestal toward its end; a flag gaff on one."""
    for e in (1, -1):
        mx, mz = -e * MAST_X, e * MAST_Z
        b = V(mx, PH_ROOF, mz)
        box(b + UP * 0.3, (0.5, 0.6, 0.5), "white")
        cyl(b + UP * 0.6, V(mx, MAST_TOP, mz), 0.12, 0.06, 8, "white")
        box(V(mx, MAST_TOP - 2.6, mz), (2.4, 0.09, 0.09), "white")
        for s in (1, -1):
            p = V(mx + s * 1.1, MAST_TOP - 2.55, mz)
            cyl(p, p + UP * 1.1, 0.025, 0.012, 3, "dark")
        box(V(mx, MAST_TOP - 0.45, mz), (0.18, 0.25, 0.18), "white")
        cyl(V(mx, MAST_TOP, mz), V(mx, MAST_TOP + 0.5, mz), 0.025, 0.02, 3, "dark")
        # The radar.
        r = V(e * 1.6, PH_ROOF, e * 1.6)
        cyl(r, r + UP * 0.9, 0.1, 0.1, 6, "white")
        box(r + UP * 0.95, (0.4, 0.12, 0.4), "white")
        box(r + UP * 1.08, (2.4, 0.13, 0.25), "white")
    gt = V(-MAST_X, MAST_TOP - 2.0, MAST_Z + 1.6)
    cyl(V(-MAST_X, MAST_TOP - 3.2, MAST_Z + 0.1), gt, 0.035, 0.025, 4, "white")
    for k, c in enumerate(("red", "white", "red", "white")):
        box(gt + V(0, -0.1 - k * 0.1, 0.38), (0.02, 0.1, 0.72), c)
    box(gt + V(0, -0.2, 0.18), (0.025, 0.2, 0.32), "navy")


# --- The rescue boat --------------------------------------------------------------
# The boat itself is the shared sub model art/rib_mid.py (assets/models/rib_mid.glb),
# which the game places with its origin at RIB_AT (model metres) turned RIB_YAW about
# +Y (FerryClass keeps a copy: keep them in step). Here only her cradle, and the davit
# with its fall hooked onto her sling's master link.
RIB_HOOK = (0.0, 2.65, -0.4)   # rib_mid.py HOOK, in the boat's frame
RIB_LIFT = 0.78                # her origin above the deck, sat in the cradle


def rib_cradle(at, yaw, davit):
    """Two saddles under her (a keel chock and padded posts under the V either side),
    the davit's pedestal at `davit` (x, z on deck) with its winch, the boom curving up
    and over to a sheave above the hook, the fall down to the master link."""
    c, s = math.cos(yaw), math.sin(yaw)
    def P(x, y, z): return at + V(x * c + z * s, y, -x * s + z * c)
    for z in (-1.4, 0.2):
        cyl(P(-0.75, -RIB_LIFT + 0.07, z), P(0.75, -RIB_LIFT + 0.07, z), 0.08, 0.08, 4, "dark", math.pi / 4)
        cyl(P(0, -RIB_LIFT, z), P(0, -0.36, z), 0.07, 0.07, 4, "dark", math.pi / 4)
        for x in (-0.5, 0.5):
            cyl(P(x, -RIB_LIFT, z), P(x, -0.2, z), 0.05, 0.05, 4, "dark", math.pi / 4)
            box(P(x, -0.18, z), (0.2, 0.05, 0.22), "black")
    d0 = V(davit[0], at.y - RIB_LIFT, davit[1])
    h = P(*RIB_HOOK)
    cyl(d0, d0 + UP * 0.12, 0.3, 0.3, 8, "dark")
    cyl(d0 + UP * 0.12, d0 + UP * 3.2, 0.17, 0.13, 8, "white")
    box(d0 + V(0, 1.1, 0), (0.42, 0.42, 0.42), "dark")
    cyl(d0 + V(-0.24, 1.1, 0), d0 + V(0.24, 1.1, 0), 0.16, 0.16, 8, "dark")
    tip = V(h.x, h.y + 0.85, h.z)
    def over(t, y): return V(lerp(d0.x, tip.x, t), y, lerp(d0.z, tip.z, t))
    tube([d0 + UP * 3.05, over(0.12, h.y + 0.95), over(0.45, h.y + 1.12), over(0.85, h.y + 1.02), tip],
         0.1, 6, "white")
    box(tip + V(0, -0.06, 0), (0.16, 0.24, 0.16), "dark")
    cyl(tip + V(0, -0.18, 0), h + UP * 0.08, 0.014, 0.014, 3, "black")
    box(h + UP * 0.13, (0.06, 0.1, 0.05), "orange")


RIB_AT, RIB_YAW = V(6.6, UPPER + RIB_LIFT, -4.0), math.pi   # bow outboard, toward -z


def deck_gear():
    """Two small black stacks beside the pilothouse, the rescue boat's cradle and
    davit at one corner, liferaft canisters at the others, mushroom vents."""
    for s in (1, -1):
        p = V(s * STACK_X, UPPER, 0)
        box(p + UP * 0.35, (1.0, 0.7, 1.2), "white")
        cyl(p + UP * 0.7, V(s * STACK_X, PH_ROOF + 0.9, 0), 0.26, 0.24, 8, "black")
        cyl(V(s * STACK_X, PH_ROOF + 0.9, 0), V(s * STACK_X, PH_ROOF + 1.0, 0), 0.3, 0.3, 8, "black")
        for e in (1, -1):
            v = V(s * 3.8, UPPER, e * 6.6)
            cyl(v, v + UP * 0.6, 0.12, 0.12, 6, "white")
            cyl(v + UP * 0.6, v + UP * 0.78, 0.3, 0.22, 8, "white")
    rib_cradle(RIB_AT, RIB_YAW, (9.0, RIB_AT.z + RIB_HOOK[2] * math.cos(RIB_YAW)))
    for p in (V(6.2, 0, 7.4), V(-6.2, 0, 7.4), V(-6.2, 0, -7.4), V(6.2, 0, -7.4)):
        rack = V(p.x, UPPER, p.z)
        slab(rack.x - 0.9, rack.x + 0.9, UPPER, UPPER + 0.25, rack.z - 0.55, rack.z + 0.55, "grey")
        for dz in (-0.3, 0.3):
            a = V(rack.x - 0.65, UPPER + 0.6, rack.z + dz)
            cyl(a, a + V(1.3, 0, 0), 0.3, 0.3, 10, "white")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); car_deck(); bulwarks()
    for s in (1, -1): cabin(s)
    bridge_and_upper_deck(); pilothouse(); masts(); deck_gear()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("hiyu_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("hiyu_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "hiyu_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("HIYU", result)
