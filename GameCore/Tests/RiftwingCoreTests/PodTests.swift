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
}
