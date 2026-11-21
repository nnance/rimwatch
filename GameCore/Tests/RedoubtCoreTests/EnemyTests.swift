import Foundation
import Testing
import GameCore
@testable import RedoubtCore

@Suite struct EnemyTests {
    @Test func skittersWalkAtTheOrbAndDieToOneShot() throws {
        var r = quietRun()
        let id = r.addEnemy(.skitter, at: Vec2(700, 300))
        let start = try distance(r.req(enemy: id).pos, r.orb.pos)
        run(&r, steps: seconds(1))
        let after = try distance(r.req(enemy: id).pos, r.orb.pos)
        #expect(start - after > 25)
        #expect(start - after < 80)
        let to = try r.req(enemy: id).pos - r.orb.pos
        let events = run(&r, steps: seconds(1), input: RedoubtInput(aim: to * (1 / to.length))) { $0.isEnemyDestroyed }
        #expect(events.contains { if case .enemyDestroyed(id, .skitter, _, 50, false) = $0 { true } else { false } })
        #expect(r.score == 50)
    }

    @Test func skittersSpeedUpInLaterWaves() throws {
        let waves = RedoubtWaves()
        let t = RedoubtTuning()
        #expect(waves.skitterSpeedScale(forWave: 1, tuning: t) == 1)
        #expect(waves.skitterSpeedScale(forWave: 5, tuning: t) > waves.skitterSpeedScale(forWave: 2, tuning: t))
        #expect(waves.skitterSpeedScale(forWave: 60, tuning: t) == t.skitterMaxScale)
    }

    @Test func theCrowdSpreadsOutInsteadOfStacking() throws {
        var r = quietRun()
        for _ in 0..<30 { r.addEnemy(.skitter, at: Vec2(700, 300)) }
        run(&r, steps: seconds(0.5))
        var overlapping = 0
        for i in r.enemies.indices {
            for j in r.enemies.indices where j > i
                && distance(r.enemies[i].pos, r.enemies[j].pos) < 4 { overlapping += 1 }
        }
        #expect(overlapping < 5)
    }

    @Test func aGleanerDragsAColonistToTheWallAndComesBackAsAHusk() throws {
        var r = quietRun()
        let colonist = r.addColonist(at: Vec2(450, 80))
        let gleaner = r.addEnemy(.gleaner, at: Vec2(450, 150))
        let events = run(&r, steps: seconds(6)) { $0.isHuskFormed }
        let kinds = events.map(\.kind)
        // Seized, dragged to the south wall, lost, and the Gleaner turns.
        #expect(kinds.contains("colonistSeized"))
        #expect(events.contains { if case .colonistTaken(colonist, .gleaner, gleaner, _) = $0 { true } else { false } })
        let seized = try #require(kinds.firstIndex(of: "colonistSeized"))
        let taken = try #require(kinds.firstIndex(of: "colonistTaken"))
        #expect(seized < taken)
        #expect(events.contains { if case .huskFormed(gleaner, _) = $0 { true } else { false } })
        let husk = try r.req(enemy: gleaner)
        #expect(husk.role == .husk)
        #expect(husk.pos.y < r.tuning.figure(15))
        #expect(try r.req(colonist: colonist).state == .lost)
        // It waits a moment, then hunts.
        guard case .waking = husk.state else {
            Issue.record("a fresh Husk should be waking")
            return
        }
        let held = husk.pos
        run(&r, steps: seconds(0.5))
        #expect(try distance(r.req(enemy: gleaner).pos, held) < 2)
        run(&r, steps: seconds(1))
        #expect(try r.req(enemy: gleaner).state == .hunting)
        #expect(try distance(r.req(enemy: gleaner).pos, r.orb.pos) < distance(held, r.orb.pos) - 40)
    }

    @Test func aGleanerTakesItsColonistToTheNearestBurrow() throws {
        var r = quietRun()
        let burrow = r.addEnemy(.burrow, at: Vec2(760, 150))
        r.enemies[r.index(of: burrow)].timer = 1e9  // keep it from pouring
        let colonist = r.addColonist(at: Vec2(700, 150))
        let gleaner = r.addEnemy(.gleaner, at: Vec2(660, 150))
        let events = run(&r, steps: seconds(6)) { $0.isHuskFormed }
        #expect(events.contains { if case .colonistTaken(colonist, .gleaner, gleaner, _) = $0 { true } else { false } })
        let husk = try r.req(enemy: gleaner)
        // At the Burrow's rim, not the wall 140 units away.
        #expect(try distance(husk.pos, r.req(enemy: burrow).pos) < r.tuning.figure(32))
    }

    @Test func shootingAGleanerFreesItsColonist() throws {
        var r = quietRun()
        let colonist = r.addColonist(at: Vec2(600, 300))
        let gleaner = r.addEnemy(.gleaner, at: Vec2(640, 300))
        run(&r, steps: seconds(2)) { if case .colonistSeized = $0 { true } else { false } }
        #expect(try r.req(colonist: colonist).state == .seized(by: gleaner))
        let events = run(&r, steps: seconds(1), input: RedoubtInput(aim: Vec2(1, 0))) {
            if case .colonistFreed = $0 { true } else { false }
        }
        #expect(events.contains { if case .colonistFreed(colonist, _) = $0 { true } else { false } })
        #expect(try r.req(colonist: colonist).state == .sheltering)
        #expect(r.enemy(gleaner) == nil)
    }

    @Test func aDraggedOrFreedColonistStaysOnTheFloor() throws {
        var r = quietRun()
        let colonist = r.addColonist(at: Vec2(450, 8))
        let gleaner = r.addEnemy(.gleaner, at: Vec2(450, 11))
        // Dragging away from the south wall: the colonist trails behind, toward it.
        let c = try #require(r.colonists.firstIndex { $0.id == colonist })
        r.colonists[c].state = .seized(by: gleaner)
        r.enemies[r.index(of: gleaner)].state = .dragging(colonist: colonist, destination: Vec2(450, 300))
        run(&r, steps: 1)
        let dragged = try r.req(colonist: colonist).pos
        #expect(dragged.y >= r.tuning.colonistRadius)
        // A colonist somehow off the floor is put back on it when freed.
        r.colonists[c].pos = Vec2(450, -4)
        r.destroyEnemy(at: r.index(of: gleaner), byShockwave: false)
        let freed = try r.req(colonist: colonist)
        #expect(freed.state == .sheltering)
        #expect(freed.pos.y >= r.tuning.colonistRadius)
    }

    @Test func twoGleanersDoNotGoForTheSameColonist() throws {
        var r = quietRun()
        let a = r.addColonist(at: Vec2(200, 100))
        let b = r.addColonist(at: Vec2(700, 500))
        let g1 = r.addEnemy(.gleaner, at: Vec2(250, 120))
        let g2 = r.addEnemy(.gleaner, at: Vec2(260, 130))
        run(&r, steps: 2)
        #expect(try r.req(enemy: g1).state == .seeking(colonist: a))
        #expect(try r.req(enemy: g2).state == .seeking(colonist: b))
    }

    @Test func aSpitterKeepsItsDistanceAndFiresAfterAWindUp() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        let id = r.addEnemy(.spitter, at: Vec2(550, 300))
        r.enemies[r.index(of: id)].timer = 1e9
        run(&r, steps: seconds(2))
        let d = try distance(r.req(enemy: id).pos, r.orb.pos)
        #expect(d > 200)
        // Ready to fire: it stops, winds up, then sends a slow shot at the orb.
        r.enemies[r.index(of: id)].timer = 0
        let events = run(&r, steps: seconds(1)) { if case .enemyFired = $0 { true } else { false } }
        let kinds = events.map(\.kind)
        #expect(kinds.contains("spitterWindUp"))
        guard let windUp = kinds.firstIndex(of: "spitterWindUp"),
              let fired = kinds.firstIndex(of: "enemyFired") else {
            Issue.record("no shot")
            return
        }
        #expect(windUp < fired)
        let shot = r.shots.first { $0.owner == .enemy }!
        #expect(abs(shot.vel.length - r.tuning.spitterShotSpeed) < 1e-6)
        let toOrb = r.orb.pos - shot.pos
        let cosine = (toOrb.x * shot.vel.x + toOrb.y * shot.vel.y) / (toOrb.length * shot.vel.length)
        #expect(cosine > 0.99)
    }

    @Test func aSpitterShotCostsALife() throws {
        var r = quietRun()
        let shot = r.takeID()
        r.shots.append(RedoubtShot(id: shot, owner: .enemy, pos: Vec2(450, 360), vel: Vec2(0, -165),
                                   radius: 5, timeLeft: 5))
        let events = run(&r, steps: seconds(1)) { $0.isOrbDestroyed }
        #expect(events.contains { if case .orbDestroyed(_, 2, .shot(id: shot)) = $0 { true } else { false } })
        #expect(events.contains { if case .shotEnded(shot, _, .hit) = $0 { true } else { false } })
        #expect(r.orb.lives == 2)
        #expect(r.shots.isEmpty)
    }

    @Test func aBurrowPoursOutSkittersUpToItsLimit() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        r.orb.pos = Vec2(100, 100)
        let burrow = r.addEnemy(.burrow, at: Vec2(700, 400))
        var events = run(&r, steps: seconds(1.3))
        #expect(count(events, "burrowSpawned") == 1)
        events = run(&r, steps: seconds(60))
        #expect(count(events, "burrowSpawned") == r.tuning.burrowMaxChildren - 1)
        #expect(r.enemies.count { $0.parent == burrow } == r.tuning.burrowMaxChildren)
        // Lose one and it pours out another.
        let child = r.enemies.firstIndex { $0.parent == burrow }!
        r.destroyEnemy(at: child, byShockwave: false)
        events = run(&r, steps: seconds(3))
        #expect(count(events, "burrowSpawned") == 1)
    }

    @Test func aBurrowHoldsBackWhileTheOrbIsClose() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        r.addEnemy(.burrow, at: Vec2(600, 300))
        let events = run(&r, steps: seconds(10))
        #expect(count(events, "burrowSpawned") == 0)
    }

    @Test func aBurrowTakesManyHits() throws {
        var r = quietRun()
        let burrow = r.addEnemy(.burrow, at: Vec2(600, 300))
        let events = run(&r, steps: seconds(3), input: RedoubtInput(aim: Vec2(1, 0))) { $0.isEnemyDestroyed }
        #expect(count(events, "enemyHit") == r.tuning.stats(for: .burrow).hp - 1)
        #expect(events.contains { if case .enemyDestroyed(burrow, .burrow, _, 1000, false) = $0 { true } else { false } })
    }

    @Test func shotsOnlyPushAThresherBack() throws {
        var r = quietRun()
        let id = r.addEnemy(.thresher, at: Vec2(650, 300))
        // Left alone it closes in, slowly.
        run(&r, steps: seconds(1))
        let near = try distance(r.req(enemy: id).pos, r.orb.pos)
        #expect(near < 200 && near > 160)
        // Under fire it is driven back and never destroyed.
        let events = run(&r, steps: seconds(4), input: RedoubtInput(aim: Vec2(1, 0)))
        #expect(r.enemy(id) != nil)
        #expect(try distance(r.req(enemy: id).pos, r.orb.pos) > near + 60)
        #expect(count(events, "enemyHit") > 30)
        #expect(count(events, "enemyDestroyed") == 0)
    }

    @Test func aThresherCrushesColonistsItMovesOver() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        let sheltering = r.addColonist(at: Vec2(560, 300))
        let thresher = r.addEnemy(.thresher, at: Vec2(640, 300))
        let events = run(&r, steps: seconds(4)) { if case .colonistCrushed = $0 { true } else { false } }
        #expect(events.contains { if case .colonistCrushed(sheltering, thresher, _) = $0 { true } else { false } })
        #expect(try r.req(colonist: sheltering).state == .lost)
    }

    @Test func aThresherCrushingAFollowerClosesTheLine() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        let ids = r.formLine(3)
        let middle = r.colonists.firstIndex { $0.id == ids[1] }!
        // Over the middle follower, clear of its neighbours.
        r.addEnemy(.thresher, at: r.colonists[middle].pos + Vec2(0, r.tuning.figure(20)))
        run(&r, steps: 1)
        #expect(r.line == [ids[0], ids[2]])
        #expect(try r.req(colonist: ids[1]).state == .lost)
    }

    @Test func husksAreFastHunters() throws {
        var r = quietRun()
        let husk = r.addEnemy(.husk, at: Vec2(800, 300))
        run(&r, steps: seconds(1))
        let speed = try r.req(enemy: husk).vel.length
        #expect(speed > r.tuning.skitterSpeed * 2.5)
        #expect(speed <= r.tuning.huskMaxSpeed + 1e-9)
        #expect(r.tuning.huskMaxSpeed < r.tuning.orbMaxSpeed)
    }

    @Test func touchingAnEnemyCostsALife() throws {
        for role in RedoubtRole.allCases {
            var r = quietRun()
            r.addEnemy(role, at: r.orb.pos + Vec2(r.tuning.orbRadius, 0))
            let events = run(&r, steps: 2)
            #expect(events.contains { $0.isOrbDestroyed }, "\(role)")
        }
    }
}
