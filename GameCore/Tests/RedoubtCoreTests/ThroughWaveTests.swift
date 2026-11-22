import Testing
import GameCore
@testable import RedoubtCore

/// Refinement 6: Gleaners come in through the wave in ones and twos, every seizure takes a least
/// time that eases by the Gleaners' appearances to a floor, and the Spitters' and Burrows' eases
/// are counted in their own appearances. `RedoubtWaves.beforeGleanersThroughWave` gives the game
/// before it.
@Suite struct ThroughWaveTests {
    /// A real run stepped to the start of `wave`, each earlier wave ended as if everything had been
    /// shot.
    private func run(toWave wave: Int, seed: UInt64 = 6, waves: RedoubtWaves = RedoubtWaves()) throws -> RedoubtRun {
        var r = RedoubtRun(seed: seed, waves: waves)
        r.orb.invulnerableTimer = 1e9
        while r.wave < wave {
            RedoubtCoreTests.run(&r, steps: seconds(5)) { $0.isWaveStarted }
            guard r.wave < wave else { break }
            r.pendingIndex = r.pending.count
            r.quota = 0
            r.arrivals.removeAll()
            r.enemies.removeAll()
        }
        try #require(r.wave == wave)
        return r
    }

    /// The Gleaners' waves, and their appearances, read from the wave makeup.
    private static let gleanerWaves = [2, 4, 7, 9, 10, 11, 12, 13, 14]

    // MARK: The arrival schedule

    /// Each wave's first Gleaner lands `gleanerFirstArrival` after the opening crowd (later in
    /// the Gleaners' early appearances, with the crowd from their eighth), on the clock alone;
    /// each of the rest is due once its share of the Skitter quota has gone (spread evenly from
    /// `gleanerSpreadStart` to `gleanerSpreadEnd`), or `gleanerFallbackGap` seconds after the one
    /// before at the latest. The Gleaners' numbers are those of the game before.
    @Test func theArrivalScheduleFollowsTheGleanersAppearances() throws {
        let waves = RedoubtWaves()
        let firsts: [Int: Double] = [2: 10, 4: 9, 7: 8, 9: 6, 10: 4, 11: 2, 12: 1, 13: 0, 14: 0, 20: 0]
        #expect(waves.gleanerFirstGroup == 1)
        for (wave, first) in firsts {
            let spawns = waves.spawns(forWave: wave)
            let plan = waves.arrivals(forWave: wave)
            #expect(plan.map(\.role) == spawns.map(\.role), "wave \(wave)")
            for i in plan.indices where plan[i].role != .gleaner {
                #expect(plan[i].delay == spawns[i].delay && plan[i].afterQuotaSpent == nil)
            }
            let gleaners = plan.indices.filter { plan[$0].role == .gleaner }
            try #require(gleaners.count >= 2)
            let head = plan[gleaners[0]]
            #expect(abs(head.delay - (spawns[gleaners[0]].delay + first)) < 1e-9, "wave \(wave)")
            #expect(head.afterQuotaSpent == nil)
            let rest = Array(gleaners.dropFirst())
            for (k, i) in rest.enumerated() {
                let share = 0.35 + 0.45 * Double(k) / Double(rest.count - 1)
                #expect(abs((plan[i].afterQuotaSpent ?? -1) - share) < 1e-9, "wave \(wave) Gleaner \(k + 2)")
                #expect(abs(plan[i].delay - (head.delay + 8 * Double(k + 1))) < 1e-9, "wave \(wave) Gleaner \(k + 2)")
            }
        }
        // As many Gleaners as before, in the same waves.
        let before = RedoubtWaves.beforeGleanersThroughWave
        for wave in 0...24 {
            #expect(waves.crowdCount(of: .gleaner, inWave: wave) == before.crowdCount(of: .gleaner, inWave: wave))
        }
        #expect([2, 4, 7, 9, 10, 11, 12].map { waves.crowdCount(of: .gleaner, inWave: $0) } == [4, 4, 5, 6, 7, 7, 8])
        // Before: all of a wave's Gleaners land together, on the clock.
        for wave in [2, 4, 7, 9] {
            let plan = before.arrivals(forWave: wave)
            let spawns = before.spawns(forWave: wave)
            #expect(plan.allSatisfy { $0.afterQuotaSpent == nil })
            for i in plan.indices {
                #expect(plan[i].delay == before.landing(of: spawns[i], inWave: wave))
            }
        }
    }

    /// The quota brings each Gleaner in: the first on the clock, then each of the rest as soon as
    /// its share of the quota has been sent in, in order. The wave cannot end while any is still
    /// to come.
    @Test func gleanersComeInAsTheQuotaIsSpent() throws {
        var r = try run(toWave: 9)
        let plan = r.director.arrivals(forWave: 9).filter { $0.role == .gleaner }
        try #require(r.pending.count - r.pendingIndex == plan.count)
        let total = r.waveQuota
        try #require(total > 0)
        var order: [(clock: Double, spent: Double)] = []
        for _ in 0..<seconds(60) {
            // Kill a few every half second, as a player would, so the quota is drawn on.
            if r.tick % 60 == 0 { r.enemies.removeAll { $0.role == .skitter && $0.id % 3 == 0 } }
            let clock = r.waveClock
            for event in r.step(still) {
                if case .arrivalTelegraphed(_, .gleaner, _) = event { order.append((clock + RedoubtRun.timeStep, r.quotaSpent)) }
                #expect(!event.isWaveCleared)
            }
            if r.pendingIndex == r.pending.count { break }
        }
        try #require(order.count == plan.count)
        // The first on the clock; each of the rest when its share was spent (or its time came).
        #expect(order[0].clock >= plan[0].delay - r.tuning.telegraphTime - 1e-9)
        for k in 1..<plan.count {
            let share = try #require(plan[k].afterQuotaSpent)
            #expect(order[k].spent >= share - 1e-9 || order[k].clock >= plan[k].delay - r.tuning.telegraphTime - 1e-9,
                    "Gleaner \(k + 1): \(order[k])")
            #expect(order[k].clock >= order[k - 1].clock)
        }
        // Spread through the wave, not in one burst.
        #expect(order.last!.clock - order[0].clock >= 5)
    }

    /// A wave whose floor is not being cleared still gets its Gleaners, on the clock fallback.
    @Test func aStalledWaveStillGetsItsGleanersOnTheClock() throws {
        var r = try run(toWave: 2)
        let plan = r.director.arrivals(forWave: 2).filter { $0.role == .gleaner }
        let quota = r.quota
        var telegraphed: [Double] = []
        for _ in 0..<seconds(40) {
            // No top-up groups, so the quota goes nowhere.
            r.groupCooldown = 1e9
            let clock = r.waveClock
            for event in r.step(still) {
                if case .arrivalTelegraphed(_, .gleaner, _) = event { telegraphed.append(clock + RedoubtRun.timeStep) }
            }
        }
        // The quota went nowhere, so each came at its time.
        #expect(r.quota == quota)
        try #require(telegraphed.count == plan.count)
        for (k, at) in telegraphed.enumerated() {
            #expect(abs(at - (plan[k].delay - r.tuning.telegraphTime)) <= RedoubtRun.timeStep + 1e-9, "Gleaner \(k + 1) at \(at)")
        }
    }

    /// Everything shot and the quota spent: the wave waits only for its first Gleaner's time, the
    /// rest come in straight after it (none is held back by a quota that is gone), and once they
    /// are shot the wave ends.
    @Test func theWaveWaitsForItsGleanersAndNeverStalls() throws {
        var r = try run(toWave: 4)
        let plan = r.director.arrivals(forWave: 4).filter { $0.role == .gleaner }
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        #expect(r.enemiesHoldingWave == plan.count)
        var telegraphed: [Double] = []
        for _ in 0..<seconds(12) {
            let clock = r.waveClock
            for event in r.step(still) {
                if case .arrivalTelegraphed(_, .gleaner, _) = event { telegraphed.append(clock + RedoubtRun.timeStep) }
                #expect(!event.isWaveCleared)
            }
        }
        try #require(telegraphed.count == plan.count)
        let first = plan[0].delay - r.tuning.telegraphTime
        #expect(telegraphed.allSatisfy { abs($0 - first) <= RedoubtRun.timeStep + 1e-9 }, "\(telegraphed)")
        #expect(r.enemies.count { $0.role == .gleaner } == plan.count)
        r.enemies.removeAll()
        let end = RedoubtCoreTests.run(&r, steps: seconds(1)) { $0.isWaveCleared }
        #expect(end.contains { $0.isWaveCleared })
    }

    /// Gleaners still to come through the wave do not count toward the floor target, so the floor
    /// stays full of Skitters while they wait; one arriving puts the floor one over its target
    /// until the next kill. (The first group, landing late on the clock, counts as before.)
    @Test func gleanersStillToComeDoNotThinTheFloor() throws {
        var r = try run(toWave: 7)
        RedoubtCoreTests.run(&r, steps: seconds(1))
        let target = r.director.floorTarget(forWave: 7)
        let waiting = r.pending[r.pendingIndex...].filter { $0.afterQuotaSpent != nil }.count
        let late = r.pending[r.pendingIndex...].filter { $0.afterQuotaSpent == nil }.count
        try #require(waiting > 0 && late == 1)
        r.enemies.removeLast(20)
        RedoubtCoreTests.run(&r, steps: seconds(2))
        let onFloor = r.enemies.count { $0.role.holdsWave } + r.arrivals.count { $0.role.holdsWave }
        #expect(onFloor + late == target)
        #expect(r.shootableOnFloor == target)
        // Spend the quota: the rest come in on top of a full floor, one each.
        r.quota = 0
        RedoubtCoreTests.run(&r, steps: seconds(10))
        #expect(r.pendingIndex == r.pending.count)
        #expect(r.shootableOnFloor <= target + waiting + 1)
    }

    /// The orb lost while Gleaners are still to come: they come and land as usual, clear of where
    /// it will respawn, and the wave still ends once they are shot.
    @Test func losingTheOrbMidScheduleStallsNothing() throws {
        var r = try run(toWave: 2)
        let gleaners = r.pending.count - r.pendingIndex
        try #require(gleaners == 4)
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        // Lost just before the first one's marker shows (9 s in), so all are telegraphed while it
        // is down.
        RedoubtCoreTests.run(&r, steps: seconds(8.6) - seconds(r.waveClock))
        try #require(r.pendingIndex == 0)
        r.orb.invulnerableTimer = 0
        r.destroyOrb(cause: .shot(id: 0))
        try #require(!r.orb.isAlive && !r.isGameOver)
        var arrived = 0
        for _ in 0..<seconds(5) {
            if r.orb.isAlive { r.orb.invulnerableTimer = 1e9 }
            for event in r.step(still) {
                if case .arrivalTelegraphed(_, .gleaner, let at) = event {
                    #expect(r.isClearOfOrb(at, by: r.tuning.safeDistance))
                }
                if case .enemyArrived(_, .gleaner, _) = event { arrived += 1 }
                #expect(!event.isWaveCleared)
            }
        }
        #expect(arrived == gleaners)
        #expect(r.orb.isAlive)
        r.enemies.removeAll()
        r.arrivals.removeAll()
        let end = RedoubtCoreTests.run(&r, steps: seconds(1)) { $0.isWaveCleared }
        #expect(end.contains { $0.isWaveCleared })
        RedoubtCoreTests.run(&r, steps: seconds(4)) { $0.isWaveStarted }
        #expect(r.wave == 3)
    }

    /// The game ending with Gleaners still to come: the run stops where it is and stepping on is
    /// harmless.
    @Test func theGameEndingMidScheduleStopsCleanly() throws {
        var r = try run(toWave: 9)
        RedoubtCoreTests.run(&r, steps: seconds(12))
        let left = r.pending.count - r.pendingIndex
        try #require(left > 0 && r.pendingIndex > 0)
        r.orb.lives = 1
        r.orb.invulnerableTimer = 0
        r.destroyOrb(cause: .shot(id: 0))
        #expect(r.isGameOver)
        let tick = r.tick
        let index = r.pendingIndex
        for _ in 0..<seconds(20) {
            #expect(r.step(still).isEmpty)
        }
        #expect(r.tick == tick)
        #expect(r.pendingIndex == index)
    }

    // MARK: The least seizure time

    /// The least time from seizure to loss, by the Gleaners' appearances: 8 s in their first wave,
    /// 7, 6, 5.5, 5, 4.5, 4 and 3.5, then the floor of 3 s for good, also in a wave without
    /// Gleaners. Never under the floor anywhere.
    @Test func theLeastSeizureTimeEasesToAFloor() throws {
        let waves = RedoubtWaves()
        let expected: [Int: Double] = [2: 8, 4: 7, 7: 6, 9: 5.5, 10: 5, 11: 4.5, 12: 4, 13: 3.5, 14: 3, 30: 3,
                                       0: 3, 1: 3, 3: 3, 5: 3, 6: 3, 8: 3]
        for (wave, time) in expected {
            #expect(waves.seizeTime(forWave: wave) == time, "wave \(wave)")
        }
        #expect(waves.seizeTimeFloor == 3)
        let times = Self.gleanerWaves.map { waves.seizeTime(forWave: $0) }
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 >= $1 })
        #expect((0...60).allSatisfy { waves.seizeTime(forWave: $0) >= waves.seizeTimeFloor })
        // No drag slowdown: the least time does that work.
        #expect((0...20).allSatisfy { waves.gleanerDragScale(forWave: $0) == 1 })
        // Before: no least time at all.
        #expect((0...20).allSatisfy { RedoubtWaves.beforeGleanersThroughWave.seizeTime(forWave: $0) == 0 })
    }

    /// Seconds from a colonist's seizure to its loss, with the Gleaner starting `gap` above it and
    /// the colonist at `at`, in `wave`; and the fastest the Gleaner moved meanwhile.
    private func drag(waves: RedoubtWaves = RedoubtWaves(), wave: Int, at: Vec2, gap: Double = 30) throws -> (time: Double, speed: Double) {
        var r = quietRun()
        r.director = waves
        r.wave = wave
        let colonist = r.addColonist(at: at)
        let gleaner = r.addEnemy(.gleaner, at: at + Vec2(0, gap))
        RedoubtCoreTests.run(&r, steps: seconds(2)) { if case .colonistSeized = $0 { true } else { false } }
        try #require(try r.req(colonist: colonist).state == .seized(by: gleaner))
        var steps = 0
        var fastest = 0.0
        var last = try r.req(enemy: gleaner).pos
        while steps < seconds(20) {
            steps += 1
            let events = r.step(still)
            if events.contains(where: { if case .colonistTaken(colonist, .gleaner, gleaner, _) = $0 { true } else { false } }) { break }
            let now = try r.req(enemy: gleaner).pos
            fastest = max(fastest, distance(now, last) / RedoubtRun.timeStep)
            last = now
        }
        return (Double(steps) * RedoubtRun.timeStep, fastest)
    }

    /// A colonist beside a wall is held for the least time, the Gleaner creeping toward the wall
    /// more slowly to fit; one far from the wall is dragged at the full speed, taking longer. In
    /// the game before, a colonist beside a wall went at once.
    @Test func aSeizureAlwaysTakesAtLeastTheLeastTime() throws {
        let waves = RedoubtWaves()
        for wave in [0, 2, 4, 7, 9, 10, 11, 12, 13, 14, 20] {
            let near = try drag(wave: wave, at: Vec2(450, 20))
            let least = waves.seizeTime(forWave: wave)
            #expect(abs(near.time - least) <= 2 * RedoubtRun.timeStep + 1e-9, "wave \(wave): \(near.time) s")
            #expect(near.speed < RedoubtTuning().gleanerDragSpeed * 0.5, "wave \(wave)")
        }
        // Far from every wall: the full speed, so longer than the least time.
        let far = try drag(wave: 20, at: Vec2(300, 300))
        #expect(far.time > 4)
        #expect(abs(far.speed - RedoubtTuning().gleanerDragSpeed) < 0.5)
        // Before: lost in well under a second.
        let before = try drag(waves: .beforeGleanersThroughWave, wave: 11, at: Vec2(450, 20))
        #expect(before.time < 1)
    }

    // MARK: Eases by appearance

    /// Which appearance of a role a wave is comes from the wave makeup itself, for every role, to
    /// wave 24: the waves before it whose opening crowd has the role. Changing the makeup moves
    /// the appearances with it.
    @Test func appearancesComeFromTheWaveMakeup() throws {
        func check(_ waves: RedoubtWaves) {
            for role in RedoubtRole.allCases where role != .skitter {
                for wave in 0...24 {
                    let has = { (w: Int) in waves.composition(forWave: w).contains { $0.role == role } }
                    let expected = has(wave) ? (1..<max(wave, 1)).count { has($0) } : nil
                    #expect(waves.appearance(of: role, inWave: wave) == expected, "\(role) wave \(wave)")
                }
            }
            for wave in 0...24 {
                #expect(waves.sendsGleaners(wave) == waves.composition(forWave: wave).contains { $0.role == .gleaner })
                #expect(waves.gleanerWave(wave) == waves.appearance(of: .gleaner, inWave: wave))
            }
        }
        let waves = RedoubtWaves()
        check(waves)
        check(.beforeGleanersThroughWave)
        let appearances = { (role: RedoubtRole) in (1...14).filter { waves.appearance(of: role, inWave: $0) != nil } }
        #expect(appearances(.gleaner) == [2, 4, 7, 9, 10, 11, 12, 13, 14])
        #expect(appearances(.spitter) == [3, 4, 7, 9, 10, 11, 12, 13, 14])
        #expect(appearances(.burrow) == [5, 7, 9, 10, 11, 12, 13, 14])
        #expect(appearances(.thresher) == [6, 7, 9, 10, 11, 12, 13, 14])
        // A Burrow-less debut wave: the Burrows' first appearance becomes wave 7.
        var noBurrowDebut = RedoubtWaves()
        noBurrowDebut.burrowsAtDebut = 0
        check(noBurrowDebut)
        #expect(noBurrowDebut.appearance(of: .burrow, inWave: 5) == nil)
        #expect(noBurrowDebut.appearance(of: .burrow, inWave: 7) == 0)
        #expect(noBurrowDebut.burrowSpawnScale(forWave: 7, tuning: RedoubtTuning())
            == max(1 - RedoubtTuning().burrowSpawnGrowth * 2, RedoubtTuning().burrowMinScale) * 2)
    }

    /// The Spitters' ease by appearance (waves 3, 4, 7, 9 and on): the fire interval keeps its
    /// shortening by wave, times what is left of the debut slowdown (all of it, three quarters,
    /// a fifth, then none); their shots fly at 0.8 of the speed and lead the orb by half in their
    /// debut, easing back the same way. Counted in wave numbers before.
    @Test func theSpittersEaseIsCountedInTheirOwnAppearances() throws {
        let waves = RedoubtWaves()
        let tuning = RedoubtTuning()
        let growth = { (wave: Int) in max(1 - tuning.spitterFireGrowth * Double(wave - 3), tuning.spitterMinScale) }
        let share: [Int: Double] = [3: 1, 4: 0.75, 7: 0.2, 9: 0, 10: 0, 14: 0, 20: 0]
        for (wave, left) in share {
            #expect(abs(waves.spitterFireScale(forWave: wave, tuning: tuning) - growth(wave) * (1 + left)) < 1e-9, "wave \(wave)")
            #expect(abs(waves.spitterShotSpeedScale(forWave: wave) - (1 - 0.2 * left)) < 1e-9, "wave \(wave)")
            #expect(abs(waves.spitterLeadScale(forWave: wave) - (1 - 0.5 * left)) < 1e-9, "wave \(wave)")
        }
        #expect(waves.spitterShotSpeedScale(forWave: 9) == 1 && waves.spitterLeadScale(forWave: 9) == 1)
        // Before: counted in waves, so wave 7 had none of it, and the shots were never eased.
        let before = RedoubtWaves.beforeGleanersThroughWave
        #expect(abs(before.spitterFireScale(forWave: 7, tuning: tuning) - 0.76) < 1e-9)
        #expect(abs(before.spitterFireScale(forWave: 4, tuning: tuning) - 0.94 * 1.75) < 1e-9)
        #expect((0...20).allSatisfy { before.spitterShotSpeedScale(forWave: $0) == 1 && before.spitterLeadScale(forWave: $0) == 1 })
    }

    /// A Spitter's shot in its debut wave flies at the eased speed, aimed with the eased lead.
    @Test func aDebutSpittersShotIsSlowerAndLessLed() throws {
        for (wave, waves) in [(3, RedoubtWaves()), (9, RedoubtWaves()), (3, RedoubtWaves.beforeGleanersThroughWave)] {
            var r = quietRun()
            r.director = waves
            r.wave = wave
            r.orb.invulnerableTimer = 1e9
            r.orb.vel = Vec2(0, 200)
            let spitter = r.addEnemy(.spitter, at: Vec2(450, 30))
            r.enemies[r.index(of: spitter)].state = .windingUp(remaining: 0.001)
            let events = r.step(RedoubtInput(move: Vec2(0, 0)))
            #expect(events.contains { if case .enemyFired = $0 { true } else { false } }, "wave \(wave)")
            let shot = try #require(r.shots.first { $0.owner == .enemy })
            let speed = shot.vel.length
            #expect(abs(speed - r.tuning.spitterShotSpeed * waves.spitterShotSpeedScale(forWave: wave)) < 1e-6, "wave \(wave)")
        }
    }

    /// The Burrows' ease by appearance (waves 5, 7, 9 and on): all of the debut slowdown, half, a
    /// fifth, then none; counted in wave numbers before (two thirds left in wave 6,
    /// which has no Burrows, a third in 7, none from 8).
    @Test func theBurrowsEaseIsCountedInTheirOwnAppearances() throws {
        let waves = RedoubtWaves()
        let tuning = RedoubtTuning()
        let growth = { (wave: Int) in max(1 - tuning.burrowSpawnGrowth * Double(wave - 5), tuning.burrowMinScale) }
        let share: [Int: Double] = [5: 1, 7: 0.5, 9: 0.2, 10: 0, 14: 0]
        for (wave, left) in share {
            #expect(abs(waves.burrowSpawnScale(forWave: wave, tuning: tuning) - growth(wave) * (1 + left)) < 1e-9, "wave \(wave)")
        }
        let before = RedoubtWaves.beforeGleanersThroughWave
        #expect(abs(before.burrowSpawnScale(forWave: 7, tuning: tuning) - growth(7) * (1 + 1.0 / 3)) < 1e-9)
        #expect(before.burrowSpawnScale(forWave: 9, tuning: tuning) == growth(9))
    }
}
