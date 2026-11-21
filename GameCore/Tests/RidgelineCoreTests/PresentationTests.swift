import Foundation
import Testing
import GameCore
@testable import RidgelineCore

/// Two colonists caught and brought home at the first outpost.
private func deliverTwo(_ sim: inout Simulation) throws -> [GameEvent] {
    sim.player.pos.y = 400
    for index in 0..<2 {
        sim.colonists[index].pos = sim.player.pos
        sim.colonists[index].state = .falling(speed: 0, from: 300)
    }
    run(&sim, maxSteps: 1)
    let outpost = try #require(sim.world.outposts.first)
    sim.player.pos = Vec2(outpost.x, outpost.groundY + 30)
    return run(&sim, maxSteps: 1)
}

@Suite struct ShieldChargedAndSavedTests {
    @Test func fillingTheShieldSaysSoOnceAndDeliveriesAreCounted() throws {
        var sim = quietSimulation()
        #expect(sim.colonistsSaved == 0)
        let events = try deliverTwo(&sim)
        #expect(events.count { $0 == .shieldCharged } == 1)
        #expect(sim.colonistsSaved == 2)

        // Already full: another delivery does not announce it again.
        let more = try deliverTwo(&sim)
        #expect(!more.contains(.shieldCharged))
        #expect(sim.colonistsSaved == 4)
    }
}

@Suite struct FrontEndPresentationTests {
    @Test func titleShowsTheBestScore() {
        let table = HighScoreTable(entries: [HighScoreEntry(score: 12_340, wave: 6, date: Date())])
        let menu = FrontEnd.menu(for: .title, session: GameSession(seed: 1), pose: .open,
                                 options: GameOptions(), highScores: table)
        #expect(menu?.detailLines == ["Best 12,340"])
        let empty = FrontEnd.menu(for: .title, session: GameSession(seed: 1), pose: .open,
                                  options: GameOptions(), highScores: HighScoreTable())
        #expect(empty?.detailLines == [])
    }

    @Test func gameOverShowsWaveSavedAndPlacement() {
        var fe = FrontEnd(session: GameSession(seed: 1), pose: .open)
        fe.perform(.play)
        fe.session.simulation.wave = 4
        fe.session.simulation.colonistsSaved = 3
        fe.session.simulation.score = 250
        fe.session.simulation.player.lives = 1
        fe.session.simulation.addEnemy(kind: .husk, at: fe.session.simulation.player.pos, state: .hunting)
        _ = fe.update(elapsed: 0.05, input: idle)
        guard case .gameOver = fe.screen else {
            Issue.record("expected game over, got \(fe.screen)")
            return
        }
        let lines = fe.menu?.lines ?? []
        #expect(lines.contains("Wave 4"))
        #expect(lines.contains("Colonists saved 3"))
        #expect(lines.contains("New high score: #1"))
        #expect(fe.highScores.entries.first?.saved == 3)
        #expect(fe.highScores.entries.first?.wave == 4)
    }

    @Test func highScoresScreenIsATableWithTheLatestHighlighted() {
        let table = HighScoreTable(entries: [
            HighScoreEntry(score: 900, wave: 4, date: Date(timeIntervalSinceReferenceDate: 900), saved: 2),
            HighScoreEntry(score: 12_000, wave: 9, date: Date(timeIntervalSinceReferenceDate: 100), saved: 11),
        ])
        let menu = FrontEnd.menu(for: .highScores, session: GameSession(seed: 1), pose: .open,
                                 options: GameOptions(), highScores: table)
        let grid = menu?.table
        #expect(grid?.columns.map(\.title) == ["#", "Score", "Wave", "Saved", "Date"])
        #expect(grid?.rows.map { Array($0.prefix(4)) } == [["1", "12,000", "9", "11"], ["2", "900", "4", "2"]])
        #expect(grid?.highlightedRow == 1)
        #expect(menu?.items.map(\.command) == [.back])
    }
}

@Suite struct ScannerProjectionTests {
    let width = 7200.0

    @Test func theCentreIsInTheMiddleAndTheFarSideAtTheEnds() {
        let p = ScannerProjection(worldWidth: width, worldHeight: 600, centerX: 1000)
        #expect(p.x(1000) == 0.5)
        #expect(abs(p.x(1000 + 1800) - 0.75) < 1e-9)
        #expect(abs(p.x(1000 - 1800) - 0.25) < 1e-9)
        // Half a world away is an end of the strip.
        #expect(p.x(1000 + 3600) == 0 || p.x(1000 + 3600) == 1)
    }

    @Test func pointsAcrossTheSeamStayBesideTheCentre() {
        // Camera just right of the seam: a point just left of it is just left of centre.
        let p = ScannerProjection(worldWidth: width, worldHeight: 600, centerX: 20)
        #expect(abs(p.x(7180) - (0.5 - 40 / width)) < 1e-9)
        #expect(abs(p.x(60) - (0.5 + 40 / width)) < 1e-9)
        let q = ScannerProjection(worldWidth: width, worldHeight: 600, centerX: 7190)
        #expect(abs(q.x(10) - (0.5 + 20 / width)) < 1e-9)
        for x in stride(from: 0.0, to: width, by: 97) {
            #expect((0...1).contains(q.x(x)))
        }
    }

    @Test func theWorldPictureOriginTilesTheStrip() {
        for center in [0.0, 10, 3599, 3600, 3601, 7199] {
            let p = ScannerProjection(worldWidth: width, worldHeight: 600, centerX: center)
            let origin = p.originX
            #expect(origin > 0 && origin <= 1)
            // World x lies at origin + x / width in the first copy or one strip to the left.
            for x in [0.0, 1000, 5000, 7100] {
                var expected = origin + x / width
                if expected > 1 { expected -= 1 }
                #expect(abs(expected - p.x(x)) < 1e-9 || abs(abs(expected - p.x(x)) - 1) < 1e-9, "c \(center) x \(x)")
            }
        }
    }

    @Test func visibleRangeIsCentredAndClamped() {
        let p = ScannerProjection(worldWidth: width, worldHeight: 600, centerX: 0)
        let r = p.visibleRange(halfWidth: 450)
        #expect(abs(r.lowerBound - (0.5 - 450 / width)) < 1e-9)
        #expect(abs(r.upperBound - (0.5 + 450 / width)) < 1e-9)
        #expect(p.visibleRange(halfWidth: 99_999) == 0...1)
        #expect(p.y(-5) == 0 && p.y(300) == 0.5 && p.y(900) == 1)
    }

    @Test func marksFollowState() {
        #expect(ScannerMark.forColonist(.grounded) == .colonist(.grounded))
        #expect(ScannerMark.forColonist(.held(by: 3)) == .colonist(.held))
        #expect(ScannerMark.forColonist(.falling(speed: 1, from: 2)) == .colonist(.falling))
        #expect(ScannerMark.forColonist(.carried) == .colonist(.carried))
        #expect(ScannerMark.forColonist(.lost) == nil)
        #expect(ScannerMark.forOutpost(integrity: 1) == .outpost(.intact))
        #expect(ScannerMark.forOutpost(integrity: 0.4) == .outpost(.damaged))
        #expect(ScannerMark.forOutpost(integrity: 0) == .outpost(.destroyed))
    }
}

@Suite struct HUDReadoutTests {
    @Test func readsTheSimulationWithoutChangingIt() throws {
        var sim = quietSimulation()
        let fresh = HUDReadout(sim)
        #expect(fresh.wave == 1)
        #expect(fresh.lives == sim.tuning.startingLives)
        #expect(fresh.shockwaves == sim.tuning.startingShockwaves)
        #expect(fresh.blinkReadiness == 1)
        #expect(fresh.multiplier == 1)
        #expect(fresh.carried == 0)
        #expect(fresh.survivors == sim.colonists.count)

        sim.player.pos.y = 400
        for index in 0..<3 {
            sim.colonists[index].pos = sim.player.pos
            sim.colonists[index].state = .falling(speed: 0, from: 300)
        }
        run(&sim, maxSteps: 1)
        run(&sim, maxSteps: 1, input: InputState(blink: true))
        let carrying = HUDReadout(sim)
        #expect(carrying.carried == 3)
        #expect(carrying.multiplier == 3)
        #expect(carrying.blinkReadiness < 0.01)
        let tickBefore = sim.tick
        _ = HUDReadout(sim)
        #expect(sim.tick == tickBefore)
    }
}

@Suite struct FeedbackCueTests {
    /// One of every event case.
    static let everyEvent: [GameEvent] = [
        .waveStarted(1), .waveCleared(wave: 1, bonus: 100), .playerFired(at: .zero, facing: 1),
        .playerOverheated, .playerBlinked(from: .zero, to: .zero), .shockwave(at: .zero), .shieldCharged,
        .shieldBroken, .playerDestroyed(at: .zero, livesLeft: 1), .playerRespawned, .extraLife,
        .enemySpawned(id: 1, kind: .harvester), .enemyFired(at: .zero), .enemyHit(id: 1, at: .zero),
        .enemyDestroyed(id: 1, kind: .brood, at: .zero, points: 1), .huskFormed(id: 1, at: .zero),
        .mineLaid(id: 1, at: .zero), .lancerTelegraph(id: 1), .lancerCharged(id: 1),
        .anchorLanded(id: 1, outpost: 0), .colonistGrabbed(id: 1), .colonistDropped(id: 1),
        .colonistCaught(id: 1), .colonistDelivered(id: 1, outpost: 0, points: 1), .colonistLanded(id: 1),
        .colonistLost(id: 1, at: .zero), .outpostDestroyed(id: 0), .outpostRestored(id: 0), .blackoutBegan,
        .blackoutEnded, .gameOver(score: 1),
    ]

    @Test func everyEventHasASoundPatchInTheFirstTheme() {
        let theme = AlienFrontier()
        for event in Self.everyEvent {
            let patch = theme.sound(for: event)
            #expect(patch?.name.hasPrefix("frontier.") == true, "\(event)")
        }
        // Different enemies explode differently.
        #expect(theme.sound(for: .enemyDestroyed(id: 1, kind: .brood, at: .zero, points: 1))
            != theme.sound(for: .enemyDestroyed(id: 1, kind: .harvester, at: .zero, points: 1)))
    }

    @Test func frequentEventsAreNotFeltAndBigOnesAre() {
        #expect(HapticCue.cue(for: .playerFired(at: .zero, facing: 1)) == nil)
        #expect(HapticCue.cue(for: .enemyFired(at: .zero)) == nil)
        #expect(HapticCue.cue(for: .playerDestroyed(at: .zero, livesLeft: 0)) == .rumble)
        #expect(HapticCue.cue(for: .shieldBroken) == .impact)
        #expect(HapticCue.cue(for: .shieldCharged) == .doubleTap)
    }
}

@Suite struct StoredTableNormalisationTests {
    /// Twelve old-format entries (no `saved`), out of order, plus one that can't be read and one
    /// with a zero score.
    static let messy: String = {
        let scores = [300, 9000, 1200, 50, 7000, 4400, 800, 15000, 2600, 100, 5100, 3300]
        var items = scores.enumerated().map { i, score in
            #"{"score":\#(score),"wave":\#(i + 1),"date":\#(700000000 + i)}"#
        }
        items.append(#"{"score":"lots","wave":1,"date":1}"#)
        items.append(#"{"score":0,"wave":1,"date":2}"#)
        return #"{"entries":["# + items.joined(separator: ",") + "]}"
    }()

    @Test func unsortedAndOverLongStoredDataDecodesNormalised() throws {
        let table = try JSONDecoder().decode(HighScoreTable.self, from: Data(Self.messy.utf8))
        #expect(table.entries.count == HighScoreTable.capacity)
        #expect(table.entries.map(\.score) == [15000, 9000, 7000, 5100, 4400, 3300, 2600, 1200, 800, 300])
        #expect(table.best?.score == 15000)
        #expect(table.entries.allSatisfy { $0.saved == 0 })
    }

    @Test func insertingIntoADecodedTableLandsInRank() throws {
        var table = try JSONDecoder().decode(HighScoreTable.self, from: Data(Self.messy.utf8))
        #expect(table.qualifies(250) == false)
        let rank = table.insert(HighScoreEntry(score: 6000, wave: 4, date: Date()))
        #expect(rank == 3)
        #expect(table.entries.map(\.score).prefix(5) == [15000, 9000, 7000, 6000, 5100])
        #expect(table.entries.count == HighScoreTable.capacity)
        #expect(table.entries.last?.score == 800)
    }

    @Test func titleBestIsTheHighestStoredScore() throws {
        let table = try JSONDecoder().decode(HighScoreTable.self, from: Data(Self.messy.utf8))
        let menu = FrontEnd.menu(for: .title, session: GameSession(seed: 1), pose: .open,
                                 options: GameOptions(), highScores: table)
        #expect(menu?.detailLines == ["Best 15,000"])
    }

    @Test func equalScoresKeepTheirOrder() {
        let a = HighScoreEntry(score: 500, wave: 1, date: Date(timeIntervalSinceReferenceDate: 1))
        let b = HighScoreEntry(score: 500, wave: 2, date: Date(timeIntervalSinceReferenceDate: 2))
        #expect(HighScoreTable(entries: [a, b]).entries == [a, b])
    }
}

@Suite struct BlinkLandingTests {
    @Test func blinkReportsWhereTheShipEndsUpWithinTheFlyingBand() {
        var sim = quietSimulation()
        sim.player.pos.y = sim.world.ceiling - 10
        let up = run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, 1), blink: true))
        guard case .playerBlinked(_, let to)? = up.first(where: { if case .playerBlinked = $0 { true } else { false } })
        else {
            Issue.record("no blink")
            return
        }
        #expect(to.y <= sim.world.ceiling)
        #expect(abs(to.y - sim.player.pos.y) < 1e-9)

        sim.player.blinkCooldown = 0
        run(&sim, maxSteps: 1)
        let down = run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, -1), blink: true))
        guard case .playerBlinked(_, let low)? = down.first(where: { if case .playerBlinked = $0 { true } else { false } })
        else {
            Issue.record("no second blink")
            return
        }
        #expect(low.y >= sim.world.groundHeight(at: low.x) + sim.tuning.playerRadius)
    }
}

@Suite struct FrontEndSelectTests {
    @Test func selectingAnOptionRowChangesNothing() {
        var fe = FrontEnd(session: GameSession(seed: 1), pose: .open)
        fe.perform(.options)
        let before = fe.options
        #expect(fe.select(1) == true)
        #expect(fe.menu?.selectedItem?.command == .option(.musicVolume))
        #expect(fe.options == before)
        #expect(fe.adjust(by: 1) == [.optionsChanged])
        #expect(fe.options.musicVolume == before.musicVolume + 1)
        #expect(fe.select(99) == false)
    }
}
