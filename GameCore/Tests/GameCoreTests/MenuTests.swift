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
