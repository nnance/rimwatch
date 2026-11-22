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

    /// A Glider pays the rider little attention. At full strength, with the rider flying about
    /// far off, it flies exactly the path it would fly with no rider at all, and it wanders.
    /// Early on it will not flap up into a rider just above it; and a rider that stays put draws
    /// its wandering (`aGliderIsDrawnToARiderThatStaysPut`).
    @Test func aGliderWandersAndPaysAFarRiderNoAttention() throws {
        func path(riderThere: Bool) -> [Vec2] {
            var r = quietRun(seed: 5)
            if !riderThere { r.removeRider() }
            let id = r.place(.glider, at: Vec2(700, 450), ease: 0)
            var points: [Vec2] = []
            for step in 0..<seconds(8) {
                if riderThere {
                    // Far below the Glider's band, moving, so it is never still for long.
                    let x = 100 + Double(step % seconds(4)) * 0.4
                    r.placeRider(at: Vec2(x, 60))
                    r.rider.invulnerableTimer = .infinity
                }
                _ = r.step(still)
                if step % 60 == 0, let g = r.opponent(id) { points.append(g.pos) }
            }
            return points
        }
        let with = path(riderThere: true), without = path(riderThere: false)
        #expect(with == without)
        let span = (with.map(\.x).max() ?? 0) - (with.map(\.x).min() ?? 0)
        #expect(span > 100)
    }

    /// In its first appearances a Glider is shy of a rider just above it: it skips the flaps
    /// that would lift it into the rider, so it flaps less than with no rider there.
    @Test func anEarlyGliderWillNotFlapUpIntoARiderJustAboveIt() throws {
        func flaps(riderAbove: Bool) -> Int {
            var total = 0
            for seed: UInt64 in 1...8 {
                var r = quietRun(seed: seed)
                if !riderAbove { r.removeRider() }
                let id = r.place(.glider, at: Vec2(600, 300), ease: 1)
                var last = 99.0
                for _ in 0..<seconds(3) {
                    guard let g = r.opponent(id) else { break }
                    if riderAbove {
                        r.placeRider(at: Vec2(g.pos.x + 70, g.pos.y + 50))
                        r.rider.invulnerableTimer = .infinity
                    }
                    _ = r.step(still)
                    if let g2 = r.opponent(id) {
                        if g2.body.sinceFlap < last { total += 1 }
                        last = g2.body.sinceFlap
                    }
                }
            }
            return total
        }
        #expect(flaps(riderAbove: true) < flaps(riderAbove: false))
    }

    /// A rider that stays put for longer than the wave allows
    /// (`RiftwingTuning.gliderDrawAfter(forWave:)`) draws the Gliders' wandering to about its
    /// height, so no perch is safe for ever.
    @Test func aGliderIsDrawnToARiderThatStaysPut() throws {
        // Opponents cannot win here (a huge leniency), so the rider stays put unhurt.
        var waves = RiftwingWaves()
        waves.clashLeniencyBase = 1000
        var r = quietRun(seed: 3, waves: waves)
        let perch = Vec2(450, 560)
        let id = r.place(.glider, at: Vec2(150, 300), ease: 0)
        let allowed = r.tuning.gliderDrawAfter(forWave: 1)
        var closest = Double.infinity
        var drawnGoals = 0
        var stillTooSoon = false
        for step in 0..<seconds(allowed + 16) {
            r.placeRider(at: perch)
            _ = r.step(still)
            if Double(step) / 120 < allowed - 0.1, r.isRiderCamping { stillTooSoon = true }
            if step > seconds(allowed + 4), let g = r.opponent(id) {
                closest = min(closest, r.wrapDistance(g.pos, perch))
                // Its wandering goal is now about the rider's height, near it.
                if abs(r.dxWrap(g.goal.x, perch.x)) <= 140 + 1e-9, g.goal.y >= perch.y - 10 - 1e-9 { drawnGoals += 1 }
            }
        }
        #expect(!stillTooSoon)
        #expect(r.isRiderCamping)
        #expect(r.isRiderStill)
        #expect(drawnGoals > seconds(5))
        #expect(closest < 150, "\(closest)")
    }

    /// Resting is not camping: the time a rider may stay in one place is long, generous in the
    /// early waves and tighter later, and never short.
    @Test func restingIsAllowedForASensibleTime() throws {
        let t = RiftwingTuning()
        #expect(t.gliderDrawAfter(forWave: 1) >= 30)
        #expect(t.gliderDrawAfter(forWave: 2) >= 25)
        var last = Double.infinity
        for wave in 1...30 {
            let allowed = t.gliderDrawAfter(forWave: wave)
            #expect(allowed <= last)
            #expect(allowed >= 15)
            last = allowed
        }
        #expect(t.gliderDrawAfter(forWave: 12) < t.gliderDrawAfter(forWave: 1))
    }

    /// The time in one place runs only while the rider is fighting unprotected: not in the break
    /// between waves, and not while it is protected after returning.
    @Test func theTimeInOnePlaceRunsOnlyWhileFightingUnprotected() throws {
        var r = RiftwingRun(seed: 4)
        // The break before the first wave.
        run(&r, steps: seconds(r.tuning.firstWaveDelay - 0.1))
        #expect(r.riderStillFor == 0)
        // Protected, in the fight.
        r = quietRun()
        r.rider.invulnerableTimer = 3
        run(&r, steps: seconds(2.5))
        #expect(r.riderStillFor == 0)
        run(&r, steps: seconds(1.5))
        #expect(r.riderStillFor > 0.9 && r.riderStillFor < 1.1, "\(r.riderStillFor)")
        // A break between waves pauses it.
        r.phase = .intermission(remaining: 99)
        r.wavesEnabled = true
        let before = r.riderStillFor
        run(&r, steps: seconds(2))
        #expect(r.riderStillFor == before)
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

    /// Holds the rider pressed up against rock at `p` (rising into it every step), protected.
    private func press(_ r: inout RiftwingRun, at p: Vec2) {
        r.placeRider(at: p, vel: Vec2(0, 120))
        r.rider.invulnerableTimer = .infinity
    }

    /// A rider passing along the roof is let be: a Striker keeps out of the roof's band, where a
    /// meeting would be level. One that stays pressed against the roof (or under a ledge) is
    /// hunted there: the Striker comes up under the same rock after it.
    @Test func aStrikerHuntsARiderThatStaysPinnedAgainstTheRoof() throws {
        var r = quietRun(seed: 2)
        let spot = Vec2(450, r.tuning.roof - r.tuning.riderRadius)
        let id = r.place(.striker, at: Vec2(300, 450), ease: 0)
        let band = r.tuning.roof - r.tuning.stats(for: .striker).radius - r.tuning.roofBand
        var highestEarly = 0.0, highestLate = 0.0
        for step in 0..<seconds(10) {
            press(&r, at: spot)
            _ = r.step(still)
            let y = try r.req(opponent: id).pos.y
            if Double(step) / 120 < r.tuning.pinnedPatience { highestEarly = max(highestEarly, y) } else { highestLate = max(highestLate, y) }
        }
        #expect(r.isRiderClinging)
        #expect(highestEarly < band)
        #expect(highestLate > band - 8)
    }

    @Test func aStrikerHuntsARiderThatStaysPinnedUnderALedge() throws {
        var r = quietRun(seed: 6)
        // Under the first layout's high right shelf (530...720, top 455).
        let ledge = r.ledges[4]
        let under = Vec2(ledge.midX, ledge.top - r.tuning.ledgeThickness - r.tuning.riderRadius * r.tuning.headShare)
        let id = r.place(.striker, at: Vec2(150, 300), ease: 0)
        var closest = Double.infinity
        for step in 0..<seconds(12) {
            press(&r, at: under)
            _ = r.step(still)
            if Double(step) / 120 > r.tuning.pinnedPatience, let o = r.opponent(id) {
                closest = min(closest, r.wrapDistance(o.pos, under))
            }
        }
        #expect(r.isRiderClinging)
        #expect(closest < r.tuning.riderRadius + r.tuning.stats(for: .striker).radius + 15, "\(closest)")
    }

    /// Flying near the roof is not clinging to it: a rider holding height a little under the roof,
    /// or touching it now and then, is not pinned. Pressed against it (bumping it again and again
    /// in a short time), it is.
    @Test func onlyARiderPressedAgainstRockIsPinned() throws {
        var r = quietRun()
        let t = r.tuning
        // Holding height 15 under the roof's limit, flapping now and then, for 6 s.
        r.placeRider(at: Vec2(450, t.roof - t.riderRadius - 15))
        r.rider.invulnerableTimer = .infinity
        var pinned = false
        for step in 0..<seconds(6) {
            let flap = r.rider.vel.y < -40 && r.rider.pos.y < t.roof - t.riderRadius - 15
            _ = r.step(RiftwingInput(stick: Vec2(step % 240 < 120 ? 0.5 : -0.5, 0), flap: flap))
            if r.isRiderPinned { pinned = true }
        }
        #expect(!pinned)
        #expect(!r.isRiderCamping)
        // One bump of the roof is not pinning either.
        r.riderBumpTicks.removeAll()
        r.placeRider(at: Vec2(450, t.roof - t.riderRadius - 1), vel: Vec2(0, 200))
        _ = r.step(still)
        #expect(!r.isRiderPinned)
        // Pressed against it, bumping again and again: pinned, and after the patience, clinging.
        for _ in 0..<seconds(t.pinnedPatience + 2) {
            press(&r, at: Vec2(450, t.roof - t.riderRadius))
            _ = r.step(still)
        }
        #expect(r.isRiderPinned)
        #expect(r.isRiderClinging)
        #expect(r.isRiderCamping)
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
