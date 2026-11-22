import Testing
import GameCore
@testable import RiftwingCore

/// The gamepad mapping, and how Riftwing plugs into the shared session and screen flow.
@Suite struct RiftwingPadTests {
    @Test func theStickOrDpadSteersAndDownDives() throws {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0.7, 0)))
        let input = RiftwingInput(pad: reader)
        #expect(input.stick == PadMapping.move(reader.current))
        #expect(input.steer > 0.6)
        #expect(!input.flap)
        #expect(!input.wantsDive(RiftwingTuning()))
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(RiftwingInput(pad: reader).wantsDive(RiftwingTuning()))
    }

    @Test func aOrEitherShoulderFlapsAndBDives() throws {
        for button in [PadButton.a, .leftShoulder, .rightShoulder] {
            var reader = PadReader()
            reader.receive(PadSnapshot(buttons: [button]))
            let input = RiftwingInput(pad: reader)
            #expect(input.flap)
            #expect(!input.dive)
        }
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.b]))
        #expect(RiftwingInput(pad: reader).dive)
        #expect(!RiftwingInput(pad: reader).flap)
        var others = PadReader()
        others.receive(PadSnapshot(buttons: [.x, .y, .leftTrigger, .rightTrigger]))
        #expect(RiftwingInput(pad: others) == RiftwingInput())
    }

    @Test func aTapBetweenStepsIsStillOneFlapAndAHeldButtonFromTheMenuIsNot() throws {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.a]))
        reader.receive(.neutral)
        #expect(RiftwingInput(pad: reader).flap)
        reader.consumePlayPresses()
        #expect(!RiftwingInput(pad: reader).flap)

        var menu = PadReader()
        menu.receive(PadSnapshot(buttons: [.a]))
        menu.suppressHeldButtons()
        #expect(!RiftwingInput(pad: menu).flap)
    }
}

@Suite struct RiftwingModeTests {
    @Test func theModeIsCalledRiftwing() throws {
        #expect(ModeDescriptor.riftwing.id == ModeID(rawValue: "riftwing"))
        #expect(ModeDescriptor.riftwing.displayName == "Riftwing")
        #expect(!ModeDescriptor.riftwing.summary.isEmpty)
        #expect(ModeDescriptor.riftwing.optionRows == [.soundVolume, .musicVolume, .haptics, .handedness])
        #expect(SettingsKeys.highScores(ModeDescriptor.riftwing.id) == "rimwatch.highScores.riftwing.v1")
    }

    @Test func itsOptionsMenuHasNoGamepadLayout() throws {
        var fe = RiftwingFrontEnd(session: RiftwingSession(seed: 1), pose: .open,
                                  catalog: ModeCatalog(modes: [.riftwing], loaded: "riftwing"))
        fe.perform(.options)
        #expect(fe.menu?.items.map(\.title) == ["Sound", "Music", "Haptics", "Stick side", "Back"])
    }

    @Test func theResultIsScoreWaveAndColonistsSaved() throws {
        var r = quietRun()
        r.addScore(1234)
        r.wave = 4
        r.colonistsSaved = 9
        #expect(r.result == RunResult(score: 1234, wave: 4, saved: 9))
        #expect(r.ending == nil)
    }

    /// Free Play runs never end with the goal met: only by defeat.
    @Test func aRunEndsOnlyInDefeat() throws {
        var r = quietRun()
        r.rider.lives = 1
        r.placeRider(at: Vec2(520, 40))
        run(&r, steps: seconds(1))
        #expect(r.ending == .defeated)
        #expect(r.ending != .goalMet)
    }

    @Test func theSharedInitialiserBuildsTheSameRun() throws {
        var tuning = RiftwingTuning()
        tuning.gravity = 400
        var a = RiftwingRun(seed: 9, config: RiftwingRun.Config(tuning: tuning))
        var b = RiftwingRun(seed: 9, tuning: tuning)
        for _ in 0..<seconds(5) {
            #expect(a.step(flapPress) == b.step(flapPress))
        }
        let session = RiftwingSession(seed: 2, tuning: tuning)
        #expect(session.tuning.gravity == 400)
        #expect(session.run.tuning.gravity == 400)
        #expect(RiftwingRun.timeStep == 1.0 / 120.0)
    }

    @Test func aSessionPausesResumesThroughTheCountdownAndEndsInGameOver() throws {
        var fe = RiftwingFrontEnd(session: RiftwingSession(seed: 4), pose: .open,
                                  catalog: ModeCatalog(modes: [.riftwing], loaded: "riftwing"))
        #expect(fe.perform(.play) == [.newRun])
        #expect(fe.screen == .playing)
        var events: [RiftwingEvent] = []
        for _ in 0..<120 { events += fe.update(elapsed: 1.0 / 60, input: still).events }
        #expect(events.contains { if case .waveStarted = $0 { true } else { false } })
        let tick = fe.session.run.tick
        #expect(tick == 240)

        // Closing the phone pauses; nothing steps while paused.
        fe.setPose(.closed)
        #expect(fe.screen == .paused)
        _ = fe.update(elapsed: 1, input: still)
        #expect(fe.session.run.tick == tick)
        #expect(fe.perform(.resume).isEmpty)
        #expect(fe.screen == .paused)
        fe.setPose(.open)
        fe.perform(.resume)
        guard case .countdown = fe.screen else {
            Issue.record("expected the countdown")
            return
        }
        for _ in 0..<200 { _ = fe.update(elapsed: 1.0 / 60, input: still) }
        #expect(fe.screen == .playing)
        #expect(fe.session.run.tick > tick)

        // A rider that never flaps is lost; the run is recorded in the table (a run that scored).
        fe.session.run.addScore(1250)
        var effects: [FlowEffect] = []
        for _ in 0..<(60 * 600) {
            let result = fe.update(elapsed: 1.0 / 60, input: still)
            effects += result.effects
            if case .gameOver = fe.screen { break }
        }
        guard case .gameOver(let score) = fe.screen else {
            Issue.record("the run should have ended")
            return
        }
        #expect(fe.session.lastEnding == .defeated)
        #expect(fe.session.lastResult == fe.session.run.result)
        #expect(effects.contains(.highScoresChanged))
        #expect(fe.lastRank == 0)
        #expect(score == 1250)
        #expect(fe.highScores.entries.first?.score == score)
        #expect(fe.menu?.lines.contains("Colonists saved \(fe.session.run.colonistsSaved)") == true)
    }

    @Test func startOverBeginsAFreshRunAtWaveOne() throws {
        var fe = RiftwingFrontEnd(session: RiftwingSession(seed: 4), pose: .open)
        fe.perform(.play)
        for _ in 0..<300 { _ = fe.update(elapsed: 1.0 / 60, input: still) }
        #expect(fe.session.run.wave == 1)
        fe.requestPause()
        #expect(fe.perform(.startOver) == [.newRun])
        #expect(fe.session.run.wave == 0)
        #expect(fe.session.run.tick == 0)
        #expect(fe.screen == .paused)
    }
}
