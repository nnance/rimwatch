import Foundation
import Testing
import GameCore
@testable import RidgelineCore

@Suite struct FrontEndTests {
    private func frontEnd(_ pose: FoldPose = .open) -> FrontEnd {
        FrontEnd(session: GameSession(seed: 1), pose: pose)
    }

    private func commands(_ fe: FrontEnd) -> [MenuItem.Command] {
        fe.menu?.items.map(\.command) ?? []
    }

    private func item(_ fe: FrontEnd, _ command: MenuItem.Command) -> MenuItem? {
        fe.menu?.items.first { $0.command == command }
    }

    /// Ends the run by losing the last life.
    private func loseLastLife(_ fe: inout FrontEnd) -> [FrontEnd.Effect] {
        fe.session.simulation.player.lives = 1
        fe.session.simulation.addEnemy(kind: .husk, at: fe.session.simulation.player.pos, state: .hunting)
        return fe.update(elapsed: 0.05, input: idle).effects
    }

    @Test func noHingeShowsTheMadeForDuoScreenWithNoMenu() {
        let fe = frontEnd(.noHinge)
        #expect(fe.screen == .madeForDuo)
        #expect(fe.menu == nil)
    }

    @Test func titleOffersPlayOnlyWhenOpen() {
        var fe = frontEnd(.closed)
        #expect(fe.screen == .title)
        #expect(commands(fe) == [.play, .options, .highScores])
        #expect(item(fe, .play)?.isEnabled == false)
        #expect(item(fe, .play)?.label == "Open to play")
        #expect(fe.menu?.selectedItem?.command == .options)
        #expect(fe.choose(0).isEmpty)
        #expect(fe.screen == .title)

        fe.setPose(.open)
        #expect(item(fe, .play)?.isEnabled == true)
        #expect(fe.menu?.selectedItem?.command == .play)
        #expect(fe.activate() == [.newRun])
        #expect(fe.screen == .playing)
        #expect(fe.menu == nil)
    }

    @Test func closingMidGamePausesWithResumeDisabled() {
        var fe = frontEnd()
        fe.perform(.play)
        _ = fe.update(elapsed: 0.05, input: idle)
        fe.setPose(.closed)
        #expect(fe.screen == .paused)
        #expect(commands(fe) == [.resume, .startOver, .endGame, .options, .highScores])
        #expect(item(fe, .resume)?.isEnabled == false)
        #expect(item(fe, .resume)?.label == "Open to resume")
        // Not Start over: a destructive item is never the default.
        #expect(fe.menu?.selectedItem?.command == .options)

        // Activating Resume by touch does nothing while closed.
        fe.choose(0)
        #expect(fe.screen == .paused)
    }

    @Test func reopeningShowsTheMenuWithResumeThenCountsDown() {
        var fe = frontEnd()
        fe.perform(.play)
        fe.setPose(.closed)
        fe.setPose(.open)
        // Not straight back into play.
        #expect(fe.screen == .paused)
        #expect(item(fe, .resume)?.isEnabled == true)
        #expect(fe.menu?.selectedItem?.command == .resume)

        fe.activate()
        #expect(fe.screen == .countdown(remaining: GameSession.resumeCountdown))
        #expect(fe.menu == nil)
        for _ in 0..<31 { _ = fe.update(elapsed: 0.1, input: idle) }
        #expect(fe.screen == .playing)
    }

    @Test func closingDuringTheCountdownPausesAgain() {
        var fe = frontEnd()
        fe.perform(.play)
        fe.requestPause()
        fe.perform(.resume)
        fe.setPose(.closed)
        #expect(fe.screen == .paused)
        #expect(fe.menu?.kind == .pause)
    }

    @Test func startOverWhileClosedResetsAndStaysPaused() {
        var fe = frontEnd()
        fe.perform(.play)
        for _ in 0..<20 { _ = fe.update(elapsed: 0.05, input: idle) }
        let oldTick = fe.session.simulation.tick
        #expect(oldTick > 0)
        fe.setPose(.closed)
        #expect(fe.perform(.startOver) == [.newRun])
        #expect(fe.screen == .paused)
        #expect(fe.session.simulation.tick == 0)
        #expect(fe.session.simulation.wave <= 1)
    }

    @Test func endGameRecordsTheScoreAndGoesToTheTitle() {
        var fe = frontEnd()
        fe.perform(.play)
        fe.session.simulation.score = 1234
        fe.setPose(.closed)
        #expect(fe.perform(.endGame) == [.highScoresChanged])
        #expect(fe.screen == .title)
        #expect(fe.highScores.entries.map(\.score) == [1234])
        #expect(fe.lastRank == 0)
    }

    @Test func endingWithNoScoreRecordsNothing() {
        var fe = frontEnd()
        fe.perform(.play)
        #expect(fe.perform(.endGame).isEmpty)
        #expect(fe.highScores.entries.isEmpty)
        #expect(fe.screen == .title)
    }

    @Test func gameOverRecordsOnceAndContinueGoesToTheTitle() {
        var fe = frontEnd()
        fe.perform(.play)
        let effects = loseLastLife(&fe)
        #expect(effects == [.highScoresChanged])
        #expect(fe.screen == .gameOver(score: 250))
        #expect(commands(fe) == [.proceed])
        #expect(fe.menu?.lines.contains("New high score: #1") == true)
        _ = fe.update(elapsed: 0.05, input: idle)
        #expect(fe.highScores.entries.count == 1)
        // Continue is dimmed through the game-over hold-off.
        #expect(fe.menu?.items.first?.isEnabled == false)
        #expect(fe.activate().isEmpty)
        #expect(fe.screen == .gameOver(score: 250))
        _ = fe.update(elapsed: FrontEnd.gameOverGrace, input: idle)
        #expect(fe.menu?.selectedItem?.command == .proceed)

        #expect(fe.activate().isEmpty)
        #expect(fe.screen == .title)
        #expect(fe.highScores.entries.count == 1)
    }

    @Test func optionsAndHighScoresOpenOverAnyMenuAndBackReturns() {
        var fe = frontEnd(.closed)
        fe.perform(.options)
        #expect(fe.screen == .options)
        #expect(commands(fe).last == .back)
        #expect(item(fe, .option(.soundVolume))?.value == "80%")

        // Touch on the down arrow, then a gamepad step up from the selected row.
        #expect(fe.choose(0, step: -1) == [.optionsChanged])
        #expect(fe.options.soundVolume == 7)
        #expect(fe.adjust(by: 1) == [.optionsChanged])
        #expect(fe.options.soundVolume == 8)
        #expect(fe.menu?.selectedItem?.command == .option(.soundVolume))
        fe.moveSelection(by: 2)
        fe.activate()
        #expect(!fe.options.hapticsEnabled)
        #expect(item(fe, .option(.haptics))?.value == "Off")
        #expect(fe.menu?.selectedItem?.command == .option(.haptics))

        #expect(fe.back() == true)
        #expect(fe.screen == .title)
        #expect(fe.back() == false)

        fe.perform(.highScores)
        #expect(fe.screen == .highScores)
        #expect(fe.menu?.lines == ["No scores yet"])
        fe.activate()
        #expect(fe.screen == .title)
    }

    @Test func optionsWhilePausedReturnToThePauseMenu() {
        var fe = frontEnd()
        fe.perform(.play)
        fe.requestPause()
        fe.perform(.options)
        fe.setPose(.closed)
        #expect(fe.screen == .options)
        fe.back()
        #expect(fe.screen == .paused)
        #expect(item(fe, .resume)?.isEnabled == false)
    }

    @Test func losingFocusPausesAndNothingResumesOnItsOwn() {
        var fe = frontEnd()
        fe.perform(.play)
        fe.appWillResignActive()
        #expect(fe.screen == .paused)
        for _ in 0..<50 { _ = fe.update(elapsed: 0.1, input: idle) }
        #expect(fe.screen == .paused)

        // On the title it does nothing.
        var title = frontEnd()
        title.appWillResignActive()
        #expect(title.screen == .title)
    }

    @Test func adjustIgnoresItemsThatAreNotOptions() {
        var fe = frontEnd()
        #expect(fe.adjust(by: 1).isEmpty)
        #expect(fe.screen == .title)
    }

    @Test func highScoresScreenListsTheTable() {
        let table = HighScoreTable(entries: [
            HighScoreEntry(score: 900, wave: 4, date: Date()),
            HighScoreEntry(score: 12_000, wave: 9, date: Date()),
        ])
        let menu = FrontEnd.menu(for: .highScores, session: GameSession(seed: 1), pose: .open,
                                 options: GameOptions(), highScores: table)
        #expect(menu?.lines == [])
        #expect(menu?.table?.rows.map { $0[1] } == ["12,000", "900"])
        #expect(menu?.table?.rows.map { $0[2] } == ["9", "4"])
    }
}
