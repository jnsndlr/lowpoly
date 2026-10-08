# Builds the mid-poly geared bulk carrier in Blender (run inside Blender, or headless:
# Blender -b --python art/bulker_mid.py) and exports it to assets/models/bulker_mid.glb.
# The ship itself is the container feeder's (art/cargo_mid.py, run here as a base), so
# CargoMidData's lights and name surface hold for it too; this adds the cargo deck: five
# holds under folding hatch covers on their coamings (the covers' hinges, cleats and the
# jacks that fold them), four deck cranes between the hatches, their jibs stowed forward
# in rests at alternate sides, hold vents and access hatches, the air pipes along the sides.
# Parts as the container ship's, plus `deck` (the deck and coamings), `hatch` (the covers)
# and `crane`, each one flat colour.
import math, os
_here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/Users/jon/Documents/GitHub/lowpoly/art"
CARGO_BASE_ONLY = True
exec(open(os.path.join(_here, "cargo_mid.py")).read())

ROLES = ("hull", "funnel", "glass", "window", "lens", "deck", "hatch", "crane")
PAL.update({"pipe": (0.78, 0.79, 0.76), "crane": (0.9, 0.74, 0.2), "hatch": (0.55, 0.18, 0.14)})

HOLD_Z = (-15.2, -6.6, 2.0, 10.6, 19.2)    # the hatches' middles, aft to forward
HOLD_LEN = 6.0
HOLD_HW = 3.5                             # the coaming's half breadth
COAMING_TOP = 4.5
CRANE_Z = [(a + b) / 2 for a, b in zip(HOLD_Z, HOLD_Z[1:])]
JIB_REST_X = 4.4


def holds():
    for zc in HOLD_Z:
        z0, z1 = zc - HOLD_LEN / 2, zc + HOLD_LEN / 2
        # The coaming, its top bar standing proud, the stays down its sides and ends.
        box(V(0, (DECK + COAMING_TOP) / 2, zc), (HOLD_HW * 2, COAMING_TOP - DECK, HOLD_LEN), "deck")
        box(V(0, COAMING_TOP - 0.05, zc), (HOLD_HW * 2 + 0.2, 0.1, HOLD_LEN + 0.2), "deck")
        for sx in (1, -1):
            for i in range(6):
                z = lerp(z0 + 0.5, z1 - 0.5, i / 5)
                tri = lambda zz: [V(sx * HOLD_HW, DECK, zz), V(sx * (HOLD_HW + 0.45), DECK, zz),
                                  V(sx * HOLD_HW, COAMING_TOP - 0.15, zz)]
                loft([tri(z - 0.04), tri(z + 0.04)], "deck")
        for sz, ze in ((1, z1), (-1, z0)):
            for x in (-2.4, 2.4):
                tri = lambda xx: [V(xx, DECK, ze), V(xx, DECK, ze + sz * 0.45), V(xx, COAMING_TOP - 0.15, ze)]
                loft([tri(x - 0.04), tri(x + 0.04)], "deck")
        covers(zc)
        # Mushroom vents for the hold at its after corners; an access hatch forward.
        for sx in (1, -1):
            v = V(sx * 4.35, DECK, z0 + 0.7)
            cyl(v, v + V(0, 1.1, 0), 0.18, 0.18, 8, "deck")
            cyl(v + V(0, 1.1, 0), v + V(0, 1.35, 0), 0.42, 0.3, 10, "deck")
            h = V(sx * 4.25, DECK, z1 - 0.9)
            box(h + V(0, 0.3, 0), (0.8, 0.6, 0.8), "deck")
            box(h + V(0, 0.64, 0), (0.86, 0.08, 0.86), "dark")
            # Ballast tanks' air pipes along the side: goosenecks, heads aft.
            g = deck_edge(zc, 0.45, sx)
            tube([g, g + V(0, 0.8, 0), g + V(0, 1.0, -0.2)], 0.1, 6, "deck")


def covers(zc):
    """A folding cover in two panels hinged athwartships at the hatch's middle, each
    cambered across with a skirt down to the coaming; cleats round the edge, the
    hinge's knuckles, the jacks at each end that fold it up."""
    hw = HOLD_HW + 0.05
    y0, ye, yc = COAMING_TOP, COAMING_TOP + 0.22, COAMING_TOP + 0.48
    prof = [(-hw, y0), (-hw, ye), (-1.4, yc), (1.4, yc), (hw, ye), (hw, y0)]
    for za, zb in ((zc - HOLD_LEN / 2 - 0.05, zc - 0.03), (zc + 0.03, zc + HOLD_LEN / 2 + 0.05)):
        loft([[V(x, y, za) for x, y in prof], [V(x, y, zb) for x, y in prof]], "hatch")
        # A stiffener across each panel's top, a lifting lug either side of it.
        zm = (za + zb) / 2
        prism([(zm - 0.06, yc - 0.01), (zm + 0.06, yc - 0.01), (zm + 0.06, yc + 0.06), (zm - 0.06, yc + 0.06)],
              -1.4, 1.4, "hatch")
        for sx in (1, -1):
            box(V(sx * 2.3, ye + 0.18, zm), (0.08, 0.14, 0.24), "dark")
    # Hinge knuckles over the panels' joint.
    for x in (-2.6, -0.9, 0.9, 2.6):
        y = yc - (abs(x) - 1.4) / (hw - 1.4) * (yc - ye) if abs(x) > 1.4 else yc
        cyl(V(x - 0.3, y, zc), V(x + 0.3, y, zc), 0.1, 0.1, 6, "dark")
    # Cleats down the sides.
    for sx in (1, -1):
        for i in range(5):
            z = lerp(zc - HOLD_LEN / 2 + 0.6, zc + HOLD_LEN / 2 - 0.6, i / 4)
            box(V(sx * (hw + 0.06), COAMING_TOP - 0.05, z), (0.12, 0.2, 0.16), "dark")
    # Jacks at each end: from the deck up to the end panel's edge.
    for sz in (1, -1):
        ze = zc + sz * HOLD_LEN / 2
        for x in (-1.6, 1.6):
            beam_between(V(x, DECK + 0.1, ze + sz * 0.9), V(x, COAMING_TOP + 0.1, ze + sz * 0.08), 0.14, 0.14, "steel")
            cyl(V(x - 0.12, DECK, ze + sz * 0.9), V(x + 0.12, DECK + 0.2, ze + sz * 0.9), 0.12, 0.12, 6, "dark")


def crane(zc, sx):
    """A deck crane on its pedestal between two hatches: the slewing house with the
    cab on the `sx` side, the A-frame the luffing wires run from, and the jib lowered
    forward into its rest outboard on that side, the hook lashed under its head."""
    ped = V(0, DECK, zc)
    top = V(0, 6.6, zc)
    cyl(ped, top, 0.85, 0.8, 12, "crane")
    cyl(top, top + V(0, 0.2, 0), 0.95, 0.95, 12, "dark")
    # Rungs up the pedestal's after side, and the hatch into the house.
    for i in range(10):
        box(V(0, DECK + 0.3 + i * 0.32, zc - 0.85), (0.4, 0.04, 0.06), "steel")
    hz = zc - 0.1
    box(V(0, 7.75, hz), (2.3, 1.9, 2.6), "crane")
    box(V(0, 8.73, hz), (2.36, 0.06, 2.66), "dark")
    # The cab: glazed forward and outboard.
    c = V(sx * 0.95, 7.9, hz + 1.25)
    box(c, (0.75, 1.3, 0.5), "crane")
    box(c + V(0, 0.2, 0.26), (0.6, 0.6, 0.03), "glass")
    box(c + V(sx * 0.38, 0.2, 0), (0.03, 0.6, 0.35), "glass")
    # A-frame over the house.
    apex = V(0, 10.4, hz - 0.5)
    for x in (-0.85, 0.85):
        beam_between(V(x, 8.7, hz - 1.1), apex, 0.18, 0.18, "crane")
        beam_between(V(x, 8.7, hz + 0.3), apex, 0.12, 0.12, "crane")
    box(apex + V(0, 0.1, 0), (0.6, 0.3, 0.4), "dark")
    # The jib: a box girder tapering to the head, lowered into its rest.
    heel = V(0, 7.3, hz + 1.35)
    head = V(sx * JIB_REST_X, 6.55, zc + 8.3)
    mid = lerp(heel, head, 0.45)
    for x in (-0.55, 0.55):
        cyl(heel + V(x, -0.1, -0.1), heel + V(x * 1.2, -0.1, -0.1), 0.18, 0.18, 6, "dark")
    beam_between(heel, mid, 0.85, 0.7, "crane")
    beam_between(mid, head, 0.6, 0.48, "crane")
    box(head + V(0, 0.15, 0.25), (0.5, 0.5, 0.5), "crane")
    # The rest: a post with a fork, braced.
    rest = V(head.x, DECK, head.z - 0.2)
    cyl(rest, rest + V(0, 2.95, 0), 0.12, 0.1, 6, "crane")
    for dx in (-0.3, 0.3):
        box(rest + V(dx, 3.1, 0), (0.08, 0.4, 0.16), "crane")
    box(rest + V(0, 2.95, 0), (0.7, 0.08, 0.2), "crane")
    beam_between(rest + V(-sx * 0.9, 0, 0), rest + V(0, 1.6, 0), 0.08, 0.08, "crane")
    # Wires: the luffing wires to the head, the hoist down to the hook on the deck.
    for dx in (-0.12, 0.12):
        tube([apex + V(dx, 0.1, 0.1), head + V(dx, 0.35, 0.1)], 0.025, 3, "black")
    hook = V(head.x - sx * 0.6, DECK + 0.35, head.z + 0.4)
    tube([head + V(0, 0, 0.4), hook + V(0, 0.3, 0)], 0.02, 3, "black")
    box(hook, (0.4, 0.6, 0.3), "yellow")
    cyl(hook - V(0, 0.3, 0), hook - V(0, 0.5, 0), 0.12, 0.06, 6, "black")


def cargo_deck():
    holds()
    for i, z in enumerate(CRANE_Z):
        crane(z, 1 if i % 2 == 0 else -1)
    deck_rails(False)


result = export("bulker_mid", BASE + [cargo_deck])
print("RESULT", result, sum(result.values()))
