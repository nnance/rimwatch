import Testing
import GameCore
@testable import RidgelineCore

@Suite struct PlayerTests {
    @Test func thrustBuildsSpeedUpToTheLimitAndTurnsTheShip() {
        var sim = quietSimulation()
        run(&sim, maxSteps: 120, input: InputState(move: Vec2(1, 0)))
        #expect(sim.player.vel.x > 300)
        #expect(sim.player.facing == 1)

        run(&sim, maxSteps: 600, input: InputState(move: Vec2(1, 0)))
        #expect(sim.player.vel.x <= sim.tuning.maxSpeed)
        #expect(sim.player.vel.x > sim.tuning.maxSpeed * 0.95)

        run(&sim, maxSteps: 1, input: InputState(move: Vec2(-1, 0)))
        #expect(sim.player.facing == -1)
    }

    @Test func shipCoastsToAStopWithoutThrust() {
        var sim = quietSimulation()
        run(&sim, maxSteps: 240, input: InputState(move: Vec2(1, 0)))
        run(&sim, maxSteps: 120 * 5)
        #expect(abs(sim.player.vel.x) < 1)
    }

    @Test func flyingOffOneEdgeArrivesAtTheOther() {
        var sim = quietSimulation()
        sim.player.pos.x = sim.world.width - 5
        run(&sim, maxSteps: 120, input: InputState(move: Vec2(1, 0)))
        // A second of thrust covers a few hundred units, so the ship is now just past the seam.
        #expect(sim.player.pos.x > 100)
        #expect(sim.player.pos.x < 700)
    }

    @Test func shipStaysBetweenTheGroundAndTheCeiling() {
        var sim = quietSimulation()
        run(&sim, maxSteps: 600, input: InputState(move: Vec2(0, -1)))
        let floor = sim.world.groundHeight(at: sim.player.pos.x) + sim.tuning.playerRadius + 2
        #expect(sim.player.pos.y == floor)

        run(&sim, maxSteps: 600, input: InputState(move: Vec2(0, 1)))
        #expect(sim.player.pos.y == sim.world.ceiling)
    }

    @Test func lanceOverheatsUnderSustainedFireThenRecovers() {
        var sim = quietSimulation()
        let firing = InputState(fire: true)

        let heating = run(&sim, maxSteps: 120 * 10, input: firing) { $0 == .playerOverheated }
        #expect(heating.contains(.playerOverheated))
        #expect(sim.player.isOverheated)

        // Locked out while hot, even with the trigger held.
        let locked = run(&sim, maxSteps: 30, input: firing)
        #expect(!locked.contains { $0.isPlayerFired })

        run(&sim, maxSteps: 120 * 3)
        #expect(!sim.player.isOverheated)
        let recovered = run(&sim, maxSteps: 2, input: firing)
        #expect(recovered.contains { $0.isPlayerFired })
    }
}

@Suite struct CombatTests {
    @Test func shotDestroysAHarvesterOnTheFarSideOfTheSeam() {
        var sim = quietSimulation()
        let y = sim.world.ceiling - 100
        sim.player.pos = Vec2(sim.world.width - 60, y)
        sim.player.facing = 1
        let id = sim.addEnemy(kind: .harvester, at: Vec2(40, y), state: .roaming)

        let events = run(&sim, maxSteps: 60, input: InputState(fire: true)) { $0.isEnemyDestroyed }

        #expect(events.contains { event in
            if case .enemyDestroyed(id, .harvester, _, 150) = event { true } else { false }
        })
        #expect(sim.enemies.isEmpty)
        #expect(sim.score == 150)
    }

    @Test func shotsFiredAwayFromAnEnemyMiss() {
        var sim = quietSimulation()
        let y = sim.world.ceiling - 100
        sim.player.pos = Vec2(1000, y)
        sim.player.facing = -1
        sim.addEnemy(kind: .harvester, at: Vec2(1200, y), state: .roaming)
        sim.enemies[0].fireTimer = 1000

        run(&sim, maxSteps: 50, input: InputState(fire: true))
        #expect(sim.enemies.count == 1)
        #expect(sim.score == 0)
    }

    @Test func collisionCostsALifeAndRespawnIsBrieflyProtected() {
        var sim = quietSimulation()
        sim.addEnemy(kind: .husk, at: sim.player.pos, state: .hunting)

        let crash = run(&sim, maxSteps: 1)
        #expect(crash.contains { $0.isPlayerDestroyed })
        #expect(crash.contains { $0.isEnemyDestroyed })
        #expect(sim.player.lives == 2)
        #expect(!sim.player.isAlive)

        run(&sim, maxSteps: 400) { $0 == .playerRespawned }
        #expect(sim.player.isAlive)
        #expect(sim.player.invulnerableTimer > 0)

        // A Husk sitting on the ship cannot hurt it until the protection runs out.
        sim.addEnemy(kind: .husk, at: sim.player.pos, state: .hunting)
        let protectedSteps = Int((sim.tuning.respawnInvulnerability - 0.5) / Simulation.timeStep)
        let protected = run(&sim, maxSteps: protectedSteps)
        #expect(!protected.contains { $0.isPlayerDestroyed })
        let exposed = run(&sim, maxSteps: 120) { $0.isPlayerDestroyed }
        #expect(exposed.contains { $0.isPlayerDestroyed })
        #expect(sim.player.lives == 1)
    }

    @Test func losingTheLastLifeEndsTheGame() {
        var sim = quietSimulation()
        sim.player.lives = 1
        sim.addEnemy(kind: .husk, at: sim.player.pos, state: .hunting)

        let events = run(&sim, maxSteps: 1)
        #expect(events.contains(.gameOver(score: 250)))
        #expect(sim.isGameOver)

        let tick = sim.tick
        #expect(sim.step(idle).isEmpty)
        #expect(sim.tick == tick)
    }

    @Test func enemyShotDestroysThePlayer() {
        var sim = quietSimulation()
        sim.addEnemy(kind: .harvester, at: Vec2(sim.player.pos.x + 200, sim.player.pos.y), state: .roaming)
        sim.enemies[0].fireTimer = 0
        sim.enemies[0].vel = .zero

        let events = run(&sim, maxSteps: 240) { $0.isPlayerDestroyed }
        #expect(events.contains { if case .enemyFired = $0 { true } else { false } })
        #expect(events.contains { $0.isPlayerDestroyed })
    }
}

@Suite struct RescueTests {
    /// One colonist, one Harvester starting just off to the side, player far out of range.
    private func abductionScene() -> (sim: Simulation, colonistID: Int) {
        var sim = quietSimulation()
        sim.colonists = [sim.colonists[0]]
        let colonist = sim.colonists[0]
        sim.player.pos.x = sim.world.wrap(colonist.pos.x + sim.world.width / 2)
        sim.addEnemy(
            kind: .harvester,
            at: Vec2(colonist.pos.x + 100, sim.world.ceiling - 30),
            state: .seeking(target: nil)
        )
        return (sim, colonist.id)
    }

    @Test func completedAbductionLosesTheColonistAndFormsAHusk() {
        var (sim, colonistID) = abductionScene()
        let harvesterID = sim.enemies[0].id

        let events = run(&sim, maxSteps: 120 * 60) { $0.isHuskFormed }

        let grabbed = events.firstIndex(of: .colonistGrabbed(id: colonistID))
        let formed = events.firstIndex { $0.isHuskFormed }
        #expect(grabbed != nil)
        #expect(formed != nil)
        if let grabbed, let formed { #expect(grabbed < formed) }
        #expect(events.contains { $0.isColonistLost })
        #expect(sim.colonists[0].state == .lost)
        #expect(sim.survivingColonists == 0)
        #expect(sim.enemies.count == 1)
        #expect(sim.enemies[0].kind == .husk)
        #expect(sim.enemies[0].id == harvesterID)
        #expect(sim.enemies[0].state == .hunting)
    }

    @Test func shootingTheHarvesterThenCatchingAndReturningTheColonistScores() throws {
        var (sim, colonistID) = abductionScene()
        run(&sim, maxSteps: 120 * 30) { $0.isColonistGrabbed }
        run(&sim, maxSteps: 480)
        #expect(sim.colonists[0].state == .held(by: sim.enemies[0].id))

        // Line up beside the Harvester and shoot it.
        let harvester = sim.enemies[0]
        sim.player.invulnerableTimer = 1_000_000
        sim.player.pos = Vec2(sim.world.wrap(harvester.pos.x - 150), harvester.pos.y)
        sim.player.facing = 1
        let shot = run(&sim, maxSteps: 60, input: InputState(fire: true)) { $0.isEnemyDestroyed }
        #expect(shot.contains(.colonistDropped(id: colonistID)))
        guard case .falling = sim.colonists[0].state else {
            Issue.record("colonist should be falling, is \(sim.colonists[0].state)")
            return
        }

        // Fly under the falling colonist.
        sim.player.pos = sim.colonists[0].pos
        let caught = run(&sim, maxSteps: 1)
        #expect(caught.contains(.colonistCaught(id: colonistID)))
        #expect(sim.player.carried == [colonistID])

        // Carried colonists hang beneath the ship.
        run(&sim, maxSteps: 1)
        #expect(sim.colonists[0].pos.y < sim.player.pos.y)

        // Bring them down at an outpost.
        let outpost = try #require(sim.world.outposts.last)
        sim.player.pos = Vec2(outpost.x, outpost.groundY + 30)
        let delivered = run(&sim, maxSteps: 1)
        #expect(delivered.contains(.colonistDelivered(id: colonistID, outpost: outpost.id, points: 500)))
        #expect(sim.colonists[0].state == .grounded)
        #expect(sim.colonists[0].home == outpost.id)
        #expect(sim.player.carried.isEmpty)
        #expect(sim.score == 150 + 250 + 500)
    }

    @Test func carryingTwoColonistsDoublesEachDelivery() throws {
        var sim = quietSimulation()
        sim.player.pos.y = 400
        for index in 0..<2 {
            sim.colonists[index].pos = sim.player.pos
            sim.colonists[index].state = .falling(speed: 0, from: 300)
        }
        run(&sim, maxSteps: 1)
        #expect(sim.player.carried.count == 2)

        let outpost = try #require(sim.world.outposts.first)
        sim.player.pos = Vec2(outpost.x, outpost.groundY + 30)
        let events = run(&sim, maxSteps: 1)
        #expect(events.count { $0.isColonistDelivered } == 2)
        #expect(sim.score == 2 * 250 + 2 * 1000)
    }

    @Test func noDeliveryWhenFlyingHighOverAnOutpost() throws {
        var sim = quietSimulation()
        sim.colonists[0].pos = sim.player.pos
        sim.colonists[0].state = .falling(speed: 0, from: 300)
        run(&sim, maxSteps: 1)

        let outpost = try #require(sim.world.outposts.first)
        sim.player.pos = Vec2(outpost.x, outpost.groundY + 200)
        run(&sim, maxSteps: 10)
        #expect(sim.player.carried.count == 1)
    }

    @Test func aLongFallIsFatalAndAShortFallIsNot() {
        var sim = quietSimulation()
        sim.player.pos.x = sim.world.wrap(sim.colonists[0].pos.x + 2000)
        let ground = sim.colonists[0].pos.y

        sim.colonists[0].pos.y = ground + 300
        sim.colonists[0].state = .falling(speed: 0, from: 300)
        let long = run(&sim, maxSteps: 120 * 5) { $0.isColonistLost || $0.isColonistLanded }
        #expect(long.contains { $0.isColonistLost })
        #expect(sim.colonists[0].state == .lost)

        let short = sim.tuning.safeFallHeight * 0.7
        sim.colonists[1].pos.y += short
        sim.colonists[1].state = .falling(speed: 0, from: short)
        let landing = run(&sim, maxSteps: 120 * 5) { $0.isColonistLost || $0.isColonistLanded }
        #expect(landing.contains { $0.isColonistLanded })
        #expect(sim.colonists[1].state == .grounded)
    }

    @Test func dyingDropsWhoeverIsBeingCarried() {
        var sim = quietSimulation()
        sim.colonists[0].pos = sim.player.pos
        sim.colonists[0].state = .falling(speed: 0, from: 300)
        run(&sim, maxSteps: 1)
        #expect(sim.player.carried.count == 1)

        sim.addEnemy(kind: .husk, at: sim.player.pos, state: .hunting)
        let events = run(&sim, maxSteps: 1)
        #expect(events.contains { $0.isColonistDropped })
        #expect(sim.player.carried.isEmpty)
        guard case .falling = sim.colonists[0].state else {
            Issue.record("colonist should be falling")
            return
        }
    }

    @Test func twoHarvestersNeverChaseTheSameColonist() {
        var sim = quietSimulation()
        sim.colonists = Array(sim.colonists.prefix(2))
        let x = sim.colonists[0].pos.x
        sim.player.pos.x = sim.world.wrap(x + sim.world.width / 2)
        sim.addEnemy(kind: .harvester, at: Vec2(x + 80, 500), state: .seeking(target: nil))
        sim.addEnemy(kind: .harvester, at: Vec2(x - 80, 500), state: .seeking(target: nil))
        run(&sim, maxSteps: 5)

        let targets = sim.enemies.compactMap { enemy -> Int? in
            if case .seeking(let target) = enemy.state { target } else { nil }
        }
        #expect(targets.count == 2)
        #expect(Set(targets).count == 2)
    }
}

@Suite struct WaveTests {
    @Test func clearingAWaveBringsABiggerOne() throws {
        var sim = Simulation(seed: 11)
        sim.player.invulnerableTimer = 1_000_000

        let first = run(&sim, maxSteps: 120 * 5) { $0 == .waveStarted(1) }
        #expect(first.contains(.waveStarted(1)))

        var spawnedInWaveOne = 0
        var sawWaveTwo = false
        for _ in 0..<(120 * 60) {
            let events = sim.step(idle)
            spawnedInWaveOne += events.count { if case .enemySpawned = $0 { true } else { false } }
            while !sim.enemies.isEmpty {
                sim.destroyEnemy(at: 0)
            }
            if events.contains(.waveStarted(2)) {
                sawWaveTwo = true
                break
            }
        }

        let director = WaveDirector()
        #expect(sawWaveTwo)
        #expect(sim.wave == 2)
        #expect(spawnedInWaveOne == director.spawns(forWave: 1).count)
        #expect(director.spawns(forWave: 2).count > director.spawns(forWave: 1).count)
        let huskDebut = try #require(WaveDirector.debut.first { $0.kind == .husk }?.wave)
        #expect(director.spawns(forWave: huskDebut).contains { $0.kind == .husk })
    }

    @Test func enemiesSpawnWellAwayFromThePlayer() {
        var sim = Simulation(seed: 3)
        run(&sim, maxSteps: 120 * 6) { if case .enemySpawned = $0 { true } else { false } }
        #expect(!sim.enemies.isEmpty)
        for enemy in sim.enemies {
            #expect(abs(sim.world.delta(from: sim.player.pos.x, to: enemy.pos.x)) >= sim.tuning.spawnClearance - 1)
        }
    }
}
