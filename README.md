# Rimwatch

A side-scrolling rescue shooter for the iPhone Duo's inner display, inspired by the classic arcade
game Defender (Williams Electronics, 1981). Native iOS, written in Swift with SpriteKit. It has no
third-party dependencies and no asset files: the art is drawn in code and the sound is synthesised.
The one image in the app, its icon, is drawn by a script too.

![Rimwatch gameplay: a colonist returned to an outpost at the end of wave 2](docs/screenshot.png)

*Captured on an ordinary iPhone simulator, letterboxed to the Duo's inner-display shape.*

## Inspiration

Rimwatch sets out to capture the feel of Defender: fast momentum flight over a wraparound world, a
scanner that shows all of it, and a loop built on protecting people on the ground and catching them
when they are carried off.

It is a tribute, not a copy. The name, ship, enemies, art, sounds and screen layout are its own,
and it adds mechanics of its own too: the heat meter, Blink, the carry multiplier, the shield and
Blackout. Rimwatch is not affiliated with or endorsed by the owners of Defender.

## Status

All seven steps of the build plan are done and were checked in the simulator. The game has not yet
been run on a real iPhone Duo, so the open inner display (layout around the crease and camera
hole), play feel, speaker sound, haptics and physical controllers are untested. `PLAN.md` lists
what is left.

## The game

You patrol a wraparound planet strip about eight screens wide. A scanner across the top shows the
whole world.

- **The loop:** colonists live in domed outposts. Harvesters descend, grab one and lift it away.
  Shoot the Harvester, catch the falling colonist and carry them back to an outpost. An abduction
  that completes turns the pair into a Husk, a fast hunter.
- **Enemies:** Harvester (abductor), Husk (hunter), Sower (lays tethered mines), Brood (splits into
  Motes when shot), Lancer (telegraphed charge across the screen) and Anchor (lands and drills an
  outpost until destroyed). Each kind first appears in a wave of its own.
- **Your ship:** a pulse lance that overheats if you hold fire too long, a Shockwave with limited
  charges that clears the screen, and Blink, a short dash on a cooldown.
- **Twists:** carrying several colonists at once builds a score multiplier. Returning them charges
  your shield. Losing every colonist triggers Blackout: the terrain goes dark, the scanner switches
  off and Husks swarm until a supply drop restores an outpost.
- **Structure:** escalating waves, three lives, an extra life every 40,000 points and a local
  top-10 high-score table.

## Controls

| Action | Touch | Gamepad |
|---|---|---|
| Fly | Floating stick under the left thumb | Left stick or D-pad |
| Fire (hold to autofire) | Fire button, right thumb | A |
| Blink | Blink button | B |
| Shockwave | Shockwave button | X |
| Pause | Pause button | Menu |

Options let you swap the touch controls to the other hand and swap Blink and Shockwave on the
gamepad. The touch controls hide while a controller is connected, and menus work with either.

Sound respects the phone's Silent mode: with Silent mode on, the game plays no sound or music.

## Fold behaviour

Gameplay only runs on the open inner display.

| Phone | What happens |
|---|---|
| Open | The game plays in landscape on the inner display. |
| Closed | The game pauses at once and the outer display shows the pause menu in portrait: start over, end game, options and high scores. Resume waits until the phone is opened. |
| Reopened | The pause menu appears on the inner display, and Resume leads into a short countdown. |
| No hinge (any other iPhone) | A "Made for iPhone Duo" screen. |

## Requirements

- macOS 26.6 or later with Xcode 27.1 or later.
- iOS 27.1 or later on the device or simulator.
- The iPhone Duo simulator needs its own runtime build; see "Progress" in `PLAN.md`.

## Building and running

1. Open `Rimwatch.xcodeproj` in Xcode.
2. To run on a device, choose your team under the Rimwatch target's Signing & Capabilities.
3. Pick a run destination and press Run.

To play on an iPhone that does not fold, add the launch argument `-hinge open` to the scheme's Run
action. The game then plays letterboxed to the Duo's shape. This works in Debug builds only.

## Tests

The game logic is a plain Swift package and its tests run with Xcode closed:

```sh
cd GameCore
swift test
```

The tests use Swift Testing. If `import Testing` fails, the Command Line Tools are selected instead
of Xcode. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, or switch
`xcode-select` to Xcode.

Difficulty was tuned against scripted bots, not people. After changing `Tuning.swift` or
`WaveDirector.swift`, re-run the bot harness as well as the tests:

```sh
cd Tools/Harness
swift build -c release -Xswiftc -DDEBUG
.build/release/Harness 80 20 idle novice competent shooter
```

The arguments are the number of seeds, a cap in minutes per game, and the bots to run.

## App icon

The icon is generated, not drawn by hand. After changing the ship or colonist shapes or the
palette in the theme, regenerate it from the repository root:

```sh
swift run --package-path Tools/Icon Icon Rimwatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Project layout

| Path | What it holds |
|---|---|
| `GameCore/` | The game logic as a Swift package, with no UIKit or SpriteKit: world, simulation, enemies, waves, scoring, menus, sound rendering and the tests. It knows what each entity does, never how it looks; appearance and sound come from a `Theme`. |
| `Rimwatch/` | The app: SpriteKit scene and rendering, touch and gamepad input, fold handling, audio playback, haptics and the menu screens. |
| `Tools/Harness/` | The bot harness used for difficulty tuning. |
| `Tools/Icon/` | The script that draws the app icon from the theme's ship and colonist shapes. |
| `PLAN.md` | The design, the build history and what is left. |
| `CLAUDE.md` | Working notes for building the project with Claude Code. |

Gameplay numbers live in `GameCore/Sources/GameCore/Tuning.swift`.

## Debug launch arguments

These exist in Debug builds only.

| Argument | Effect |
|---|---|
| `-hinge open\|closed\|none` | Overrides the fold state. |
| `-autopilot` | A bot plays the game. `-autopilot shooter` uses one that never rescues. |
| `-showStats` | Shows node count, draw count and frame rate. |
| `-resetSettings` | Clears saved options and high scores at launch. |
| `-logFeedback` | Logs every routed sound and haptic. |
| `-realPads` | Uses real controllers in the simulator, which otherwise reports a phantom one. |
| `-dumpAudio <dir>` | Writes every sound and music mood to WAV files. |

`PLAN.md` also lists the Darwin notifications that change the fold state and drive the menus and a
simulated controller at run time.
