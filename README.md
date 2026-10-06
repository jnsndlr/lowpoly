# Ferry Tycoon (preview)

A low-poly ferry-system management game prototype in **Godot 4.7**. It procedurally
generates an archipelago with towns, terminals and routes. Cars drive from town to
the holding lots, queue in lanes, board double-ended ferries, cross, and drive off
at the other side.

Open the folder in Godot 4.7 and press **Play** (F5). Everything is built in code,
so there are no assets to import.

## Controls

| Action | Mouse / trackpad | Keys |
|---|---|---|
| Pan | Left-drag, two-finger swipe | WASD / arrows |
| Rotate / tilt | Right- or middle-drag | Q E / R F |
| Zoom (toward cursor) | Wheel, pinch | Z X or + − |
| Select island / vessel | Click (or click an island label) | Tab = next ferry, Esc = deselect |
| Time | Speed buttons in the top bar | Space = pause, 1–3 = speed |
| New random map | | G |

Selecting a ferry, sailboat or cargo ship follows it with the camera. Selecting an
island shows its stats and the terminal status bar (queue, next departure, weather,
wind, tide).

## Architecture

```
scripts/
  main.gd                 entry point: generate → build world → start sim → HUD
  map/map_data.gd         pure data: islands, terminals, marinas, towns, routes (editor-friendly)
  map/map_generator.gd    procedural layout → MapData
  map/terrain.gd          heightfield (island stamping, cliffs, terminal flattening)
  world/world_builder.gd  MapData → meshes (terrain, water, terminals, towns, forests)
  world/models.gd         procedural low-poly meshes (trees, houses, cars, ferry…)
  world/mesh_builder.gd   flat-shaded vertex-coloured mesh helper
  world/glow_builder.gd   night-light quads (glows, pools, beams, reflections) for glow.gdshader
  world/night_lights.gd   dusk-to-dawn switching, car head/tail lights, ferry nav lights, bokeh focus
  world/seagulls.gd       simulated gulls perching on lamps, lifts, ferries, water
  world/orcas.gd          orca pods: formation, breathing rolls, blows, breaches, spyhops
  sim/simulation.gd       clock (1 s = 1 game min), seasons, demand curve, fares, satisfaction
  sim/wildlife.gd         species table, daily visits, sightings, island wildlife reputation
  sim/terminal.gd         spawning, lane queues, boarding/exit paths
  sim/vessel.gd           base for anything afloat: hull capsule, path lookahead, right of way
  sim/ferry.gd            load → sail → unload state machine along a Curve3D
  sim/ferry_class.gd      the five ferry sizes: lanes, rows, hull, speed, fittings
  sim/sailboat.gd         marina-to-marina sailing: back out, sail, wait for and enter a berth
  sim/cargo_ship.gd       container ships transiting the map edge to edge
  sim/marine_traffic.gd   all vessels: collision avoidance, ferry corridors, marina berths
  sim/nav_grid.gd         A* water grids (small boats / ships) and path smoothing
  sim/nav_path.gd         polyline walked by arc length
  sim/vehicle.gd          waypoint-following car/truck
  sim/layout.gd           shared terminal / ferry dimensions
  camera/camera_rig.gd    RTS orbit camera
  ui/hud.gd               all UI, built in code
tools/vessel_soak_test.gd headless soak test: hulls touching, groundings, long holds
shaders/water.gdshader    depth-based shallow/deep colour + shoreline foam
shaders/seagull.gdshader     gull wing flap/fold
shaders/orca.gdshader     orca dorsal fin height/sweep and tail beat
shaders/glow.gdshader     screen-space night lights with distance bokeh and water reflections
```

`MapData` is the seam for a future **map builder**: the generator only produces
`MapData`, and the world builder and simulation only read it. A hand-authored or
saved map can therefore replace `MapGenerator.generate()` without other changes.

## Traffic afloat

Most inhabited islands get a small marina (a pier with a T-head and four berths).
Sailboats lie there for a few game hours, then back out and sail to a free berth
elsewhere, or out and back home, in daylight only. Container ships pass through
from one map edge to another every hour or so. Both plan routes on coarse water
grids (`NavGrid`) that keep clear of land, terminals and piers, cost extra on
ferry lanes, and keep to the right so opposing traffic passes.

No two hulls ever touch. Each hull is a capsule, and every frame `MarineTraffic`
checks each moving vessel's hull at a run of poses along its path ahead against
every other hull, and against the path ahead of any higher-ranked vessel (ferries
outrank cargo ships, which outrank sailboats). The answer is a distance the vessel
may still go, and it brakes to stop within it. Where two ferry routes run too close
to pass (`Corridor`), one ferry at a time reserves the stretch; one boat at a time
backs out of or noses into a marina; a sailboat stuck nose to nose re-plans round
the other vessel.

## Wildlife

`Wildlife` rolls each species once a game day. A visiting group arrives from offshore,
circles one island (picked by `Island.wildlife_appeal`, scaled by
`Wildlife.island_attraction` for future research and policies), and leaves when the
visit is over. Orcas come every day as a pod of 2–8 for 3 game hours. The other
species (humpback, gray whale, sea lion, porpoises, harbor seal) are in the table
with their draw, but stay disabled until they have their own behaviour and models.

A visit counts as a sighting for an island only in daylight, and only if the group
comes within 150 m of that island's ferry dock or 110 m of a sailing ferry. A ferry
sighting credits both ends of its route. Each credited island's wildlife reputation
jumps by the species' draw (orca 3.0 … harbor seal 0.08), then halves every 6 days
down to a floor of 40% of the season's best, which clears when the season turns
(30 days). Clicking a surfaced animal once per visit adds a 50% photo bonus. Open
**WILDLIFE** in the sidebar for recent sightings and the islands with the most draw.

## Debug / screenshot flags

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --seed=42 --select=1 --speed=2 --shot=out.png --shot-delay=10
```

Available flags: `--seed=N`, `--speed=0..3`, `--cam=x,z,dist,yaw,pitch`, `--select=K`,
`--follow=K`, `--time=H`, `--shot=path.png`, `--shot-delay=s`, `--bench=s`, `--orcas`
(start an orca visit now and follow it).

`--bench=s` prints average frame time, GPU time, draw calls and primitives over `s`
seconds and quits. Metal doesn't report GPU time, so profile with Vulkan:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --rendering-driver vulkan -- --seed=42 --bench=6
```
