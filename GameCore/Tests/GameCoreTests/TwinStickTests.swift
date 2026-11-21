import Testing
import GameCore

/// The second stick and the shoulder buttons on a gamepad, the floating touch stick, and the
/// Options rows each mode lists.
@Suite struct TwinStickPadTests {
    @Test func aSnapshotStartsWithTheRightStickCentred() {
        #expect(PadSnapshot.neutral.rightStick == .zero)
        #expect(PadSnapshot(stick: Vec2(1, 0)).rightStick == .zero)
    }

    @Test func theRightStickHasTheLeftSticksDeadZone() {
        var reader = PadReader()
        reader.receive(PadSnapshot(rightStick: Vec2(0.1, 0.1)))
        #expect(reader.rightStick == .zero)
        reader.receive(PadSnapshot(rightStick: Vec2(0.6, -0.3)))
        #expect(reader.rightStick == PadMapping.stick(Vec2(0.6, -0.3)))
        reader.receive(PadSnapshot(rightStick: Vec2(1, 1)))
        #expect(abs(reader.rightStick.length - 1) < 1e-9)
        // The left stick is independent of it.
        #expect(PadMapping.move(reader.current) == .zero)
        reader.reset()
        #expect(reader.rightStick == .zero)
    }

    @Test func shouldersAndTriggersLatchLikeTheFaceButtons() {
        let new: [PadButton] = [.leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger]
        for button in new {
            var reader = PadReader()
            // A tap between two frames is still seen by the next step, once.
            reader.receive(PadSnapshot(buttons: [button]))
            reader.receive(.neutral)
            #expect(reader.playButtons == [button])
            reader.consumePlayPresses()
            #expect(reader.playButtons.isEmpty)
            // Held, it stays down.
            reader.receive(PadSnapshot(buttons: [button]))
            reader.consumePlayPresses()
            #expect(reader.playButtons == [button])
        }
    }

    @Test func aShoulderHeldWhenPlayStartsIsIgnoredUntilLetGo() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.rightShoulder, .a]))
        reader.suppressHeldButtons()
        #expect(reader.playButtons.isEmpty)
        reader.receive(PadSnapshot(buttons: [.rightShoulder]))
        #expect(reader.playButtons.isEmpty)
        reader.receive(.neutral)
        reader.receive(PadSnapshot(buttons: [.rightShoulder]))
        #expect(reader.playButtons == [.rightShoulder])
    }

    @Test func menusIgnoreTheRightStickShouldersAndTriggers() {
        var reader = PadReader()
        reader.receive(PadSnapshot(rightStick: Vec2(0, 1)))
        reader.receive(PadSnapshot(buttons: [.leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger],
                                   rightStick: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        #expect(reader.menuCommands(elapsed: 1) == [])
        // The menu button still pauses during play with a shoulder held.
        reader.receive(PadSnapshot(buttons: [.leftShoulder, .menu]))
        #expect(reader.takePausePress() == true)
    }

    @Test func theNewButtonsHaveNamesForTheSimulatedController() {
        #expect(PadButton(rawValue: "lshoulder") == .leftShoulder)
        #expect(PadButton(rawValue: "rshoulder") == .rightShoulder)
        #expect(PadButton(rawValue: "ltrigger") == .leftTrigger)
        #expect(PadButton(rawValue: "rtrigger") == .rightTrigger)
        #expect(PadButton.a.rawValue == "a" && PadButton.menu.rawValue == "menu")
    }
}

@Suite struct TouchStickTests {
    private static let leftHalf = TouchStick.Zone(minX: 0, minY: 0, maxX: 400, maxY: 600)
    private static let rightHalf = TouchStick.Zone(minX: 440, minY: 0, maxX: 840, maxY: 600)

    private func stick(_ zone: TouchStick.Zone = leftHalf, radius: Double = 60,
                       rest: Vec2 = Vec2(100, 100)) -> TouchStick {
        var stick = TouchStick()
        stick.layout(zone: zone, radius: radius, rest: rest)
        return stick
    }

    @Test func atRestItSitsAtItsRestingPlaceWithNoVector() {
        let s = stick()
        #expect(s.center == Vec2(100, 100))
        #expect(s.vector == .zero)
        #expect(s.isActive == false)
    }

    @Test func aThumbInTheZoneMovesTheCentreUnderIt() {
        var s = stick()
        #expect(s.begin(at: Vec2(200, 300)) == true)
        #expect(s.center == Vec2(200, 300))
        #expect(s.vector == .zero)
        // A second thumb doesn't take it over.
        #expect(s.begin(at: Vec2(50, 50)) == false)
        #expect(s.center == Vec2(200, 300))
    }

    @Test func aThumbOutsideTheZoneIsRefused() {
        var s = stick()
        #expect(s.begin(at: Vec2(400, 300)) == false) // the zone's right edge is outside
        #expect(s.begin(at: Vec2(500, 300)) == false)
        #expect(s.isActive == false)
        #expect(s.begin(at: Vec2(0, 0)) == true) // its bottom-left corner is inside
    }

    @Test func dragsGiveAnAnalogueVector() {
        var s = stick()
        _ = s.begin(at: Vec2(200, 300))
        s.move(to: Vec2(230, 300))
        #expect(s.vector == Vec2(0.5, 0))
        s.move(to: Vec2(200, 255))
        #expect(s.vector == Vec2(0, -0.75))
        #expect(s.center == Vec2(200, 300))
    }

    @Test func pastTheRimTheCentreTrailsTheThumb() {
        var s = stick()
        _ = s.begin(at: Vec2(200, 300))
        s.move(to: Vec2(300, 300))
        // 100 points out with a 60-point radius: the centre follows 40 points.
        #expect(s.center == Vec2(240, 300))
        #expect(s.vector == Vec2(1, 0))
        // Coming back, the centre stays where it was pulled to.
        s.move(to: Vec2(240, 330))
        #expect(s.center == Vec2(240, 300))
        #expect(s.vector == Vec2(0, 0.5))
    }

    @Test func lettingGoReturnsToRest() {
        var s = stick()
        _ = s.begin(at: Vec2(200, 300))
        s.move(to: Vec2(250, 330))
        s.end()
        #expect(s.isActive == false)
        #expect(s.vector == .zero)
        #expect(s.center == Vec2(100, 100))
        // Moves after letting go change nothing.
        s.move(to: Vec2(10, 10))
        #expect(s.vector == .zero)
    }

    @Test func aNewLayoutMovesAnIdleStickButNotOneInUse() {
        var s = stick()
        s.layout(zone: Self.rightHalf, radius: 50, rest: Vec2(700, 90))
        #expect(s.center == Vec2(700, 90))
        _ = s.begin(at: Vec2(600, 200))
        s.layout(zone: Self.rightHalf, radius: 50, rest: Vec2(710, 95))
        #expect(s.center == Vec2(600, 200))
        s.end()
        #expect(s.center == Vec2(710, 95))
    }

    @Test func twoSticksEachTakeTheThumbInTheirOwnZone() {
        var sticks = [stick(Self.leftHalf), stick(Self.rightHalf, rest: Vec2(740, 100))]
        #expect(TouchStick.begin(&sticks, at: Vec2(600, 200)) == 1)
        #expect(TouchStick.begin(&sticks, at: Vec2(150, 200)) == 0)
        // Both taken: a third thumb goes to neither, and the crease band between them to neither.
        #expect(TouchStick.begin(&sticks, at: Vec2(160, 210)) == nil)
        sticks[0].end()
        #expect(TouchStick.begin(&sticks, at: Vec2(420, 200)) == nil)
        sticks[0].move(to: Vec2(0, 0))
        #expect(sticks[0].vector == .zero)
        #expect(sticks[1].center == Vec2(600, 200))
    }
}

@Suite struct OptionRowTests {
    private func optionsMenu(rows: [OptionKey]) -> Menu? {
        let mode = ModeDescriptor(id: "m", displayName: "M", optionRows: rows)
        var fe = CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: 10)),
                                  pose: .open, catalog: ModeCatalog(modes: [mode], loaded: "m"))
        fe.perform(.options)
        return fe.menu
    }

    @Test func aModeShowsOnlyTheRowsItLists() {
        let menu = optionsMenu(rows: [.soundVolume, .musicVolume, .haptics, .handedness])
        #expect(menu?.items.map(\.command) == [.option(.soundVolume), .option(.musicVolume), .option(.haptics),
                                               .option(.handedness), .back])
        #expect(menu?.items.contains { $0.command == .option(.gamepadLayout) } == false)
    }

    @Test func byDefaultAModeListsTheSharedRows() {
        #expect(ModeDescriptor(id: "m", displayName: "M").optionRows == [.soundVolume, .musicVolume, .haptics])
        #expect(optionsMenu(rows: OptionKey.shared)?.items.map(\.title) == ["Sound", "Music", "Haptics", "Back"])
    }

    @Test func hiddenOptionsKeepTheirStoredValues() {
        let mode = ModeDescriptor(id: "m", displayName: "M")
        var options = GameOptions()
        options.gamepadLayout = .swapped
        options.handedness = .stickRight
        var fe = CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: 10)),
                                  pose: .open, options: options, catalog: ModeCatalog(modes: [mode], loaded: "m"))
        fe.perform(.options)
        #expect(fe.adjust(by: 1) == [.optionsChanged])
        #expect(fe.options.soundVolume == options.soundVolume + 1)
        #expect(fe.options.gamepadLayout == .swapped)
        #expect(fe.options.handedness == .stickRight)
    }

    @Test func theOptionsShownFollowTheLoadedMode() {
        let full = ModeDescriptor(id: "full", displayName: "Full", optionRows: OptionKey.allCases)
        let small = ModeDescriptor(id: "small", displayName: "Small")
        for (loaded, count) in [("full", 5), ("small", 3)] as [(ModeID, Int)] {
            var fe = CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: 10)),
                                      pose: .open, catalog: ModeCatalog(modes: [full, small], loaded: loaded))
            fe.perform(.options)
            #expect(fe.menu?.items.filter(\.isAdjustable).count == count)
        }
    }
}
