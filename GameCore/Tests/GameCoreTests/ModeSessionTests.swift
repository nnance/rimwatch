import Testing
import GameCore

@Suite struct ModeSessionTests {
    private func session(endAfter: Int = 1000, ending: RunEnding = .goalMet) -> CountingSession {
        CountingSession(seed: 5, config: CountingRun.Config(endAfter: endAfter, ending: ending))
    }

    @Test func aRunThatMeetsItsGoalEndsInGameOver() {
        var s = session(endAfter: 5, ending: .goalMet)
        #expect(s.startGame() == true)
        let events = s.update(elapsed: 0.09375, input: 7)
        #expect(events == [7, 7, 7])
        #expect(s.phase == .playing)
        #expect(s.lastEnding == nil)
        // Three steps are due, but the run ends at its fifth step, so the third is dropped.
        let more = s.update(elapsed: 0.09375, input: 8)
        #expect(more == [8, 8])
        #expect(s.phase == .gameOver(score: 50))
        #expect(s.lastEnding == .goalMet)
        #expect(s.lastResult == RunResult(score: 50, wave: 0, saved: 1))
        #expect(s.lastScore == 50)
        #expect(s.isInGame == false)
        // Nothing more happens until a new game.
        #expect(s.update(elapsed: 0.1, input: 9).isEmpty)
        #expect(s.stepCount == 5)
    }

    @Test func aDefeatEndsTheSameWayWithItsOwnEnding() {
        var s = session(endAfter: 2, ending: .defeated)
        #expect(s.startGame() == true)
        _ = s.update(elapsed: 0.1, input: 0)
        #expect(s.phase == .gameOver(score: 20))
        #expect(s.lastEnding == .defeated)
    }

    @Test func framesAreCappedAndStepsCarryTheRemainder() {
        var s = session()
        #expect(s.startGame() == true)
        // A stall counts as 0.1 s at most: three steps of 1/32 s, with 0.00625 s carried.
        #expect(s.update(elapsed: 5, input: 1).count == 3)
        #expect(s.update(elapsed: 0.03, input: 1).count == 1)
        #expect(s.update(elapsed: -1, input: 1).isEmpty)
        #expect(s.stepCount == 4)
    }

    @Test func pausingDropsThePartStepAndTheCountdownTakesNoSteps() {
        var s = session()
        #expect(s.startGame() == true)
        #expect(s.update(elapsed: 0.05, input: 1).count == 1)  // 0.01875 s left over
        s.pause()
        #expect(s.phase == .paused)
        #expect(s.update(elapsed: 0.05, input: 1).isEmpty)
        #expect(s.resume() == true)
        #expect(s.phase == .countdown(remaining: CountingSession.resumeCountdown))
        var frames = 0
        while s.phase != .playing, frames < 40 {
            #expect(s.update(elapsed: 0.1, input: 1).isEmpty)
            frames += 1
        }
        #expect(s.phase == .playing)
        #expect((30...31).contains(frames))
        // Without the leftover, 0.02 s is not yet a step.
        #expect(s.update(elapsed: 0.02, input: 1).isEmpty)
        #expect(s.stepCount == 1)
    }

    @Test func eachNewRunGetsTheAnnouncedSeedAndTheStepCountKeepsGoing() {
        var s = session()
        let first = s.nextRunSeed
        #expect(s.startGame() == true)
        #expect(s.runSeed == first)
        #expect(s.run.seed == first)
        #expect(s.run.config == CountingRun.Config(endAfter: 1000))
        _ = s.update(elapsed: 0.1, input: 0)
        let second = s.nextRunSeed
        s.startOver()
        #expect(s.run.seed == second)
        #expect(s.run.steps == 0)
        #expect(s.stepCount == 3)
        _ = s.update(elapsed: 0.1, input: 0)
        #expect(s.stepCount == 6)
    }

    @Test func endingTheGameRecordsTheResultWithNoEnding() {
        var s = session()
        #expect(s.startGame() == true)
        _ = s.update(elapsed: 0.1, input: 0)
        #expect(s.endGame() == 30)
        #expect(s.phase == .title)
        #expect(s.lastResult == RunResult(score: 30, wave: 0, saved: 1))
        #expect(s.lastEnding == nil)
        #expect(s.endGame() == nil)
    }

    @Test func losingThePlayfieldPausesAndBlocksPlay() {
        var s = session()
        s.setPlayfieldAvailable(false)
        #expect(s.startGame() == false)
        s.setPlayfieldAvailable(true)
        #expect(s.startGame() == true)
        s.setPlayfieldAvailable(false)
        #expect(s.phase == .paused)
        #expect(s.canResume == false)
        #expect(s.resume() == false)
    }
}
