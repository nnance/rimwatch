import Testing
import GameCore
@testable import RidgelineCore

/// How Ridgeline plugs into the shared session: its run's result and ending, its id, and the look
/// its theme gives the shared screens.
@Suite struct RidgelineModeTests {
    @Test func theResultReadsScoreWaveAndColonistsSaved() {
        var sim = quietSimulation()
        sim.addScore(1250)
        sim.wave = 4
        sim.colonistsSaved = 3
        #expect(sim.result == RunResult(score: sim.score, wave: 4, saved: 3))
        #expect(sim.score == 1250)
    }

    @Test func theRunEndsInDefeatOnlyAtGameOver() {
        var sim = quietSimulation()
        #expect(sim.ending == nil)
        sim.player.lives = 1
        sim.addEnemy(kind: .husk, at: sim.player.pos, state: .hunting)
        run(&sim, maxSteps: 60, until: \.isGameOver)
        #expect(sim.isGameOver)
        #expect(sim.ending == .defeated)
    }

    @Test func theSharedInitialiserBuildsTheSameRun() {
        var tuning = Tuning()
        tuning.maxSpeed = 500
        var a = Simulation(seed: 11, config: tuning)
        var b = Simulation(seed: 11, tuning: tuning)
        #expect(a.tuning.maxSpeed == 500)
        for _ in 0..<600 {
            #expect(a.step(InputState()) == b.step(InputState()))
        }
        #expect(a.result == b.result)
    }

    @Test func theSessionStillSpeaksRidgeline() {
        var tuning = Tuning()
        tuning.maxLives = 5
        let session = GameSession(seed: 3, tuning: tuning)
        #expect(session.tuning.maxLives == 5)
        #expect(session.config.maxLives == 5)
        #expect(session.simulation.tuning.maxLives == 5)
        #expect(Simulation.timeStep == 1.0 / 120)
    }

    @Test func theModeIsCalledRidgeline() {
        #expect(ModeDescriptor.ridgeline.id == ModeID(rawValue: "ridgeline"))
        #expect(ModeDescriptor.ridgeline.displayName == "Ridgeline")
        #expect(SettingsKeys.highScores(ModeDescriptor.ridgeline.id) == "rimwatch.highScores.ridgeline.v1")
        #expect(ModeDescriptor.ridgeline.summary == "Rescue patrol over the crater")
    }

    @Test func ridgelinesOptionsMenuKeepsEveryRowInItsOrder() {
        #expect(ModeDescriptor.ridgeline.optionRows == OptionKey.allCases)
        var fe = FrontEnd(session: GameSession(seed: 1), pose: .open,
                          catalog: ModeCatalog(modes: [.ridgeline], loaded: "ridgeline"))
        fe.perform(.options)
        #expect(fe.menu?.items.map(\.title) == ["Sound", "Music", "Haptics", "Stick side", "Gamepad", "Back"])
    }

    @Test func theRightStickShouldersAndTriggersDoNothingInRidgeline() {
        var reader = PadReader()
        let quiet = reader.input(layout: .standard)
        reader.receive(PadSnapshot(buttons: [.leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger],
                                   rightStick: Vec2(1, 0)))
        for layout in GameOptions.GamepadLayout.allCases {
            #expect(reader.input(layout: layout) == quiet)
        }
    }

    @Test func theShipsHullIsTheEmblemsArrowhead() {
        let ship = AlienFrontier().shape(for: .player)
        #expect(ship.scale == 18)
        #expect(ship.strokes.count == 3)
        #expect(ship.strokes[0].points == Emblem.shipHull)
        #expect(ship.strokes[0].closed)
        #expect(ship.strokes[0].color == Emblem.ship.color)
    }

    @Test func theShellStyleComesFromTheTheme() {
        let theme = AlienFrontier()
        let style = theme.shellStyle
        #expect(style.background == theme.palette.background)
        #expect(style.text == theme.palette.hud)
        #expect(style.highlight == theme.palette.falling)
        #expect(style.heading == theme.terrain.ridge)
        #expect(style.controls == theme.palette.controls)
        #expect(style.menuSounds.count == MenuSound.allCases.count)
        for sound in MenuSound.allCases {
            #expect(style.menuSounds[sound] == theme.menuSound(sound))
        }
    }
}
