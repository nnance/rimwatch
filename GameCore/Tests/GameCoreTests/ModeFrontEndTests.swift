import Foundation
import Testing
import GameCore

@Suite struct ModeFrontEndTests {
    private func frontEnd(endAfter: Int, ending: RunEnding = .goalMet) -> CountingFrontEnd {
        CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: endAfter, ending: ending)),
                         pose: .open)
    }

    @Test func aGoalMetEndingShowsGameOverAndRecordsTheResult() {
        var fe = frontEnd(endAfter: 21, ending: .goalMet)
        #expect(fe.perform(.play) == [.newRun])
        var effects: [FlowEffect] = []
        for _ in 0..<10 { effects += fe.update(elapsed: 0.09375, input: 0).effects }
        #expect(fe.screen == .gameOver(score: 210))
        #expect(fe.session.lastEnding == .goalMet)
        #expect(effects == [.highScoresChanged])
        #expect(fe.lastRank == 0)
        #expect(fe.highScores.entries.map(\.score) == [210])
        #expect(fe.highScores.entries.map(\.wave) == [2])
        #expect(fe.highScores.entries.map(\.saved) == [7])
        #expect(fe.menu?.kind == .gameOver)
        #expect(fe.menu?.lines == ["Score 210", "Wave 2", "Colonists saved 7", "New high score: #1"])
    }

    @Test func aRunEndedBeforeItsFirstWaveCountsAsWaveOne() {
        var fe = frontEnd(endAfter: 3, ending: .defeated)
        #expect(fe.perform(.play) == [.newRun])
        _ = fe.update(elapsed: 0.1, input: 0)
        #expect(fe.screen == .gameOver(score: 30))
        #expect(fe.session.lastEnding == .defeated)
        #expect(fe.highScores.entries.first?.wave == 1)
        #expect(fe.menu?.lines.prefix(3) == ["Score 30", "Wave 1", "Colonists saved 1"])
        // Continue goes back to the title once the hold-off has passed.
        for _ in 0..<20 { _ = fe.update(elapsed: 0.1, input: 0) }
        #expect(fe.perform(.proceed).isEmpty)
        #expect(fe.screen == .title)
    }

    @Test func thePauseMenuShowsTheRunSoFar() {
        var fe = frontEnd(endAfter: 1000)
        #expect(fe.perform(.play) == [.newRun])
        // Three steps of 1/32 s a frame.
        for _ in 0..<4 { _ = fe.update(elapsed: 0.09375, input: 0) }
        fe.requestPause()
        #expect(fe.screen == .paused)
        #expect(fe.menu?.lines == ["Score 120", "Wave 1"])
        // End game records the run.
        #expect(fe.perform(.endGame) == [.highScoresChanged])
        #expect(fe.screen == .title)
        #expect(fe.highScores.entries.map(\.score) == [120])
        #expect(fe.session.lastEnding == nil)
    }

    @Test func aHighScoreEntryFromAResultCountsWaveZeroAsOne() {
        let date = Date(timeIntervalSince1970: 1_000)
        #expect(HighScoreEntry(RunResult(score: 5, wave: 0, saved: 2), date: date)
            == HighScoreEntry(score: 5, wave: 1, date: date, saved: 2))
        #expect(HighScoreEntry(RunResult(score: 5, wave: 4, saved: 0), date: date).wave == 4)
    }
}
