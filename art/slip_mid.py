# Builds the mid-poly ferry slip's lift and transfer span in Blender (run inside Blender,
# or headless: Blender -b --factory-startup --python art/slip_mid.py) and exports it to
# assets/models/slip_mid.glb (glTF, +Y up, vertex colours, flat shaded).
# A WSF-style slip: two green lattice lift towers on pile caps either side of the slip,
# joined over the top by a header truss; in each tower's head a sheave carries the hoist
# cable from the span's lifting beam over to a concrete counterweight hanging in the
# tower. The transfer span is a steel bridge, plate girders either side with a railing
# on top, hinged at its shore end to the trestle; the lifting beam under its tip runs out
# into guides in the towers. The apron, hinged to the span's tip, is a steel plate with a
# striped toe that lies on the ferry's car deck, raised and lowered by a pair of rams.
# Game frame: the terminal's slip frame (Layout): +Z ("u") out to sea along the slip, +X
# across it, +Y up, water at y = 0, the lot and the car deck at LOT_Y (Blender: +Z up,
# seaward to -Y). Parts, each about its own pivot (mirrored in scripts/sim/slip_ramp.gd):
#   towers         fixed, in the slip frame
#   span           origin at the shore hinge (0, LOT_Y, HINGE_U), deck top at y 0, out +Z
#   apron          origin at its hinge on the span's tip, plate top at y 0, out +Z
#   counterweight  origin at the cable's eye on top, block hanging below
#   cable          the hoist cable, 1 m long from its top (origin) down -Y, scaled to length
#   rambody        apron ram's cylinder, eye at the origin, reaching out +Z
#   ramrod         its piston rod, eye at the origin, reaching out +Z (into the cylinder)
import bpy, bmesh, math, os
from mathutils import Vector

PAL = {
    "green": (0.07, 0.36, 0.25), "green_dark": (0.05, 0.27, 0.19), "concrete": (0.62, 0.62, 0.6),
    "concrete_dark": (0.48, 0.48, 0.47), "asphalt": (0.26, 0.27, 0.29), "yellow": (0.92, 0.78, 0.3),
    "black": (0.08, 0.08, 0.09), "steel": (0.55, 0.57, 0.58), "steel_dark": (0.3, 0.31, 0.32),
    "cable": (0.17, 0.17, 0.18), "chrome": (0.8, 0.82, 0.84), "wood": (0.33, 0.26, 0.2),
    "galv": (0.68, 0.69, 0.68), "plate": (0.36, 0.37, 0.38), "rust": (0.45, 0.3, 0.2),
}
PARTS = ("towers", "span", "apron", "counterweight", "cable", "rambody", "ramrod")

# --- Dimensions (metres; keep in step with SlipRamp) ----------------------------------
LOT_Y = 3.15
HINGE_U = 2.0            # the span's shore hinge
SPAN_L = 26.5            # hinge to the apron's hinge
APRON_L = 7.0
APRON_T = 0.12           # the plate's thickness past the heel, where it lies over a ferry's deck
APRON_HEEL = 1.0         # the deep heel round the hinge, which stays clear of the boat's end
DECK_HW = 6.6            # half width between the curbs
GIRDER_X = 7.2
LIFT_Z = 25.0            # lifting beam, along the span from its hinge
LUG = (9.0, -0.5)        # cable lugs on the lifting beam (x, y in the span's frame)
TOWER_X = 9.6            # tower centres either side
TOWER_U = HINGE_U + LIFT_Z
TOWER_HW = 1.4           # half the tower's side (leg centres)
TOP_Y = 16.95            # top of the header and the tower heads
HEADER_Y0 = 15.35
SHEAVE_Y = 14.6
SHEAVE_R = 0.6
CW_X = TOWER_X + SHEAVE_R   # counterweight hangs under the outside of the sheave
CW_SIZE = (0.9, 3.2, 1.8)
RAM_X = 5.9
RAM_A = (0.5, 23.5)      # ram cylinder's eye on the span (y, z)
RAM_B = (0.5, 1.2)       # rod's eye on the apron (y, z)
RAM_BODY = 2.6
RAM_ROD = 2.4

UP = Vector((0, 1, 0))


def G(p): return Vector((p.x, -p.z, p.y))
def V(x, y, z): return Vector((x, y, z))


coll = bpy.data.collections.get("SLIP") or bpy.data.collections.new("SLIP")
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
PART = ["towers"]


def bm_for():
    role = PART[0]
    if role not in BMS:
        bm = bmesh.new(); bm.loops.layers.color.new("Col"); BMS[role] = bm
    return BMS[role]


def face(pts, key):
    q = [pts[0]]
    for p in pts[1:]:
        if (p - q[-1]).length > 1e-5: q.append(p)
    if len(q) > 2 and (q[0] - q[-1]).length < 1e-5: q.pop()
    if len(q) < 3: return
    bm = bm_for(); cl = bm.loops.layers.color["Col"]
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
    face(pts if normal(pts).dot(out) > 0 else pts[::-1], key)


def loft(rings, key, caps=True):
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        ax = (centre(a) + centre(b)) * 0.5
        for j in range(n):
            k = (j + 1) % n
            q = [a[j], a[k], b[k], b[j]]
            oface(q, key, centre(q) - ax)
    if caps:
        for r, o in ((rings[0], rings[1]), (rings[-1], rings[-2])):
            oface(r, key, centre(r) - centre(o))


def box(c, size, key):
    """Axis-aligned box centred on `c`."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    lo = [V(c.x + hx, c.y - hy, c.z - hz), V(c.x + hx, c.y - hy, c.z + hz),
          V(c.x - hx, c.y - hy, c.z + hz), V(c.x - hx, c.y - hy, c.z - hz)]
    hi = [p + V(0, 2 * hy, 0) for p in lo]
    loft([lo, hi], key)


def span_box(x0, x1, y0, y1, z0, z1, key):
    box(V((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), key)


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


def bar(a, b, w, key, up=None):
    """A square member of side `w` from a to b, its faces square to `up` (default: the
    member's own frame)."""
    ax = (b - a).normalized()
    up = up or (V(0, 1, 0) if abs(ax.y) < 0.9 else V(0, 0, 1))
    e1 = ax.cross(up).normalized(); e2 = e1.cross(ax).normalized()
    h = w / 2
    ring = lambda c: [c + e1 * h + e2 * h, c - e1 * h + e2 * h, c - e1 * h - e2 * h, c + e1 * h - e2 * h]
    loft([ring(a), ring(b)], key)


def tube(path, r, n, key):
    rings, prev = [], None
    for i, p in enumerate(path):
        t = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        t.normalize()
        e1 = (prev - prev.dot(t) * t).normalized() if prev is not None else frame(t)[0]
        prev = e1; e2 = t.cross(e1)
        rings.append([p + (e1 * math.cos(math.tau * k / n) + e2 * math.sin(math.tau * k / n)) * r for k in range(n)])
    for i in range(len(path) - 1):
        a, b = rings[i], rings[i + 1]
        c = (path[i] + path[i + 1]) * 0.5
        for k in range(n):
            q = [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]
            oface(q, key, centre(q) - c)


def prism_x(profile, x0, x1, key):
    """A side-view (z, y) outline extruded across x0..x1."""
    a = [V(x0, y, z) for z, y in profile]; b = [V(x1, y, z) for z, y in profile]
    c = centre(a + b); n = len(profile)
    for j in range(n):
        k = (j + 1) % n
        q = [a[j], a[k], b[k], b[j]]
        oface(q, key, centre(q) - c)
    oface(a, key, V(-1, 0, 0)); oface(b, key, V(1, 0, 0))


# --- Lift towers and header ------------------------------------------------------------

LEVELS = [1.2, 4.0, 6.8, 9.6, 12.4, HEADER_Y0]


def tower(s):
    cx, cz, h = s * TOWER_X, TOWER_U, TOWER_HW
    # Pile cap and its piles.
    box(V(cx, 0.5, cz), (2 * h + 1.4, 1.4, 2 * h + 1.4), "concrete")
    for dx in (-1, 1):
        for dz in (-1, 1):
            cyl(V(cx + dx * (h + 0.1), -10.0, cz + dz * (h + 0.1)), V(cx + dx * (h + 0.1), -0.2, cz + dz * (h + 0.1)),
                0.42, 0.42, 8, "concrete_dark")
    # Base plates and the four legs, up to the head.
    for dx in (-1, 1):
        for dz in (-1, 1):
            x, z = cx + dx * h, cz + dz * h
            box(V(x, 1.26, z), (0.7, 0.12, 0.7), "steel_dark")
            # An H section: two flanges and the web.
            for f in (-1, 1):
                box(V(x + f * 0.15, (1.2 + TOP_Y) / 2, z), (0.06, TOP_Y - 1.2, 0.36), "green")
            box(V(x, (1.2 + TOP_Y) / 2, z), (0.26, TOP_Y - 1.2, 0.06), "green")
    # Girts round every level and X bracing in every panel, on all four faces.
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for li, y in enumerate(LEVELS):
        for c in range(4):
            a, b = corners[c], corners[(c + 1) % 4]
            pa = V(cx + a[0] * h, y, cz + a[1] * h); pb = V(cx + b[0] * h, y, cz + b[1] * h)
            bar(pa, pb, 0.24, "green", V(0, 1, 0))
            if li + 1 < len(LEVELS):
                y1 = LEVELS[li + 1]
                qa, qb = V(pa.x, y1, pa.z), V(pb.x, y1, pb.z)
                out = V(a[0] + b[0], 0, a[1] + b[1]).normalized()
                bar(pa, qb, 0.14, "green_dark", out)
                bar(pb, qa, 0.14, "green_dark", out)
    # Head: a cap plate the eagles sit on.
    box(V(cx, TOP_Y - 0.1, cz), (2 * h + 0.5, 0.2, 2 * h + 0.5), "green")
    # Counterweight guides: a channel either side of it, down the outside half.
    for dz in (-1, 1):
        box(V(s * CW_X, (2.0 + SHEAVE_Y) / 2 - 0.4, cz + dz * (CW_SIZE[2] / 2 + 0.12)), (0.2, SHEAVE_Y - 2.8, 0.14), "steel_dark")
        for y in (4.0, 6.8, 9.6, 12.4):
            bar(V(s * CW_X, y, cz + dz * (CW_SIZE[2] / 2 + 0.12)), V(s * CW_X, y, cz + dz * h), 0.1, "steel_dark")
    # The span's guides on the inside half: a pair of rails the lifting beam's shoes run in.
    gx = s * (TOWER_X - 0.25)
    for dz in (-1, 1):
        box(V(gx, 4.6, cz + dz * 0.52), (0.22, 5.2, 0.12), "steel")
    # Sheave on its axle between two bearing beams across the head.
    for dz in (-1, 1):
        bar(V(cx - h, SHEAVE_Y, cz + dz * 0.42), V(cx + h, SHEAVE_Y, cz + dz * 0.42), 0.26, "green")
        box(V(cx, SHEAVE_Y, cz + dz * 0.42), (0.36, 0.42, 0.34), "steel_dark")
    sc = V(cx, SHEAVE_Y, cz)
    cyl(sc + V(0, 0, -0.42), sc + V(0, 0, 0.42), 0.09, 0.09, 8, "steel")
    cyl(sc + V(0, 0, -0.13), sc + V(0, 0, 0.13), SHEAVE_R + 0.06, SHEAVE_R + 0.06, 20, "steel_dark")
    for k in range(6):
        a = math.tau * k / 6
        bar(sc + V(0, 0, -0.14), sc + V(math.cos(a) * SHEAVE_R, math.sin(a) * SHEAVE_R, -0.14), 0.06, "steel")
    # The cable over the top of the sheave, from the span side round to the counterweight's.
    arc = [sc + V(-s * SHEAVE_R * math.cos(math.pi * i / 8), SHEAVE_R * math.sin(math.pi * i / 8), 0) for i in range(9)]
    for dz in (-0.05, 0.05):
        tube([p + V(0, 0.03, dz) for p in arc], 0.035, 5, "cable")
    # Ladder up the outside face, with a cage from 3 m up.
    lx = cx + s * (h + 0.32)
    for dz in (-0.24, 0.24):
        box(V(lx, (1.3 + TOP_Y) / 2, cz + dz), (0.06, TOP_Y - 1.3, 0.06), "galv")
    y = 1.6
    while y < TOP_Y - 0.2:
        box(V(lx, y, cz), (0.04, 0.04, 0.48), "galv")
        y += 0.3
    y = 4.0
    while y < TOP_Y:
        hoop = [V(lx + s * (0.35 + 0.35 * math.sin(math.pi * i / 6)), y, cz + 0.36 * math.cos(math.pi * i / 6)) for i in range(7)]
        hoop = [V(lx + s * 0.0, y, cz + 0.36)] + hoop + [V(lx, y, cz - 0.36)]
        tube(hoop, 0.025, 4, "galv")
        y += 1.2
    for dz in (-0.3, 0, 0.3):
        box(V(lx + s * 0.68, (4.0 + TOP_Y) / 2, cz + dz), (0.04, TOP_Y - 4.0, 0.04), "galv")


def header():
    z0, z1 = TOWER_U - 0.55, TOWER_U + 0.55
    x0 = TOWER_X - TOWER_HW
    # Top chord: the plate the gulls line up on.
    span_box(-x0 - 0.2, x0 + 0.2, TOP_Y - 0.4, TOP_Y, z0 - 0.05, z1 + 0.05, "green")
    span_box(-x0 - 0.2, x0 + 0.2, HEADER_Y0, HEADER_Y0 + 0.32, z0, z1, "green")
    # Warren web in both faces.
    n = 8
    for z in (z0 + 0.08, z1 - 0.08):
        for i in range(n):
            xa = -x0 + 2 * x0 * i / n; xb = -x0 + 2 * x0 * (i + 1) / n
            bot = HEADER_Y0 + 0.3; top = TOP_Y - 0.38
            if i % 2 == 0:
                bar(V(xa, bot, z), V(xb, top, z), 0.16, "green_dark", V(0, 0, 1))
            else:
                bar(V(xa, top, z), V(xb, bot, z), 0.16, "green_dark", V(0, 0, 1))
            bar(V(xb, bot, z), V(xb, top, z), 0.14, "green_dark", V(0, 0, 1))
    # Gusset plates where it meets the towers.
    for s in (-1, 1):
        for z in (z0 - 0.04, z1 + 0.04):
            face([V(s * x0, HEADER_Y0 - 1.3, z), V(s * (x0 - 1.3), HEADER_Y0, z), V(s * (x0 - 1.3), TOP_Y - 0.4, z),
                  V(s * x0, TOP_Y - 0.4, z)], "green")
            face([V(s * x0, HEADER_Y0 - 1.3, z), V(s * x0, TOP_Y - 0.4, z), V(s * (x0 - 1.3), TOP_Y - 0.4, z),
                  V(s * (x0 - 1.3), HEADER_Y0, z)], "green")


# --- Transfer span ---------------------------------------------------------------------

def span():
    L = SPAN_L
    # Deck plate, asphalt on top, and the dashed centre line.
    span_box(-DECK_HW, DECK_HW, -0.32, -0.02, 0.0, L, "plate")
    span_box(-DECK_HW, DECK_HW, -0.02, 0.0, 0.0, L, "asphalt")
    z = 1.5
    while z < L - 2.0:
        span_box(-0.18, 0.18, 0.0, 0.03, z, z + 3.0, "yellow")
        z += 6.0
    # Curbs.
    for s in (-1, 1):
        span_box(s * DECK_HW, s * (DECK_HW + 0.4), -0.02, 0.3, 0.0, L, "concrete")
    # Plate girders either side: web, flanges, stiffeners, a railing on top.
    for s in (-1, 1):
        gx = s * GIRDER_X
        prof = [(0.0, -0.9), (0.0, 1.0), (L, 1.0), (L, -0.6), (L - 2.5, -1.5), (2.5, -1.5)]
        prism_x(prof, gx - 0.1, gx + 0.1, "green")
        for f, y in ((1, 1.0), (-1, -1.5)):
            span_box(gx - 0.32, gx + 0.32, y - 0.06, y + 0.06, 2.5 if f < 0 else 0.0, L - 2.5 if f < 0 else L, "green_dark")
        z = 1.1
        while z < L:
            bot = -1.5 if 2.5 < z < L - 2.5 else -0.9 if z <= 2.5 else -0.6
            span_box(gx + s * 0.1, gx + s * 0.28, bot, 0.95, z - 0.05, z + 0.05, "green_dark")
            z += 2.2
        # Hazard chevrons on the girder's seaward end.
        for k in range(3):
            y0 = 1.0 - 0.6 * (k + 1)
            span_box(gx - 0.33 * s, gx + 0.33 * s, y0, y0 + 0.3, L - 0.02, L + 0.01, "yellow" if k % 2 == 0 else "black")
        # Railing.
        z = 0.2
        while z <= L:
            span_box(gx - 0.05, gx + 0.05, 1.06, 2.1, z - 0.05, z + 0.05, "galv")
            z += 2.2
        for y in (1.6, 2.1):
            cyl(V(gx, y, 0.1), V(gx, y, L - 0.1), 0.04, 0.04, 4, "galv")
    # Floor beams under the deck between the girders, and a bottom lateral bracing X.
    z = 0.5
    while z < L:
        span_box(-GIRDER_X + 0.1, GIRDER_X - 0.1, -1.15, -0.32, z - 0.18, z + 0.18, "green_dark")
        z += 2.65
    for k in range(4):
        za, zb = 2.0 + k * (L - 4.0) / 4, 2.0 + (k + 1) * (L - 4.0) / 4
        bar(V(-GIRDER_X + 0.1, -1.1, za), V(GIRDER_X - 0.1, -1.1, zb), 0.12, "green_dark")
        bar(V(GIRDER_X - 0.1, -1.1, za), V(-GIRDER_X + 0.1, -1.1, zb), 0.12, "green_dark")
    # Shore hinge: knuckles on the trestle's pins.
    for k in range(6):
        x = -DECK_HW + 0.8 + k * (2 * DECK_HW - 1.6) / 5
        cyl(V(x - 0.35, -0.75, 0.15), V(x + 0.35, -0.75, 0.15), 0.28, 0.28, 8, "steel_dark")
    cyl(V(-DECK_HW, -0.75, 0.15), V(DECK_HW, -0.75, 0.15), 0.1, 0.1, 6, "steel")
    # Lifting beam under the tip, out into the towers' guides, the cables' lugs on top.
    span_box(-TOWER_X - 0.15, TOWER_X + 0.15, -1.45, -0.55, LIFT_Z - 0.4, LIFT_Z + 0.4, "green")
    for s in (-1, 1):
        # Guide shoes at its ends.
        span_box(s * (TOWER_X - 0.45), s * (TOWER_X - 0.05), -1.6, -0.4, LIFT_Z - 0.45, LIFT_Z + 0.45, "steel_dark")
        # Lug plates, pin and the cable's socket.
        for dz in (-0.12, 0.12):
            span_box(s * LUG[0] - 0.2, s * LUG[0] + 0.2, -0.56, LUG[1] + 0.3, LIFT_Z + dz - 0.03, LIFT_Z + dz + 0.03, "steel")
        cyl(V(s * LUG[0], LUG[1] + 0.15, LIFT_Z - 0.18), V(s * LUG[0], LUG[1] + 0.15, LIFT_Z + 0.18), 0.06, 0.06, 6, "steel_dark")
        cyl(V(s * LUG[0], LUG[1] + 0.15, LIFT_Z), V(s * LUG[0], LUG[1] + 0.75, LIFT_Z), 0.09, 0.07, 6, "steel_dark")
    # Ram pedestals by the curbs.
    for s in (-1, 1):
        y, z = RAM_A
        span_box(s * RAM_X - 0.3, s * RAM_X + 0.3, 0.0, 0.2, z - 0.5, z + 0.3, "steel_dark")
        for dx in (-0.2, 0.2):
            span_box(s * RAM_X + dx - 0.03, s * RAM_X + dx + 0.03, 0.15, y + 0.2, z - 0.25, z + 0.25, "steel")
        cyl(V(s * RAM_X - 0.25, y, z), V(s * RAM_X + 0.25, y, z), 0.05, 0.05, 6, "steel_dark")
    # Apron hinge knuckles on the tip.
    for k in range(7):
        x = -DECK_HW + 0.4 + k * (2 * DECK_HW - 0.8) / 6
        cyl(V(x - 0.3, -0.2, L - 0.05), V(x + 0.3, -0.2, L - 0.05), 0.2, 0.2, 8, "steel_dark")


# --- Apron -----------------------------------------------------------------------------

def apron():
    L = APRON_L
    hw = DECK_HW - 0.05
    # A deep heel at the hinge, then a flat-bottomed plate out to a toe bevelled on top,
    # so that it lies on the car deck rather than sinking into it.
    prism_x([(0.0, 0.0), (L - 0.3, 0.0), (L, -0.08), (L, -APRON_T), (APRON_HEEL, -APRON_T),
             (APRON_HEEL - 0.4, -0.42), (0.0, -0.42)], -hw, hw, "plate")
    # Anti-skid strips across it.
    z = 0.5
    while z < L - 0.9:
        span_box(-hw + 0.3, hw - 0.3, 0.0, 0.025, z - 0.04, z + 0.04, "steel_dark")
        z += 0.45
    # Striped toe and yellow edges.
    n = 16
    for i in range(n):
        x0 = -hw + 2 * hw * i / n; x1 = -hw + 2 * hw * (i + 1) / n
        span_box(x0, x1, 0.0, 0.03, L - 0.85, L - 0.35, "yellow" if i % 2 == 0 else "black")
    for s in (-1, 1):
        span_box(s * (hw - 0.25), s * hw, 0.0, 0.18, 0.0, L - 0.9, "yellow")
    # Hinge knuckles between the span's.
    for k in range(6):
        x = -DECK_HW + 0.4 + (k + 0.5) * (2 * DECK_HW - 0.8) / 6
        cyl(V(x - 0.3, -0.2, -0.05), V(x + 0.3, -0.2, -0.05), 0.2, 0.2, 8, "steel_dark")
    cyl(V(-DECK_HW, -0.2, -0.05), V(DECK_HW, -0.2, -0.05), 0.08, 0.08, 6, "steel")
    # Ram brackets.
    for s in (-1, 1):
        y, z = RAM_B
        span_box(s * RAM_X - 0.3, s * RAM_X + 0.3, 0.0, 0.12, z - 0.4, z + 0.4, "steel_dark")
        for dx in (-0.16, 0.16):
            span_box(s * RAM_X + dx - 0.03, s * RAM_X + dx + 0.03, 0.1, y + 0.18, z - 0.22, z + 0.22, "steel")
        cyl(V(s * RAM_X - 0.2, y, z), V(s * RAM_X + 0.2, y, z), 0.05, 0.05, 6, "steel_dark")


# --- Counterweight, cable, ram ---------------------------------------------------------

def counterweight():
    w, h, d = CW_SIZE
    box(V(0, -0.35 - h / 2, 0), (w, h, d), "concrete")
    # Steel bands, the yoke and the eye.
    for y in (-0.6, -0.35 - h + 0.25):
        box(V(0, y, 0), (w + 0.06, 0.18, d + 0.06), "steel_dark")
    for dz in (-1, 1):
        box(V(0, -0.35 - h / 2, dz * (d / 2 + 0.06)), (0.16, h, 0.1), "steel_dark")
        box(V(0, -0.35 - h / 2, dz * (d / 2 + 0.13)), (0.3, h - 0.4, 0.04), "steel")  # guide shoe
    box(V(0, -0.38, 0), (0.3, 0.1, d * 0.8), "steel_dark")
    for dz in (-0.06, 0.06):
        box(V(0, -0.18, dz), (0.24, 0.36, 0.03), "steel_dark")


def cable():
    for dz in (-0.05, 0.05):
        cyl(V(0, 0, dz), V(0, -1, dz), 0.035, 0.035, 5, "cable", 0.0)


def rambody():
    for dx in (-0.06, 0.06):
        box(V(dx, 0, 0.0), (0.03, 0.24, 0.24), "steel_dark")
    cyl(V(0, 0, 0.1), V(0, 0, 0.3), 0.08, 0.17, 8, "green_dark")
    cyl(V(0, 0, 0.3), V(0, 0, RAM_BODY), 0.17, 0.17, 8, "green")
    cyl(V(0, 0, RAM_BODY - 0.15), V(0, 0, RAM_BODY), 0.19, 0.19, 8, "green_dark")
    cyl(V(0, 0.14, 0.6), V(0, 0.14, RAM_BODY - 0.3), 0.025, 0.025, 4, "black")   # hose


def ramrod():
    box(V(0, 0, 0.0), (0.1, 0.22, 0.22), "steel_dark")
    cyl(V(0, 0, 0.1), V(0, 0, RAM_ROD), 0.07, 0.07, 8, "chrome")


# --- Build -----------------------------------------------------------------------------

def build():
    for bm in BMS.values(): bm.free()
    BMS.clear()
    PART[0] = "towers"; tower(-1); tower(1); header()
    PART[0] = "span"; span()
    PART[0] = "apron"; apron()
    PART[0] = "counterweight"; counterweight()
    PART[0] = "cable"; cable()
    PART[0] = "rambody"; rambody()
    PART[0] = "ramrod"; ramrod()
    obs = []
    for role in PARTS:
        bm = BMS[role]
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        old = bpy.data.meshes.get("slip_" + role)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new("slip_" + role); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(role, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


_here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    (os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art")
built = build()
_glb = os.path.normpath(os.path.join(_here, "..", "assets", "models", "slip_mid.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
result = {o.name: len(o.data.polygons) for o in built}
print("slip_mid:", result, "total", sum(result.values()))
if bpy.app.background and not bpy.data.filepath:
    for o in list(bpy.data.objects):
        if o not in built: bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(_here, "slip_mid.blend"))
