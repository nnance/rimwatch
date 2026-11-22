import Testing
import GameCore
@testable import RiftwingCore

/// What each of the five opponents does.
@Suite struct RiftwingOpponentTests {
    @Test func aGliderKeepsOutOfTheRift() throws {
        for seed: UInt64 in 1...12 {
            var r = quietRun(seed: seed)
            r.removeRider()
            let id = r.place(.glider, at: Vec2(880, 380), vel: Vec2(-120, 0), ease: 1)
            var lowest = 999.0
            for _ in 0..<seconds(20) {
                _ = r.step(still)
                guard let g = r.opponent(id) else { break }
                lowest = min(lowest, g.pos.y)
            }
            #expect(r.opponent(id) != nil, "seed \(seed): fell, lowest \(lowest)")
            #expect(lowest > 40, "seed \(seed): lowest \(lowest)")
        }
    }

    @Test func aGliderWandersAndPaysTheRiderNoAttention() throws {
        // The same Glider with the rider far off on a ledge, or gone: the same path.
        func path(riderThere: Bool) -> [Vec2] {
            var r = quietRun(seed: 5)
            if !riderThere { r.removeRider() }
            r.rider.invulnerableTimer = .infinity
            let id = r.place(.glider, at: Vec2(700, 450), ease: 0)
            var points: [Vec2] = []
            for step in 0..<seconds(8) {
                _ = r.step(still)
                if step % 60 == 0, let g = r.opponent(id) { points.append(g.pos) }
            }
            return points
        }
        let with = path(riderThere: true), without = path(riderThere: false)
        // It stays clear of the rider's ledge in this seed, so its flight is the same.
        #expect(with == without)
        // And it wanders: it covers ground.
        let span = (with.map(\.x).max() ?? 0) - (with.map(\.x).min() ?? 0)
        #expect(span > 100)
    }

    /// Holds the rider still in the air at `p`, protected, every step.
    private func hold(_ r: inout RiftwingRun, at p: Vec2) {
        r.placeRider(at: p)
        r.rider.invulnerableTimer = .infinity
    }

    @Test func aStrikerClimbsAboveTheRiderThenComesDownOnIt() throws {
        var r = quietRun(seed: 2)
        let spot = Vec2(450, 300)
        hold(&r, at: spot)
        let id = r.place(.striker, at: Vec2(200, 260), ease: 0)
        var wasAbove = false, struck = false, recovered = false
        var lowestInStrike = 999.0
        for _ in 0..<seconds(10) {
            hold(&r, at: spot)
            _ = r.step(still)
            let s = try r.req(opponent: id)
            if s.pos.y > spot.y + 15 { wasAbove = true }
            if s.phase == .striking {
                struck = true
                lowestInStrike = min(lowestInStrike, s.pos.y)
            }
            if struck, s.phase == .recovering { recovered = true }
        }
        #expect(wasAbove)
        #expect(struck)
        #expect(recovered)
        #expect(lowestInStrike < spot.y + 30)
    }

    @Test func aStrikerDoesNotChaseARiderPressedAgainstTheRoof() throws {
        var r = quietRun(seed: 2)
        let spot = Vec2(450, r.tuning.roof - r.tuning.riderRadius)
        let id = r.place(.striker, at: Vec2(300, 450), ease: 0)
        var highest = 0.0
        for _ in 0..<seconds(8) {
            hold(&r, at: spot)
            _ = r.step(still)
            highest = max(highest, try r.req(opponent: id).pos.y)
        }
        // It never climbs into the roof's band, where a meeting would only be level.
        #expect(highest < r.tuning.roof - r.tuning.stats(for: .striker).radius - r.tuning.roofBand)
    }

    @Test func aWardenKeepsHeightAboveTheRiderAndDives() throws {
        var r = quietRun(seed: 4)
        let spot = Vec2(450, 250)
        let id = r.place(.warden, at: Vec2(150, 300), ease: 0)
        var highAbove = false
        var dived = 0
        for _ in 0..<seconds(12) {
            hold(&r, at: spot)
            let events = r.step(still)
            dived += events.count { if case .opponentDived(id, .warden, _) = $0 { true } else { false } }
            if try r.req(opponent: id).pos.y > spot.y + 50 { highAbove = true }
        }
        #expect(highAbove)
        #expect(dived >= 1)
    }

    @Test func aGleanerCarriesARestingPodOffTakingAtLeastTheMinimumTime() throws {
        var r = quietRun()
        r.removeRider()
        let ledge = r.ledges[1]
        let pod = r.dropPod(at: Vec2(ledge.midX, ledge.top + 10), vel: .zero, from: .glider)
        run(&r, steps: seconds(1))
        let g = r.place(.gleaner, at: Vec2(20, 350))
        var seizedAt: Double?, carriedAt: Double?, lostAt: Double?
        var withdrew = false
        for step in 0..<seconds(40) {
            for event in r.step(still) {
                let t = Double(step) / 120
                if case .podSeized(pod, g, _) = event { seizedAt = t }
                if case .podCarried(pod, g, _) = event { carriedAt = t }
                if case .podLost(pod, _, .carried) = event { lostAt = t }
                if case .opponentWithdrew(g, .gleaner, _) = event { withdrew = true }
            }
            if lostAt != nil { break }
        }
        let seized = try #require(seizedAt), carried = try #require(carriedAt), lost = try #require(lostAt)
        #expect(withdrew)
        // It holds the pod a moment before lifting it (eased longer in early waves)...
        #expect(carried - seized >= r.director.gleanerGrab(forWave: 1, tuning: r.tuning) - 0.02)
        // ... and the carry to the mouth always takes at least the minimum, so it can be answered.
        #expect(lost - carried >= r.director.gleanerMinCarry(forWave: 1, tuning: r.tuning) - 0.05)
        // A pod in a Gleaner's grip does not hatch.
        #expect(r.waveLost == 1)
    }

    @Test func aGleanerIgnoresTheRiderAndLeavesWhenThereIsNothingToTake() throws {
        var r = quietRun()
        hold(&r, at: Vec2(450, 400))
        let g = r.place(.gleaner, at: Vec2(300, 400))
        var withdrew = false
        var closest = 999.0
        for _ in 0..<seconds(10) {
            hold(&r, at: Vec2(450, 400))
            let events = r.step(still)
            if events.contains(where: { if case .opponentWithdrew(g, _, _) = $0 { true } else { false } }) { withdrew = true; break }
            if let o = r.opponent(g) { closest = min(closest, r.wrapDistance(o.pos, r.rider.pos)) }
        }
        #expect(withdrew)
        #expect(closest > 60)
    }

    @Test func aSowerLaysTetheredMinesButNotBesideTheRider() throws {
        var r = quietRun()
        r.removeRider()
        let s = r.place(.sower, at: Vec2(100, 400), vel: Vec2(70, 0), ease: 0)
        var laid = 0
        for _ in 0..<seconds(20) {
            for event in r.step(still) {
                if case .mineLaid(_, s, _) = event { laid += 1 }
            }
            // At most its limit at once.
            #expect(r.mines.count { $0.sower == s } <= r.tuning.minesPerSower)
        }
        #expect(laid >= 4)
        for mine in r.mines {
            // Hanging on its tether below the anchor, swaying a little.
            #expect(abs(mine.pos.y - (mine.anchor.y - r.tuning.mineTether)) < 1e-9)
            #expect(abs(r.dxWrap(mine.anchor.x, mine.pos.x)) <= r.tuning.mineSway + 1e-9)
        }

        // With the rider right beside it, it lays none.
        var near = quietRun()
        let s2 = near.place(.sower, at: Vec2(450, 400), ease: 0)
        var nearLaid = 0
        for _ in 0..<seconds(8) {
            near.placeRider(at: Vec2(near.opponent(s2)!.pos.x + 40, 400))
            near.rider.invulnerableTimer = .infinity
            nearLaid += count(near.step(still), "mineLaid")
        }
        #expect(nearLaid == 0)
    }

    @Test func minesTimeOut() throws {
        var r = quietRun()
        r.removeRider()
        let id = r.takeID()
        r.mines.append(RiftwingMine(id: id, sower: 99, anchor: Vec2(300, 400), pos: Vec2(300, 366)))
        let events = run(&r, steps: seconds(r.tuning.mineLifetime + 0.1))
        #expect(events.contains { if case .mineCleared(id, _, .expired) = $0 { true } else { false } })
        #expect(r.mines.isEmpty)
    }

    @Test func aSowerInItsFirstAppearancesLaysFewerMinesAndHoldsFewer() throws {
        func laid(ease: Double) -> (laid: Int, most: Int) {
            var r = quietRun()
            r.removeRider()
            let s = r.place(.sower, at: Vec2(100, 400), vel: Vec2(70, 0), ease: ease)
            r.opponents[r.index(of: s)].mineTimer = r.tuning.mineInterval * (1 + r.director.sowerIntervalEase * ease)
            var count = 0, most = 0
            for _ in 0..<seconds(30) {
                count += r.step(still).count { if case .mineLaid = $0 { true } else { false } }
                most = max(most, r.mines.count)
            }
            return (count, most)
        }
        let early = laid(ease: 1), full = laid(ease: 0)
        #expect(early.laid < full.laid)
        #expect(early.most <= RiftwingTuning().minesPerSower - 2)
        #expect(full.most == RiftwingTuning().minesPerSower)
    }
}
