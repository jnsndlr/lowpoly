# Builds the mid-poly Guemes Island ferry, M/V Guemes (Skagit County, Gladding-Hearn
# 1979), in Blender (run inside Blender: exec(open(path).read())) and exports it to
# assets/models/guemes_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# Real scale, in metres. Game frame: double ended, the two ends at +Z and -Z alike, +Y
# up, waterline at y = 0 (Blender: +Z end to -Y, Z up). 37.8 m over the rim and 15.85 m
# in the beam (124 x 52 ft, the county's figures); 21 cars. The plan, after the user's
# photos: straight sides and broad, full oval ends, a rusty steel rim round the deck
# edge. One open car deck (three lanes, for the game's cars), the house a long narrow block along the
# starboard side, the passenger cabin in it under an open upper deck; on that, a short
# tower and the flared pilothouse with its mast. Tall white panels guard the deck's
# four corners (her name on them), low bulwarks with a pipe rail between, yellow bands
# across the deck where the game hangs its nets (Models.ferry_net, at NET_Z, so it can
# drop the one at the docked end), and the engine rooms at two opposite corners, each
# with its black machinery box, silencer and tall exhaust stack.
# Glass is split out for the vertex alpha the game's shader reads: `glass` (the
# pilothouse, lit at night) and `window` (the house's windows, some lit); the rest is
# `fixed`.
#
# Heights above her car deck: the upper deck 3.7, the pilothouse roof 7.45, the
# masthead 13.25 (measured off the photos against the cars on deck). Her freeboard
# is raised to meet the game's piers (CAR_DECK), the rest kept as built over it.
#
# Numbers the game wants (game frame, metres):
#   CAR_DECK 2.5; three lanes at x = LANES (-5.2, -1.63, 1.94; the house's inboard face at
#   x 3.95, |z| < HOUSE_Z 10.6), rows 5.95 apart; cars park inside |z| ~ 14.3 (the nets
#   at NET_Z 15.2), but the port lane's +z end is the port machinery box's (|x| 4.85
#   to 6.55, z 12.6 to 14.2): cars in it turn in to |x| < 2 past z 8.6 to clear it.
#   Masthead lantern at (PH_X, MAST_TOP, 0); pilothouse half width 1.6 at its sill..
#   Masthead lantern MAST_TOP over the pilothouse at z 0.
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.12, 0.1, 0.09), "antifoul": (0.36, 0.14, 0.11), "rim": (0.36, 0.25, 0.18),
    "white": (0.94, 0.95, 0.94), "deck": (0.27, 0.28, 0.29), "apron": (0.38, 0.3, 0.24),
    "stripe": (0.86, 0.86, 0.82), "yellow": (0.9, 0.74, 0.12), "net": (0.7, 0.58, 0.38),
    "grey": (0.5, 0.52, 0.54), "roof": (0.42, 0.44, 0.47), "dkwall": (0.22, 0.23, 0.24),
    "glass": (0.16, 0.22, 0.27), "window": (0.13, 0.16, 0.19), "dark": (0.1, 0.1, 0.11),
    "black": (0.07, 0.07, 0.07), "rust": (0.3, 0.2, 0.15), "red": (0.72, 0.13, 0.11),
    "navy": (0.12, 0.16, 0.36), "steel": (0.6, 0.62, 0.64), "orange": (0.95, 0.42, 0.1),
}
ROLES = ("glass", "window")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


coll = bpy.data.collections.get("Guemes") or bpy.data.collections.new("Guemes")
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


# --- Dimensions (metres, game frame) ------------------------------------------------

HB = 7.75          # half beam of the hull at the deck (the rim stands RIM proud)
HZ = 18.72         # half length of the hull at the deck
RIM = 0.18
OVAL_Z, OVAL_P = 6.5, 2.6     # where the ends begin to round in, and how full they are
CAR_DECK = 2.5     # her real freeboard is about 1.55; raised to the game's pier height
#                    (Layout.DECK_Y 3.15 at FerryClass.MID_SCALE 1.26)
LANES = (-5.2, -1.63, 1.94)   # 4.5 apart at MID_SCALE (FerryClass.LANE_SPACING)
NET_Z = 15.2       # the nets across the open ends (built by the game)
WALL_Z = 15.8      # the corner panels' ends
PANEL_Z0, PANEL_Z1 = 10.8, 12.2
# The machinery boxes: side, centre z, length, outboard and inboard |x|.
MACH = ((-1, 13.4, 1.6, 6.55, 4.85), (1, -12.4, 2.4, 6.7, 4.9))   # the bulwark rises to the corner panels between these
LOW_H, PANEL_H = 1.05, 2.2
HOUSE_X0, HOUSE_X1, HOUSE_Z = 3.95, 7.55, 10.6
HOUSE_TOP = CAR_DECK + 3.5    # the upper deck (0.2 thick above)
UPPER = HOUSE_TOP + 0.2
TOWER_TOP = CAR_DECK + 5.3
PH_X = 5.75
PH_SILL, PH_HEAD, PH_ROOF = CAR_DECK + 5.75, CAR_DECK + 7.2, CAR_DECK + 7.45
MAST_TOP = CAR_DECK + 13.25


# --- Plan outline -------------------------------------------------------------------
# Straight sides for |z| < OVAL_Z, then each end one superellipse quadrant round to the
# apron; under water the ends are shorter and the sides drawn in.

def deck_x(z, hb=HB, hz=HZ):
    t = min(max((abs(z) - OVAL_Z) / (hz - OVAL_Z), 0.0), 1.0)
    return hb * max(0.0, 1.0 - t ** OVAL_P) ** (1.0 / OVAL_P)


def oval(y, hb=HB, hz=HZ, n_end=14, n_side=4):
    """Closed plan ring at height y: up the starboard side, round the +z end, down the
    port side and round the -z end (same vertex count for any hb, hz)."""
    L = hz - OVAL_Z
    q = []
    for i in range(n_end + 1):
        a = (math.pi / 2) * i / n_end
        c, s = math.cos(a), math.sin(a)
        q.append((hb * c ** (2 / OVAL_P), OVAL_Z + L * s ** (2 / OVAL_P)))
    pts = [(hb, lerp(-OVAL_Z, OVAL_Z, i / n_side)) for i in range(n_side)]
    pts += q
    pts += [(-x, z) for x, z in reversed(q)][1:]
    pts += [(-hb, lerp(OVAL_Z, -OVAL_Z, i / n_side)) for i in range(1, n_side)]
    pts += [(-x, -z) for x, z in q]
    pts += [(x, -z) for x, z in reversed(q)][1:-1]
    return [V(x, y, z) for x, z in pts]


def zs_between(z0, z1, step=0.6, extra=()):
    n = max(1, math.ceil(abs(z1 - z0) / step))
    zs = [lerp(z0, z1, i / n) for i in range(n + 1)]
    lo, hi = min(z0, z1), max(z0, z1)
    zs += [e for e in extra if lo + 0.05 < e < hi - 0.05]
    return sorted(set(round(z, 4) for z in zs), reverse=z1 < z0)


def side_normal(s, z):
    a, b = V(s * deck_x(z - 0.05), 0, z - 0.05), V(s * deck_x(z + 0.05), 0, z + 0.05)
    t = (b - a).normalized()
    n = V(t.z, 0, -t.x)
    return n if n.x * s > 0 else -n


# --- Hull ---------------------------------------------------------------------------

def hull():
    """A shallow scow-ended hull: the ends rake up from a flat bottom; the rusty rim
    round the deck edge stands proud of the sides."""
    rings = [oval(-2.0, HB - 1.3, HZ - 3.4), oval(-1.2, HB - 0.5, HZ - 1.7),
             oval(-0.3, HB - 0.12, HZ - 0.5), oval(0.6, HB - 0.02, HZ - 0.1),
             oval(CAR_DECK - 0.45, HB, HZ)]
    loft(rings, lambda i, j, c: "antifoul" if c.y < -0.05 else "hull", cap_key="hull")
    y0, y1 = CAR_DECK - 0.45, CAR_DECK + 0.06
    r = lambda y, o: oval(y, HB + o, HZ + o)
    loft([r(y0, 0), r(y0 + 0.1, RIM), r(y1, RIM), r(y1, 0)], "rim", caps=False)


def car_deck():
    """Bare steel at the ends, asphalt between the nets, white lane lines, yellow bands
    across the deck at the nets."""
    hface(oval(CAR_DECK), "apron")
    y = CAR_DECK + 0.01
    zs = zs_between(-NET_Z, NET_Z, 0.8, (-OVAL_Z, OVAL_Z))
    hface([V(deck_x(z) - 0.05, y, z) for z in zs] + [V(-deck_x(z) + 0.05, y, z) for z in reversed(zs)], "deck")
    for e in (1, -1):
        z0, z1 = e * NET_Z, e * (NET_Z + 0.35)
        hface([V(deck_x(z0) - 0.05, y, z0), V(deck_x(z1) - 0.05, y, z1),
               V(-deck_x(z1) + 0.05, y, z1), V(-deck_x(z0) + 0.05, y, z0)], "yellow")
    for a, b in zip(LANES, LANES[1:]):
        hface(rect((a + b) / 2, y + 0.005, 0, 0.06, 12.8), "stripe")
    hface(rect(LANES[0] - 1.785, y + 0.005, 0, 0.06, 10.6), "stripe")


# --- Bulwarks, corner panels, rails --------------------------------------------------

def wall_h(z):
    az = abs(z)
    if az >= PANEL_Z1: return PANEL_H
    if az <= PANEL_Z0: return LOW_H
    return lerp(LOW_H, PANEL_H, (az - PANEL_Z0) / (PANEL_Z1 - PANEL_Z0))


def wall(s, z0, z1, thick=0.15):
    zs = zs_between(z0, z1, 0.5, (PANEL_Z0, PANEL_Z1, -PANEL_Z0, -PANEL_Z1))
    path = [V(s * (deck_x(z) - 0.03), CAR_DECK, z) for z in zs]
    ns = horiz_normals(path, False)
    rings = []
    for p, n, z in zip(path, ns, zs):
        h = wall_h(z); q = p - n * thick
        rings.append([p, p + UP * h, q + UP * h, q])
    loft(rings, "white")
    return path, zs


def bulwarks():
    # Port: one wall end to end, low amidships with a pipe rail on it.
    path, zs = wall(-1, -WALL_Z, WALL_Z)
    top = [p + UP * LOW_H + V(0.075, 0, 0) for p, z in zip(path, zs) if abs(z) <= PANEL_Z0 + 0.01]
    rail_loop(top, 0.7, "white", step=1.6, closed=False)
    # Starboard: the house fills amidships; the corner panels run from its ends.
    for e in (1, -1):
        wall(1, e * HOUSE_Z, e * WALL_Z)
    # Her name and port of registry in black on each corner panel's outboard face.
    for s in (1, -1):
        for e in (1, -1):
            z = e * 13.6
            n = side_normal(s, z)
            c = V(s * deck_x(z), 0, z) + n * 0.0
            for y, w in ((CAR_DECK + 1.75, 1.3), (CAR_DECK + 1.35, 1.5), (CAR_DECK + 1.0, 0.45)):
                panel(c + UP * y, n, w, 0.2, 0.02, "dark")


# --- The house ------------------------------------------------------------------------

def house():
    """The long house down the starboard side: the passenger cabin amidships (its grey
    band of windows facing the cars), doors toward the ends, the open upper deck on
    its roof with a rail, life-jacket boxes and the liferaft canisters."""
    cx, hw = (HOUSE_X0 + HOUSE_X1) / 2, (HOUSE_X1 - HOUSE_X0) / 2
    loft([rect(cx, CAR_DECK, 0, hw, HOUSE_Z), rect(cx, HOUSE_TOP, 0, hw, HOUSE_Z)], "white")
    nin, nout = V(-1, 0, 0), V(1, 0, 0)
    xi, xo = HOUSE_X0, HOUSE_X1
    panel(V(xi, CAR_DECK + 1.75, 0), nin, 11.0, 1.5, 0.02, "dkwall")
    for z in (-4.0, -2.0, 0.0, 2.0, 4.0):
        panel(V(xi, CAR_DECK + 1.8, z), nin, 0.6, 1.0, 0.035, "window")
    for e in (1, -1):
        panel(V(xi, CAR_DECK + 1.75, e * 5.9), nin, 0.75, 1.5, 0.03, "red")
        panel(V(xi, CAR_DECK + 1.05, e * 7.9), nin, 0.9, 2.05, 0.03, "grey")
        panel(V(xi, CAR_DECK + 2.7, e * 9.4), nin, 0.8, 0.45, 0.03, "white")   # a notice board
        # Outboard: tall narrow windows in pairs, and a door at the end.
        for z in (0.9, 1.65, 4.6, 5.35, 8.2):
            panel(V(xo, CAR_DECK + 1.85, e * z), nout, 0.45, 1.2, 0.035, "window")
        panel(V(cx, CAR_DECK + 1.05, e * HOUSE_Z), V(0, 0, e), 0.9, 2.05, 0.03, "grey")
    box(V(xi - 0.08, CAR_DECK + 0.07, 0), (0.16, 0.14, 2 * HOUSE_Z), "yellow")   # kerb
    for z in (-6.8, -3.0, 3.0, 6.8):     # yellow posts guarding the house side
        cyl(V(xi - 0.35, CAR_DECK, z), V(xi - 0.35, CAR_DECK + 0.9, z), 0.08, 0.08, 6, "yellow")

    # The upper deck, overhanging the cars a little, and its rail.
    ux0, ux1, uz = HOUSE_X0 - 0.6, 7.72, HOUSE_Z + 0.4
    loft([rect((ux0 + ux1) / 2, HOUSE_TOP, 0, (ux1 - ux0) / 2, uz),
          rect((ux0 + ux1) / 2, UPPER, 0, (ux1 - ux0) / 2, uz)], "white")
    rail_loop([V(ux0 + 0.05, UPPER, -uz + 0.05), V(ux0 + 0.05, UPPER, uz - 0.05),
               V(ux1 - 0.05, UPPER, uz - 0.05), V(ux1 - 0.05, UPPER, -uz + 0.05)], 1.0, "white", step=1.5)
    for z in (-6.8, 6.8):
        box(V(ux0 + 0.6, UPPER + 0.4, z), (0.8, 0.8, 1.5), "white")       # life jackets
        panel(V(ux0 + 0.2, UPPER + 0.5, z), V(-1, 0, 0), 1.1, 0.3, 0.02, "dark")
    # Liferaft canisters, two rows of three, on a rack.
    box(V(6.0, UPPER + 0.08, -8.3), (2.2, 0.16, 1.6), "grey")
    for i in range(3):
        for j in range(2):
            p = V(5.3 + i * 0.7, UPPER + 0.16, -8.65 + j * 0.7)
            cyl(p, p + UP * 0.95, 0.3, 0.3, 8, "black")

    # A steep ladder up the house's +z end from the car deck.
    a0, a1 = V(0, CAR_DECK, HOUSE_Z + 1.7), V(0, UPPER, HOUSE_Z)
    for x in (4.4, 5.2):
        box_between(a0 + V(x, 0, 0), a1 + V(x, 0, 0), 0.07, "steel")
        cyl(a0 + V(x, 0.9, 0), a1 + V(x, 0.9, 0), 0.03, 0.03, 4, "yellow")
    for i in range(1, 9):
        p = lerp(a0, a1, i / 9)
        box(p + V(4.8, 0, 0), (0.8, 0.04, 0.22), "steel")


def tower_and_pilothouse():
    """A short tower on the upper deck carrying the name board, and the pilothouse on
    it: windows all round, flared outward, under an overhanging grey roof."""
    loft([rect(PH_X, UPPER, 0, 1.25, 2.3), rect(PH_X, TOWER_TOP, 0, 1.25, 2.3)], "white")
    for s in (1, -1):
        n = V(s, 0, 0)
        panel(V(PH_X + s * 1.25, CAR_DECK + 4.55, 0), n, 2.4, 0.42, 0.04, "dark")
        panel(V(PH_X + s * 1.25, CAR_DECK + 4.55, 0), n, 1.8, 0.16, 0.06, "white")
    for e in (1, -1):
        panel(V(PH_X, UPPER + 0.85, e * 2.3), V(0, 0, e), 0.5, 0.5, 0.03, "window")
    lo = rect(PH_X, PH_SILL, 0, 1.6, 2.55, 0.5)
    hi = rect(PH_X, PH_HEAD, 0, 1.9, 2.85, 0.6)
    loft([rect(PH_X, TOWER_TOP, 0, 1.6, 2.55, 0.5), lo], "white")
    loft([lo, hi], "glass", caps=False)
    for i in range(8):
        a, b = lo[i], hi[i]
        box_between(a, b, 0.09, "white")
        a2, b2 = lo[(i + 1) % 8], hi[(i + 1) % 8]
        if (a - a2).length > 2.0:
            for t in (1 / 3, 2 / 3) if (a - a2).length > 4.0 else (0.5,):
                box_between(lerp(a, a2, t), lerp(b, b2, t), 0.07, "white")
    loft([rect(PH_X, PH_HEAD, 0, 1.9, 2.85, 0.6), rect(PH_X, PH_HEAD + 0.08, 0, 1.9, 2.85, 0.6)], "white")
    loft([rect(PH_X, PH_HEAD + 0.08, 0, 2.2, 3.15, 0.7), rect(PH_X, PH_ROOF, 0, 2.2, 3.15, 0.7)], "roof")
    # Searchlights and horn on the roof.
    for e in (1, -1):
        for s in (1, -1):
            p = V(PH_X + s * 1.6, PH_ROOF, e * 2.5)
            cyl(p, p + UP * 0.25, 0.05, 0.05, 4, "steel")
            cyl(p + UP * 0.35 + V(0, 0, -e * 0.15), p + UP * 0.35 + V(0, 0, e * 0.2), 0.14, 0.16, 8, "steel")


def mast():
    """A pole mast on the pilothouse roof: radar, a yard with aerials and domes, the
    masthead light, a gaff with the flag."""
    b = V(PH_X, PH_ROOF, 0)
    box(b + UP * 0.6, (0.7, 1.2, 0.7), "white")
    cyl(b + UP * 1.2, V(PH_X, MAST_TOP, 0), 0.14, 0.07, 8, "white")
    box(V(PH_X, PH_ROOF + 1.5, 0), (1.3, 0.1, 1.3), "white")
    cyl(V(PH_X, PH_ROOF + 1.55, 0), V(PH_X, PH_ROOF + 1.8, 0), 0.12, 0.12, 6, "dark")
    box(V(PH_X, PH_ROOF + 1.87, 0), (0.25, 0.14, 2.2), "dark")            # radar scanner
    box(V(PH_X, PH_ROOF + 3.35, 0), (2.6, 0.1, 0.1), "white")              # yard
    for s in (1, -1):
        p = V(PH_X + s * 1.2, PH_ROOF + 3.4, 0)
        cyl(p, p + UP * 1.4, 0.03, 0.015, 3, "dark")
        cyl(V(PH_X + s * 0.6, PH_ROOF + 3.4, 0), V(PH_X + s * 0.6, PH_ROOF + 3.65, 0), 0.13, 0.13, 6, "white")
    box(V(PH_X, MAST_TOP - 0.5, 0), (0.18, 0.25, 0.18), "white")
    cyl(V(PH_X, MAST_TOP, 0), V(PH_X, MAST_TOP + 0.6, 0), 0.025, 0.02, 3, "dark")
    gt = V(PH_X, PH_ROOF + 3.45, -2.2)
    cyl(V(PH_X, PH_ROOF + 2.45, -0.1), gt, 0.04, 0.03, 4, "white")
    for i, k in enumerate(("red", "white", "red", "white")):
        box(gt + V(0, -0.12 - i * 0.12, -0.45), (0.02, 0.12, 0.85), k)
    box(gt + V(0, -0.24, -0.2), (0.025, 0.24, 0.38), "navy")


def machinery():
    """The engine rooms at opposite corners: each a black box on deck with its silencer
    and tall exhaust stack, a lifebuoy on its face. The port one (+z) is tucked into
    the corner past the end of the port lane, which turns in round it."""
    for s, zc, zl, x_out, x_in in MACH:
        cx, w = s * (x_out + x_in) / 2, abs(x_out - x_in)
        box(V(cx, CAR_DECK + 1.2, zc), (w, 2.4, zl), "black")
        box(V(cx, CAR_DECK + 2.42, zc), (w + 0.1, 0.06, zl + 0.1), "dkwall")
        top = CAR_DECK + 2.45
        cyl(V(cx - 0.7, top + 0.38, zc), V(cx + 0.7, top + 0.38, zc), 0.32, 0.32, 8, "rust")
        for x in (cx - 0.45, cx + 0.45):
            box(V(x, top + 0.12, zc), (0.12, 0.24, 0.5), "dark")
        e = 1 if zc > 0 else -1
        sx = cx + s * 0.55
        cyl(V(sx, top + 0.38, zc), V(sx, CAR_DECK + 7.85, zc), 0.15, 0.13, 8, "black")
        box_between(V(sx, CAR_DECK + 7.85, zc), V(sx, CAR_DECK + 7.95, zc + e * 0.3), 0.3, "black")
        cyl(V(sx, top + 1.5, zc), V(cx - s * 0.55, top + 0.9, zc), 0.03, 0.03, 4, "steel")
        torus(V(s * (x_in - 0.03), CAR_DECK + 1.5, zc), V(1, 0, 0), 0.3, 0.07, 10, 4, "white")
    # A lifebuoy on each of the other corners' panels, inboard.
    for s, e in ((1, 1), (-1, -1)):
        z = e * 13.2
        n = side_normal(s, z)
        torus(V(s * deck_x(z), CAR_DECK + 1.5, z) - n * 0.22, n, 0.3, 0.07, 10, 4, "orange")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); car_deck()
    bulwarks()
    house(); tower_and_pilothouse(); mast()
    machinery()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("guemes_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("guemes_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "guemes_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("GUEMES", result)
