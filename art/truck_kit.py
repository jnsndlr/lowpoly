# Geometry kit for the trucks: exec'd by art/vehicles.py after art/vehicle_kit.py, whose
# primitives (face, poly, loft, box, bar, disc_pts, finish) and palette it shares. Same
# frame: +Z front, +Y up, ground at y = 0, centred on the footprint, real metres.
#
# A straight truck (`kind="straight"`) is a medium-duty conventional cab (hood and
# fenders lofted as one section, the cab a chamfered box with a raked windscreen) on a
# ladder frame, with a body behind it: a dry box, a reefer box (refrigeration unit on
# its nose) or a tank. A step van (`kind="step"`) is one walk-in body with a short nose.
# Wheels are steel discs; rear axles are dual-tyred, single or tandem.
import math

PAL.update({
    "boxw": (0.9, 0.9, 0.88), "post": (0.8, 0.8, 0.78), "tape": (0.78, 0.07, 0.05),
    "tankw": (0.86, 0.86, 0.84), "deck": (0.62, 0.45, 0.28), "log": (0.5, 0.33, 0.2),
    "logend": (0.78, 0.6, 0.4), "gravel": (0.48, 0.46, 0.42), "dump": (0.2, 0.21, 0.24), "accent2": (0.15, 0.3, 0.7), "orange": (0.93, 0.45, 0.08), "reefer": (0.84, 0.85, 0.85),
})


class TS:
    """What a truck build hands back: the lamp centres (right-hand ones, +x)."""
    head = V(0, 0, 0)
    tail = V(0, 0, 0)


def rrect(z, hw, y0, y1, ct=0.0, cb=0.0):
    """A chamfered rectangle across the truck at z (8 points, ct/cb the top and bottom
    chamfers): one ring for a loft."""
    return [V(hw, y0 + cb, z), V(hw, y1 - ct, z), V(hw - ct, y1, z), V(-hw + ct, y1, z),
            V(-hw, y1 - ct, z), V(-hw, y0 + cb, z), V(-hw + cb, y0, z), V(hw - cb, y0, z)]


def sdecal(x, z0, z1, y0, y1, key, both=True, eps=0.006):
    """A rectangle on the side plane x (facing out), mirrored to -x by default."""
    sx = 1 if x >= 0 else -1
    xx = x + sx * eps
    poly([V(xx, y0, z0), V(xx, y0, z1), V(xx, y1, z1), V(xx, y1, z0)], key, V(sx, 0, 0), both)


def fdecal(z, x0, x1, y0, y1, key, out=1, both=False, eps=0.006):
    """A rectangle on the end plane z, facing +z (out=1) or -z."""
    zz = z + out * eps
    poly([V(x0, y0, zz), V(x1, y0, zz), V(x1, y1, zz), V(x0, y1, zz)], key, V(0, 0, out), both)


def cyl(a, b, r, key, n=8):
    """A prism of n sides from a to b (any direction)."""
    d = (b - a).normalized()
    u = d.cross(V(0, 1, 0)) if abs(d.y) < 0.9 else d.cross(V(1, 0, 0))
    u.normalize(); w = d.cross(u)
    rg = lambda c: [c + (u * math.cos(math.tau * i / n) + w * math.sin(math.tau * i / n)) * r for i in range(n)]
    loft([rg(a), rg(b)], key)


def arch_bottom(z, base, axles, r, R):
    """A body's lower edge at z: `base`, lifted round each wheel in `axles`."""
    y = base
    for za in axles:
        dz = abs(z - za)
        if dz <= R:
            y = max(y, r + math.sqrt(max(0.0, R * R - dz * dz)))
    return y


def arch_stations(axles, R, z0, z1):
    """Loft stations from z0 down to z1, dense round each arch."""
    zs = {z0, z1}
    for za in axles:
        for i in range(13):
            z = za + R * math.cos(math.radians(15 * i))
            if z1 <= z <= z0: zs.add(z)
    return sorted(zs, reverse=True)


# --- Wheels ---------------------------------------------------------------------------

def tk_wheel(xo, z, r, tw, sx, hub="front"):
    """A truck tyre on a steel disc wheel, its outer face at |x| = xo on side sx. `hub`:
    "front" (a domed cap), "outer" (the dished outer dual, its hub standing out of it),
    "inner" (hidden behind the outer one)."""
    n = 14
    co, ci = V(xo, r, z), V(xo - tw, r, z)
    rings = [disc_pts(ci, r * 0.94, n), disc_pts(ci + V(0.03, 0, 0), r, n),
             disc_pts(co - V(0.03, 0, 0), r, n), disc_pts(co, r * 0.94, n)]
    W_ = (lambda q: q) if sx > 0 else mx
    loft([[W_(q) for q in rg] for rg in rings], "tyre", caps=False)
    side = V(sx, 0, 0)
    rr = r * 0.62
    dish = 0.05 if hub == "outer" else 0.015
    cr = co - V(dish, 0, 0)
    outer, inner = rings[-1], disc_pts(co, rr, n)
    for i in range(n):
        j = (i + 1) % n
        poly([W_(outer[i]), W_(outer[j]), W_(inner[j]), W_(inner[i])], "tyre", side)
    if hub == "inner":
        poly([W_(q) for q in disc_pts(co - V(0.01, 0, 0), rr, n)], "gunmetal", side)
        return
    # The dish: a short cone in to the disc.
    loft([[W_(q) for q in disc_pts(co, rr, n)], [W_(q) for q in disc_pts(cr, rr * 0.9, n)]], "silver", caps=False)
    poly([W_(q) for q in disc_pts(cr, rr * 0.9, n)], "silver", side)
    # Hand holes round the disc.
    e = V(0.004, 0, 0)
    for i in range(6):
        a = math.tau * i / 6
        c = cr + e + V(0, rr * 0.62 * math.cos(a), rr * 0.62 * math.sin(a))
        poly([W_(q) for q in disc_pts(c, rr * 0.13, 5, a)], "trim", side)
    hb = [disc_pts(cr, rr * 0.36, 8), disc_pts(cr + V(0.06 if hub == "outer" else 0.05, 0, 0), rr * 0.26, 8)]
    loft([[W_(q) for q in rg] for rg in hb], "chrome" if hub == "front" else "grey")


def axle(p, z, dual):
    """One axle's wheels (both sides), and the axle beam between them."""
    r, tw, xo = p["r"], p["tw"], p["track"]
    for sx in (1, -1):
        if dual:
            tk_wheel(xo, z, r, tw, sx, "outer")
            tk_wheel(xo - tw - 0.04, z, r, tw, sx, "inner")
        else:
            tk_wheel(xo, z, r, tw, sx, "front")
    box(V(0, r, z), (2 * (xo - tw), 0.14, 0.14), "under")
    if dual:
        box(V(0, r, z), (0.44, 0.36, 0.4), "under")  # (the differential)


def mud_flap(p, z, hw):
    for sx in (1, -1):
        box(V(sx * (hw - 0.3), 0.55, z), (0.55, 0.62, 0.025), "black")


# --- Conventional cab -----------------------------------------------------------------

def md_cab(s):
    """Hood, fenders, cab (and sleeper), bumper, lamps, mirrors, steps and tanks of a
    conventional: a medium-duty one (the M2/MV kind) by default, a Class 8 with wider,
    longer hoods and a sleeper behind the cab for the tractors. Sets s.zb, the back of
    the cab (or sleeper)."""
    p = s.p
    zF = s.zF
    zg = zF - 0.26                     # grille face
    zc = zg - p["hood"]                # cowl
    zw = zc - p["ws"]                  # windscreen top
    zb = zc - p["cab"]                 # back of the cab
    sl = p["sleeper"]
    s.zb = zb - sl
    roof, chw = p["roof"], p["cab_w"] / 2
    r, R = p["r"], p["r"] + 0.08
    s_fa = s.zfa

    # Hood and fenders: one section, hood centre over fender tops over the arches.
    def ring(z):
        d = zg - z
        u = min(max(d / p["hood"], 0.0), 1.0)
        ytop = lerp(p["hood_y0"], p["hood_y1"], u) - p["nose_round"] * (1 - min(d / 0.16, 1.0)) ** 2
        hh = lerp(p["hood_hw"][0], p["hood_hw"][1], u)
        yf = lerp(p["fender_y"], p["fender_y"] + 0.08, u)
        hf = chw + 0.05 - p["fender_round"] * (1 - min(d / p["fender_run"], 1.0)) ** 2
        yb = arch_bottom(z, lerp(p["bump"][1] + 0.05, p["cab_y0"], u), [s_fa], r, R)
        right = [V(hh - 0.07, ytop, z), V(hh, ytop - 0.07, z), V(hh + 0.07, yf, z), V(hf - 0.07, yf, z),
                 V(hf, yf - 0.07, z), V(hf, yb, z)]
        return right + [mx(q) for q in reversed(right)]
    zs = arch_stations([s_fa], R, zg, zc)
    zs = sorted(set(zs) | {zg - 0.06, zg - 0.16, zg - 0.32}, reverse=True)
    loft([ring(z) for z in zs], lambda i, j: "black" if j == 5 else "body", caps=False)
    poly(ring(zg), "body", V(0, 0, 1))
    poly(ring(zc), "body", V(0, 0, -1))
    # Wheel well inside the fender.
    yw = p["bump"][1] + 0.07
    box(V(0, (r + R + yw) / 2, s_fa), (2 * (p["track"] - p["tw"] - 0.02), r + R - yw, 2 * R), "black")

    # Grille: chrome surround, black core, bars.
    gx, gy0, gy1 = p["grille_w"] / 2, p["bump"][1] + 0.11, p["hood_y0"] - p["grille_top"]
    fdecal(zg, -gx, gx, gy0, gy1, p["grille"])
    fdecal(zg + 0.004, -gx + 0.06, gx - 0.06, gy0 + 0.05, gy1 - 0.05, "black")
    if p["grille_bars"] == "vertical":
        for i in range(1, 8):
            x = lerp(-gx + 0.06, gx - 0.06, i / 8)
            fdecal(zg + 0.008, x - 0.015, x + 0.015, gy0 + 0.05, gy1 - 0.05, p["grille"])
    else:
        for i in range(1, 5):
            y = lerp(gy0 + 0.05, gy1 - 0.05, i / 5)
            fdecal(zg + 0.008, -gx + 0.06, gx - 0.06, y - 0.012, y + 0.012, p["grille"])
    # Headlamps on the fender fronts, amber turn lamps outboard.
    hx0, hx1 = gx + 0.08, chw - 0.12
    ly0, ly1 = p["lamp_y"]
    zl = zg - p["lamp_set"]
    for sx in (1, -1):
        x0, x1 = sorted((sx * hx0, sx * hx1))
        fdecal(zl, x0, x1, ly0, ly1, "head")
        xa0, xa1 = sorted((sx * (hx1 + 0.01), sx * (hx1 + 0.1)))
        fdecal(zl - 0.04, xa0, xa1, ly0, ly1 - 0.02, "amber")
    if p["lamp_set"]:
        # (lamps set back in the fenders behind a long nose: the fender fronts under them)
        for sx in (1, -1):
            x0, x1 = sorted((sx * (gx + 0.02), sx * (chw + 0.04)))
            fdecal(zl - 0.002, x0, x1, ly0 - 0.08, ly1 + 0.06, "body")
    s.head = V((hx0 + hx1) / 2, (ly0 + ly1) / 2, zl)

    # Bumper, tow hooks.
    bumper_w = chw + 0.08
    by0, by1 = p["bump"]
    box(V(0, (by0 + by1) / 2, zF - 0.14), (2 * bumper_w, by1 - by0, 0.28), p["bumper"])
    fdecal(zF, -0.3, 0.3, by0 + 0.1, by0 + 0.22, "black")
    for x in (-0.5, 0.5):
        box(V(x, by0 - 0.03, zF - 0.1), (0.07, 0.08, 0.14), "caliper" if p["hooks"] else "black")

    # Cab: a chamfered box, the windscreen raked from the cowl to the roof.
    ct = 0.13
    yc = p["hood_y1"] + 0.05
    cy0 = p["cab_y0"]
    # (a sleeper behind the cab: flat-top at the cab's roof, or a raised roof rising
    # from over the windscreen in a fairing)
    prof = [(zc, yc), (zw, roof)]
    sroof = p["sl_roof"] or roof
    if sroof > roof + 0.05:
        prof.append((zw - p["rise"], sroof))
    prof.append((zb - sl, sroof))
    loft([rrect(z, chw, cy0, y, ct) for z, y in prof], "body")
    if sl:
        # The sleeper's joint, a bunk window and a luggage door.
        sdecal(chw, zb - 0.012, zb + 0.012, cy0 + 0.04, roof - ct - 0.04, "seam")
        sdecal(chw, zb - sl + 0.25, zb - sl + 0.7, roof - 0.55, roof - ct - 0.12, "glass")
        sdecal(chw, zb - 0.3, zb - 0.8, cy0 + 0.08, cy0 + 0.58, "seam")
        sdecal(chw, zb - 0.32, zb - 0.78, cy0 + 0.1, cy0 + 0.56, "body", eps=0.01)
    if p["extenders"]:
        # Side extenders closing the gap to the trailer.
        for sx in (1, -1):
            box(V(sx * (chw - 0.02), (cy0 + 0.3 + sroof - 0.05) / 2, s.zb - 0.15), (0.03, sroof - cy0 - 0.35, 0.3), "body")
    # Windscreen on the rake; side windows up to the pillar line; rear window.
    a, b = V(0, yc, zc), V(0, roof, zw)
    d = b - a
    n_ = V(0, -d.z, d.y).normalized() * 0.006
    xg = chw - ct - 0.05
    pts = [lerp(a, b, u) + n_ for u in (0.1, 0.9)]
    poly([pts[0] + V(xg, 0, 0), pts[1] + V(xg - 0.04, 0, 0), pts[1] - V(xg - 0.04, 0, 0), pts[0] - V(xg, 0, 0)], "glass", V(0, d.z * -1, d.y))
    belt = yc + 0.07
    wtop = roof - ct - 0.1
    z_at = lambda y: zc - (y - (yc - ct)) / (roof - yc) * p["ws"]
    zdoor = zb + p["door_back"]
    for sx in (1, -1):
        xx = sx * (chw + 0.006)
        win = [V(xx, belt, z_at(belt) - 0.12), V(xx, wtop, z_at(wtop) - 0.12), V(xx, wtop, zdoor + 0.12), V(xx, belt, zdoor + 0.12)]
        poly(win, "glass", V(sx, 0, 0))
    # Door seams and handle.
    sdecal(chw, zdoor - 0.012, zdoor + 0.012, cy0 + 0.04, roof - ct - 0.04, "seam")
    sdecal(chw, zc - 0.05, zc - 0.03, cy0 + 0.04, belt, "seam")
    sdecal(chw, zdoor + 0.16, zdoor + 0.3, belt - 0.14, belt - 0.1, "silver")
    if not sl:
        fdecal(zb, -0.45, 0.45, belt + 0.05, wtop - 0.1, "glass", out=-1)
    if p["visor"]:
        # A drum-style sun visor over the windscreen.
        box(V(0, roof - 0.06, zw + 0.12), (2 * chw - 0.2, 0.05, 0.3), p["visor"])
    # Roof marker lamps (wider than 80": five amber lamps over the windscreen).
    for x in (-0.5, -0.25, 0.0, 0.25, 0.5):
        box(V(x, roof + 0.02, zw - 0.06), (0.09, 0.04, 0.06), "amber")
    # West-coast mirrors on arms off the A pillars.
    for sx in (1, -1):
        bar(V(sx * chw, belt + 0.1, zc - 0.2), V(sx * (chw + 0.3), belt + 0.1, zc - 0.2), 0.04, 0.04, "black")
        box(V(sx * (chw + 0.32), belt + 0.3, zc - 0.2), (0.05, 0.5, 0.2), "black")
        box(V(sx * (chw + 0.32), belt - 0.04, zc - 0.2), (0.05, 0.16, 0.16), "black")
    # Steps under the door, fuel tank behind them (driver's side, +x), battery box
    # opposite.
    zs0 = zc - 0.12 - p["step_set"]
    for sx in ((1, -1) if p["tanks"] == 2 else (1,)):
        for y in lerp_steps(cy0):
            box(V(sx * (chw - 0.16), y, zs0 - 0.2), (0.34, 0.04, 0.36), p["steps"])
        box(V(sx * (chw - 0.16), (0.38 + cy0) / 2, zs0 - 0.02), (0.34, cy0 - 0.38, 0.03), "black")
    # Fuel tanks behind the steps (both sides on a tractor; else the driver's, +x,
    # with the battery box opposite), steps strapped on.
    tr = p["tank_r"]
    zt0 = zs0 - 0.42
    zt1 = zt0 - p["tank_len"]
    for sx in ((1, -1) if p["tanks"] == 2 else (1,)):
        c = sx * (chw - tr - 0.06)
        cyl(V(c, 0.38 + tr, zt0), V(c, 0.38 + tr, zt1), tr, "silver", 10)
        for z in (zt0 - 0.15, zt1 + 0.15):
            cyl(V(c, 0.38 + tr, z + 0.03), V(c, 0.38 + tr, z - 0.03), tr + 0.012, "black", 10)
    if p["tanks"] == 1:
        box(V(-(chw - 0.3), 0.66, zc - 1.0), (0.5, 0.5, 0.8), "black")
    if p["skirts"]:
        # Chassis fairings over the tanks, from the steps back to the drive wheels.
        z1 = s.skirt_end
        for sx in (1, -1):
            loft([[V(sx * x, y, z) for x, y in ((chw + 0.02, 0.42), (chw + 0.02, cy0), (chw - 0.1, cy0 + 0.02), (chw - 0.1, 0.42))]
                  for z in (zs0 - 0.04, z1)], "body", caps=True)
    # Engine and transmission under the cab.
    box(V(0, (cy0 + 0.55) / 2, zc + 0.2), (0.8, cy0 - 0.55, 1.6), "under")
    if p["air_cleaners"]:
        # Chrome air cleaners on the cowl sides.
        for sx in (1, -1):
            cyl(V(sx * (chw + 0.12), cy0 + 0.1, zc + 0.15), V(sx * (chw + 0.12), yc + 0.15, zc + 0.15), 0.2, "chrome", 10)
    if p["stacks"]:
        # Exhaust stacks up the back of the cab, past the roof.
        for sx in ((1, -1) if p["stacks"] == 2 else (-1,)):
            c = V(sx * (chw - 0.22), cy0, s.zb - 0.16)
            cyl(c, c + V(0, roof + 0.95 - cy0, 0), 0.08, "chrome", 8)
            cyl(c + V(0, 0.45, 0), c + V(0, 1.4, 0), 0.115, "silver", 8)


def lerp_steps(cy0):
    """Step heights up to a cab floor at cy0."""
    n = max(1, round((cy0 - 0.45) / 0.35))
    return [lerp(0.45, cy0, i / n) for i in range(n)]


def frame(s, z0, z1, y_top=1.0):
    """The ladder frame's rails from z0 back to z1."""
    for x in (-0.43, 0.43):
        box(V(x, y_top - 0.13, (z0 + z1) / 2), (0.08, 0.26, z0 - z1), "black")
    for z in (z0 - 0.1, z1 + 0.1):
        box(V(0, y_top - 0.13, z), (0.86, 0.2, 0.08), "black")


def rear_fenders(p, axles, hw):
    """Flat fenders over the rear wheels (a tandem gets one long one)."""
    z0, z1 = max(axles) + p["r"] + 0.12, min(axles) - p["r"] - 0.12
    y = 2 * p["r"] + 0.1
    for sx in (1, -1):
        box(V(sx * (hw - 0.3), y, (z0 + z1) / 2), (0.6, 0.03, z0 - z1), "black")
        for z in (z0, z1):
            box(V(sx * (hw - 0.3), y - 0.15, z), (0.6, 0.3, 0.025), "black")


def quarter_fenders(p, axles):
    """A tractor's quarter fenders: curved over the front of the first drive axle's
    wheels and the back of the last's, the deck clear between for the trailer."""
    r, xo = p["r"], p["track"] + 0.03
    xi = xo - 2 * p["tw"] - 0.1
    for za, a0, a1 in ((max(axles), 20, 100), (min(axles), 80, 160)):
        arc = [V(0, r + (r + 0.1) * math.sin(math.radians(a)), za + (r + 0.1) * math.cos(math.radians(a)))
               for a in range(a0, a1 + 1, 20)]
        for sx in (1, -1):
            loft([[V(sx * xo, q.y, q.z), V(sx * xi, q.y, q.z)] for q in arc], "black", closed_ring=False, caps=False)
            loft([[V(sx * xi, q.y, q.z), V(sx * xo, q.y, q.z)] for q in arc], "black", closed_ring=False, caps=False)


def tape_side(x, z0, z1, y, both=True):
    """Red reflective tape in dashes along a side (white dashes vanish on white)."""
    n = max(1, int((z0 - z1) / 0.6))
    for i in range(n):
        za = z0 - 0.1 - i * (z0 - z1 - 0.2) / n
        sdecal(x, za - 0.28, za, y, y + 0.05, "tape", both)
        sdecal(x, za - 0.56, za - 0.28, y, y + 0.05, "plate", both)


def rear_end(s, z, hw, y_sill, key="black"):
    """Rear sill and underride bar, tail lamps on the sill: sets s.tail."""
    box(V(0, y_sill - 0.09, z + 0.06), (2 * hw, 0.18, 0.12), key)
    box(V(0, 0.52, z + 0.05), (2 * hw - 0.3, 0.12, 0.1), "black")
    for x in (-0.6, 0.6):
        box(V(x, (0.52 + y_sill) / 2, z + 0.08), (0.08, y_sill - 0.52, 0.08), "black")
    for sx in (1, -1):
        x0, x1 = sorted((sx * (hw - 0.34), sx * (hw - 0.12)))
        fdecal(z, x0, x1, y_sill - 0.15, y_sill - 0.04, "tail", out=-1)
        x0, x1 = sorted((sx * (hw - 0.46), sx * (hw - 0.37)))
        fdecal(z, x0, x1, y_sill - 0.15, y_sill - 0.04, "reverse", out=-1)
        fdecal(z, -0.2, 0.2, 0.47, 0.57, "tape", out=-1)
    s.tail = V(hw - 0.23, y_sill - 0.095, z)


# --- Bodies ---------------------------------------------------------------------------

def box_body(s, z0, z1):
    """A van body: plain sides with posts, rails, tape, clearance lamps, a roll-up or
    swing rear door, and a refrigeration unit on its nose for a reefer."""
    p = s.p
    hw, y0, y1 = p["W"] / 2, p["floor"], p["H"]
    loft([rrect(z0, hw, y0, y1, 0.02), rrect(z1, hw, y0, y1, 0.02)], "boxw")
    # Rails top and bottom, posts between.
    sdecal(hw, z1, z0, y1 - 0.09, y1 - 0.02, "silver")
    sdecal(hw, z1, z0, y0, y0 + 0.14, "silver")
    n = max(2, int((z0 - z1) / 0.62))
    for i in range(1, n):
        z = lerp(z0, z1, i / n)
        sdecal(hw, z - 0.025, z + 0.025, y0 + 0.14, y1 - 0.09, "post")
    tape_side(hw, z0, z1, y0 + 0.045)
    # Floor bearers on the frame, crossmembers showing under the floor.
    yb = p["bearer_y"]
    for x in (-0.43, 0.43):
        box(V(x, (yb + y0) / 2, (z0 + z1) / 2), (0.1, y0 - yb, z0 - z1), "under")
    for i in range(int((z0 - z1) / 0.5)):
        box(V(0, y0 - 0.04, z0 - 0.25 - i * 0.5), (2 * hw - 0.2, 0.08, 0.07), "under")
    # Rear frame and door.
    fdecal(z1, -hw, hw, y1 - 0.12, y1, "silver", out=-1)
    for sx in (1, -1):
        x0, x1 = sorted((sx * hw, sx * (hw - 0.1)))
        fdecal(z1, x0, x1, y0, y1, "silver", out=-1)
    if p["door"] == "roll":
        for i in range(1, 12):
            y = lerp(y0 + 0.05, y1 - 0.12, i / 12)
            fdecal(z1 - 0.003, -hw + 0.1, hw - 0.1, y - 0.008, y + 0.008, "post", out=-1)
        fdecal(z1 - 0.003, -0.12, 0.12, y0 + 0.12, y0 + 0.18, "grey", out=-1)
    else:
        fdecal(z1 - 0.003, -0.012, 0.012, y0, y1 - 0.12, "seam", out=-1)
        for x in (-0.75, -0.3, 0.3, 0.75):
            box(V(x, (y0 + y1 - 0.12) / 2, z1 - 0.025), (0.03, y1 - y0 - 0.2, 0.03), "silver")
            box(V(x + (0.07 if x > 0 else -0.07), lerp(y0, y1, 0.42), z1 - 0.04), (0.12, 0.03, 0.03), "silver")
    # Clearance lamps: amber at the front top corners, red at the back with the three
    # ID lamps in the middle.
    for sx in (1, -1):
        box(V(sx * (hw - 0.05), y1 - 0.06, z0 + 0.025), (0.07, 0.05, 0.04), "amber")
        box(V(sx * (hw - 0.05), y1 - 0.06, z1 - 0.025), (0.07, 0.05, 0.04), "tail")
        box(V(sx * (hw + 0.01), y0 + 0.08, z0 - 0.15), (0.03, 0.05, 0.1), "amber")
        box(V(sx * (hw + 0.01), y0 + 0.08, z1 + 0.15), (0.03, 0.05, 0.1), "tail")
    for x in (-0.25, 0.0, 0.25):
        box(V(x, y1 - 0.06, z1 - 0.025), (0.07, 0.05, 0.04), "tail")
    if p["reefer"]:
        # The refrigeration unit high on the nose, over the cab roof.
        uy0, uy1 = p["roof"] + 0.12, y1 - 0.06
        box(V(0, (uy0 + uy1) / 2, z0 + 0.21), (1.8, uy1 - uy0, 0.42), "reefer")
        fdecal(z0 + 0.42, -0.62, 0.1, uy0 + 0.1, uy1 - 0.12, "black")
        for i in range(1, 6):
            y = lerp(uy0 + 0.1, uy1 - 0.12, i / 6)
            fdecal(z0 + 0.424, -0.62, 0.1, y - 0.015, y + 0.015, "grey")
        fdecal(z0 + 0.42, 0.22, 0.7, uy0 + 0.1, uy1 - 0.12, "post")
        fdecal(z0 + 0.424, 0.5, 0.62, uy1 - 0.24, uy1 - 0.17, "amber")
        for sx in (1, -1):
            poly([V(sx * 0.906, y, z) for y, z in ((uy0 + 0.1, z0 + 0.06), (uy0 + 0.1, z0 + 0.36), (uy1 - 0.1, z0 + 0.36), (uy1 - 0.1, z0 + 0.06))],
                 "grey", V(sx, 0, 0))
    rear_end(s, z1, hw, y0)


def tank_body(s, z0, z1):
    """A fuel tank: a flat-sided oval with a painted stripe, girth bands, manlids under a
    walkway rail, a ladder and hose cabinet at the back, hazmat placards."""
    p = s.p
    hw, hh = p["W"] / 2 - 0.04, p["tank_h"] / 2
    yc = p["tank_y0"] + hh
    prof = [(0.0, 1.0), (0.45, 0.97), (0.8, 0.84), (0.97, 0.52), (1.0, 0.18), (1.0, -0.18), (0.97, -0.52), (0.8, -0.84), (0.45, -0.97)]
    half = [(hw * x, yc + hh * y) for x, y in prof]
    sec = half + [(0.0, yc - hh)] + [(-x, y) for x, y in reversed(half[1:])]

    def ring(z, k=1.0):
        return [V(x * k, yc + (y - yc) * k, z) for x, y in sec]
    zs = [z0, z0 - 0.12]
    nb = max(2, round((z0 - z1) / p["band"]))
    for i in range(1, nb):
        z = lerp(z0 - 0.12, z1 + 0.12, i / nb)
        zs += [z + 0.03, z - 0.03]
    zs += [z1 + 0.12, z1]
    rings = [ring(z, 0.8 if z in (z0, z1) else 1.0) for z in zs]
    stripe = {4, len(sec) - 5}
    band = lambda i: 0 < i < len(zs) - 2 and i % 2 == 0

    tk = p["tank_key"]

    def key(i, j):
        if band(i): return "silver" if tk != "chrome" else "grey"
        return p["stripe"] if p["stripe"] and j in stripe else tk
    loft(rings, key, caps=False)
    poly(rings[0], tk, V(0, 0, 1))
    poly(rings[-1], tk, V(0, 0, -1))
    # Saddles down to the frame.
    if yc - hh * 0.9 > 1.05:
        for z in (z0 - 0.5, (z0 + z1) / 2, z1 + 0.5):
            box(V(0, (1.0 + yc - hh * 0.9) / 2, z), (1.1, yc - hh * 0.9 - 1.0, 0.16), "black")
    # Manlids and the walkway rail.
    for i in range(3):
        z = lerp(z0 - 0.8, z1 + 0.8, i / 2)
        cyl(V(0, yc + hh - 0.02, z), V(0, yc + hh + 0.12, z), 0.24, "grey", 8)
    for sx in (1, -1):
        bar(V(sx * 0.45, yc + hh + 0.3, z0 - 0.3), V(sx * 0.45, yc + hh + 0.3, z1 + 0.3), 0.035, 0.035, "silver")
        for i in range(5):
            z = lerp(z0 - 0.3, z1 + 0.3, i / 4)
            box(V(sx * 0.45, yc + hh + 0.15, z), (0.035, 0.3, 0.035), "silver")
    # Product line along the lower side, valves under the tank.
    bar(V(hw * 0.86, yc - hh * 0.72, z0 - 0.3), V(hw * 0.86, yc - hh * 0.72, z1 + 0.4), 0.06, 0.06, "silver")
    for i in range(3):
        box(V(hw * 0.55, yc - hh * 0.95, lerp(z0 - 0.8, z1 + 0.8, i / 2)), (0.2, 0.16, 0.2), "grey")
    # Placards: red diamonds, side and back.
    def diamond(c, out, k=0.2):
        dirs = (V(0, k, 0), V(0, 0, k), V(0, -k, 0), V(0, 0, -k)) if out.x else (V(0, k, 0), V(k, 0, 0), V(0, -k, 0), V(-k, 0, 0))
        poly([c + d for d in dirs], "tape", out)
        poly([c + out * 0.004 + d * 0.45 + V(0, -k * 0.35, 0) for d in dirs], "plate", out)
    for sx in (1, -1):
        diamond(V(sx * (hw + 0.008), yc, z1 + 0.7), V(sx, 0, 0))
    diamond(V(0, yc + 0.1, z1 - 0.008), V(0, 0, -1))
    # Hose cabinet under the back of the tank, ladder up the back.
    box(V(0, 1.12, z1 + 0.25), (2 * hw - 0.2, 0.42, 0.5), "silver")
    fdecal(z1, -0.6, 0.6, 0.97, 1.27, "grey", out=-1)
    for x in (0.3, 0.62):
        box(V(x, yc + 0.2, z1 - 0.12), (0.04, 2 * hh + 0.5, 0.04), "silver")
    for i in range(7):
        box(V(0.46, lerp(1.4, yc + hh + 0.3, i / 6), z1 - 0.12), (0.32, 0.03, 0.03), "silver")
    rear_end(s, z1, hw, 0.92)


# --- Builds ---------------------------------------------------------------------------

def build_straight(p):
    s = TS(); s.p = p
    PAL["body"] = p["paint"]
    s.zF, s.zR = p["L"] / 2, -p["L"] / 2
    s.zfa = s.zF - p["fo"]
    rear = [s.zfa - p["wb"]] if not p["tandem"] else [s.zfa - p["wb"] + 0.66, s.zfa - p["wb"] - 0.66]
    md_cab(s)
    z0 = s.zb - p["body_gap"]
    frame(s, s.zF - 0.3, s.zR + 0.2)
    if p["body"] == "tank":
        tank_body(s, z0, s.zR + 0.05)
        rear_fenders(p, rear, p["track"] + 0.02)
    else:
        box_body(s, z0, s.zR)
        mud_flap(p, min(rear) - p["r"] - 0.15, p["track"])
    axle(p, s.zfa, False)
    for z in rear:
        axle(p, z, True)
    return s


def build_step(p):
    """A walk-in step van: one body from a short nose to a barn-door back."""
    s = TS(); s.p = p
    PAL["body"] = p["paint"]
    zF, zR = p["L"] / 2, -p["L"] / 2
    s.zF, s.zR = zF, zR
    zfa = zF - p["fo"]; zra = zfa - p["wb"]
    r, R = p["r"], p["r"] + 0.07
    hw, H = p["W"] / 2, p["H"]
    zn = zF - 0.2                 # nose face
    zws = zF - p["hood"]          # windscreen foot
    zwt = zws - 0.22              # windscreen top
    ywt = H - 0.48

    def top(z):
        if z > zws: return lerp(p["hood_y"] - 0.06, p["hood_y"], min((zn - z) / 0.12, 1.0))
        if z > zwt: return lerp(p["hood_y"], ywt, (zws - z) / (zws - zwt))
        return H

    def half(z):
        return hw - 0.08 * (1 - min((zn - z) / 0.25, 1.0)) ** 2

    def ring(z, ytop=None):
        yb = arch_bottom(z, p["sill"], (zfa, zra), r, R)
        return rrect(z, half(z), yb, ytop if ytop is not None else top(z), 0.06)
    zs = arch_stations((zfa, zra), R, zn, zR)
    zs = sorted(set(zs) | {zn - 0.06, zn - 0.14, zws, zwt}, reverse=True)
    rings = []
    for z in zs:
        # (a vertical header over the windscreen: two rings at its top)
        rings += [ring(z, ywt), ring(z, H)] if z == zwt else [ring(z)]
    loft(rings, lambda i, j: "black" if j == 6 else "body", caps=False)
    poly(rings[0], "body", V(0, 0, 1))
    poly(rings[-1], "body", V(0, 0, -1))
    # Roof peak over the windscreen.
    box(V(0, H - 0.04, zwt + 0.02), (2 * hw - 0.04, 0.08, 0.16), "body")
    # Windscreen (two panes), side window by the driver, the folding door's glass.
    a, b = V(0, p["hood_y"], zws), V(0, ywt, zwt)
    d = b - a
    nrm = V(0, -d.z, d.y).normalized()
    for x0, x1 in ((0.04, hw - 0.12), (-(hw - 0.12), -0.04)):
        q0, q1 = lerp(a, b, 0.08) + nrm * 0.006, lerp(a, b, 0.92) + nrm * 0.006
        poly([q0 + V(x0, 0, 0), q0 + V(x1, 0, 0), q1 + V(x1, 0, 0), q1 + V(x0, 0, 0)], "glass", nrm)
    for sx in (1, -1):
        sdecal(sx * hw, zwt - 0.75, zwt - 0.08, p["hood_y"] + 0.05, ywt - 0.02, "glass", both=False)
        sdecal(sx * hw, zwt - 0.8, zwt - 0.77, p["sill"] + 0.05, H - 0.15, "seam", both=False)
        sdecal(sx * hw, zwt - 1.2, zwt - 0.9, p["hood_y"] + 0.15, ywt - 0.1, "glass", both=False)
        sdecal(sx * hw, zwt - 1.23, zwt - 1.2, p["sill"] + 0.05, H - 0.15, "seam", both=False)
    # A crease down each side, rub strip low.
    sdecal(hw, zR + 0.05, zwt - 1.25, p["hood_y"] - 0.04, p["hood_y"] - 0.02, "seam")
    # Nose: grille between stacked lamps, black bumper.
    fdecal(zn, -0.42, 0.42, 0.7, p["hood_y"] - 0.12, "black")
    for i in range(1, 4):
        y = lerp(0.7, p["hood_y"] - 0.12, i / 4)
        fdecal(zn + 0.004, -0.4, 0.4, y - 0.012, y + 0.012, "grey")
    for sx in (1, -1):
        x0, x1 = sorted((sx * 0.5, sx * 0.78))
        fdecal(zn, x0, x1, p["hood_y"] - 0.4, p["hood_y"] - 0.14, "head")
        fdecal(zn, x0, x1, p["hood_y"] - 0.58, p["hood_y"] - 0.44, "amber")
    s.head = V(0.64, p["hood_y"] - 0.27, zn)
    box(V(0, 0.5, zF - 0.1), (2 * hw + 0.02, 0.3, 0.2), "black")
    # Marker lamps along the roof edges.
    for sx in (1, -1):
        for z in (zwt - 0.05, zR + 0.05):
            box(V(sx * (hw - 0.08), H + 0.02, z), (0.08, 0.04, 0.06), "amber" if z > 0 else "tail")
    for x in (-0.2, 0.0, 0.2):
        box(V(x, H + 0.02, zwt - 0.05), (0.07, 0.04, 0.06), "amber")
    # Rear: barn doors with windows, tail lamps up the corners, bumper.
    fdecal(zR, -0.012, 0.012, p["sill"] + 0.1, H - 0.1, "seam", out=-1)
    for x0, x1 in ((0.2, 0.75), (-0.75, -0.2)):
        fdecal(zR, x0, x1, H - 1.0, H - 0.35, "glass", out=-1)
    for sx in (1, -1):
        x0, x1 = sorted((sx * (hw - 0.04), sx * (hw - 0.2)))
        fdecal(zR, x0, x1, 0.9, 1.35, "tail", out=-1)
        fdecal(zR, x0, x1, 0.78, 0.88, "reverse", out=-1)
    s.tail = V(hw - 0.12, 1.12, zR)
    box(V(0, 0.48, zR - 0.08), (2 * hw - 0.1, 0.2, 0.16), "black")
    box(V(0, 0.26, zR + 0.3), (0.5, 0.06, 0.3), "grey")  # (the rear step)
    frame(s, zF - 0.3, zR + 0.1, p["sill"])
    box(V(0, p["sill"] - 0.15, (zfa + zra) / 2), (0.9, 0.3, 1.8), "under")
    tp = dict(p); tp["track"] = hw - 0.02
    axle(tp, zfa, False)
    axle(tp, zra, True)
    mud_flap(tp, zra - r - 0.15, hw)
    return s


def build_tractor(p):
    """A Class 8 tractor: conventional cab (day or sleeper), tandem drive axles, a
    fifth wheel (s.hitch, where a trailer's kingpin sits)."""
    s = TS(); s.p = p
    PAL["body"] = p["paint"]
    s.zF, s.zR = p["L"] / 2, -p["L"] / 2
    s.zfa = s.zF - p["fo"]
    zd = s.zfa - p["wb"]
    rear = [zd + 0.66, zd - 0.66]
    s.skirt_end = rear[0] + p["r"] + 0.14
    md_cab(s)
    fy, frame_y = p["fw_y"], p["frame_y"]
    frame(s, s.zF - 0.3, s.zR + 0.05, frame_y)
    axle(p, s.zfa, False)
    for z in rear:
        axle(p, z, True)
    quarter_fenders(p, rear)
    # Fifth wheel on its mount, the jaws' slot open to the back.
    fw = zd + p["fw_ahead"]
    box(V(0, (frame_y + fy - 0.06) / 2, fw), (0.9, fy - 0.06 - frame_y, 0.6), "black")
    box(V(0, fy - 0.03, fw), (1.0, 0.06, 1.0), "gunmetal")
    poly([V(x, fy + 0.004, z) for x, z in ((-0.08, fw), (0.08, fw), (0.12, fw - 0.5), (-0.12, fw - 0.5))], "black", V(0, 1, 0))
    s.hitch = V(0, fy, fw)
    # Deck plate behind the cab, air and electric lines coiled on the back wall.
    if s.zb - (fw + 0.55) > 0.2:
        box(V(0, frame_y + 0.02, (s.zb + fw + 0.55) / 2), (1.0, 0.04, s.zb - fw - 0.55), "silver")
    for x, key in ((-0.15, "caliper"), (0.0, "accent2"), (0.15, "black")):
        cyl(V(x, frame_y + 0.6, s.zb - 0.05), V(x, frame_y + 0.6, s.zb - 0.12), 0.12, key, 8)
    # Rear crossmember with the tail lamps, mud flaps on hangers.
    zr = s.zR + 0.05
    hw = p["track"] - 0.15
    box(V(0, frame_y - 0.2, zr), (2 * hw, 0.14, 0.1), "black")
    for sx in (1, -1):
        x0, x1 = sorted((sx * (hw - 0.3), sx * (hw - 0.06)))
        fdecal(zr - 0.05, x0, x1, frame_y - 0.25, frame_y - 0.15, "tail", out=-1)
    s.tail = V(hw - 0.18, frame_y - 0.2, zr - 0.05)
    mud_flap(p, rear[1] - p["r"] - 0.15, p["track"])
    return s


# --- Trailers -------------------------------------------------------------------------
# A semi-trailer: +Z front, its kingpin (s.pin) under the front at the tractors' fifth
# wheel height, a tandem (s.axle the group's centre, where it pivots when the rig turns).

def landing_gear(s, z, y_top):
    for sx in (1, -1):
        box(V(sx * 0.82, (y_top + 0.3) / 2, z), (0.1, y_top - 0.3, 0.1), "black")
        box(V(sx * 0.82, 0.28, z), (0.24, 0.05, 0.28), "black")
    bar(V(0.82, 0.75, z), V(-0.82, 0.75, z), 0.05, 0.05, "black")
    box(V(0.95, 0.85, z), (0.18, 0.12, 0.05), "silver")  # (the crank)


def trailer_bogie(s, za, hw, deck_y):
    """The tandem on its slider, mud flaps behind."""
    p = s.p
    axles = [za + 0.62, za - 0.62]
    for z in axles:
        axle(p, z, True)
    box(V(0, (2 * p["r"] + 0.15 + deck_y) / 2, za), (1.1, deck_y - 2 * p["r"] - 0.15, 2.6), "black")
    mud_flap(p, min(axles) - p["r"] - 0.18, p["track"])
    s.axle = V(0, 0, za)


def trailer_start(p):
    s = TS(); s.p = p
    PAL["body"] = p["paint"]
    s.zF, s.zR = p["L"] / 2, -p["L"] / 2
    s.pin = V(0, p["fw_y"], s.zF - p["kp"])
    s.head = V(0, 0, 0)  # (no headlamps)
    # Upper coupler plate and the kingpin.
    box(V(0, p["fw_y"] + 0.04, s.zF - 1.0), (1.8, 0.08, 1.9), "under")
    cyl(V(0, p["fw_y"], s.pin.z), V(0, p["fw_y"] - 0.07, s.pin.z), 0.05, "grey", 6)
    return s


def build_trailer(p):
    s = trailer_start(p)
    zF, zR = s.zF, s.zR
    hw = p["W"] / 2
    body = p["body"]
    za = zR + p["ro"]
    if body in ("van", "reefer"):
        box_body(s, zF, zR)
        if p["skirts"]:
            for sx in (1, -1):
                sdecal(sx * (hw - 0.04), za + 1.3, zF - 3.5, 0.45, p["floor"] - 0.02, "boxw", both=False, eps=0.0)
                poly([V(sx * (hw - 0.04), y, z) for y, z in ((0.45, za + 1.3), (0.45, zF - 3.5), (p["floor"], zF - 3.5), (p["floor"], za + 1.3))],
                     "boxw", V(-sx, 0, 0))
        landing_gear(s, zF - 3.3, p["floor"] - 0.3)
        trailer_bogie(s, za, hw, p["floor"] - 0.1)
    elif body == "container":
        container_chassis(s, zF, zR, za)
    elif body == "flatbed":
        flatbed(s, zF, zR, za)
    elif body == "logs":
        log_trailer(s, zF, zR, za)
    elif body == "tank":
        tank_body(s, zF - 0.05, zR + 0.1)
        for z in (zF - 1.1, za + 1.3):
            box(V(0, 0.98, z), (1.2, 0.2, 0.9), "black")
        landing_gear(s, zF - 2.6, 1.0)
        trailer_bogie(s, za, hw, 1.0)
    elif body == "dump":
        dump_body(s, zF, zR, za)
    elif body == "carhauler":
        car_hauler(s, zF, zR, za)
    return s


def beams(s, z0, z1, y_top, depth=0.42, x=0.5, key="black"):
    """A trailer's main I-beams."""
    for sx in (1, -1):
        box(V(sx * x, y_top - depth / 2, (z0 + z1) / 2), (0.12, depth, z0 - z1), key)
    n = int((z0 - z1) / 1.2)
    for i in range(n + 1):
        box(V(0, y_top - 0.08, lerp(z0 - 0.1, z1 + 0.1, i / max(n, 1))), (2 * x, 0.1, 0.08), key)


def container_chassis(s, zF, zR, za):
    """A 40' box on a skeletal chassis: corrugated sides, corner castings, door locking
    bars."""
    p = s.p
    hw, y0, y1 = p["W"] / 2, p["floor"], p["H"]
    beams(s, zF - 0.2, zR + 0.1, y0, 0.36)
    for z in (zF - 0.15, zR + 0.15):
        box(V(0, y0 - 0.1, z), (2 * hw, 0.2, 0.2), "black")
    loft([rrect(zF, hw, y0, y1), rrect(zR, hw, y0, y1)], "body")
    # Corrugations: darker grooves down the sides, rails top and bottom.
    n = int((zF - zR) / 0.28)
    for i in range(1, n):
        z = lerp(zF - 0.15, zR + 0.15, i / n)
        sdecal(hw, z - 0.05, z + 0.05, y0 + 0.12, y1 - 0.1, "accent")
    sdecal(hw, zR, zF, y0, y0 + 0.12, "accent")
    sdecal(hw, zR, zF, y1 - 0.1, y1, "accent")
    for i in range(1, 7):
        x = lerp(-hw + 0.1, hw - 0.1, i / 7)
        fdecal(zF, x - 0.06, x + 0.06, y0 + 0.12, y1 - 0.1, "accent")
    # Corner castings.
    for sx in (1, -1):
        for y in (y0 + 0.06, y1 - 0.06):
            for z in (zF - 0.08, zR + 0.08):
                box(V(sx * (hw - 0.08), y, z), (0.18, 0.13, 0.18), "grey")
    # Doors: the seam, four locking bars with their handles.
    fdecal(zR, -0.012, 0.012, y0 + 0.1, y1 - 0.1, "seam", out=-1)
    for x in (-0.95, -0.4, 0.4, 0.95):
        box(V(x, (y0 + y1) / 2, zR - 0.025), (0.035, y1 - y0 - 0.15, 0.035), "grey")
        box(V(x + (0.08 if x > 0 else -0.08), lerp(y0, y1, 0.4), zR - 0.04), (0.14, 0.03, 0.03), "grey")
    landing_gear(s, zF - 2.8, y0 - 0.2)
    trailer_bogie(s, za, hw, y0 - 0.36)
    rear_end(s, zR - 0.1, hw - 0.04, y0 - 0.02)


def flatbed(s, zF, zR, za):
    """A 48' flatbed: a wood deck on a steel frame, stake pockets down the rails."""
    p = s.p
    hw, y = p["W"] / 2, p["floor"]
    beams(s, zF - 0.2, zR + 0.15, y - 0.12, 0.5)
    box(V(0, y - 0.06, (zF + zR) / 2), (2 * hw, 0.12, zF - zR), "black")
    poly([V(x, y + 0.002, z) for x, z in ((hw - 0.06, zF - 0.06), (-hw + 0.06, zF - 0.06), (-hw + 0.06, zR + 0.06), (hw - 0.06, zR + 0.06))],
         "deck", V(0, 1, 0))
    for x in (-0.6, 0.0, 0.6):
        poly([V(xx, y + 0.004, z) for xx, z in ((x + 0.008, zF - 0.06), (x - 0.008, zF - 0.06), (x - 0.008, zR + 0.06), (x + 0.008, zR + 0.06))],
             "seam", V(0, 1, 0))
    n = int((zF - zR) / 0.6)
    for i in range(1, n):
        z = lerp(zF, zR, i / n)
        sdecal(hw, z - 0.04, z + 0.04, y - 0.1, y - 0.02, "seam")
    tape_side(hw, zF - 0.1, zR + 0.1, y - 0.07)
    for sx in (1, -1):
        box(V(sx * (hw - 0.05), y - 0.04, zF + 0.025), (0.07, 0.05, 0.04), "amber")
    landing_gear(s, zF - 3.0, y - 0.6)
    trailer_bogie(s, za, hw, y - 0.62)
    rear_end(s, zR, hw, y - 0.12)


def log_trailer(s, zF, zR, za):
    """A log trailer: a pole frame with bunks and stakes, loaded with long logs (an
    octagon each, the cut ends lighter)."""
    p = s.p
    hw, y = p["W"] / 2, p["floor"]
    beams(s, zF - 0.2, zR + 0.4, y - 0.15, 0.4, 0.4)
    bunks = [zF - 0.6, zF - 4.4, za + 1.7, za - 0.6]
    for z in bunks:
        box(V(0, y - 0.05, z), (2 * hw, 0.2, 0.22), "black")
        for sx in (1, -1):
            box(V(sx * (hw - 0.06), y + 0.95, z), (0.12, 1.9, 0.14), "black")
            sdecal(sx * (hw - 0.06) + sx * 0.06, z - 0.07, z + 0.07, y + 0.9, y + 1.0, "tape", both=False)
    # The load: three rows of logs, overhanging the back.
    lr = 0.24
    rows = [(-0.84, 0), (-0.28, 0), (0.28, 0), (0.84, 0), (-0.56, 1), (0.0, 1), (0.56, 1), (-0.28, 2), (0.28, 2)]
    for i, (x, row) in enumerate(rows):
        yy = y + 0.05 + lr + row * 2 * lr * 0.88
        z0, z1 = zF - 0.3 - 0.15 * (i % 3), zR - 0.6 + 0.2 * (i % 2)
        cyl(V(x, yy, z0), V(x, yy, z1), lr * (0.92 + 0.08 * (i % 3) / 2), "log", 8)
        for z, out in ((z0, 1), (z1, -1)):
            poly([q + V(0, 0, out * 0.004) for q in disc_pts_xy(V(x, yy, z), lr * 0.85, 8)], "logend", V(0, 0, out))
    # Binder chains over the load.
    for z in bunks[1:3]:
        bar(V(hw - 0.1, y + 1.9, z), V(-hw + 0.1, y + 1.9, z), 0.03, 0.03, "grey")
    landing_gear(s, zF - 2.4, y - 0.4)
    trailer_bogie(s, za, hw, y - 0.55)
    rear_end(s, zR + 0.3, hw - 0.2, y - 0.2)
    # (a red flag on the overhanging logs)
    poly([V(0.1, y + 0.5, zR - 0.6), V(0.4, y + 0.5, zR - 0.6), V(0.25, y + 0.2, zR - 0.6)], "tape", V(0, 0, -1))


def disc_pts_xy(c, r, n):
    """Points round a circle in the x-y plane (a log's end)."""
    return [c + V(r * math.cos(math.tau * i / n + math.pi / 8), r * math.sin(math.tau * i / n + math.pi / 8), 0) for i in range(n)]


def dump_body(s, zF, zR, za):
    """An end-dump: a ribbed tub (sloped nose, flared top rail), a tarp arm, a top-hinged
    tailgate."""
    p = s.p
    hw, y0, y1 = p["W"] / 2, p["floor"], p["H"]
    beams(s, zF - 0.4, zR + 0.15, y0 - 0.05, 0.45)
    zn = zF - 0.5
    prof = [(zn - 0.5, y0), (zn, y0 + 0.6), (zF, y1)]
    rg = lambda z, yt, yb: rrect(z, hw, yb, yt, 0.0, 0.25)
    rings = [rg(zF, y1, y0 + 0.6 + 0.15), rg(zn, y1, y0 + 0.6), rg(zn - 0.5, y1, y0), rg(zR, y1, y0)]
    loft(rings, "body", caps=False)
    poly(rings[0], "body", V(0, 0, 1))
    poly(rings[-1], "body", V(0, 0, -1))
    # Loaded: gravel heaped to the rim.
    poly([V(x, y1 + 0.003, z) for x, z in ((hw - 0.08, zF - 0.08), (-hw + 0.08, zF - 0.08), (-hw + 0.08, zR + 0.12), (hw - 0.08, zR + 0.12))],
         "gravel", V(0, 1, 0))
    # Ribs, top rail.
    n = int((zn - zR) / 0.9)
    for i in range(n + 1):
        z = lerp(zn - 0.5, zR + 0.15, i / max(n, 1))
        box(V(hw + 0.03, (y0 + y1) / 2, z), (0.06, y1 - y0, 0.1), "body")
        box(V(-hw - 0.03, (y0 + y1) / 2, z), (0.06, y1 - y0, 0.1), "body")
    for sx in (1, -1):
        box(V(sx * (hw + 0.04), y1 - 0.06, (zF + zR) / 2), (0.1, 0.12, zF - zR), "body")
    tape_side(hw + 0.065, zn - 0.6, zR + 0.2, y0 + 0.08)
    # Tarp arm across the side.
    bar(V(hw + 0.1, y0 + 0.4, zF - 1.2), V(hw + 0.1, y1 + 0.05, zR + 2.5), 0.08, 0.08, "grey")
    cyl(V(hw - 0.2, y1 + 0.1, zF - 0.1), V(-hw + 0.2, y1 + 0.1, zF - 0.1), 0.12, "black", 8)
    # Tailgate hinged at the top.
    fdecal(zR, -hw + 0.1, hw - 0.1, y0 + 0.1, y1 - 0.15, "accent", out=-1)
    landing_gear(s, zF - 2.6, y0 - 0.4)
    trailer_bogie(s, za, hw, y0 - 0.5)
    rear_end(s, zR, hw - 0.04, y0 - 0.05)


def car_hauler(s, zF, zR, za):
    """A two-level car hauler: an upper deck on posts; the lower deck climbs a gooseneck
    over the fifth wheel, drops low in the middle and rises again over the bogie.
    Diamond-plate track runways, a ladder up the front post."""
    p = s.p
    hw = p["W"] / 2
    yg, yl, yu, yt = p["fw_y"] + 0.14, 0.78, 2.55, 3.95
    zg = zF - 2.6                    # end of the gooseneck
    zb0, zb1 = za + 1.4, za - 1.4    # over the bogie
    # The lower deck's profile, front to back.
    prof = [(zF, yg), (zg, yg), (zg - 0.6, yl), (zb0 + 0.6, yl), (zb0, 2 * p["r"] + 0.25), (zR, 2 * p["r"] + 0.25)]
    for sx in (1, -1):
        for (z0, y0), (z1, y1) in zip(prof, prof[1:]):
            bar(V(sx * 0.8, y0 - 0.25, z0), V(sx * 0.8, y1 - 0.25, z1), 0.14, 0.25, "body")
            for x in (0.45, 0.95):
                bar(V(sx * x, y0, z0), V(sx * x, y1, z1), 0.42, 0.04, "silver")
        bar(V(sx * (hw - 0.06), yu, zF), V(sx * (hw - 0.06), yu, zR), 0.1, 0.16, "body")
        bar(V(sx * (hw - 0.06), yt - 0.12, zF - 0.4), V(sx * (hw - 0.06), yt - 0.12, zR + 0.4), 0.08, 0.12, "body")
        for i in range(6):
            z = lerp(zF - 0.4, zR + 0.4, i / 5)
            yb = next(lerp(y0, y1, (z0 - z) / (z0 - z1)) for (z0, y0), (z1, y1) in zip(prof, prof[1:]) if z1 <= z <= z0) - 0.25
            box(V(sx * (hw - 0.06), (yb + yt) / 2, z), (0.1, yt - yb, 0.1), "body")
        for i in range(5):
            z0, z1 = lerp(zF - 0.4, zR + 0.4, i / 5), lerp(zF - 0.4, zR + 0.4, (i + 1) / 5)
            bar(V(sx * (hw - 0.06), yu - 0.9, z0), V(sx * (hw - 0.06), yu - 0.1, z1), 0.05, 0.06, "body")
        tape_side(hw - 0.01, zF, zR, yu + 0.04)
    for x in (-0.7, 0.7):
        box(V(x, yu + 0.02, (zF + zR) / 2), (0.5, 0.04, zF - zR - 0.2), "silver")
    for z in (zF - 0.2, zg, zb0, zR + 0.2):
        yb = next(lerp(y0, y1, (z0 - z) / (z0 - z1)) for (z0, y0), (z1, y1) in zip(prof, prof[1:]) if z1 <= z <= z0)
        box(V(0, yb - 0.2, z), (1.7, 0.12, 0.12), "body")
    # Ladder up the front post.
    for x in (hw - 0.02, hw - 0.3):
        box(V(x, (yg + yt) / 2, zF - 0.1), (0.035, yt - yg, 0.035), "silver")
    for i in range(7):
        box(V(hw - 0.16, lerp(yg + 0.2, yt - 0.2, i / 6), zF - 0.1), (0.28, 0.03, 0.03), "silver")
    landing_gear(s, zg + 0.3, yg - 0.25)
    trailer_bogie(s, za, hw, 2 * p["r"])
    rear_end(s, zR, hw - 0.06, 2 * p["r"] + 0.05)


def build_truck(p):
    return {"step": build_step, "tractor": build_tractor, "trailer": build_trailer}.get(p["kind"], build_straight)(p)
