import Foundation
import Testing
@testable import GameCore

@Suite struct MenuTests {
    private func sample() -> Menu {
        Menu(kind: .pause, heading: "Paused", items: [
            MenuItem(.resume, "Resume", disabledTitle: "Open to resume", isEnabled: false),
            MenuItem(.startOver, "Start over"),
            MenuItem(.endGame, "End game"),
            MenuItem(.options, "Options"),
        ])
    }

    @Test func selectionStartsOnTheFirstEnabledItem() {
        let menu = sample()
        #expect(menu.selectedItem?.command == .startOver)
        #expect(menu.items[0].label == "Open to resume")
        #expect(menu.items[1].label == "Start over")
    }

    @Test func movingSkipsDisabledItemsAndWraps() {
        var menu = sample()
        menu.moveSelection(by: 1)
        #expect(menu.selectedItem?.command == .endGame)
        menu.moveSelection(by: 2)
        // Past Options it wraps, skipping the disabled Resume.
        #expect(menu.selectedItem?.command == .startOver)
        menu.moveSelection(by: -1)
        #expect(menu.selectedItem?.command == .options)
    }

    @Test func disabledItemsCannotBeSelected() {
        var menu = sample()
        #expect(menu.select(0) == false)
        #expect(menu.select(9) == false)
        #expect(menu.selectedItem?.command == .startOver)
        #expect(menu.select(.options) == true)
        #expect(menu.selectedItem?.command == .options)
    }

    @Test func aMenuWithNothingEnabledHasNoSelection() {
        var menu = Menu(kind: .title, heading: "", items: [MenuItem(.play, "Play", isEnabled: false)])
        #expect(menu.selection == nil)
        menu.moveSelection(by: 1)
        #expect(menu.selection == nil)
    }

    @Test func replacingItemsKeepsTheSelectionUnlessWhatIsEnabledChanged() {
        var menu = sample()
        menu.select(.options)
        var items = menu.items
        items[3].value = "changed"
        menu.replaceItems(items)
        #expect(menu.selectedItem?.command == .options)

        // Resume becomes available: the selection jumps to it.
        items[0].isEnabled = true
        menu.replaceItems(items)
        #expect(menu.selectedItem?.command == .resume)
    }
}

@Suite struct OptionsTests {
    @Test func volumesClampWhenAdjustedAndWrapWhenCycled() {
        var options = GameOptions()
        options.soundVolume = 9
        options.adjust(.soundVolume, by: 1)
        options.adjust(.soundVolume, by: 1)
        #expect(options.soundVolume == GameOptions.volumeSteps)
        options.adjust(.soundVolume, by: 1, wrap: true)
        #expect(options.soundVolume == 0)
        options.adjust(.soundVolume, by: -1)
        #expect(options.soundVolume == 0)
        options.adjust(.musicVolume, by: -1, wrap: true)
        #expect(options.musicVolume == 5)
        #expect(options.valueText(of: .musicVolume) == "50%")
        #expect(options.musicLevel == 0.5)
    }

    @Test func togglesAndChoicesCycleEitherWay() {
        var options = GameOptions()
        options.adjust(.haptics, by: 1)
        #expect(!options.hapticsEnabled)
        options.adjust(.haptics, by: -1)
        #expect(options.hapticsEnabled)
        options.adjust(.handedness, by: -1)
        #expect(options.handedness == .stickRight)
        options.adjust(.handedness, by: 1)
        #expect(options.handedness == .stickLeft)
        options.adjust(.gamepadLayout, by: 1)
        #expect(options.gamepadLayout == .swapped)
    }

    @Test func roundTripsThroughJSONAndToleratesMissingKeys() throws {
        var options = GameOptions()
        options.soundVolume = 3
        options.handedness = .stickRight
        options.gamepadLayout = .swapped
        options.hapticsEnabled = false
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(GameOptions.self, from: data) == options)

        let partial = try JSONDecoder().decode(GameOptions.self, from: Data(#"{"musicVolume": 99}"#.utf8))
        #expect(partial.musicVolume == GameOptions.volumeSteps)
        #expect(partial.soundVolume == GameOptions().soundVolume)
        #expect(partial.handedness == .stickLeft)
    }
}

@Suite struct HighScoreTests {
    private func entry(_ score: Int, wave: Int = 1) -> HighScoreEntry {
        HighScoreEntry(score: score, wave: wave, date: Date(timeIntervalSince1970: 0))
    }

    @Test func keepsTheBestTenHighestFirst() {
        var table = HighScoreTable()
        for score in [500, 100, 900, 300, 700, 200, 800, 400, 600, 1000, 50] {
            table.insert(entry(score))
        }
        #expect(table.entries.map(\.score) == [1000, 900, 800, 700, 600, 500, 400, 300, 200, 100])
        #expect(table.insert(entry(90)) == nil)
        #expect(table.insert(entry(650)) == 4)
        #expect(table.entries.count == HighScoreTable.capacity)
        #expect(table.entries.last?.score == 200)
    }

    @Test func anEqualScoreRanksBelowTheOneAlreadyThere() {
        var table = HighScoreTable()
        table.insert(entry(500, wave: 1))
        #expect(table.insert(entry(500, wave: 2)) == 1)
        #expect(table.entries.map(\.wave) == [1, 2])
    }

    @Test func zeroNeverPlaces() {
        var table = HighScoreTable()
        #expect(table.insert(entry(0)) == nil)
        #expect(table.entries.isEmpty)
    }

    @Test func aFullTableRefusesATieWithItsLastPlace() {
        var table = HighScoreTable()
        for score in 1...10 { table.insert(entry(score * 10)) }
        #expect(!table.qualifies(10))
        #expect(table.qualifies(11))
    }

    @Test func groupsDigits() {
        #expect(groupedDigits(0) == "0")
        #expect(groupedDigits(999) == "999")
        #expect(groupedDigits(12_340) == "12,340")
        #expect(groupedDigits(1_234_567) == "1,234,567")
    }
}

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
