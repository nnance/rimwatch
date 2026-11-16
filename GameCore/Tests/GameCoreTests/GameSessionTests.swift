import Testing
@testable import GameCore

private let frame = Simulation.timeStep

@Suite struct GameSessionTests {
    @Test func startsOnTheTitleScreenAndPlaysOnRequest() {
        var session = GameSession(seed: 1)
        #expect(session.phase == .title)
        #expect(session.update(elapsed: 1, input: idle).isEmpty)
        #expect(session.simulation.tick == 0)

        #expect(session.startGame() == true)
        #expect(session.phase == .playing)
        _ = session.update(elapsed: frame * 10.5, input: idle)
        #expect(session.simulation.tick == 10)
    }

    @Test func pausingStopsTheSimulationAndResumeCountsDownFirst() {
        var session = GameSession(seed: 1)
        session.startGame()
        _ = session.update(elapsed: 0.05, input: idle)
        let tick = session.simulation.tick

        session.pause()
        #expect(session.phase == .paused)
        _ = session.update(elapsed: 0.05, input: idle)
        #expect(session.simulation.tick == tick)

        #expect(session.resume() == true)
        #expect(session.phase == .countdown(remaining: GameSession.resumeCountdown))
        _ = session.update(elapsed: 0.05, input: idle)
        #expect(session.simulation.tick == tick)

        for _ in 0..<40 { _ = session.update(elapsed: 0.1, input: idle) }
        #expect(session.phase == .playing)
        #expect(session.simulation.tick > tick)
    }

    @Test func losingThePlayfieldPausesAndBlocksResume() {
        var session = GameSession(seed: 1)
        session.startGame()
        _ = session.update(elapsed: 0.05, input: idle)

        session.setPlayfieldAvailable(false)
        #expect(session.phase == .paused)
        #expect(!session.canResume)
        #expect(session.resume() == false)
        #expect(session.phase == .paused)

        session.setPlayfieldAvailable(true)
        // Getting the playfield back does not restart play by itself.
        #expect(session.phase == .paused)
        #expect(session.resume() == true)
    }

    @Test func losingThePlayfieldDuringTheCountdownPausesAgain() {
        var session = GameSession(seed: 1)
        session.startGame()
        session.pause()
        session.resume()
        _ = session.update(elapsed: 0.1, input: idle)

        session.setPlayfieldAvailable(false)
        #expect(session.phase == .paused)
    }

    @Test func startOverWhileUnavailableResetsButStaysPaused() {
        var session = GameSession(seed: 1)
        session.startGame()
        for _ in 0..<100 { _ = session.update(elapsed: 0.1, input: idle) }
        session.simulation.score = 4200
        #expect(session.simulation.wave >= 1)

        session.setPlayfieldAvailable(false)
        session.startOver()

        #expect(session.phase == .paused)
        #expect(session.simulation.score == 0)
        #expect(session.simulation.wave == 0)
        #expect(session.simulation.tick == 0)
        #expect(session.simulation.player.lives == session.tuning.startingLives)

        _ = session.update(elapsed: 0.1, input: idle)
        #expect(session.simulation.tick == 0)
    }

    @Test func startOverWhilePlayingKeepsPlaying() {
        var session = GameSession(seed: 1)
        session.startGame()
        _ = session.update(elapsed: 0.1, input: idle)
        session.startOver()
        #expect(session.phase == .playing)
        #expect(session.simulation.tick == 0)
    }

    @Test func endGameWorksWhileUnavailableAndReportsTheScore() {
        var session = GameSession(seed: 1)
        session.startGame()
        session.simulation.score = 900
        session.setPlayfieldAvailable(false)

        #expect(session.endGame() == 900)
        #expect(session.phase == .title)
        #expect(session.lastScore == 900)
        #expect(session.endGame() == nil)
    }

    @Test func aNewGameCannotStartWhileThePlayfieldIsUnavailable() {
        var session = GameSession(seed: 1)
        session.setPlayfieldAvailable(false)
        #expect(session.startGame() == false)
        #expect(session.phase == .title)

        session.setPlayfieldAvailable(true)
        #expect(session.startGame() == true)
    }

    @Test func runningOutOfLivesMovesToGameOverAndANewGameCanFollow() {
        var session = GameSession(seed: 1)
        session.startGame()
        session.simulation.player.lives = 1
        session.simulation.addEnemy(kind: .husk, at: session.simulation.player.pos, state: .hunting)

        let events = session.update(elapsed: 0.05, input: idle)
        #expect(events.contains { $0.isGameOver })
        #expect(session.phase == .gameOver(score: 250))
        #expect(session.lastScore == 250)
        #expect(!session.isInGame)

        #expect(session.startGame() == true)
        #expect(session.phase == .playing)
        #expect(session.simulation.score == 0)
    }

    @Test func aLongStallDoesNotTriggerABurstOfCatchUpSteps() {
        var session = GameSession(seed: 1)
        session.startGame()
        _ = session.update(elapsed: 30, input: idle)
        #expect(session.simulation.tick <= 12)
    }
}

@Suite struct ReplayTests {
    /// A fixed, arbitrary stream of stick and trigger input.
    private func script(seed: UInt64, length: Int) -> [InputState] {
        var rng = SeededRNG(seed: seed)
        var input = InputState()
        return (0..<length).map { step in
            if step % 30 == 0 {
                input = InputState(
                    move: Vec2(rng.range(-1...1), rng.range(-1...1)),
                    fire: rng.chance(0.7),
                    shockwave: rng.chance(0.05),
                    blink: rng.chance(0.2)
                )
            }
            return input
        }
    }

    @Test func theSameSeedAndInputGiveTheSameGame() {
        let inputs = script(seed: 99, length: 120 * 60)
        var a = Simulation(seed: 42)
        var b = Simulation(seed: 42)
        for input in inputs {
            let ea = a.step(input)
            let eb = b.step(input)
            #expect(ea == eb)
        }
        #expect(a.score == b.score)
        #expect(a.player.pos == b.player.pos)
        #expect(a.enemies.map(\.pos) == b.enemies.map(\.pos))
        #expect(a.colonists.map(\.state) == b.colonists.map(\.state))

        var c = Simulation(seed: 43)
        for input in inputs { _ = c.step(input) }
        #expect(c.world.outposts != a.world.outposts)
    }

    @Test func tenMinutesOfPlayKeepsEverythingInBounds() {
        var session = GameSession(seed: 2026)
        session.startGame()
        var gamesPlayed = 1
        var events = 0
        var seen: [GameEvent] = []

        for (step, input) in script(seed: 5, length: 120 * 600).enumerated() {
            let batch = session.update(elapsed: frame, input: input)
            events += batch.count
            // Keep one example of each kind of event that isn't a shot.
            for event in batch where !event.isPlayerFired {
                if !seen.contains(where: { $0.kind == event.kind }) { seen.append(event) }
            }
            if case .gameOver = session.phase {
                session.startGame()
                gamesPlayed += 1
            }
            guard step % 20 == 0 else { continue }

            let sim = session.simulation
            let world = sim.world
            let positions = [sim.player.pos]
                + sim.enemies.map(\.pos)
                + sim.projectiles.map(\.pos)
                + sim.colonists.map(\.pos)
            for pos in positions {
                #expect(pos.x.isFinite && pos.y.isFinite)
                #expect(pos.x >= 0 && pos.x < world.width)
                #expect(pos.y >= 0 && pos.y <= world.height)
            }
            #expect(sim.player.heat >= 0 && sim.player.heat <= 1)
            #expect(sim.player.lives >= 0)
            #expect(sim.projectiles.count < 200)
            #expect(sim.enemies.count < 60)
        }

        #expect(events > 1000)
        #expect(gamesPlayed >= 1)

        // The run should have exercised the whole loop, not just flown about.
        let kinds = Set(seen.map(\.kind))
        for expected in ["waveStarted", "enemySpawned", "enemyDestroyed", "enemyFired",
                         "colonistGrabbed", "colonistLost", "huskFormed",
                         "playerDestroyed", "playerRespawned", "gameOver"] {
            #expect(kinds.contains(expected), "no \(expected) event in ten minutes of play")
        }
    }
}
