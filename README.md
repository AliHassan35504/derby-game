# Derby Game

A last-car-standing demolition derby on narrow roads floating in the sky.
The roads are one car wide with no rails. Ram the other cars off the edge or
smash them until they blow up. The last car still driving wins the round.

Every map hands the same car to everyone, so a round is about driving, not
about who got the better car.

Built with [Godot 4.4](https://godotengine.org) (free, MIT licence).

## Play it

Download `DerbyGame-windows.zip` from the latest
[release](https://github.com/AliHassan35504/derby-game/releases), unzip it and
double-click `DerbyGame.exe`. Windows may warn that the app is unrecognised
because it isn't code-signed yet: click **More info → Run anyway**.

## Open it in the editor

1. Install Godot 4.4 or newer (the standard version, not .NET).
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button in the top right) to play.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate | W / ↑ | Right trigger |
| Reverse / brake | S / ↓ | Left trigger |
| Steer | A D / ← → | Left stick |
| Nitro | Shift | Right bumper |
| Hop (jump a gap or dodge a hit) | E | A |
| Brace (heavier, slower, takes less damage) | Q | Left bumper |
| Handbrake | Space | B |
| Spectate next / previous car (after you're out) | → / ← | D-pad |
| Graphics quality (Low / Medium / High) | F3 | |
| Restart round | R | Start |

## How a round works

- A **Next Derby** screen shows the map, the car everyone gets and the map's twist.
- After a countdown, six cars fight for up to 2:30.
- Hard impacts cost health; hits on your front bumper hurt less, so ram rather than get rammed.
- A car at 0 HP explodes. A car that falls off, or sits on its roof for 3 seconds, is out too.
- In the last minute the map starts **collapsing** from the outside in, piece by piece.
- Knocking a car out gives you the credit in the kill feed. Once you're out you can spectate.
- The scoreboard ranks drivers by how long they survived. The next map loads automatically.

## Maps

| Map | Car | Twist |
|---|---|---|
| Boardwalk | Hot Rod Van | Wooden stilt roads over the sea, a spiked hub in the middle |
| Sky Maze | Stinger GT | A grid of pale ramps above the clouds at different heights; nitro refills twice as fast |
| Mountain Spiral | Big Foot monster truck | An asphalt helix climbing a rock pillar to a summit pad; hops go higher |
| Harbour Cranes | Ranger Pickup | Sunset port: grated steel walkways between container stacks and two gantry crane booms, with a low walkway passing under both; fall in the sea and you're out |
| Canyon Bridges | Bulldog Muscle | Midday desert canyon: rope spans and timber trestles between sandstone mesas, in a figure eight that crosses over itself; nitro refills 50% faster |
| Neon Overpass | Cruiser Sedan | Night city: a stacked highway interchange between skyscrapers and neon signs, crossing over and under itself five times; wet roads, 15% less grip |
| Frozen Peaks | Kestrel Rally | Dawn in the mountains: ice roads on rock arches in a six-pointed star round a high summit, falling snow, a frozen lake below; a third less grip |

## Project layout

| Path | What it is |
|---|---|
| `scenes/main.tscn` | Entry scene; everything else is built from code |
| `scripts/game.gd` | Round flow: spawning, countdown, eliminations, winner |
| `scripts/car.gd` | The car: types and stats, driving, nitro, hop, damage, explosions |
| `scripts/car_visuals.gd` | Builds the van, sports car and monster truck bodies and wheels |
| `scripts/player_controller.gd` | Keyboard / gamepad driving |
| `scripts/bot_controller.gd` | Bot AI: follow the roads, pick a target, ram it, stay on the road |
| `scripts/maps/derby_map.gd` | Map building blocks: pads, roads, stilts, collapse, sky and lighting |
| `scripts/maps/*.gd` | The seven maps |
| `scripts/maps/mesh_kit.gd` | Merges boxes, beams, tubes and rock shells into single meshes for map scenery |
| `shaders/` | Road decks (planks, asphalt, wet asphalt, steel grating, ice), rock (sandstone, snowy granite), concrete, steel, containers, city windows and streets, sky, ocean and clouds |
| `scripts/chase_camera.gd` | Third-person follow camera |
| `scripts/hud.gd` | Health, nitro, timer, kill feed, Next Derby screen and scoreboard |
| `tests/calibrate.gd` | Prints top speed and turning for each car type |

## Building the .exe

Every push to `main` builds `DerbyGame.exe` in CI (download it from the run's
artifacts). Pushing a `v*` tag that has a GitHub release attaches the zip to
that release. To build locally, install Godot's export templates
(Editor → Manage Export Templates) and run:

```
godot --headless --path . --export-release "Windows" build/windows/DerbyGame.exe
```

## Testing without a screen

```
godot --headless --path . -- --autotest
```

That swaps you for a bot, plays one round on each map at 4× speed and prints
who was eliminated and who won. CI runs it on every pull request.
