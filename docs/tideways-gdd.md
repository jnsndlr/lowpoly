# Tideways

## Game Design Document (v0.4, 2026-10-31)

Built from GDD v0.3 in the Tideways prototype repo, the systems on the "Ferry game" FigJam board, and the October 2026 design review.

**How to read this document**

- This GDD is the master design. Anything not marked otherwise is decided.
- **Default** marks a suggestion that was not explicitly confirmed. It stands until someone changes it.
- All numbers are starting points for tuning unless a rule says otherwise.
- The TypeScript prototype is a reference, not a spec. Its scheduling and terminal ideas are useful, but its numbers are not canonical. Real cars in real lanes and real space on boats, as in [Jon's Tideways Godot project](https://github.com/jnsndlr/tideways), are what matter.

---

## High Concept

Tideways is a cozy but deep ferry management sim for computer and iPad, inspired by Washington State Ferries, SimAirport, Mini Metro, RollerCoaster Tycoon, Port Royale and Lemonade Tycoon.

The player builds a region and a ferry fleet together. They start with two small terminals and one basic boat, and grow a network that changes the islands it serves. Logistics is the main activity, with direct building for terminals, moorings and upgrades.

The player could be a private company or a public agency. It doesn't matter. Their job is to serve the region and thrive.

---

## Design Pillars

**Meaningful logistics.** Every decision ripples through the simulation. A new sailing can raise revenue, raise fuel costs, cut waits, tire crews and help a town grow. The game rewards thoughtful optimization, not perfect execution.

**Real things in the world.** Each vehicle is a real trip, and each lane and deck space is physical. Problems are visible in the world: a long queue, a blocked slip, a driver giving up and turning around.

**Human management.** Transportation is about people. Pay, staffing, fatigue and captains all affect how well the network runs.

**Organic community growth.** Players don't build towns directly. They create the conditions for towns to grow, and each town shows who it has been served by.

**Calm strategy.** No combat and no twitch mechanics. The challenge comes from balancing connected systems and watching the network evolve.

**Regular progress.** Building and upgrading are part of the fun, so there should always be something worth buying soon.

---

## Core Loop

1. See what a town needs.
2. Buy, build or research something that helps.
3. Assign boats and set schedules, fares and staffing.
4. Carry vehicles and collect revenue.
5. Pay for fuel, crew and upkeep.
6. Watch towns respond with more demand, new buildings and new needs.
7. Expand to the next dock, boat or island.

The core feedback loop is: community growth, travel demand, revenue, fleet and terminal expansion, better service, more community growth.

---

## Game Structure

- **Start:** 2 or maybe 3 terminals, 1 or 2 boats and some money. Other islands are present but not built out or connected.
- **Length:** open-ended. A full region should take 20–30 hours.
- **Direction:** milestones give sessions purpose, such as serving every island or growing a town to a given size. They are recognition, not gates.
- **Failure:** bankruptcy is the only loss, and the route to it is generous (see Finance).
- **Test scene:** the current tech demo stays as a hidden scene that developers can switch to inside Godot. Players never see it.

### Time

- 1 real second is 1 game minute at 1x.
- A game day is 24 minutes at 1x, 8 at 3x and 3 at 8x.
- A season lasts about 7 days, so a game year is 28 days.
- 3x is normal play, 1x is for watching, and 8x is for skipping ahead. Test builds should also run at about 20x.

At 3x, a year takes about 3.7 hours, so a full region spans about 6–8 game years.

### Pacing Targets

| Reward | Target at 3x | In game time | Over 25 hours |
|---|---|---|---|
| Something new | Every 3 minutes | About 9 hours | About 500 |
| Bigger purchase | Every 5–10 minutes | About 15–30 hours | About 150–300 |
| Visible change | Every 10 minutes | About 30 hours | About 150 |

Towns must therefore evaluate growth at least daily. The prototype's weekly tick is too slow.

With 10 towns, 150 visible changes means about 14 per town. Towns need small steps, such as a new house, shop or dock shed, with larger authored stages as milestones. Terminal construction also counts as a visible change.

---

## The Region

- One curated map with fictional names. Random generation remains for testing.
- One mainland edge and 10 islands, with one town per island to start.
- Each island has 2–3 authored terminal sites, so the map has about 20–30 sites.
- Water is divided into authored zones. Passages can have their own events and delays.
- Unconnected islands show small settlements with no travel until they are connected.
- Later, players can place a terminal along a shoreline to change a route's length.
- This map size is a planning target that must be confirmed on an M1 iPad.

---

## Terminals

Developing a terminal site costs money. After that, terminals upgrade one purchase at a time.

| Track | Rule |
|---|---|
| Lanes | Start at 3 on a small terminal, then add one at a time. About 10 is a large terminal. |
| Slips | Add one at a time, up to 3 per terminal for now. |
| Boat size limit | Upgrade wingwalls and dolphins so larger boats can dock. |
| Amenities | Add one by one for satisfaction and side income. |
| Moorings | Cheap to build. They hold boats without using a loading ramp. |
| Truck staging | Extra lanes for commercial traffic. |

- Amenity examples are a coffee shop, restaurant, gift shop, covered waiting area, restrooms, expanded parking, bike storage and tourist information.
- Lanes split automatically by scheduled capacity, and the player can override the split.
- When a slip is busy, arriving boats hold offshore.
- **Default:** construction takes game time, stays visible, and the terminal stays open.

---

## Routes and Scheduling

Any two docks can be connected. Distance comes naturally from where they are. Players can build whatever network they like, and hub-versus-direct play is not a separate mechanic.

A route's running cost comes from:

- **Fuel:** distance and speed.
- **Staffing:** the level set on the boats serving it.

Scheduling offers three depths, so players can do as much as they enjoy:

1. **Auto:** assign a boat to a route and it schedules itself.
2. **Frequency:** set how often it sails.
3. **Manual:** build complex multi-leg schedules for each boat.

All three are in Phase 1. Manual scheduling is the largest UI job in that phase, and it must work on touch screens. The prototype is a reference for the logic, not its screens.

Schedules show projected fuel and crew cost per day, calculated from the boat's schedule. That makes the timetable a financial tool: players see the cost before a sailing runs.

**Default:** players can run separate weekday and weekend schedules, so the weekly rhythm is a real planning choice.

---

## Demand and Vehicles

Towns generate real trips. Every vehicle has an origin, destination, type and patience. The types of traveller are commuter, tourist and freight.

Vehicles that run out of patience visibly give up, and this counts against service in that town.

| Vehicle | Fare relative to a car | Notes |
|---|---|---|
| Car | 1x | Base fare |
| Big van | 1.5x | Takes more deck space |
| Box truck | 2x | Commercial |
| Large truck | 3x | Commercial |

Deck space and fares follow vehicle length and height. Commercial traffic needs to travel, so it pays more and is less likely to give up.

**Weekly rhythm:** commuters peak on weekdays, tourists surge on weekends and freight runs steadily on weekdays.

**Seasonal rhythm:** tourism swells in summer and falls in winter.

**Service-induced demand:** frequency, reliability, short waits, travel time, satisfaction and capacity all create more travel.

### Walk-on Passengers

Walk-ons are not in Phase 1, but they will become an integral core system on every boat, even without passenger-only vessels.

### Fares

- Players set fares per route for each vehicle type.
- The game suggests a starting fare based on distance.
- High fares reduce trips and satisfaction.
- **Default:** a company-wide control can adjust all fares at once.
- Research can reveal price tolerance and market segments.

### Satisfaction

Satisfaction emerges from play.

- **Improved by:** reliable schedules, short waits, friendly crews, safe operation and comfortable terminals.
- **Reduced by:** delays, crowding, breakdowns, long queues, poor service and strikes.

---

## Towns

Each town needs service in several categories. Towns grow by having specific needs met, or more slowly through general surplus capacity.

- **Town card:** shows 3–4 current needs and how well each is being met. Research adds more detail.
- **Example needs:** commuters want morning and evening capacity, tourists want weekend frequency, and lumber towns want reliable truck space.
- **Identity:** each town starts with a leaning, and service shapes what it unlocks.
- **No decline:** towns never lose buildings. Unhappiness lowers demand, and better service restores it.
- **Growth is visible:** town changes reflect who has been served.

| Leaning | Example unlocks |
|---|---|
| Lumber and industry | Sawmill, factory, shipyard |
| Tourism | Resort, marina, whale tours |
| Commuter | Suburbs, business parks, university |
| Other | Dairy, fishing, agriculture and more, varying by island |

A town can change direction. A fishing town served well for tourists could become a resort. Second towns on an island can come after launch.

---

## Fleet

Five size classes are planned, with fictional names. **Default:** players can name their boats and sell them later.

Owning a boat is cheap. Most cost comes from running it. A boat can sit idle if the player can't afford its crew or fuel, so selling isn't forced.

Every boat tracks capacity, fuel efficiency, speed, age, condition, staffing level and tank size.

### Fuel

- Each boat has a fuel level, and tank size varies by class.
- Boats fill up at any dock when below 10%, if there is money. There are no fuel depots, tank grades or supply chains.
- Fuel costs the same at every dock.
- A boat cannot depart unless it has enough fuel to reach its destination.
- It can always move to an adjoining mooring at the same terminal, if there is one.
- Warn the player before fuel or money stops a boat.

**Stop time** is the longer of two actions: offload and load, or refuelling. If loading takes less time than refuelling, refuelling sets the length of the stop.

### Laying Up

- The player can move a boat to a mooring. This takes no ramp.
- Laying up costs nothing beyond building the mooring.
- A boat stuck at a slip with no fuel money blocks that slip until the player pays or moves it.
- **Default:** a laid-up boat's crew goes unpaid, and bringing it back takes about a game day.

### Condition and Maintenance

- Condition is a percentage that falls slightly with each trip.
- Wear depends mostly on how hard a boat is run, and on captain skill and the boat's engineering score. Rough passages are not the main cause.
- Overhauls cost money and take the boat out of service, so maintenance collides with the timetable. Overhauls happen at one mainland yard, and the boat must sail there.
- A shipyard unlocked in a lumber town could later add a second yard.
- Used boats are cheaper and start with reduced condition, such as 50%. They need yard time and money to restore.

### Breakdowns

Breakdowns become more likely as condition falls. A broken boat limps to the next dock and blocks a slip. There are no rescues at sea.

Failure types include engine, hydraulics, electrical, loading ramp and navigation.

---

## Crew

Phase 1 uses one staffing level per boat: lean, adequate or well staffed. Lean costs less, but adds fatigue and risk.

Later phases build on the board's chain:

1. **Inputs:** pay per role, benefits tier, staffing level, schedule intensity and captain.
2. **Crew state:** fatigue and happiness.
3. **Performance:** per-boat crew scores.
4. **Results:** delays, call-outs, service quality, safety events and strikes.
5. **Effect on the network:** satisfaction, trips and willingness to pay.

### Crew Scores

Each boat has scores for Reliability, Morale, Safety, Service and engineering. Individual deckhands are not named or managed, and engineers are not named. Engineering is a per-boat score.

### Captains

Each boat has one named captain, with five stats: Seamanship, Leadership, Efficiency, Hospitality and Safety. Personalities such as Old Salt, Mentor or Strict add character. Worse captains can wear a boat faster.

### Pay and Events

- Players set pay per role and pick a benefits tier: minimal, standard or excellent.
- On-call and relief crews come from the board and are planned for later.
- Delays and call-outs arrive first, followed by safety events and strikes. Strikes always have warning signs.

---

## Finance

Revenue comes from vehicle fares, commercial traffic, amenities and bonuses. Walk-on fares come later.

Costs include fuel, wages, benefits, overhauls, repairs, upgrades and research.

Running out of money follows three steps:

1. The game warns the player.
2. Loans become available, once loans exist in a later phase.
3. Bankruptcy arrives only after a generous grace period. **Default:** about a full game week, or about an hour at 3x.

Loans are not in Phase 1.

---

## Research

Research costs money and time. There is no separate research currency. Operating routes also builds some passive information for free.

Research covers everything:

- **Information:** peak windows, price tolerance, demand types, hidden shortages, forecasts, latent potential and route profitability. Research can add this detail to town cards.
- **Purchase unlocks:** larger buildings, new boat classes and new terminal options.
- **Capabilities:** reservations and fleet analytics.
- **Direct improvements:** fuel efficiency, speed and faster ramps.

This replaces the old rule that research should avoid stat bonuses.

---

## Requests and Events

**Requests** are bonus side quests from towns, such as bringing the circus or delivering lumber. They have deadlines, and the only penalty for missing one is losing the bonus. There are no named representatives for now, though a mayor may come later.

Recurring requests such as mail or a school run can use the same system, with no penalties.

**Weather** can cause slow sailings and delays. Seasons change how the world looks and bring more bad weather in winter.

**Calendar events** come with seasons and will be designed later. They can be positive or negative, and should be announced early enough to react.

---

## Interface

The map is the main view. Every other view is a panel over it, and panels must work on desktop, tablet and phone.

Panels cover the board's Home Office functions: hiring, revenue and expenses, research, fleet purchasing, regional reports, scheduling and routing.

- Touch comes first. Hovering on PC for more information must also work as a tap.
- Touch targets should be at least 44 pixels.
- Queues and terminal problems should be readable directly on the map.

### Onboarding

Teaching happens through integrated popups and callouts during the main mission, not a separate tutorial.

### Saves

Saves are local to each platform, with no accounts or cloud management to start. **Default:** the game autosaves regularly, because iPad sessions get interrupted.

---

## Platforms and Graphics

- **Primary:** computer and iPad.
- **Secondary:** phone.
- **Performance floor:** M1 iPad at 30+ fps. Desktop targets 60 fps. Phone support does not lower the iPad floor.
- Use one scalable quality system, with graphics that vary by platform.
- Test the Mobile renderer early, and reduce polygon counts where needed.

---

## Phase 1: First Playable

A 2–3 hour game on one corner of the map, starting with 2 docks and one basic boat.

**In scope:**

- Cars and trucks as real trips, using lanes and deck space
- Auto, frequency and manual multi-leg scheduling
- Fare setting
- Fuel and staffing costs
- Laying up and moorings
- Town needs, town cards and visible growth
- A third dock and second boat
- A small research list for purchase unlocks
- Onboarding callouts
- Local saves
- Bankruptcy

**Not in scope:**

- Walk-ons
- Named captains and crew scores
- Requests and contracts
- Loans
- Breakdowns
- Used boats

### Purchase List

This draft assumes 3 terminals in the Phase 1 corner.

| Purchase | Count | Size |
|---|---|---|
| Lanes, added one at a time | 15 | Small |
| Terminal amenities | 9 | Small |
| Mooring spots | 3 | Small |
| Truck staging lanes | 3 | Small |
| Research unlocks | 8 | Mixed |
| Second and third slips | 3 | Bigger |
| Dock size upgrades | 3 | Bigger |
| New terminal sites | 2 | Major |
| Additional boats | 2 | Major |

That is 48 purchases, or one every 3–4 minutes over 2–3 hours. Phase 1 also needs about 12–18 visible changes.

Research unlocks can include bigger docks, a larger boat class, faster ramps, fuel efficiency and more town card detail.

### Later Phases

Later phases will be chosen by what the game needs once Phase 1 is playable. Likely candidates are walk-ons, captains and crew scores, requests, loans, breakdowns, used boats, the full region and weather.

---

## From Tech Demo to Game

The Tideways Godot project already has terminals, lanes, real vehicles, shuttling boats, five ferry sizes, fares, seasons and working Fleet, Wildlife, Routes and Map panels.

It does not yet have expenses, breakdowns, foot passengers, audio or saves. Company, Research and Finances are placeholders.

The tech demo uses 30-day seasons, and the game uses about 7. Town population is also set once, so growth is new work.

---

## Open Issues

- **Advertising:** v0.3 has paid campaigns to raise demand for a while, such as tourism or freight. Whether the game needs this is undecided, and nothing in Phase 1 depends on it.

### Possible Later

Environmental rules, carbon tracking, a mayor, regional fuel prices, passenger-only boats and second towns on an island.

### Cut

Rival companies, historical eras and a story campaign.

---

## Vision

The player begins with one basic boat serving two small communities.

Over time they build a regional network where every schedule, crew, boat and town influences the others. Success isn't the number of ferries owned. It's a resilient, thriving transport system that shapes the future of an entire island region.
