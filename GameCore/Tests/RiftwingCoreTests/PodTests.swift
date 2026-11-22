import Testing
import GameCore
@testable import RiftwingCore

/// Pods: falling, resting on a ledge, the Rift, freeing and catching them, and hatching.
@Suite struct RiftwingPodTests {
    @Test func aPodFallsAndComesToRestOnALedge() throws {
        var r = quietRun()
        r.removeRider()
        let ledge = r.ledges[2]
        let id = r.dropPod(at: Vec2(ledge.midX, ledge.top + 120), vel: .zero, from: .glider)
        let events = run(&r, steps: seconds(4), until: { $0.kind == "podLanded" })
        #expect(events.contains { if case .podLanded(id, _, 2) = $0 { true } else { false } })
        let pod = try r.req(pod: id)
        #expect(pod.state == .resting(ledge: 2))
        #expect(abs(pod.pos.y - (ledge.top + r.tuning.podRadius)) < 1e-9)
        #expect(pod.hatchIn == r.director.podLife(forWave: 1, tuning: r.tuning))
    }

    @Test func aPodThatFallsIntoTheRiftIsLost() throws {
        var r = quietRun()
        r.removeRider()
        // Over open Rift (between the ledges of the first layout).
        let id = r.dropPod(at: Vec2(570, 120), vel: .zero, from: .glider)
        let events = run(&r, steps: seconds(6), until: { $0.kind == "podLost" })
        #expect(events.contains { if case .podLost(id, _, .rift) = $0 { true } else { false } })
        #expect(r.waveLost == 1)
        #expect(r.podsInPlay == 0)
    }

    @Test func aPodFromARoleInItsFirstAppearancesFallsMoreSlowly() throws {
        var r = quietRun()
        let early = r.dropPod(at: Vec2(560, 430), vel: .zero, from: .glider, ease: 1)
        let late = r.dropPod(at: Vec2(600, 430), vel: .zero, from: .glider, ease: 0)
        r.removeRider()
        run(&r, steps: seconds(2))
        let a = try r.req(pod: early), b = try r.req(pod: late)
        #expect(a.vel.y >= -r.tuning.podTerminal * (1 - r.director.podFallEase) - 1e-9)
        #expect(b.vel.y < a.vel.y - 50)
        #expect(a.pos.y > b.pos.y + 100)
    }

    @Test func touchingAPodFreesItsColonistAndEachFreedInAWaveScoresMore() throws {
        var r = quietRun()
        r.removeRider()
        var ids: [Int] = []
        for (i, ledge) in r.ledges.prefix(3).enumerated() {
            let id = r.dropPod(at: Vec2(ledge.midX + Double(i), ledge.top + 30), vel: .zero, from: .glider)
            ids.append(id)
        }
        run(&r, steps: seconds(3))
        #expect(r.pods.allSatisfy { if case .resting = $0.state { true } else { false } })
        r.rider.isAlive = true
        var points: [Int] = []
        for id in ids {
            let pod = try r.req(pod: id)
            r.placeRider(at: Vec2(pod.pos.x + 20, pod.pos.y + 6))
            for event in r.step(still) {
                if case .podFreed(id, _, let order, let p) = event {
                    points.append(p)
                    #expect(order == points.count)
                }
            }
        }
        #expect(points == [500, 1000, 1500])
        #expect(r.colonistsSaved == 3)
        #expect(r.waveFreed == 3)
    }

    @Test func catchingAPodInTheAirScoresDouble() throws {
        var r = quietRun()
        let id = r.dropPod(at: Vec2(570, 400), vel: .zero, from: .glider)
        // Past the moment after the drop when it cannot be taken (`aCatchNeedsPursuit`).
        r.pods[0].catchableIn = 0
        r.placeRider(at: Vec2(575, 380))
        let events = r.step(still)
        #expect(events.contains { if case .podCaught(id, _, 1, 1000) = $0 { true } else { false } })
        #expect(try r.req(pod: id).state == .freed)
    }

    @Test func podsLastLongInEarlyWavesAndShrinkToAFloor() throws {
        let waves = RiftwingWaves(), tuning = RiftwingTuning()
        #expect(waves.podLife(forWave: 1, tuning: tuning) == 20)
        var last = 99.0
        for wave in 1...30 {
            let life = waves.podLife(forWave: wave, tuning: tuning)
            #expect(life <= last)
            #expect(life >= 7)
            last = life
        }
        #expect(waves.podLife(forWave: 11, tuning: tuning) > 7)
        #expect(waves.podLife(forWave: 12, tuning: tuning) == 7)
        #expect(waves.podLife(forWave: 30, tuning: tuning) == 7)
    }

    @Test func aPodLeftTooLongWarnsThenHatchesOneGradeTougher() throws {
        for (from, into) in [(RiftwingRole.glider, RiftwingRole.striker), (.striker, .warden), (.warden, .warden), (.sower, .warden)] {
            var r = quietRun()
            // Every kind has had its debut (before then a pod hatches into its own kind).
            r.wave = 8
            r.removeRider()
            let ledge = r.ledges[1]
            let id = r.dropPod(at: Vec2(ledge.midX, ledge.top + 20), vel: .zero, from: from)
            run(&r, steps: seconds(1))
            let life = r.director.podLife(forWave: 8, tuning: r.tuning)
            var warnedAt: Double?
            var hatchedAt: Double?
            var hatched: (Int, RiftwingRole)?
            for step in 0..<seconds(life + 1) {
                for event in r.step(still) {
                    if case .hatchWarning(id, _, let becomes) = event {
                        warnedAt = Double(step) / 120
                        #expect(becomes == into)
                    }
                    if case .podHatched(id, let o, let role, _) = event {
                        hatchedAt = Double(step) / 120
                        hatched = (o, role)
                    }
                    if case .podLost(id, _, let cause) = event { #expect(cause == .hatched) }
                }
                if hatched != nil { break }
            }
            let (opponentID, role) = try #require(hatched)
            #expect(role == into)
            let w = try #require(warnedAt), h = try #require(hatchedAt)
            #expect(abs(h - w - r.tuning.hatchWarning) < 0.02)
            let o = try r.req(opponent: opponentID)
            #expect(o.hatched)
            #expect(o.body.ledge == 1)
            if case .waking = o.state {} else { Issue.record("a hatched rig stands a moment first") }
            #expect(r.waveLost == 1)
            // It takes off when it wakes.
            run(&r, steps: seconds(r.tuning.hatchWake + 0.2))
            #expect(try r.req(opponent: opponentID).state != .waking(remaining: 0))
        }
    }

    /// A hatched rig is one grade tougher (of the tougher kind once that kind has had its debut,
    /// before then of its own kind), and how much of its kind's early ease it keeps depends on
    /// the rider's rescues: a rider who has freed at least `hatchedEaseFullShare` of the
    /// colonists settled in this wave and the last meets it with all of its kind's ease; one who
    /// has freed hardly any (`hatchedEaseNoShare` or fewer: who leaves pods to hatch) meets it at
    /// full strength; between, in proportion. So a beginner slow to reach pods is not punished, and leaving pods to hatch
    /// is no way to fill the gallery with gentle opponents. Measured with
    /// `RiftwingWaves.withGentleDebuts`, where the ease also slows its flying; by default (since
    /// 2026-11-22) the ease no longer slows any rig, and a diligent rider's hatchling flies at
    /// full speed.
    @Test func aHatchedRigKeepsItsKindsEaseForARiderWhoFreesColonists() throws {
        func hatchling(freed: Int, lost: Int, previousFreed: Int = 0, previousLost: Int = 0, wave: Int = 1,
                       waves: RiftwingWaves = .withGentleDebuts) throws -> RiftwingOpponent {
            var r = quietRun(waves: waves)
            r.wave = wave
            r.removeRider()
            r.waveFreed = freed
            r.waveLost = lost
            r.previousWaveFreed = previousFreed
            r.previousWaveLost = previousLost
            let ledge = r.ledges[1]
            let id = r.dropPod(at: Vec2(ledge.midX, ledge.top + 20), vel: .zero, from: .glider, ease: 1)
            var opponent: Int?
            for _ in 0..<seconds(30) {
                for event in r.step(still) {
                    if case .podHatched(id, let o, _, _) = event { opponent = o }
                }
                if opponent != nil { break }
            }
            return try r.req(opponent: try #require(opponent))
        }
        let waves = RiftwingWaves.withGentleDebuts
        let full = waves.ease(of: .glider, inWave: 1)
        #expect(full == 1)
        // Freed every colonist so far (the hatching pod itself is the only one lost): all the ease.
        let diligent = try hatchling(freed: 3, lost: 0)
        #expect(abs(diligent.ease - full) < 1e-9)
        #expect(waves.gliderSpeedEase > 0)
        #expect(abs(diligent.speed - RiftwingTuning().stats(for: .glider).maxSpeed * (1 - waves.gliderSpeedEase)) < 1e-9)
        let plain = try hatchling(freed: 3, lost: 0, waves: RiftwingWaves())
        #expect(abs(plain.ease - full) < 1e-9)
        #expect(abs(plain.speed - RiftwingTuning().stats(for: .glider).maxSpeed) < 1e-9)
        // Freed none, in this wave or the last: full strength.
        let idle = try hatchling(freed: 0, lost: 4, previousFreed: 0, previousLost: 5, wave: 2)
        #expect(idle.ease == 0)
        #expect(abs(idle.speed - RiftwingTuning().stats(for: .glider).maxSpeed) < 1e-9)
        // The first pod of a run hatching before anything else is settled: none freed, so full
        // strength, the same as any rider who has freed none.
        #expect(try hatchling(freed: 0, lost: 0).ease == 0)
        // Last wave's rescues count: a rider who freed most of last wave's colonists keeps the
        // ease for the first hatch of this wave.
        let carried = try hatchling(freed: 0, lost: 0, previousFreed: 4, previousLost: 1, wave: 2)
        #expect(carried.ease > 0.9 * waves.ease(of: .glider, inWave: 2), "\(carried.ease)")
        // Freeing hardly any (one in six) earns none of it.
        #expect(try hatchling(freed: 1, lost: 4, wave: 1).ease == 0)
        // Between: in proportion to the share freed, from the share that earns none to the share
        // that earns all of it.
        let some = try hatchling(freed: 2, lost: 3, wave: 1)
        let share = 2.0 / 6.0
        let expected = full * (share - waves.hatchedEaseNoShare) / (waves.hatchedEaseFullShare - waves.hatchedEaseNoShare)
        #expect(expected > 0.1 && expected < 0.9)
        #expect(abs(some.ease - expected) < 1e-9, "\(some.ease)")
    }

    @Test func aWaveEndsOnlyWhenEveryPodIsSettled() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        #expect(r.wave == 1)
        // Everything sent and down, but a pod still falls.
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        let id = r.dropPod(at: Vec2(570, 300), vel: .zero, from: .glider)
        r.placeRider(at: Vec2(100, 560))
        r.rider.invulnerableTimer = .infinity
        var cleared = false
        for _ in 0..<seconds(10) {
            let events = r.step(RiftwingInput(flap: r.tick % 20 < 10))
            if has(events, "waveCleared") {
                cleared = true
                #expect(try r.req(pod: id).state == .lost)
                break
            }
            if r.pod(id)?.isUnsettled == true { #expect(r.phase == .fighting) }
        }
        #expect(cleared)
    }

    @Test func colonistsFreedInAWaveScoreABonusAtItsEnd() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        r.waveFreed = 3
        r.waveDropped = 3
        let before = r.score
        let events = r.step(still)
        #expect(events.contains { if case .waveCleared(1, 3, 750) = $0 { true } else { false } })
        #expect(r.score == before + 750)
    }

    // MARK: Pods and rock

    /// True when `p` (a pod's centre) is inside a ledge's rock.
    private func insideRock(_ r: RiftwingRun, _ p: Vec2) -> Bool {
        r.ledges.contains { $0.spans(p.x) && p.y < $0.top && p.y > $0.top - r.tuning.ledgeThickness }
    }

    /// A pod moving across into a ledge below its top is stopped by the ledge's side, as a rig
    /// is, and falls on past it: it never enters the rock.
    @Test func aPodIsStoppedByALedgesSide() throws {
        var r = quietRun()
        r.removeRider()
        // The first layout's low right shelf: 640...850, top 175.
        let id = r.dropPod(at: Vec2(630, 166), vel: .zero, from: .glider)
        r.pods[0].vel = Vec2(100, 0)
        for _ in 0..<seconds(3) {
            _ = r.step(still)
            let pod = try r.req(pod: id)
            #expect(!insideRock(r, pod.pos), "\(pod.pos)")
            if !pod.isUnsettled { break }
        }
        let pod = try r.req(pod: id)
        #expect(pod.pos.x <= 640)
    }

    /// A pod moving up into a ledge's underside is stopped by it.
    @Test func aPodIsStoppedByALedgesUnderside() throws {
        var r = quietRun()
        r.removeRider()
        let ledge = r.ledges[2]
        let id = r.dropPod(at: Vec2(ledge.midX, ledge.top - r.tuning.ledgeThickness - 12), vel: .zero, from: .glider)
        r.pods[0].vel = Vec2(0, 120)
        for _ in 0..<seconds(1) {
            _ = r.step(still)
            #expect(!insideRock(r, try r.req(pod: id).pos))
        }
    }

    /// Wherever an early pod (one that drifts and hovers) is dropped, in every layout, its
    /// centre never enters rock; it drifts only toward a ledge it reaches from above, and lands
    /// on that ledge when it does.
    @Test func anEasedPodNeverEntersRockAndLandsWhereItDrifts() throws {
        var inRock: [String] = []
        var missed: [String] = []
        for layout in RiftwingCavern.layouts.indices {
            for x in stride(from: 5.0, to: 900, by: 35) {
                for y in stride(from: 150.0, through: 560, by: 50) {
                    var r = quietRun()
                    r.removeRider()
                    r.applyLayout(layout)
                    let start = Vec2(x, y)
                    guard !insideRock(r, start) else { continue }
                    let id = r.dropPod(at: start, vel: .zero, from: .glider, ease: 1)
                    let aim = r.pods[0].driftLedge
                    var landed: Int?
                    for _ in 0..<seconds(60) {
                        for event in r.step(still) {
                            if case .podLanded(id, _, let l) = event { landed = l }
                        }
                        let pod = try r.req(pod: id)
                        if insideRock(r, pod.pos) { inRock.append("layout \(layout) from \(start) at \(pod.pos)") }
                        if !pod.isUnsettled || landed != nil { break }
                    }
                    if let aim, landed != aim { missed.append("layout \(layout) from \(start): aimed \(aim), landed \(String(describing: landed))") }
                }
            }
        }
        #expect(inRock.isEmpty, "\(inRock.count): \(inRock.prefix(5))")
        #expect(missed.isEmpty, "\(missed.count): \(missed.prefix(5))")
    }

    /// The height an early pod is held at above the Rift is clear of every ledge's rock in
    /// every layout (with room for the pod), and the pod is held there without moving across.
    @Test func anEasedPodHoversClearOfRock() throws {
        let t = RiftwingTuning(), w = RiftwingWaves()
        let hover = t.riftLevel + w.podHoverHeight
        for layout in RiftwingCavern.layouts {
            for ledge in layout.ledges {
                let clear = hover > ledge.top + t.podRadius || hover < ledge.top - t.ledgeThickness - t.podRadius
                #expect(clear, "\(layout.name) ledge \(ledge): hover \(hover)")
            }
        }
        var r = quietRun()
        r.removeRider()
        // Over open Rift in the first layout.
        let id = r.dropPod(at: Vec2(580, 215), vel: .zero, from: .glider, ease: 1)
        r.pods[0].vel = Vec2(40, 0)
        r.pods[0].driftLedge = nil
        var held = 0
        var heldX: Double?
        for _ in 0..<seconds(4) {
            _ = r.step(still)
            let pod = try r.req(pod: id)
            #expect(pod.pos.y >= hover - 1e-9)
            if abs(pod.pos.y - hover) < 1e-9 {
                held += 1
                if let x = heldX { #expect(abs(pod.pos.x - x) < 1e-9) } else { heldX = pod.pos.x }
            }
        }
        #expect(held > seconds(1))
    }
}
