# Rimwatch: rescue games in one world, for the iPhone Duo inner screen

## Context

You want a game with the feel of the classic side-scrolling rescue shooter, built as a native iOS app
for the iPhone Duo's inner (unfolded) display, with gamepad and touch controls. The first theme is an
alien frontier; a deep-sea theme is a later expansion. The project folder is empty, so this is a new
build.

Rimwatch is an original game: its own name, ship, enemies, sounds and HUD. It borrows genre mechanics
(wraparound world, scanner, protect-and-rescue loop, momentum flight) but does not copy the original's
sprites, sounds, names or screen layout.

On 2026-11-20, after playing the finished game on a phone, you decided to grow it into three modes
set in one world, with a campaign later. That plan is in "Expansion" below. The game built so far
becomes the first mode, Ridgeline. The sections from "Game design" to "Verification" describe it and
were written while it was the whole game.

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

## Expansion: three modes and a campaign (decided 2026-11-20)

Rimwatch grows from one game into three modes that share a world, and later a campaign. Progress
on it is in the "Expansion" list under "Progress".

### What was decided

- **The whole game stays Rimwatch.** The bundle ID, Xcode project, repository and icon keep their
  names. In the story, Rimwatch is the force you serve in.
- **The world is Calder**, a colony built inside a vast crater. The crater wall is the Rim. The
  setting is Outpost Calder, which can sit under the title as a subtitle.
- **Three modes, one per place:**

  | Mode | Where | What you do | Kind of game |
  |---|---|---|---|
  | Ridgeline | The sky over the crater | Fly the patrol ship and catch colonists the Harvesters lift away | Side-scrolling rescue shooter. This is the game built in steps 1 to 7. |
  | Redoubt | Inside a breached dome | Hold the floor and get colonists to the airlock | Twin-stick arena shooter |
  | Riftwing | The caves and tunnels of the crater wall | Fight Husks wing to wing on a flap-wing rig, in spaces too small for a ship | Flap-to-fly combat where the higher fighter wins a clash |

- **Every mode is about saving colonists**, and the modes share one cast where it fits. In
  Riftwing, a Husk struck from above drops a pod holding the colonist it was made from. Reach the
  pod in time to free them; leave it and it hatches into a tougher Husk.
- **Each new mode is an original game in its genre**, as Ridgeline is. You named Robotron as the
  inspiration for Redoubt and Joust for Riftwing. The modes take the genre mechanics and nothing
  else: their names, characters, art, sounds and layouts are their own.
- **Free Play first.** Each mode is built as an endless score game with its own top-10 table. The
  existing high scores become Ridgeline's table.
- **You play and refine each mode before the next one starts.** The progress list has a gate after
  each mode.
- **The campaign is not designed yet.** It gets its own design and planning step with you before
  anything is built (step 16). One idea so far is three acts (sky, dome, caves) with the colony's
  population carrying from chapter to chapter. You may not want it built on acts, so that is an
  idea, not a decision. One allowance is made before then: a mode's session can end because a goal
  was met, not only because the player died, so a campaign can use the modes without reworking
  them. Nothing else is built for the campaign ahead of its design step.
- **An idea for the campaign, not a decision (yours, 2026-11-20):** an overworld in the spirit of
  a platformer's world map. The player moves around Calder and enters portals, each leading to
  a mini game they complete, with 15 to 20 classic-arcade-style games in all and the surprise of
  not knowing which game is behind a portal. It should follow the world's theme so it does not
  feel like a rigid set of separate scenes. This is input for step 16. It does not change the
  build order, and nothing is built for it before then.
- **A second idea for the campaign, also not a decision (yours, 2026-11-20):** the player is an
  aspiring spacecraft pilot, and every game in the campaign develops their flying skill while
  they protect civilians. All the games are about flying, and the reward that drives the player
  is earning pilot wings or pilot levels. Input for step 16. The one part acted on now is that
  Redoubt's player is a hover orb, so the three big modes are all flight.
- **Pilot skills, game by game (2026-11-20).** The first three rows are the big modes, which
  are in the build order. The six after them are the portal games you picked as first
  candidates: each would be a small original game on one classic mechanic. Those six are input
  for step 16, not part of the build order, and none is designed yet. Together the table shows
  how every game trains a different part of flying:

  | Game | Pilot skill | Classic mechanic it builds on |
  |---|---|---|
  | Ridgeline (built) | Patrol and recovery: fast momentum flight, and catching someone in mid-air | Side-scrolling rescue shooter over a wraparound world (Defender) |
  | Redoubt (planned) | Close-quarters flying: steering and aiming independently in a crowded room | Twin-stick arena shooter (Robotron) |
  | Riftwing (planned) | Altitude and energy: holding height over an opponent in tight spaces | Flap-to-fly combat where the higher fighter wins (Joust) |
  | Lander | Landing | Thrust-and-gravity landing on small pads with limited fuel, to pick up colonists (Lunar Lander) |
  | Tether tow | Towing under gravity | Fly into a cave, hook a stranded pod and haul it out without touching the walls (Gravitar, Thrust) |
  | The rim | Perimeter defence | Fly around the lip of a shaft, firing down at what climbs it (Tempest) |
  | Rescue lift | Search and rescue | Land near stranded colonists under fire, load them and fly them home (Choplifter) |
  | Dogfight | Dogfighting | A free-roaming fight in every direction against circling attackers (Time Pilot, Bosconian) |
  | Meteor field | Inertial flying | Clear a meteor storm drifting over the outpost with rotate-and-thrust controls (Asteroids) |

  Other candidates discussed: a canyon supply run (Scramble), a rift speed run (River Raid), a
  debris-belt descent (Lunar Rescue), mining under threat (Sinistar), holding the dome gate
  (Galaga), a convoy escort (Xevious), meteor interception (Missile Command), a tunnel maze
  (Pac-Man, Rally-X), a hover skimmer (Moon Patrol) and a cave defence (Centipede).

### What is shared and what belongs to a mode

| | Shared by every mode | Owned by each mode |
|---|---|---|
| Game logic (the Swift package) | Maths and random numbers, the shape and theme types, the sound renderer, the menu model, options, high-score tables, pause and countdown session logic, gamepad mapping | World, entities, waves, tuning numbers, bots, theme content (shapes, sounds, names) |
| App | Fold handling, touch and gamepad input, audio playback, haptics, menu screens, the glow renderer, particles | The SpriteKit scene and the HUD |

These lines were written from memory of the code before step 8. What step 8 found:

- Shared now (`GameCore` target): maths and random numbers, sweep collision maths, colour and
  shape types, the menu model, options, high-score tables, the gamepad reader and menu
  navigation, haptic cue names, the sound patch types and renderer, and the music synthesis.
- Shared since step 9a: the pause, countdown and screen-flow logic (`ModeSession`,
  `ModeFrontEnd` in `GameCore/Session/`, written against the `ModeRun` protocol that a mode's
  simulation conforms to) and saved settings with one high-score table per mode
  (`SavedSettings`). `RidgelineCore` keeps the names `GameSession` and `FrontEnd` as typealiases.
- Owned by each mode: its theme protocol and palette (`Theme` for Ridgeline, `RedoubtTheme` for
  Redoubt) and the mapping from gamepad buttons to actions. Each target builds the shell's
  colours (`ShellStyle`) from its palette with near-identical code, a candidate to share.
- Found in step 13b: Redoubt needed no change to the shell or the shared target. Ridgeline's
  particle and callout layers are built round its wraparound camera, so Redoubt has its own
  simpler ones rather than sharing them. Loading a mode with different sounds into the one
  synthesiser, never exercised before, works: sounds start again after each return to Ridgeline.
- Known Ridgeline-shaped parts of the shared session code, to settle while building Redoubt:
  the run result is fixed at score, wave and colonists saved; the pause and game-over menu
  lines are written in the shared front end (the heading says "Game over" even for a goal-met
  ending). Options are stored once and each mode lists the rows it shows.
- Some shared types still carry Ridgeline wording (a `blackout` music mood, `wave` and `saved`
  on a high-score entry, option names that mention Blink and Shockwave). They get tidied when
  the second mode shows what the general form should be.

The mode contract stays thin at first, and I expect to revise it while building Redoubt, since a shared
layer shaped around one game guesses wrong about what the second needs.

Rules that carry over to every mode:

- Gameplay only runs on the open inner display, and the fold behaviour below applies unchanged.
- Game logic has no UIKit or SpriteKit and knows roles, never appearance.
- No asset files: art is drawn in code and sound is synthesised.
- Each mode has its own tuning file, its own bots and a harness run that pins its difficulty.

### Build order

Each step is built, independently verified and committed before the next one starts.

8. **Split the shared game logic out of Ridgeline** inside the Swift package: one shared target and
   one target for Ridgeline. Nothing may behave differently: every test passes and the harness
   gives the same results for the same seeds.
9. **Split the app the same way**: a shared shell, with Ridgeline's scene and HUD plugged into it
   as a mode. High scores become one table per mode, and the existing table moves to Ridgeline.
   Nothing the player sees or does may change. It is built in three stages, each verified and
   committed on its own:
   - **9a, game logic.** The pause, countdown and screen-flow logic (`GameSession`, `FrontEnd`)
     becomes generic over a mode's run and moves to the shared target. A run can end because a
     goal was met as well as by defeat. High scores are stored per mode, and the old table is
     migrated to Ridgeline's.
   - **9b, shared app files.** Menus, overlays, audio playback, feedback routing and the glow
     renderer stop depending on Ridgeline's theme (they take a small shell style instead), and
     the app's folders become `Shell/` and `Modes/Ridgeline/`.
   - **9c, the scene.** `GameScene.swift` is split into a shell scene, a host that runs one mode,
     and the Ridgeline mode. One registry file lists the modes and is the only shell-level file
     that names Ridgeline.

   A safety net came first, on otherwise unchanged code: `FrontEndReplayTests` replays a scripted
   20,000-frame session and pins every event, screen and score, and the DEBUG arguments
   `-seed <n>` and `-fixedFrame` (with `-autopilot idle|novice|competent|shooter` and
   `-logFeedback`) make two runs of the app log identical `[Rimwatch run]`, `[Rimwatch screen]`
   and haptic lines, so each stage can be compared with the one before.
10. **Title screen with Free Play.** Rimwatch is the title and the player picks a mode; only
    Ridgeline is listed until the others exist. The pause menu gains a way back to the title. A
    DEBUG launch argument starts a given mode directly. `README.md` and `CLAUDE.md` are updated to
    the new names here. The app icon is redesigned in this step as an emblem for the whole game
    instead of Ridgeline's ship, and the title screen uses the same emblem. You chose "The Rim"
    from five candidates on 2026-11-20: the crater's rim seen from above as a rough ring, with the
    arrowhead ship crossing it. Its geometry, in a 100 x 100 icon space with y down, on black:
    - Outer ring, orange `0xFF7A3D`, line width 2.8: a closed 20-point polygon centred at
      (50, 50); point i is at angle 2*pi*i/20 with radius 36 + J[i mod 16], where
      J = [0, 2.2, -1.2, 1.6, -2.0, 0.8, 2.6, -1.6, 0.4, 1.8, -2.4, 1.0, -0.6, 2.0, -1.8, 0.6].
    - Inner ring, darker orange `0xC2552B`, line width 1.5: a closed 18-point polygon, angle
      2*pi*i/18 + 0.3, radius 27 + 0.5 * J[i mod 16].
    - The ship: the theme's arrowhead hull outline only, cyan `0x3FF6FF`, line width 2.4, centred
      at (50, 50), scale 19, nose turned 28 degrees up from pointing right.
    - Four faint stars near the corners. Lines are drawn as neon (halos, line, pale core) like the
      current icon.
    - Check, in parallel: you confirm on your phone that Ridgeline plays as it did before. This
      does not hold up the next step; a difference you find is fixed before other work.
11. **Twin-stick input in the shared shell**: a second floating stick for aiming on touch, and the
    right stick and shoulder buttons on a gamepad.
12. **Redoubt design.** Written under "Redoubt design" at the end of this plan and approved on
    2026-11-20.
13. **Redoubt build**, in the same order Ridgeline was built: game logic with tests and bots,
    rendering, sound and haptics, waves and tuning, polish.
    - Gate: you play Redoubt and we refine it until you are happy to move on.
14. **Riftwing design**, written into this plan for you to approve. No code before that.
15. **Riftwing build**, in the same order.
    - Gate: you play Riftwing and we refine it until you are happy to move on.
16. **Campaign design and planning** with you: what the campaign is, how it is structured (acts or
    something else), what carries between sessions, how the story is told. The result is written
    into this plan as its own build steps. Nothing is built before you approve it.
17. **Campaign build**, following the steps written in 16.

## Progress

Tick each item when it is built and verified. Continue from the first unticked one. Steps 0 to 7
built Ridgeline (then the whole game) and are done; the unticked items are in the expansion list
at the end of this section.

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
`Tools/Icon`); a side-view jet and then the Pincer, a forked top-down gunship, were both
tried for the ship and rejected, so the ship is back to the original arrowhead, with the HUD
life icons drawn from its full shape as before; the kill sounds `enemy.explode`,
`brood.burst` and `anchor.explode` became explosions built on a new `crackle` waveform, with
their energy above 300 Hz. 204 tests pass. Sound was confirmed working on the phone; it is silent
in Silent mode by design.

### Expansion

The steps are described under "Build order" in "Expansion" above. A gate is yours to tick: do not
start the step after a gate until you have said to move on. Your checks on the phone that nothing
changed are different: they run in parallel and block nothing (decided 2026-11-20). Each verified
step is pushed so you can install it.

- [x] Expansion planned and the names chosen: Rimwatch (the whole game), Calder (the world),
      Ridgeline, Redoubt, Riftwing (2026-11-20)
- [x] 8. Split the shared game logic out of Ridgeline in the Swift package (2026-11-20). The
      package now has two targets, `GameCore` (shared) and `RidgelineCore`, in one library product
      named `GameCore`, so the Xcode project file did not change. The app and the tools gained
      `import RidgelineCore` lines and nothing else. 204 tests pass: 36 in `GameCoreTests`, 168 in
      `RidgelineCoreTests`, with the same names and bodies as before. The harness gives the same
      results as before for the same seeds, and the app's 44 rendered sounds are byte-identical.
      Small maths helpers are `@inlinable`; the builder measured no change in harness speed and
      the verifier about 3% slower, which does not matter at the game's 120 Hz step. The
      harness's "death causes" lines print ties in an unstable order, as they did before the
      split. What landed where is under "What is shared and what belongs to a mode".
- [x] 9. Split the app into a shared shell and the Ridgeline mode; one high-score table per mode
  - [x] Safety net: golden replay test and the DEBUG `-seed`, `-fixedFrame` and
        `-autopilot <skill>` arguments (2026-11-20). 205 tests.
  - [x] 9a. Session and screen-flow logic shared; per-mode high scores with migration
        (2026-11-20). `ModeRun`, `ModeSession` and `ModeFrontEnd` are in the shared target; a run
        can end by goal as well as by defeat. The old high-score table moves to Ridgeline's key
        (`rimwatch.highScores.ridgeline.v1`) on first launch, byte for byte, and options are
        untouched. The golden replay passes unchanged and the app's logs match the baseline line
        for line. 231 tests: 56 in `GameCoreTests`, 175 in `RidgelineCoreTests`. The generic
        session code is `@inlinable`; without that the session pipeline ran about 25% slower.
  - [x] 9b. Shared app files cut free of Ridgeline; folders reorganised (2026-11-20). Menus,
        overlays and feedback routing take a `ShellStyle`, the synth takes plain sounds and
        music, and Ridgeline's role glyphs are in `RidgelineGlyphs`.
  - [x] 9c. `GameScene` split into `ShellScene`, `ModeHost<Mode>` and `RidgelineMode`
        (+Backdrop, +Events, +Sync); `ModeRegistry` is the only shell-level file that names
        Ridgeline (2026-11-20). 9b and 9c were independently verified together against the 9a
        build: the run, screen and haptic logs match line for line, the 44 rendered sounds are
        byte-identical and every screen looks the same. The node count is one higher (the
        mode's root node).
- [x] 10. Title screen with Free Play mode selection; new app icon and emblem ("The Rim")
      (2026-11-21). The title shows the emblem, "Rimwatch", "Outpost Calder" and one item per
      registered mode (Ridgeline only), each with a one-line summary and its best score.
      Choosing a mode that is not loaded switches modes at run time: `ShellScene` swaps
      `ModeHost`s, while the synth, gamepad and haptics live in `ShellDevices` and survive the
      switch. High scores are shown per mode, with a mode selector when there are several. The
      last mode played is remembered (`rimwatch.lastMode.v1`). DEBUG `-mode <id>` loads a mode
      at launch and `-debugSecondMode` lists Ridgeline again as "Ridgeline B" to exercise
      switching. The emblem's geometry is `Emblem` in `GameCore`; the icon generator, the title
      and Ridgeline's ship hull all draw from it. The old title tagline "Hold the rim. Bring
      them home." gave way to the subtitle. Switching modes takes a hitch of about 0.2 s while
      the new mode is built.
- [ ] Parallel check (not a gate): Ridgeline checked on the phone and unchanged
- [x] 11. Twin-stick input (touch and gamepad) (2026-11-21). The gamepad reads the right stick,
      both shoulders and both triggers (`PadSnapshot.rightStick`, new `PadButton`s,
      `PadReader.rightStick`). The floating touch stick is shared: `TouchStick` in `GameCore`
      holds the logic and `FloatingStick` in `Shell/Input` draws it; Ridgeline's `TouchControls`
      uses it, and a mode can place two. Each mode lists the Options rows it shows
      (`ModeDescriptor.optionRows`), so a mode without a gamepad layout does not show that row.
      Ridgeline's action buttons were not extracted, being tied to its gauges. DEBUG
      notifications `com.rimwatch.debug.pad.rstick.*` and
      `pad.{lshoulder,rshoulder,ltrigger,rtrigger}.*` drive the new inputs. Steps 10 and 11 were
      independently verified together. 273 tests.
- [x] 12. Redoubt design written here and approved (2026-11-20; see "Redoubt design")
- [ ] 13. Redoubt build
  - [x] 13a. Game logic (2026-11-21): the `RedoubtCore` target, with the whole approved design
        as a deterministic 120 Hz simulation (`RedoubtRun`), scripted bots (`RedoubtPilot`: idle,
        novice, competent) and a first tuning pass. The harness runs it with a leading
        `redoubt` argument. The builder's choices beyond the written design are listed under
        "Redoubt design". 351 tests in all (78 for Redoubt).
  - [x] 13b. On screen (2026-11-21): the Redoubt mode in the app (`Rimwatch/Modes/Redoubt/`),
        listed on the title screen with its own high-score table. Its look is the Calder Dome
        theme in `RedoubtCore`; the arena, pooled sprites, HUD strip, two floating sticks and
        a Shockwave button, gamepad, bots under `-autopilot`, event banners and popups, and a
        first power cut. Silent until 13c. No shell or shared code changed. The independent
        check failed it twice (Skitter arrival markers invisible in early waves; sprites
        re-textured while scaled drawn the wrong size) and passed the third time. The choices
        made are under "Decisions made while putting it on screen (13b)". 360 tests.
  - [x] 13c. Feedback (2026-11-21): 53 sound patches, a music style with four moods and a
        haptic cue for each event that matters, all in `RedoubtCore`; a tested rule keeps a
        dying crowd from stacking into noise. Nobody has listened to it.
  - [x] 13e. Polish (2026-11-21): deaths by kind, shot tails and muzzle flashes, power-cut
        flicker and lighting, the delivery run-in, compact banners, clipping to the arena,
        new colonist and life glyphs.
  - [x] 13d. Balance (2026-11-21): the wall-circling hole closed with one rule, then the
        early waves eased after the owner's first play (too hard: swarmed by wave 2). The
        novice bot now reaches wave 6. 13c, 13e and the wall rule were independently verified
        together and passed with notes (listed under "Redoubt design"). 406 tests.
- [ ] Gate: Redoubt played and refined
- [ ] 14. Riftwing design written here and approved
- [ ] 15. Riftwing build
- [ ] Gate: Riftwing played and refined
- [ ] 16. Campaign design and planning, approved
- [ ] 17. Campaign build

## What is left

The next piece of building is step 13 of the expansion, Redoubt. Ridgeline itself is built; what remains for
it needs a person and a device, and can happen alongside the expansion:

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
5. A possible later addition: the deep-sea theme for Ridgeline, as one new `Theme` file. It is
   not part of the three-mode expansion.

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

The title screen, options and high scores are also usable while closed; only starting a mode waits for the
phone to be open. Reopening mid-game does not drop you straight into the action: the same menu
appears on the inner display with Resume enabled, followed by a short countdown.

Implementation notes: `UIRequiresFullScreen = YES` so the app gets a discrete resize on each pose
change; supported orientations switch between landscape (open) and portrait (closed) via
`setNeedsUpdateOfSupportedInterfaceOrientations()`. Backgrounding the app pauses the same way.

## Game design

This section and the four after it describe Ridgeline.

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
  GameCore/                     Swift package, no UIKit/SpriteKit: builds and tests on macOS.
                                One target per mode plus the shared one.
    Sources/GameCore/           shared by every mode
      Math.swift                vectors, seeded random numbers
      Collision.swift           sweep collision maths
      Shapes.swift              colour and shape types
      Menu.swift, Options.swift, HighScores.swift, FoldPose.swift
      Gamepad.swift             pad snapshot (two sticks, shoulders, triggers), reader, menu
                                navigation
      TouchStick.swift          the floating touch stick's logic
      Feedback.swift            haptic cue names
      Audio/                    SoundPatch, SoundRenderer, Music (synthesis)
      Session/                  ModeRun, ModeSession (playing / paused / countdown / game over),
                                ModeFrontEnd (which screen and menu to show); generic over a
                                mode's run
      Modes.swift (mode descriptors and the catalog the title lists), ShellStyle.swift,
      SavedSettings.swift (options, one score table per mode, the last mode played)
      Emblem.swift              the Rimwatch emblem's geometry, including the ship hull
    Sources/RidgelineCore/      Ridgeline's game logic
      World.swift               wraparound maths, terrain heightmap, outposts
      Simulation.swift          fixed 120 Hz step; owns all entities; emits events
      Entities/                 Player, Colonist, enemy state machines, projectiles
      WaveDirector.swift        wave composition and difficulty curve
      Tuning.swift              gameplay numbers
      Input.swift               device-neutral InputState
      PadInput.swift            gamepad buttons to actions
      RidgelineMode.swift       Simulation as a ModeRun; GameSession and FrontEnd typealiases
      Events.swift, Scanner.swift, Autopilot.swift (DEBUG bots), HapticCue+Events.swift
      Theme.swift               Theme protocol: palette, shape per entity role, terrain style,
                                sound patches, display names
      Themes/AlienFrontier.swift, Themes/AlienFrontierSounds.swift
      Audio/MusicMoodDirector.swift
    Sources/RedoubtCore/        Redoubt's game logic
      RedoubtRun.swift          fixed 120 Hz step; the arena, orb, shots, waves; emits events
      Enemies.swift, Colonists.swift, Entities.swift, SpatialGrid.swift (collision grid)
      WaveDirector.swift, Tuning.swift
      Input.swift, PadInput.swift (two sticks; shoulders are Shockwave)
      RedoubtMode.swift         RedoubtRun as a ModeRun; RedoubtSession and RedoubtFrontEnd
      Events.swift, Pilot.swift (DEBUG bots), HapticCue+Events.swift
      RedoubtReadout.swift      what the HUD shows that is a rule (the colonist alarm)
      Theme.swift               RedoubtTheme protocol: palette, a shape per role, sounds
      Themes/CalderDome.swift, Themes/CalderDomeSounds.swift
      Audio/                    RedoubtSoundDirector (which events sound), RedoubtMoodDirector
    Tests/GameCoreTests/, Tests/RidgelineCoreTests/, Tests/RedoubtCoreTests/
  Rimwatch/                     app target. Shell and modes since step 9 of the expansion.
    AppDelegate.swift, SceneDelegate.swift, Info.plist, Assets.xcassets
    Shell/                      shared by every mode; imports nothing of any one mode
      ShellScene.swift          the SpriteKit scene; owns ShellDevices, loads and switches modes
      ShellDevices.swift        the synth, gamepad and haptics, shared across mode switches
      ModeHost.swift            runs one mode: menus, pause, fold poses, input, sound routing
      GameMode.swift            what a mode must provide; ModeDriver.swift, ShellServices.swift
      GameViewController.swift, FoldGate.swift (hinge status -> open / closed / no hinge),
      Settings.swift (options and per-mode high scores), DebugLog.swift, DebugMenuCommands.swift
      Input/                    GamepadInput.swift, FloatingStick.swift, DebugPadCommands.swift
      Audio/                    Synth.swift (AVAudioEngine voices), AudioDump.swift
      Feedback/                 FeedbackRouter.swift, Haptics.swift
      Render/                   GlowShapeFactory (shapes pre-rendered to additive textures),
                                EmblemNode.swift, CharRow.swift, ThemeColors.swift
      Screens/                  MenuNode (title with emblem, pause, options, game over, high scores),
                                PlayOverlays (pause button, countdown, Made for Duo), GlowText
    Modes/ModeRegistry.swift    lists the modes; the only shell-level file that names one
    Modes/Ridgeline/            RidgelineMode (+Backdrop, +Events, +Sync), TerrainNode,
                                ScannerNode, HUDNode, EffectsLayer, CalloutLayer, TouchControls,
                                RidgelineGlyphs
    Modes/Redoubt/              RedoubtMode (+Arena, +Sync, +Events), RedoubtHUD,
                                RedoubtTouchControls, RedoubtEffects, RedoubtCallouts,
                                RedoubtGlyphs
  PLAN.md                       this plan plus a progress checklist, kept current as work lands
  CLAUDE.md                     loaded automatically each session: points at PLAN.md, and notes
                                to build via the Xcode MCP tools and test GameCore with `swift test`
```

The simulation knows entity *roles*, never their appearance. The deep-sea expansion is then one new
`Theme` file (palette, shapes, terrain style, sounds, names) with no gameplay changes.

## Build order (Ridgeline, done)

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

## Redoubt design

Approved 2026-11-20. You accepted my eight recommendations and added one requirement, which leads
the list below. Every number here is a starting value, to be tuned with bots and then by you.

### The feel

- **A constant stream of fire and floods of enemies.** This is the point of the mode. Pushing
  the aim stick fires without pause: about 10 shots a second, no heat meter, no reload. The floor
  is crowded from the first second of a wave: about 20 enemies in wave 1, rising by about 8 a
  wave to around 90 on the floor at once, with more pouring in while you fight. You are always
  cutting a path, never waiting for a target.
- Redoubt is an original twin-stick arena shooter. It takes that genre's mechanics and the pace
  you asked for; its names, characters, art, sounds and layout are its own.

### The place and the player

- **Arena:** the floor of a breached outpost dome, seen from above, on one fixed screen with no
  scrolling. A wall runs round the edge. An airlock sits in the wall; its position changes from
  wave to wave. A thin strip at the top holds the HUD (score, wave, lives, Shockwave charges,
  colonists left). There is no scanner, because the whole floor is visible.
- **You** pilot a hover orb, a small one-seat craft that floats just above the floor and flies
  around the room (changed from a trooper on foot on 2026-11-20, so that every mode is about
  flying). Nothing else about the mode changes. Movement stays direct enough for a twin-stick
  game, with a little glide so it feels like a craft and not a walker; how much is tuned in
  play. Touching an enemy or a shot costs a life. You come back at the centre with a moment of
  invulnerability, and any colonists following you scatter.

### Controls

| Action | Touch | Gamepad |
|---|---|---|
| Move | Floating stick, left thumb | Left stick or D-pad |
| Aim and fire | Floating stick, right thumb; fires while pushed | Right stick; fires while pushed |
| Shockwave | A button above the aim stick's area | Either shoulder button |
| Pause | Pause button | Menu |

The handedness option swaps the two sticks. Aim is analogue, not eight-way.

### Rescue

- Each wave starts with 6 to 10 colonists sheltering around the floor.
- Touch a colonist and they follow you in a line. Lead the line to the airlock to deliver them.
- A delivery scores more for each colonist in the line (500 for the first, 1,000 for the
  second, and so on), so a long line is worth far more than several short trips. It is also a
  long tail to protect: enemies can take followers off the end.
- Every fourth colonist delivered earns a Shockwave charge.

### Abilities

- **Shockwave** only: it clears everything near you and pushes back the rest. You start each
  life with one charge and hold at most three. Blink is left out for now, since both thumbs are
  on sticks; it can be added during refinement if you miss it.

### Enemies

Six kinds, in the same cast as Ridgeline's. Each new kind first appears in a wave of its own.

| Name | What it does |
|---|---|
| Skitter | The flood. Walks straight at you in large numbers; one shot kills it. |
| Gleaner | Ignores you and goes for colonists. It drags one to the nearest Burrow or to the wall; if it gets there, a Husk comes back in its place. |
| Spitter | Keeps its distance and fires slow shots you have to weave through. |
| Burrow | A hole torn in the floor that pours out Skitters until you destroy it. Takes many hits. |
| Thresher | A slow heavy that shots only push back. It crushes colonists it walks over and is destroyed only by a Shockwave. It does not have to be killed to clear the wave. |
| Husk | The fast hunter, as in Ridgeline: a colonist the invaders have turned. |

Nothing appears within a safe distance of you, and arrivals are telegraphed for about a second.

### Structure and scoring

- A wave ends when the floor is cleared of everything that can be shot. Colonists still safe
  then score a bonus.
- Three lives, and an extra life at a score threshold.
- The high-score table records score, wave and colonists saved, like Ridgeline's.
- **Power cut:** lose every colonist in a wave (taken or crushed) and the dome's power fails.
  The next wave is fought in the dark, with a small pool of light around you and muzzle flashes
  for the rest, until you deliver a colonist. This is Redoubt's answer to Ridgeline's Blackout.

### Look and sound

- The same neon vector lines on black. Top-down shapes for the orb, colonists and each
  enemy, all drawn in code from a Redoubt theme.
- Its own sound patches and music moods on the shared synthesiser, and its own haptic cues.
- The crowd and the stream of shots must hold 120 Hz: the simulation targets 120 enemies and
  60 shots at once, with a grid for collisions, and the renderer reuses pooled sprites.

### How it is built (step 13)

The same order as Ridgeline, each stage built, independently verified and committed:

- **13a. Game logic:** a `RedoubtCore` target in the package (arena, orb, shots, the six
  enemies, colonist lines, airlock, Shockwave, waves, scoring, power cut), conforming to the
  shared run contract, with tests and scripted bots.
- **13b. On screen:** the Redoubt mode in the app (arena, sprites, HUD, twin-stick controls),
  listed on the title screen.
- **13c. Feedback:** sounds, music moods and haptics for every event.
- **13d. Waves and tuning:** the difficulty curve tuned against bots with the harness, pinned
  by tests.
- **13e. Polish:** particles, death effects, wave banners, the power-cut lighting.

Then the gate: you play Redoubt and we refine it until you are happy to move on.

### Decisions made while building the logic (13a)

These were the builder's calls where the design above was silent. All are in
`GameCore/Sources/RedoubtCore/Tuning.swift` or `WaveDirector.swift` and are yours to change when
you play it.

- **Arena:** 900 x 600 units, a rectangular floor walled on all four sides.
- **Orb:** top speed 280. The glide eases toward the stick over about 0.07 s; letting go stops it
  in about a quarter of a second.
- **Fire:** exactly 10 shots a second while the aim stick is pushed past 30%. Shots stop at the
  wall.
- **Losing a life:** touching any enemy, a Burrow included, or a Spitter's shot. You come back
  after 1.2 s at the centre with 2.5 s of invulnerability, and nearby enemies are shoved away.
- **The line:** followers trail like beads on a cord, tracing the orb's path. Only the last
  follower can be taken.
- **Delivery:** coming within reach of the airlock delivers the whole line at once.
- **Gleaner:** takes the nearest sheltering colonist or the line's tail, and drags them slowly to
  the nearest Burrow or wall. Shooting it frees the colonist where they fall.
- **Spitter:** circles at a distance, stops and winds up for 0.4 s before each slow shot. Its
  shots cannot be shot down.
- **Burrow:** 20 hits to destroy. It pours out a Skitter every 2.4 s while fewer than 10 of its
  own are alive, and 2.5 times as fast when the floor is nearly empty.
- **Hit size:** the orb is hit as if slightly smaller than it is drawn (7 units against 10), so
  a graze in the crowd is forgiven.
- **Thresher:** very slow; each shot pushes it back. If any are left when the wave clears, they
  withdraw.
- **Shockwave:** destroys everything within 150 units, Threshers and Burrows included, and pushes
  back enemies out to 340. Charges you have earned carry over to your next life.
- **Arrivals:** shown for 1 s, at least 190 units from the orb. If you sit on one, it moves.
- **Waves keep the floor full.** Each wave opens with its crowd (first 20 in wave 1, now 18;
  about 8 more each wave, up to 90), telegraphed in the last second of the break so it lands as the wave starts.
  On top of that each wave has a quota of further Skitters (90 in wave 1, 25 more each wave, up
  to 400). Whenever the number on the floor drops below the opening crowd, another group of up
  to 6 is sent in at once, until the quota is spent. The wave ends when the quota is spent and
  the floor is clear. A first version sent reinforcements on a slow timer and left a skilled
  player with nothing to shoot for half of the early waves; it was replaced after the
  independent check measured that.
- **Colonists:** 6 in wave 1, one more every two waves, up to 10. 2 s between waves.
- **Debut waves:** Gleaner 2, Spitter 3, Burrow 5, Thresher 6, Husk 8. A debut wave holds only
  Skitters and the newcomer.
- **Airlock:** moves to a different wall position each wave, and is shut between waves.
- **Wave bonus:** 250 for each colonist still safe when the wave clears; they count as saved.
- **Lives:** three, at most five, an extra one every 60,000 points.
- **Points:** Skitter 50, Gleaner 150, Spitter 200, Husk 250, Burrow 1,000, Thresher 1,500.

These were the first measurements, before the balance pass and the easier early waves
described further down, which hold the current numbers (the novice bot now reaches wave 6).
Measured then with the bots over 80 seeds: an idle orb is overrun in about 13 s. The novice bot
usually reaches wave 3. The competent bot usually reaches wave 11, loses almost no lives before
wave 7 and saves most colonists in the early waves, killing about 440 enemies a minute. In every
wave the floor has fewer than five targets for only 2 to 7% of the fighting time, which is the
mop-up at the end of a wave. Early waves last 26 to 30 s for the competent bot. The competent bot
dodges crowds almost perfectly and dies mostly to Spitter shots, so the middle waves will feel
harder to a person than these numbers say. The bots almost never trigger the power cut.

Things to judge when you play:

- Threshers soak up shots and shield what is behind them, so late waves get long if you stand
  still.
- A Burrow left alive can be farmed for Skitter points (up to about 10,000 a minute with three
  Burrows, against about 36,000 a minute for playing on), so it is a way to rest, not to score.
- Arrivals are telegraphed at least 190 units away but can appear as close as about 93 if you fly
  at them.
- Circling the wall while firing at the nearest enemy was a very strong tactic. Stage 13d
  closed it; see "The balance pass (13d)" below.

Harness: `cd Tools/Harness && swift build -c release -Xswiftc -DDEBUG &&
.build/release/Harness redoubt 80 20` (seeds, minutes cap).

### The balance pass (13d)

One hole was found and closed; nothing else in the tuning changed.

- **The hole:** a bot that only laps the arena hugging the wall and fires at the nearest enemy
  reached wave 12, lasted about 9 minutes and survived the 10-minute cap in 26 of 80 games. It
  outlasted the bot that plays properly. Skitters tail a circling orb and never catch it.
- **The fix, one rule:** while the orb is running along a wall (within 40 units of it, faster
  than 100, nearly all of that speed along the wall), each reinforcement group lands on its
  path 400 to 520 units ahead, instead of at a random side. The one-second warning and the
  minimum distance of 190 still hold. Near a corner the group arrives the usual way.
- **The numbers** are new in `Tuning.swift`: `wallRunGap` 40, `wallRunSpeed` 100,
  `wallRunAlong` 0.9, `wallRunReach` 400 to 520. Setting `wallRunGap` to 0 turns the rule off
  and gives exactly the game as it was before.
- **Result over 80 seeds:**

  | Bot | Wave reached | Survival | Score | Games at the 10-minute cap |
  |---|---|---|---|---|
  | Wall circler, before | 12 | 529 s | 228,000 | 26 of 80 |
  | Wall circler, after | 5 | 109 s | 41,000 | 0 |
  | Circler that reverses when blocked, before | 10 | 338 s | 143,000 | 0 |
  | Circler that reverses when blocked, after | 8 | 239 s | 99,000 | 0 |
  | Novice, before and after | 3 | 95 s, then 92 s | 28,200, then 26,700 | 0 |
  | Competent, before and after | 11 | 379 s, then 374 s | 227,600, then 227,800 | 0 |

  The floor is as crowded as before (fewer than five targets for 7% of the time at most) and
  never empty.
- **Tried and rejected:** a full-size hit (the circler still reached the cap, and proper play
  lost a wave), faster Skitters (everyone lost a wave), Skitters that aim ahead of the orb
  (they overshoot when you turn, which made proper play easier and changed how they feel).
- **Left as it is, for you to judge:**
  - The circler that reverses still reaches about wave 8. It scores under half of proper play
    and dies to Spitter shots.
  - Farming a Burrow pays about 6,000 to 7,000 points a minute with three Burrows, against
    about 36,000 for playing on, but it has no limit: an hour of it would beat a good game's
    score. Every clean fix changes the design (Burrow Skitters worth nothing late in a wave,
    Burrows that run dry, or a hunter that arrives when a wave drags on).
  - An enemy can land as close as 93 units if you fly at its marker.
  - Whether groups landing ahead of you on the wall feel fair or like the game cheating.
- **Bots and harness:** three DEBUG bots were added to measure this (`wallCircler`,
  `innerCircler`, `reversingCircler`). `Harness redoubt` now runs idle, novice, competent and
  the wall circler, and prints score a minute, ranges, games at the cap and how close arrivals
  land. Tests pin the hole shut and pin the farming rate.

### Easier early waves (after your first play, 2026-11-21)

You found it too hard on a controller: most games ended in wave 2 and none passed wave 3, and
the cause was being swarmed by the crowd. That matched the novice bot exactly (it died in wave
3), so the novice bot is now the stand-in for a first-time player and the target is the one
you chose: a first game usually reaches wave 5 to 6.

- **The crowd comes from one side early on.** In waves 1 to 4 the opening crowd and every
  reinforcement group arrive along one wall, usually a far one. Wave 5 uses two walls, waves 6
  and 7 three, and from wave 8 they come from anywhere, as before. This was the biggest single
  effect: the orb no longer starts each wave surrounded.
- **Slightly fewer early.** The opening crowd and Skitter quota are scaled to 90% in wave 1,
  rising 1.5% a wave to full from wave 8. Opening crowd by wave: 18, 26, 33, 42, 50, 59, 67,
  76, 84, 90 (it was 20, 28, 36, 44, 52, 60, 68, 76, 84, 90).
- **Spitters fire half as often in their debut wave**, easing back to the normal rate by
  wave 7. Once the swarm deaths were gone, Spitter shots were what ended the novice's games.
- **The numbers** are in `WaveDirector.swift`: `entrySides` `[1,1,1,1,2,3,3,4]` (was anywhere
  in every wave), `crowdEaseStart` 0.9 (was 1), `crowdEaseGrowth` 0.015 (was 0),
  `spitterDebutSlowdown` 2.0 (was 1), `spitterEaseWaves` 4; and in `Tuning.swift`:
  `entryBandDepth` 180, `entrySideJitter` 300. Setting the first four back gives exactly the
  previous game.
- **Result over 80 seeds:**

  | | Before | After |
  |---|---|---|
  | Novice: wave reached | 3 | 6 |
  | Novice: survival | 92 s | 183 s |
  | Novice: lives lost in waves 1 and 2 together | 1.05 | 0.21 |
  | Novice: directions blocked round the orb in wave 1 (of 8) | 1.3 | 0.8 |
  | Competent: wave reached | 11 | 11 |
  | Wall circler: wave reached | 5 | 4 |

  The floor is still never empty mid-wave. The late game (wave 8 on) is untouched.
- **Not changed:** orb speed, fire rate, how Skitters walk, lives, the respawn, Shockwave.
- **Tried and left out** because they made no measurable difference: a bigger clear zone at
  the start of a wave, and keeping reinforcements off the wall the orb is heading for.
- **To look for when you play:** whether there is room to back away and whether one wall is
  too predictable; whether 18 in wave 1 still feels like a crowd; whether wave 3 (Spitters) or
  wave 7 (the third wall at nearly full density, where the novice loses most lives) is a step.
- **An alternative** if "about 20 in wave 1" matters more: the same entry walls and Spitter
  easing with no crowd reduction gives a novice median of wave 5, with little margin.
- The harness now also prints the pressure on the orb per wave (enemies within 120 and 200
  units, directions blocked) and what each loss looked like.

### What the independent check of sound, polish and balance found

It passed with notes (before the easier early waves above, which were checked separately).

- A colonist seized within about 0.3 s of another makes no second alarm sound; the HELP! popup
  and the haptic still fire.
- Starting a Redoubt run in the first second after switching modes can lose the wave's first
  two sounds (the airlock opening and the first arrival rustle) while the sounds are still
  being prepared. Fixing it means caching prepared sounds per mode in the shell.
- At full sound volume the very worst pile-up of sounds relies on the limiter, as Ridgeline's
  does. At the default volume it stays just under full scale.
- **A gap left in the wall rule:** walking the wall slowly (under the rule's speed threshold)
  reaches about wave 9, close to proper play's survival at about 60% of its score. Not closed.
- A player running along a wall to an airlock at full speed will meet a group landing on
  their path. Whether that feels fair is yours to judge.
- Haptics run at about 39 cues a minute in a good game, 44 of them light ticks for colonists
  joining the line.

And from the check of the easier early waves and the last fixes (also a pass with notes):

- **Camping in a corner now does better than the novice bot.** A bot that parks in a corner
  and fires at the nearest enemy reaches wave 7 (about 4 minutes); before the easing it
  reached wave 4. The one-wall rule favours walls far from the orb, so a camper sees every
  early crowd coming from the far side. Parking mid-wall reaches wave 4 and at the centre
  wave 3. Whether sitting in a corner should work is yours to decide; it is not closed.
- **In the app the bots play worse than in the harness.** The app asks a bot for its sticks
  once per drawn frame and the harness once per simulation step, so in the app the bot reacts
  half as fast: the novice bot under `-autopilot` dies in wave 1 or 2. Every balance number in
  this plan is from the harness. It has been this way since Ridgeline; it only affects what
  you see when watching a bot play in the app.
- Closing the phone during a power cut and reopening it keeps the darkness and the music mood
  correct.

### Decisions made while putting it on screen (13b, polished in 13e)

The builder's calls for the look and the layout. The shapes and colours are in
`GameCore/Sources/RedoubtCore/Themes/CalderDome.swift`; the layout is in
`Rimwatch/Modes/Redoubt/`. All are first versions for you to judge on the phone.

- **Orb:** a cyan ring (the Watch's cyan) round a pale seat, with a pointed emitter at the front
  that shows where it aims and two hover struts. A faint wide halo helps find it in a crowd.
- **Colonist:** an upright mint figure with its arms up (head, body, arms, legs). A first
  version seen from above read as a small "u" and was redrawn.
- **Enemies, one colour each:** Skitter, a small orange four-legged diamond; Gleaner, a yellow
  open claw; Spitter, a violet hexagonal turret with a barrel; Burrow, a dull brown ragged hole
  with rings stepping down (first dark orange, moved away from the Skitter's colour); Thresher, a big
  crimson hull with a toothed blade; Husk, Ridgeline's magenta spinning star.
- **Shots:** the orb's are pale cyan streaks with a dim tail about 50 units long, a muzzle
  flash on every shot and a spark where each ends. The Spitter's is a throbbing hot-pink
  four-pointed star inside a faint ring.
- **Deaths, by worth:** a Skitter is four sparks and a small flash; Gleaner, Spitter and Husk
  each burst in their own colour (tumbling shards, venom sparks, spinning shards); a Burrow
  falls in on itself; a Thresher is a wreck of big shards with a shake.
- **Airlock:** mint posts with chevrons pointing out and a faint arc marking the delivery reach;
  a steel bar across it when shut. It pulses while colonists are following you.
- **Arrivals:** four corner brackets in the newcomer's colour that close in over the warning
  second. Skitters, which arrive by the dozen, get a small faint ring instead that brightens
  and strobes in the last quarter second, so a late wave's opening is not a carpet of brackets.
  Anything bigger than a Skitter lands with a puff in its own colour.
- **Banners:** a compact line or two along the top of the floor, left of the crease: about 1 s
  for a wave, 2 s for a debut wave (which names the newcomer and what it does). Popups stay
  inside the floor.
- **Clipping:** effects and the orb's halo are cut at the arena wall.
- **Delivery:** the line runs in through the airlock door one colonist after another, and the
  ring, burst and popup grow with the number delivered.
- **Losing the orb** is shown at the orb (hull shards, a red flash, a ring) with only a light
  red wash over the screen.
- **Floor:** steel-blue walls, faint floor crosses, a ring marking the centre where you return.
- **HUD:** one thin strip above the arena. Score and wave left of the crease; lives, Shockwave
  charges and colonists left to the right, ending before the pause button.
- **Arena size:** as large as fits below the strip, spanning the crease: about 0.97 pt per unit
  on the Duo's inner display.
- **Touch controls:** a move stick and an aim stick resting low in the two bottom corners, each
  floating to wherever a thumb lands in its half. The Shockwave button sits above the aim stick
  with its three charges shown over it. Stick side in Options swaps the sticks and the button
  goes with the aim stick. With a controller connected they are hidden.
- **Thumbs over the floor:** the arena was kept full size rather than shrunk to leave gutters
  for the thumbs, which would have cost about 20% of the size of everything. The price is that
  thumbs sometimes cover a colonist or an airlock in a bottom corner.
- **State you can see:** a Spitter turns white-hot while it winds up; a Husk grows and flickers
  as it wakes; a Burrow's hole shrinks as it is shot; a seized colonist flashes red on a red
  tether to its Gleaner; the line is joined to the orb by a mint cord; the orb strobes inside a
  ring while it cannot be hit.
- **Power cut:** the lights stutter out over about a second, and stutter back when a delivery
  restores them. The floor and the enemies go dark except a pool of light about 70 units round
  the orb, fading out by 160. Firing throws that pool forward along the aim, and a Shockwave
  lights the whole room for a moment. Shots, sparks, colonists, the airlock and arrival markers
  stay visible. Enemies in the dark show very faintly, except a Spitter winding up, which
  glows through as fair warning.
- **A fourth bot, `shooter`** (DEBUG only): fights like the competent bot but never rescues.
  It was added to reach the power cut, and stopped reaching it once the difficulty was
  retuned; no bot reaches it by play now.
- **Seeing the power cut:** the DEBUG argument `-powerCutAtWave <n>` starts wave n in the dark
  as if every colonist had been lost in the wave before, whatever the tuning. With
  `-autopilot competent -powerCutAtWave 2` the lights fail about 25 s in and return on the
  first delivery.
- **The colonist count** in the HUD turns red and blinks only for danger: the power is out or
  about to fail, or every colonist still on the floor is in a Gleaner's grip. A zero after
  everyone was delivered stays calm. The rule is `RedoubtRun.colonistAlarm`, with tests.
- **One more DEBUG argument:** `-noClip` turns the wall clipping off for comparison.
- **Banners and notices can never overflow their half of the floor:** a line that does not fit
  shrinks, then wraps onto a second line, then is cut short with an ellipsis.

Things to judge on the phone (first versions, none measured by a person yet):

- Whether ten shots a second reads as a constant stream. In a still it is an evenly spaced
  line of streaks.
- The orb is about 10 pt across on the Duo. The halo helps; judge it in a real crowd.
- The thumbs cover the lower corners, and sometimes a colonist or a low airlock there. The
  delivery run-in is short and can happen under a thumb.
- A dense clump of Skitters merges into an orange mass.
- The size of each death effect at a few hundred kills a minute.
- The power cut: how dark it is, how far firing throws the light, whether the flicker feels
  like failing lights, and whether enemies in the dark should show at all.
- The new colonist and life glyphs and the brown Burrow at real size.
- Whether the Skitter's faint arrival ring is warning enough.

### Decisions made for sound, music and haptics (13c)

Nobody has heard any of this: every sound was measured (level, length, how it survives a phone
speaker, the worst pile-up) and none was listened to. The patches are in
`GameCore/Sources/RedoubtCore/Themes/CalderDomeSounds.swift`.

- **Its own voice, same world:** 53 patches named `dome.*`. The orb is clean tones, enemies are
  rough and noisy, colonists are pure tones, alerts are chords with a short close echo. None is
  taken from Ridgeline.
- **The shot** is a 45 ms tick in three pitches that never repeats the same pitch twice running,
  quieter than Ridgeline's shot because it sounds ten times a second.
- **A dying crowd cannot stack into noise:** a small tested rule (`RedoubtSoundDirector`) lets
  one sound per kind of event through each frame, limits Skitter deaths to about 40 a second
  and arrival rustles to one a second, and keeps small enemies silent when a Shockwave clears
  them.
- **Sounds that carry information:** a colonist seized is the most urgent alarm and cannot be
  cut off by shots or Skitter deaths; a Spitter's wind-up sounds for exactly its 0.4 s; a
  Thresher hit is a dull clank; a Burrow's hit sound rises as it is damaged; colonists joining
  the line climb a scale; the delivery fanfare grows with the length of the line.
- **Shockwave** is the loudest sound in the game.
- **Music:** G Phrygian at 104 bpm (Ridgeline's is A minor at 84), with a low pulse while a
  wave is fought. Tension is the normal state; calm fills the 2 s break between waves; the
  power cut uses the shared `blackout` mood; menus use the title mood.
- **Haptics:** nothing for shots or Skitter kills. A warning for a colonist seized or a Husk
  forming, an impact for a colonist lost and for a Burrow or Thresher destroyed, a rumble for
  the orb lost, the power failing and game over, a sweep for Shockwave, and light taps for the
  rest. About one cue every two seconds in a normal game.
- **The title screen** plays the loaded mode's menu sounds and title music, so it sounds
  different with Redoubt selected than with Ridgeline, as its colours already do.

Things to judge by ear on the phone, least certain first:

- Whether the shot stays pleasant for ten minutes, or is too faint under the music.
- The tension music looping for minutes, and whether the 2 s of calm between waves sounds like
  a breath or a hiccup.
- Whether the seized alarm cuts through a crowd without being shrill.
- The arrival rustle (up to once a second): subtle, or a constant hiss.
- The Thresher clank and the respawn sound lose most of their weight on a phone speaker.
- Shockwave and the power failing are both gentler than Ridgeline's Shockwave and Blackout.
- The haptics have never run on hardware.

A fault found here that Ridgeline shares, left alone until you decide: a sprite given a new
texture while it is scaled comes out the wrong size. Redoubt now guards against it in one
place (`RedoubtSprites.dress`). In Ridgeline it affects reused particles all the time
(`Modes/Ridgeline/EffectsLayer.swift`, sparks and shards of slightly wrong sizes), an enemy
whose tint flickers during a hit pulse for about a tenth of a second
(`RidgelineMode+Sync.swift`), and a held touch button on relayout. Ridgeline's look as you
approved it includes this, so fixing it changes the particle sizes you have seen; it is not
fixed.
