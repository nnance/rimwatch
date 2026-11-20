# Rimwatch: an original rescue shooter for the iPhone Duo inner screen

## Context

You want a game with the feel of the classic side-scrolling rescue shooter, built as a native iOS app
for the iPhone Duo's inner (unfolded) display, with gamepad and touch controls. The first theme is an
alien frontier; a deep-sea theme is a later expansion. The project folder is empty, so this is a new
build.

Rimwatch is an original game: its own name, ship, enemies, sounds and HUD. It borrows genre mechanics
(wraparound world, scanner, protect-and-rescue loop, momentum flight) but does not copy the original's
sprites, sounds, names or screen layout.

## Decisions I made (say so if you disagree)

- **Look: neon vector glow, not a match of the original's art.** You asked to match the original look
  as closely as possible; I won't copy it, so I took your fallback and picked from my options. Thin
  glowing lines on true black suit a 430 ppi OLED at 120 Hz and stay sharp at any size. The *feel*
  (speed, inertia, particle bursts, scanner) stays in the classic arcade spirit.
- **Engine: SpriteKit + Swift**, no third-party dependencies. All art drawn in code, all sound
  synthesised with AVAudioEngine, so there are no asset files.
- **Minimum iOS 27.1**, iPhone only. The Duo ships with it, so no availability checks are needed.
- **Build through Xcode's MCP server** (your suggestion), in place of XcodeGen and scripted
  `xcodebuild`. Game logic still lives in a plain Swift package so it can be tested from the
  terminal with Xcode closed.

## Progress

Tick each item when it is built and verified. Continue from the first unticked one.

- [x] Step 0: plan saved here, `CLAUDE.md` written, folder renamed to `rimwatch` (2026-11-16)
- [x] Prerequisites (2026-11-16): macOS 26.6.2, Xcode 27.2, `xcode-select` on Xcode, the `xcode`
      MCP server connected. The Duo simulator needs its own runtime: the ordinary iOS 27.2 runtime
      (24B8117) refuses the Duo, and build 24B91016s (installed with
      `xcodebuild -downloadPlatform iOS -buildVersion 24B91016s`) is restricted to it. Device
      "iPhone Duo", UDID 523C696B-F865-4583-88F2-7EE9DDA6A72E. Xcode 27 has no Simulator.app;
      simulators show in DeviceHub.app.
- [x] 1. `GameCore` package: world, player flight, projectiles, collisions, Harvester/colonist
      loop, session states, tests passing with `swift test` (2026-11-16)
- [x] 2. Xcode project and app shell: scene, glow renderer, terrain, camera, touch, plus
      `Theme.swift` and `Themes/AlienFrontier.swift` in `GameCore` (2026-11-16). One target,
      `Rimwatch` (iPhone only, Swift 6, iOS 27.1, synchronized folder `Rimwatch/`), linking
      `GameCore` as a local package. Independently verified on the iPhone 18 Pro simulator: clean
      build, real multi-touch input, a full lap of the world across the seam, game over and
      restart, no node leak over 3 minutes. Not verified: the Duo's inner display (nobody has found
      a way to unfold the Duo simulator from the command line; it boots closed and the game lays
      out correctly on the outer display), 120 Hz pacing (the simulator caps at 60), and the Lancer
      telegraph, outpost ruin and Husk-forming burst on screen. DEBUG launch arguments:
      `-autopilot` (scripted input) and `-showStats`.
- [x] 3. Fold gate and pause menu on both displays, options, orientation switching (2026-11-16).
      Also a minimal title screen, game-over screen, pause button, persisted options and a top-10
      high-score table. The menu model, options, high scores and screen-choice logic (`FrontEnd`)
      live in `GameCore` with tests. Hinge API confirmed in the iOS 27.2 SDK: `UIHingeInteraction`
      (status unknown / closed / partiallyOpen / fullyOpen, plus angle) and
      `UIView.reservedRegions(kind:options:)` with kinds `.occlusion` and `.division`. No API says
      which display the app is on. Independently verified by real touch on the iPhone 18 Pro
      simulator (with the debug hinge override) and on the Duo simulator's outer display (real
      hinge API reports closed). DEBUG hooks: `-hinge open|closed|none`, `-resetSettings`, Darwin
      notifications `com.rimwatch.debug.hinge.{open,closed,none}` and
      `com.rimwatch.debug.menu.{up,down,left,right,activate,back,pause}` (post with
      `xcrun simctl spawn <udid> notifyutil -p <name>`). Not verified: anything on the Duo's open
      inner display (crease regions, inner layout, partial open). `UIRequiresFullScreen` is
      deprecated since iOS 26 and builds with a warning.
- [x] 4. Remaining enemies, wave director, Shockwave, Blink, Blackout, scoring and lives
  - [x] 4a. Game logic in `GameCore`, done ahead of order because it needs no Xcode: Sower and
        mines, Brood and Motes, Lancer, Anchor and outpost destruction, Shockwave, Blink, shield,
        Blackout and supply drops, extra lives, wave bonus, wave makeup (2026-11-16)
  - [x] 4b. On-screen feedback for every `GameEvent` and every piece of entity state (banners,
        notices with off-screen pointers, stacked popups, tow lines, tethers, beams), button
        states on the touch controls, and sound and haptic routing (2026-11-16). Every event maps
        to a theme sound patch and a `HapticCue`; `Rimwatch/Feedback/FeedbackRouter.swift` has the
        `SoundOutput` and `HapticOutput` protocols with silent players for steps 6 and 7 to
        replace. `GameCore` gained `GameEvent.shieldCharged` and `Simulation.colonistsSaved`.
- [x] 5. Scanner, HUD, title and game-over screens, high scores (2026-11-16). The scanner is
      centred on the camera and sits left of the crease, with the HUD right of it; they stack in
      portrait. `ScannerProjection`, `HUDReadout` and the high-score table logic live in
      `GameCore` with tests. Steps 4b and 5 were independently verified together on the iPhone 18
      Pro simulator (`-hinge open` letterbox) and the Duo simulator's outer display, by real touch
      and autopilot. Later waves were reached only in the verifier's modified copy of the game,
      because autopilot does not survive past wave 3. Known cosmetic leftovers: popups can sit
      under the touch-control rings at the bottom corners, and the ship can pass over the lowest
      popup line. DEBUG extras: `-logFeedback` logs routed sounds and haptics.
- [x] 6. Gamepad input (gameplay and menus), haptics (2026-11-16). The pad logic (`PadSnapshot`,
      `PadMapping`, `PadReader`, `MenuDirectionTracker`, `MenuCommand`) is in `GameCore` with
      tests; `Rimwatch/Input/GamepadInput.swift` is a thin `GCController` adapter. The touch stick
      and buttons hide while a controller is connected, and a disconnect mid-game pauses. Menus
      ignore activation for 0.35 s after they appear (1.2 s on game over), and a button held when
      play starts is ignored until released. A pause menu with Resume disabled selects Options by
      default. `Rimwatch/Feedback/Haptics.swift` plays one Core Haptics pattern per `HapticCue`,
      on the controller if it has haptics, otherwise on the phone. Independently verified with a
      DEBUG simulated controller (Darwin notifications `com.rimwatch.debug.pad.*`, listed in
      `Rimwatch/Input/DebugPadCommands.swift`) and by real touch. The iOS simulator reports a
      phantom "Gamepad" controller with nothing attached, so DEBUG simulator builds ignore real
      controllers unless launched with `-realPads`. Not verified: real controller hardware and
      real haptics (Core Haptics does not run in the simulator). The diagonal menu chatter found
      here was fixed in step 7.
- [x] 7. Synthesised audio, particle polish, difficulty tuning (2026-11-16).
      - Audio: every sound is a `SoundPatch` in the theme (`Themes/AlienFrontierSounds.swift`),
        rendered by the pure-Swift `SoundRenderer` in `GameCore`; `Rimwatch/Audio/Synth.swift`
        plays pre-rendered buffers through AVAudioEngine (12 gameplay voices, 2 menu voices, rate
        limiting, `.ambient` session). `AmbientMusic` is a generative bed with title, calm,
        tension and blackout moods chosen by `MusicMoodDirector`. Checked by measurement only:
        DEBUG `-dumpAudio` writes every patch and mood to WAV.
      - Visuals: a fixed pool of 480 particles, engine plume, a death effect per enemy kind,
        parallax stars and a far ridge, screen shake (off under Reduce Motion), a catch beam. The
        next run's terrain is drawn in the background and text is warmed on the title, so a run
        starts without a hitch.
      - Tuning: done with scripted bots (`GameCore/Autopilot.swift`, DEBUG only; idle, novice,
        competent, shooter) and the harness described below. `DifficultyTests` pin the results
        coarsely. DEBUG `-autopilot` uses the competent bot and `-autopilot shooter` the one that
        never rescues, which reaches Blackout.
      - Independently verified on the iPhone 18 Pro simulator and the Duo simulator's outer
        display. Not verified: sound through a real speaker, play feel, catching by hand, real
        controllers and haptics, 120 Hz, and the Duo's open inner display.

State of `GameCore` on 2026-11-16: 201 tests pass (about 11 s). The numbers in `Tuning.swift` and
`WaveDirector.swift` were tuned against bots, not people. Measured over 80 seeds per bot: an idle
ship first dies at about 39 s; the novice bot reaches wave 4 and keeps 3 colonists to wave 6; the
competent bot reaches wave 10 and loses 2 colonists by wave 5; the shooter bot hits Blackout in
about 46% of games, first around wave 8, and usually recovers. Holding Fire overheats the lance
after about 6.7 s with a 1.2 s lockout. A colonist dropped in the first 3.3 s of a 15 s lift
survives the fall uncaught (`safeFallHeight` 100); after that it must be caught (`catchRadius`
40). Each enemy kind debuts on its own, in waves 2, 3, 5, 7 and 9. The competent bot dodges
shots almost perfectly, so its numbers are optimistic for a person. Two details differ from the
design text below: the shield starts empty (two deliveries fill it), and a supply drop comes on a
25-second timer when there are no colonists or no outposts left, not as something the player
collects.

The tuning harness is in `Tools/Harness`: a small executable that depends on the `GameCore`
package and runs each bot over many seeds. The bots only exist in DEBUG builds, so run it with
`swift build -c release -Xswiftc -DDEBUG && .build/release/Harness 80 20 idle novice competent
shooter` (seeds, minutes cap, bots). Environment variables such as `SAFE`, `CATCH` and `FROM`
override single tuning values for a sweep; see the top of its `main.swift`.

Changes after the first play on a real phone (2026-11-20): the app icon was added (generated by
`Tools/Icon`); a side-view jet was tried for the ship and rejected, and the ship is now the
Pincer, a forked top-down gunship the owner chose from five candidates, with the HUD life icons
drawn from the theme's simplified `icon(for:)`; the kill sounds `enemy.explode`,
`brood.burst` and `anchor.explode` became explosions built on a new `crackle` waveform, with
their energy above 300 Hz. 204 tests pass. Sound was confirmed working on the phone; it is silent
in Silent mode by design.

## What is left

Everything in the build order is done. What remains needs a person and a device:

1. Run on a real iPhone Duo (set the signing team in Xcode). Nothing has been seen on the open
   inner display: check the layout, the crease band, the camera hole, partial-open poses and
   120 Hz pacing. The crease code uses `.division` reserved regions when the system reports
   them and otherwise keeps a central band of 5% of the width clear.
2. Play-test the feel: flight inertia, shot rhythm, thumb reach, whether colonists can be caught
   by hand in waves 1 to 5, whether wave 2 is too steep for a first game, whether Blackout and
   its recovery are clear.
3. Listen on the phone speaker: overall mix, music level, whether the Shockwave and ship-death
   sounds are prominent enough.
4. Try a real controller (input, Menu button, controller haptics) and feel the phone haptics.
5. Later expansion: the deep-sea theme, as one new `Theme` file.

## Prerequisites (yours; I can't do these)

This Mac can't build for the Duo yet: it has Xcode 26.6 (iOS 26.5 SDK, no simulator runtimes) on
macOS 26.2, and `xcode-select` points at the Command Line Tools.

1. Update macOS to 26.6 or later (required by Xcode 27.1).
2. Install Xcode 27.1 or later and the iOS 27.1 simulator runtime (includes the iPhone Duo simulator).
3. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
4. Xcode > Settings > Intelligence > Model Context Protocol: set "Allow External Agents to Use
   Xcode Tools" to "While Xcode is Open" (or Always).
5. `claude mcp add --transport stdio xcode -- xcrun mcpbridge`, then check with `claude mcp list`.
6. Keep the Rimwatch project open in Xcode while I work.

Build step 1 (the game core) needs none of this and can start as soon as the new session opens.

## Target device facts

- Inner display: 7.6 in, 1878 x 2670 px, 430 ppi, 120 Hz. Opened, it is landscape (about 890 x 626 pt
  at 3x; Apple publishes no point size, so read it at runtime) with the crease running vertically
  down the centre. The crease has zero width when fully open.
- Outer display: 5.4 in, 1398 x 2034 px (about 466 x 678 pt), used in portrait.
- **There is no documented way to restrict an app to the inner display**, so the game enforces
  "inner screen only" itself (next section).
- The Duo API names (`UIHingeInteraction`, `UIView.reservedRegions(kind:)`) come from third-party
  write-ups. I'll confirm them against the installed SDK through the Xcode tools before coding.

## Fold behaviour

| Hinge status | What the game does |
|---|---|
| Fully or partially open | Gameplay runs, landscape, on the inner display. |
| Closed (outer display) | Gameplay pauses at once. The outer display shows the pause menu, in portrait. |
| No hinge (non-folding iPhone) | "Made for iPhone Duo" screen; DEBUG-only override letterboxes to the Duo aspect for testing. |

**Closed-screen pause menu** (touch and gamepad both work):

- **Resume** is shown but disabled, labelled "Open to resume".
- **Start over**: resets to wave 1 and stays paused until the phone is opened.
- **End game**: records the score and returns to the title screen.
- **Options**: sound and music volume, haptics on/off, touch-control handedness, gamepad button layout.
- **High scores**.

The title screen, options and high scores are also usable while closed; only "Play" waits for the
phone to be open. Reopening mid-game does not drop you straight into the action: the same menu
appears on the inner display with Resume enabled, followed by a short countdown.

Implementation notes: `UIRequiresFullScreen = YES` so the app gets a discrete resize on each pose
change; supported orientations switch between landscape (open) and portrait (closed) via
`setNeedsUpdateOfSupportedInterfaceOrientations()`. Backgrounding the app pauses the same way.

## Game design

- **World:** a wraparound planet strip about 8 screens wide, with a scanner minimap across the top
  showing the whole world.
- **Loop:** colonists live in domed outposts. Harvesters descend, grab one and lift it. Shoot the
  Harvester, catch the falling colonist and return them to an outpost. A completed abduction turns
  the pair into a Husk, a fast hunter.
- **Enemies (original designs):** Harvester (abductor), Husk (hunter), Sower (drifts, lays tethered
  mines), Brood (splits into Motes when shot), Lancer (telegraphed charge across the screen),
  Anchor (lands and drills an outpost until destroyed).
- **Player kit:** pulse lance with a heat meter, Shockwave (limited charges, clears the screen),
  Blink (short dash on a cooldown).
- **Own twists:** carrying several colonists builds a score multiplier; returning them recharges
  your shield; losing every colonist triggers Blackout (terrain goes dark, scanner off, Husks swarm)
  until a supply drop restores an outpost.
- **Structure:** escalating waves, three lives, local high-score table.

## Controls

- **Touch:** floating stick under the left thumb (ship faces the direction of travel); Fire (hold to
  autofire), Shockwave and Blink under the right thumb. Both clusters sit in the lower corners, clear
  of the crease and the reserved regions.
- **Gamepad** (GameController framework): left stick or D-pad to fly, A fire, B Blink, X Shockwave,
  Menu pause. The touch overlay hides while a controller is connected.
- Haptics through Core Haptics on the phone and on supported controllers.

## Architecture

```
rimwatch/
  Rimwatch.xcodeproj            created via the Xcode tools if they support it, otherwise by you
                                from the iOS Game (SpriteKit) template; bundle name Rimwatch
  GameCore/                     Swift package, no UIKit/SpriteKit: builds and tests on macOS
    Sources/GameCore/
      World.swift               wraparound maths, terrain heightmap, outposts
      Simulation.swift          fixed 120 Hz step; owns all entities; emits events
      Entities/                 Player, Colonist, enemy state machines, projectiles
      WaveDirector.swift        wave composition and difficulty curve
      Collision.swift           wrap-aware broad and narrow phase
      Input.swift               device-neutral InputState
      GameSession.swift         playing / paused / game over; start over; end game
      Theme.swift               Theme protocol: palette, shape per entity role, terrain style,
                                sound patches, display names
      Themes/AlienFrontier.swift
    Tests/GameCoreTests/
  Rimwatch/                     app target
    AppDelegate.swift, SceneDelegate.swift, Info.plist
    FoldGate.swift              hinge status -> open / closed / no hinge; drives pause + orientation
    GameScene.swift             SpriteKit scene: steps Simulation, syncs nodes
    Render/                     GlowShapeFactory (shapes pre-rendered to additive textures),
                                TerrainNode, ScannerNode, HUDNode, particle bursts
    Input/TouchControls.swift, GamepadInput.swift
    Audio/Synth.swift           AVAudioEngine voices driven by simulation events
    Screens/                    title, pause menu (inner and outer layouts), options, game over,
                                high scores
    Settings.swift              options persisted in UserDefaults
  PLAN.md                       this plan plus a progress checklist, kept current as work lands
  CLAUDE.md                     loaded automatically each session: points at PLAN.md, and notes
                                to build via the Xcode MCP tools and test GameCore with `swift test`
```

The simulation knows entity *roles*, never their appearance. The deep-sea expansion is then one new
`Theme` file (palette, shapes, terrain style, sounds, names) with no gameplay changes.

## Build order

1. `GameCore`: world, player flight, projectiles, collisions, Harvester/colonist loop, session
   states, with tests. No Xcode needed.
2. Xcode project and app shell on the Duo simulator: scene, glow renderer, terrain, camera, touch.
3. Fold gate and pause menu on both displays, options, orientation switching.
4. Remaining enemies, wave director, Shockwave, Blink, Blackout, scoring and lives.
5. Scanner, HUD, title and game-over screens, high scores.
6. Gamepad input (gameplay and menus), haptics.
7. Synthesised audio, particle polish, difficulty tuning.

## Verification

- `swift test` in `GameCore/` on macOS: wraparound distance and collision across the seam, abduction
  to Husk transition, catch and return scoring, heat and cooldown timers, wave progression, Blackout
  entry and exit, pause / start over / end game transitions, and a seeded simulation that runs
  10 minutes of scripted input without crashing.
- Build and run on the iPhone Duo simulator through the Xcode MCP tools, capturing a screenshot in
  each pose:
  - fully open: gameplay runs;
  - partially folded: controls sit clear of the crease;
  - closed mid-game: paused, portrait menu on the outer display, Resume disabled, and Start over,
    End game and Options each work;
  - reopened: menu on the inner display, Resume then countdown.
  Also a non-folding iPhone simulator (made-for-Duo screen).
- Frame pacing checked at 120 Hz in the simulator with the SpriteKit debug overlay.
- Not verifiable without hardware: real thumb reach, haptics, physical controller pairing and true
  120 Hz performance. Those need a run on an actual Duo, which also needs your signing team set in
  Xcode.
