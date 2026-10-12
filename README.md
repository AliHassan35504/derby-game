# Derby Game

A last-car-standing demolition derby. Every player gets a car on a floating
arena with no walls. Smash the other cars until they blow up or get knocked off
the edge. The last car still driving wins the round.

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
| Handbrake | Space | A |
| Restart round | R | Start |

## How a round works

- You drive the blue **Sedan**. Five bots get a random **Compact**, **Sedan** or **Truck**.
- After a 3-second countdown everyone can drive.
- Hard impacts with other cars cost health. Hits on your front bumper hurt less, so ram rather than get rammed.
- A car at 0 HP explodes; a car that falls off the platform is out too.
- After 75 seconds it's **sudden death**: every car slowly loses health until one is left.
- The next round starts automatically, or press R.

## Project layout

| Path | What it is |
|---|---|
| `scenes/main.tscn` | Entry scene; everything else is built from code |
| `scripts/game.gd` | Round flow: spawning, countdown, eliminations, winner |
| `scripts/car.gd` | The car: types and stats, driving, damage, explosions |
| `scripts/player_controller.gd` | Keyboard / gamepad driving |
| `scripts/bot_controller.gd` | Bot AI: pick a target, ram it, stay away from the edge |
| `scripts/arena.gd` | The floating platform map, ramps, crates, sky and lighting |
| `scripts/chase_camera.gd` | Third-person follow camera |
| `scripts/hud.gd` | Health, cars left, countdown and kill feed |
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

That swaps you for a bot, plays one round at 4× speed and prints who was
eliminated and who won. CI runs it on every pull request.
