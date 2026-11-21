import Foundation
import Testing
import GameCore

/// The title screen's mode choice, the switch it asks for, the per-mode high-score screen, the
/// remembered mode and the emblem.
@Suite struct FreePlayTests {
    private static let alpha = ModeDescriptor(id: "alpha", displayName: "Alpha", summary: "The first mode")
    private static let beta = ModeDescriptor(id: "beta", displayName: "Beta", summary: "The second mode")

    private static func table(_ scores: [Int]) -> HighScoreTable {
        HighScoreTable(entries: scores.map {
            HighScoreEntry(score: $0, wave: 2, date: Date(timeIntervalSince1970: 1_000_000), saved: 1)
        })
    }

    private func frontEnd(_ pose: FoldPose = .open, modes: [ModeDescriptor] = [alpha, beta], loaded: ModeID = "alpha",
                          highScores: HighScoreTable = HighScoreTable(),
                          tables: [ModeID: HighScoreTable] = [:]) -> CountingFrontEnd {
        CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: 1000)), pose: pose,
                         highScores: highScores,
                         catalog: ModeCatalog(modes: modes, loaded: loaded, tables: tables))
    }

    private func commands(_ fe: CountingFrontEnd) -> [MenuItem.Command] {
        fe.menu?.items.map(\.command) ?? []
    }

    private func item(_ fe: CountingFrontEnd, _ command: MenuItem.Command) -> MenuItem? {
        fe.menu?.items.first { $0.command == command }
    }

    // MARK: Title

    @Test func theTitleNamesTheGameAndListsEveryModeThenOptionsAndHighScores() {
        let fe = frontEnd()
        #expect(fe.menu?.heading == "Rimwatch")
        #expect(fe.menu?.subtitle == "Outpost Calder")
        #expect(commands(fe) == [.play, .chooseMode("beta"), .options, .highScores])
        #expect(fe.menu?.items.map(\.title) == ["Alpha", "Beta", "Options", "High scores"])
        #expect(fe.menu?.lines == [])
    }

    @Test func theLoadedModeIsSelectedFirstWhereverItIsListed() {
        let fe = frontEnd(loaded: "beta")
        #expect(commands(fe) == [.chooseMode("alpha"), .play, .options, .highScores])
        #expect(fe.menu?.selectedItem?.title == "Beta")
    }

    @Test func theDescriptionFollowsTheHighlightedMode() {
        var fe = frontEnd(highScores: Self.table([4_200]), tables: ["beta": Self.table([77])])
        #expect(fe.menu?.detailLines == ["The first mode", "Best 4,200"])
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.title == "Beta")
        #expect(fe.menu?.detailLines == ["The second mode", "Best 77"])
        // Options has no description of its own: the loaded mode's shows.
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.command == .options)
        #expect(fe.menu?.detailLines == ["The first mode", "Best 4,200"])
    }

    @Test func aModeWithNoScoresHasNoBestLine() {
        let fe = frontEnd()
        #expect(fe.menu?.detailLines == ["The first mode"])
    }

    @Test func closedTheModesWaitForThePhoneToOpenAndSayItOnce() {
        var fe = frontEnd(.closed)
        #expect(item(fe, .play)?.isEnabled == false)
        #expect(item(fe, .chooseMode("beta"))?.isEnabled == false)
        // Several modes keep their names; one line under the heading says why.
        #expect(item(fe, .play)?.label == "Alpha")
        #expect(fe.menu?.lines == ["Open to play"])
        #expect(fe.menu?.selectedItem?.command == .options)
        #expect(fe.choose(1).isEmpty)
        #expect(fe.perform(.chooseMode("beta")).isEmpty)
        #expect(fe.screen == .title)
        // Options and High scores still work closed.
        fe.perform(.highScores)
        #expect(fe.screen == .highScores)
        fe.back()

        fe.setPose(.open)
        #expect(fe.menu?.lines == [])
        #expect(fe.menu?.selectedItem?.command == .play)
    }

    @Test func oneModeSaysOpenToPlayOnItsItem() {
        let fe = frontEnd(.closed, modes: [Self.alpha])
        #expect(commands(fe) == [.play, .options, .highScores])
        #expect(item(fe, .play)?.label == "Open to play")
        #expect(fe.menu?.lines == [])
        var open = frontEnd(.open, modes: [Self.alpha])
        #expect(item(open, .play)?.label == "Alpha")
        #expect(open.activate() == [.newRun])
    }

    // MARK: Choosing a mode

    @Test func choosingTheLoadedModeStartsARun() {
        var fe = frontEnd()
        #expect(fe.choose(0) == [.newRun])
        #expect(fe.screen == .playing)
    }

    @Test func choosingAnotherModeAsksForASwitchAndStartsNothingHere() {
        var fe = frontEnd()
        #expect(fe.choose(1) == [.switchMode("beta")])
        #expect(fe.screen == .title)
        #expect(fe.session.isInGame == false)
        // By pad as well.
        var pad = frontEnd()
        pad.handle(.down)
        _ = pad.update(elapsed: CountingFrontEnd.activationGrace + 0.01, input: 0)
        #expect(pad.handle(.activate) == FlowCommandResult(accepted: true, effects: [.switchMode("beta")]))
    }

    @Test func choosingTheLoadedModeByIDIsPlay() {
        var fe = frontEnd()
        #expect(fe.perform(.chooseMode("alpha")) == [.newRun])
        #expect(fe.screen == .playing)
    }

    @Test func anUnknownModeOrOneChosenMidRunDoesNothing() {
        var fe = frontEnd()
        #expect(fe.perform(.chooseMode("gamma")).isEmpty)
        fe.perform(.play)
        fe.requestPause()
        #expect(fe.perform(.chooseMode("beta")).isEmpty)
    }

    @Test func theSwitchedToModeStartsWithPlay() {
        // What the app does after a switch: a front end for the chosen mode, then Play.
        var fe = frontEnd(loaded: "beta")
        #expect(fe.perform(.play) == [.newRun])
        #expect(fe.screen == .playing)
    }

    // MARK: High scores

    @Test func oneModesHighScoresNameItAndOnlyGoBack() {
        var fe = frontEnd(modes: [Self.alpha], highScores: Self.table([300]))
        fe.perform(.highScores)
        #expect(fe.menu?.subtitle == "Alpha")
        #expect(commands(fe) == [.back])
        #expect(fe.menu?.table?.rows.map { $0[1] } == ["300"])
        // Left and right change nothing.
        #expect(fe.handle(.right).accepted == false)
        #expect(fe.menu?.subtitle == "Alpha")
    }

    @Test func severalModesPageThroughTheirOwnTables() {
        var fe = frontEnd(highScores: Self.table([300]), tables: ["beta": Self.table([9_000, 50])])
        fe.perform(.highScores)
        #expect(fe.scoresShown == "alpha")
        #expect(fe.menu?.subtitle == "Alpha")
        #expect(commands(fe) == [.scoresMode, .back])
        #expect(item(fe, .scoresMode)?.value == "Alpha")
        #expect(fe.menu?.selectedItem?.command == .scoresMode)
        #expect(fe.menu?.table?.rows.map { $0[1] } == ["300"])

        #expect(fe.handle(.right) == FlowCommandResult(accepted: true))
        #expect(fe.menu?.subtitle == "Beta")
        #expect(item(fe, .scoresMode)?.value == "Beta")
        #expect(fe.menu?.table?.rows.map { $0[1] } == ["9,000", "50"])
        // It wraps, and works with the selection on Back too.
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.command == .back)
        fe.handle(.right)
        #expect(fe.menu?.subtitle == "Alpha")
        fe.handle(.left)
        #expect(fe.menu?.subtitle == "Beta")
        // Touch arrows on the row step it the same way.
        #expect(fe.select(0) == true)
        fe.adjust(by: 1)
        #expect(fe.menu?.subtitle == "Alpha")
        // Reopening starts from the loaded mode.
        fe.handle(.right)
        fe.back()
        fe.perform(.highScores)
        #expect(fe.menu?.subtitle == "Alpha")
    }

    @Test func aModeWithNoScoresSaysSo() {
        var fe = frontEnd(highScores: Self.table([300]))
        fe.perform(.highScores)
        fe.handle(.right)
        #expect(fe.menu?.subtitle == "Beta")
        #expect(fe.menu?.lines == ["No scores yet"])
        #expect(fe.menu?.table == nil)
    }

    @Test func aRunIsRecordedInTheLoadedModesTableOnly() {
        var fe = frontEnd(tables: ["beta": Self.table([9_000])])
        fe.perform(.play)
        for _ in 0..<4 { _ = fe.update(elapsed: 0.09375, input: 0) }
        fe.requestPause()
        #expect(fe.perform(.endGame) == [.highScoresChanged])
        #expect(fe.highScores.entries.map(\.score) == [120])
        #expect(fe.catalog.tables["beta"]?.entries.map(\.score) == [9_000])
    }

    // MARK: Remembered mode

    @Test func theLaunchModeIsTheRequestedThenTheRememberedThenTheFirst() {
        let registered: [ModeID] = ["alpha", "beta"]
        #expect(ModeCatalog.launchMode(registered: registered, remembered: nil) == "alpha")
        #expect(ModeCatalog.launchMode(registered: registered, remembered: "beta") == "beta")
        #expect(ModeCatalog.launchMode(registered: registered, remembered: "beta", requested: "alpha") == "alpha")
        // A mode that is no longer there is passed over.
        #expect(ModeCatalog.launchMode(registered: registered, remembered: "gone") == "alpha")
        #expect(ModeCatalog.launchMode(registered: registered, remembered: "beta", requested: "gone") == "beta")
        #expect(ModeCatalog.launchMode(registered: [], remembered: "beta") == nil)
    }

    @Test func theDefaultCatalogIsOneUnnamedModeThatPlays() {
        let fe = CountingFrontEnd(session: CountingSession(seed: 1, config: CountingRun.Config(endAfter: 10)),
                                  pose: .open)
        #expect(commands(fe) == [.play, .options, .highScores])
        #expect(fe.menu?.items.first?.title == "Play")
        #expect(fe.catalog.offersChoice == false)
    }
}

@Suite struct EmblemTests {
    @Test func theRingsFollowTheDesign() {
        #expect(Emblem.outerRing.points.count == 20)
        #expect(Emblem.innerRing.points.count == 18)
        #expect(Emblem.outerRing.closed && Emblem.innerRing.closed && Emblem.ship.closed)
        #expect(Emblem.outerRing.color == RGB(hex: 0xFF7A3D))
        #expect(Emblem.innerRing.color == RGB(hex: 0xC2552B))
        #expect(Emblem.ship.color == RGB(hex: 0x3FF6FF))
        #expect([Emblem.outerRing.width, Emblem.innerRing.width, Emblem.ship.width] == [2.8, 1.5, 2.4])
        // Point 1 of the rim: angle 2*pi/20, radius 36 + 2.2.
        let p = Emblem.outerRing.points[1]
        #expect(abs(p.x - (50 + 38.2 * cos(Double.pi / 10))) < 1e-9)
        #expect(abs(p.y - (50 + 38.2 * sin(Double.pi / 10))) < 1e-9)
        // Point 16 of the rim takes jitter 0 again; point 17 of the inner ring takes jitter[1].
        #expect(abs((Emblem.outerRing.points[16] - Vec2(50, 50)).length - 36) < 1e-9)
        #expect(abs((Emblem.innerRing.points[17] - Vec2(50, 50)).length - 28.1) < 1e-9)
        #expect(Emblem.stars.count == 4)
    }

    @Test func theShipIsTheHullTurnedUpTwentyEightDegrees() {
        #expect(Emblem.ship.points.count == Emblem.shipHull.count)
        // The nose, (1, 0) in the hull, sits 19 units from the centre, up and to the right.
        let nose = Emblem.ship.points[0]
        let angle = 28 * Double.pi / 180
        #expect(abs(nose.x - (50 + 19 * cos(angle))) < 1e-9)
        #expect(abs(nose.y - (50 - 19 * sin(angle))) < 1e-9)
        // Everything stays inside the square.
        for line in Emblem.lines {
            for point in line.points {
                #expect((0...100).contains(point.x) && (0...100).contains(point.y))
            }
        }
    }

    @Test func theHullIsTheArrowhead() {
        #expect(Emblem.shipHull == [
            Vec2(1, 0), Vec2(0.25, 0.2), Vec2(-0.5, 0.45), Vec2(-0.9, 0.45), Vec2(-0.62, 0.12), Vec2(-0.78, 0),
            Vec2(-0.62, -0.12), Vec2(-0.9, -0.45), Vec2(-0.5, -0.45), Vec2(0.25, -0.2),
        ])
    }
}
