# Geometry kit for the road vehicles: exec'd by art/vehicles.py (inside Blender), which
# holds the models' parameter tables and does the build and export.
# Game frame: +Z is the front, +Y up, ground at y = 0, centred on the footprint, real
# metres (Blender: front to -Y, Z up).
#
# A body is a lofted lower body (sections of sill, crease, shoulder and crown, the sill
# lifted round the wheel arches), a lofted greenhouse on it (windscreen, roof, rear
# window; flat sides carrying the window decals), wheels, and details laid on as thin
# decals over the surfaces: lamps, grilles, seams, trim. A three-box body (sedan) has a
# trunk deck behind the rear window; a two-box body (`twobox`: SUV, minivan, van) runs
# its roof back to a steep tailgate window just ahead of the rear fascia.
#
# Parts per variant, named <model>_<variant>_<role>: `body` (painted per car in the
# game), `head` and `tail` (lamp glass, lit at night) and `fixed` (everything else, in
# its own colours).
import bpy, bmesh, math, os
from mathutils import Vector

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


class Body:
    def __init__(s, p):
        s.p = p
        L = p["L"]
        s.zF, s.zR = L / 2, -L / 2
        s.zfa = s.zF - p["fo"]; s.zra = s.zfa - p["wb"]
        s.zc = s.zF - p["hood"]; s.zw = s.zc - p["ws"]
        if p["twobox"]:
            # The roof runs back to the tailgate window, which meets the beltline just
            # ahead of the rear fascia: no deck.
            s.zd = s.zR + p["tail_set"]; s.zr = s.zd + p["rw"]
            assert s.zw - s.zr > 0.3, "no roof left"
        else:
            s.zr = s.zw - p["roof"]; s.zd = s.zr - p["rw"]
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
        side at each station (so it stops at the wheel arches). y0 and y1 may be fn(z)."""
        z0, z1 = max(z0, z1), min(z0, z1)
        Y0 = y0 if callable(y0) else (lambda z: y0)
        Y1 = y1 if callable(y1) else (lambda z: y1)
        zs = [z0] + [z for z in s.stations if z1 < z < z0] + [z1]
        for za, zb in zip(zs, zs[1:]):
            cols = []
            for z in (za, zb):
                q = s.sec(z)
                lo, hi = max(Y0(z), q[0].y + 0.002), min(Y1(z), q[2].y - 0.002)
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


def build(p):
    s = Body(p)
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
        # Arch liners over the tyres, out to the body side (no seeing into the hollow body).
        xo = s.hw(za, flare=False) + p["flare"] - 0.004
        arc = [V(0, p["r"] + s.R * math.cos(a), za + s.R * math.sin(a)) for a in [math.radians(-90 + 15 * i) for i in range(13)]]
        for a, b in zip(arc, arc[1:]):
            m = (a + b) * 0.5
            poly([a + V(wx, 0, 0), b + V(wx, 0, 0), b + V(xo, 0, 0), a + V(xo, 0, 0)], "black", V(0, p["r"], za) - m, both=True)

    greenhouse(s)
    lamps_and_face(s)
    tail_end(s)
    if p["twobox"]:
        tailgate(s)
    side_details(s)
    roof_kit(s)
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
        if kind == "rw" and p["twobox"]: return "body"  # the tailgate, glazed below
        return p["roof_key"] if kind == "roof" else "glass"
    loft(rings, key, closed_ring=False, caps=False)
    if p["twobox"]:
        # Tailgate glass inset in the hatch, D pillars and a roof lip round it.
        ir = next(i for i, t in enumerate(tops) if t[3] == "rw")
        patch([r[1:-1] for r in rings[ir:]], 0.07, 0.93, 0.08, 0.96, "glass", V(0, s.belt(s.zd), s.zw))
    s.tops, s.rings = tops, rings

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
    if p["twobox"]:
        # Doors from the body, not the glass (which runs on over the load space): the
        # rear door ends over the rear arch, the B pillar a little behind halfway, and
        # a third window's pillar stands on the rear door's shut line.
        s.zrd = s.zra + s.R * p["rd_end"]
        zB = lerp(s.zc - 0.04, s.zrd, p["b_at"])
        zq = s.zrd
    else:
        s.zrd = s.zra + s.R + 0.04
        zB = lerp(win[0][0], win[-1][0], p["b_at"])
        zq = lerp(win[0][0], win[-1][0], p["quarter"])
    pillars = [(zB, 0.05)]
    if p["quarter"]:
        pillars.append((zq, p["q_w"]))
    for zp, w in pillars:
        put([(zp + w, s.belt(zp) + 0.02), (zp - w, s.belt(zp) + 0.02),
             (zp - w, H - p["rail"] - 0.005), (zp + w, H - p["rail"] - 0.005)], "black", 0.012)
    if p["c_key"]:
        # The rearmost pillar blacked out (the "floating roof").
        yb, yr = win[-1][1], win[-2][1]
        put([win[-2], win[-1], (z_on(rear_edge, yb) + 0.012, yb), (z_on(rear_edge, yr) + 0.012, yr)], p["c_key"], 0.006)
    s.zB = zB
    s.win = win


def ring_at(ring, u):
    """The point a fraction u (0 to 1) of the way round an open ring, by length."""
    segs = [(ring[i + 1] - ring[i]).length for i in range(len(ring) - 1)]
    t = u * sum(segs)
    for i, d in enumerate(segs):
        if t <= d or i == len(segs) - 1:
            return ring[i].lerp(ring[i + 1], min(t / d, 1.0) if d > 1e-9 else 0.0)
        t -= d


def patch(rings, u0, u1, v0, v1, key, inside, eps=0.006, nu=8):
    """A decal on a lofted surface: across its rings from u0 to u1 (by length round each
    ring), along them from v0 to v1 (by ring count), lifted off it away from `inside`."""
    nv = len(rings) - 1

    def at(u, v):
        i = min(int(v * nv), nv - 1)
        f = v * nv - i
        return ring_at(rings[i], u).lerp(ring_at(rings[i + 1], u), f)
    vs = sorted(set([v0, v1] + [i / nv for i in range(1, nv) if v0 < i / nv < v1]))
    us = [lerp(u0, u1, i / nu) for i in range(nu + 1)]
    for va, vb in zip(vs, vs[1:]):
        for ua, ub in zip(us, us[1:]):
            q = [at(ua, va), at(ub, va), at(ub, vb), at(ua, vb)]
            n = normal(q).normalized()
            if n.dot(centre(q) - inside) < 0: n = -n
            poly([c + n * eps for c in q], key, n)


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
    elif st == "round":
        # Round lamps in square black bezels (the Jeep face).
        cx, cy, rr = (x0 + x1) / 2, (y0 + y1) / 2, (y1 - y0) / 2
        s.front([(cx + 1.15 * rr * math.cos(a), cy + 1.15 * rr * math.sin(a)) for a in [math.tau * (i + 0.5) / 8 for i in range(8)]], "black", 0.006)
        s.front([(cx + rr * math.cos(a), cy + rr * math.sin(a)) for a in [math.tau * (i + 0.5) / 8 for i in range(8)]], "head", 0.01)
    if lp.get("slits"):
        # Upright light slits down the fascia's corners.
        sx = hwt - 0.04
        s.front([(sx - 0.03, y0 - 0.22), (sx, y0 - 0.2), (sx, y0 - 0.02), (sx - 0.03, y0 - 0.04)], "head", 0.01)
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
            n_ = g.get("n", 4)
            if g.get("surround"):
                s.front(rect2(0, w + 0.025, gy0 - 0.025, gy1 + 0.025), g["surround"], 0.006)
            s.front(rect2(0, w, gy0, gy1), "black")
            for i in range(n_):
                yy = lerp(gy0, gy1, (i + 0.6) / (n_ + 0.4))
                s.front(rect2(0, w - 0.02, yy, yy + 0.014), g.get("key", "trim"), 0.012)
        elif gs == "shield":
            # A big six-sided grille (modern SUVs), framed, with bars across.
            sh = [(0, gy0), (w * 0.78, gy0), (w, gy0 + (gy1 - gy0) * 0.45), (w * 0.94, gy1), (0, gy1)]
            if g.get("surround"):
                s.front([(x * 1.06 + 0.0, y + (0.022 if y > gy0 + 0.01 else -0.022)) for x, y in sh], g["surround"], 0.006)
            s.front(sh, "black", 0.009)
            for i in range(g.get("n", 3)):
                yy = lerp(gy0, gy1, (i + 0.7) / (g.get("n", 3) + 0.4))
                s.front(rect2(0, w * 0.92, yy, yy + 0.012), g.get("key", "trim"), 0.012)
            s.front(rect2(0, 0.05, (gy0 + gy1) / 2 - 0.03, (gy0 + gy1) / 2 + 0.03), "silver", 0.015)
        elif gs == "slots":
            # Seven upright slots, the middle one on the centreline.
            s.front(rect2(-0.018, 0.018, gy0, gy1), "black", 0.01, both=False)
            for i in range(1, 4):
                xx = i * w / 3.4
                s.front(rect2(xx - 0.018, xx + 0.018, gy0, gy1), "black", 0.01)
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
    zr3 = s.zrd
    for z in (s.zc - 0.04, s.zB, zr3):
        s.side_decal(z + 0.007, z - 0.007, 0.0, s.belt(z) - 0.012, "seam", 0.008)
    for z in (s.zB + 0.1, zr3 + 0.1):
        yh = s.belt(z) - 0.1
        s.side_decal(z + 0.12, z, yh, yh + 0.028, "seam" if p["mirror"] == "body" else p["mirror"], 0.006)
    if p["hinges"]:
        # Bolt-on door hinges at the front edge of each door (the Jeep look).
        for z in (s.zc - 0.04, s.zB):
            for y in (s.belt(z) - 0.14, (s.belt(z) + max(s.bottom(z), p["sill"])) / 2 - 0.08):
                hit = s.side_at(z - 0.05, y)
                if hit:
                    q, nrm = hit
                    for sx in (1, -1):
                        box(V(sx * (q.x + 0.012), q.y, q.z), (0.03, 0.05, 0.1), "black")
    if p["rub"]:
        s.side_decal(s.zF, s.zR, p["rub_y"], p["rub_y"] + 0.06, "black", 0.01)
    c = p["clad"]
    if c:
        # Unpainted plastic: eyebrows round the arches and a band along the sills.
        for za in (s.zfa, s.zra):
            s.side_decal(za + s.R + c["arch"], za - s.R - c["arch"], 0.0, lambda z: s.bottom(z) + c["arch"], c["key"], 0.01)
        s.side_decal(s.zF - 0.25, s.zR + 0.25, 0.0, p["sill"] + c["sill"], c["key"], 0.009)
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


def roof_y(s, z, x):
    """Height of the roof's top surface at (x, z), from the greenhouse rings."""
    tops = s.tops
    for (za, ya, ca, _), (zb, yb, cb, _) in zip(tops, tops[1:]):
        if zb - 1e-6 <= z <= za + 1e-6:
            t = (z - za) / (zb - za) if abs(zb - za) > 1e-9 else 0.0
            y, cr = lerp(ya, yb, t), lerp(ca, cb, t)
            break
    else:
        y, cr = tops[0][1], 0.0
    xe = s.hwg() - s.p["tumble"]
    return y + cr * 0.7 * min(max((xe - abs(x)) / (xe * 0.5), 0.0), 1.0)


def bar(a, b, w, h, key):
    """A square bar from a to b, w wide and h deep (its bottom on the a-b line)."""
    d = b - a
    side = V(0, 0, w / 2) if abs(d.x) > abs(d.z) else V(w / 2, 0, 0)
    rg = lambda c: [c + side, c + side + V(0, h, 0), c - side + V(0, h, 0), c - side]
    loft([rg(a), rg(b)], key)


def roof_kit(s):
    """Roof rails (on feet), with cross bars for a rack."""
    p = s.p
    kind = p["rails"]
    if not kind: return
    xr = s.hwg() - p["tumble"] - 0.1
    z0, z1 = s.zw - 0.12, s.zr + 0.08
    zs = [lerp(z0, z1, i / 4) for i in range(5)]
    lift = 0.045
    for sx in (1, -1):
        pts = [V(sx * xr, roof_y(s, z, xr) + lift, z) for z in zs]
        for a, b in zip(pts, pts[1:]):
            bar(a, b, 0.035, 0.03, p["rail_key"])
        for q in (pts[0], pts[-1]):
            box(q + V(0, -lift / 2 + 0.005, 0), (0.04, lift + 0.01, 0.1), "black")
    if kind == "bars":
        for z in (lerp(z0, z1, 0.3), lerp(z0, z1, 0.75)):
            y = roof_y(s, z, xr) + lift + 0.03
            bar(V(xr + 0.02, y, z), V(-xr - 0.02, y, z), 0.04, 0.025, "black")


def tailgate(s):
    """A two-box body's tailgate: its shut lines, a roof lip over the glass and the spare."""
    p = s.p
    zR = s.zR
    top = s.top(zR)
    hw = s.hw(zR) - 0.07
    yb = p["tail"]["y0"] - 0.03
    for x in (hw, -hw):
        s.front(rect2(x - 0.006, x + 0.006, yb, top - 0.02), "seam", 0.01, both=False, rear=True)
    s.front(rect2(-hw, hw, yb - 0.006, yb + 0.006), "seam", 0.01, both=False, rear=True)
    if p["spoiler"]:
        y = p["H"] - p["dr"] + p["crown"] * 0.5
        xs = s.hwg() - p["tumble"] - 0.02
        prof = [V(0, y - 0.02, s.zr + 0.05), V(0, y + 0.01, s.zr + 0.05), V(0, y - 0.005, s.zr - 0.16), V(0, y - 0.04, s.zr - 0.12)]
        loft([[q + V(xs, 0, 0) for q in prof], [q - V(xs, 0, 0) for q in prof]], p["spoiler"])
    if p["spare"]:
        # A spare wheel on the tailgate, its tread facing out.
        r = p["r"] * 0.98
        c = V(0, p["spare"], zR - 0.02)
        n = 12
        circ = lambda z, rad: [V(c.x + rad * math.cos(math.tau * i / n), c.y + rad * math.sin(math.tau * i / n), z) for i in range(n)]
        loft([circ(zR + 0.01, r * 0.9), circ(zR - 0.04, r), circ(zR - p["tw"] - 0.02, r), circ(zR - p["tw"] - 0.04, r * 0.9)], "tyre")
        zc = zR - p["tw"] - 0.045
        poly(circ(zc, r * 0.62), "gunmetal", V(0, 0, -1))
        poly(circ(zc - 0.005, r * 0.18), "silver", V(0, 0, -1))
        box(V(0, c.y, zR + 0.0), (0.12, 0.12, 0.08), "black")


WHEELS = {
    # rim colour, pocket colour, pockets, pocket inner/outer radius (of the rim), spoke share
    "alloy5": ("silver", "black", 5, 0.3, 0.88, 0.45),
    "alloy6": ("silver", "black", 6, 0.32, 0.86, 0.5),
    "sport": ("gunmetal", "black", 5, 0.28, 0.9, 0.55),
    "multi": ("silver", "black", 10, 0.5, 0.86, 0.45),
    "steel": ("grey", "trim", 8, 0.62, 0.74, 0.55),
    "hubcap": ("silver", "grey", 6, 0.4, 0.8, 0.25),
    "aero": ("gunmetal", "silver", 5, 0.25, 0.9, 0.75),
    "offroad": ("gunmetal", "black", 6, 0.36, 0.84, 0.55),
    "turbine": ("silver", "gunmetal", 12, 0.3, 0.9, 0.35),
}


def wheel(s, za, sx):
    p = s.p
    r, tw = p["r"], p["tw"]
    xo = s.hw(za) - p["tuck"] - 0.025
    xi = xo - tw
    n = 12
    c_out, c_in = V(xo, r, za), V(xi, r, za)
    rings = [disc_pts(c_in, r * 0.97, n), disc_pts(c_out - V(0.03, 0, 0), r, n), disc_pts(c_out, r * 0.93, n)]
    if p["tread"]:
        # Knobbly all-terrain tyres: square shoulders, a lugged tread.
        n = 16
        lug = lambda c, rad: [c + V(0, rad * (1.0 if i % 2 else 0.955) * math.cos(math.tau * i / n),
                                    rad * (1.0 if i % 2 else 0.955) * math.sin(math.tau * i / n)) for i in range(n)]
        rings = [disc_pts(c_in, r * 0.96, n), lug(c_in + V(0.02, 0, 0), r), lug(c_out - V(0.02, 0, 0), r), disc_pts(c_out, r * 0.95, n)]
    rr = r * 0.66
    pts = []
    loft_rings = rings
    if sx < 0:
        loft_rings = [[mx(q) for q in rg] for rg in rings]
    loft(loft_rings, "tyre", closed_ring=True, caps=False)
    side = V(sx, 0, 0)
    W_ = lambda q: q if sx > 0 else mx(q)
    # Sidewall annulus round the rim.
    outer, inner = rings[-1], disc_pts(c_out, rr, n)
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
