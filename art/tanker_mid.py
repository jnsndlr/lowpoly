# Builds the mid-poly product tanker in Blender (run inside Blender, or headless:
# Blender -b --python art/tanker_mid.py) and exports it to assets/models/tanker_mid.glb.
# The ship itself is the container feeder's (art/cargo_mid.py, run here as a base: hull,
# forecastle, accommodation, poop), so CargoMidData's lights and name surface hold for it
# too; this adds the tank deck: the cargo lines on their rack under the flying catwalk,
# with expansion loops, the manifold amidships in its drip trays and the hose crane, the
# tank hatches with their cleaning hatches and P/V vents, foam monitors before the house
# and at the manifold, and the air pipes along the sides.
# Parts as the container ship's, plus `deck` (the deck paint, one flat colour).
import math, os
_here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/Users/jon/Documents/GitHub/lowpoly/art"
CARGO_BASE_ONLY = True
exec(open(os.path.join(_here, "cargo_mid.py")).read())

ROLES = ("hull", "funnel", "glass", "window", "lens", "deck")
PAL.update({"pipe": (0.78, 0.79, 0.76), "valve": (0.2, 0.36, 0.62), "red": (0.75, 0.15, 0.13),
            "walk": (0.8, 0.82, 0.82)})

DECK_Z = (-20.0, FC_Z)                         # the tank deck, house front to forecastle
TANK_Z = (-17.5, -10.5, -3.5, 3.5, 10.5, 17.5)  # a tank hatch each side at each
MANIFOLD_Z = (-1.05, -0.35, 0.35, 1.05)
CAT_Y = 5.7                                    # the catwalk's floor: level with the house's first deck


def pipe_rack():
    """The cargo and vapour lines on saddles down the middle of the deck, two of the
    outer ones bowed out in an expansion loop each; the catwalk over them."""
    z0, z1 = DECK_Z[0] + 0.1, DECK_Z[1] - 0.1
    lines = [(-1.45, 3.75, 0.2), (-0.95, 3.75, 0.2), (-0.45, 3.72, 0.17), (0.45, 3.72, 0.17), (0.95, 3.75, 0.2),
             (1.45, 3.62, 0.08)]
    loops = {0: (-8.0, -1), 4: (8.0, 1)}
    for k, (x, y, r) in enumerate(lines):
        if k in loops:
            zc, sx = loops[k]
            bow = 1.6 * sx
            path = [V(x, y, z0), V(x, y, zc - 1.6), V(x + bow * 0.15, y, zc - 1.3), V(x + bow, y, zc - 1.0),
                    V(x + bow, y, zc + 1.0), V(x + bow * 0.15, y, zc + 1.3), V(x, y, zc + 1.6), V(x, y, z1)]
            tube(path, r, 8, "pipe")
        else:
            cyl(V(x, y, z0), V(x, y, z1), r, r, 8, "pipe")
    # Saddles every 3 m, and the catwalk's posts on every other one.
    n = 15
    for i in range(n + 1):
        z = lerp(z0 + 0.6, z1 - 0.6, i / n)
        box(V(0, 3.38, z), (3.5, 0.16, 0.22), "deck")
        for x in (-1.75, 1.75):
            box(V(x, 3.4, z), (0.14, 0.4, 0.22), "deck")
        if i % 2 == 0:
            for x in (-0.55, 0.55):
                cyl(V(x * 3.4, DECK, z), V(x * 1.1, CAT_Y - 0.1, z), 0.07, 0.07, 4, "walk")
            box(V(0, CAT_Y - 0.15, z), (1.4, 0.12, 0.14), "walk")
    # The flying catwalk: grating, rails both sides; its stair down to the forecastle.
    zc, ln = (z0 + z1) / 2, z1 - z0
    box(V(0, CAT_Y - 0.04, zc), (1.1, 0.08, ln), "walk")
    for sx in (1, -1):
        rail([V(sx * 0.53, CAT_Y, z0), V(sx * 0.53, CAT_Y, z1 - 0.2)], 1.0, "walk", 1.8)
    # Crossovers down to the deck at the manifold: a short stair each side.
    for sx in (1, -1):
        a, b = V(sx * 0.6, CAT_Y, -2.4), V(sx * 2.0, DECK, -2.4)
        for dz in (-0.35, 0.35):
            beam_between(a + V(0, 0, dz), b + V(0, 0, dz), 0.05, 0.2, "walk")
        for i in range(1, 7):
            box(lerp(a, b, i / 7), (0.22, 0.04, 0.7), "walk")


def manifold():
    """Four lines across the deck at midships, each with its valve, out to flanged
    connections over the drip trays at either side; the crane that lifts the hoses."""
    for z in MANIFOLD_Z:
        cyl(V(-4.55, 3.75, z), V(4.55, 3.75, z), 0.17, 0.17, 8, "pipe")
        for sx in (1, -1):
            # Valve body and handwheel on the riser's top, the blank flange outboard.
            v = V(sx * 3.2, 3.75, z)
            box(v, (0.5, 0.5, 0.42), "valve")
            cyl(v + V(0, 0.25, 0), v + V(0, 0.75, 0), 0.04, 0.04, 4, "valve")
            cyl(v + V(0, 0.75, 0), v + V(0, 0.8, 0), 0.22, 0.22, 8, "valve")
            cyl(V(sx * 4.55, 3.75, z), V(sx * 4.7, 3.75, z), 0.28, 0.28, 10, "red")
            box(V(sx * 4.2, 3.32, z), (0.16, 0.24, 0.16), "deck")
        # Where the line meets the rack.
        cyl(V(0, 3.75, z), V(0, 3.38, z), 0.17, 0.17, 6, "pipe")
    for sx in (1, -1):
        # The drip tray (low walls, a dark floor), the platform the crew stand on.
        x0, x1, zz = sx * 3.7, sx * 5.0, 1.7
        box(V((x0 + x1) / 2, DECK + 0.02, 0), (1.3, 0.04, zz * 2), "black")
        for z in (-zz, zz):
            box(V((x0 + x1) / 2, DECK + 0.15, z), (1.3, 0.3, 0.06), "deck")
        box(V(x0, DECK + 0.15, 0), (0.06, 0.3, zz * 2), "deck")
        box(V(sx * 3.05, DECK + 0.6, -1.65), (0.9, 0.06, 0.6), "walk")
        # A foam monitor on its tower aft of the manifold.
        foam_monitor(V(sx * 3.4, DECK, -3.2), 2.2, V(sx * 0.3, 0.25, 1))
    hose_crane(V(-2.5, DECK, 2.0))


def hose_crane(base):
    """A pedestal crane, its jib stowed forward in a rest over the deck."""
    top = base + V(0, 3.4, 0)
    cyl(base, top, 0.45, 0.38, 10, "yellow")
    box(top + V(0, 0.4, -0.1), (1.0, 0.8, 1.2), "yellow")
    box(top + V(-0.48, 0.5, 0.3), (0.06, 0.4, 0.5), "glass")
    heel = top + V(0, 0.55, 0.45)
    head = V(-3.6, 4.9, 7.6)
    beam_between(heel, head, 0.36, 0.42, "yellow")
    # The rest: a post with a fork, outboard of the tank hatches.
    rest = V(head.x, DECK, head.z - 0.6)
    cyl(rest, rest + V(0, 1.4, 0), 0.08, 0.08, 4, "yellow")
    for dx in (-0.25, 0.25):
        box(rest + V(dx, 1.5, 0), (0.06, 0.3, 0.12), "yellow")
    # Luffing wire from the cab's top to the head, the hook block lashed under it.
    tube([top + V(0, 0.8, -0.3), head + V(0, 0.2, 0)], 0.02, 3, "black")
    tube([head, head - V(0, 0.85, 0)], 0.015, 3, "black")
    box(head - V(0, 1.0, 0), (0.18, 0.3, 0.14), "black")


def foam_monitor(foot, h, aim):
    """A fire/foam monitor on a post: a red body, the nozzle aimed along `aim`."""
    top = foot + V(0, h, 0)
    cyl(foot, top, 0.1, 0.1, 6, "red")
    box(top - V(0, 0.05, 0), (0.6, 0.1, 0.6), "walk")
    cyl(top, top + V(0, 0.35, 0), 0.14, 0.14, 8, "red")
    a = top + V(0, 0.45, 0)
    cyl(a, a + aim.normalized() * 0.9, 0.12, 0.06, 8, "red")


def tank_fittings():
    """Over each tank, either side: the cargo hatch on its trunk, a tank-cleaning hatch
    and the ullage port, and the tank's P/V valve on its riser."""
    for z in TANK_Z:
        for sx in (1, -1):
            x = sx * 3.1
            h = V(x, DECK, z)
            cyl(h, h + V(0, 0.45, 0), 0.42, 0.42, 10, "deck")
            cyl(h + V(0, 0.45, 0), h + V(0, 0.55, 0), 0.52, 0.5, 10, "pipe")
            box(h + V(0, 0.52, -0.55), (0.3, 0.12, 0.16), "dark")      # hinge, aft
            box(h + V(0, 0.58, 0.48), (0.16, 0.06, 0.12), "dark")      # the dog
            for dz, r in ((1.3, 0.2), (-1.2, 0.12)):
                c = V(sx * 3.3, DECK, z + dz)
                cyl(c, c + V(0, 0.22, 0), r, r, 8, "deck")
            # P/V valve: a riser off the vapour line, the valve's bell on top.
            p = V(sx * 2.25, DECK, z + 1.0)
            cyl(p, p + V(0, 1.9, 0), 0.09, 0.09, 6, "pipe")
            cyl(p + V(0, 1.9, 0), p + V(0, 2.2, 0), 0.2, 0.16, 8, "valve")
            cyl(p + V(0, 2.2, 0), p + V(0, 2.32, 0), 0.08, 0.08, 6, "valve")
            # The branch to the rack.
            tube([V(sx * 1.6, 3.75, z + 1.0), V(sx * 2.25, 3.75, z + 1.0), V(sx * 2.25, 3.95, z + 1.0)], 0.07, 6, "pipe")
            # Ballast tanks' air pipes along the side: goosenecks with their heads aft.
            g = deck_edge(z - 2.2, 0.45, sx)
            tube([g, g + V(0, 0.8, 0), g + V(0, 1.0, -0.2)], 0.1, 6, "deck")


def house_front():
    """The tank deck's after end: foam monitors on the house's first deck, a mast
    riser venting the tanks above it, the deck's foam main and hydrants."""
    for sx in (1, -1):
        foam_monitor(V(sx * 3.6, LEVELS[1], -19.5), 0.9, V(sx * 0.15, 0.2, 1))
        # A platform out from the house to carry it.
        box(V(sx * 3.6, LEVELS[1] - 0.06, -19.5), (1.4, 0.12, 1.2), "edge")
        beam_between(V(sx * 3.0, DECK, -19.1), V(sx * 3.6, LEVELS[1] - 0.12, -19.1), 0.1, 0.1, "edge")
        beam_between(V(sx * 4.2, DECK, -19.1), V(sx * 3.6, LEVELS[1] - 0.12, -19.1), 0.1, 0.1, "edge")
    # The vent mast: a tall riser at the house front, a flame screen's head on top.
    m = V(2.0, DECK, -19.6)
    cyl(m, m + V(0, 9.6, 0), 0.2, 0.16, 8, "pipe")
    cyl(m + V(0, 9.6, 0), m + V(0, 10.1, 0), 0.32, 0.26, 8, "dark")
    for y in (4.0, 7.0):
        beam_between(m + V(0, y, 0), V(2.0, m.y + y, -20.0), 0.08, 0.08, "pipe")
    # The foam main along the port side, a hydrant at each tank.
    zs = [DECK_Z[0] + 0.5, DECK_Z[1] - 0.6]
    cyl(V(4.3, 3.55, zs[0]), V(4.3, 3.55, zs[1]), 0.08, 0.08, 6, "red")
    for z in TANK_Z:
        cyl(V(4.3, 3.55, z - 2.0), V(4.3, 4.2, z - 2.0), 0.06, 0.06, 4, "red")
        box(V(4.3, 4.25, z - 2.0), (0.12, 0.12, 0.2), "red")


def tank_deck():
    pipe_rack(); manifold(); tank_fittings(); house_front()
    deck_rails(False)


result = export("tanker_mid", BASE + [tank_deck])
print("RESULT", result, sum(result.values()))
