import Testing
import GameCore
@testable import RedoubtCore

/// The gamepad mapping, and how Redoubt plugs into the shared session and screen flow.
@Suite struct RedoubtPadTests {
    @Test func theLeftStickOrDpadMovesAndTheRightStickAims() throws {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0.7, 0), rightStick: Vec2(0, -1)))
        let input = RedoubtInput(pad: reader)
        #expect(input.move == PadMapping.move(reader.current))
        #expect(input.move.x > 0.6)
        #expect(input.aim == reader.rightStick)
        #expect(abs(input.aim.y + 1) < 1e-9)
        #expect(!input.shockwave)
        reader.receive(PadSnapshot(dpad: Vec2(-1, 1)))
        let dpad = RedoubtInput(pad: reader)
        #expect(dpad.move.x < -0.7 && dpad.move.y > 0.7)
        #expect(dpad.aim == .zero)
    }

    @Test func theRightStickHasADeadZoneSoARestingThumbDoesNotFire() throws {
        var reader = PadReader()
        reader.receive(PadSnapshot(rightStick: Vec2(0.12, 0.1)))
        #expect(RedoubtInput(pad: reader).aim == .zero)
        var r = quietRun()
        let events = run(&r, steps: seconds(1), input: RedoubtInput(pad: reader))
        #expect(count(events, "orbFired") == 0)
    }

    @Test func eitherShoulderSendsAShockwaveAndNothingElseDoes() throws {
        for button in [PadButton.leftShoulder, .rightShoulder] {
            var reader = PadReader()
            reader.receive(PadSnapshot(buttons: [button]))
            #expect(RedoubtInput(pad: reader).shockwave)
        }
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.a, .b, .x, .y, .leftTrigger, .rightTrigger]))
        #expect(RedoubtInput(pad: reader) == RedoubtInput())
    }

    @Test func aTapBetweenStepsIsStillSeenAndAHeldShoulderFromTheMenuIsNot() throws {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.rightShoulder]))
        reader.receive(.neutral)
        #expect(RedoubtInput(pad: reader).shockwave)
        reader.consumePlayPresses()
        #expect(!RedoubtInput(pad: reader).shockwave)

        var menu = PadReader()
        menu.receive(PadSnapshot(buttons: [.leftShoulder]))
        menu.suppressHeldButtons()
        #expect(!RedoubtInput(pad: menu).shockwave)
    }
}

@Suite struct RedoubtModeTests {
    @Test func theModeIsCalledRedoubt() throws {
        #expect(ModeDescriptor.redoubt.id == ModeID(rawValue: "redoubt"))
        #expect(ModeDescriptor.redoubt.displayName == "Redoubt")
        #expect(!ModeDescriptor.redoubt.summary.isEmpty)
        #expect(ModeDescriptor.redoubt.optionRows == [.soundVolume, .musicVolume, .haptics, .handedness])
        #expect(SettingsKeys.highScores(ModeDescriptor.redoubt.id) == "rimwatch.highScores.redoubt.v1")
    }

    @Test func itsOptionsMenuHasNoGamepadLayout() throws {
        var fe = RedoubtFrontEnd(session: RedoubtSession(seed: 1), pose: .open,
                                 catalog: ModeCatalog(modes: [.redoubt], loaded: "redoubt"))
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

    @Test func theSharedInitialiserBuildsTheSameRun() throws {
        var tuning = RedoubtTuning()
        tuning.orbMaxSpeed = 250
        var a = RedoubtRun(seed: 9, config: tuning)
        var b = RedoubtRun(seed: 9, tuning: tuning)
        for _ in 0..<seconds(5) {
            #expect(a.step(still) == b.step(still))
        }
        let session = RedoubtSession(seed: 2, tuning: tuning)
        #expect(session.tuning.orbMaxSpeed == 250)
        #expect(session.run.tuning.orbMaxSpeed == 250)
    }

    @Test func aSessionPausesResumesThroughTheCountdownAndEndsInGameOver() throws {
        var fe = RedoubtFrontEnd(session: RedoubtSession(seed: 4), pose: .open,
                                 catalog: ModeCatalog(modes: [.redoubt], loaded: "redoubt"))
        #expect(fe.perform(.play) == [.newRun])
        #expect(fe.screen == .playing)
        var events: [RedoubtEvent] = []
        for _ in 0..<120 { events += fe.update(elapsed: 1.0 / 60, input: still).events }
        #expect(events.contains { $0.isWaveStarted })
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

        // An idle orb is overrun; the run is recorded in the table (a run that scored).
        fe.session.run.addScore(1250)
        var effects: [FlowEffect] = []
        for _ in 0..<(60 * 60) {
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
        #expect(fe.highScores.entries.first?.wave == 1)
        #expect(fe.menu?.lines.contains("Colonists saved \(fe.session.run.colonistsSaved)") == true)
    }

    @Test func startOverBeginsAFreshRunAtWaveOne() throws {
        var fe = RedoubtFrontEnd(session: RedoubtSession(seed: 4), pose: .open)
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
