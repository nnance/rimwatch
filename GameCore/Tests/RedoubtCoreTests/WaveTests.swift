import Testing
import GameCore
@testable import RedoubtCore

/// Waves, arrivals and the airlock.
@Suite struct WaveTests {
    /// A real run stepped to the start of wave 1.
    private func waveOne(seed: UInt64 = 3, waves: RedoubtWaves = RedoubtWaves()) -> (RedoubtRun, [RedoubtEvent]) {
        var r = RedoubtRun(seed: seed, waves: waves)
        let events = run(&r, steps: seconds(3)) { $0.isWaveStarted }
        return (r, events)
    }

    /// Ends the wave on now as if everything had been shot.
    private func emptyTheFloor(_ r: inout RedoubtRun, keep: (RedoubtEnemy) -> Bool = { _ in false }) {
        r.pendingIndex = r.pending.count
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll { !keep($0) }
    }

    @Test func theFirstWaveStartsSoonWithColonistsAndAnOpenAirlock() throws {
        let (r, events) = waveOne()
        #expect(events.contains(.waveStarted(wave: 1, colonists: 6)))
        #expect(events.contains { if case .airlockOpened = $0 { true } else { false } })
        #expect(Double(r.tick) * RedoubtRun.timeStep <= 1.6)
        #expect(r.wave == 1)
        #expect(r.phase == .fighting)
        #expect(r.airlock.isOpen)
        #expect(r.colonists.count == 6)
        #expect(r.colonistsLeft == 6)
        for colonist in r.colonists {
            #expect(distance(colonist.pos, r.orb.pos) >= r.tuning.colonistClearance)
            #expect(distance(colonist.pos, r.airlock.pos) >= r.tuning.colonistClearance)
        }
    }

    @Test func theFloorIsFullFromTheFirstSecond() throws {
        // The opening crowd is telegraphed in the break's last second...
        var r = RedoubtRun(seed: 3)
        let crowd = r.director.floorCrowd(forWave: 1)
        let before = run(&r, steps: seconds(3)) { $0.isWaveStarted }
        #expect(count(before, "arrivalTelegraphed") == crowd)
        #expect(count(before, "enemyArrived") <= 1)
        // ...and lands as the wave begins, all of it within the first second.
        let events = run(&r, steps: seconds(0.9))
        #expect(count(events, "enemyArrived") + count(before, "enemyArrived") == crowd)
        #expect(r.enemies.count == crowd)
        #expect(r.enemies.allSatisfy { $0.role == .skitter })
    }

    @Test func theFloorIsToppedUpFromTheQuotaWhileItLasts() throws {
        var (r, _) = waveOne()
        run(&r, steps: seconds(1))
        let target = r.director.floorTarget(forWave: 1)
        let quota = r.quota
        #expect(quota == r.director.quota(forWave: 1))
        // Shoot most of the floor away: a group is telegraphed at once to make up the shortfall.
        r.enemies.removeLast(15)
        let events = run(&r, steps: 1)
        let group = count(events, "arrivalTelegraphed")
        #expect(group == RedoubtWaves.groupSize)
        #expect(r.quota == quota - group)
        // More follow at the group gap until the floor is back at its target.
        run(&r, steps: seconds(1))
        #expect(r.shootableOnFloor == target)
        // With the quota spent, nothing more comes and the wave can be cleared.
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        let end = run(&r, steps: 1)
        #expect(end.contains { $0.isWaveCleared })
    }

    @Test func topUpGroupsArriveTogetherAwayFromTheOrb() throws {
        var (r, _) = waveOne(seed: 8)
        run(&r, steps: seconds(1))
        r.enemies.removeAll()
        r.orb.invulnerableTimer = 1e9
        let events = run(&r, steps: 1)
        let spots = events.compactMap { if case .arrivalTelegraphed(_, .skitter, let at) = $0 { at } else { nil } }
        #expect(spots.count == RedoubtWaves.groupSize)
        for spot in spots {
            #expect(distance(spot, r.orb.pos) >= r.tuning.safeDistance)
        }
        // A cluster, not scattered over the floor.
        let first = try #require(spots.first)
        #expect(spots.allSatisfy { distance($0, first) <= 130 })
    }

    @Test func runningAlongAWallBringsTopUpGroupsInAheadOfTheOrb() throws {
        var (r, _) = waveOne(seed: 8)
        run(&r, steps: seconds(1))
        r.orb.invulnerableTimer = 1e9
        // Hugging the south wall, flying east at top speed.
        r.orb.pos = Vec2(150, 12)
        r.orb.vel = Vec2(r.tuning.orbMaxSpeed, 0)
        r.enemies.removeAll()
        let events = run(&r, steps: 1, input: RedoubtInput(move: Vec2(1, 0)))
        let spots = events.compactMap { if case .arrivalTelegraphed(_, .skitter, let at) = $0 { at } else { nil } }
        #expect(spots.count == RedoubtWaves.groupSize)
        for spot in spots {
            // On its path, 400 to 520 ahead (give or take the group's spread), still clear of it.
            #expect(spot.x >= r.orb.pos.x + 300 && spot.x <= r.orb.pos.x + 600, "\(spot)")
            #expect(spot.y <= 100, "\(spot)")
            #expect(distance(spot, r.orb.pos) >= r.tuning.safeDistance)
        }

        // With a corner close ahead there is no room on its path: the group comes in elsewhere,
        // as usual, clear of the orb.
        r.orb.pos = Vec2(840, 12)
        r.orb.vel = Vec2(r.tuning.orbMaxSpeed, 0)
        r.enemies.removeAll()
        r.arrivals.removeAll()
        r.groupCooldown = 0
        let cornered = run(&r, steps: 1, input: RedoubtInput(move: Vec2(1, 0)))
        let elsewhere = cornered.compactMap { if case .arrivalTelegraphed(_, .skitter, let at) = $0 { at } else { nil } }
        #expect(!elsewhere.isEmpty)
        #expect(elsewhere.allSatisfy { distance($0, r.orb.pos) >= r.tuning.safeDistance })
    }

    /// How far a spot is from a wall.
    private func gap(_ spot: Vec2, to wall: ArenaWall, _ tuning: RedoubtTuning) -> Double {
        switch wall {
        case .north: tuning.arenaHeight - spot.y
        case .south: spot.y
        case .east: tuning.arenaWidth - spot.x
        case .west: spot.x
        }
    }

    @Test func earlyWavesPushInFromOneWallWithAScatterAndLaterOnesFromAnywhere() throws {
        let waves = RedoubtWaves()
        #expect((1...4).allSatisfy { waves.entrySides(forWave: $0) == 1 })
        #expect(waves.entrySides(forWave: 5) == 2)
        #expect(waves.entrySides(forWave: 7) == 3)
        #expect((8...30).allSatisfy { waves.entrySides(forWave: $0) == 4 })
        // The scattered share grows wave by wave, and from wave 8 the whole crowd is anywhere.
        let shares = (1...8).map { waves.scatterShare(forWave: $0) }
        #expect(shares[0] > 0 && shares[0] < 0.5)
        #expect(zip(shares, shares.dropFirst()).allSatisfy { $0 < $1 })
        #expect((8...30).allSatisfy { waves.scatterShare(forWave: $0) == 1 })
        // Which spawns are scattered: the share of the list, spread through it.
        for wave in 1...7 {
            let count = waves.spawns(forWave: wave).count
            let scattered = (0..<count).count { waves.isScattered($0, forWave: wave) }
            #expect(scattered == Int((Double(count) * waves.scatterShare(forWave: wave)).rounded(.down)))
        }

        // Wave 1: the main wall is not the one the orb is nearest; most of the crowd lands in a
        // deep band along it, the scattered share anywhere well clear of the orb.
        for seed: UInt64 in [3, 8, 21, 40] {
            var r = RedoubtRun(seed: seed)
            let events = run(&r, steps: seconds(3)) { $0.isWaveStarted }
            let wall = try #require(r.entrySides.first)
            #expect(r.entrySides.count == 1)
            #expect(wall != r.nearestWall(r.centre))
            let spots = events.compactMap { if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil } }
            #expect(spots.count == waves.floorCrowd(forWave: 1))
            var scattered = 0
            for (index, spot) in spots.enumerated() {
                #expect(distance(spot, r.orb.pos) >= r.tuning.safeDistance)
                if waves.isScattered(index, forWave: 1) {
                    scattered += 1
                    #expect(distance(spot, r.centre) >= r.tuning.scatterClearance, "\(spot) scattered too close")
                } else {
                    #expect(gap(spot, to: wall, r.tuning) <= r.tuning.pushDepth + 1e-9, "\(spot) not along \(wall)")
                }
            }
            #expect(scattered >= 3)
            // Top-up groups come from the main wall.
            run(&r, steps: seconds(1))
            r.enemies.removeAll()
            r.orb.invulnerableTimer = 1e9
            let group = run(&r, steps: 1).compactMap { if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil } }
            #expect(!group.isEmpty)
            for spot in group {
                #expect(gap(spot, to: wall, r.tuning) <= 160, "\(spot) not along \(wall)")
            }
        }

        // From wave 8 the crowd lands anywhere, as it always did.
        var late = RedoubtRun(seed: 3)
        late.wave = 7
        late.prepareWave(startingIn: 1)
        #expect(late.entrySides.isEmpty)
    }

    @Test func theMainWallChangesEveryWaveAndAvoidsTheOrb() throws {
        var r = RedoubtRun(seed: 5)
        var picker = SeededRNG(seed: 99)
        var chosen: [ArenaWall: Int] = [:]
        var previous: ArenaWall?
        for _ in 0..<400 {
            r.orb.pos = Vec2(picker.range(20...880), picker.range(20...580))
            r.chooseEntrySides(count: 1)
            let main = try #require(r.entrySides.first)
            #expect(main != r.nearestWall(r.orb.pos), "\(main) is nearest \(r.orb.pos)")
            #expect(main != previous)
            chosen[main, default: 0] += 1
            previous = main
        }
        // Every wall takes its turn.
        #expect(ArenaWall.allCases.allSatisfy { (chosen[$0] ?? 0) > 40 }, "\(chosen)")

        // Not just the farthest: from the same spot, more than one wall is chosen.
        var walls = Set<ArenaWall>()
        for _ in 0..<40 {
            r.orb.pos = Vec2(450, 300)
            r.lastMainWall = nil
            r.chooseEntrySides(count: 1)
            walls.insert(r.entrySides[0])
        }
        #expect(walls.count == 3)
        #expect(!walls.contains(r.nearestWall(Vec2(450, 300))))

        // Two or three walls: the main one first, none of them the orb's nearest.
        for count in 2...3 {
            r.orb.pos = Vec2(800, 300)
            r.chooseEntrySides(count: count)
            #expect(r.entrySides.count == count)
            #expect(Set(r.entrySides).count == count)
            #expect(!r.entrySides.contains(.east))
        }

        // The same seed gives the same walls and the same crowd.
        func opening(_ seed: UInt64) -> ([ArenaWall], [RedoubtEvent]) {
            var fresh = RedoubtRun(seed: seed)
            let events = run(&fresh, steps: seconds(3)) { $0.isWaveStarted }
            return (fresh.entrySides, events)
        }
        #expect(opening(12) == opening(12))
    }

    /// `RedoubtWaves.pushAndScatter` off gives back the first 13d entry exactly: the whole crowd
    /// in a 180-unit band along one wall, nothing scattered.
    @Test func theMainPushAndScatterCanBeTurnedOff() throws {
        var waves = RedoubtWaves()
        waves.pushAndScatter = false
        #expect((1...7).allSatisfy { waves.scatterShare(forWave: $0) == 0 })
        for seed: UInt64 in [3, 8, 21] {
            var r = RedoubtRun(seed: seed, waves: waves)
            let events = run(&r, steps: seconds(3)) { $0.isWaveStarted }
            let wall = try #require(r.entrySides.first)
            let spots = events.compactMap { if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil } }
            #expect(spots.allSatisfy { gap($0, to: wall, r.tuning) <= r.tuning.entryBandDepth + 1e-9 })
        }
    }

    @Test func theScatteredShareIsPinnedWaveByWave() throws {
        let waves = RedoubtWaves()
        let shares = (1...9).map { waves.scatterShare(forWave: $0) }
        #expect(shares == [0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6, 1, 1])
    }

    @Test func fartherWallsAreLikelierToBeTheMainWall() throws {
        /// How often each wall is the main wall over many draws with the orb at (700, 450):
        /// north is nearest (150), then east (200), south (450) and west (700).
        func shares(weighting: Double) -> [ArenaWall: Double] {
            var tuning = RedoubtTuning()
            tuning.mainWallWeighting = weighting
            var r = RedoubtRun(seed: 5, tuning: tuning)
            r.orb.pos = Vec2(700, 450)
            var chosen: [ArenaWall: Int] = [:]
            let trials = 1000
            for _ in 0..<trials {
                r.lastMainWall = nil
                r.chooseEntrySides(count: 1)
                chosen[r.entrySides[0], default: 0] += 1
            }
            return chosen.mapValues { Double($0) / Double(trials) }
        }
        // Weighted by distance squared: west about 0.67, east about 0.05.
        let weighted = shares(weighting: RedoubtTuning().mainWallWeighting)
        #expect(weighted[.north] == nil)
        #expect((weighted[.west] ?? 0) > 0.55, "\(weighted)")
        #expect((weighted[.east] ?? 0) < 0.12, "\(weighted)")
        // Unweighted, each open wall about a third.
        let even = shares(weighting: 0)
        #expect((even[.west] ?? 0) < 0.45, "\(even)")
        #expect((even[.east] ?? 0) > 0.22, "\(even)")
    }

    @Test func theMainPushThinsAwayFromTheWallAndLeansAwayFromTheOrb() throws {
        /// The mean inset (0 at the margin, 1 at `pushDepth`) and the mean place along the wall
        /// (0 at the south end, 1 at the north) of many main-push spots along the west wall.
        func spread(falloff: Double, alongDraws: Int, orbAt: Vec2) -> (inset: Double, along: Double) {
            var tuning = RedoubtTuning()
            tuning.pushFalloff = falloff
            tuning.pushAlongDraws = alongDraws
            var r = RedoubtRun(seed: 7, tuning: tuning)
            r.wavesEnabled = false
            r.phase = .fighting
            r.orb.pos = orbAt
            r.entrySides = [.west]
            let margin = tuning.spawnWallMargin
            let trials = 1000
            for _ in 0..<trials { r.telegraph(.skitter) }
            #expect(r.arrivals.count == trials)
            let insets = r.arrivals.map { ($0.pos.x - margin) / (tuning.pushDepth - margin) }
            let alongs = r.arrivals.map { ($0.pos.y - margin) / (tuning.arenaHeight - 2 * margin) }
            return (insets.reduce(0, +) / Double(trials), alongs.reduce(0, +) / Double(trials))
        }
        let defaults = RedoubtTuning()
        let low = Vec2(650, 150), high = Vec2(650, 450)
        // Thinning out: the inset is u^1.5 (mean 0.4) rather than uniform (mean 0.5).
        let thinned = spread(falloff: defaults.pushFalloff, alongDraws: defaults.pushAlongDraws, orbAt: low)
        let flat = spread(falloff: 1, alongDraws: defaults.pushAlongDraws, orbAt: low)
        #expect(thinned.inset < 0.45, "\(thinned)")
        #expect(flat.inset > 0.45, "\(flat)")
        // Leaning away from the orb: the farthest of four draws (mean 0.8 toward the far end)
        // rather than one (mean 0.5), whichever end the orb is level with.
        #expect(thinned.along > 0.72, "\(thinned)")
        let leanLow = spread(falloff: defaults.pushFalloff, alongDraws: defaults.pushAlongDraws, orbAt: high)
        #expect(leanLow.along < 0.28, "\(leanLow)")
        let unleaned = spread(falloff: defaults.pushFalloff, alongDraws: 1, orbAt: low)
        #expect(abs(unleaned.along - 0.5) < 0.06, "\(unleaned)")
    }

    @Test func topUpGroupsLandAtTheFarthestOfSeveralSpots() throws {
        /// The mean distance from the orb of top-up groups' centres along the south wall, with the
        /// orb still at (250, 300), over many draws from the same moment in wave 1.
        func meanGap(spotDraws: Int) -> Double {
            var tuning = RedoubtTuning()
            tuning.groupSpotDraws = spotDraws
            var base = RedoubtRun(seed: 8, tuning: tuning)
            run(&base, steps: seconds(3)) { $0.isWaveStarted }
            run(&base, steps: seconds(1))
            base.orb.invulnerableTimer = 1e9
            base.orb.pos = Vec2(250, 300)
            base.orb.vel = .zero
            base.entrySides = [.south]
            base.enemies.removeAll()
            base.arrivals.removeAll()
            base.groupCooldown = 0
            var total = 0.0
            let trials = 200
            for trial in 0..<trials {
                var r = base
                r.rng = SeededRNG(seed: UInt64(1000 + trial))
                let spots = r.step(still).compactMap {
                    if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil }
                }
                #expect(spots.count == RedoubtWaves.groupSize)
                let centre = spots.reduce(Vec2(0, 0)) { $0 + $1 } * (1 / Double(spots.count))
                total += distance(centre, r.orb.pos)
            }
            return total / Double(trials)
        }
        let farthest = meanGap(spotDraws: RedoubtTuning().groupSpotDraws)
        let any = meanGap(spotDraws: 1)
        #expect(farthest > any + 80, "farthest of six \(farthest), one spot \(any)")
    }

    /// Waves 2 to 4 with the orb off-centre and flying about through the intermission: the main
    /// wall is never the one it was nearest when the wave was laid out, the push lands along that
    /// wall, and the scattered share keeps its clearance.
    @Test func laterEarlyWavesKeepTheEntryRulesWithTheOrbOffCentreAndMoving() throws {
        let waves = RedoubtWaves()
        let moves = [Vec2(1, 0.4), Vec2(-0.7, -1), Vec2(0.3, -1), Vec2(-1, 0.8)]
        for (n, seed) in ([4, 9, 17, 33] as [UInt64]).enumerated() {
            var (r, _) = waveOne(seed: seed)
            r.orb.invulnerableTimer = 1e9
            let input = RedoubtInput(move: moves[n])
            for wave in 2...4 {
                emptyTheFloor(&r)
                var telegraphed: [Vec2] = []
                var orbAt = r.orb.pos
                var nearest = r.nearestWall(r.orb.pos)
                var steps = 0
                while r.wave < wave, steps < seconds(5) {
                    let before = r.orb.pos
                    let events = r.step(input)
                    let spots = events.compactMap {
                        if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil }
                    }
                    if !spots.isEmpty, telegraphed.isEmpty {
                        orbAt = before
                        nearest = r.nearestWall(before)
                        telegraphed = spots
                    }
                    steps += 1
                }
                try #require(r.wave == wave)
                #expect(distance(orbAt, r.centre) > 60, "seed \(seed) wave \(wave): orb still central")
                let wall = try #require(r.entrySides.first)
                #expect(r.entrySides.count == 1)
                #expect(wall != nearest, "seed \(seed) wave \(wave): \(wall) is nearest \(orbAt)")
                // The opening crowd but the Gleaners landing late (`RedoubtWaves.gleanerDebutDelay`),
                // by index into the wave's spawns.
                let opening = waves.spawns(forWave: wave).indices.filter {
                    waves.landing(of: waves.spawns(forWave: wave)[$0], inWave: wave) <= r.tuning.telegraphTime
                }
                #expect(telegraphed.count == opening.count)
                #expect(r.pending.count == waves.spawns(forWave: wave).count - opening.count)
                let slack = r.tuning.orbMaxSpeed / 120 + 1e-6
                for (spot, index) in zip(telegraphed, opening) {
                    #expect(distance(spot, orbAt) >= r.tuning.safeDistance - slack)
                    if waves.isScattered(index, forWave: wave) {
                        #expect(distance(spot, orbAt) >= r.tuning.scatterClearance - slack, "\(spot) scattered too close")
                    } else {
                        #expect(gap(spot, to: wall, r.tuning) <= r.tuning.pushDepth + 1e-9, "\(spot) not along \(wall)")
                    }
                }
            }
        }
    }

    @Test func spittersFireSlowlyInTheirFirstWaves() throws {
        let waves = RedoubtWaves()
        let tuning = RedoubtTuning()
        // Twice the interval in their debut wave (3; 3.8 times before the Burrows' ease, twice
        // before the figures grew), easing back over their own appearances (waves 3, 4, 7, 9).
        #expect(abs(waves.spitterFireScale(forWave: 3, tuning: tuning) - 2.0) < 1e-9)
        #expect(abs(RedoubtWaves.beforeBurrowEase.spitterFireScale(forWave: 3, tuning: tuning) - 3.8) < 1e-9)
        #expect(abs(RedoubtWaves.beforeFiguresGrew.spitterFireScale(forWave: 3, tuning: tuning) - 2.0) < 1e-9)
        let appearances = (3...20).filter { waves.appearance(of: .spitter, inWave: $0) != nil }
        let scales = appearances.map { waves.spitterFireScale(forWave: $0, tuning: tuning) }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 >= $1 })
        var flat = RedoubtWaves()
        flat.spitterDebutSlowdown = 1
        #expect(abs(waves.spitterFireScale(forWave: 9, tuning: tuning) - flat.spitterFireScale(forWave: 9, tuning: tuning)) < 1e-9)
        #expect(abs(flat.spitterFireScale(forWave: 3, tuning: tuning) - 1) < 1e-9)
        // Fewer in their second appearance, then counted in appearances: 3, 2, 6, 7, then 8.
        let counts = [3, 4, 7, 9, 10, 11, 20].map { waves.crowdCount(of: .spitter, inWave: $0) }
        #expect(counts == [3, 2, 6, 7, 8, 8, 8])
        let before = RedoubtWaves.beforeGleanersThroughWave
        #expect([3, 4, 7, 9, 10].map { before.crowdCount(of: .spitter, inWave: $0) } == [3, 3, 6, 8, 8])
        // The crowd keeps its size: Skitters fill the difference.
        for wave in 1...20 {
            #expect(waves.composition(forWave: wave).reduce(0) { $0 + $1.count } == before.composition(forWave: wave).reduce(0) { $0 + $1.count })
        }
    }

    /// The Spitters' fire from one of their appearances to the next (waves 3, 4, 7, 9, 10 and
    /// on; counted in wave numbers before Refinement 6, this test passed only because waves 5
    /// and 6, which have no Spitters, sat between 4 and 7). The interval shortens by at most 1.45
    /// times an appearance, except from wave 4 to 7, two waves without Spitters apart, where it
    /// is 1.8 times (it was 2.16): easing wave 7 more lets the corner camper, which dies only to
    /// Spitter shots and mostly in wave 7, live longer.
    @Test func spitterFireRisesSmoothlyByAppearance() throws {
        let waves = RedoubtWaves()
        let tuning = RedoubtTuning()
        let expected: [Int: Double] = [3: 2.0, 4: 0.94 * 1.75, 7: 0.76 * 1.2, 9: 0.64, 10: 0.58]
        for (wave, scale) in expected {
            #expect(abs(waves.spitterFireScale(forWave: wave, tuning: tuning) - scale) < 1e-9, "wave \(wave)")
        }
        let appearances = (3...24).filter { waves.appearance(of: .spitter, inWave: $0) != nil }
        #expect(Array(appearances.prefix(5)) == [3, 4, 7, 9, 10])
        for (a, b) in zip(appearances, appearances.dropFirst()) {
            let ratio = waves.spitterFireScale(forWave: a, tuning: tuning) / waves.spitterFireScale(forWave: b, tuning: tuning)
            #expect(ratio >= 1 && ratio <= (a == 4 ? 1.81 : 1.45), "wave \(a) to \(b): \(ratio)")
        }
        let before = RedoubtWaves.beforeGleanersThroughWave
        #expect(before.spitterFireScale(forWave: 4, tuning: tuning) / before.spitterFireScale(forWave: 7, tuning: tuning) > 2.1)
    }

    /// The Burrows' ease: their debut wave (5) sends one Burrow, not two, and it pours twice as
    /// slowly, easing back to the normal rate over their next two appearances (half the slowdown
    /// left in wave 7, a fifth in 9; by wave 8 before Refinement 6). `beforeBurrowEase` turns it off.
    @Test func burrowsDebutAloneAndPourSlowlyAtFirst() throws {
        let waves = RedoubtWaves()
        let tuning = RedoubtTuning()
        let burrows = { (w: RedoubtWaves, wave: Int) in w.composition(forWave: wave).first { $0.role == .burrow }?.count ?? 0 }
        #expect(burrows(waves, 5) == 1)
        #expect(waves.composition(forWave: 5).map(\.role) == [.skitter, .burrow])
        #expect(burrows(waves, 7) == 1)
        #expect(burrows(waves, 9) == 2)
        #expect(burrows(RedoubtWaves.beforeBurrowEase, 5) == 2)
        // The crowd keeps its size: the missing Burrow is a Skitter.
        let crowd = { (w: RedoubtWaves) in w.composition(forWave: 5).reduce(0) { $0 + $1.count } }
        #expect(crowd(waves) == crowd(RedoubtWaves.beforeBurrowEase))
        // Counted in their own appearances (waves 5, 7, 9, 10): all the slowdown, half, a fifth,
        // none. Before Refinement 6, in wave numbers (back to full by wave 8).
        let expected: [Int: Double] = [5: 2.0, 7: 0.9 * 1.5, 9: 0.8 * 1.2, 10: 0.75]
        for (wave, scale) in expected {
            #expect(abs(waves.burrowSpawnScale(forWave: wave, tuning: tuning) - scale) < 1e-9, "wave \(wave)")
        }
        let appearances = (5...20).filter { waves.appearance(of: .burrow, inWave: $0) != nil }
        for (a, b) in zip(appearances, appearances.dropFirst()) {
            #expect(waves.burrowSpawnScale(forWave: b, tuning: tuning) <= waves.burrowSpawnScale(forWave: a, tuning: tuning))
        }
        let byWave = RedoubtWaves.beforeGleanersThroughWave
        let old: [Int: Double] = [5: 2.0, 6: 0.95 * (1 + 2.0 / 3), 7: 0.9 * (1 + 1.0 / 3), 8: 0.85, 9: 0.8]
        for (wave, scale) in old {
            #expect(abs(byWave.burrowSpawnScale(forWave: wave, tuning: tuning) - scale) < 1e-9, "wave \(wave)")
        }
        let before = RedoubtWaves.beforeBurrowEase
        for wave in 5...20 {
            let plain = max(1 - tuning.burrowSpawnGrowth * Double(wave - 5), tuning.burrowMinScale)
            #expect(before.burrowSpawnScale(forWave: wave, tuning: tuning) == plain)
        }
        #expect(RedoubtWaves.beforeGleanerEase.burrowsAtDebut == 2)
        #expect(RedoubtWaves.beforeFiguresGrew.burrowDebutSlowdown == 1)
    }

    /// The Gleaners' ease (after the owner's third play) and its ramp, as they were before
    /// Refinement 6 (`beforeGleanersThroughWave`): in their first wave the opening crowd's
    /// Gleaners land 7 s after the rest of it and drag six times more slowly, easing over their
    /// next waves (counted in waves that send Gleaners: 2, 4, 7, 9, 10) to nothing in their
    /// sixth (11); each step shortens the delay by at most 2.1 s and at most doubles the drag
    /// speed. `beforeGleanerRamp` counts it in waves (gone by wave 7); `beforeGleanerEase`
    /// turns it off. Since Refinement 6 the delay is `gleanerFirstArrival` and the drag speed is
    /// whole (`ThroughWaveTests`).
    @Test func gleanersArriveLateAndDragSlowlyInTheirFirstWaves() throws {
        let waves = RedoubtWaves.beforeGleanersThroughWave
        // The waves that send Gleaners, and which of theirs each is.
        #expect((0...12).filter { waves.sendsGleaners($0) } == [2, 4, 7, 9, 10, 11, 12])
        for wave in 0...12 {
            #expect(waves.sendsGleaners(wave) == waves.composition(forWave: wave).contains { $0.role == .gleaner }, "wave \(wave)")
        }
        #expect([2, 4, 7, 9, 10, 11, 3, 0].map { waves.gleanerWave($0) } == [0, 1, 2, 3, 4, 5, nil, nil])
        let expected: [Int: (delay: Double, slowdown: Double)] = [
            2: (7, 6), 4: (4.9, 4.5), 7: (3.85, 3.75), 9: (2.8, 3), 10: (1.4, 2), 11: (0, 1),
        ]
        for (wave, value) in expected {
            #expect(abs(waves.gleanerDelay(forWave: wave) - value.delay) < 1e-9, "wave \(wave)")
            #expect(abs(1 / waves.gleanerDragScale(forWave: wave) - value.slowdown) < 1e-9, "wave \(wave)")
        }
        // No ease in a wave without Gleaners (nor a quiet run's wave 0), nor from wave 11.
        for wave in [0, 1, 3, 5, 6, 8] + Array(11...20) {
            #expect(waves.gleanerDelay(forWave: wave) == 0)
            #expect(waves.gleanerDragScale(forWave: wave) == 1)
        }
        // Each Gleaner wave a little harder than the last, never easier, and no step a cliff: the
        // drag speeds up by at most twice and the delay shrinks by at most 2.1 s.
        let gleanerWaves = (2...20).filter { waves.sendsGleaners($0) }
        for (a, b) in zip(gleanerWaves, gleanerWaves.dropFirst()) {
            let (delayA, delayB) = (waves.gleanerDelay(forWave: a), waves.gleanerDelay(forWave: b))
            #expect(delayB < delayA || delayA == 0)
            #expect(delayA - delayB <= 2.1 + 1e-9, "waves \(a) to \(b)")
            let (dragA, dragB) = (waves.gleanerDragScale(forWave: a), waves.gleanerDragScale(forWave: b))
            #expect(dragB > dragA || dragA == 1)
            #expect(dragB / dragA <= 2 + 1e-9, "waves \(a) to \(b)")
        }
        // Only Gleaners wait.
        for spawn in waves.spawns(forWave: 4) {
            let late = spawn.role == .gleaner ? waves.gleanerDelay(forWave: 4) : 0
            #expect(waves.landing(of: spawn, inWave: 4) == spawn.delay + late)
        }
        // Before the ramp: counted in waves, so wave 7 had none of it, and wave 0 all of it.
        let unramped = RedoubtWaves.beforeGleanerRamp
        #expect(abs(unramped.gleanerDelay(forWave: 2) - 7) < 1e-9)
        #expect(abs(unramped.gleanerDelay(forWave: 4) - 4.2) < 1e-9)
        #expect(abs(unramped.gleanerDragScale(forWave: 4) - 0.25) < 1e-9)
        #expect(abs(unramped.gleanerDragScale(forWave: 0) - 1.0 / 6) < 1e-9)
        #expect(unramped.gleanerDelay(forWave: 7) == 0)
        #expect(unramped.gleanerDragScale(forWave: 7) == 1)
        let before = RedoubtWaves.beforeGleanerEase
        for wave in 0...20 {
            #expect(before.gleanerDelay(forWave: wave) == 0)
            #expect(before.gleanerDragScale(forWave: wave) == 1)
        }
        #expect(RedoubtWaves.beforeFiguresGrew.gleanerDelay(forWave: 2) == 0)
    }

    /// In the game before Refinement 6 (`beforeGleanersThroughWave`; the schedule since then is
    /// in `ThroughWaveTests`): Gleaners landing late always land with the main push, in the band
    /// along the wave's entry wall, even when the opening-crowd spawn they came from is scattered
    /// (`RedoubtWaves.lateArrivalsScatter` off: scattering them put Gleaners beside colonists).
    /// Every one keeps the clear distance from the orb as it is when its marker appears, the orb
    /// flying about meanwhile.
    @Test func lateGleanersLandWithTheMainPushAndKeepClearOfTheOrb() throws {
        let moves = [Vec2(1, 0.4), Vec2(-0.7, -1), Vec2(0.3, -1), Vec2(-1, 0.8)]
        var fromScattered = 0
        for (n, seed) in ([4, 9, 17, 33] as [UInt64]).enumerated() {
            var (r, _) = waveOne(seed: seed, waves: .beforeGleanersThroughWave)
            r.orb.invulnerableTimer = 1e9
            for wave in [2, 3, 4] {
                emptyTheFloor(&r)
                run(&r, steps: seconds(5)) { $0.isWaveStarted }
                try #require(r.wave == wave)
                guard wave != 3 else { continue }
                let spawns = r.director.spawns(forWave: wave)
                let late = spawns.indices.filter {
                    r.director.landing(of: spawns[$0], inWave: wave) > r.tuning.telegraphTime
                }
                try #require(!late.isEmpty)
                #expect(late.allSatisfy { spawns[$0].role == .gleaner })
                fromScattered += late.count { r.director.isScattered($0, forWave: wave) }
                let wall = try #require(r.entrySides.first)
                #expect(r.entrySides.count == 1)
                var ids: Set<Int> = []
                let slack = r.tuning.orbMaxSpeed / 120 + 1e-6
                for step in 0..<seconds(8) {
                    // Fly about, and keep the floor thin so nothing else is telegraphed.
                    let input = RedoubtInput(move: moves[(n + step / 90) % moves.count])
                    r.quota = 0
                    r.enemies.removeAll { $0.role != .gleaner }
                    let orbAt = r.orb.pos
                    for event in r.step(input) {
                        // Its first marker (one the orb flies onto moves anywhere on the floor).
                        guard case .arrivalTelegraphed(let id, .gleaner, let at) = event, ids.insert(id).inserted else { continue }
                        #expect(distance(at, orbAt) >= r.tuning.safeDistance - slack, "seed \(seed) wave \(wave)")
                        #expect(gap(at, to: wall, r.tuning) <= r.tuning.pushDepth + 1e-9,
                                "seed \(seed) wave \(wave): \(at) not along \(wall)")
                    }
                }
                #expect(ids.count == late.count, "seed \(seed) wave \(wave)")
            }
        }
        // Some of them came from scattered spawns, so the rule was put to the test.
        #expect(fromScattered > 0)
        #expect(!RedoubtWaves().lateArrivalsScatter)
        #expect(!RedoubtWaves.beforeGleanersThroughWave.lateArrivalsScatter)
    }

    /// Before Refinement 6 (`beforeGleanersThroughWave`): the orb lost while wave 2's Gleaners
    /// are still to come: they are telegraphed and land as
    /// usual (clear of where it will respawn), and the wave still ends once they are shot.
    @Test func losingTheOrbWhileGleanersAreToComeStallsNothing() throws {
        var (r, _) = waveOne(seed: 6, waves: .beforeGleanersThroughWave)
        emptyTheFloor(&r)
        run(&r, steps: seconds(3)) { $0.isWaveStarted }
        try #require(r.wave == 2)
        let gleaners = r.pending.count
        try #require(gleaners > 0 && r.pendingIndex == 0)
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        // Lost just before their markers show (6 s in), so they are telegraphed while it is down.
        run(&r, steps: seconds(5.5) - seconds(r.waveClock))
        try #require(r.pendingIndex == 0)
        r.orb.invulnerableTimer = 0
        r.destroyOrb(cause: .shot(id: 0))
        try #require(!r.orb.isAlive && !r.isGameOver)
        var arrived = 0
        for _ in 0..<seconds(4) {
            if r.orb.isAlive { r.orb.invulnerableTimer = 1e9 }
            for event in r.step(RedoubtInput()) {
                if case .arrivalTelegraphed(_, .gleaner, let at) = event {
                    #expect(r.isClearOfOrb(at, by: r.tuning.safeDistance))
                }
                if case .enemyArrived(_, .gleaner, _) = event { arrived += 1 }
                #expect(!event.isWaveCleared)
            }
        }
        #expect(arrived == gleaners)
        #expect(r.pendingIndex == r.pending.count)
        #expect(r.orb.isAlive)
        // Shoot them (and anything they made): the wave ends and the next one comes.
        r.enemies.removeAll()
        r.arrivals.removeAll()
        r.quota = 0
        let end = run(&r, steps: seconds(1)) { $0.isWaveCleared }
        #expect(end.contains { $0.isWaveCleared })
        run(&r, steps: seconds(4)) { $0.isWaveStarted }
        #expect(r.wave == 3)
    }

    /// Before Refinement 6 (`beforeGleanersThroughWave`): the game ending while wave 2's Gleaners
    /// are still to come: the run stops where it is,
    /// nothing more is telegraphed, and stepping on is harmless.
    @Test func theGameEndingWhileGleanersAreToComeStopsCleanly() throws {
        var (r, _) = waveOne(seed: 6, waves: .beforeGleanersThroughWave)
        emptyTheFloor(&r)
        run(&r, steps: seconds(3)) { $0.isWaveStarted }
        try #require(r.wave == 2)
        try #require(r.pending.count > 0 && r.pendingIndex == 0)
        run(&r, steps: seconds(1))
        r.orb.lives = 1
        r.orb.invulnerableTimer = 0
        r.destroyOrb(cause: .shot(id: 0))
        #expect(r.isGameOver)
        let tick = r.tick
        for _ in 0..<seconds(10) {
            #expect(r.step(RedoubtInput()).isEmpty)
        }
        #expect(r.tick == tick)
        #expect(r.pendingIndex == 0)
        #expect(!r.arrivals.contains { $0.role == .gleaner })
    }

    /// Before Refinement 6 (`beforeGleanersThroughWave`): wave 2's Gleaners are telegraphed 6 s
    /// into the wave and land at 7 s. While they wait the
    /// floor is topped up around them (they count toward the target), and the wave cannot end.
    @Test func wave2sGleanersLandLateAndHoldTheWave() throws {
        var (r, _) = waveOne(seed: 6, waves: .beforeGleanersThroughWave)
        r.orb.invulnerableTimer = 1e9
        emptyTheFloor(&r)
        run(&r, steps: seconds(3)) { $0.isWaveStarted }
        try #require(r.wave == 2)
        let gleaners = try #require(r.director.composition(forWave: 2).first { $0.role == .gleaner }).count
        #expect(!r.arrivals.contains { $0.role == .gleaner })
        #expect(r.pending.count - r.pendingIndex == gleaners)
        #expect(r.pending.allSatisfy { $0.role == .gleaner })
        // Shoot most of the crowd: the floor is made up to its target, the Gleaners counted.
        run(&r, steps: seconds(1))
        r.enemies.removeLast(15)
        run(&r, steps: seconds(1.5))
        let skitters = r.enemies.count { $0.role == .skitter } + r.arrivals.count { $0.role == .skitter }
        #expect(skitters + gleaners == r.director.floorTarget(forWave: 2))
        #expect(r.shootableOnFloor == r.director.floorTarget(forWave: 2))
        // Everything else gone and the quota spent: the wave waits for its Gleaners.
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        let start = r.tick - seconds(2.5)
        var telegraphed: [Int] = []
        var arrived: [Int] = []
        for _ in 0..<seconds(6) {
            for event in r.step(RedoubtInput()) {
                if case .arrivalTelegraphed(_, .gleaner, _) = event { telegraphed.append(r.tick - start) }
                if case .enemyArrived(_, .gleaner, _) = event { arrived.append(r.tick - start) }
                #expect(!event.isWaveCleared)
            }
        }
        #expect(telegraphed.count == gleaners)
        #expect(arrived.count == gleaners)
        let ripple = seconds(0.8) + 1
        #expect(telegraphed.allSatisfy { (seconds(6)...(seconds(6) + ripple)).contains($0) }, "\(telegraphed)")
        #expect(arrived.allSatisfy { (seconds(7)...(seconds(7) + ripple)).contains($0) }, "\(arrived)")
        #expect(r.phase == .fighting)
        #expect(r.enemies.count { $0.role == .gleaner } == gleaners)
    }

    @Test func theWallRunRuleCanBeTurnedOff() throws {
        /// The spots of the group telegraphed when the floor is emptied with the orb at the south
        /// wall, either still or running east along it.
        func groupSpots(wallRunGap: Double, running: Bool) -> [Vec2] {
            var tuning = RedoubtTuning()
            tuning.wallRunGap = wallRunGap
            var r = RedoubtRun(seed: 8, tuning: tuning)
            run(&r, steps: seconds(3)) { $0.isWaveStarted }
            run(&r, steps: seconds(1))
            r.orb.invulnerableTimer = 1e9
            r.orb.pos = Vec2(150, 12)
            r.orb.vel = running ? Vec2(tuning.orbMaxSpeed, 0) : .zero
            r.enemies.removeAll()
            return run(&r, steps: 1).compactMap { if case .arrivalTelegraphed(_, _, let at) = $0 { at } else { nil } }
        }
        let still = groupSpots(wallRunGap: 0, running: false)
        #expect(still.count == RedoubtWaves.groupSize)
        // Turned off, running the wall changes nothing: the same random spots as standing still.
        #expect(groupSpots(wallRunGap: 0, running: true) == still)
        // On (the default), it is what moves the group onto the orb's path.
        #expect(groupSpots(wallRunGap: RedoubtTuning().wallRunGap, running: false) == still)
        #expect(groupSpots(wallRunGap: RedoubtTuning().wallRunGap, running: true) != still)
    }

    @Test func arrivalsAreTelegraphedForASecondAwayFromTheOrb() throws {
        var r = RedoubtRun(seed: 11)
        var telegraphed: [Int: (tick: Int, at: Vec2)] = [:]
        var checked = 0
        for _ in 0..<seconds(20) {
            let orbAt = r.orb.pos
            // Fly about so the orb is not always at the centre.
            let input = RedoubtInput(move: Vec2(r.tick % 400 < 200 ? 1 : -1, r.tick % 700 < 350 ? 0.6 : -0.6))
            r.orb.invulnerableTimer = 1
            // Thin the floor now and then, as kills would, so top-up groups keep coming.
            if r.tick % 120 == 0 { r.enemies.removeLast(min(6, r.enemies.count)) }
            for event in r.step(input) {
                switch event {
                case .arrivalTelegraphed(let id, _, let at):
                    #expect(distance(at, orbAt) >= r.tuning.safeDistance - r.tuning.orbMaxSpeed / 120 - 1e-6)
                    telegraphed[id] = (r.tick, at)
                case .enemyArrived(let id, _, let at):
                    guard let start = telegraphed[id] else {
                        Issue.record("arrived without a telegraph")
                        continue
                    }
                    // A second; the opening crowd lands in a ripple up to 0.8 s longer.
                    #expect(r.tick - start.tick >= 120)
                    #expect(r.tick - start.tick <= 120 + 97)
                    #expect(at == start.at)
                    #expect(distance(at, r.orb.pos) >= r.tuning.safeDistance * 0.5)
                    checked += 1
                default:
                    break
                }
            }
        }
        #expect(checked >= 25)
    }

    @Test func anArrivalTheOrbSitsOnMovesAndIsTelegraphedAgain() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        r.telegraph(.skitter)
        let arrival = try #require(r.arrivals.first)
        r.orb.pos = arrival.pos
        let events = run(&r, steps: seconds(1.05))
        #expect(!events.contains { if case .enemyArrived = $0 { true } else { false } })
        #expect(events.contains { if case .arrivalTelegraphed(arrival.id, .skitter, _) = $0 { true } else { false } })
        let moved = try #require(r.arrivals.first)
        #expect(distance(moved.pos, r.orb.pos) >= r.tuning.safeDistance)
        let later = run(&r, steps: seconds(1.05))
        #expect(later.contains { if case .enemyArrived(arrival.id, .skitter, _) = $0 { true } else { false } })
    }

    @Test func clearingTheFloorEndsTheWaveAndPaysForSafeColonists() throws {
        var (r, _) = waveOne()
        try #require(r.colonists.count == 6)
        // One in the line, one lost, four still sheltering.
        r.colonists[0].state = .following
        r.line = [r.colonists[0].id]
        r.colonists[1].state = .lost
        emptyTheFloor(&r)
        let events = r.step(still)
        #expect(events.contains(.waveCleared(wave: 1, safe: 5, bonus: 5 * r.tuning.waveBonusPerColonist)))
        #expect(r.score == 1250)
        #expect(r.colonistsSaved == 5)
        #expect(r.colonistsDelivered == 0)
        #expect(!r.airlock.isOpen)
        #expect(events.contains { if case .airlockClosed = $0 { true } else { false } })
        #expect(r.phase == .intermission(remaining: r.tuning.intermission))
    }

    @Test func threshersNeedNotBeKilledAndLeaveWithTheWave() throws {
        var (r, _) = waveOne()
        let thresher = r.addEnemy(.thresher, at: Vec2(100, 100))
        emptyTheFloor(&r) { $0.role == .thresher }
        #expect(r.enemiesHoldingWave == 0)
        let events = r.step(still)
        #expect(events.contains { $0.isWaveCleared })
        #expect(events.contains { if case .enemyWithdrew(thresher, .thresher, _) = $0 { true } else { false } })
        #expect(r.enemies.isEmpty)
    }

    @Test func aWaveIsHeldOpenByWhatIsStillToArrive() throws {
        var (r, _) = waveOne()
        r.enemies.removeAll()
        r.arrivals.removeAll()
        // The quota is still to come.
        #expect(r.quota > 0)
        let events = r.step(still)
        #expect(!events.contains { $0.isWaveCleared })
    }

    @Test func theUnspentQuotaAloneHoldsAWaveOpen() throws {
        var (r, _) = waveOne()
        // Between a kill and the next top-up: the floor is empty, nothing is telegraphed or still
        // to come from the opening crowd, and the group gap has not run out.
        r.pendingIndex = r.pending.count
        r.arrivals.removeAll()
        r.enemies.removeAll()
        r.groupCooldown = 1
        try #require(r.quota > 0)
        #expect(r.enemiesHoldingWave == r.quota)
        let events = r.step(still)
        #expect(!events.contains { $0.isWaveCleared })
        #expect(r.phase == .fighting)
    }

    @Test func theAirlockMovesBetweenWaves() throws {
        var (r, _) = waveOne()
        let first = r.airlock.pos
        emptyTheFloor(&r)
        _ = r.step(still)
        // Shut and still in place during the intermission.
        #expect(r.airlock.pos == first)
        let events = run(&r, steps: seconds(2.1)) { $0.isWaveStarted }
        #expect(events.contains(.waveStarted(wave: 2, colonists: 6)))
        #expect(r.airlock.isOpen)
        #expect(distance(r.airlock.pos, first) >= r.tuning.airlockMinMove)
        // It sits on its wall.
        switch r.airlock.wall {
        case .north: #expect(r.airlock.pos.y == 600)
        case .south: #expect(r.airlock.pos.y == 0)
        case .east: #expect(r.airlock.pos.x == 900)
        case .west: #expect(r.airlock.pos.x == 0)
        }
    }

    @Test func colonistsAndTheCrowdGrowWaveByWave() throws {
        let waves = RedoubtWaves()
        // With the figures at 1.5: a 10% bigger crowd and a bigger quota (126 + 28 a wave), eased in faster from
        // the same 18 in wave 1; the full (20 + 8 a wave) x 1.1 from wave 7, capped at 90.
        #expect(waves.floorCrowd(forWave: 1) == 18)
        #expect(waves.floorCrowd(forWave: 2) == 26)
        #expect(waves.floorCrowd(forWave: 7) == 75)
        #expect(waves.floorCrowd(forWave: 8) == 84)
        #expect(waves.floorCrowd(forWave: 9) == 90)
        #expect(waves.floorCrowd(forWave: 30) == 90)
        #expect(waves.quota(forWave: 1) == 103)
        #expect(waves.quota(forWave: 8) == 322)
        #expect((1...29).allSatisfy { waves.floorCrowd(forWave: $0 + 1) >= waves.floorCrowd(forWave: $0) })
        // Before the figures grew: a gentler opening (13d), the full 20 + 8 a wave from wave 8.
        let before = RedoubtWaves.beforeFiguresGrew
        #expect(before.floorCrowd(forWave: 1) == 18)
        #expect(before.floorCrowd(forWave: 2) == 26)
        #expect(before.floorCrowd(forWave: 8) == 76)
        #expect(before.floorCrowd(forWave: 9) == 84)
        #expect(before.floorCrowd(forWave: 30) == 90)
        #expect(before.quota(forWave: 1) == 81)
        #expect(before.quota(forWave: 8) == 265)
        // Undone, the numbers are the original ones.
        var flat = RedoubtWaves.beforeFiguresGrew
        flat.crowdEaseStart = 1
        flat.crowdEaseGrowth = 0
        #expect(flat.floorCrowd(forWave: 1) == 20 && flat.floorCrowd(forWave: 2) == 28)
        #expect(flat.quota(forWave: 1) == 90)
        #expect(waves.colonists(forWave: 1) == 6)
        #expect((1...40).allSatisfy { (6...10).contains(waves.colonists(forWave: $0)) })
        #expect(waves.colonists(forWave: 40) == 10)
        for wave in 1...30 {
            let opening = waves.composition(forWave: wave).reduce(0) { $0 + $1.count }
            #expect(opening == waves.floorCrowd(forWave: wave))
            #expect(waves.spawns(forWave: wave).count == opening)
            #expect(waves.floorTarget(forWave: wave) == waves.floorCrowd(forWave: wave))
            // Each wave sends in several times its opening crowd, more as the waves go on.
            #expect(waves.quota(forWave: wave) >= 3 * min(opening, 30))
            #expect(waves.quota(forWave: wave + 1) >= waves.quota(forWave: wave))
        }
    }

    @Test func eachRoleDebutsInAWaveOfItsOwn() throws {
        let waves = RedoubtWaves()
        #expect(waves.composition(forWave: 1).map(\.role) == [.skitter])
        var seen: Set<RedoubtRole> = [.skitter]
        for (role, wave) in RedoubtWaves.debut {
            // Only Skitters and the newcomer.
            let roles = waves.composition(forWave: wave).map(\.role)
            #expect(roles == [.skitter, role], "wave \(wave)")
            #expect(!seen.contains(role))
            seen.insert(role)
            // Never earlier.
            for earlier in 1..<wave {
                #expect(!waves.composition(forWave: earlier).map(\.role).contains(role))
            }
        }
        #expect(seen == Set(RedoubtRole.allCases))
        #expect(Set(RedoubtWaves.debut.map(\.wave)).count == RedoubtWaves.debut.count)
        // The wave after the last debut mixes everyone.
        let last = RedoubtWaves.debut.map(\.wave).max()!
        #expect(Set(waves.composition(forWave: last + 1).map(\.role)) == Set(RedoubtRole.allCases))
    }

    @Test func burrowsAndThreshersAreKeptOffColonistsAndTheCentre() throws {
        var r = quietRun()
        r.orb.pos = Vec2(100, 100)
        for i in 0..<8 { r.addColonist(at: Vec2(150 + 90 * Double(i), i % 2 == 0 ? 180 : 420)) }
        for _ in 0..<3 { r.telegraph(.burrow) }
        for arrival in r.arrivals {
            #expect(distance(arrival.pos, r.centre) >= r.tuning.burrowCentreClearance)
            #expect(r.colonists.allSatisfy { distance($0.pos, arrival.pos) >= 60 })
        }
    }
}
