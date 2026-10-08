class_name Units
extends RefCounted
## Lengths are metres throughout. Things that move about the map (vessels, cars,
## wildlife) go SPEED_UP times faster than their real speed, so that with the
## clock's one real second to a game minute a crossing still takes a sensible part
## of a game hour; the HUD shows their real speed.

const KNOT := 0.514444          # m/s
const SPEED_UP := 3.6


## Real speed, in knots, of something moving at `v` (m/s on the map).
static func knots(v: float) -> float:
	return v / SPEED_UP / KNOT


## Speed on the map (m/s) of something making `kn` knots.
static func from_knots(kn: float) -> float:
	return kn * KNOT * SPEED_UP
