// Needs `Autopilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RidgelineCore

/// A golden replay of the whole session pipeline: a `FrontEnd` driven frame by frame with uneven
/// frame times and the scripted pilot at the controls, through a pause (with the phone closing
/// and opening), a resume countdown, a start-over, a game over, Continue, another game and an
/// End game. The expected values were captured from the code as it was before step 9 split the
/// session logic out of Ridgeline, so a refactor that changes behaviour anywhere in that
/// pipeline (stepping, pausing, the countdown, seeds, recording scores, screens) fails here.
///
/// If a deliberate gameplay change (tuning, waves, the bot) breaks it, capture the new values
/// from the test's printed summary and say so in the commit.
@Suite struct FrontEndReplayTests {
    /// Frame times cycle through these: 120 Hz, 60 Hz and an awkward in-between, so the session's
    /// accumulator carries remainders.
    private static let frameTimes: [Double] = [1.0 / 120, 1.0 / 60, 0.013]
    private static let frameBudget = 20_000

    private struct Replay {
        var frames = 0
        var screens: [String] = []
        var events: [String: Int] = [:]
        var effects: [String: Int] = [:]
        /// FNV-1a over every event's full description and the frame it came in, so the order and
        /// payloads (positions, ids, points) count too, not only the totals.
        var eventHash: UInt64 = 0xCBF2_9CE4_8422_2325
        var gameOverFrame = 0
        var usedFallbackBot = false
        var runSeeds: [UInt64] = []
        var gameOverScore: Int?
        var gameOverWave = 0
        var gameOverSaved = 0
        var gameOverRank: Int?
        var endGameScore: Int?
        var finalScore = 0
        var finalWave = 0
        var finalSaved = 0
        var finalRunSeed: UInt64 = 0
        var table: [[Int]] = []
    }

    private static func screenName(_ screen: FrontEnd.Screen) -> String {
        "\(screen)".components(separatedBy: "(").first ?? ""
    }

    private static func play() -> Replay {
        var fe = FrontEnd(session: GameSession(seed: 42), pose: .open)
        var replay = Replay()
        var bot = Autopilot(skill: .competent, seed: 1)
        var runs = 0

        func note() {
            let name = screenName(fe.screen)
            if replay.screens.last != name { replay.screens.append(name) }
        }
        func apply(_ effects: [FrontEnd.Effect]) {
            for effect in effects {
                replay.effects["\(effect)", default: 0] += 1
                if effect == .newRun {
                    // As the app's -autopilot does: a fresh bot per run, seeded by the run count.
                    runs += 1
                    bot = Autopilot(skill: runs >= 3 ? .novice : .competent, seed: UInt64(runs))
                    replay.runSeeds.append(fe.session.runSeed)
                }
            }
            note()
        }
        func frame() {
            let elapsed = frameTimes[replay.frames % frameTimes.count]
            replay.frames += 1
            let input = bot.input(for: fe.session.simulation)
            let result = fe.update(elapsed: elapsed, input: input)
            for event in result.events {
                replay.events[event.kind, default: 0] += 1
                for byte in "\(replay.frames) \(event);".utf8 {
                    replay.eventHash = (replay.eventHash ^ UInt64(byte)) &* 0x100_0000_01B3
                }
            }
            apply(result.effects)
        }
        func run(frames count: Int) {
            for _ in 0..<count where replay.frames < frameBudget { frame() }
        }
        func runUntil(_ done: () -> Bool) {
            while !done(), replay.frames < frameBudget { frame() }
        }

        note()
        apply(fe.perform(.play))
        // 2,999 frames leave part of a step in the accumulator when the pause comes, so the
        // replay notices if pausing stops discarding it.
        run(frames: 2999)

        // Pause, close and open the phone, resume through the countdown.
        fe.requestPause()
        note()
        run(frames: 60)
        fe.setPose(.closed)
        note()
        run(frames: 60)
        fe.setPose(.open)
        note()
        run(frames: 30)
        apply(fe.perform(.resume))
        run(frames: 500)

        // Pause again and start over: the new run begins paused, then resumes.
        fe.requestPause()
        note()
        run(frames: 20)
        apply(fe.perform(.startOver))
        run(frames: 20)
        apply(fe.perform(.resume))

        // Play the second run to its end. Half way through the budget the bot gets worse, so the
        // run is sure to end.
        func isOver() -> Bool { if case .gameOver = fe.screen { true } else { false } }
        runUntil { isOver() || replay.frames >= 9_000 }
        if !isOver() {
            replay.usedFallbackBot = true
            bot = Autopilot(skill: .novice, seed: 99)
            runUntil(isOver)
        }
        if case .gameOver(let score) = fe.screen {
            replay.gameOverScore = score
            replay.gameOverFrame = replay.frames
            replay.gameOverWave = fe.session.simulation.wave
            replay.gameOverSaved = fe.session.simulation.colonistsSaved
            replay.gameOverRank = fe.lastRank
        }
        run(frames: 200)
        apply(fe.perform(.proceed))
        run(frames: 100)

        // A short third game, ended from the pause menu.
        apply(fe.perform(.play))
        run(frames: 1500)
        fe.requestPause()
        note()
        apply(fe.perform(.endGame))
        replay.endGameScore = fe.session.lastScore
        run(frames: frameBudget)

        let sim = fe.session.simulation
        replay.finalScore = sim.score
        replay.finalWave = sim.wave
        replay.finalSaved = sim.colonistsSaved
        replay.finalRunSeed = fe.session.runSeed
        replay.table = fe.highScores.entries.map { [$0.score, $0.wave, $0.saved] }
        return replay
    }

    @Test func theSessionPipelineReplaysExactly() {
        let replay = Self.play()
        print("REPLAY \(replay)")

        #expect(replay.frames == Self.frameBudget)
        #expect(replay.screens == [
            "title", "playing", "paused", "countdown", "playing", "paused", "countdown", "playing",
            "gameOver", "title", "playing", "paused", "title",
        ])
        #expect(replay.events == [
            "colonistCaught": 3,
            "colonistDelivered": 2,
            "colonistDropped": 16,
            "colonistGrabbed": 20,
            "colonistLanded": 9,
            "colonistLost": 8,
            "enemyDestroyed": 72,
            "enemyFired": 19,
            "enemyHit": 3,
            "enemySpawned": 73,
            "gameOver": 1,
            "huskFormed": 4,
            "lancerTelegraph": 1,
            "mineLaid": 16,
            "playerBlinked": 5,
            "playerDestroyed": 3,
            "playerFired": 911,
            "playerOverheated": 12,
            "playerRespawned": 2,
            "shieldBroken": 1,
            "shieldCharged": 1,
            "waveCleared": 7,
            "waveStarted": 10,
        ])
        #expect(replay.effects == ["newRun": 3, "highScoresChanged": 2])
        #expect(replay.eventHash == 8_496_102_242_286_793_760)
        #expect(replay.runSeeds == [10_481_999_410_520_546_993, 4_159_066_171_780_167_020, 7_615_522_811_268_512_075])
        // The competent pilot is still alive at frame 9,000, so the novice finishes the run.
        #expect(replay.usedFallbackBot)
        #expect(replay.gameOverFrame == 15_350)
        #expect(replay.gameOverScore == 23_150)
        #expect(replay.gameOverWave == 6)
        #expect(replay.gameOverSaved == 2)
        #expect(replay.gameOverRank == 0)
        #expect(replay.endGameScore == 300)
        #expect(replay.finalScore == 300)
        #expect(replay.finalWave == 1)
        #expect(replay.finalSaved == 0)
        #expect(replay.finalRunSeed == 7_615_522_811_268_512_075)
        // Score, wave, saved (the dates are the time of the test run).
        #expect(replay.table == [[23_150, 6, 2], [300, 1, 0]])
    }
}
#endif
