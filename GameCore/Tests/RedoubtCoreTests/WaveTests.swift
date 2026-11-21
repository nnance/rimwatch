import Testing
import GameCore
@testable import RedoubtCore

/// Waves, arrivals and the airlock.
@Suite struct WaveTests {
    /// A real run stepped to the start of wave 1.
    private func waveOne(seed: UInt64 = 3) -> (RedoubtRun, [RedoubtEvent]) {
        var r = RedoubtRun(seed: seed)
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
        let before = run(&r, steps: seconds(3)) { $0.isWaveStarted }
        #expect(count(before, "arrivalTelegraphed") == 20)
        #expect(count(before, "enemyArrived") <= 1)
        // ...and lands as the wave begins, all twenty within the first second.
        let events = run(&r, steps: seconds(0.9))
        #expect(count(events, "enemyArrived") + count(before, "enemyArrived") == 20)
        #expect(r.enemies.count == 20)
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
        #expect(waves.floorCrowd(forWave: 1) == 20)
        #expect(waves.floorCrowd(forWave: 2) == 28)
        #expect(waves.floorCrowd(forWave: 9) == 84)
        #expect(waves.floorCrowd(forWave: 30) == 90)
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
