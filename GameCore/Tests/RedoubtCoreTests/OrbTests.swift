import Foundation
import Testing
import GameCore
@testable import RedoubtCore

@Suite struct OrbTests {
    @Test func theOrbStartsAtTheCentreWithThreeLivesAndOneCharge() throws {
        let run = RedoubtRun(seed: 1)
        #expect(run.orb.pos == Vec2(450, 300))
        #expect(run.orb.lives == 3)
        #expect(run.orb.charges == 1)
        #expect(run.arenaSize == Vec2(900, 600))
        #expect(RedoubtRun.timeStep == 1.0 / 120)
    }

    @Test func movementIsDirectWithAShortGlide() throws {
        var r = quietRun()
        let max = r.tuning.orbMaxSpeed
        // Speeding up: most of the way there in a tenth of a second, all of it soon after.
        run(&r, steps: seconds(0.1), input: RedoubtInput(move: Vec2(1, 0)))
        #expect(r.orb.vel.x > max * 0.6)
        #expect(r.orb.vel.x < max * 0.99)
        run(&r, steps: seconds(0.3), input: RedoubtInput(move: Vec2(1, 0)))
        #expect(r.orb.vel.x > max * 0.98)
        #expect(r.orb.vel.x <= max)
        // Letting go: a short glide, not Ridgeline's long coast.
        let before = r.orb.pos.x
        run(&r, steps: seconds(0.25))
        #expect(r.orb.vel.length < max * 0.05)
        let glide = r.orb.pos.x - before
        #expect(glide > 5 && glide < 40)
    }

    @Test func aHalfPushedStickFliesAtHalfSpeed() throws {
        var r = quietRun()
        run(&r, steps: seconds(1), input: RedoubtInput(move: Vec2(0, 0.5)))
        #expect(abs(r.orb.vel.y - r.tuning.orbMaxSpeed * 0.5) < 1)
        // Past the rim it is capped at full speed, diagonals included.
        r.orb.pos = Vec2(100, 100)
        run(&r, steps: seconds(1), input: RedoubtInput(move: Vec2(1, 1)))
        #expect(abs(r.orb.vel.length - r.tuning.orbMaxSpeed) < 1)
    }

    @Test func theWallStopsTheOrb() throws {
        var r = quietRun()
        run(&r, steps: seconds(4), input: RedoubtInput(move: Vec2(-1, -1)))
        #expect(r.orb.pos == Vec2(r.tuning.orbRadius, r.tuning.orbRadius))
        #expect(r.orb.vel == .zero)
    }

    @Test func pushingTheAimStickFiresTenShotsASecondWithoutLimit() throws {
        var r = quietRun()
        let aim = RedoubtInput(aim: Vec2(0, 1))
        // The first shot leaves at once.
        #expect(r.step(aim).contains { $0.isOrbFired })
        var r2 = quietRun()
        // Twenty seconds of fire: no heat, no reload, an exact cadence.
        let events = run(&r2, steps: seconds(20), input: aim)
        #expect(count(events, "orbFired") == 200)
        #expect(r2.orb.isFiring)
    }

    @Test func aLightTouchOnTheAimStickDoesNotFire() throws {
        var r = quietRun()
        let events = run(&r, steps: seconds(1), input: RedoubtInput(aim: Vec2(0.2, 0)))
        #expect(count(events, "orbFired") == 0)
        #expect(!r.orb.isFiring)
        let firing = run(&r, steps: seconds(1), input: RedoubtInput(aim: Vec2(0.35, 0)))
        #expect(count(firing, "orbFired") == 10)
    }

    @Test func aimIsAnalogueAndIndependentOfMovement() throws {
        var r = quietRun()
        let angle = 2.2
        let input = RedoubtInput(move: Vec2(1, 0), aim: Vec2(cos(angle), sin(angle)))
        let events = run(&r, steps: seconds(0.5), input: input)
        #expect(abs(r.orb.heading - angle) < 1e-9)
        #expect(r.orb.vel.x > 200)
        for event in events {
            if case .orbFired(_, let heading) = event { #expect(abs(heading - angle) < 1e-9) }
        }
        // Shots fly where the stick points, not where the orb moves.
        for shot in r.shots {
            let dir = atan2(shot.vel.y, shot.vel.x)
            #expect(abs(dir - angle) < 1e-9)
            #expect(abs(shot.vel.length - r.tuning.shotSpeed) < 1e-6)
        }
        // Not aiming, it faces the way it moves.
        run(&r, steps: seconds(0.3), input: RedoubtInput(move: Vec2(0, -1)))
        #expect(abs(r.orb.heading + .pi / 2) < 0.05)
    }

    @Test func shotsStopAtTheWall() throws {
        var r = quietRun()
        run(&r, steps: 1, input: RedoubtInput(aim: Vec2(1, 0)))
        let shot = try #require(r.shots.first)
        // 440 units to the east wall at 900 a second.
        let events = run(&r, steps: seconds(0.6))
        #expect(r.shots.isEmpty)
        let end = try #require(events.compactMap { if case .shotEnded(shot.id, let at, .wall) = $0 { at } else { nil } }.first)
        #expect(end.x == 900)
        #expect(abs(end.y - 300) < 1e-9)
    }

    @Test func everyShotThatEndsSaysWhy() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        // Hit: a Skitter in the way.
        let target = r.addEnemy(.skitter, at: Vec2(560, 300))
        r.enemies[r.index(of: target)].trait = 0
        run(&r, steps: 1, input: RedoubtInput(aim: Vec2(1, 0)))
        let hitShot = try #require(r.shots.first).id
        var events = run(&r, steps: seconds(0.3))
        #expect(events.contains { if case .shotEnded(hitShot, _, .hit) = $0 { true } else { false } })
        // Expired: a shot whose time runs out mid-floor.
        let short = r.takeID()
        r.shots.append(RedoubtShot(id: short, owner: .orb, pos: Vec2(300, 300), vel: Vec2(0, 10), radius: 3, timeLeft: 0.05))
        events = run(&r, steps: seconds(0.2))
        #expect(events.contains { if case .shotEnded(short, _, .expired) = $0 { true } else { false } })
        // Cleared: an enemy shot caught by a Shockwave.
        let wiped = r.takeID()
        r.shots.append(RedoubtShot(id: wiped, owner: .enemy, pos: r.orb.pos + Vec2(0, 80), vel: Vec2(40, 0), radius: 5, timeLeft: 5))
        events = r.step(RedoubtInput(shockwave: true))
        #expect(events.contains { if case .shotEnded(wiped, _, .cleared) = $0 { true } else { false } })
        #expect(r.shots.isEmpty)
    }
}
