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
| Pause (resume, restart, settings, quit) | Esc / P | Start |
| Graphics quality (Low / Medium / High) | F3 | |
| Restart round | R | |

## Game modes

- **Championship:** every map in a row against the same bots. Points for each finish (10, 8, 6, 5, 4, 3, 2, 1), standings after every round and a champion at the end.
- **Quick Race:** pick one map and play it as many times as you like.
- **Career:** your stunt cash, rounds, wins, knockouts, longest survival and biggest hit across every round you've played (saved between runs).
- **Settings** (saved between runs): graphics quality, fullscreen, vsync, render scale, field of view, master/music/effects volume, your driver name and car colour, number of bots (1–9), bot difficulty and round length.

## How a round works

- A **Next Derby** screen shows the map, the car everyone gets and the map's twist.
- After a countdown, everyone fights for up to 2:30 (or the round length you picked).
- Hard impacts cost health; hits on your front bumper hurt less, so ram rather than get rammed.
- A car at 0 HP explodes. A car that falls off, or sits on its roof for 3 seconds, is out too.
- In the last minute the map starts **collapsing** from the outside in, piece by piece.
- Knocking a car out gives you the credit in the kill feed. Once you're out you can spectate.
- The scoreboard ranks drivers by how long they survived and shows everyone's stunt cash. The next map loads automatically.

## Pickups

Glowing icons on the platforms (never on the roads). Drive through one to take it; it comes back about 20 seconds later.

| Pickup | Effect |
|---|---|
| **Repair** (green cross) | +40% health, and some of the smoke clears |
| **Nitro** (blue bottle) | Fills your nitro |
| **Ram** (orange chevrons) | For 8 seconds your hits do double damage and you take half; your car glows |
| **Shockwave** (purple rings) | Blasts every car near you outward and up. Knock-offs it causes count as yours |

Badly hurt bots go for a repair if one is up on a platform close by.

## Stunt cash

| Stunt | Cash |
|---|---|
| Big hit (14+ damage; "mega" at 34+) | $10 per point of damage |
| Knockout credited to you | $500 |
| Airtime: a second or more with all wheels off the ground, landing on your wheels (a plain hop doesn't count) | $150 a second |
| Surviving | $8 a second at the end of the round |
| Winning the round | $1,000 |

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
| `scripts/car_visuals.gd` | Loads the car models and wheels, sets their materials, dents the body on hits |
| `scripts/player_controller.gd` | Keyboard / gamepad driving |
| `scripts/bot_controller.gd` | Bot AI: follow the roads, pick a target, ram it, stay on the road |
| `scripts/maps/derby_map.gd` | Map building blocks: pads, roads, stilts, collapse, sky and lighting |
| `scripts/maps/*.gd` | The seven maps |
| `scripts/maps/mesh_kit.gd` | Merges boxes, beams, tubes and rock shells into single meshes for map scenery |
| `shaders/` | Road decks (planks, asphalt, wet asphalt, steel grating, ice), rock (sandstone, snowy granite), concrete, steel, containers, city windows and streets, sky, ocean and clouds, and the glow round pickups |
| `scripts/chase_camera.gd` | Third-person follow camera |
| `scripts/hud.gd` | Health, nitro, timer, kill feed, Next Derby screen, scoreboard and standings |
| `scripts/pickups.gd`, `scripts/pickup.gd` | Pickups: placing them on pads, collecting, effects, respawning, bots' repair detours; the spinning icon |
| `scripts/ram_boost.gd` | The Ram pickup's damage boost and glow |
| `scripts/stunt_score.gd`, `scripts/stunt_hud.gd` | Stunt cash for hits, knockouts, airtime, survival and wins; the cash popups and pickup notices |
| `scripts/career.gd` | Career totals saved to `user://profile.cfg` |
| `scripts/game_settings.gd` | Settings and their save file |
| `scripts/ui/` | Title menu, settings panel, pause menu and the shared UI look |
| `scripts/audio/` | Engine, tyre and crash sounds per car; music and UI sounds |
| `assets/cars/` | Car models, generated by `tools/blender/build_cars.py` |
| `assets/audio/` | Sounds and music, generated by `tools/audio/make_sounds.py` |
| `tests/calibrate.gd` | Prints top speed and turning for each car type |
| `tests/push_test.gd` | Checks a bot pushes a car stuck on an edge off |
| `tests/menu_test.gd` | Plays the menu and a whole championship headless |
| `tests/audio_test.gd` | Checks every sound loads and plays |
| `tests/pickup_test.gd` | Checks each pickup's effect and respawn, Ram crash damage, stunt cash, bot repair detours and the career file |

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
