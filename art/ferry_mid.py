# Builds the mid-poly Evergreen State class car ferry in Blender (run inside Blender:
# exec(open(path).read())) and exports it to assets/models/ferry_mid.glb (glTF, +Y up,
# vertex colours, flat shaded).
# Real scale, in metres. Game frame: double ended, the two ends at +Z and -Z alike, +Y
# up, waterline at y = 0 (Blender: +Z end to -Y, Z up). 94.5 m over the guards and
# 22.3 m in the beam, measured off the user's outboard profile; the plan, with its
# full ends and broad rounded aprons, after the user's photos of her and the Tillikum.
# One vehicle deck at CAR_DECK: a full-height centre tunnel of two lanes between the
# casings (the walls that carry the stairs up to the passenger cabin), and a wing of
# one lane outboard of each casing, under the passenger deck, behind the hull sides
# with their row of square ports. At each end the passenger deck runs out over the
# wings as the two "pickle forks", open to the sky between them over the tunnel, a
# narrow walkway across the cabin's end joining them; the forks' ends and the cabin's
# end faces are raked back 15 degrees. Above: the passenger cabin, the sun deck on its
# roof with a crew house toward each end, the two funnels side by side amidships with
# the fan room between them, a pilothouse at each end set back from the cabin's ends,
# its mast on its roof.
# Glass is split out for the vertex alpha the game's shader reads: `glass` (the
# pilothouses and the passenger cabin, lit at night) and `window` (the crew houses,
# some lit); the rest is `fixed`.
#
# Numbers the game wants (game frame, metres):
#   CAR_DECK 2.85; lanes at x = -8.45, -1.9, 1.9, 8.45 (wing, tunnel, tunnel, wing);
#   tunnel |x| < 4.0, casings 4.0..6.4 over |z| < CASING_Z, wings 6.4..10.5 inside the
#   hull side; clear headroom to the deckhead 4.15 (13 ft 6 in, as signed on her; 3.83
#   under the shallow beams and lights, so the game's trucks clear them at its scale). The
#   hull sides round in toward the ends (half beam 9.5 at |z| 35, 7.0 at the forks'
#   ends at 41.6), so wing cars park inside |z| ~ 36 and turn in to leave.
#   Masthead lanterns MAST_TOP at z = +-MAST_Z; sidelights on the pilothouse sides.
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "hull": (0.1, 0.1, 0.11), "antifoul": (0.4, 0.13, 0.11), "guard": (0.42, 0.43, 0.45),
    "green": (0.07, 0.36, 0.25), "white": (0.94, 0.95, 0.94), "deck": (0.4, 0.41, 0.42),
    "deckp": (0.5, 0.53, 0.52), "ceiling": (0.82, 0.83, 0.82), "panel": (0.66, 0.68, 0.7),
    "glass": (0.16, 0.22, 0.27), "window": (0.16, 0.22, 0.27), "pane": (0.62, 0.74, 0.8),
    "dark": (0.1, 0.1, 0.11), "black": (0.07, 0.07, 0.07), "steel": (0.6, 0.62, 0.64),
    "orange": (0.95, 0.42, 0.1), "red": (0.75, 0.12, 0.1), "lamp": (0.96, 0.95, 0.86),
    "yellow": (0.88, 0.7, 0.12), "bronze": (0.55, 0.42, 0.22), "apron": (0.4, 0.34, 0.29),
    "mesh": (0.72, 0.76, 0.75), "dkwall": (0.2, 0.21, 0.22), "gold": (0.78, 0.6, 0.2),
}
ROLES = ("glass", "window")
UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))
def lerp(a, b, t): return a + (b - a) * t


coll = bpy.data.collections.get("Ferry") or bpy.data.collections.new("Ferry")
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


# --- Plan outline -------------------------------------------------------------------
# Normalised: u along the half length (0 amidships, 1 at the end), v the half beam (1
# at the parallel body). At the deck her ends are one smooth oval, a superellipse from
# the parallel body round to the apron, that the hull sides, the forks and the green
# bulwarks all follow; under water her lines are much finer, so the hull's sides flare
# out toward the ends. `full` blends from the fine lines (0) to the deck's (1).

OVAL_Z, OVAL_P = 20.0, 2.3     # where the ends begin to round in, and how full they are


def deck_x(z):
    """Half beam of the hull at the deck at |z| (metres; the deck's end at HZ)."""
    t = min(max((abs(z) - OVAL_Z) / (HZ - OVAL_Z), 0.0), 1.0)
    return HB * max(0.0, 1.0 - t ** OVAL_P) ** (1.0 / OVAL_P)


def plan_v(u, full=1.0):
    u = min(abs(u), 1.0)
    t = max(0.0, (u - 0.3) / 0.7)
    fine = math.sqrt(max(0.0, 1.0 - t ** 2.2))
    return lerp(fine, deck_x(u * HZ) / HB, full)


# --- Dimensions (metres, game frame) ------------------------------------------------

HB = 10.8          # half beam of the hull at the deck (the guards stand 0.35 proud)
HZ = 46.4          # half length of the hull at the deck (the guards' ends at 47.25)
GUARD = 0.35
CAR_DECK = 2.85
GREEN_TOP = 3.92   # the green band up the hull side
PAX_DECK = 7.0     # underside of the passenger deck (the car deck's deckhead)
PAX_TOP = 7.3
RAKE = math.tan(math.radians(15.0))   # the forks' ends and the cabin's end faces lean back
FORK_Z = 41.6      # the forks' ends, where the hull sides round in to the car deck's opening
FORK_X = 4.7       # the forks' inner edges (over the casings)
GREEN_Z = 42.75    # the green bulwark's ends, at the apron's edge
CABIN_Z = 29.0     # the cabin's ends at the deck (raked back 15 degrees above)
WALK_Z = 30.6      # the walkway across the cabin's end, between the forks
SILL, HEAD, ROOF = 8.3, 9.75, 10.55
SUN = 10.75        # the sun deck (the cabin roof's top)
CASING_X0, CASING_X1, CASING_Z = 4.0, 6.4, 28.0
PH_Z0, PH_Z1, PH_HW = 21.6, 26.0, 4.5     # pilothouse (each end)
PH_SILL, PH_HEAD, PH_TOP = 12.4, 13.4, 13.7
MAST_Z, MAST_TOP = 22.5, 21.6     # on the pilothouse roofs, toward their inboard ends
STAIR_RUN = 5.6    # the open stair up inside each casing's end
FUNNEL_TOP = 14.8


def half_beam(z):
    """Half beam of the hull at the deck at z."""
    return HB * plan_v(z / HZ)


def side_pt(s, z, y, out=0.0):
    """Point on the hull side (s = +1 starboard... +x) at z, height y, and its outward normal."""
    dz = 0.05
    d = (half_beam(z + dz) - half_beam(z - dz)) / (2 * dz)
    n = V(s, 0, -d).normalized()
    return V(s * half_beam(z), y, z) + n * out, n


STATIONS = [0.0, 0.1, 0.2, 0.3, 0.38, 0.426, 0.47, 0.52, 0.57, 0.62, 0.67, 0.71, 0.75, 0.79, 0.83, 0.865,
            0.895, 0.92, 0.945, 0.965, 0.98, 0.99, 0.996, 1.0]
US = [-u for u in reversed(STATIONS[1:])] + STATIONS


def cabin_hd(y):
    """Half length of the cabin at height y, its end faces raked back."""
    return CABIN_Z - (y - PAX_TOP) * RAKE


def ring_at(y, sx, zt, d, full=1.0):
    """The hull's waterline at height y: x scaled by sx, its ends at +-zt, `d` out,
    `full` how full its ends are (see plan_v)."""
    stb = [V(HB * plan_v(u, full) * sx + d, y, u * zt) for u in US]
    return stb + [V(-p.x, y, p.z) for p in reversed(stb[1:-1])]


def zs_between(z0, z1, step=1.2):
    n = max(1, int(math.ceil((z1 - z0) / step)))
    return [lerp(z0, z1, i / n) for i in range(n + 1)]


# --- Hull ---------------------------------------------------------------------------

def hull():
    lines = [(-3.9, 0.8, 29.0, 0.0, 0.0), (-3.4, 0.92, 34.5, 0.0, 0.1), (-2.4, 0.975, 39.5, 0.0, 0.25),
             (-1.0, 0.995, 43.2, 0.0, 0.45), (0.0, 1.0, 44.6, 0.0, 0.6), (1.0, 1.0, 45.5, 0.0, 0.8), (2.15, 1.0, HZ, 0.0),
             (2.2, 1.0, 47.25, GUARD), (2.78, 1.0, 47.25, GUARD), (CAR_DECK, 1.0, 47.15, GUARD - 0.06)]
    rings = [ring_at(*l) for l in lines]

    def col(i, j, c):
        if c.y < 0.0: return "antifoul"
        if c.y < 2.17: return "hull"
        return "guard"
    loft(rings, col, caps=False)
    hface(rings[0], "antifoul", up=False)
    hface(rings[-1], "deck")
    # The aprons, worn bare steel, beyond the forks.
    for e in (1, -1):
        z0 = GREEN_Z - 0.3
        us = [u for u in STATIONS if u * 47.15 > z0]
        stb = [V(HB * plan_v(u) + GUARD - 0.08, CAR_DECK + 0.006, e * u * 47.15) for u in [z0 / 47.15] + us]
        hface(stb + [V(-p.x, p.y, p.z) for p in reversed(stb)], "apron")
    # Under water at each end: a skeg, the propeller and the rudder abaft it.
    for e in (1, -1):
        box(V(0, -3.6, e * 33.0), (0.5, 0.9, 7.0), "antifoul")
        hub = V(0, -2.75, e * 39.6)
        cyl(V(0, -2.75, e * 36.8), hub, 0.22, 0.22, 6, "antifoul")
        cyl(hub, hub + V(0, 0, e * 0.6), 0.35, 0.2, 8, "bronze")
        for k in range(4):
            a = math.tau * k / 4 + 0.4
            tip = hub + V(math.cos(a), math.sin(a), 0) * 1.35 + V(0, 0, e * 0.3)
            loft([[hub + V(0, 0, e * 0.05) + V(-math.sin(a), math.cos(a), 0) * 0.25, hub + V(0, 0, e * 0.45),
                   tip + V(0, 0, e * 0.1)],
                  [hub + V(0, 0, e * 0.05) + V(-math.sin(a), math.cos(a), 0) * 0.25 + V(0, 0, 0.001), hub + V(0, 0, e * 0.45 + 0.001),
                   tip + V(0, 0, e * 0.1 + 0.001)]], "bronze")
        box(V(0, -2.2, e * 41.3), (0.4, 2.8, 1.6), "antifoul")


OPEN_Y0, OPEN_Y1, OPEN_HW = 4.25, 5.73, 1.25    # the car deck's side openings
OPEN_Z = [-35.96 + k * 4.23 for k in range(18)]  # their centres, 18 down each side


def bulwarks():
    """The hull sides above the car deck: the green band to GREEN_Z, white to the
    passenger deck to the forks' raked ends, pierced by the row of square ports onto
    the wings, each with its corners filleted and a cross of round steel bars in it."""
    def band(s, y0, y1, z0, z1, key, top_key=None, in_key=None):
        prof = [(0.0, y0), (0.0, y1), (-0.3, y1), (-0.3, y0)]
        rings = []
        for z in zs_between(z0, z1):
            p, n = side_pt(s, z, 0.0)
            rings.append([p + n * u + UP * v for u, v in prof])
        loft(rings, lambda i, j, c: (top_key if j == 1 and top_key else in_key if j == 2 and in_key else key), cap_key=key)

    edges = [-FORK_Z] + [z + d for z in OPEN_Z for d in (-OPEN_HW, OPEN_HW)] + [FORK_Z]
    for s in (1, -1):
        band(s, CAR_DECK - 0.02, GREEN_TOP, -GREEN_Z, GREEN_Z, "green", "white", "dkwall")
        band(s, GREEN_TOP, OPEN_Y0, -FORK_Z, FORK_Z, "white")
        band(s, OPEN_Y1, PAX_DECK + 0.02, -FORK_Z, FORK_Z, "white")
        # The raked ends: a wedge from the deckhead out to the foot.
        for e in (1, -1):
            zb = FORK_Z + (PAX_DECK + 0.02 - GREEN_TOP) * RAKE
            pts = [side_pt(s, e * z, y) for z, y in ((FORK_Z, GREEN_TOP), (zb, GREEN_TOP), (FORK_Z, PAX_DECK + 0.02))]
            loft([[p for p, n in pts], [p - n * 0.3 for p, n in pts]], "white")
        for z0, z1 in zip(edges[::2], edges[1::2]):
            band(s, OPEN_Y0, OPEN_Y1, z0, z1, "white")
        for z in OPEN_Z:
            p, n = side_pt(s, z, (OPEN_Y0 + OPEN_Y1) / 2)
            t = V(n.z, 0, -n.x)
            mid = p - n * 0.15
            # Fillets in the four corners, so they read as big square ports.
            f = 0.28
            for sz in (-1, 1):
                for sy in (-1, 1):
                    zc = z + sz * OPEN_HW
                    cp, cn = side_pt(s, zc, 0.0)
                    yc = OPEN_Y1 if sy > 0 else OPEN_Y0
                    tz = V(cn.z, 0, -cn.x)
                    tri = lambda o: [cp + cn * o + UP * yc, cp + cn * o + UP * (yc - sy * f),
                                     cp + cn * o + UP * yc + tz * (s * sz * f)]
                    loft([tri(0.0), tri(-0.3)], "white")
            # The cross of round bars.
            cyl(mid + UP * -0.76, mid + UP * 0.76, 0.06, 0.06, 6, "steel")
            cyl(mid - t * (OPEN_HW + 0.02), mid + t * (OPEN_HW + 0.02), 0.06, 0.06, 6, "steel")
        # Inside: the side's frames, about every metre and a half a port's pitch apart in
        # step with them, from the dark lower band up to the deckhead; a yellow kerb.
        pitch = 4.23 / 4
        z = OPEN_Z[0] - pitch / 2
        while z - pitch > -FORK_Z + 0.4: z -= pitch
        while z < FORK_Z - 0.4:
            p, n = side_pt(s, z, (GREEN_TOP + PAX_DECK) / 2, -0.3)
            panel(p, -n, 0.12, PAX_DECK - GREEN_TOP, 0.22, "white")
            z += pitch
        rings = []
        for z in zs_between(-FORK_Z, FORK_Z):
            p, n = side_pt(s, z, 0.0, -0.3)
            rings.append([p + n * u + UP * v for u, v in ((0.02, CAR_DECK), (0.02, CAR_DECK + 0.18),
                                                          (-0.2, CAR_DECK + 0.18), (-0.2, CAR_DECK))])
        loft(rings, "yellow")


# --- Car deck -----------------------------------------------------------------------

def car_deck():
    # The casings either side of the tunnel, carrying the stairs up to the cabin.
    cx, cw = (CASING_X0 + CASING_X1) / 2, CASING_X1 - CASING_X0
    hh = PAX_DECK - CAR_DECK
    cz = CASING_Z - STAIR_RUN       # where the solid casing ends and the stair bay begins
    for s in (1, -1):
        loft([rect(s * cx, CAR_DECK, 0, cw / 2, cz, 0.0), rect(s * cx, PAX_DECK, 0, cw / 2, cz, 0.0)], "white")
        for e in (1, -1):
            stair(s, e, cz)
        # Doors and fire stations on both faces, a yellow-edged kerb along the foot.
        for face_x in (CASING_X0, CASING_X1):
            n = V(s if face_x == CASING_X1 else -s, 0, 0)
            for z in (-19.5, -8.0, 8.0, 19.5):
                panel(V(s * face_x, CAR_DECK + 1.05, z), n, 0.9, 2.1, 0.04, "dark")
            for z in (-14.0, 0.0, 14.0):
                panel(V(s * face_x, CAR_DECK + 1.3, z), n, 0.7, 0.8, 0.12, "red")
        box(V(s * cx, CAR_DECK + 0.08, 0), (cw + 0.3, 0.16, 2 * cz + 0.3), "panel")
        # Yellow struts raked out from the casings' ends to the deckhead.
        for e in (1, -1):
            for x in (CASING_X0 + 0.25, CASING_X1 - 0.25):
                box_between(V(s * x, CAR_DECK, e * (CASING_Z - 0.15)), V(s * x, PAX_DECK - 0.05, e * (CASING_Z + 1.9)),
                            0.32, "yellow")
    # Lane lines: down the tunnel's middle, and the tunnel's edges past the casings.
    for x, z0, z1 in ((0.0, -42.0, 42.0), (CASING_X0 - 0.3, CASING_Z + 0.5, 41.0), (-(CASING_X0 - 0.3), CASING_Z + 0.5, 41.0),
                      (CASING_X0 - 0.3, -41.0, -CASING_Z - 0.5), (-(CASING_X0 - 0.3), -41.0, -CASING_Z - 0.5)):
        z = z0
        while z < z1:
            box(V(x, CAR_DECK + 0.005, z + 1.0), (0.15, 0.01, 2.0), "yellow")
            z += 3.5
    # Deck beams across the deckhead (only under the forks past the walkway), curved
    # knees where they meet the hull sides, lights between them over each lane; a big
    # knee at each fork's end, arching the wing's entrance.
    z = -40.0
    while z <= 40.01:
        hw = half_beam(z) - 0.3
        if abs(z) < WALK_Z:
            box(V(0, PAX_DECK - 0.13, z), (2 * hw, 0.26, 0.35), "ceiling")
        else:
            for s in (1, -1):
                box(V(s * (hw + FORK_X) / 2, PAX_DECK - 0.13, z), (hw - FORK_X, 0.26, 0.35), "ceiling")
        for s in (1, -1):
            knee(s, z, 0.9, 0.3)
        for x in (-8.45, -1.9, 1.9, 8.45):
            if abs(x) < hw - 1.0 and abs(z) < 41.0 and (abs(z + 2.0) < WALK_Z - 0.6 or abs(x) > FORK_X + 0.6):
                box(V(x, PAX_DECK - 0.29, z + 2.0), (0.3, 0.06, 1.2), "lamp")
        z += 4.0
    for e in (1, -1):
        for s in (1, -1):
            knee(s, e * (FORK_Z - 0.2), 1.9, 0.4)


def stair(s, e, cz):
    """The open stair in casing s's end at end e: a flight climbing inboard from the car
    deck at the casing's end to the deckhead at cz, a wall on its wing side, open with
    a handrail to the tunnel."""
    x0, x1 = CASING_X0 + 0.15, CASING_X1 - 0.2
    xc, w = s * (x0 + x1) / 2, x1 - x0
    box(V(s * (CASING_X1 - 0.1), (CAR_DECK + PAX_DECK) / 2, e * (cz + CASING_Z) / 2), (0.2, PAX_DECK - CAR_DECK, CASING_Z - cz), "white")
    n = 18
    rise, going = (PAX_DECK - CAR_DECK) / n, STAIR_RUN / n
    for i in range(n):
        z = e * (CASING_Z - (i + 0.5) * going)
        box(V(xc, CAR_DECK + (i + 1) * rise - 0.03, z), (w, 0.06, going + 0.02), "steel")
        box(V(xc, CAR_DECK + (i + 0.5) * rise, e * (CASING_Z - (i + 1) * going + 0.02)), (w, rise, 0.03), "dkwall")
    a, b = V(xc, CAR_DECK, e * CASING_Z), V(xc, PAX_DECK, e * cz)
    for x in (x0 + 0.04, x1 - 0.04):
        box_between(V(s * x, CAR_DECK - 0.1, e * CASING_Z), V(s * x, PAX_DECK - 0.1, e * cz), 0.08, "dkwall")
    hx = s * (x0 + 0.05)
    tube([V(hx, CAR_DECK + 0.95, e * (CASING_Z - 0.2)), V(hx, PAX_DECK - 0.15, e * (cz + 1.0))], 0.03, 4, "yellow")
    for t in (0.1, 0.5, 0.9):
        p = lerp(V(hx, CAR_DECK, e * CASING_Z), V(hx, PAX_DECK, e * cz), t)
        cyl(p, p + UP * 0.95, 0.025, 0.025, 4, "yellow")


def knee(s, z, r, depth):
    """A curved knee in the corner between the hull side's inside and the deckhead."""
    xi = half_beam(z) - 0.3
    arc = [V(s * (xi - r + r * math.cos(a)), PAX_DECK - r + r * math.sin(a), z)
           for a in [math.pi / 2 * k / 6 for k in range(7)]]
    poly = [V(s * xi, PAX_DECK, z)] + arc
    loft([[p + V(0, 0, -depth / 2) for p in poly], [p + V(0, 0, depth / 2) for p in poly]], "ceiling")


# --- Passenger deck and cabin ---------------------------------------------------------

def deck_outline(y, zmax, out=0.0):
    zs = sorted(set([u * HZ for u in US if abs(u * HZ) < zmax - 0.3] + [-zmax, zmax]))
    stb = [V(half_beam(z) + out, y, z) for z in zs]
    return stb + [V(-p.x, y, p.z) for p in reversed(stb)]


def slab(poly_at, side="white"):
    """A deck plate between PAX_DECK and PAX_TOP over the outline poly_at(y)."""
    lo, hi = poly_at(PAX_DECK), poly_at(PAX_TOP)
    loft([lo, hi], side, caps=False)
    hface(lo, "ceiling", up=False)
    hface(hi, "deckp")


def pax_deck():
    """The passenger deck: full width to the walkway across the cabin's ends, then the
    two forks out over the wings, nothing over the tunnel between them."""
    slab(lambda y: deck_outline(y, WALK_Z, 0.12))
    for e in (1, -1):
        for s in (1, -1):
            zs = zs_between(WALK_Z, FORK_Z, 1.5)
            slab(lambda y, e=e, s=s, zs=zs: [V(s * (half_beam(z) + 0.12), y, e * z) for z in zs] +
                 [V(s * FORK_X, y, e * FORK_Z), V(s * FORK_X, y, e * WALK_Z)])
    # A grey rubbing strip along the deck edge.
    for s in (1, -1):
        rings = []
        for z in zs_between(-FORK_Z, FORK_Z):
            p, n = side_pt(s, z, PAX_TOP, 0.12)
            rings.append([p + n * u + UP * v for u, v in ((0.0, -0.14), (0.04, -0.14), (0.04, -0.02), (0.0, -0.02))])
        loft(rings, "panel")
    # The walkway's fascia over the tunnel: the end's number and the clearance board.
    for e in (1, -1):
        zf = e * (WALK_Z + 0.02)
        box(V(0.9, PAX_DECK - 0.2, zf), (1.3, 0.38, 0.04), "yellow")
        box(V(-0.9, PAX_DECK - 0.2, zf), (1.0, 0.3, 0.04), "white")


def cabin_dims():
    hw = min(10.3, half_beam(CABIN_Z - 3.0) - 0.25)
    ch = max(1.2, hw - (half_beam(CABIN_Z) - 0.3))
    return hw, ch


def cabin():
    hw, ch = cabin_dims()
    base, sill, head, top = (rect(0, y, 0, hw, cabin_hd(y), ch) for y in (PAX_TOP, SILL, HEAD, ROOF))
    loft([base, sill, head, top], lambda i, j, c: "glass" if i == 1 else "white", caps=False)
    # Piers between the windows, about 2.1 m apart (following the raked ends).
    pw = 0.5
    for k in range(8):
        a0, a1 = sill[k], sill[(k + 1) % 8]
        b0, b1 = head[k], head[(k + 1) % 8]
        L = (a1 - a0).length
        n = max(1, round(L / 2.13))
        out = V(a1.z - a0.z, 0, -(a1.x - a0.x)).normalized()
        if out.dot(V(a0.x + a1.x, 0, a0.z + a1.z)) < 0: out = -out
        for i in range(n + 1):
            t0, t1 = max(0.0, i / n - pw / 2 / L), min(1.0, i / n + pw / 2 / L)
            q = [lerp(a0, a1, t0), lerp(a0, a1, t1), lerp(b0, b1, t1), lerp(b0, b1, t0)]
            q = [p + out * 0.02 for p in q]
            face(q if normal(q).dot(out) > 0 else q[::-1], "white")
    # Its roof: the sun deck, overhanging a little.
    loft([rect(0, ROOF, 0, hw + 0.15, cabin_hd(ROOF) + 0.15, ch), rect(0, SUN, 0, hw + 0.15, cabin_hd(ROOF) + 0.15, ch)],
         "white", cap_key="deckp")


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


def end_decks():
    """The forks and the walkway: railed all round in green with mesh panels; the
    rescue boat and its davit out on one fork, vents and life rings."""
    prof = [(0.0, 0.0), (0.0, 0.95), (-0.06, 0.95), (-0.06, 0.0)]
    for e in (1, -1):
        def pt(x, z): return V(x, PAX_TOP, e * z)
        outer = zs_between(CABIN_Z - 0.3, FORK_Z - 0.1, 1.0)
        path = [pt(-(half_beam(z) + 0.05), z) for z in outer]
        xt = half_beam(FORK_Z - 0.1)
        path += [pt(-x, FORK_Z - 0.1) for x in (lerp(xt, FORK_X, 0.5), FORK_X + 0.05)]
        path += [pt(-(FORK_X + 0.05), z) for z in zs_between(WALK_Z + 0.05, FORK_Z - 1.2, 1.6)[::-1]]
        path += [pt(x, WALK_Z + 0.05) for x in (-(FORK_X + 0.05), -2.4, 0.0, 2.4, FORK_X + 0.05)]
        path += [pt(FORK_X + 0.05, z) for z in zs_between(WALK_Z + 0.05, FORK_Z - 1.2, 1.6)[1:]]
        path += [pt(x, FORK_Z - 0.1) for x in (FORK_X + 0.05, lerp(xt, FORK_X, 0.5))]
        path += [pt(half_beam(z) + 0.05, z) for z in outer[::-1]]
        ns = horiz_normals(path, False)
        loft([[p + n * u + UP * v for u, v in prof] for p, n in zip(path, ns)], "mesh", cap_key="green")
        tube([p + n * -0.03 + UP * 1.0 for p, n in zip(path, ns)], 0.06, 4, "green")
        tube([p + n * -0.03 + UP * 0.08 for p, n in zip(path, ns)], 0.05, 4, "green")
        for p, n in zip(path, ns):
            cyl(p + n * -0.03, p + n * -0.03 + UP * 1.0, 0.05, 0.05, 4, "green")
        # A staff on the walkway, raked out a little, and life rings on the fork rails.
        cyl(V(0, PAX_TOP + 0.95, e * (WALK_Z - 0.1)), V(0, 12.4, e * (WALK_Z + 0.9)), 0.06, 0.035, 4, "white")
        for s in (1, -1):
            torus(V(s * (FORK_X - 0.05), PAX_TOP + 0.6, e * (WALK_Z + 1.2)), V(1, 0, 0), 0.38, 0.09, 10, 4, "orange")
            torus(V(s * (half_beam(36.0) + 0.12), PAX_TOP + 0.6, e * 36.0), V(1, 0, 0), 0.38, 0.09, 10, 4, "orange")
    # The rescue boat in its cradle on the -Z end, and its davit.
    bz, bx = -34.6, half_beam(-34.6) - 2.3
    rings = []
    for t, w, hgt in ((-2.5, 0.35, 0.5), (-2.1, 0.8, 0.75), (-1.0, 1.0, 0.8), (1.2, 1.0, 0.8), (2.2, 0.85, 0.8), (2.5, 0.6, 0.75)):
        c = V(bx, PAX_TOP + 1.15, bz + t)
        rings.append([c + V(w, 0.3, 0), c + V(w * 0.8, -0.2, 0), c + V(0, -0.35, 0) * (hgt / 0.8),
                      c + V(-w * 0.8, -0.2, 0), c + V(-w, 0.3, 0)])
    # (The open top, the segment closing each ring, is her cockpit floor.)
    loft(rings, lambda i, j, c: "dark" if j == 4 else "orange", cap_key="orange")
    box(V(bx, PAX_TOP + 1.65, bz + 0.6), (1.1, 0.5, 1.0), "white")
    box(V(bx, PAX_TOP + 1.95, bz + 0.6), (1.0, 0.12, 0.9), "orange")
    tube([V(bx + s * 1.0, PAX_TOP + 1.5, bz + t) for s, t in ((1, -2.0), (1, 2.1), (-1, 2.1), (-1, -2.0))] +
         [V(bx + 1.0, PAX_TOP + 1.5, bz - 2.0)], 0.2, 6, "dark")
    for t in (-1.5, 1.5):
        box(V(bx, PAX_TOP + 0.45, bz + t), (1.6, 0.9, 0.25), "steel")
    dv = V(bx + 1.5, PAX_TOP, bz + 3.0)
    cyl(dv, dv + UP * 2.6, 0.22, 0.18, 8, "dark")
    cyl(dv + UP * 2.4, V(bx, PAX_TOP + 3.3, bz), 0.15, 0.1, 6, "dark")
    cyl(V(bx, PAX_TOP + 3.3, bz), V(bx, PAX_TOP + 1.9, bz), 0.02, 0.02, 3, "black")


# --- Sun deck -----------------------------------------------------------------------

def sun_deck():
    hw, ch = cabin_dims()
    rail_loop(rect(0, SUN, 0, hw + 0.05, cabin_hd(ROOF) + 0.05, ch), 1.05, "green")
    # The crew houses: one toward each end, enclosed, running inboard from the pilothouse
    # nearly to the funnels; small square windows and doors down their sides, a name
    # board, and on the roof vents, an air-conditioning unit and a ladder up at the
    # inboard end.
    for e in (1, -1):
        z0, z1 = 5.6, PH_Z0
        cz, hd, hw, top = e * (z0 + z1) / 2, (z1 - z0) / 2, 5.0, 12.9
        loft([rect(0, SUN, cz, hw, hd, 0.3), rect(0, top, cz, hw, hd, 0.3)], "white", cap_key="white")
        loft([rect(0, top, cz, hw + 0.12, hd + 0.12, 0.35), rect(0, top + 0.15, cz, hw + 0.12, hd + 0.12, 0.35)],
             "white", cap_key="deckp")
        for s in (1, -1):
            n = V(s, 0, 0)
            for k, z in enumerate(zs_between(z0 + 1.2, z1 - 1.0, 2.4)):
                if k == 2:
                    panel(V(s * hw, SUN + 1.0, e * z), n, 0.85, 2.0, 0.04, "steel")
                else:
                    panel(V(s * hw, 11.95, e * z), n, 0.8, 0.8, 0.03, "window")
            box(V(s * (hw + 0.02), 12.62, e * (z0 + z1) / 2), (0.04, 0.3, 1.6), "orange")
        # The inboard end: a door, and the ladder up to the roof beside it.
        panel(V(1.2, SUN + 1.0, e * z0), V(0, 0, -e), 0.85, 2.0, 0.04, "steel")
        for x in (-2.0, -1.4):
            cyl(V(x, SUN, e * (z0 - 0.25)), V(x, top + 1.0, e * (z0 - 0.25)), 0.03, 0.03, 4, "steel")
        for k in range(8):
            y = SUN + 0.3 + k * 0.3
            cyl(V(-2.0, y, e * (z0 - 0.25)), V(-1.4, y, e * (z0 - 0.25)), 0.02, 0.02, 3, "steel")
        # Roof gear.
        box(V(2.4, top + 0.55, e * (z0 + 2.2)), (1.6, 0.8, 1.2), "steel")
        for x, z in ((-2.5, z0 + 5.0), (2.0, z0 + 8.5), (-1.0, z0 + 11.5)):
            cyl(V(x, top + 0.15, e * z), V(x, top + 0.75, e * z), 0.2, 0.2, 8, "white")
            cyl(V(x, top + 0.75, e * z), V(x, top + 0.95, e * z), 0.38, 0.3, 8, "white")
        rail_loop([V(-hw + 0.3, top + 0.15, e * (z0 + 0.3)), V(-hw + 0.3, top + 0.15, e * (z0 + 4.0)),
                   V(-0.6, top + 0.15, e * (z0 + 4.0))], 1.0, "green", step=1.8, closed=False)
    # Liferaft canisters on racks outboard of each pilothouse, life rings on the rail.
    for e in (1, -1):
        for s in (1, -1):
            for zr in (22.4, 24.5):
                box(V(s * 7.6, SUN + 0.2, e * zr), (3.2, 0.4, 1.6), "steel")
                for dz in (-0.42, 0.42):
                    a = V(s * 6.2, SUN + 0.75, e * (zr + dz))
                    cyl(a, a + V(s * 2.8, 0, 0), 0.36, 0.36, 8, "white")
            torus(V(s * (hw - 1.4), SUN + 0.75, e * (cabin_hd(ROOF) + 0.12)), V(0, 0, 1), 0.38, 0.09, 10, 4, "orange")


FUNNEL_X = 4.2      # the two funnels, side by side either side of the centreline


def funnel():
    """Two funnels side by side amidships, white with a gold band under the black top,
    the WSF disc on their outboard faces; the fan room between them."""
    for s in (1, -1):
        x = s * FUNNEL_X
        rings = [rect(x, SUN, 0, 1.3, 3.0, 1.0), rect(x, 13.62, 0, 1.24, 2.05, 0.95), rect(x, 13.84, 0, 1.235, 2.0, 0.95),
                 rect(x, FUNNEL_TOP, 0, 1.2, 1.75, 0.9)]
        loft(rings, lambda i, j, c: ("white", "gold", "black")[i], cap_key="black")
        cyl(V(x, FUNNEL_TOP - 0.1, 0.3), V(x, FUNNEL_TOP + 0.9, 0.3), 0.32, 0.32, 8, "black")
        cyl(V(x, FUNNEL_TOP - 0.1, -0.7), V(x, FUNNEL_TOP + 0.5, -0.7), 0.2, 0.2, 6, "black")
        xo = x + s * 1.27
        cyl(V(xo, 12.4, 0), V(xo + s * 0.06, 12.4, 0), 0.6, 0.6, 12, "green")
        box(V(xo + s * 0.07, 12.45, 0), (0.02, 0.12, 0.78), "white")
        box(V(xo + s * 0.07, 12.25, 0.15), (0.02, 0.12, 0.52), "white")
        panel(V(x, SUN + 1.0, 2.6), V(0, 0, 1), 0.8, 2.0, 0.04, "steel")
    # The fan room: louvred sides, doors at both ends.
    hw = FUNNEL_X - 1.3
    loft([rect(0, SUN, 0, hw, 3.4, 0.2), rect(0, 12.7, 0, hw, 3.4, 0.2)], "white", cap_key="white")
    box(V(0, 12.78, 0), (2 * hw + 0.2, 0.16, 7.0), "white")
    for e in (1, -1):
        panel(V(0, SUN + 1.0, e * 3.4), V(0, 0, e), 0.9, 2.0, 0.04, "steel")
        for x in (-1.6, 1.6):
            panel(V(x, SUN + 1.25, e * 3.4), V(0, 0, e), 0.8, 1.0, 0.04, "dkwall")
            for k in range(5):
                panel(V(x, SUN + 0.85 + k * 0.2, e * 3.4), V(0, 0, e), 0.8, 0.04, 0.07, "white")
    for x in (-0.8, 0.8):
        cyl(V(x, 12.86, 1.8), V(x, 13.3, 1.8), 0.3, 0.3, 8, "steel")
        cyl(V(x, 13.3, 1.8), V(x, 13.45, 1.8), 0.45, 0.45, 8, "steel")


def pilothouses():
    for e in (1, -1):
        cz, hd = e * (PH_Z0 + PH_Z1) / 2, (PH_Z1 - PH_Z0) / 2
        cho, chi = 1.3, 0.3          # outboard (end) corners raked, inboard nearly square
        ch, chb = (cho, chi) if e > 0 else (chi, cho)
        base = rect(0, SUN, cz, PH_HW, hd, ch, chb)
        sill = rect(0, PH_SILL, cz, PH_HW, hd, ch, chb)
        head = rect(0, PH_HEAD, cz + e * 0.12, PH_HW + 0.12, hd + 0.12, ch + 0.05, chb)
        top = rect(0, PH_TOP, cz + e * 0.12, PH_HW + 0.12, hd + 0.12, ch + 0.05, chb)
        loft([base, sill, head, top], lambda i, j, c: "glass" if i == 1 else "white", cap_key="white")
        for k in range(8):
            a0, a1, b0, b1 = sill[k], sill[(k + 1) % 8], head[k], head[(k + 1) % 8]
            n = max(1, round((a1 - a0).length / 1.25))
            for i in range(n):
                t = i / n
                cyl(lerp(a0, a1, t), lerp(b0, b1, t), 0.05, 0.05, 4, "white")
        # The green roof, overhanging most at the end; a door aft on each side.
        loft([rect(0, PH_TOP, cz + e * 0.45, PH_HW + 0.45, hd + 0.75, ch + 0.2, chb),
              rect(0, PH_TOP + 0.3, cz + e * 0.45, PH_HW + 0.45, hd + 0.75, ch + 0.2, chb)], "green")
        for s in (1, -1):
            panel(V(s * PH_HW, SUN + 1.0, e * (PH_Z0 + 0.8)), V(s, 0, 0), 0.8, 2.0, 0.04, "steel")


def masts():
    """A mast on each pilothouse roof: yards for the lights, the radar on a railed
    platform facing the end, the gaff raked toward amidships."""
    for e in (1, -1):
        z = e * MAST_Z
        base = PH_TOP + 0.3
        cyl(V(0, base, z), V(0, MAST_TOP, z), 0.18, 0.1, 8, "white")
        for a in (-1, 1):
            cyl(V(a * 1.2, base, z), V(0, 16.6, z), 0.06, 0.05, 4, "white")
        for y, w in ((18.5, 3.2), (17.4, 2.4)):
            box(V(0, y, z), (w, 0.12, 0.12), "white")
        box(V(0, 16.6, z + e * 0.9), (1.2, 0.1, 1.8), "white")
        rail_loop([V(0.6, 16.65, z + e * 0.15), V(0.6, 16.65, z + e * 1.8), V(-0.6, 16.65, z + e * 1.8),
                   V(-0.6, 16.65, z + e * 0.15)], 0.6, "white", step=1.0, closed=False)
        cyl(V(0, 16.7, z + e * 1.2), V(0, 16.9, z + e * 1.2), 0.12, 0.12, 6, "dark")
        box(V(0, 16.98, z + e * 1.2), (2.6, 0.12, 0.22), "dark")
        cyl(V(0, 19.6, z), V(0, 21.5, z - e * 3.2), 0.07, 0.05, 4, "white")
        cyl(V(0, MAST_TOP, z), V(0, MAST_TOP + 0.35, z), 0.06, 0.06, 4, "dark")
        # Whip aerials at the roof's corners.
        for a in (-1, 1):
            cyl(V(a * 3.8, base, e * (PH_Z0 + 0.4)), V(a * 3.9, base + 3.2, e * (PH_Z0 + 0.3)), 0.03, 0.015, 3, "dark")


def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    hull(); bulwarks()
    car_deck()
    pax_deck(); cabin(); end_decks()
    sun_deck(); funnel(); pilothouses(); masts()
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("ferry_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("ferry_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built = build()
_glb = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art",
                                     "..", "assets", "models", "ferry_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
