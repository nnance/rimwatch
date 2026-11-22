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
- [x] Gate: Redoubt played and refined (closed 2026-11-21 on your instruction to fix the
      later-wave Gleaners and then move on; what is left for you to judge is listed at the end
      of "Gleaners through the wave" in the Redoubt design)
  - [x] Refinement 1 (2026-11-21, after your second play): the opening crowd arrives as a main
        push from a different side each wave plus a thin scatter, in place of a strip along one
        wall that stayed on the same side. 415 tests. Pushed before its independent check, by
        agreement; see "A natural crowd entry" in the Redoubt design. You played it the same
        day and said it was good and more natural.
  - [x] Refinement 2 (2026-11-21): the orb, enemies, colonists and shots are 50% bigger, in
        collision and in drawing, with the balance brought back. 416 tests. Pushed before its
        independent check; see "Everything 50% bigger" in the Redoubt design. You played it and
        called the size a good improvement.
  - [x] Refinement 3 (2026-11-21): colonists are taken later and more slowly in the early
        waves. 425 tests. Pushed before its independent check; see "Colonists taken later and
        more slowly" in the Redoubt design.
  - [x] Refinement 4 (2026-11-21): Spitters fire in their first wave again and the Burrows'
        first wave is eased instead. 428 tests. Pushed before its independent check; see
        "Spitters back, Burrows eased" in the Redoubt design.
  - [x] Refinement 5 (2026-11-21): the Gleaners' ease ramps across their appearances, so
        wave 7 is no longer a cliff for colonists. 432 tests. Pushed before its independent
        check; see "The Gleaners' ease as a ramp" in the Redoubt design. You played refinement
        3 and said stage 2 was improved.
  - [x] Refinement 6 (2026-11-21, the fix you chose before moving on): Gleaners arrive one at
        a time through the wave, and a seized colonist cannot be lost in less than a least
        time. The Spitters' and Burrows' eases now count each kind's own appearances. 535 tests
        (with Riftwing's). Pushed before its independent check; see "Gleaners through the wave"
        in the Redoubt design, which also lists what it did not reach. Its independent check
        passed with notes, and the three shortfalls it found were corrected the same day
        (548 tests).
- [x] 14. Riftwing design written here (2026-11-21). You chose the one-screen cavern and
      flap plus a dive with no weapon, and told me to build while you were away; I took that
      as approval. My other choices are marked "mine" in "Riftwing design" for you to overrule.
- [ ] 15. Riftwing build
  - [x] 15a. Game logic (2026-11-21): the `RiftwingCore` target, its tests, eight scripted
        bots and the `riftwing` harness. 521 tests. The novice bot reaches wave 5.5 to 5.6 on
        three sets of 200 games; the competent bot wave 10.3; no exploit bot outlasts or
        outscores proper play. Pushed before its independent check; see "Decisions made while
        building the logic (15a)" in the Riftwing design.
  - [x] 15b. On screen (2026-11-21): Riftwing is the third mode on the title screen and can
        be played with touch or a gamepad. No shell change. 544 tests. Pushed before any
        independent check; touch controls were laid out but could not be exercised from the
        command line. See "Decisions made while putting it on screen (15b)".
  - [x] 15c. Sounds, music and haptics (2026-11-21): 54 patches, a sound director, music in
        its own key with three moods, and haptic cues. 581 tests. Every patch was rendered and
        measured; nothing has been heard or felt. Pushed before any independent check. See
        "Decisions made for sound, music and haptics (15c)".
  - [x] 15d. Fixes and tuning (2026-11-21): every defect the logic check found is fixed, the
        breath is fairer, no place is safe to camp, and the game is tuned to a novice bot
        remade to fly like a person, which reaches wave 5.5 to 5.6 (median 6) over 600 games.
        602 tests. Pushed before its independent check; see "Fixes and tuning (15d)".
  - [ ] 15e. Polish
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

### A natural crowd entry (after your second play, 2026-11-21)

You said the difficulty was right and builds well (you reached wave 5), but that at the start
of a round all the enemies appeared on the right-hand side and it looked odd.

- **Why it happened.** In waves 1 to 4 the whole crowd arrived in a strip along one wall, the
  wall farthest from the orb. A player backs away from the crowd and ends the wave near the
  opposite wall, so the same wall was the farthest again next wave: the crowd stayed on one
  side for four waves.
- **The main push.** Most of the opening crowd still comes from one side, but within 260 of
  the wall (it was a 180 strip), thinning out away from it and leaning toward the end of the
  wall away from the orb. It reads as a front coming from, say, the north-west.
- **The side changes every wave.** It is never the wall the orb is nearest and never the
  previous wave's wall. Among the rest, farther walls are likelier but not certain.
- **The scatter.** A share of the crowd lands anywhere on the floor at least 300 from the
  orb: 20% in wave 1, rising to 60% in wave 7, and everything from wave 8 as before. Every
  role takes part.
- **Reinforcement groups** keep to the wave's entry walls, each landing at the farthest from
  the orb of six clear spots. The wall-run rule is unchanged.
- **The numbers:** `RedoubtWaves.scatterShare` `[0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6, 1]`; in
  `Tuning.swift` `pushDepth` 260, `pushFalloff` 1.5, `pushAlongDraws` 4, `scatterClearance`
  300, `mainWallWeighting` 2, `groupSpotDraws` 6. `RedoubtWaves.pushAndScatter = false` gives
  exactly the previous game (a test checks it against the old golden values).
- **Result over 80 seeds:**

  | | Before | After |
  |---|---|---|
  | Novice: wave reached (median, mean) | 6 (5.59) | 5 (5.46) |
  | Novice: survival | 183 s | 159 s |
  | Novice: lives lost in waves 1 and 2 together | 0.21 | 0.28 |
  | Novice: directions blocked round the orb in wave 1 (of 8) | 0.8 | 0.6 |
  | Competent: wave reached | 11 | 11 |
  | Wall circler: wave reached (mean) | 4 (4.25) | 4 (3.75) |
  | Corner camper: wave reached (mean) | 7 (6.92) | 7 (6.74) |

  The novice's median sits on the line between waves 5 and 6, so 80 seeds flip it. Over 800
  games on a second seed set the mean is 5.38 before and after; over 400 on the first it is
  5.49 before and 5.26 after. Read it as level or very slightly harder. Waves 3 and 4 are a
  little harder and wave 6 easier.
- **What it cost and what paid for it.** Choosing the wall at random instead of the farthest
  costs about a quarter of a wave, and each 10% of scatter about 0.15. Landing reinforcement
  groups at the farthest of several spots and leaning the push toward one end of the wall
  bought that back. There is no margin left: a heavier scatter would make a first game shorter.
- **Tried and left out:** reinforcements from any wall the orb is not near (clearly harder);
  the scatter arriving a second or two late; a larger scatter clearance; scattering Skitters
  only; a push along the whole wall (about a tenth of a wave harder than the lean; set
  `pushAlongDraws` to 1 for that look).
- **To look for when you play:** whether the heavier side is still too one-sided or now right;
  whether the few scattered enemies behind you feel unfair; whether waves 3 and 4 are a step.
- **Not yet checked independently or seen on a screen** when it was pushed: the look was
  judged from text maps (`MAP=<seed>[,<seed>] .build/release/Harness redoubt` prints where
  the opening crowd lands in waves 1 to 5).
- The harness also gained a corner-camping bot (`cornerCamper`). It still reaches wave 7; the
  camping note below stands.
- **The independent check afterwards passed with notes** (no defect; spacing, the wall rules
  and determinism hold; the novice measured level on a fresh 200 seeds, 5.45 against 5.46):
  - The push gathers toward a corner more than along a wall (the lean, `pushAlongDraws` 4), so
    it usually arrives diagonally opposite the orb. A player who moves sees a different corner
    each wave; one who holds a spot sees the same far corner (a corner camper 92% of the
    time). `pushAlongDraws` 2 would give more of a front at about a tenth of a wave harder.
    Left as it is: you played it and called it natural.
  - With the orb at the exact centre (the start of a run, or a respawn) the "nearest wall" is
    always taken as north, so wave 1 never pushes from the north and rarely from the south.
  - The tests pinned the wall rules, the distances, the shares rising and the switch back, but
    not that farther walls are likelier, the lean, the six-spot rule for reinforcement groups
    or the exact shares. Five tests added afterwards pin those, and cover waves 2 to 4 with
    the orb off-centre and moving (421 tests).
  - The wall circler and corner camper both do slightly worse than before.

### Everything 50% bigger (2026-11-21)

You said the orb and the enemies were very small, the orb almost a dot, and chose to grow
everything by 50%.

- **One number.** `RedoubtTuning.figureScale` is 1.5. The orb, every enemy, colonists, the
  orb's shots and Spitter shots follow it for both collisions and drawing, so what you see is
  still what gets hit. The orb is now 30 units across on the 600-unit floor (it was 20), a
  Skitter 24, the Burrow 54.
- **What else follows it:** the colonist pick-up reach and the spacing of the line, the
  airlock's opening and reach, how close arrivals land to a wall, the spacing between Burrows,
  and the effects fixed to a figure (halo, shield, muzzle flash, respawn ring, death pops and
  sparks, the airlock beacon).
- **What does not:** the floor, every speed, the fire rate, the clear distance for arrivals,
  Shockwave's reach, Spitter ranges, lives, scoring, the crowd-entry rule, the HUD, text and
  the touch controls.
- **Balance.** Growing the figures alone made a first game a little shorter (novice mean wave
  5.18 against 5.47) and corner camping better. Four numbers in `WaveDirector.swift` bring it
  back:
  - `crowdScale` 1.1 (new): the opening crowd and the floor target are 10% larger, still
    capped at 90. Bigger enemies are easier to hit, so the crowd dies faster.
  - The Skitter quota is `quotaFirst` 126 plus `quotaGrowth` 28 a wave (it was 90 plus 25).
  - `crowdEaseStart` 0.82 and `crowdEaseGrowth` 0.03 (they were 0.9 and 0.015). Wave 1 still
    opens with 18; the full crowd arrives in wave 7.
  - `spitterDebutSlowdown` 3.8 (it was 2): in their first wave Spitters fire about every 8 to
    11 seconds. This is the one you are most likely to notice.
- **Result over 80 seeds:**

  | | Before | After |
  |---|---|---|
  | Novice: wave reached (median, mean) | 5 (5.47) | 5 (5.46) |
  | Novice: survival | 158 s | 178 s |
  | Novice: lives lost in waves 1 and 2 together | 0.27 | 0.25 |
  | Competent: wave reached (median, mean) | 11 (10.55) | 10 (10.05) |
  | Wall circler: wave reached (median, mean) | 4 (3.73) | 3 (3.41) |
  | Corner camper: wave reached (median, mean) | 7 (6.74) | 7 (7.11) |

  Over 400 seeds the novice's mean is 5.48 and its median 6. Two misses against what I asked
  for: the corner camper is slightly better on average (it still nearly always dies in wave
  7), and the competent bot is about half a wave worse.
- **To undo it:** `figureScale = 1` with `RedoubtWaves.beforeFiguresGrew` gives exactly the
  previous game (a test checks it against the old golden values).
- **Not yet checked independently** when it was pushed. The builder looked at wave 1, a wave 3
  crowd and wave 4 on the simulator; a delivery through the airlock, the respawn and the power
  cut at the new size had not been seen.
- **To look for when you play:** whether 50% is enough or too much; whether hits still look
  fair now that the orb is a bigger target; whether the floor feels cramped in waves 5 and
  later; whether the Spitters' first wave is now too gentle.
- **The independent check afterwards passed with notes.** Nothing broken: sizes are right on
  screen beside the old build (orb, enemies, colonists, arrival rings about 1.5 times; HUD
  icons identical), the line fits the airlock, the respawn ring and shield fit the orb, the
  forced power cut still works (the builder's captures were simply taken after the first
  delivery had ended it), no figure is scaled twice or on one side only, the switch back is
  exact, and the balance numbers reproduce. Its notes:
  - **Spitters barely fire in their first wave.** With the debut slow-down at 3.8 the novice
    sees 1.1 Spitter shots in wave 3 (it was 3.5), and in 43% of games none at all, so the
    wave that introduces them teaches nothing. The slow-down also now lasts to wave 6, making
    wave 6 to 7 a bigger jump in Spitter fire (about 1.8 times; it was 1.3).
  - **The difficulty moved later.** The average is the same but the shape is not: the novice
    loses more lives in wave 5, the Burrow's first wave (1.33 against 0.93), and wave 6; its
    first death comes later (100 s against 73 s); far fewer games reach wave 7. Wave 5 is now
    the hardest step for a first game. Deaths to Threshers and Burrows rose and deaths to
    Spitter shots fell.
  - Not seen on the simulator: a Husk, Spitter shots in flight, death pops close up.
  - **Not changed yet.** The better trade is probably to put the Spitter slow-down back
    toward 2 and ease wave 5 instead. It waits for your verdict on the size, since a different
    size needs the balance re-run anyway.

### Colonists taken later and more slowly (2026-11-21)

After playing at the bigger size you said that twice nearly every colonist was taken very
quickly when the stage started, that balance is also how quickly colonists are taken and not
only how early the player dies, and that Ridgeline takes them much later in a stage and
slowly in the early stages. Until now the bots measured only how the orb fared.

- **Why it happened.** Gleaners first come in wave 2: four of them against six colonists, all
  on the floor about two seconds in. Each went straight for the nearest colonist and dragged
  it to the nearest wall at 60 units a second, and a colonist can stand 50 units from a wall.
  The novice bot's first colonist was seized 2 seconds into wave 2 and gone 1.5 seconds later.
- **Gleaners arrive later in the early waves.** In wave 2 the opening crowd's Gleaners land 7
  seconds after the rest of the crowd (their markers show for the usual second). The delay is
  4.2 seconds in wave 4 and gone by wave 7. The wave cannot end while they are on their way.
- **They drag more slowly in the early waves.** Six times slower in wave 2 (10 units a
  second), four times in wave 4, and the normal 60 from wave 7.
- **The numbers** are in `WaveDirector.swift`: `gleanerDebutDelay` 7, `gleanerDebutDragSlowdown`
  6, `gleanerEaseWaves` 5. `RedoubtWaves.beforeGleanerEase` gives exactly the previous game.
  The Gleaners' count, their approach speed and where colonists stand are unchanged.
- **Result for the novice over 80 seeds** (Gleaners come in waves 2, 4, 7, 9 and on; waves 3,
  5 and 6 introduce other enemies and have none):

  | Wave | First seizure, s (one game in ten is earlier than) | Colonists lost by the wave's end | Seizure to loss, s (shortest) |
  |---|---|---|---|
  | 2 | 2.0 (1.0) to 10.8 (8.3) | 23% to 3% | 1.5 (0.5) to 5.9 (3.4) |
  | 4 | 1.5 (0.7) to 6.2 (5.1) | 29% to 13% | 1.7 (0.5) to 5.4 (1.4) |
  | 7 | 1.2 (0.7) to 1.1 (0.7) | 37% to 39% | 1.9 (0.7) to 1.9 (0.4) |

  Games losing three or more colonists in the first 20 seconds of wave 2: 14% to none; of
  wave 4: 35% to 9%.
- **The rest of the balance held:** novice wave 6 (mean 5.53; it was 5.46), survival 188 s,
  lives lost in waves 1 and 2 together 0.20; competent 10 (9.90); wall circler 3 (3.46);
  corner camper 7 (7.30). More colonists delivered means 0.6 more Shockwave charges a game
  and about 4% more score.
- **What it does not fix.**
  - Every seizure still happens in one burst when the Gleaners land, because reinforcements
    are Skitters only. The burst is later and slower in waves 2 and 4, but colonists are not
    taken across the length of a wave the way Ridgeline's are.
  - From wave 7 the Gleaners are as before: about 39% of colonists gone in the first seconds
    of the wave.
  - The shortest drags are still 1.4 to 3.4 seconds, when a colonist stands beside a wall.
    A floor on that needs a rule (a hold before the drag starts), not a speed.
  - A fuller answer would send Gleaners in through the wave in ones and twos and give every
    seizure a minimum time. That is a design change and was not made here.
- **Not judged on a screen:** a drag at 10 units a second may look like a crawl. The novice
  bot ignores the alarm, so that a person will use the slower drag to shoot the Gleaner is
  reasoned, not measured.
- The harness now prints, per wave, the time to the first seizure, the share seized and lost
  in the first 10 and 20 seconds and by the end, the time from seizure to loss, and how many
  were freed.
- **The independent check afterwards passed with notes.** No defect in the code; the numbers
  reproduce; waves without the ease are identical to before; the wave cannot end while
  Gleaners are still to come. Its notes:
  - **Wave 7 is a cliff.** The ease is counted in waves, but Gleaners only come in waves 2, 4
    and 7, so a player meets three steps: late and slow, less so, then nothing. From wave 4 to
    wave 7 the first seizure goes from 6.2 s to 1.1 s, colonists lost from 13% to 39%, and
    games losing three or more in the first 20 seconds from 9% to 70%. About a quarter of
    novice games reach wave 7. Counting the ease in Gleaner waves (first, second, third and
    so on) would make it a ramp. Not fixed yet.
  - **Delayed Gleaners always land with the main push**, never in the scatter, because the
    late arrivals skip the scatter rule. They keep the clear distance from the orb as it is
    when their marker appears.
  - **The balance is level within noise.** On a second seed set of 200 games the novice's mean
    went from 5.49 to 5.38 and its median from 6 to 5, the opposite way to the first set.
  - **On screen a wave-2 drag reads as "held", not "dragged".** The colonist turns red with
    HELP! and the Gleaner sits on it, which is clear, but the pair barely moves for about 5
    seconds. Along the east wall it can sit under the Shockwave button.
  - **The "New: Gleaner" banner shows at the start of wave 2**, about 6 seconds before any
    Gleaner's marker appears.
  - No test covers where delayed Gleaners land, or the orb being lost while they are still to
    come (seen four times in its runs with nothing going wrong).

### The Gleaners' ease as a ramp (2026-11-21)

The check of the first Gleaner ease found that it ended abruptly: Gleaners come in waves 2, 4,
7, 9, 10 and on, and the ease was counted in wave numbers, so wave 7 had none of it.

- **The ease now steps down across the Gleaners' own appearances** and applies only in waves
  that send Gleaners:

  | Wave | Gleaners land after the crowd by | Drag speed |
  |---|---|---|
  | 2 | 7 s | 10 units a second (6 times slower) |
  | 4 | 4.9 s | 13 (4.5 times) |
  | 7 | 3.9 s | 16 (3.75 times) |
  | 9 | 2.8 s | 20 (3 times) |
  | 10 | 1.4 s | 30 (twice) |
  | 11 on | none | 60 |

  `RedoubtWaves.gleanerRampEase` is `[1, 0.7, 0.55, 0.4, 0.2]`, the share of the ease left in
  each Gleaner wave. `RedoubtWaves.beforeGleanerRamp` gives exactly the previous game.
- **Late Gleaners always land with the main push, never in the scatter**, as a deliberate rule
  (`lateArrivalsScatter` false). I first asked for them to follow the scatter rule like the
  rest of the crowd; measured, that landed some beside colonists, moved the first seizure
  earlier, allowed an instant loss and cost the novice about a sixth of a wave.
- **Result for the novice in wave 7** (before to after; two seed sets):
  first seizure 1.1 s to 4.6 s; colonists lost about 30% to between 6% and 12%; games losing
  three or more in the first 20 seconds about 60% to between 11% and 33%. Few novice games
  reach wave 7 (12 of 80 and 35 of 160), so these are rough. Wave 2 is unchanged. Wave 4 is
  slightly softer than before the ramp (11% lost against 13%, first seizure 6.9 s against 6.0).
- **The balance** over 80 seeds: novice wave 5 (mean 5.14; it was 6 and 5.36); competent 10
  (9.93); wall circler 3 (3.44); corner camper 7 (7.42; it was 7.16). On a second set of 160
  seeds the novice is level (6, mean 5.32 against 5.33). The 80-seed set is noisy for the
  novice, but across the last three changes its mean there has gone 5.53, 5.36, 5.14, so the
  next check measures it on more seeds.
- **What it leaves:**
  - **With unlimited lives the bot still loses colonists steeply from wave 7** (measured
    before the last correction: 38% in wave 7, 49% in wave 9, 61% in wave 10). That comes from
    the waves themselves, not the delay or drag speed. Gleaners arriving through the wave in
    ones and twos would be the answer; it is a design change and waits for you.
  - **The corner camper does a little better.**
  - A second ramp value of 0.6 keeps wave 4 exactly as it was, but the reversing circler then
    survives 300.5 s against the 300 s limit of `circlingTheWallIsNoSaferThanFighting`, so 0.7
    was kept.
  - A colonist standing right beside the wall the Gleaners come from can still be lost at
    once.
- Also fixed: a run with no waves (used only by tests) dragged at the debut crawl, and the
  test of a full-speed drag ending in a Husk had been stretched to fit; both are put right.
  New tests cover the orb being lost and the game ending while Gleaners are still to come.
- **The independent check of this and of "Spitters back, Burrows eased" passed with notes**
  (no code defect; every switch replays its old game exactly; 600 novice games at each point):
  - **The novice really did get worse, by a third of a wave, and all of it came from the
    Spitters firing again**, not from this ramp (which is neutral for the novice). Mean wave
    5.54 before the Spitter change, 5.23 after it, 5.21 now; median 6 then 5. Games ending by
    wave 4 went from 22% to 38%; Spitter shots are now the main cause of death in waves 3
    and 4. The novice sits just under the range I aim for.
  - **The same kind of cliff remains for Spitters and Burrows.** Their eases are counted in
    wave numbers, but Spitters come in waves 3, 4 and then 7, so between waves 4 and 7 their
    fire rate more than doubles while their number goes from 3 to 6. Wave 7 is the novice's
    deadliest wave.
  - **For Gleaners a cliff remains between waves 7 and 9**, seen by the competent bot:
    colonists lost 19% then 37%, games losing three or more in the first 20 seconds 19% then
    67%, and 84% in wave 10.
  - The corner camper's gain is real but small (about 0.14 of a wave).
  - Small slips in comments and one harness note.
- **Decided by you on 2026-11-21:** fix the later-wave Gleaners before moving on, by sending
  them in through the wave in ones and twos and giving every seizure a minimum time. That
  pass also counts the Spitters' and Burrows' eases in their own appearances and brings the
  novice back into range; see "Refinement 6" in the progress list when it lands.

### Spitters back, Burrows eased (2026-11-21)

The check of the size change found that the balance had been held by making Spitters almost
silent in their first wave, and that wave 5 had become the hardest step. You confirmed the
50% size, so this puts the trade right.

- **Spitters fire in their first wave again.** `spitterDebutSlowdown` is back to 2 (it was
  3.8). The novice now sees 2.5 Spitter shots in wave 3 (it was 1.0) and none in 11% of games
  (it was 45%). The biggest step in Spitter fire between two waves is 1.35 times (it was
  1.83 between waves 6 and 7).
- **The Burrows' first wave is eased.** Wave 5 sends one Burrow, not two (`burrowsAtDebut`
  1; the other becomes a Skitter, so the crowd is the same size), and Burrows pour at half
  rate in wave 5, back to full by wave 8 (`burrowDebutSlowdown` 2, `burrowEaseWaves` 3).
  Slowing the pour alone was not enough; removing the second Burrow was what did it.
- **To undo it:** `RedoubtWaves.beforeBurrowEase` gives exactly the previous game.
- **Novice lives lost by wave** (per game that reached the wave, 80 seeds):

  | Wave | Before | After | Games ending here, before to after |
  |---|---|---|---|
  | 1 | 0.10 | 0.10 | 0% to 0% |
  | 2 | 0.10 | 0.10 | 0% to 0% |
  | 3 (Spitters) | 0.45 | 0.70 | 4% to 8% |
  | 4 | 0.82 | 0.95 | 15% to 28% |
  | 5 (Burrows) | 1.48 | 0.88 | 31% to 10% |
  | 6 (Threshers) | 1.27 | 1.66 | 25% to 31% |
  | 7 | 1.50 | 1.47 | 25% to 24% |

- **The balance:** novice wave 6 (mean 5.36; it was 5.53; 5.41 over 160 seeds), survival
  190 s, lives lost in waves 1 and 2 together 0.20; competent 10 (10.06); wall circler 3
  (3.42); corner camper 7 (7.16). The novice's mean is near the bottom of the range I aim for.
- **What it leaves:**
  - **Wave 6, the Threshers' first, is now the highest step** (about 0.6 to 0.8 lives above
    wave 5). Partly this is because novices reach it with more lives to lose.
  - **Wave 2 to 3 is a step of 0.6 lives.** Each Spitter shot ends about one novice life in
    six, so Spitters that fire cost about half a life in wave 3. It cannot be both.
  - **A Burrow in wave 5 may be too mild:** it pours about 6 Skitters a game, down from 23.
    Whether it still feels worth destroying is yours to judge.
  - More games now end in wave 4 (28%, up from 15%).
- The harness now prints, per wave, Spitter shots, the share of games with none, Burrow
  spawns, lives at the wave's start and the share of games ending there.

### Gleaners through the wave (2026-11-21)

The last check found that in later waves the Gleaners all landed together and took most of the
colonists in the first seconds, and that a colonist beside a wall could be lost at once. You
chose to have that fixed before moving on. Commit `cfcbd8c`.

**What changed**

- **Gleaners come one at a time.** The first Gleaner of a wave lands a set time after the
  opening crowd. Each of the rest is sent once its share of the wave's Skitters has come in
  (shares spread evenly from 35% to 80% of the wave), or 8 s after the one before at the
  latest. The number of Gleaners in a wave is unchanged, and a wave still waits for all of
  them.
- **A least time to save a seized colonist.** A Gleaner that seizes a colonist close to the
  wall drags it more slowly, so that the drag always takes at least the time below; if it is
  pushed to the wall early it waits there. The pair always creeps toward the wall, so it never
  looks merely held. This replaces the slower drag speed of refinement 3.

| Gleaner wave | 2 | 4 | 7 | 9 | 10 | 11 | 12 | 13 | 14 on |
|---|---|---|---|---|---|---|---|---|---|
| First lands after the crowd, s | 10 | 9 | 8 | 6 | 4 | 2 | 1 | 0 | 0 |
| Least time from seizure to loss, s | 8 | 7 | 6 | 5.5 | 5 | 4.5 | 4 | 3.5 | 3 |

- **Spitters and Burrows ease by their own appearances**, not by wave number, like the
  Gleaners. A kind's appearances are now read from the wave makeup itself.
  - Spitters: 3 in their first wave (wave 3), 2 in their second (wave 4), then 6, 7 and 8.
    Their first shots fly at 0.8 of full speed with half the lead, easing over three
    appearances. Fire interval scale by Spitter wave: 2.0, 1.65, 0.91, 0.64, 0.58.
  - Burrows: spawn interval scale 2.0, 1.35, 0.96 over their first three waves (5, 7, 9).
- Undo: `RedoubtWaves.beforeGleanersThroughWave` restores the game before this change; the
  older switches chain from it. Harness: `BEFORE6=1`.

**Measured by the builder** (not yet independently checked)

| | Before | After |
|---|---|---|
| Novice, 600 games: mean wave | 5.21 | 5.31 (median 5) |
| Novice games over by wave 4 | 39% | 33% |
| Competent: mean wave | 9.96 | 10.22 |
| Wave 7, share of seizures in its first 10 s | 94 to 95% | 16 to 22% |
| Wave 9, competent games losing 3 or more colonists in the first 20 s | 70% | 20% |
| Shortest time from seizure to loss, any wave | 0 s | the least time above |
| Wall circler / corner camper (mean wave) | 3.45 / 7.31 | 3.53 / 7.33 |

**What it did not reach**

- The novice mean is 5.31, under the 5.4 to 5.8 I asked for, and the median is 5, not 6. The
  step in lives lost from wave 2 to wave 3 (the Spitters' debut) is 0.54, the largest.
- Colonists lost still step up between wave 7 and wave 9 (13% to 32% for the competent bot).
  The builder traced this to the orb being lost more often there, which scatters the line,
  not to the Gleaners.
- Novice Spitter shots go from 2.3 in wave 4 to 11.3 in wave 7, about five times. Easing wave
  7 further let the corner camper reach wave 7.7, so it was left.
- A lighter opening crowd looked as if it would lift the novice to about 5.4. I measured four
  settings of it on 600 games each: 5.31 (as pushed), 5.29, 5.43 and 5.38, in no order and
  each ±0.05, so the difference is within the noise. Redoubt's numbers stay as pushed.
- Nothing here has been judged on screen: how the slow creep beside a wall reads, and the
  slower first shots.

**What the independent check found** (2026-11-21, a separate checker with its own
measurements): **pass with notes.** Nothing is broken. The least time is never beaten by any
route, waves neither end early nor stall, the undo switch replays the earlier game exactly,
and no difficulty or feel test was loosened. Its numbers agree with the builder's (novice 5.32
against 5.21 before, median 5; competent 10.22 against 9.96; none of the four exploit bots
better off).

- Gleaners still landed together in waves 2 and 4: the first waits for its clock, and by then
  a quick player has already let in the others. Corrected (below).
- The 8 s fallback was counted from the wave's first Gleaner, not the one before, so a gap of
  10 s was possible. Corrected (below).
- One to three in a hundred seizures happen so close to the wall that the drag creeps at
  about 1 unit a second and looks held. Corrected (below).
- For the novice, colonists are lost later in a wave but not fewer by its end (wave 7: 39%
  before and after). For the competent bot they are fewer (wave 9: 36% to 30%).
- Lives lost in wave 2 rose slightly (0.13 to 0.17), probably because Gleaners still to come
  no longer hold places on the floor.
- Novice Spitter shots rise 5.6 times from wave 4 to wave 7 (2.4 to 13.5): the count goes
  from 2 Spitters to 6 after two waves without any. This is the steepest step left in Redoubt
  after the wave 2 to 3 step in lives lost (0.54).
- The Spitter smoothness test's bound is a little looser than before (1.45 an appearance, and
  1.81 allowed for wave 4 to 7).

**The corrections** (commit `63fcbca`, pushed the same day; not separately
checked, since each has a test that failed before it and passes after):

- **A least gap of 4 s between Gleaners** in a wave (`RedoubtWaves.gleanerLeastGap`). It is
  waived only when the Gleaners still to come are all that keeps the wave open, so a cleared
  floor never waits on them. Gleaners sharing a moment with another: 436 of 800 in wave 2
  before for the competent bot, none after, in any wave, for either bot.
- **The 8 s fallback counts from the Gleaner before.** The longest gap measured is now 8.0 s.
- **No drag slower than 8 units a second** (`RedoubtWaves.leastDragSpeed`). When the straight
  path to the wall is too short to fill the least time, the Gleaner drags its colonist along
  the wall toward its middle instead, so it keeps moving for the whole time. The least time
  is unchanged. Before, 12 to 21% of drags were slower than this and the slowest hardly moved.
- Novice mean wave, same seeds before and after: 5.21, 5.27, 5.22 before; 5.38, 5.36, 5.49
  after (about +0.18, beyond the noise), so the novice is now at about 5.4. Competent: 10.22
  to 10.12, within about 1.6 standard errors.
- Both numbers are off under `beforeGleanersThroughWave`, which still restores the earlier
  game exactly.

**Left for you to judge when you play Redoubt again** (the gate is closed on your instruction
to fix this and move on; none of these blocks Riftwing):

- How the slow drag reads on screen: a Gleaner beside a wall now slides along it with its
  colonist for several seconds.
- Whether colonists still feel taken too fast in waves 9 and later; for the novice bot they
  are lost later in the wave but not fewer by its end.
- The two steepest steps left: wave 3 (the Spitters' debut, 0.54 more lives lost than wave 2)
  and wave 7 (Spitters return in numbers: shots rise more than five times from wave 4).
- From earlier checks, still open: the main push gathers toward a corner; wave 1 never pushes
  from the north; the corner-camping bot reaches about wave 7.4; the "New: Gleaner" banner
  shows some seconds before any Gleaner.

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

## Riftwing design

Written 2026-11-21. You chose the two things that shape it most (a one-screen cavern; flap
plus a dive, no weapon) and told me to build while you were away, so I have taken that as
approval of the design below. Everything else here is my decision, marked "mine", for you to
overrule when you play. Every number is a starting value, to be tuned with bots and then by you.

### The feel

- **A duel of height and momentum.** Where Redoubt is a flood, Riftwing is a handful of
  opponents, each one a duel: four to ten on screen, never ninety. You win a clash by being
  above your opponent when you meet. Every flap spends effort to buy height, and height is
  what you fight with. The pilot skill it trains is altitude and energy.
- Riftwing is an original game in the flap-to-fly genre. It takes that genre's mechanic (flap
  to climb, the higher fighter wins) and nothing else: its cavern, cast, names, art, sounds
  and layouts are its own, and no layout is modelled on another game's.

### The place and the player

- **Arena (yours):** one fixed screen, seen from the side: a gallery in the caves of the crater
  wall. The left and right edges are tunnel mouths that join, so flying off one side brings
  you in on the other. A thin strip at the top holds the HUD (score, wave, lives, colonists).
- **Ledges (mine):** four to six rock shelves at uneven heights, never symmetrical. There are
  three layouts; the cavern shifts to the next every three waves, with a rumble and a short
  pause while the rock settles. You can land on a ledge and run along it.
- **The Rift (mine):** the bottom of the screen is the Rift, a glowing fissure with no floor
  over it. Falling into it costs a life. Two or three vents in the Rift send up columns of
  rising air: fly into one and it carries you up without flapping, so there are routes that
  save effort. Enemies use them too.
- **The roof (mine):** the cavern roof stops you; it does no harm. An opponent pressed against
  the roof beside you is level with you, so sitting at the top wins nothing.
- **You** fly a flap-wing rig: a one-person frame with two wings, small enough for caves a
  ship cannot enter. Gravity pulls you down all the time. Each flap gives a push upward and a
  little along the way you are steering. Speed carries: you glide, and you turn by leaning
  against your own momentum, not instantly.
- **Size (mine, from what you said about Redoubt):** the rig is about 5% of the screen's
  height across, and opponents are similar, so nothing is a dot.

### Controls

| Action | Touch | Gamepad |
|---|---|---|
| Steer left and right | Floating stick, left thumb | Left stick or D-pad |
| Flap | Tap anywhere on the right half; each tap is one flap | A, or either shoulder button |
| Dive | Pull the stick down and hold | Stick or D-pad down, or B |
| Pause | Pause button | Menu |

The handedness option swaps the sides. There is no weapon and no fire button (yours).

### The clash

- When you and an opponent touch, the higher one wins. If you are within a small margin of
  level, you both bounce apart and nobody is hurt.
- Win, and the opponent is knocked off its rig. Lose, and it costs you a life; you return on
  a ledge away from the fight with a moment of invulnerability.
- **The dive (yours):** hold dive to fold the wings and drop fast. A strike made while diving
  is a stoop: it scores more the farther you fell, and it beats in one blow the tougher
  opponents that otherwise take two. The risk is the commitment: the wings take a moment to
  open again, and a dive begun too low ends in the Rift.

### Rescue

- Every opponent on a rig is a Husk: a colonist the invaders have turned. Knock one off and it
  drops a pod holding that colonist.
- **Reach the pod to free the colonist.** A pod falls and comes to rest on a ledge. Catching
  it in the air, before it lands, scores double: the same skill as Ridgeline's mid-air catch.
- **A pod that falls into the Rift is lost**, so where you make the strike matters: over a
  ledge is safe, over the Rift means you must dive after it.
- **A pod left too long hatches** into a Husk one grade tougher, and that colonist is gone for
  good. Pods last a long time in the early waves and less as the waves go on (mine, from what
  you said about how fast Redoubt's colonists were taken: about 15 seconds at first, never
  under about 7).
- Freeing several in a wave scores more each time (500, 1,000, 1,500 and so on), and colonists
  freed in a wave score a bonus at its end.
- **Lamps out (mine):** lose every colonist in a wave (to the Rift, to hatching or carried
  off) and the gallery's lamps fail. The next wave is flown in the dark with a pool of light
  round you, until you free a colonist. This is Riftwing's answer to Blackout and the power
  cut.

### Opponents

Five kinds (mine), in the same cast as the other modes where it fits. Each new kind first
appears in a wave of its own, and each one's early appearances are gentler, counted in its own
appearances so that no wave is a cliff.

| Name | What it does |
|---|---|
| Glider | The first Husk rig. Slow, flaps lazily, holds height badly and wanders. One blow. |
| Striker | Hunts you: climbs to get above you, then comes down. One blow. A hatched Glider pod becomes a Striker. |
| Warden | Fast and patient. It keeps height and uses the dive as you do. Two blows, or one stoop. A hatched Striker pod becomes a Warden. |
| Gleaner | Not on a rig, and it ignores you: it flies to a pod on a ledge and carries it off into a tunnel mouth. It comes late in a wave, singly, and slowly at first. Any touch from above or level destroys it; from below it bumps you away. |
| Sower | Drifts across the gallery leaving mines that hang in the air on tethers and block the good lines. Touching a mine costs a life. Strike the Sower from above to destroy it and all its mines. |

Opponents fly in from the tunnel mouths at the sides, at a height shown by a glow in the
mouth for about a second beforehand. None arrives within a safe distance of you.

**If a wave drags on, the Rift breathes (mine):** after a long wave, gas rises from the Rift
part of the way up the gallery for a few seconds, with a warning first, and anything caught
low in it is lost. It rewards finishing the fight over hiding on a low ledge.

### Structure and scoring

- A wave ends when every opponent on a rig is down and every pod is settled (freed, lost or
  hatched and beaten). There is a short break between waves.
- Three lives, at most five, an extra one at a score threshold.
- Points for a blow by grade, a stoop bonus by the height fallen, the rising rescue score
  above, a mid-air catch doubling it, and the end-of-wave bonus for colonists freed.
- The high-score table records score, wave and colonists saved, like the other two.

### Look and sound

- The same neon vector lines on black. A side-on cavern: rock ledges in outline, the Rift
  glowing along the bottom, drifting motes showing the vents' rising air. Rigs with wings
  drawn in several poses so a flap reads as a beat. All drawn in code from a Riftwing theme.
- Its own sound patches and music on the shared synthesiser (a different key and tempo from
  the other two), and its own haptic cues: none for a flap, since it is constant; a clear cue
  for a clash won, a clash lost, a pod freed and a pod lost.

### What I will measure from the start

What Redoubt taught, applied before you play, not after:

- **A first game usually reaches wave 5 to 6.** The novice bot stands in for you; its level is
  judged on at least 600 games, because 80 proved too few to trust.
- **Rescue pacing as well as survival:** per wave, how long pods last, the share lost and how
  (the Rift, hatching, carried off), and how long you have once a Gleaner picks one up. Early
  waves lose few and slowly, and the pressure ramps.
- **No cliffs:** lives lost per wave, and each kind's threat by its own appearances, rise
  steadily.
- **Exploits tried by bots:** sitting on the top ledge, sitting under the roof, riding one
  vent forever, hiding low, and bouncing level without ever committing.

### How it is built (step 15)

The same order as Redoubt. Each stage is pushed as soon as it builds and passes its tests, and
checked independently afterwards (agreed 2026-11-21):

- **15a. Game logic:** a `RiftwingCore` target in the package (cavern and ledges, flight,
  clashes, the dive, pods, the five opponents, vents, the Rift, waves, scoring, lamps out),
  conforming to the shared run contract, with tests, scripted bots and a `riftwing` harness.
- **15b. On screen:** the Riftwing mode in the app (cavern, sprites, HUD, controls), listed on
  the title screen, with DEBUG `-mode riftwing`.
- **15c. Feedback:** sounds, music moods and haptics for every event.
- **15d. Waves and tuning:** the measurements above, tuned with the harness and pinned by
  tests.
- **15e. Polish:** particles, wing and clash effects, wave banners, the cavern shifting, the
  lamps-out lighting.

Then the gate: you play Riftwing and we refine it until you are happy to move on.

### Decisions made while building the logic (15a)

Built 2026-11-21 in `GameCore/Sources/RiftwingCore/`. The design left these open; all are
mine, and every number is in `Tuning.swift` or `WaveDirector.swift`. Harness:
`cd Tools/Harness && swift build -c release -Xswiftc -DDEBUG && .build/release/Harness riftwing 200 25 novice`.

**Gallery and rider**

- The gallery is 900 x 600 units, stepped at 120 Hz. Anything whose centre drops below
  height 20 is in the Rift and lost; the Rift takes a life even from a protected rider.
- One size factor, as in Redoubt. The rider is 30 units across (5% of the height). Gliders
  and Strikers are 28, Wardens and Sowers 30, Gleaners 22, pods and mines 18.

**Flight**

- Gravity 430; falling with the wings open is capped at 290. A flap adds 165 upward (rising
  speed capped at 250) and 45 along the steer. Steering accelerates at 300 up to 230 across;
  with no steer the rig glides and loses 30% of its speed a second. Running on a ledge: 150.
  Rigs land on ledge tops and bump their heads on the undersides.
- The dive: gravity 1,000, falling up to 600, steering at 35%. The wings take 0.25 s to
  reopen, with no flap until then. A dive starts with the stick down past 0.6, or B.

**The clash**

- Heights are compared; within 8 units both bounce apart. Against the roof every rig counts
  as the same height, so sitting at the roof beside an opponent is level.
- The winner springs up a little. A Warden takes two blows: the first makes it tumble for
  0.7 s and scores 100.
- **Added: clash leniency.** In a kind's first appearances it must be well above you (8 + 16
  units, shrinking with its ease) to win; otherwise you bounce. Winning is unchanged. This was
  the biggest single lever for gentle opening waves.
- The stoop scores 2 points per unit fallen since the dive began, in 50s, up to 1,000.

**Layouts** (original, uneven, open over the Rift)

- Terraces (waves 1 to 3, then 10 to 12): five shelves, two vents. Spur (waves 4 to 6): four
  shelves including one long one and a high bridge, three vents. Shelves (waves 7 to 9): six
  short shelves scattered high and low, two vents. A shift adds 2 s to the break.
- Vents are 52 units wide and lift rigs up to a set height. Pods ignore them. To go down
  through a vent you dive or slip out sideways.

**Pods**

- A pod falls slowly (up to 150). **Added:** a pod from a kind still in its ease falls up to
  80% more slowly; without this, 20 to 45% of early pods went into the Rift.
- Life on a ledge: 15 s in wave 1, 0.8 s less each wave, 7 s from wave 11. The hatch warning
  comes 4 s before. A hatched Glider pod becomes a Striker; everything else becomes a Warden.
  The new rig stands for 0.8 s before it flies.
- Rescue scores 500 times n for the nth in a wave, doubled for a mid-air catch, plus 250 for
  each freed when the wave ends. Destroying a Gleaner that holds a pod frees the colonist.

**Opponents** (each eased over its own first six appearances: 1, 0.7, 0.5, 0.35, 0.2, 0.1)

- **Glider:** wanders, slow, skips some flaps. Eased: slower, lower, and it will not flap up
  into a rider just above it.
- **Striker:** climbs above you, then glides down at you for up to 1.4 s, then spends 1 s
  flying off level, open to a blow. It breaks off after 3.5 s if it cannot get above (added to
  end stalemates), and hangs back below a rider at the roof. Eased: slower, climbs less,
  reaches less far, decides later, recovers for twice as long.
- **Warden:** keeps 80 above you and dives when lined up. Eased: slower and far less likely
  to dive.
- **Gleaner:** ignores you; goes to the nearest resting pod, holds it 1 s, then carries it to
  the nearer side in no less than 4 s. The first of a wave comes 22 s in at its debut (8 s
  when fully ramped), then one at a time, and only while a pod rests. Eased: half speed, a
  longer hold, a carry of at least 8 s.
- **Sower:** drifts laying a tethered mine every 3.5 s, never within 110 of you, at most four
  at once; mines time out after 18 s. Struck from above it takes its mines with it. Eased:
  fewer mines, less often.
- Arrivals glow for 1 s in a mouth and never appear within 220 of you.

**Waves**

| Wave | Sent |
|---|---|
| 1 | 4 Gliders |
| 2 | 5 Gliders |
| 3 | 3 Gliders, 2 Strikers (Striker debut) |
| 4 | 2 Gliders, 3 Strikers, 1 Gleaner (Gleaner debut) |
| 5 | 3 Gliders, 3 Strikers, 1 Gleaner |
| 6 | 2 Gliders, 2 Strikers, 1 Warden, 1 Gleaner (Warden debut) |
| 7 | 2 Gliders, 3 Strikers, 1 Warden, 1 Gleaner |
| 8 | 2 Gliders, 3 Strikers, 1 Warden, 1 Sower, 1 Gleaner (Sower debut) |
| 9 | 2 Gliders, 3 Strikers, 2 Wardens, 1 Gleaner |
| 10 | 2 Gliders, 3 Strikers, 2 Wardens, 1 Sower, 2 Gleaners |
| 11 on | grows to at most 5 Strikers, 4 Wardens, 2 Sowers, 3 Gleaners |

- Two rigs fly at once in waves 1 and 2, rising to six by wave 12. A debut wave is not a wave
  of the new kind alone, as the design said; it adds the new kind to a smaller mix.
- Blows score: Glider 250, Striker 500, Warden 750, Gleaner 300, Sower 600. An extra life
  every 35,000. Respawn after 1.5 s on the ledge farthest from danger, protected for 2.5 s.

**The Rift's breath**

- The first warning comes 50 s into a wave: 3 s of warning, then the gas rises for 1 s, holds
  for 3 s and falls. It repeats 15 s later.
- **Added: it grows.** The first breath reaches a little under a third of the way up; each
  later one in the same wave reaches about a third of the gallery higher, up to the roof. This
  is what ends every stall: before it, a bot hovering under the roof lived over 1,000 s.
- Anything under the gas is lost: the rider, opponents (no pod, no points) and pods.

**Lamps out:** a wave that dropped at least one pod and freed none puts the lamps out from
the next wave's start until a colonist is freed.

**Measured** (harness, novice on three sets of 200 seeds)

- Novice: mean wave 5.50 to 5.59 (±0.10), median 5 or 6, about 218 s. Lives lost per wave,
  waves 1 to 7: 0.10, 0.27, 0.53, 0.98, 1.29, 1.19, 1.74. Share of pods lost per wave: 4%,
  11%, 11%, 12%, 16%, 19%, 19%.
- Competent: mean wave 10.3, median 10, 401 s.
- Exploit bots, 200 seeds each, against the competent bot's 401 s and 24,150 points a minute:
  top-ledge sitter 229 s and 1,110; roof hoverer 253 s and 42; vent rider 183 s and 1,680;
  low hider 79 s and 1,520; level bouncer 184 s and 5,230. A test pins all five.

**Known weak points, for the tuning stage (15d) and for you**

- Rescue pressure is weak. The bots reach a pod about half a second after it lands, so
  hatching and Gleaners hardly bite: nearly every lost pod is lost to the Rift. A person will
  be slower, so these may matter more in real play than the numbers show.
- Lamps out never happens to the novice or competent bot by play.
- Wave 5 ends the largest share of novice games (26 to 30%), and lives lost dip in wave 6.
- The novice bot was improved while tuning (it routes round ledges, leads a moving opponent,
  waits instead of chasing upward). How close it is to a first-time person is reasoned, not
  measured; the independent check is asked to judge it.
- Simplifications: opponents pass through one another; Gleaners fly through ledges; pods
  ignore vents.

### What the independent check of the logic found (15a)

Checked 2026-11-21 by a separate checker given the code and this design, not the builder's
conclusions. Verdict: **pass with notes.** The rules mostly match the design, debug and
release builds agree, and its own measurements match the builder's (novice 5.58 over 600
games, median 6; competent about 10.5; no exploit bot near proper play). It found these, all
being fixed in the tuning stage (15d):

- **A rider standing still when the cavern shifts can fall into the Rift** during the break,
  from three ledges, with under a second to react. The bots never stand still, so the harness
  missed it.
- **About half of all mid-air catches happen by themselves:** the pod appears within reach of
  the rider who struck, and is caught a step later for double points.
- **Score and events after game over:** if the last life goes in the step the wave clears, the
  wave bonus is added after the game-over score is announced.
- **The third breath of a wave reaches the roof and cannot be escaped,** about 100 s into any
  wave, and the first warning comes 50 s into even wave 1. The design said "part of the way
  up". A respawn while every ledge is under the gas dies again.
- **Hovering pressed under a ledge can never lose a clash,** and hovering at the side join
  stops anything arriving. Only the breath ends either.
- **The novice bot flies far better than a person:** frame-perfect flapping, exact routing
  round ledges, and none of about 2,400 lives lost to the Rift. The checker expects a person's
  first game to end around wave 3 to 4 on these numbers, not 5 to 6. Pods are freed half a
  second after landing, so hatching and Gleaners are hardly tested.
- A Glider's pod can hatch into a Striker before the Strikers' debut wave.
- Weak tests: the difficulty tests use 12 seeds and a wide band; two tests pass by luck of
  their seed or check a number and not the behaviour.

**My decisions from it (mine, for you to overrule):**

- The novice bot is being remade to fly like a person (late reactions, a human tapping rate,
  misjudged heights, falls into the Rift), and the game tuned until that bot reaches wave 5 to
  6. This will make Riftwing easier than the numbers above describe.
- The breath starts later in early waves (about 90 s in waves 1 and 2), grows over more steps
  that can each be flown above, and fills the gallery only on its last step, with its own
  warning. That last step stays, as the answer of last resort to hiding; it goes against the
  design's "part of the way up", so say if you would sooner have a breath that can always be
  survived.
- No place where a rider can sit safe from clashes: a rig will not be able to cling to the
  roof or the underside of a ledge.
- Until a tougher kind has had its debut, a pod hatches into its own kind.
- The bar for exploit bots is now "reaches no wave near the novice's, scores less, and cannot
  survive without limit", in place of "survives less long than proper play".

**For you to judge, on originality.** The checker noted that, taken together, several of
Riftwing's rules resemble one well-known flap-to-fly game more than "the genre's mechanic and
nothing else" suggests: a knocked-off opponent leaving something that turns into a tougher one
if left, a collection score that rises through the wave with a bonus for a mid-air catch,
opponent grades, and a threat that comes when a wave drags on. The cavern, cast, names, art,
layouts, the dive, vents, Gleaners, mines, lamps out and the rescue story are Rimwatch's own.
I have kept the design as you approved it. If you want more distance, the cheapest change is
to drop hatching into a tougher grade (a pod left too long is simply lost, or draws a
Gleaner).

### Decisions made while putting it on screen (15b)

Built 2026-11-21 in `Rimwatch/Modes/Riftwing/`, with the look in a `RiftwingTheme`
(`GameCore/Sources/RiftwingCore/Theme.swift`). The shell did not change. All of these are mine.

- **Size:** every figure is drawn at the size it collides at. The rig is 30 units across, 5%
  of the gallery's height (about 17 points on an iPhone 18 Pro, where the gallery is 345
  points high). It reads as a winged frame but is still small; this is the first thing to
  judge on the Duo.
- **Colours:** the rider is cyan and pods are mint, as the Watch and colonists are in the
  other modes. Glider magenta, Striker red, Warden violet, Gleaner yellow, Sower orange, mines
  pink, rock grey-blue, the Rift orange, the gas yellow-green.
- **Shapes:** every rig is a side-on frame with two wings, the far wing dimmer. The Glider has
  broad drooping wings; the Striker narrow swept wings and a nose spike; the Warden an armour
  plate and crest, which it loses after one blow; the Sower a seed sac underneath. The Gleaner
  is not a rig: a round drone with a hanging claw.
- **The wing beat:** swept down just after a flap, raised, then spread; folded in a dive;
  perched or striding on a ledge. The rig tilts with its climb or fall.
- **States:** a protected rider strobes in a shield ring; a Warden that took a blow spins; a
  hatched rig grows from half size before it flies; a held pod flashes red on a line to its
  Gleaner; a pod near hatching turns red and flashes faster, and shows through the dark.
- **Arrivals:** a glow in the kind's colour at the mouth with two chevrons pointing in.
- **The breath:** the Rift pulses and a dashed line blinks where the gas will reach, with the
  notice "THE RIFT IS BREATHING. CLIMB!"; then a band of gas rises, holds and sinks.
- **Lamps out:** darkness with a pool of light round the rider. The Rift's edge, pods near
  hatching, the gas and arrival glows show through.
- **The cavern shift:** a shake and falling rock, then a cross-fade to the new ledges.
- **The side join:** anything overlapping an edge is drawn on both sides.
- **HUD:** score and wave on the left; lives (as small rigs) and colonists saved on the right.
- **Touch:** the stick steers in its half; each tap in the other half is one flap (taps never
  merge; at most two are queued); pulling the stick down past 0.6 dives, and a chevron under
  the stick lights while diving. The handedness option swaps the halves.
- **Bots in the app:** `-autopilot` takes `idle`, `novice`, `competent` and the exploit bots
  by name; `shooter` flies the competent bot. The bot is asked once for each step, so it flies
  in the app as it does in the harness.
- **Not in this stage:** no sound, music or haptics (15c). Callouts are Redoubt's pattern and
  can overlap the rider.
- **Not checked:** touch input (no tap could be made from the command line), a dive on the
  gamepad seen in a screenshot, sizes on any screen but the iPhone 18 Pro.

### Decisions made for sound, music and haptics (15c)

Built 2026-11-21 (`GameCore/Sources/RiftwingCore/Themes/RiftCavesSounds.swift`, `Audio/`).
All mine. **Nobody has heard any of it:** every patch was rendered and measured (level,
clipping, clicks, length, loss on a small speaker, how far each differs from the others), and
the app's log was read to confirm each cue fires on its event. How it sounds is yours to judge.

- **The flap** is the quietest sound in the game: a 68 ms puff of air in three pitches, never
  the same twice running. A flap from a ledge is a scuff and a fuller beat.
- **Clashes:** a crack and a bright struck fifth for a clash won; a stoop adds a low boom and
  a chord struck down from high, in four sizes by how far you fell; a hard crunch and a
  dissonant stab for a clash lost.
- **Pods:** a two-note call when one drops; a chime when freed that climbs a scale with each
  rescue in the wave; a quick sparkling climb for a mid-air catch; a shrill trill when a
  Gleaner seizes one; three falling pings for the hatch warning; three sinking notes for a pod
  lost.
- **Alerts:** the Rift's warning is a deep breath drawn in under a pulsing alarm, the loudest
  warning; the gas is a swelling hiss; lamps failing is the hum guttering out; the cavern
  shift is a rumble and rockfall, held back half a second so the wave-cleared sting is heard.
- **Left silent on purpose:** an opponent arriving (the glow already warned), wings fully
  open, mines cleared by the wave ending, a mine struck (the life lost covers it).
- **Rules for what plays:** one sound per kind of event per frame; at most four sounds a
  frame; flaps on one voice; small sounds held for a quarter-second after an urgent cue; the
  urgent cues (clash lost, rider lost, pod lost or seized, hatch warning, the Rift's warning,
  lamps failing, game over) are never refused. In bot games every urgent cue was voiced.
- **Music:** E Lydian at 96 beats a minute (Ridgeline is A minor at 84, Redoubt G Phrygian at
  104), with a pulse in threes like a wingbeat during a wave, calm in the breaks, and a low
  drone while the lamps are out.
- **Haptics:** none for a flap or any of flight. A tap for a clash won, an impact for a stoop,
  a rumble for a clash lost, a double tap for a pod freed, an impact for a pod lost, a warning
  knock for a pod seized, the hatch warning and the Rift's warning, a rumble for the cavern
  shift, lamps failing and game over.
- **Not confirmed in the app, only in package tests:** the hatch warning, a pod seized and
  carried, hatching, mines and game over (the bots free pods too fast for these to come up).
- Events added after this stage (such as a separate warning for the breath's last step) are
  silent and unfelt until given a cue; that is for the polish stage (15e).

### What the independent check of screen and sound found (15b and 15c)

Checked 2026-11-21 by a separate checker given the code and this design. Verdict: **pass with
notes.** Nothing blocks the stage. It confirmed, by doing it, that adding the third mode loses
nothing saved: high scores and options saved by the build before Riftwing were all still there
afterwards. Two runs of the same seed gave identical logs, the node count stayed flat over a
five-minute run, and a simulated gamepad flew, dived and paused correctly. Touch was checked by
reading the code only: one tap is exactly one flap in every case it could think of. Found,
and being fixed in the polish stage (15e):

- **Gas from a finished run stays on the title screen** if the game ended while it was up
  (seen); the lamps-out darkness has the same fault by the code.
- **The synthesiser can still drop an urgent cue** if two of the same kind come within a
  quarter to half a second (two pods lost almost together give one sound). It did not happen
  in bot games.
- **Bursts and the lamps-out light do not cross the side join,** though figures do.
- Small: effects keep moving on the pause screen; a touch the system cancels still flaps; a
  tap while the rider is down is used up.
- Weak tests: the list of events the sound tests walk is written by hand; the colour test only
  requires colours to differ at all (the Striker's red is close to the warning red and the
  mines' pink).

Its opinions on the look, also given to the polish stage: figures are the right size but read
small next to their glow; with the lamps out, threats outside the pool of light are nearly
invisible; the touch controls at rest sit over the lowest ledges although the screen has wide
black margins beside the gallery.

### Fixes and tuning (15d)

Built 2026-11-21, after the check of the logic. All mine. Commits `604e67a`, `c294c95` and
`8e79833`. This replaces several numbers in "Decisions made while building the logic (15a)";
where the two disagree, this section is the game as it is.

**The defects, fixed** (each with a test that failed first)

- **The cavern shift** never costs a life. Whoever is standing is put on the nearest ledge of
  the new cavern; whoever is flying is moved clear of any rock.
- **A mid-air catch needs pursuit.** A knocked pod is thrown clear and cannot be taken for
  0.4 s. Catches within 0.4 s of the drop fell from 54% to none; about a third of pods are
  still caught in the air.
- **Nothing happens after game over,** so the score announced is the final score.
- **A respawn is never lost to gas already in the gallery.**
- **Camping the side join no longer stops arrivals:** after 2.5 s with no clear mouth, one
  comes anyway at the farthest place, after a 2 s glow.
- **A pod hatches into its own kind** until the tougher kind has had its debut.

**The novice bot now flies like a person.** It sees the world a quarter of a second late, taps
at a human rate, misjudges heights, bumps ledges and falls into the Rift: 15% of its lives go
to the Rift (the old one lost none in 2,400), and pods lie about 4 s before it reaches them
(the old one took half a second). The old bot is kept as `sharpNovice`; on the retuned game it
reaches wave 10, which shows how much easier the game now is.

**The game, retuned to that bot**

| | Novice (3 x 200 games) |
|---|---|
| Mean wave | 5.52, 5.63, 5.62 |
| Median | 6 |
| Games ending in waves 1 to 7 | 0.2%, 2%, 7%, 12%, 23.5%, 27.5%, 21% |
| Lives lost per wave, waves 1 to 7 | 0.2, 0.35, 0.45, 0.8, 1.2, 1.4, 2.0 |
| Colonists lost per wave, waves 1 to 7 | 3%, 7%, 9%, 11%, 16%, 23%, 29% |

Lives go to: Strikers 57%, the Rift 15%, Gliders 12%, the breath 13%, Wardens 3%, mines 1%.
Colonists are now lost to hatching and Gleaners as well as the Rift, as the design meant. The
competent bot reaches wave 10.1.

What was changed to get there:

- **The clash is more forgiving.** You bounce when within 11 units of level (was 8). To beat
  you an opponent must be almost squarely on top (more than 27 units above, where contact
  comes at about 29).
- **Early opponents misjudge.** In a kind's early appearances, an opponent that would have won
  a clash sometimes misjudges it and you both bounce: always at its debut, never once it is at
  full strength, fading over twelve appearances. This is a seeded chance, so the same game
  replays the same way. Say if you would sooner have a rule with no chance in it.
- **A bounce is level:** it no longer throws either rig up or down.
- **Pods are kinder early.** They last 20 s in wave 1 (was 15), 1.2 s less each wave, never
  under 7 s. A pod from a kind still in its ease falls slowly, drifts toward a ledge it can
  land on, and hangs above the Rift for up to 5 s before it falls in.
- **Waves:** wave 5 sends 2 Gliders (was 3); wave 6 sends 3 Strikers (was 2).

**The breath, fairer**

- The first warning comes 90 s into waves 1 and 2, easing to 50 s by wave 7 (was 50 s in
  every wave). It repeats every 18 s.
- It rises in four low steps (to about a fifth, a third, under a half and over a half of the
  gallery's height), each of which can be flown above. Only the fifth fills the gallery, after
  its own 5 s warning ("THE RIFT ERUPTS"); then the cycle starts again. Opponents shelter from
  the fill.
- For the human-like novice, waves take 55 to 120 s, so a low step or two comes in most waves
  from wave 3 on, and the fill takes 5% of its lives.

**No safe place**

- **No clinging to a ceiling.** Flying up into the roof or the underside of a ledge knocks a
  rig downward.
- **A rider pinned against rock for 1.5 s is hunted** there: Strikers and Wardens come up
  under the same rock.
- **A rider who stays within a small area for 6 s draws the Gliders,** and gets none of the
  early leniency.
- Exploit bots, 200 games each, against the novice's wave 5.5 and 7,150 points a minute:

| Bot | Mean wave | Points a minute |
|---|---|---|
| Bouncing level, never committing | 4.3 | 3,160 |
| Hiding, coming out only to strike below | 3.0 | 1,360 |
| Hovering under the highest ledge | 2.6 | 1,650 |
| Sitting on the top ledge | 1.6 | 1,520 |
| Hovering under the roof | 1.5 | 320 |
| Riding one vent | 1.3 | 1,250 |
| Camping the side join | 1.2 | 430 |
| Hiding low | 1.0 | 960 |

None survives without limit, and they now die to clashes more than to the breath.

**Not met, or borderline**

- **Lives lost in waves 1 and 2 are 0.5 to 0.7 a game,** higher than the old bot's 0.3: about
  0.4 of it is the human-like novice falling into the Rift while it learns nothing. A person
  learns; watch whether the first two waves feel fair.
- **The level bouncer** reaches wave 4.3, about 1.3 short of the novice: inside the bar I set
  (one wave), but the closest of the exploits.
- **Standing still for 6 s draws the Gliders.** That may be harsh on a person pausing on a
  ledge to think; it is the first number I would relax.
- A forced arrival can appear as close as 107 units to the rider (the safe distance is 220).
- How the knock from a ceiling, the hunting of a camper and the misjudged clashes feel has
  only been reasoned. Nobody has played it.
- Design lines above that this changes: a debut wave no longer sends a smaller mix (wave 6);
  Gliders do pay attention to a rider who camps; opponents are not lost to the fill.

### What the independent check of the fixes and tuning found (15d)

Checked 2026-11-22 by a separate checker with its own measurements. Verdict: **pass with
notes.** The six fixes work by every route it tried, debug and release agree, and its numbers
match the builder's: novice 5.59 to 5.75 over 600 games, median 6; competent 10.5; no exploit
bot near the novice. It found these, all in a second round of corrections now being built:

- **Pods fall through ledges.** The sideways drift given to early pods can carry one into the
  side of a ledge, and it then drops through the rock. About a third of all pods lost to the
  Rift are lost this way.
- **The rule against clinging to a ceiling punishes holding height under the roof.** Flying
  within 30 units of the roof for 1.5 s counted as camping, and a camper lost a clash to
  anything 2 units above it. The competent bot spent a fifth of its fighting time in that
  state, and 83% of its lost clashes happened there.
- **Standing still is punished too hard.** A bot that does nothing loses all three lives to
  wave-1 Gliders in 48 s (102 s before). A novice that rests on ledges for a few seconds
  drops from wave 5.6 to 5.2. The count also runs through the break between waves.
- **Each kind's threat steps up at its second appearance,** because in its first it can never
  win a clash (lives lost per Striker: 0.01, then 0.20).
- **Two exploit bots never did what they were named for:** the top-ledge sitter and the
  ambusher hovered under the top ledge. The checker's own bots that do reach it are far below
  the bar (wave 1.0 standing or pacing; 3.2 pacing and stooping).
- **The difficulty tests are close to luck on their seeds,** and four of their bounds were
  loosened by the last change.
- **The novice bot:** it has lapses low over the Rift that a person would stop having within
  a minute, and it ignores mines; against that, it still aims and times its flaps exactly. The
  checker's estimate for a person's first game on these numbers is wave 4.5 to 5.5, about
  half a wave under the bot, more if the person rests on ledges or holds height near the roof
  (the two habits the faults above punish).

**My decisions from it (mine):** resting on a ledge is not camping (a much longer time,
generous in early waves, not counted in the break or while protected); being pinned or camping
never changes the clash rule against you, it only draws opponents and removes the beginner's
leniency; "pinned" means pressed against rock, not flying near it; a kind may win a little in
its first wave so that its threat ramps.
