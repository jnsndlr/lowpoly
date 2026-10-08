# Builds the road vehicles in Blender (run inside Blender: exec(open(path).read())) and
# exports them to assets/models/vehicles.glb (glTF, +Y up, vertex colours, flat shaded),
# plus scripts/world/vehicle_data.gd (each variant's size and lamp positions).
# Game frame: +Z is the front, +Y up, ground at y = 0, centred on the footprint, real
# metres (Blender: front to -Y, Z up).
#
# Each model is a generator driven by a parameter dict, and each variant is a named set
# of parameters over the model's defaults, so a new variant costs a few lines. The
# sedans follow the user's reference sheet: a 2010s mid-size, a rally sport sedan, an
# 80s box, a 90s mid-size, a chrome-grille land yacht, an EV with a light bar, a
# compact and an 80s German executive.
#
# A sedan is a lofted lower body (sections of sill, crease, shoulder and crown, the sill
# lifted round the wheel arches), a lofted greenhouse on it (windscreen, roof, rear
# window; flat sides carrying the window decals), wheels, and details laid on as thin
# decals over the surfaces: lamps, grilles, seams, trim.
#
# Parts per variant, named <model>_<variant>_<role>: `body` (painted per car in the
# game), `head` and `tail` (lamp glass, lit at night) and `fixed` (everything else, in
# its own colours).
import bpy, bmesh, math, os
from mathutils import Vector

ART = os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art"

PAL = {
    "body": (0.6, 0.6, 0.6),  # set per variant for the preview; the game repaints it
    "tyre": (0.07, 0.07, 0.075), "black": (0.05, 0.05, 0.055), "trim": (0.11, 0.11, 0.12),
    "seam": (0.04, 0.04, 0.045), "glass": (0.3, 0.42, 0.53), "chrome": (0.8, 0.82, 0.84),
    "silver": (0.66, 0.68, 0.7), "gunmetal": (0.2, 0.21, 0.23), "grey": (0.42, 0.43, 0.45),
    "plate": (0.9, 0.9, 0.86), "caliper": (0.75, 0.08, 0.06), "amber": (0.95, 0.55, 0.1),
    "reverse": (0.88, 0.88, 0.86), "under": (0.08, 0.08, 0.09),
    "head": (0.97, 0.94, 0.82), "tail": (0.72, 0.05, 0.04),
}
ROLES = ("body", "head", "tail")


def V(x, y, z): return Vector((x, y, z))
def G(p): return Vector((p.x, -p.z, p.y))
def lerp(a, b, t): return a + (b - a) * t
def mx(p): return V(-p.x, p.y, p.z)


coll = bpy.data.collections.get("Vehicles") or bpy.data.collections.new("Vehicles")
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
    # (bmesh stores the byte colour as given, and the exporter reads it as sRGB.)
    for l in f.loops: l[cl] = (*PAL[key], 1.0)


def normal(pts):
    n = Vector()
    for i in range(len(pts)):
        n += pts[i].cross(pts[(i + 1) % len(pts)])
    return n


def centre(pts): return sum(pts, Vector()) / len(pts)


def poly(pts, key, out, both=False):
    """A face wound to face `out`; `both` adds its mirror image across x = 0."""
    face(pts if normal(pts).dot(out) > 0 else pts[::-1], key)
    if both:
        poly([mx(p) for p in pts], key, mx(out))


def loft(rings, key, closed_ring=True, caps=True):
    """Quads between successive rings (same vertex count, same direction), wound outward
    from the rings' centres. `key` is a palette key or fn(i, j) -> key."""
    n, quads = len(rings[0]), []
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        ax = (centre(a) + centre(b)) * 0.5
        for j in range(n if closed_ring else n - 1):
            k = (j + 1) % n
            quads.append((i, j, [a[j], a[k], b[k], b[j]], ax))
    s = sum(normal(q).dot(centre(q) - ax) for _, _, q, ax in quads)
    for i, j, q, _ in quads:
        face(q if s > 0 else q[::-1], key(i, j) if callable(key) else key)
    if caps and closed_ring:
        for r, o in ((rings[0], rings[1]), (rings[-1], rings[-2])):
            face(r if normal(r).dot(centre(r) - centre(o)) > 0 else r[::-1], key if not callable(key) else "black")


def box(c, size, key):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    r = lambda y: [V(c.x + hx, y, c.z - hz), V(c.x + hx, y, c.z + hz), V(c.x - hx, y, c.z + hz), V(c.x - hx, y, c.z - hz)]
    loft([r(c.y - hy), r(c.y + hy)], key)


def disc_pts(c, r, n, a0=0.0):
    """Points round a circle in the y-z plane (a wheel's face)."""
    return [c + V(0, r * math.cos(a0 + math.tau * i / n), r * math.sin(a0 + math.tau * i / n)) for i in range(n)]


# --- Sedan ---------------------------------------------------------------------------

SEDAN = dict(
    L=4.85, W=1.84, H=1.45, wb=2.76, fo=0.97,         # length, width, height, wheelbase, front overhang
    r=0.33, tw=0.22, arch=0.05,                        # tyre radius and width, arch clearance
    sill=0.2, bump_bot=0.24, tuck=0.05,                # sill and bumper bottoms, how far the sill tucks in
    nose_top=0.74, nose_set=0.16, hood_front=0.79,     # fascia top, run back to the hood proper
    belt=0.92, belt_rise=0.04, crease=0.8,             # beltline (rising rearward), side crease
    deck_lift=0.02, tail_top=0.94, tail_set=0.14,      # trunk lid, rear fascia top
    hood=1.6, ws=0.85, roof=1.05, rw=0.6,              # runs: tip to cowl, windscreen, roof, rear window
    df=0.03, dr=0.05, crown=0.04, ws_bulge=0.0, rw_bulge=0.0,
    tumble=0.2, sh_in=0.1, gh_in=0.03,                 # greenhouse lean-in, shoulder inset
    cf=0.14, cfl=0.45, cr=0.1, crl=0.35, flare=0.0,    # plan rounding of the corners, arch flares
    a_w=0.07, c_w=0.2, rail=0.07, b_at=0.52, quarter=0.0,
    frame="black", roof_key="body", mirror="body",
    lamp=dict(style="swept", x0=0.34, x1=0.8, y0=0.6, y1=0.73, wrap=0.38),
    grille=dict(style="trapezoid", w=0.3, y0=0.52, y1=0.7),
    intake=dict(w=0.52, y0=0.26, y1=0.42, fogs=True),
    tail=dict(style="wrap", x0=0.4, x1=0.85, y0=0.79, y1=0.92, wrap=0.3),
    bumper="body", rub=False, sill_key=None, plate_y=0.6,
    wheel="alloy5", scoop=False, wing=False,
)

SEDANS = {
    # 2010s mid-size (the white Accord-alike).
    "modern": dict(paint=(0.88, 0.86, 0.8)),
    # Rally sport sedan: flared arches, hood scoop, wing, dark wheels, red calipers.
    "sport": dict(L=4.6, W=1.8, H=1.44, wb=2.65, fo=0.94, r=0.34, sill=0.17, bump_bot=0.15,
                  nose_top=0.72, nose_set=0.18, hood_front=0.78, belt=0.92, crease=0.79,
                  hood=1.52, ws=0.8, roof=1.0, rw=0.55, flare=0.035, cf=0.12,
                  lamp=dict(style="swept", x0=0.4, x1=0.8, y0=0.6, y1=0.71, wrap=0.36),
                  grille=dict(style="hex", w=0.3, y0=0.5, y1=0.68),
                  intake=dict(w=0.64, y0=0.17, y1=0.44, fogs=True, vents=True),
                  tail=dict(style="wrap", x0=0.46, x1=0.8, y0=0.8, y1=0.91, wrap=0.24),
                  wheel="sport", scoop=True, wing=True, paint=(0.1, 0.3, 0.75)),
    # 80s box: upright fascia, black bumpers and rubbing strip, square lamps.
    "boxy": dict(L=4.62, W=1.7, H=1.38, wb=2.58, fo=0.94, r=0.3, sill=0.24, bump_bot=0.27,
                 nose_top=0.76, nose_set=0.08, hood_front=0.79, belt=0.9, belt_rise=0.0, crease=0.76,
                 deck_lift=0.0, tail_top=0.9, tail_set=0.07,
                 hood=1.42, ws=0.58, roof=1.28, rw=0.44, df=0.02, dr=0.03, crown=0.02,
                 tumble=0.12, sh_in=0.05, cf=0.04, cfl=0.2, cr=0.03, crl=0.2, c_w=0.16,
                 lamp=dict(style="rect", x0=0.42, x1=0.74, y0=0.6, y1=0.72, wrap=0.0),
                 grille=dict(style="slats", w=0.36, y0=0.58, y1=0.72),
                 intake=None, tail=dict(style="rect", x0=0.4, x1=0.78, y0=0.66, y1=0.84, wrap=0.1),
                 bumper="black", rub=True, plate_y=0.55, mirror="black", wheel="steel",
                 paint=(0.78, 0.18, 0.1)),
    # Late-90s mid-size: soft corners, narrow chrome grille, a dark lower lip.
    "nineties": dict(L=4.8, W=1.78, H=1.41, wb=2.72, fo=0.98, r=0.31, sill=0.21, bump_bot=0.24,
                     nose_top=0.71, nose_set=0.16, hood_front=0.76, belt=0.91, belt_rise=0.03, crease=0.78,
                     hood=1.55, ws=0.8, roof=1.1, rw=0.56, cf=0.12, cfl=0.42,
                     lamp=dict(style="wedge", x0=0.34, x1=0.78, y0=0.6, y1=0.7, wrap=0.25),
                     grille=dict(style="band", w=0.3, y0=0.6, y1=0.69),
                     intake=dict(w=0.55, y0=0.27, y1=0.36, fogs=False),
                     tail=dict(style="wrap", x0=0.4, x1=0.8, y0=0.78, y1=0.89, wrap=0.22),
                     wheel="alloy6", paint=(0.2, 0.42, 0.26)),
    # Chrome-grille land yacht: long, square, formal roof, chrome everywhere.
    "luxury": dict(L=5.35, W=1.95, H=1.46, wb=3.0, fo=1.05, r=0.34, sill=0.22, bump_bot=0.24,
                   nose_top=0.8, nose_set=0.08, hood_front=0.84, belt=0.93, belt_rise=0.01, crease=0.82,
                   deck_lift=0.0, tail_top=0.93, tail_set=0.08,
                   hood=1.78, ws=0.68, roof=1.4, rw=0.42, df=0.02, dr=0.02, crown=0.03,
                   tumble=0.14, sh_in=0.06, cf=0.05, cfl=0.25, cr=0.04, crl=0.25, c_w=0.26,
                   frame="chrome",
                   lamp=dict(style="rect", x0=0.42, x1=0.88, y0=0.64, y1=0.76, wrap=0.12),
                   grille=dict(style="waterfall", w=0.3, y0=0.5, y1=0.78),
                   intake=None, tail=dict(style="rect", x0=0.5, x1=0.9, y0=0.7, y1=0.86, wrap=0.08),
                   bumper="chrome", sill_key="grey", plate_y=0.55, wheel="multi",
                   paint=(0.78, 0.7, 0.56)),
    # EV: smooth nose with a light bar, black roof, fastback, aero wheels.
    "ev": dict(L=4.72, W=1.86, H=1.42, wb=2.88, fo=0.88, r=0.35, sill=0.18, bump_bot=0.18,
               nose_top=0.66, nose_set=0.24, hood_front=0.74, belt=0.94, belt_rise=0.03, crease=0.8,
               tail_top=0.96, hood=1.34, ws=0.95, roof=0.92, rw=0.86, rw_bulge=0.05, ws_bulge=0.02,
               crown=0.05, cf=0.18, cfl=0.5, roof_key="black", mirror="black",
               lamp=dict(style="bar", x0=0.5, x1=0.82, y0=0.54, y1=0.6, wrap=0.3),
               grille=None, intake=dict(w=0.46, y0=0.22, y1=0.34, fogs=False, vents=True),
               tail=dict(style="bar", x0=0.0, x1=0.85, y0=0.88, y1=0.93, wrap=0.2),
               wheel="aero", paint=(0.92, 0.72, 0.15)),
    # Compact: short and tall, small grille, hubcaps.
    "compact": dict(L=4.42, W=1.72, H=1.48, wb=2.6, fo=0.88, r=0.3, sill=0.2, bump_bot=0.24,
                    nose_top=0.72, nose_set=0.18, hood_front=0.78, belt=0.94, belt_rise=0.04, crease=0.8,
                    tail_top=0.97, hood=1.33, ws=0.86, roof=1.0, rw=0.5, cf=0.15, cfl=0.42,
                    lamp=dict(style="swept", x0=0.32, x1=0.76, y0=0.58, y1=0.71, wrap=0.36),
                    grille=dict(style="trapezoid", w=0.26, y0=0.54, y1=0.68),
                    intake=dict(w=0.46, y0=0.28, y1=0.42, fogs=True),
                    tail=dict(style="wrap", x0=0.38, x1=0.78, y0=0.81, y1=0.94, wrap=0.24),
                    wheel="hubcap", paint=(0.3, 0.62, 0.68)),
    # 80s German executive: upright chrome grille, slab sides, chrome trim, dark cladding.
    "exec": dict(L=4.75, W=1.74, H=1.42, wb=2.8, fo=0.9, r=0.31, sill=0.22, bump_bot=0.25,
                 nose_top=0.76, nose_set=0.1, hood_front=0.79, belt=0.91, belt_rise=0.01, crease=0.77,
                 deck_lift=0.0, tail_top=0.92, tail_set=0.08,
                 hood=1.48, ws=0.72, roof=1.2, rw=0.5, df=0.02, dr=0.03, crown=0.03,
                 tumble=0.14, sh_in=0.05, cf=0.05, cfl=0.22, cr=0.04, crl=0.22, c_w=0.18,
                 frame="chrome",
                 lamp=dict(style="rect", x0=0.32, x1=0.74, y0=0.62, y1=0.74, wrap=0.08),
                 grille=dict(style="upright", w=0.2, y0=0.52, y1=0.78),
                 intake=None, tail=dict(style="ribbed", x0=0.38, x1=0.8, y0=0.66, y1=0.86, wrap=0.08),
                 bumper="clad", sill_key="trim", plate_y=0.55, wheel="multi",
                 paint=(0.1, 0.1, 0.11)),
}


class Sedan:
    def __init__(s, p):
        s.p = p
        L = p["L"]
        s.zF, s.zR = L / 2, -L / 2
        s.zfa = s.zF - p["fo"]; s.zra = s.zfa - p["wb"]
        s.zc = s.zF - p["hood"]; s.zw = s.zc - p["ws"]; s.zr = s.zw - p["roof"]; s.zd = s.zr - p["rw"]
        s.R = p["r"] + p["arch"]
        s.stations = s._stations()

    # Profiles along the car.
    def belt(s, z):
        p = s.p
        return p["belt"] + p["belt_rise"] * min(max((s.zc - z) / (s.zc - s.zd), 0.0), 1.0)

    def top(s, z):
        """Height of the lower body's top: fascia, hood, beltline, trunk, rear fascia."""
        p = s.p
        zn = s.zF - p["nose_set"]; zt = s.zR + p["tail_set"]
        deck_end = s.belt(s.zd) + p["deck_lift"]
        if z >= zn:
            t = (s.zF - z) / p["nose_set"]
            return p["nose_top"] + (p["hood_front"] - p["nose_top"]) * (1 - (1 - t) ** 2)
        if z >= s.zc:
            return lerp(s.belt(s.zc), p["hood_front"], (z - s.zc) / (zn - s.zc))
        if z >= s.zd:
            return s.belt(z)
        if z >= zt:
            return lerp(deck_end, s.belt(s.zd), (z - zt) / (s.zd - zt))
        t = (z - s.zR) / p["tail_set"]
        return p["tail_top"] + (deck_end - p["tail_top"]) * (1 - (1 - t) ** 2)

    def bottom(s, z):
        p = s.p
        y = p["sill"]
        d = min(s.zF - z, z - s.zR)
        if d < 0.3: y = lerp(p["bump_bot"], p["sill"], d / 0.3)
        for za in (s.zfa, s.zra):
            dz = abs(z - za)
            if dz <= s.R + 1e-6:
                y = max(y, p["r"] + math.sqrt(max(0.0, s.R * s.R - dz * dz)))
        return y

    def crease(s, z):
        p = s.p
        y = p["crease"] + p["belt_rise"] * min(max((s.zc - z) / (s.zc - s.zd), 0.0), 1.0)
        return max(min(y, s.top(z) - 0.035), s.bottom(z) + 0.05)

    def hw(s, z, flare=True):
        p = s.p
        w = p["W"] / 2
        if z > s.zF - p["cfl"]:
            u = (z - (s.zF - p["cfl"])) / p["cfl"]; w -= p["cf"] * (1 - math.sqrt(max(0.0, 1 - u * u)))
        if z < s.zR + p["crl"]:
            u = ((s.zR + p["crl"]) - z) / p["crl"]; w -= p["cr"] * (1 - math.sqrt(max(0.0, 1 - u * u)))
        if flare and p["flare"]:
            for za in (s.zfa, s.zra):
                w += p["flare"] * max(0.0, 1 - ((z - za) / (s.R + 0.3)) ** 2)
        return w

    def hwg(s):
        return s.p["W"] / 2 - s.p["sh_in"] - s.p["gh_in"]

    def sec(s, z):
        """The right half of the lower body's section: sill, crease, shoulder, crown."""
        p = s.p
        w, yt, yb = s.hw(z), s.top(z), s.bottom(z)
        tuck = p["tuck"] * min(max((p["r"] + 0.05 - yb) / (p["r"] + 0.05 - p["sill"]), 0.0), 1.0)
        return [V(w - tuck, yb, z), V(w, s.crease(z), z), V(w - p["sh_in"], yt, z),
                V((w - p["sh_in"]) * 0.5, yt + p["crown"] * 0.75, z), V(0, yt + p["crown"], z)]

    def ring(s, z):
        r = s.sec(z)
        return r + [mx(q) for q in r[-2::-1]]

    def _stations(s):
        p = s.p
        zs = [s.zF - p["nose_set"] * t for t in (0, 0.1, 0.3, 0.6, 1.0)]
        zs += [s.zR + p["tail_set"] * t for t in (0, 0.15, 0.45, 1.0)]
        zs += [s.zF - p["cfl"] * t for t in (0.5, 1.0)] + [s.zR + p["crl"] * t for t in (0.5, 1.0)]
        for za in (s.zfa, s.zra):
            zs += [za + s.R * math.sin(math.radians(a)) for a in (-90, -60, -30, 0, 30, 60, 90)]
            zs += [za - s.R - 0.04, za + s.R + 0.04]
        zs += [s.zc, s.zd, (s.zc + s.zd) / 2, (s.zF - p["nose_set"] + s.zc) / 2]
        zs = sorted(set(round(z, 4) for z in zs if s.zR <= z <= s.zF), reverse=True)
        out = [zs[0]]
        for z in zs[1:]:
            if out[-1] - z > 0.02 or z == zs[-1]: out.append(z)
        return out

    # Surface points for decals.
    def side_at(s, z, y):
        """Point on the right side (sill to shoulder) at height y, and its outward normal."""
        q = s.sec(z)[:3]
        for a, b in ((q[0], q[1]), (q[1], q[2])):
            if a.y - 1e-6 <= y <= b.y + 1e-6:
                t = (y - a.y) / (b.y - a.y) if b.y - a.y > 1e-6 else 0.0
                d = b - a
                return a.lerp(b, t), V(d.y, -d.x, 0).normalized()
        return None

    def side_decal(s, z0, z1, y0, y1, key, eps=0.006):
        """A band over the right and left sides from z0 down to z1, y0 to y1, clipped to the
        side at each station (so it stops at the wheel arches)."""
        z0, z1 = max(z0, z1), min(z0, z1)
        zs = [z0] + [z for z in s.stations if z1 < z < z0] + [z1]
        for za, zb in zip(zs, zs[1:]):
            cols = []
            for z in (za, zb):
                q = s.sec(z)
                lo, hi = max(y0, q[0].y + 0.002), min(y1, q[2].y - 0.002)
                cols.append((z, lo, hi, (q[1].y)))
            if any(c[2] - c[1] < 0.004 for c in cols): continue
            ycr = (cols[0][3] + cols[1][3]) / 2
            fr = [0.0, 1.0]
            lo = max(c[1] for c in cols); hi = min(c[2] for c in cols)
            if lo < ycr < hi:
                fr = [0.0, None, 1.0]
            for k in range(len(fr) - 1):
                def at(c, f):
                    z, l, h, cy = c
                    y = cy if f is None else lerp(l, h, f)
                    return s.side_at(z, y)
                cA = [at(cols[0], fr[k]), at(cols[0], fr[k + 1])]
                cB = [at(cols[1], fr[k]), at(cols[1], fr[k + 1])]
                if None in cA or None in cB: continue
                quad = [cA[0], cB[0], cB[1], cA[1]]
                n = sum((c[1] for c in quad), Vector()).normalized()
                poly([c[0] + c[1] * eps for c in quad], key, n, both=True)

    def front(s, pts, key, eps=0.008, both=True, rear=False):
        """A decal on the front (or rear) fascia from (x, y) points."""
        z = s.zR - eps if rear else s.zF + eps
        q = s.sec(s.zR if rear else s.zF)[:3]

        def edge_x(y):
            # The fascia's half width at height y, a hair inside its outline.
            for a, b in ((q[0], q[1]), (q[1], q[2])):
                if a.y - 1e-6 <= y <= b.y + 1e-6:
                    return lerp(a.x, b.x, (y - a.y) / (b.y - a.y) if b.y - a.y > 1e-6 else 0.0) - 0.012
            return q[2].x - 0.012 if y > q[2].y else q[0].x - 0.012
        pts = [(max(min(x, edge_x(y)), -edge_x(y)), min(y, q[2].y - 0.004)) for x, y in pts]
        poly([V(x, y, z) for x, y in pts], key, V(0, 0, -1 if rear else 1), both)


def rect2(x0, x1, y0, y1): return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def sedan(p):
    s = Sedan(p)
    PAL["body"] = p["paint"]
    zF, zR = s.zF, s.zR

    # Lower body, its fascias as end caps.
    rings = [s.ring(z) for z in s.stations]
    loft(rings, "body", closed_ring=False, caps=False)
    for r, out in ((rings[0], V(0, 0, 1)), (rings[-1], V(0, 0, -1))):
        poly(r, "body", out)
    # Underside and wheel wells.
    hw0 = p["W"] / 2
    box(V(0, p["sill"] - 0.02, (zF + zR) / 2), (2 * hw0 - 0.25, 0.06, p["L"] - 0.5), "under")
    for za in (s.zfa, s.zra):
        # (inside the tyres' inner faces, so it can't swallow the rims)
        wx = s.hw(za) - p["tuck"] - 0.025 - p["tw"] - 0.01
        box(V(0, (p["r"] + s.R + p["sill"]) / 2, za), (2 * wx, s.R + p["r"] - p["sill"], 2 * s.R + 0.02), "black")

    greenhouse(s)
    lamps_and_face(s)
    tail_end(s)
    side_details(s)
    for za in (s.zfa, s.zra):
        for sx in (1, -1):
            wheel(s, za, sx)
    extras(s)
    return s


def greenhouse(s):
    p = s.p
    H, xb, tum = p["H"], s.hwg(), p["tumble"]

    def x_at(z, y):
        yb = s.belt(z)
        return xb - tum * (y - yb) / (H - yb)

    def gring(z, y, crown):
        yb = s.belt(z)
        xt = x_at(z, y)
        r = [V(xb, yb, z), V(xt, y, z), V(xt * 0.5, y + crown * 0.7, z), V(0, y + crown, z)]
        return r + [mx(q) for q in r[-2::-1]]

    tops = [(s.zc, s.belt(s.zc), 0.0, "ws")]
    if p["ws_bulge"]:
        tops.append((lerp(s.zc, s.zw, 0.5) + p["ws_bulge"], lerp(s.belt(s.zc), H - p["df"], 0.5) + p["ws_bulge"],
                     p["crown"] * 0.5, "ws"))
    tops += [(s.zw, H - p["df"], p["crown"], "roof"), ((s.zw + s.zr) / 2, H, p["crown"], "roof"),
             (s.zr, H - p["dr"], p["crown"], "rw")]
    if p["rw_bulge"]:
        tops.append((lerp(s.zr, s.zd, 0.5) - p["rw_bulge"] * 0.4, lerp(H - p["dr"], s.belt(s.zd), 0.5) + p["rw_bulge"],
                     p["crown"] * 0.6, "rw"))
    tops.append((s.zd, s.belt(s.zd), 0.0, None))
    rings = [gring(z, y, c) for z, y, c, _ in tops]

    def key(i, j):
        if j in (0, 5): return "body"
        kind = tops[i][3]
        return p["roof_key"] if kind == "roof" else "glass"
    loft(rings, key, closed_ring=False, caps=False)

    # Side windows: the opening inset from the side's outline, framed, a black B pillar.
    k = tum / (H - p["belt"])
    n = V(1, k, 0).normalized()
    side = [(z, y) for z, y, _, _ in tops]
    fi = next(i for i, t in enumerate(tops) if t[3] == "roof")
    ri = max(i for i, t in enumerate(tops) if t[3] == "roof") + 1
    front_edge, rear_edge = side[:fi + 1], side[ri - 1:]

    def z_on(edge, y):
        for (za, ya), (zb, yb) in zip(edge, edge[1:]):
            lo, hi = min(ya, yb), max(ya, yb)
            if lo - 1e-6 <= y <= hi + 1e-6:
                return lerp(za, zb, (y - ya) / (yb - ya)) if abs(yb - ya) > 1e-6 else za
        return edge[0][0] if abs(y - edge[0][1]) < abs(y - edge[-1][1]) else edge[-1][0]

    def opening(inset):
        a, c, rail = p["a_w"] - inset, p["c_w"] - inset, p["rail"] - inset
        y0 = p["belt"] + 0.03 - inset
        yf, yr = tops[fi][1] - rail, tops[ri - 1][1] - rail
        pts = [(z_on(front_edge, y0) - a, y0), (z_on(front_edge, yf) - a, yf)]
        pts += [(z, y - rail) for z, y, _, kd in tops[fi + 1:ri - 1]]
        yb = s.belt(s.zd) + 0.03 - inset
        pts += [(z_on(rear_edge, yr) + c, yr), (z_on(rear_edge, yb) + c, yb)]
        return pts

    def put(pts, key, eps):
        poly([V(x_at(z, y), y, z) + n * eps for z, y in pts], key, n, both=True)

    put(opening(-0.0 + 0.02 if p["frame"] == "chrome" else 0.012), p["frame"], 0.004)
    win = opening(0.0)
    put(win, "glass", 0.008)
    zB = lerp(win[0][0], win[-1][0], p["b_at"])
    pillars = [(zB, 0.05)]
    if p["quarter"]:
        pillars.append((lerp(win[0][0], win[-1][0], p["quarter"]), 0.025))
    for zp, w in pillars:
        put([(zp + w, s.belt(zp) + 0.02), (zp - w, s.belt(zp) + 0.02),
             (zp - w, H - p["rail"] - 0.005), (zp + w, H - p["rail"] - 0.005)], "black", 0.012)
    s.zB = zB
    s.win = win


def lamps_and_face(s):
    p = s.p
    zF = s.zF
    hwt = s.hw(zF) - p["sh_in"]
    lp = p["lamp"]
    s.head = V((lp["x0"] + lp["x1"]) / 2, (lp["y0"] + lp["y1"]) / 2, zF)
    st = lp["style"]
    x0, x1, y0, y1 = lp["x0"], min(lp["x1"], hwt + p["sh_in"] - 0.03), lp["y0"], lp["y1"]
    if st == "rect":
        s.front([(x0 - 0.015, y0 - 0.015), (x1 + 0.01, y0 - 0.015), (x1 + 0.01, y1 + 0.012), (x0 - 0.015, y1 + 0.012)], "chrome" if p["frame"] == "chrome" else "trim", 0.006)
        s.front(rect2(x0, x1, y0, y1), "head")
        s.front(rect2(x1 - 0.06, x1, y0, y1), "amber", 0.01)
    elif st == "swept":
        s.front([(x0, y0 + 0.03), (x1, y0), (x1, y1), (x0 + 0.04, y1 - 0.025)], "head")
        s.front([(x0 + 0.06, y0 + 0.035), (x0 + 0.14, y0 + 0.03), (x0 + 0.14, y1 - 0.04), (x0 + 0.08, y1 - 0.035)], "trim", 0.011)
    elif st == "wedge":
        s.front([(x0, y0 + 0.01), (x1, y0), (x1, y1), (x0, y1 - 0.02)], "head")
        s.front(rect2(x1 - 0.07, x1, y0, y1), "amber", 0.01)
    elif st == "bar":
        yb0, yb1 = p["nose_top"] - 0.055, p["nose_top"] - 0.03
        s.front([(-hwt, yb0), (hwt, yb0), (hwt, yb1), (-hwt, yb1)], "head", both=False)
        s.front([(x0, y0), (x1, y0 + 0.01), (x1, y1), (x0 + 0.02, y1)], "head")
        s.head = V((x0 + x1) / 2, (y0 + y1) / 2, zF)
    if lp["wrap"] > 0:
        s.side_decal(zF, zF - lp["wrap"], y0 if st != "bar" else p["nose_top"] - 0.055, y1 if st != "bar" else p["nose_top"] - 0.03, "head", 0.006)

    g = p["grille"]
    if g:
        gs, w, gy0, gy1 = g["style"], g["w"], g["y0"], g["y1"]
        if gs == "trapezoid":
            s.front([(0, gy0), (w * 0.85, gy0), (w, gy1), (0, gy1)], "black")
            s.front([(0, gy1 - 0.03), (w, gy1 - 0.03), (w, gy1), (0, gy1)], "chrome", 0.012)
            s.front(rect2(0, 0.05, (gy0 + gy1) / 2 - 0.03, (gy0 + gy1) / 2 + 0.03), "silver", 0.014)
        elif gs == "hex":
            s.front([(0, gy0), (w * 0.8, gy0), (w, gy1 - 0.03), (w * 0.9, gy1), (0, gy1)], "black")
            s.front(rect2(0, 0.045, (gy0 + gy1) / 2 - 0.025, (gy0 + gy1) / 2 + 0.025), "silver", 0.012)
        elif gs == "slats":
            s.front(rect2(0, w, gy0, gy1), "black")
            for i in range(4):
                yy = lerp(gy0, gy1, (i + 0.6) / 4.4)
                s.front(rect2(0, w - 0.02, yy, yy + 0.012), "trim", 0.012)
        elif gs == "band":
            s.front([(0, gy0), (w * 0.85, gy0), (w, gy1), (0, gy1)], "black")
            s.front([(0, gy0 + 0.035), (w * 0.9, gy0 + 0.035), (w * 0.93, gy0 + 0.05), (0, gy0 + 0.05)], "chrome", 0.012)
            s.front(rect2(0, 0.04, gy0 + 0.02, gy1 - 0.015), "silver", 0.014)
        elif gs in ("waterfall", "upright"):
            # A chrome grille shell standing proud of the fascia, bars across or down it.
            d = 0.06
            box(V(0, (gy0 + gy1) / 2, s.zF + d / 2 - 0.01), (2 * w, gy1 - gy0, d), "chrome")
            z = s.zF + d - 0.01
            poly([V(x, y, z + 0.004) for x, y in rect2(-w + 0.035, w - 0.035, gy0 + 0.03, gy1 - 0.03)], "black", V(0, 0, 1))
            if gs == "waterfall":
                for i in range(9):
                    xx = lerp(-w + 0.06, w - 0.06, i / 8)
                    poly([V(x, y, z + 0.008) for x, y in rect2(xx - 0.008, xx + 0.008, gy0 + 0.03, gy1 - 0.03)], "chrome", V(0, 0, 1))
            else:
                for i in range(4):
                    yy = lerp(gy0 + 0.05, gy1 - 0.06, i / 3)
                    poly([V(x, y, z + 0.008) for x, y in rect2(-w + 0.035, w - 0.035, yy, yy + 0.012)], "chrome", V(0, 0, 1))
                poly([V(x, y, z + 0.01) for x, y in rect2(-0.012, 0.012, gy0 + 0.03, gy1 - 0.03)], "chrome", V(0, 0, 1))
            # Hood ornament / star.
            box(V(0, s.top(s.zF - 0.02) + 0.035, s.zF - 0.03), (0.02, 0.07, 0.02), "chrome")

    it = p["intake"]
    if it:
        s.front([(0, it["y0"]), (it["w"], it["y0"]), (it["w"] - 0.04, it["y1"]), (0, it["y1"])], "black")
        if it.get("fogs"):
            fx = min(it["w"] + 0.1, hwt - 0.05)
            s.front([(fx - 0.07, it["y0"] + 0.02), (fx + 0.05, it["y0"] + 0.02), (fx + 0.05, it["y1"] - 0.02), (fx - 0.07, it["y1"] - 0.02)], "black")
        if it.get("vents"):
            vx = hwt + p["sh_in"] - 0.05
            s.front([(vx - 0.12, it["y0"] + 0.02), (vx, it["y0"] + 0.02), (vx, it["y1"]), (vx - 0.08, it["y1"])], "black")
    # Front plate on its holder (Washington wants one front and back).
    py = (it["y0"] + it["y1"]) / 2 if it else p["plate_y"]
    if p["bumper"] in ("black", "chrome", "clad"):
        py = p["plate_y"] - 0.12
    s.front(rect2(-0.16, 0.16, py - 0.07, py + 0.07), "plate", 0.03 if p["bumper"] != "body" else 0.016, both=False)

    bumpers(s, s.zF, 1)


def bumpers(s, zt, sgn):
    p = s.p
    bs = p["bumper"]
    hwt = s.hw(zt)
    rear = sgn < 0
    if bs == "body":
        # A dark lower lip.
        s.front(rect2(-hwt + 0.06, hwt - 0.06, p["bump_bot"], p["bump_bot"] + 0.05), "black", 0.006, both=False, rear=rear)
        return
    if bs == "black":
        y0, y1, d, key = p["bump_bot"] + 0.02, p["bump_bot"] + 0.2, 0.07, "black"
    elif bs == "chrome":
        y0, y1, d, key = p["bump_bot"] + 0.04, p["bump_bot"] + 0.2, 0.06, "chrome"
    else:  # clad: dark plastic with a chrome strip
        y0, y1, d, key = p["bump_bot"] + 0.02, p["bump_bot"] + 0.24, 0.06, "trim"
    box(V(0, (y0 + y1) / 2, zt + sgn * (d / 2 - 0.01)), (2 * hwt + 0.03, y1 - y0, d), key)
    zf = zt + sgn * (d - 0.01)
    if bs == "chrome":
        poly([V(x, y, zf + sgn * 0.004) for x, y in rect2(-hwt, hwt, y0 + 0.06, y0 + 0.09)], "black", V(0, 0, sgn))
    if bs == "clad":
        poly([V(x, y, zf + sgn * 0.004) for x, y in rect2(-hwt, hwt, y1 - 0.06, y1 - 0.045)], "chrome", V(0, 0, sgn))
    # Wrap round the corners.
    zs = sorted((zt, zt - sgn * 0.4))
    s.side_decal(zs[1], zs[0], y0, y1, key, 0.012)


def tail_end(s):
    p = s.p
    t = p["tail"]
    zR = s.zR
    st, x0, x1, y0, y1 = t["style"], t["x0"], min(t["x1"], s.hw(zR) - 0.03), t["y0"], t["y1"]
    s.tail = V((x0 + x1) / 2 if st != "bar" else x1 - 0.1, (y0 + y1) / 2, zR)
    if st == "bar":
        s.front(rect2(-x1, x1, y0, y1), "tail", both=False, rear=True)
    else:
        s.front(rect2(x0, x1, y0, y1), "tail", rear=True)
        if st == "ribbed":
            for i in range(1, 4):
                yy = lerp(y0, y1, i / 4)
                s.front(rect2(x0, x1, yy - 0.006, yy + 0.006), "trim", 0.012, rear=True)
            s.front(rect2(x0, x0 + 0.08, y0, (y0 + y1) / 2), "amber", 0.014, rear=True)
        else:
            s.front(rect2(x0, x0 + 0.08, y0, y1), "reverse", 0.012, rear=True)
    if t["wrap"] > 0:
        s.side_decal(zR + t["wrap"], zR, y0, y1, "tail", 0.006)
    py = p["plate_y"] if p["bumper"] == "body" else p["plate_y"] + 0.05
    s.front(rect2(-0.16, 0.16, py - 0.075, py + 0.075), "plate", 0.012, both=False, rear=True)
    bumpers(s, zR, -1)


def side_details(s):
    p = s.p
    belt = p["belt"]
    # Door shuts: front of the front door, between the doors (under the B pillar), behind the rear.
    zr3 = s.zra + s.R + 0.04
    for z in (s.zc - 0.04, s.zB, zr3):
        s.side_decal(z + 0.007, z - 0.007, 0.0, s.belt(z) - 0.012, "seam", 0.008)
    for z in (s.zB + 0.1, zr3 + 0.1):
        yh = s.belt(z) - 0.1
        s.side_decal(z + 0.12, z, yh, yh + 0.028, "seam" if p["mirror"] == "body" else p["mirror"], 0.006)
    if p["rub"]:
        s.side_decal(s.zF, s.zR, 0.52, 0.58, "black", 0.01)
    if p["sill_key"]:
        s.side_decal(s.zfa - s.R, s.zra + s.R, 0.0, p["sill"] + 0.1, p["sill_key"], 0.008)
    if p["frame"] == "chrome":
        s.side_decal(s.zF - 0.3, s.zR + 0.3, p["crease"] - 0.08, p["crease"] - 0.065, "chrome", 0.008)
    # Mirrors on the door's front corner.
    xm = s.hwg() - 0.02
    mk = p["mirror"]
    zm = s.zc - 0.16
    ym = s.belt(zm) + 0.1
    for sx in (1, -1):
        box(V(sx * (xm + 0.05), ym - 0.04, zm), (0.1, 0.04, 0.06), "black")
        box(V(sx * (xm + 0.12), ym, zm - 0.01), (0.13, 0.1, 0.07), mk)


WHEELS = {
    # rim colour, pocket colour, pockets, pocket inner/outer radius (of the rim), spoke share
    "alloy5": ("silver", "black", 5, 0.3, 0.88, 0.45),
    "alloy6": ("silver", "black", 6, 0.32, 0.86, 0.5),
    "sport": ("gunmetal", "black", 5, 0.28, 0.9, 0.55),
    "multi": ("silver", "black", 10, 0.5, 0.86, 0.45),
    "steel": ("grey", "trim", 8, 0.62, 0.74, 0.55),
    "hubcap": ("silver", "grey", 6, 0.4, 0.8, 0.25),
    "aero": ("gunmetal", "silver", 5, 0.25, 0.9, 0.75),
}


def wheel(s, za, sx):
    p = s.p
    r, tw = p["r"], p["tw"]
    xo = s.hw(za) - p["tuck"] - 0.025
    xi = xo - tw
    n = 12
    c_out, c_in = V(xo, r, za), V(xi, r, za)
    rings = [disc_pts(c_in, r * 0.97, n), disc_pts(c_out - V(0.03, 0, 0), r, n), disc_pts(c_out, r * 0.93, n)]
    rr = r * 0.66
    pts = []
    loft_rings = rings
    if sx < 0:
        loft_rings = [[mx(q) for q in rg] for rg in rings]
    loft(loft_rings, "tyre", closed_ring=True, caps=False)
    side = V(sx, 0, 0)
    W_ = lambda q: q if sx > 0 else mx(q)
    # Sidewall annulus round the rim.
    outer, inner = rings[2], disc_pts(c_out, rr, n)
    for i in range(n):
        j = (i + 1) % n
        poly([W_(outer[i]), W_(outer[j]), W_(inner[j]), W_(inner[i])], "tyre", side)
    rim, pk, k, ri, ro, share = WHEELS[p["wheel"]]
    cr = c_out - V(0.012, 0, 0)
    poly([W_(q) for q in disc_pts(cr, rr, n)], rim, side)
    # Pockets between the spokes.
    e = V(0.004, 0, 0)
    for i in range(k):
        a0 = math.tau * i / k + math.tau / k * share / 2
        a1 = math.tau * (i + 1) / k - math.tau / k * share / 2
        quad = [cr + e + V(0, rr * f * math.cos(a), rr * f * math.sin(a)) for f, a in ((ri, a0), (ro, a0), (ro, a1), (ri, a1))]
        if p["wheel"] == "aero":
            quad = [cr + e + V(0, rr * f * math.cos(a), rr * f * math.sin(a)) for f, a in ((ri, a0), (ro, a0 + 0.5), (ro, a1 + 0.3))]
        poly([W_(q) for q in quad], pk, side)
    if p["wheel"] == "sport":
        a0, a1 = math.radians(25), math.radians(60)
        quad = [cr + e * 2 + V(0, rr * f * math.cos(a), -rr * f * math.sin(a)) for f, a in ((0.45, a0), (0.8, a0), (0.8, a1), (0.45, a1))]
        poly([W_(q) for q in quad], "caliper", side)
    poly([W_(q) for q in disc_pts(cr + e * 2, rr * 0.18, 6)], "silver" if rim != "silver" else "grey", side)


def extras(s):
    p = s.p
    if p["scoop"]:
        z = s.zc + 0.5
        y = s.top(z) + p["crown"]
        box(V(0, y + 0.01, z), (0.46, 0.07, 0.34), "body")
        poly([V(x, yy, z + 0.172) for x, yy in rect2(-0.2, 0.2, y - 0.01, y + 0.035)], "black", V(0, 0, 1))
    if p["wing"]:
        zt = s.zR + 0.16
        yd = s.top(zt) + p["crown"]
        for x in (-0.55, 0.55):
            box(V(x, yd + 0.07, zt), (0.04, 0.16, 0.12), "black")
        w = s.hw(zt) - 0.08
        y = yd + 0.16
        prof = [V(0, y, zt + 0.12), V(0, y + 0.03, zt - 0.1), V(0, y + 0.05, zt - 0.13), V(0, y, zt - 0.1)]
        loft([[q + V(w, 0, 0) for q in prof], [q - V(w, 0, 0) for q in prof]], "body")


# --- Build and export -----------------------------------------------------------------

def finish(name):
    obs = []
    for role, bm in BMS.items():
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        mname = name + "_" + role
        old = bpy.data.meshes.get(mname)
        if old: bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new(mname); bm.to_mesh(me); bm.free()
        me.materials.append(mat)
        me.color_attributes.active_color_name = "Col"; me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(mname, me); coll.objects.link(ob); obs.append(ob)
    BMS.clear()
    return obs


built, data, tris = [], {}, {}
for i, (vname, over) in enumerate(SEDANS.items()):
    prm = dict(SEDAN); prm.update(over)
    s = sedan(prm)
    name = "sedan_" + vname
    obs = finish(name)
    for ob in obs:
        ob.location = ((i % 4) * 2.8, (i // 4) * 7.0, 0)
    built += obs
    tris[name] = sum(len(o.data.polygons) for o in obs)
    data[name] = dict(size=(prm["W"], prm["H"], prm["L"]), head=s.head, tail=s.tail)

_glb = os.path.normpath(os.path.join(ART, "..", "assets", "models", "vehicles.glb"))
for o in bpy.data.objects: o.select_set(o in built)
bpy.ops.export_scene.gltf(filepath=_glb, export_format="GLB", use_selection=True,
                          export_normals=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)


def v3(v): return "Vector3(%.3f, %.3f, %.3f)" % tuple(v)


_gd = os.path.normpath(os.path.join(ART, "..", "scripts", "world", "vehicle_data.gd"))
with open(_gd, "w") as f:
    f.write("class_name VehicleData\nextends RefCounted\n")
    f.write("## Generated by art/vehicles.py with assets/models/vehicles.glb: don't edit by hand.\n\n")
    f.write("## Per variant (glb part prefix): size (width, height, length, m) and the centres of\n")
    f.write("## the right-hand head and tail lamps (+Z front; mirror x for the left).\n")
    f.write("const VARIANTS := {\n")
    for name, d in data.items():
        f.write('\t"%s": {"size": %s, "head": %s, "tail": %s},\n' % (name, v3(d["size"]), v3(d["head"]), v3(d["tail"])))
    f.write("}\n")
result = tris
