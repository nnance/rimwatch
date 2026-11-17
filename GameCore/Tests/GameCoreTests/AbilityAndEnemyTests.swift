import Testing
@testable import GameCore

private func quietSimulation(_ adjust: (inout Tuning) -> Void) -> Simulation {
    var tuning = Tuning()
    adjust(&tuning)
    var sim = Simulation(seed: 7, tuning: tuning)
    sim.wavesEnabled = false
    return sim
}

/// Puts `count` colonists in the player's hold by dropping them onto the ship.
private func carry(_ count: Int, in sim: inout Simulation) {
    sim.player.pos.y = 400
    for index in 0..<count {
        sim.colonists[index].pos = sim.player.pos
        sim.colonists[index].state = .falling(speed: 0, from: 300)
    }
    run(&sim, maxSteps: 1)
}

@Suite struct ShockwaveTests {
    @Test func destroysEnemiesAndShotsInRangeAndLeavesTheRest() {
        var sim = quietSimulation()
        let p = sim.player.pos
        sim.addEnemy(kind: .husk, at: Vec2(p.x + 300, p.y))
        sim.addEnemy(kind: .anchor, at: Vec2(p.x - 400, 500))
        let farID = sim.addEnemy(kind: .husk, at: Vec2(p.x + 900, p.y))
        sim.fireEnemyShot(from: Vec2(p.x + 200, p.y + 60))
        #expect(sim.projectiles.count == 1)

        let events = run(&sim, maxSteps: 1, input: InputState(shockwave: true))

        #expect(events.contains { $0.kind == "shockwave" })
        #expect(sim.enemies.map(\.id) == [farID])
        #expect(sim.projectiles.isEmpty)
        #expect(sim.player.shockwaves == sim.tuning.startingShockwaves - 1)
        #expect(sim.score == 250 + 500)
    }

    @Test func firesOncePerPressAndNotAtAllWhenEmpty() {
        var sim = quietSimulation()
        let pressed = InputState(shockwave: true)

        run(&sim, maxSteps: 30, input: pressed)
        #expect(sim.player.shockwaves == 2)

        run(&sim, maxSteps: 1)
        run(&sim, maxSteps: 1, input: pressed)
        #expect(sim.player.shockwaves == 1)

        sim.player.shockwaves = 0
        run(&sim, maxSteps: 1)
        let empty = run(&sim, maxSteps: 1, input: pressed)
        #expect(!empty.contains { $0.kind == "shockwave" })
        #expect(sim.player.shockwaves == 0)
    }

    @Test func aBroodCaughtInTheBlastDoesNotBurst() {
        var sim = quietSimulation()
        sim.addEnemy(kind: .brood, at: Vec2(sim.player.pos.x + 200, 300))
        run(&sim, maxSteps: 1, input: InputState(shockwave: true))
        #expect(sim.enemies.isEmpty)
    }

    @Test func aHarvesterCaughtInTheBlastDropsItsColonist() {
        var sim = quietSimulation()
        let p = sim.player.pos
        let colonistID = sim.colonists[0].id
        let harvesterID = sim.addEnemy(
            kind: .harvester, at: Vec2(p.x + 200, 400), state: .lifting(colonist: colonistID))
        sim.colonists[0].state = .held(by: harvesterID)
        sim.colonists[0].pos = Vec2(p.x + 200, 382)

        let events = run(&sim, maxSteps: 1, input: InputState(shockwave: true))
        #expect(events.contains(.colonistDropped(id: colonistID)))
        guard case .falling = sim.colonists[0].state else {
            Issue.record("colonist should be falling")
            return
        }
    }
}

@Suite struct BlinkTests {
    @Test func jumpsAheadAcrossTheSeamThenNeedsToRecharge() {
        var sim = quietSimulation()
        sim.player.pos.x = sim.world.width - 50
        let pressed = InputState(blink: true)

        let events = run(&sim, maxSteps: 1, input: pressed)
        #expect(events.contains { $0.kind == "playerBlinked" })
        #expect(abs(sim.player.pos.x - (sim.tuning.blinkDistance - 50)) < 1)
        #expect(sim.player.invulnerableTimer > 0)

        run(&sim, maxSteps: 1)
        let tooSoon = run(&sim, maxSteps: 1, input: pressed)
        #expect(!tooSoon.contains { $0.kind == "playerBlinked" })

        run(&sim, maxSteps: 120 * 3)
        let ready = run(&sim, maxSteps: 1, input: pressed)
        #expect(ready.contains { $0.kind == "playerBlinked" })
    }

    @Test func followsTheStickAndStaysInsideTheWorld() {
        var sim = quietSimulation()
        let startX = sim.player.pos.x
        run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, 1), blink: true))
        #expect(sim.player.pos.y > 500)
        #expect(sim.player.pos.y <= sim.world.ceiling)
        #expect(sim.player.pos.x == startX)

        run(&sim, maxSteps: 120 * 3)
        run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, -1), blink: true))
        run(&sim, maxSteps: 120 * 3)
        run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, -1), blink: true))
        run(&sim, maxSteps: 120 * 3)
        run(&sim, maxSteps: 1, input: InputState(move: Vec2(0, -1), blink: true))
        #expect(sim.player.pos.y >= sim.world.groundHeight(at: sim.player.pos.x) + sim.tuning.playerRadius)
    }
}

@Suite struct ShieldTests {
    @Test func twoDeliveriesFillTheShieldAndItAbsorbsOneHit() throws {
        var sim = quietSimulation()
        #expect(sim.player.shield == 0)
        carry(2, in: &sim)
        let outpost = try #require(sim.world.outposts.first)
        sim.player.pos = Vec2(outpost.x, outpost.groundY + 30)
        run(&sim, maxSteps: 1)
        #expect(sim.player.shield == 1)

        sim.addEnemy(kind: .husk, at: sim.player.pos)
        let first = run(&sim, maxSteps: 1)
        #expect(first.contains(.shieldBroken))
        #expect(sim.player.isAlive)
        #expect(sim.player.lives == sim.tuning.startingLives)
        #expect(sim.player.shield == 0)

        // Once the brief protection ends, the next hit is fatal.
        run(&sim, maxSteps: 130)
        sim.addEnemy(kind: .husk, at: sim.player.pos)
        let second = run(&sim, maxSteps: 1)
        #expect(second.contains { $0.isPlayerDestroyed })
    }
}

@Suite struct SowerTests {
    @Test func laysAMineEveryFewSecondsAndMinesExpireUnscored() {
        var sim = quietSimulation()
        sim.player.pos.x = 5000
        sim.addEnemy(kind: .sower, at: Vec2(1000, 350))

        let events = run(&sim, maxSteps: 120 * 10)
        #expect(events.count { $0.kind == "mineLaid" } == 3)
        #expect(sim.enemies.count { $0.kind == .mine } == 3)
        #expect(sim.enemies.filter { $0.kind == .mine }.allSatisfy { $0.state == .armed })

        sim.enemies.removeAll { $0.kind == .sower }
        run(&sim, maxSteps: 120 * 13)
        #expect(sim.enemies.isEmpty)
        #expect(sim.score == 0)
    }

    @Test func neverHasMoreThanTheMineLimitOut() {
        var sim = quietSimulation { $0.maxMines = 2; $0.mineLifetime = 100 }
        sim.player.pos.x = 5000
        sim.addEnemy(kind: .sower, at: Vec2(1000, 350))
        run(&sim, maxSteps: 120 * 20)
        #expect(sim.enemies.count { $0.kind == .mine } == 2)
    }

    @Test func touchingAMineIsFatal() {
        var sim = quietSimulation()
        sim.addEnemy(kind: .mine, at: sim.player.pos)
        let events = run(&sim, maxSteps: 1)
        #expect(events.contains { $0.isPlayerDestroyed })
    }
}

@Suite struct BroodTests {
    @Test func takesTwoHitsThenBurstsIntoMotes() {
        var sim = quietSimulation()
        sim.player.pos = Vec2(1000, 400)
        sim.player.invulnerableTimer = 1_000_000
        let id = sim.addEnemy(kind: .brood, at: Vec2(1060, 400))
        sim.enemies[0].vel = .zero

        let events = run(&sim, maxSteps: 60, input: InputState(fire: true)) { $0.isEnemyDestroyed }

        #expect(events.contains { if case .enemyHit(id, _) = $0 { true } else { false } })
        #expect(events.contains { if case .enemyDestroyed(id, .brood, _, 300) = $0 { true } else { false } })
        #expect(sim.enemies.count == sim.tuning.motesPerBrood)
        #expect(sim.enemies.allSatisfy { $0.kind == .mote && $0.state == .hunting })
        #expect(sim.score == 300)
    }

    @Test func motesCloseInOnThePlayer() {
        var sim = quietSimulation()
        sim.player.invulnerableTimer = 1_000_000
        let p = sim.player.pos
        sim.addEnemy(kind: .mote, at: Vec2(p.x + 600, p.y))
        run(&sim, maxSteps: 120 * 3)
        #expect(sim.world.distance(sim.enemies[0].pos, sim.player.pos) < 200)
    }
}

@Suite struct LancerTests {
    @Test func windsUpMatchesAltitudeThenChargesAtThePlayer() {
        var sim = quietSimulation()
        sim.player.pos = Vec2(2000, 200)
        sim.player.invulnerableTimer = 1_000_000
        let id = sim.addEnemy(kind: .lancer, at: Vec2(2400, 450))
        sim.enemies[0].vel = .zero

        let windup = run(&sim, maxSteps: 5)
        #expect(windup.contains(.lancerTelegraph(id: id)))

        let charge = run(&sim, maxSteps: 120) { $0 == .lancerCharged(id: id) }
        #expect(charge.contains(.lancerCharged(id: id)))
        #expect(sim.enemies[0].vel.x == -sim.tuning.lancerChargeSpeed)
        #expect(abs(sim.enemies[0].pos.y - 200) < 60)

        // The charge carries it past the player, after which it has to recover.
        run(&sim, maxSteps: 120 * 2)
        #expect(sim.world.delta(from: 2000, to: sim.enemies[0].pos.x) < -300)
        guard case .recovering = sim.enemies[0].state else {
            Issue.record("lancer should be recovering, is \(sim.enemies[0].state)")
            return
        }
    }

    @Test func ignoresAPlayerWhoIsOutOfRange() {
        var sim = quietSimulation()
        sim.addEnemy(kind: .lancer, at: Vec2(sim.player.pos.x + 1500, 400))
        run(&sim, maxSteps: 120)
        #expect(sim.enemies[0].state == .patrolling)
    }

    @Test func aChargeThatConnectsDestroysTheShip() {
        var sim = quietSimulation()
        sim.player.pos = Vec2(2000, 300)
        sim.addEnemy(kind: .lancer, at: Vec2(2300, 300))
        let events = run(&sim, maxSteps: 120 * 3) { $0.isPlayerDestroyed }
        #expect(events.contains { $0.isPlayerDestroyed })
    }
}

@Suite struct AnchorTests {
    private func landedAnchor() -> (sim: Simulation, id: Int) {
        var sim = quietSimulation()
        let outpost = sim.world.outposts[1]
        sim.player.pos.x = sim.world.wrap(outpost.x + sim.world.width / 2)
        let id = sim.addEnemy(kind: .anchor, at: Vec2(outpost.x + 100, 300))
        run(&sim, maxSteps: 120 * 20) { $0 == .anchorLanded(id: id, outpost: 1) }
        return (sim, id)
    }

    @Test func landsOnTheNearestOutpostAndDrillsItToDestruction() throws {
        var (sim, id) = landedAnchor()
        #expect(sim.enemies[0].state == .drilling(outpost: 1))

        let events = run(&sim, maxSteps: 120 * 20) { $0 == .outpostDestroyed(id: 1) }
        #expect(events.contains(.outpostDestroyed(id: 1)))
        #expect(!sim.isOutpostIntact(1))
        #expect(events.count { $0.isColonistLost } == sim.tuning.colonistsPerOutpost)
        #expect(sim.colonists.filter { $0.home == 1 }.allSatisfy { $0.state == .lost })

        // It then goes looking for another outpost.
        run(&sim, maxSteps: 2)
        guard case .descending(let next) = sim.enemies[0].state else {
            Issue.record("anchor should be heading for another outpost")
            return
        }
        #expect(next != 1)
        #expect(sim.enemies[0].id == id)
    }

    @Test func aDestroyedOutpostNoLongerTakesDeliveries() {
        var (sim, _) = landedAnchor()
        run(&sim, maxSteps: 120 * 20) { $0 == .outpostDestroyed(id: 1) }
        sim.enemies.removeAll()

        let survivor = sim.colonists.firstIndex { $0.state == .grounded }!
        sim.player.pos.y = 400
        sim.colonists[survivor].pos = sim.player.pos
        sim.colonists[survivor].state = .falling(speed: 0, from: 300)
        run(&sim, maxSteps: 1)
        #expect(sim.player.carried.count == 1)

        let ruined = sim.world.outposts[1]
        sim.player.pos = Vec2(ruined.x, ruined.groundY + 30)
        run(&sim, maxSteps: 5)
        #expect(sim.player.carried.count == 1)

        let standing = sim.world.outposts[0]
        sim.player.pos = Vec2(standing.x, standing.groundY + 30)
        run(&sim, maxSteps: 1)
        #expect(sim.player.carried.isEmpty)
    }

    @Test func destroyingTheAnchorMidDrillSavesTheOutpost() {
        var (sim, id) = landedAnchor()
        run(&sim, maxSteps: 120 * 5)
        #expect(sim.outpostIntegrity[1] < 0.75)
        #expect(sim.outpostIntegrity[1] > 0.5)

        let anchor = sim.enemies[0]
        sim.player.pos = Vec2(anchor.pos.x - 45, anchor.pos.y)
        sim.player.facing = 1
        let events = run(&sim, maxSteps: 120, input: InputState(fire: true)) { $0.isEnemyDestroyed }

        #expect(events.count { if case .enemyHit(id, _) = $0 { true } else { false } } == 2)
        #expect(events.contains { if case .enemyDestroyed(id, .anchor, _, 500) = $0 { true } else { false } })
        #expect(sim.outpostIntegrity[1] == 1)
        #expect(sim.survivingColonists == sim.colonists.count)
    }
}

@Suite struct BlackoutTests {
    @Test func losingEveryColonistTurnsHarvestersAndASupplyDropEndsIt() {
        var sim = quietSimulation { $0.supplyDelay = 2 }
        sim.player.invulnerableTimer = 1_000_000
        sim.addEnemy(kind: .harvester, at: Vec2(sim.player.pos.x + 1500, 500))
        let before = sim.colonists.count
        for index in sim.colonists.indices {
            sim.colonists[index].state = .lost
        }

        let begin = run(&sim, maxSteps: 1)
        #expect(begin.contains(.blackoutBegan))
        #expect(sim.isBlackout)
        #expect(sim.enemies[0].kind == .husk)
        #expect(sim.enemies[0].state == .hunting)

        // It is announced once, not every step.
        let during = run(&sim, maxSteps: 60)
        #expect(!during.contains(.blackoutBegan))

        let end = run(&sim, maxSteps: 120 * 3) { $0 == .blackoutEnded }
        #expect(end.contains { $0.kind == "outpostRestored" })
        #expect(end.contains(.blackoutEnded))
        #expect(!sim.isBlackout)
        #expect(sim.survivingColonists == sim.tuning.colonistsPerOutpost)
        #expect(sim.colonists.count == before + sim.tuning.colonistsPerOutpost)
    }

    @Test func harvestersArriveAsHusksDuringABlackout() {
        var sim = Simulation(seed: 7)
        sim.player.invulnerableTimer = 1_000_000
        for index in sim.colonists.indices {
            sim.colonists[index].state = .lost
        }
        let events = run(&sim, maxSteps: 120 * 5) { $0.kind == "enemySpawned" }
        #expect(events.contains { if case .enemySpawned(_, .husk) = $0 { true } else { false } })
        #expect(sim.enemies.allSatisfy { $0.kind == .husk })
    }

    @Test func withEveryOutpostGoneASupplyDropRebuildsOneWithoutABlackout() {
        var sim = quietSimulation { $0.supplyDelay = 1 }
        carry(1, in: &sim)
        for id in sim.outpostIntegrity.indices {
            sim.destroyOutpost(id)
        }
        #expect(sim.survivingColonists == 1)

        let events = run(&sim, maxSteps: 120 * 2) { $0.kind == "outpostRestored" }
        #expect(events.contains { $0.kind == "outpostRestored" })
        #expect(!events.contains(.blackoutBegan))
        #expect(sim.outpostIntegrity.count { $0 > 0 } == 1)
        #expect(sim.survivingColonists == 1 + sim.tuning.colonistsPerOutpost)
    }
}

@Suite struct ScoringTests {
    @Test func eachExtraLifeThresholdEarnsALifeUpToTheLimit() {
        var sim = quietSimulation()
        let y = sim.world.ceiling - 100
        sim.player.pos = Vec2(1000, y)
        sim.score = sim.tuning.extraLifeEvery - 100
        sim.addEnemy(kind: .harvester, at: Vec2(1100, y), state: .roaming)

        let events = run(&sim, maxSteps: 60, input: InputState(fire: true)) { $0.isEnemyDestroyed }
        #expect(events.contains(.extraLife))
        #expect(sim.player.lives == sim.tuning.startingLives + 1)

        sim.player.lives = sim.tuning.maxLives
        sim.addScore(sim.tuning.extraLifeEvery)
        #expect(sim.player.lives == sim.tuning.maxLives)
    }

    @Test func clearingAWavePaysForSurvivorsAndEveryThirdWaveAddsAShockwave() {
        var sim = Simulation(seed: 11)
        sim.player.invulnerableTimer = 1_000_000
        var cleared: [GameEvent] = []

        for _ in 0..<(120 * 120) {
            let events = sim.step(idle)
            cleared += events.filter { $0.kind == "waveCleared" }
            while !sim.enemies.isEmpty {
                sim.destroyEnemy(at: 0, split: false)
            }
            if events.contains(.waveStarted(3)) { break }
        }

        // Nobody was abducted, so wave 1 pays 100 for each of the ten colonists.
        #expect(cleared.first == .waveCleared(wave: 1, bonus: 1000))
        #expect(cleared.count == 2)
        #expect(sim.wave == 3)
        #expect(sim.player.shockwaves == sim.tuning.startingShockwaves + 1)
    }
}

@Suite struct WaveDirectorTests {
    let director = WaveDirector()

    @Test func theFirstWaveIsHarvestersOnly() {
        #expect(director.composition(forWave: 1).map(\.kind) == [.harvester])
    }

    @Test func newEnemiesAreIntroducedOneAtATime() {
        let introduced: [(EnemyKind, Int)] = [(.sower, 2), (.brood, 3), (.lancer, 5), (.anchor, 7), (.husk, 9)]
        #expect(WaveDirector.debut.map(\.kind) == introduced.map(\.0))
        #expect(WaveDirector.debut.map(\.wave) == introduced.map(\.1))
        for (kind, wave) in introduced {
            #expect(!director.composition(forWave: wave - 1).contains { $0.kind == kind })
            // A debut: just one of the new kind, alongside Harvesters and nothing else.
            let debut = director.composition(forWave: wave)
            #expect(debut.map(\.kind) == [.harvester, kind])
            #expect(debut.first { $0.kind == kind }?.count == 1)
            // The next wave that isn't a debut mixes it in with the others.
            let mixed = (wave + 1...wave + 3).first { w in !introduced.contains { $0.1 == w } }!
            let kinds = director.composition(forWave: mixed).map(\.kind)
            #expect(kinds.contains(kind))
            #expect(kinds.count > 2)
        }
    }

    @Test func harvestersShootMoreOftenAsWavesGoOn() {
        var previous = Double.infinity
        for wave in 1...20 {
            let scale = director.fireIntervalScale(forWave: wave)
            #expect(scale <= previous)
            #expect(scale > 0)
            previous = scale
        }
        #expect(director.fireIntervalScale(forWave: 1) > 1)
    }

    @Test func wavesNeverShrinkAndNeverSpawnMinesOrMotesDirectly() {
        var previous = 0
        for wave in 1...20 {
            let spawns = director.spawns(forWave: wave)
            #expect(spawns.count >= previous)
            #expect(!spawns.contains { $0.kind == .mine || $0.kind == .mote })
            #expect(spawns.allSatisfy { $0.delay >= 0 })
            previous = spawns.count
        }
    }
}
