# Builds the road vehicles in Blender (run inside Blender: exec(open(path).read()), or
# `Blender -b art/vehicles.blend --python art/vehicles.py`) and exports them to
# assets/models/vehicles.glb (glTF, +Y up, vertex colours, flat shaded), plus
# scripts/world/vehicle_data.gd (each variant's size and lamp positions). The geometry
# is in art/vehicle_kit.py; this file holds the models.
#
# Each model is a parameter dict, and each variant is a named set of parameters over
# the model's defaults, so a new variant costs a few lines. The models follow the
# user's reference sheets:
# - sedans: a 2010s mid-size, a rally sport sedan, an 80s box, a 90s mid-size, a
#   chrome-grille land yacht, an EV with a light bar, a compact and an 80s German
#   executive;
# - SUVs (two-box): a modern crossover, a three-row family SUV, a chrome-grille luxury
#   SUV, a coupe-SUV, an angular EV, an 80s-90s boxy 4x4, an open-top-style off-roader
#   with its spare on the back, and a 90s mid-size;
# - minivans (two-box, sliding doors): a 2000s family van, a 90s box with a rubbing
#   strip, a 2010s, an angular modern one with a big grille, a compact MPV, an EV with
#   a light bar, a 90s square-cut one in black plastic and an SUV-styled one;
# - vans (two-box, high roofs, barn doors): a medium-roof cargo van, a long-nosed
#   passenger van, a high-roof cargo van, an 80s long-nose in two-tone, a camper with a
#   high top, a high-roof minibus, a compact cargo van and an overlander on a rack;
# - pickups (a cab and an open bed): a midsize extended cab, an 80s square-body, a
#   crew-cab trail truck, a crew-cab dually, a lifted off-roader with a light bar, a
#   lowered sport truck, a 90s compact and a modern full-size crew cab; and one not on
#   the sheet, the pavement princess (see PICKUPS);
# - trucks (art/truck_kit.py): straight trucks on a medium-duty conventional cab (box,
#   reefer, fuel tank) and a step van; Class 8 tractors (aero high-roof and mid-roof
#   sleepers, an aero day cab, a long-nose day cab and a long-nose flat-top sleeper);
#   and semi-trailers (dry van, reefer, container chassis, flatbed, logs, tanker, end
#   dump, car hauler). Tractors export their fifth wheel (`hitch`), trailers their
#   kingpin (`pin`) and tandem centre (`axle`), for coupling and articulating in game.
import bpy, os

ART = os.path.dirname(bpy.data.filepath) or "/Users/jon/Documents/GitHub/lowpoly/art"
_kit = os.path.join(ART, "vehicle_kit.py")
exec(compile(open(_kit).read(), _kit, "exec"))
_tkit = os.path.join(ART, "truck_kit.py")
exec(compile(open(_tkit).read(), _tkit, "exec"))


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
    # (two-box and trim options, off for the sedans)
    twobox=False, q_w=0.025, c_key=None, rub_y=0.52, clad=None, rails=None, rail_key="black",
    spoiler=None, spare=None, tread=False, rd_end=0.3, hinges=False,
    # (minivan and van options)
    upper="body", ws_top=None, cap=0.45, win_top=None, glass="all", slide=False,
    rear_doors=None, rear_glass=True, accent=None, markers=False,
    bullbar=False, ladder=False, hightop=None, vent=False,
    # (pickup options)
    bed=False, bed_gap=0.06, tg=0.05, bed_floor=None, bed_wall=0.05, tg_key=None,
    cab="crew", cab_corner=0.1, dually=False, rflare=0.0, steps=None, tow_mirrors=False,
    roof_lamps=False, rollbar=False, hooks=False, shocks=None, lightbar=False, stacks=False, lift=False,
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

# --- SUV (two-box) ----------------------------------------------------------------------

SUV = dict(SEDAN,
    L=4.6, W=1.86, H=1.72, wb=2.69, fo=0.93, r=0.39, tw=0.24, arch=0.06,
    sill=0.34, bump_bot=0.32, tuck=0.04,
    nose_top=0.97, nose_set=0.2, hood_front=1.02, belt=1.12, belt_rise=0.05, crease=0.98,
    deck_lift=0.0, tail_top=1.1, tail_set=0.12,
    hood=1.15, ws=0.95, rw=0.5, df=0.03, dr=0.07, crown=0.035,
    tumble=0.18, sh_in=0.08, cf=0.12, cfl=0.42, cr=0.08, crl=0.3,
    a_w=0.07, c_w=0.14, rail=0.06, b_at=0.53, quarter=1.0, q_w=0.03,
    lamp=dict(style="swept", x0=0.34, x1=0.86, y0=0.8, y1=0.93, wrap=0.34),
    grille=dict(style="band", w=0.3, y0=0.8, y1=0.9),
    intake=dict(w=0.62, y0=0.42, y1=0.64, fogs=True),
    tail=dict(style="wrap", x0=0.5, x1=0.9, y0=0.94, y1=1.05, wrap=0.3),
    plate_y=0.7, twobox=True, c_key="black", clad=dict(key="trim", arch=0.06, sill=0.12),
    rails="rails", spoiler="body",
)

SUVS = {
    # Modern compact crossover (RAV4/CR-V): floating roof, cladding, rails.
    "crossover": dict(paint=(0.88, 0.86, 0.8)),
    # Three-row family SUV (Highlander/Explorer): longer, a big framed grille.
    "threerow": dict(L=4.95, W=1.93, H=1.77, wb=2.85, fo=0.96, r=0.4, belt=1.14, crease=1.0,
                     nose_top=1.0, hood_front=1.05, tail_top=1.1, hood=1.3, ws=0.88, rw=0.32,
                     quarter=1.0, c_w=0.12,
                     lamp=dict(style="swept", x0=0.5, x1=0.88, y0=0.82, y1=0.95, wrap=0.34),
                     grille=dict(style="shield", w=0.46, y0=0.62, y1=0.9, surround="chrome", key="chrome", n=3),
                     intake=dict(w=0.5, y0=0.38, y1=0.52, fogs=True, vents=True),
                     tail=dict(style="wrap", x0=0.45, x1=0.92, y0=0.97, y1=1.07, wrap=0.32),
                     rail_key="silver", wheel="alloy6", paint=(0.72, 0.16, 0.1)),
    # Big luxury SUV (Escalade/Wagoneer): square, tall, a chrome waterfall grille.
    "luxury": dict(L=5.4, W=2.06, H=1.96, wb=3.07, fo=1.0, r=0.43, sill=0.38, bump_bot=0.34,
                   nose_top=1.15, nose_set=0.08, hood_front=1.19, belt=1.27, belt_rise=0.01, crease=1.1,
                   tail_top=1.23, tail_set=0.08, hood=1.5, ws=0.78, rw=0.2, df=0.02, dr=0.02, crown=0.03,
                   tumble=0.1, cf=0.06, cfl=0.3, cr=0.04, crl=0.25, quarter=1.0, c_w=0.1,
                   frame="chrome", c_key=None,
                   lamp=dict(style="rect", x0=0.52, x1=0.94, y0=1.04, y1=1.11, wrap=0.12),
                   grille=dict(style="waterfall", w=0.42, y0=0.66, y1=1.09),
                   intake=dict(w=0.7, y0=0.42, y1=0.56, fogs=False),
                   tail=dict(style="rect", x0=0.6, x1=0.98, y0=0.92, y1=1.19, wrap=0.08),
                   clad=None, sill_key="silver", rail_key="silver", wheel="turbine",
                   paint=(0.66, 0.68, 0.7)),
    # Coupe-SUV (Urus-ish): low roof, fastback, huge intakes, calipers.
    "coupe": dict(L=5.1, W=2.0, H=1.64, wb=3.0, fo=1.0, r=0.43, tw=0.26, sill=0.33, bump_bot=0.28,
                  nose_top=0.97, nose_set=0.26, hood_front=1.02, belt=1.13, belt_rise=0.06, crease=0.98,
                  tail_top=1.18, tail_set=0.2, hood=1.3, flare=0.03, ws=1.0, rw=1.15, rw_bulge=0.05, ws_bulge=0.02,
                  crown=0.05, tumble=0.22, cf=0.16, cfl=0.5, quarter=0.0, c_w=0.18,
                  lamp=dict(style="swept", x0=0.46, x1=0.92, y0=0.86, y1=0.94, wrap=0.3),
                  grille=dict(style="hex", w=0.3, y0=0.66, y1=0.8),
                  intake=dict(w=0.5, y0=0.34, y1=0.56, fogs=False, vents=True),
                  tail=dict(style="bar", x0=0.0, x1=0.92, y0=1.04, y1=1.09, wrap=0.2),
                  clad=dict(key="black", arch=0.05, sill=0.08), rails=None, c_key=None,
                  mirror="body", wheel="sport", paint=(0.92, 0.75, 0.12)),
    # Angular EV SUV: flat facets, a light bar, light slits, a grey two-tone lower body.
    "ev": dict(L=4.95, W=1.98, H=1.8, wb=3.0, fo=0.95, r=0.42, sill=0.34, bump_bot=0.32,
               nose_top=1.0, nose_set=0.3, hood_front=1.04, belt=1.15, belt_rise=0.06, crease=1.0,
               tail_top=1.18, tail_set=0.12, hood=1.0, ws=1.35, rw=1.05, crown=0.0, df=0.0, dr=0.06,
               tumble=0.2, cf=0.04, cfl=0.35, cr=0.04, quarter=0.0, c_w=0.2,
               roof_key="black", mirror="black", c_key=None,
               lamp=dict(style="bar", x0=0.6, x1=0.9, y0=0.92, y1=0.95, wrap=0.3, slits=True),
               grille=None, intake=dict(w=0.6, y0=0.4, y1=0.64, fogs=False),
               tail=dict(style="bar", x0=0.0, x1=0.94, y0=1.1, y1=1.14, wrap=0.25),
               clad=dict(key="grey", arch=0.1, sill=0.22), rails=None, wheel="aero",
               paint=(0.24, 0.25, 0.27)),
    # 80s-90s boxy 4x4 (Cherokee XJ): upright, square lamps, flares, knobbly tyres.
    "cherokee": dict(L=4.25, W=1.76, H=1.68, wb=2.58, fo=0.82, r=0.41, sill=0.4, bump_bot=0.34,
                     nose_top=0.96, nose_set=0.06, hood_front=0.99, belt=1.1, belt_rise=0.0, crease=0.98,
                     tail_top=1.06, tail_set=0.07, hood=1.15, ws=0.62, rw=0.14, df=0.02, dr=0.02, crown=0.015,
                     tumble=0.06, sh_in=0.04, cf=0.03, cfl=0.2, cr=0.03, crl=0.2, flare=0.04,
                     quarter=1.0, q_w=0.04, c_w=0.1, c_key=None,
                     lamp=dict(style="rect", x0=0.5, x1=0.78, y0=0.8, y1=0.92, wrap=0.0),
                     grille=dict(style="slats", w=0.4, y0=0.78, y1=0.93, n=5, key="grey"),
                     intake=None, tail=dict(style="rect", x0=0.7, x1=0.86, y0=0.62, y1=0.98, wrap=0.04),
                     bumper="black", plate_y=0.66, mirror="black", spoiler=None,
                     clad=dict(key="black", arch=0.08, sill=0.08), rails="bars",
                     wheel="steel", tread=True, paint=(0.15, 0.32, 0.72)),
    # Off-roader (Wrangler): round lamps, slotted grille, big flares, spare on the back.
    "offroad": dict(L=4.62, W=1.9, H=1.9, wb=2.9, fo=0.74, r=0.46, tw=0.3, arch=0.07,
                    sill=0.5, bump_bot=0.42, tuck=0.02,
                    nose_top=1.1, nose_set=0.05, hood_front=1.13, belt=1.2, belt_rise=0.0, crease=1.12,
                    tail_top=1.18, tail_set=0.06, hood=1.22, ws=0.38, rw=0.06, df=0.01, dr=0.01, crown=0.01,
                    tumble=0.05, sh_in=0.03, cf=0.04, cfl=0.25, cr=0.03, crl=0.2, flare=0.07,
                    a_w=0.06, quarter=1.0, q_w=0.04, c_w=0.08, c_key=None,
                    lamp=dict(style="round", x0=0.5, x1=0.68, y0=0.9, y1=1.08, wrap=0.0),
                    grille=dict(style="slots", w=0.36, y0=0.8, y1=1.08),
                    intake=None, tail=dict(style="rect", x0=0.76, x1=0.88, y0=0.76, y1=0.98, wrap=0.0),
                    bumper="black", plate_y=0.76, mirror="black", spoiler=None,
                    clad=dict(key="black", arch=0.12, sill=0.1), rails="bars",
                    spare=1.04, wheel="offroad", tread=True, hinges=True, paint=(0.33, 0.4, 0.22)),
    # 90s mid-size (4Runner/Explorer): rubbing strip, black bumpers, square lamps.
    "nineties": dict(L=4.6, W=1.75, H=1.74, wb=2.7, fo=0.86, r=0.38, sill=0.34, bump_bot=0.32,
                     nose_top=0.94, nose_set=0.1, hood_front=0.98, belt=1.1, belt_rise=0.01, crease=0.96,
                     tail_top=1.06, tail_set=0.08, hood=1.22, ws=0.72, rw=0.2, crown=0.02,
                     tumble=0.08, sh_in=0.05, cf=0.05, cfl=0.25, cr=0.04, crl=0.22,
                     quarter=1.0, q_w=0.04, c_w=0.11, c_key=None,
                     lamp=dict(style="rect", x0=0.46, x1=0.8, y0=0.78, y1=0.9, wrap=0.04),
                     grille=dict(style="slats", w=0.36, y0=0.76, y1=0.9, n=3, key="chrome"),
                     intake=None, tail=dict(style="rect", x0=0.68, x1=0.85, y0=0.7, y1=1.0, wrap=0.05),
                     bumper="black", rub=True, rub_y=0.62, plate_y=0.66, mirror="black", spoiler=None,
                     clad=dict(key="black", arch=0.04, sill=0.06), wheel="alloy6",
                     paint=(0.15, 0.55, 0.58)),
}

# --- Minivan (two-box, sliding doors) ---------------------------------------------------

MINIVAN = dict(SUV,
    L=5.1, W=1.96, H=1.77, wb=3.0, fo=0.98, r=0.36, tw=0.23, arch=0.05,
    sill=0.3, bump_bot=0.27, tuck=0.04,
    nose_top=0.88, nose_set=0.22, hood_front=0.96, belt=1.08, belt_rise=0.05, crease=0.92,
    tail_top=1.08, tail_set=0.1, hood=0.86, ws=1.32, rw=0.32, df=0.04, dr=0.06, crown=0.04,
    tumble=0.16, sh_in=0.07, cf=0.16, cfl=0.5, cr=0.08, crl=0.3,
    a_w=0.07, c_w=0.13, b_at=0.42, quarter=1.0, q_w=0.03, rd_end=1.1, slide=True,
    lamp=dict(style="swept", x0=0.36, x1=0.9, y0=0.72, y1=0.84, wrap=0.36),
    grille=dict(style="band", w=0.34, y0=0.7, y1=0.8),
    intake=dict(w=0.6, y0=0.36, y1=0.54, fogs=True),
    tail=dict(style="wrap", x0=0.62, x1=0.94, y0=0.84, y1=1.05, wrap=0.22),
    plate_y=0.66, c_key=None, clad=None, rails="rails", rail_key="black", spoiler="body",
    wheel="alloy5",
)

MINIVANS = {
    # 2000s family minivan (Odyssey/Sienna): soft, a thin chrome band grille, rails.
    "family": dict(paint=(0.86, 0.8, 0.68)),
    # 90s minivan (Caravan/Previa): square face, black bumpers and rubbing strip.
    "nineties": dict(L=4.95, W=1.9, H=1.73, wb=2.88, fo=0.96, r=0.33, nose_top=0.86, nose_set=0.12,
                     hood_front=0.9, belt=1.02, belt_rise=0.01, crease=0.86, tail_top=1.0, tail_set=0.07,
                     hood=0.95, ws=1.15, crown=0.025, tumble=0.12, sh_in=0.05, cf=0.06, cfl=0.3, cr=0.04,
                     lamp=dict(style="rect", x0=0.46, x1=0.84, y0=0.68, y1=0.8, wrap=0.04),
                     grille=dict(style="slats", w=0.38, y0=0.66, y1=0.8, n=3, key="grey"),
                     intake=None, tail=dict(style="rect", x0=0.66, x1=0.9, y0=0.68, y1=0.96, wrap=0.04),
                     bumper="black", rub=True, rub_y=0.58, plate_y=0.62, mirror="black", spoiler=None,
                     rails=None, wheel="hubcap", paint=(0.18, 0.55, 0.6)),
    # 2010s minivan: a wider swept face, a broad lower intake, alloy wheels.
    "modern": dict(lamp=dict(style="swept", x0=0.34, x1=0.92, y0=0.7, y1=0.84, wrap=0.4),
                   grille=dict(style="trapezoid", w=0.36, y0=0.62, y1=0.78),
                   intake=dict(w=0.7, y0=0.32, y1=0.52, fogs=True, vents=True),
                   rail_key="silver", wheel="alloy6", paint=(0.66, 0.68, 0.7)),
    # Angular modern minivan (2021 Sienna): a huge shield grille, slim lamps, chrome trim.
    "bold": dict(L=5.17, W=1.99, H=1.77, nose_top=0.9, hood_front=0.96, hood=1.08, ws=1.2,
                 cf=0.12, frame="chrome",
                 lamp=dict(style="swept", x0=0.44, x1=0.93, y0=0.76, y1=0.84, wrap=0.36),
                 grille=dict(style="shield", w=0.5, y0=0.36, y1=0.72, surround="black", key="gunmetal", n=4),
                 intake=dict(w=0.5, y0=0.3, y1=0.34, fogs=False, vents=True),
                 rails=None, roof_key="black", c_key="black", wheel="aero", paint=(0.42, 0.1, 0.12)),
    # Compact MPV (Mazda5/Freed): short, narrow, rides on small wheels.
    "compact": dict(L=4.5, W=1.75, H=1.66, wb=2.75, fo=0.88, r=0.31, tw=0.2, sill=0.26, bump_bot=0.24,
                    nose_top=0.8, nose_set=0.2, hood_front=0.86, belt=0.99, crease=0.84, tail_top=0.96,
                    hood=0.78, ws=1.2, rw=0.28, cf=0.15, cfl=0.42,
                    lamp=dict(style="swept", x0=0.3, x1=0.8, y0=0.66, y1=0.78, wrap=0.32),
                    grille=dict(style="band", w=0.28, y0=0.64, y1=0.73),
                    intake=dict(w=0.5, y0=0.32, y1=0.48, fogs=True),
                    tail=dict(style="wrap", x0=0.48, x1=0.82, y0=0.8, y1=0.93, wrap=0.26),
                    plate_y=0.6, rails=None, wheel="hubcap", paint=(0.2, 0.48, 0.82)),
    # EV minivan: smooth nose with a light bar, black roof, angled corner vents.
    "ev": dict(L=5.15, W=1.98, H=1.76, nose_top=0.84, nose_set=0.28, hood_front=0.92, hood=0.95, ws=1.32,
               crown=0.03, cf=0.08, cfl=0.4, roof_key="black", mirror="black", c_key="black",
               lamp=dict(style="bar", x0=0.6, x1=0.9, y0=0.76, y1=0.8, wrap=0.3, slits=True),
               grille=None, intake=dict(w=0.54, y0=0.3, y1=0.48, fogs=False, vents=True),
               tail=dict(style="bar", x0=0.0, x1=0.94, y0=0.94, y1=0.99, wrap=0.2),
               rails=None, wheel="aero", paint=(0.9, 0.9, 0.88)),
    # 90s square-cut minivan (Astro/Quest): black bumpers and lower cladding, square lamps.
    "boxy": dict(L=4.85, W=1.88, H=1.8, wb=2.83, fo=0.9, r=0.34, sill=0.32, bump_bot=0.28,
                 nose_top=0.9, nose_set=0.1, hood_front=0.94, belt=1.05, belt_rise=0.0, crease=0.9,
                 tail_top=1.02, tail_set=0.07, hood=1.05, ws=1.0, rw=0.2, df=0.02, dr=0.03, crown=0.02,
                 tumble=0.1, sh_in=0.04, cf=0.04, cfl=0.25, cr=0.03, crl=0.2,
                 lamp=dict(style="rect", x0=0.46, x1=0.84, y0=0.72, y1=0.84, wrap=0.04),
                 grille=dict(style="slats", w=0.38, y0=0.7, y1=0.84, n=4, key="trim"),
                 intake=None, tail=dict(style="rect", x0=0.7, x1=0.9, y0=0.66, y1=0.98, wrap=0.04),
                 bumper="black", plate_y=0.64, mirror="black", spoiler=None,
                 clad=dict(key="black", arch=0.05, sill=0.16), rails=None, wheel="steel",
                 paint=(0.36, 0.45, 0.25)),
    # SUV-styled minivan (Carnival): longer hood, chrome grille, rails, more upright.
    "suvish": dict(L=5.15, W=1.99, H=1.78, nose_top=0.94, nose_set=0.2, hood_front=1.0, belt=1.08,
                   hood=1.2, ws=1.05, crown=0.03, cf=0.1, cfl=0.4, frame="chrome",
                   lamp=dict(style="swept", x0=0.48, x1=0.92, y0=0.8, y1=0.9, wrap=0.34),
                   grille=dict(style="shield", w=0.46, y0=0.54, y1=0.86, surround="chrome", key="chrome", n=4),
                   intake=dict(w=0.46, y0=0.34, y1=0.46, fogs=False, vents=True),
                   rail_key="silver", clad=dict(key="trim", arch=0.04, sill=0.08), wheel="turbine",
                   paint=(0.78, 0.36, 0.14)),
}

# --- Van (two-box, high roofs, barn doors) -------------------------------------------------

VAN = dict(SUV,
    L=5.55, W=2.05, H=2.5, wb=3.3, fo=0.92, r=0.385, tw=0.24, arch=0.06,
    sill=0.4, bump_bot=0.32, tuck=0.03,
    nose_top=1.08, nose_set=0.22, hood_front=1.15, belt=1.27, belt_rise=0.02, crease=1.1,
    tail_top=1.25, tail_set=0.06, hood=0.95, ws=0.85, rw=0.08, df=0.06, dr=0.04, crown=0.04,
    ws_top=2.02, cap=0.22, win_top=1.9,
    tumble=0.04, sh_in=0.015, gh_in=0.0, cf=0.1, cfl=0.45, cr=0.03, crl=0.15, flare=0.0,
    a_w=0.07, c_w=0.07, rail=0.07, b_at=0.45, quarter=1.0, q_w=0.04, rd_end=2.0,
    glass="front", slide=True, rear_doors="barn",
    lamp=dict(style="wedge", x0=0.56, x1=0.98, y0=0.86, y1=1.04, wrap=0.26),
    grille=dict(style="slats", w=0.5, y0=0.64, y1=1.0, n=4, key="trim", surround="trim"),
    intake=None, tail=dict(style="rect", x0=0.84, x1=0.98, y0=0.74, y1=1.18, wrap=0.04),
    bumper="black", plate_y=0.62, mirror="black", c_key=None, clad=None, rails=None, spoiler=None,
    wheel="steel",
)

VANS = {
    # Medium-roof cargo van (Transit/ProMaster): windowless behind the doors.
    "cargo": dict(paint=(0.92, 0.92, 0.9)),
    # Long-nosed passenger van (Express/Econoline): low roof, windows all the way back.
    "passenger": dict(L=5.75, W=2.01, H=2.1, wb=3.45, fo=0.86, r=0.39, nose_top=1.06, nose_set=0.08,
                      hood_front=1.1, belt=1.23, belt_rise=0.0, crease=1.08, tail_top=1.21, hood=1.12, ws=0.48,
                      ws_top=None, win_top=1.8, df=0.04, dr=0.03, crown=0.03, cf=0.06, cfl=0.3, b_at=0.42,
                      rd_end=2.2, c_w=0.1, glass="all", slide=False,
                      lamp=dict(style="rect", x0=0.5, x1=0.86, y0=0.84, y1=0.99, wrap=0.04),
                      grille=dict(style="slats", w=0.44, y0=0.78, y1=0.99, n=3, key="trim", surround="trim"),
                      tail=dict(style="rect", x0=0.82, x1=0.96, y0=0.7, y1=1.12, wrap=0.04),
                      paint=(0.15, 0.32, 0.72)),
    # High-roof cargo van (Sprinter): taller still, a black rubbing strip low down.
    "hightop": dict(L=5.9, W=2.02, H=2.75, wb=3.66, fo=0.94, r=0.39, ws_top=2.0, cap=0.3, win_top=1.88,
                    rd_end=2.6, b_at=0.42, rub=True, rub_y=0.52,
                    lamp=dict(style="wedge", x0=0.5, x1=0.96, y0=0.84, y1=1.04, wrap=0.3),
                    grille=dict(style="shield", w=0.44, y0=0.62, y1=0.98, surround="black", key="trim", n=3),
                    paint=(0.92, 0.72, 0.15)),
    # 80s long-nose van (Econoline): two-tone side, chrome-ringed square lamps and grille.
    "retro": dict(L=5.4, W=2.0, H=2.08, wb=3.48, fo=0.82, r=0.38, nose_top=1.04, nose_set=0.05,
                  hood_front=1.07, belt=1.2, belt_rise=0.0, crease=1.04, tail_top=1.18, hood=1.15, ws=0.45,
                  ws_top=None, win_top=1.78, slide=False, df=0.03, dr=0.03, crown=0.02, cf=0.05, cfl=0.25, b_at=0.4,
                  rd_end=2.2, frame="chrome",
                  lamp=dict(style="rect", x0=0.5, x1=0.8, y0=0.8, y1=0.97, wrap=0.04),
                  grille=dict(style="slats", w=0.4, y0=0.76, y1=0.97, n=4, key="chrome", surround="chrome"),
                  tail=dict(style="rect", x0=0.82, x1=0.96, y0=0.66, y1=1.1, wrap=0.04),
                  accent=dict(y0=0.56, y1=1.08, stripe="cream"), markers=True,
                  wheel="multi", paint=(0.84, 0.76, 0.6)),
    # Camper on a passenger van: a cream fibreglass high top, cream upper body, a vent.
    "camper": dict(L=5.3, W=2.0, H=2.06, wb=3.2, fo=0.94, nose_top=0.98, belt=1.18, crease=1.02,
                   tail_top=1.16, hood=1.0, ws=0.7, ws_top=None, win_top=1.84, b_at=0.42, rd_end=1.9,
                   glass="all", c_w=0.1, upper="cream", roof_key="cream",
                   hightop=dict(h=0.36, key="cream"), vent=True,
                   lamp=dict(style="wedge", x0=0.54, x1=0.96, y0=0.8, y1=0.96, wrap=0.26),
                   grille=dict(style="slats", w=0.46, y0=0.62, y1=0.94, n=4, key="trim", surround="trim"),
                   wheel="hubcap", paint=(0.33, 0.48, 0.28)),
    # High-roof minibus (Sprinter passenger): windows all round, marker lamps.
    "shuttle": dict(L=5.9, W=2.02, H=2.72, wb=3.66, fo=0.94, r=0.39, ws_top=2.0, cap=0.3, win_top=1.9,
                    rd_end=2.6, b_at=0.42, glass="all", c_w=0.1, markers=True,
                    lamp=dict(style="wedge", x0=0.5, x1=0.96, y0=0.84, y1=1.04, wrap=0.3),
                    grille=dict(style="shield", w=0.44, y0=0.62, y1=0.98, surround="chrome", key="chrome", n=3),
                    wheel="hubcap", paint=(0.24, 0.25, 0.28)),
    # Compact cargo van (Transit Connect): a car's front on a box, low roof.
    "compact": dict(L=4.75, W=1.84, H=1.86, wb=3.0, fo=0.86, r=0.33, tw=0.21, sill=0.32, bump_bot=0.28,
                    nose_top=0.88, nose_set=0.22, hood_front=0.94, belt=1.06, belt_rise=0.02, crease=0.92,
                    tail_top=1.04, tail_set=0.07, hood=1.05, ws=0.95, ws_top=None, win_top=None,
                    df=0.04, dr=0.04, tumble=0.08, sh_in=0.05, cf=0.14, cfl=0.42, rd_end=1.4, b_at=0.46,
                    lamp=dict(style="swept", x0=0.4, x1=0.86, y0=0.72, y1=0.84, wrap=0.3),
                    grille=dict(style="band", w=0.32, y0=0.68, y1=0.78),
                    intake=dict(w=0.56, y0=0.36, y1=0.52, fogs=True),
                    tail=dict(style="rect", x0=0.74, x1=0.88, y0=0.62, y1=0.98, wrap=0.04),
                    bumper="body", plate_y=0.56, wheel="hubcap", paint=(0.8, 0.18, 0.12)),
    # Overlander: lifted on knobbly tyres, bull bar, a basket rack with lamps, a ladder.
    "overland": dict(r=0.42, tw=0.28, sill=0.48, bump_bot=0.42, nose_top=1.16, hood_front=1.22, belt=1.33,
                     crease=1.16, tail_top=1.31, H=2.58, ws_top=2.08, win_top=1.96, flare=0.03,
                     lamp=dict(style="wedge", x0=0.56, x1=0.98, y0=0.94, y1=1.12, wrap=0.26),
                     grille=dict(style="slats", w=0.5, y0=0.72, y1=1.08, n=4, key="black", surround="trim"),
                     tail=dict(style="rect", x0=0.84, x1=0.98, y0=0.82, y1=1.24, wrap=0.04),
                     plate_y=0.7, clad=dict(key="black", arch=0.08, sill=0.08), rails="basket",
                     bullbar=True, ladder=True, rear_glass=False, wheel="offroad", tread=True,
                     paint=(0.33, 0.4, 0.22)),
}

# --- Pickup (cab and open bed) -------------------------------------------------------------
# The cab is a three-box greenhouse whose "rear window" run (rw) is its near-upright back;
# the bed runs from just behind it to the tailgate. Kept to <= 5.9 m like the vans (the
# ferries' slot pitch), so the crew cabs carry short beds.

PICKUP = dict(SUV,
    L=5.88, W=2.03, H=1.95, wb=3.6, fo=0.95, r=0.41, tw=0.27, arch=0.06,
    sill=0.5, bump_bot=0.42, tuck=0.03,
    nose_top=1.2, nose_set=0.06, hood_front=1.25, belt=1.31, belt_rise=0.0, crease=1.12,
    tail_top=1.31, tail_set=0.03, hood=1.62, ws=0.38, roof=1.62, rw=0.06,
    df=0.03, dr=0.03, crown=0.02, ws_bulge=0.0, rw_bulge=0.0,
    tumble=0.1, sh_in=0.05, gh_in=0.02, cf=0.07, cfl=0.32, cr=0.02, crl=0.1, flare=0.0,
    a_w=0.07, c_w=0.12, rail=0.06, b_at=0.5, quarter=0.0, twobox=False,
    lamp=dict(style="rect", x0=0.5, x1=0.95, y0=1.02, y1=1.14, wrap=0.1),
    grille=dict(style="slats", w=0.52, y0=0.7, y1=1.12, n=3, key="chrome", surround="chrome"),
    intake=None, tail=dict(style="rect", x0=0.86, x1=0.98, y0=0.92, y1=1.25, wrap=0.03),
    bumper="chrome", plate_y=0.8, mirror="black", c_key=None, clad=None, rails=None, spoiler=None,
    wheel="alloy6", bed=True, cab="crew", steps="black", tg_key="chrome",
)

PICKUPS = {
    # Modern full-size crew cab (Silverado/F-150): chrome grille and bumpers, steps.
    "fullsize": dict(paint=(0.1, 0.1, 0.11)),
    # Midsize extended cab (Tacoma Access Cab): swept lamps, a hex grille, a dark bumper.
    "midsize": dict(L=5.3, W=1.86, H=1.78, wb=3.24, fo=0.88, r=0.38, tw=0.25, sill=0.44, bump_bot=0.36,
                    nose_top=0.98, nose_set=0.14, hood_front=1.04, belt=1.16, crease=1.0, tail_top=1.16,
                    hood=1.4, ws=0.5, roof=1.3, cf=0.12, cfl=0.4, tumble=0.12, cab="ext", b_at=0.74,
                    lamp=dict(style="swept", x0=0.38, x1=0.88, y0=0.86, y1=0.98, wrap=0.3),
                    grille=dict(style="hex", w=0.4, y0=0.62, y1=0.92),
                    intake=dict(w=0.58, y0=0.4, y1=0.52, fogs=True),
                    tail=dict(style="rect", x0=0.8, x1=0.91, y0=0.82, y1=1.1, wrap=0.03),
                    bumper="black", steps=None, tg_key=None, wheel="alloy6", paint=(0.88, 0.86, 0.8)),
    # 80s square-body (C10): regular cab, long bed, chrome bumpers and trim, hubcaps.
    "squarebody": dict(L=5.6, W=2.0, H=1.8, wb=3.3, fo=0.86, r=0.37, tw=0.24, sill=0.46, bump_bot=0.38,
                       nose_top=1.08, nose_set=0.04, hood_front=1.1, belt=1.2, crease=1.05, tail_top=1.2,
                       hood=1.72, ws=0.34, roof=1.06, rw=0.05, crown=0.01, tumble=0.07, sh_in=0.04, cf=0.03,
                       cfl=0.15, cab="regular", c_w=0.16, cab_corner=0.14, frame="chrome",
                       lamp=dict(style="rect", x0=0.6, x1=0.88, y0=0.86, y1=1.04, wrap=0.02),
                       grille=dict(style="slats", w=0.56, y0=0.84, y1=1.05, n=3, key="grey", surround="chrome"),
                       tail=dict(style="rect", x0=0.84, x1=0.96, y0=0.8, y1=1.1, wrap=0.03),
                       mirror="chrome", steps=None, tg_key=None, wheel="hubcap", paint=(0.78, 0.15, 0.1)),
    # Crew-cab trail truck (Tacoma TRD Off-Road): flares, cladding, knobbly tyres.
    "trail": dict(L=5.4, W=1.94, H=1.86, wb=3.3, fo=0.9, r=0.42, tw=0.28, arch=0.07, sill=0.5, bump_bot=0.42,
                  nose_top=1.04, nose_set=0.14, hood_front=1.1, belt=1.21, crease=1.04, tail_top=1.21,
                  hood=1.42, ws=0.48, roof=1.58, cf=0.12, cfl=0.42, flare=0.05, tumble=0.13,
                  lamp=dict(style="swept", x0=0.42, x1=0.9, y0=0.9, y1=1.0, wrap=0.3),
                  grille=dict(style="hex", w=0.46, y0=0.66, y1=1.0),
                  intake=dict(w=0.56, y0=0.46, y1=0.56, fogs=True),
                  tail=dict(style="rect", x0=0.82, x1=0.93, y0=0.86, y1=1.15, wrap=0.03),
                  bumper="clad", clad=dict(key="black", arch=0.09, sill=0.07), steps=None, tg_key=None,
                  wheel="offroad", tread=True, paint=(0.15, 0.32, 0.72)),
    # Crew-cab dually (Silverado HD): twin rear wheels under wide fenders, roof lamps,
    # tow mirrors, a big two-tier chrome grille.
    "dually": dict(L=5.9, W=2.03, rflare=0.2, H=2.0, wb=3.55, fo=0.95, r=0.42, tw=0.24, sill=0.52, bump_bot=0.44,
                   nose_top=1.22, nose_set=0.05, hood_front=1.25, belt=1.36, crease=1.18, tail_top=1.36,
                   hood=1.65, ws=0.38, roof=1.66, rw=0.05,
                   lamp=dict(style="rect", x0=0.56, x1=0.96, y0=1.06, y1=1.2, wrap=0.08),
                   grille=dict(style="slats", w=0.54, y0=0.72, y1=1.2, n=2, key="chrome", surround="chrome"),
                   tail=dict(style="rect", x0=0.86, x1=0.98, y0=0.96, y1=1.3, wrap=0.03),
                   dually=True, steps="silver", roof_lamps=True, tow_mirrors=True, tg_key=None,
                   wheel="dually", paint=(0.9, 0.9, 0.88)),
    # Lifted off-roader (TRD Pro/Raptor): big knobbly tyres, flares, a black hood scoop,
    # a sport bar with a lamp pod, red tow hooks.
    "rock": dict(L=5.5, W=2.0, H=2.0, wb=3.3, fo=0.82, r=0.48, tw=0.32, arch=0.07, sill=0.6, bump_bot=0.5,
                 nose_top=1.16, nose_set=0.12, hood_front=1.22, belt=1.33, crease=1.15, tail_top=1.33,
                 hood=1.4, ws=0.46, roof=1.58, rw=0.05, cf=0.1, cfl=0.42, flare=0.08, tumble=0.13,
                 lamp=dict(style="swept", x0=0.44, x1=0.92, y0=1.0, y1=1.1, wrap=0.3),
                 grille=dict(style="hex", w=0.46, y0=0.76, y1=1.1),
                 intake=None, tail=dict(style="rect", x0=0.84, x1=0.95, y0=0.98, y1=1.26, wrap=0.03),
                 bumper="black", clad=dict(key="black", arch=0.13, sill=0.1), steps=None, tg_key=None,
                 scoop="black", rollbar=True, hooks=True, wheel="offroad", tread=True,
                 paint=(0.33, 0.4, 0.22)),
    # Sport truck (Lightning/SRT-10): lowered, regular cab, hood scoop, big intakes,
    # sport wheels with red calipers.
    "sport": dict(L=5.35, W=1.96, H=1.64, wb=3.1, fo=0.95, r=0.38, tw=0.3, arch=0.04, sill=0.3, bump_bot=0.16,
                  nose_top=0.92, nose_set=0.22, hood_front=0.99, belt=1.1, crease=0.92, tail_top=1.1,
                  hood=1.55, ws=0.58, roof=1.16, rw=0.07, crown=0.03, cf=0.14, cfl=0.45, flare=0.03, tumble=0.14,
                  cab="regular", c_w=0.16, cab_corner=0.14,
                  lamp=dict(style="swept", x0=0.42, x1=0.9, y0=0.78, y1=0.88, wrap=0.32),
                  grille=dict(style="hex", w=0.4, y0=0.56, y1=0.82),
                  intake=dict(w=0.7, y0=0.2, y1=0.48, fogs=False, vents=True),
                  tail=dict(style="rect", x0=0.82, x1=0.94, y0=0.78, y1=1.04, wrap=0.03),
                  bumper="body", plate_y=0.34, mirror="body", steps=None, tg_key=None, scoop=True,
                  wheel="sport", paint=(0.92, 0.75, 0.12)),
    # 90s compact (Ranger/S-10) extended cab: small, plain, a black grille.
    "compact": dict(L=5.1, W=1.76, H=1.66, wb=3.2, fo=0.82, r=0.35, tw=0.22, sill=0.4, bump_bot=0.34,
                    nose_top=0.94, nose_set=0.1, hood_front=0.98, belt=1.08, crease=0.95, tail_top=1.08,
                    hood=1.45, ws=0.44, roof=1.34, rw=0.05, tumble=0.09, cf=0.08, cfl=0.3, cab="ext", b_at=0.76,
                    lamp=dict(style="rect", x0=0.46, x1=0.82, y0=0.8, y1=0.92, wrap=0.06),
                    grille=dict(style="slats", w=0.42, y0=0.76, y1=0.93, n=3, key="trim", surround="trim"),
                    tail=dict(style="rect", x0=0.74, x1=0.84, y0=0.76, y1=1.0, wrap=0.03),
                    bumper="black", mirror="black", steps=None, tg_key=None, wheel="alloy5",
                    paint=(0.15, 0.55, 0.58)),
    # The pavement princess: a crew-cab dually on a towering lift and mud tyres that
    # have never met mud, chrome wheels, chrome everything, coilovers in a loud colour
    # on show in the arch gaps, an LED light bar and ditch lights for the mall car
    # park, and twin chrome stacks in a spotless bed. Too tall for the ordinary lanes.
    "princess": dict(L=5.9, W=2.03, rflare=0.2, H=2.36, wb=3.55, fo=0.95, r=0.5, tw=0.33, arch=0.2,
                     sill=1.0, bump_bot=0.74, nose_top=1.56, nose_set=0.05, hood_front=1.6, belt=1.72,
                     crease=1.54, tail_top=1.72, hood=1.65, ws=0.38, roof=1.66, rw=0.05,
                     frame="chrome",
                     lamp=dict(style="rect", x0=0.56, x1=0.96, y0=1.42, y1=1.56, wrap=0.08),
                     grille=dict(style="slats", w=0.54, y0=1.08, y1=1.56, n=2, key="chrome", surround="chrome"),
                     tail=dict(style="rect", x0=0.86, x1=0.98, y0=1.32, y1=1.66, wrap=0.03),
                     dually=True, steps="chrome", roof_lamps=True, tow_mirrors=True, tg_key="chrome",
                     lift=True, shocks="caliper", lightbar=True, stacks=True, wheel="chrome", tread=True,
                     paint=(0.9, 0.9, 0.88)),
}

# --- Trucks (art/truck_kit.py) ---------------------------------------------------------

# A medium-duty conventional (Freightliner M2 / International MV) with a body behind.
TRUCK = dict(
    kind="straight", L=10.3, W=2.5, H=3.6, wb=6.1, fo=1.12,   # body width and height
    r=0.5, tw=0.27, track=1.22,                                # tyres; outer tyre face from the centre
    hood=1.3, hood_y0=1.5, hood_y1=1.7, fender_y=1.16, grille_w=1.0,
    ws=0.48, cab=1.42, cab_w=2.3, roof=2.68, door_back=0.18,
    grille="chrome", bumper="gunmetal", steps="silver", hooks=False,
    hood_hw=(0.58, 0.74), nose_round=0.1, fender_round=0.14, fender_run=0.32, bump=(0.39, 0.73),
    cab_y0=0.98, grille_top=0.14, grille_bars="horizontal", lamp_y=(0.92, 1.08), lamp_set=0.0,
    step_set=0.18, tanks=1, tank_r=0.27, tank_len=0.9, skirts=False, air_cleaners=False, stacks=0,
    sleeper=0.0, sl_roof=0.0, rise=1.0, extenders=False, visor=None,
    body="box", body_gap=0.16, floor=1.2, door="roll", reefer=False, tandem=False,
    tank_h=1.45, stripe="orange", tank_y0=1.1, tank_key="tankw", bearer_y=1.0, band=1.4,
    # (step van)
    sill=0.62, hood_y=1.32,
)

TRUCKS = {
    # 24' dry box on a single rear axle, roll-up door (the rental/delivery box truck).
    "box": dict(paint=(0.9, 0.9, 0.88)),
    # 20' reefer box with its unit over the cab, swing doors (sheet: the white reefer).
    "reefer": dict(L=9.3, wb=5.3, H=3.7, door="swing", reefer=True, paint=(0.88, 0.88, 0.86)),
    # Fuel delivery tank truck on a tandem (sheet: white cab, orange-striped tank).
    "tank": dict(L=9.4, wb=5.2, H=2.7, body="tank", tandem=True, grille="silver", paint=(0.9, 0.9, 0.88)),
    # Walk-in step van (sheet: the yellow one): one body, short nose, barn doors.
    "step": dict(kind="step", L=7.2, W=2.36, H=3.0, wb=4.1, fo=1.0, r=0.43, tw=0.24, hood=0.82,
                 paint=(0.93, 0.72, 0.14)),
}

# A Class 8 tractor: a bigger conventional on a tandem with a fifth wheel.
TRACTOR = dict(TRUCK)
TRACTOR.update(
    kind="tractor", L=7.0, W=2.5, H=3.0, wb=4.7, fo=1.1, r=0.52, tw=0.28, track=1.25,
    hood=1.95, hood_y0=1.66, hood_y1=1.98, fender_y=1.3, grille_w=1.05, hood_hw=(0.62, 0.86),
    nose_round=0.18, fender_round=0.25, fender_run=0.6, bump=(0.45, 0.82), cab_y0=1.25,
    grille_top=0.12, lamp_y=(1.02, 1.18), ws=0.55, cab=1.5, cab_w=2.36, roof=3.0,
    tanks=2, tank_r=0.33, tank_len=1.3, step_set=0.12, fw_ahead=0.2, fw_y=1.22, frame_y=1.05,
)

TRACTORS = {
    # Aero high-roof sleeper (sheet: the blue Cascadia): roof fairing, side extenders,
    # chassis skirts.
    "aero": dict(L=9.2, wb=6.4, sleeper=1.9, sl_roof=4.0, rise=1.2, extenders=True, skirts=True,
                 paint=(0.12, 0.3, 0.72)),
    # Mid-roof sleeper (sheet: the green one hauling the dry van).
    "midroof": dict(L=8.8, wb=6.0, sleeper=1.5, sl_roof=3.45, rise=0.9, extenders=True, skirts=True,
                    paint=(0.22, 0.5, 0.2)),
    # Aero day cab: drayage, the port and container work.
    "day": dict(L=6.9, wb=4.6, tank_len=1.0, paint=(0.9, 0.9, 0.88)),
    # Long-nose day cab (sheet: the red Peterbilt 389): square hood, set-back lamps,
    # air cleaners, a chrome stack, chrome bumper.
    "longnose": dict(L=7.9, wb=5.4, fo=1.05, hood=2.3, hood_y0=1.88, hood_y1=1.92, nose_round=0.03,
                     hood_hw=(0.6, 0.66), fender_y=1.22, fender_round=0.4, fender_run=0.9, grille_w=1.12,
                     grille_bars="vertical", grille_top=0.08, lamp_set=0.5, lamp_y=(1.04, 1.2), ws=0.45,
                     roof=2.95, air_cleaners=True, stacks=1, bumper="chrome", tank_len=1.1,
                     paint=(0.75, 0.13, 0.08)),
    # Long-nose flat-top sleeper (W900 kind): twin stacks, a visor.
    "classic": dict(L=9.4, wb=6.6, fo=1.05, hood=2.3, hood_y0=1.88, hood_y1=1.92, nose_round=0.03,
                    hood_hw=(0.6, 0.66), fender_y=1.22, fender_round=0.4, fender_run=0.9, grille_w=1.12,
                    grille_bars="vertical", grille_top=0.08, lamp_set=0.5, lamp_y=(1.04, 1.2), ws=0.45,
                    roof=2.95, sleeper=1.6, air_cleaners=True, stacks=2, visor="body", bumper="chrome",
                    paint=(0.38, 0.08, 0.12)),
}

# Semi-trailers: the kingpin kp behind the nose at the fifth wheels' height, the tandem's
# centre ro ahead of the back. Two axles on all (US practice), tyres as the tractors'.
TRAILER = dict(TRUCK)
TRAILER.update(
    kind="trailer", L=16.15, W=2.6, H=4.1, r=0.5, tw=0.27, track=1.28, kp=0.9, ro=1.6, fw_y=1.22,
    body="van", floor=1.32, roof=2.5, bearer_y=0.95, door="swing", skirts=True, stripe=None,
)

TRAILERS = {
    # 53' dry van, side skirts (sheet: the white one).
    "van": dict(paint=(0.9, 0.9, 0.88)),
    # 53' reefer, its unit on the nose (sheet).
    "reefer": dict(reefer=True, paint=(0.88, 0.88, 0.86)),
    # 40' container on a skeletal chassis (sheet: the red one).
    "container": dict(L=12.5, H=3.92, body="container", ro=1.4, floor=1.33, paint=(0.72, 0.18, 0.1)),
    # 48' flatbed, wood deck (sheet).
    "flatbed": dict(L=14.6, H=1.6, body="flatbed", floor=1.5, ro=1.5, paint=(0.2, 0.2, 0.22)),
    # Log trailer: bunks and stakes on a pole frame, long logs (sheet, PNW style).
    "logs": dict(L=13.0, H=3.4, body="logs", floor=1.45, ro=2.4, paint=(0.2, 0.2, 0.22)),
    # Polished aluminium fuel tanker (sheet).
    "tank": dict(L=13.0, H=3.1, body="tank", tank_h=2.0, tank_y0=1.02, tank_key="chrome", stripe=None, ro=1.5, band=3.0,
                 paint=(0.2, 0.2, 0.22)),
    # End dump (sheet: the dark ribbed tub).
    "dump": dict(L=11.0, H=3.4, body="dump", floor=1.4, ro=1.4, paint=(0.2, 0.21, 0.24)),
    # Two-level car hauler (sheet).
    "carhauler": dict(L=16.0, H=3.95, body="carhauler", ro=1.3, paint=(0.15, 0.17, 0.25)),
}

MODELS = {"sedan": (SEDAN, SEDANS), "suv": (SUV, SUVS), "minivan": (MINIVAN, MINIVANS), "van": (VAN, VANS),
          "pickup": (PICKUP, PICKUPS), "truck": (TRUCK, TRUCKS),
          "tractor": (TRACTOR, TRACTORS), "trailer": (TRAILER, TRAILERS)}


# --- Build and export -----------------------------------------------------------------

built, data, tris = [], {}, {}
for row, (model, (base, variants)) in enumerate(MODELS.items()):
    for i, (vname, over) in enumerate(variants.items()):
        prm = dict(base); prm.update(over)
        s = build_truck(prm) if model in ("truck", "tractor", "trailer") else build(prm)
        name = model + "_" + vname
        obs = finish(name)
        for ob in obs:
            ob.location = (i * (12.0 if model in ("truck", "tractor", "trailer") else 3.0), row * 7.0, 0)
        built += obs
        tris[name] = sum(len(o.data.polygons) for o in obs)
        # (the height overall: high tops and racks count, for the ferries' headroom)
        top = max(max((v.co.z for v in o.data.vertices), default=0.0) for o in obs)
        data[name] = dict(size=(prm["W"] + 2 * prm.get("rflare", 0.0), max(prm["H"], top), prm["L"]), head=s.head, tail=s.tail)
        for k in ("hitch", "pin", "axle"):
            if getattr(s, k, None) is not None:
                data[name][k] = getattr(s, k)

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
        extra = "".join(', "%s": %s' % (k, v3(d[k])) for k in ("hitch", "pin", "axle") if k in d)
        f.write('\t"%s": {"size": %s, "head": %s, "tail": %s%s},\n' % (name, v3(d["size"]), v3(d["head"]), v3(d["tail"]), extra))
    f.write("}\n")
result = tris

