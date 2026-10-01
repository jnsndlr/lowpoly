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
| Select island / ferry | Click (or click an island label) | Tab = next ferry, Esc = deselect |
| Time | Speed buttons in the top bar | Space = pause, 1–3 = speed |
| New random map | | G |

Selecting a ferry follows it with the camera. Selecting an island shows its stats and
the terminal status bar (queue, next departure, weather, wind, tide).

## Architecture

```
scripts/
  main.gd                 entry point: generate → build world → start sim → HUD
  map/map_data.gd         pure data: islands, terminals, towns, routes (editor-friendly)
  map/map_generator.gd    procedural layout → MapData
  map/terrain.gd          heightfield (island stamping, cliffs, terminal flattening)
  world/world_builder.gd  MapData → meshes (terrain, water, terminals, towns, forests)
  world/models.gd         procedural low-poly meshes (trees, houses, cars, ferry…)
  world/mesh_builder.gd   flat-shaded vertex-coloured mesh helper
  sim/simulation.gd       clock (1 s = 1 game min), demand curve, fares, satisfaction
  sim/terminal.gd         spawning, lane queues, boarding/exit paths
  sim/ferry.gd            load → sail → unload state machine along a Curve3D
  sim/vehicle.gd          waypoint-following car/truck
  sim/layout.gd           shared terminal / ferry dimensions
  camera/camera_rig.gd    RTS orbit camera
  ui/hud.gd               all UI, built in code
shaders/water.gdshader    depth-based shallow/deep colour + shoreline foam
```

`MapData` is the seam for a future **map builder**: the generator only produces
`MapData`, and the world builder and simulation only read it. A hand-authored or
saved map can therefore replace `MapGenerator.generate()` without other changes.

## Debug / screenshot flags

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --seed=42 --select=1 --speed=2 --shot=out.png --shot-delay=10
```

Available flags: `--seed=N`, `--speed=0..3`, `--cam=x,z,dist,yaw,pitch`, `--select=K`,
`--follow=K`, `--time=H`, `--shot=path.png`, `--shot-delay=s`, `--bench=s`.

`--bench=s` prints average frame time, GPU time, draw calls and primitives over `s`
seconds and quits. Metal doesn't report GPU time, so profile with Vulkan:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --rendering-driver vulkan -- --seed=42 --bench=6
```
