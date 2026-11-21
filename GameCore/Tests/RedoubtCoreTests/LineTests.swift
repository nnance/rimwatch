import Testing
import GameCore
@testable import RedoubtCore

/// Colonists: picking them up, the line behind the orb, losing the tail, the airlock.
@Suite struct LineTests {
    @Test func touchingColonistsAddsThemToTheEndOfTheLineInOrder() throws {
        var r = quietRun()
        let a = r.addColonist(at: Vec2(500, 300))
        let b = r.addColonist(at: Vec2(560, 300))
        let c = r.addColonist(at: Vec2(620, 300))
        let events = run(&r, steps: seconds(1), input: RedoubtInput(move: Vec2(1, 0)))
        #expect(r.line == [a, b, c])
        let positions = events.compactMap { if case .colonistPickedUp(let id, _, let n) = $0 { [id, n] } else { nil } }
        #expect(positions == [[a, 1], [b, 2], [c, 3]])
        #expect(r.colonists.allSatisfy { $0.state == .following })
    }

    @Test func theLineFollowsTheOrbsPathAtAnEvenSpacing() throws {
        var r = quietRun()
        let ids = r.formLine(5)
        // Round a corner.
        run(&r, steps: seconds(0.8), input: RedoubtInput(move: Vec2(1, 0)))
        run(&r, steps: seconds(0.8), input: RedoubtInput(move: Vec2(0, 1)))
        var leader = r.orb.pos
        for id in ids {
            let pos = try r.req(colonist: id).pos
            #expect(distance(pos, leader) <= r.tuning.lineSpacing + 1e-6)
            #expect(distance(pos, leader) > r.tuning.lineSpacing - 1)
            leader = pos
        }
        // The first follower is on the orb's new heading, below it.
        let first = try r.req(colonist: ids[0]).pos
        #expect(abs(first.x - r.orb.pos.x) < 2)
        #expect(first.y < r.orb.pos.y)
    }

    @Test func aSkitterTakesTheLastFollowerOnly() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        let ids = r.formLine(4)
        // A Skitter on a middle follower does nothing to it.
        let middle = try r.req(colonist: ids[1]).pos
        let passer = r.addEnemy(.skitter, at: middle)
        run(&r, steps: 1)
        #expect(r.line == ids)
        r.enemies.removeAll { $0.id == passer }
        // On the tail, it takes them.
        let taker = try r.addEnemy(.skitter, at: r.req(colonist: ids[3]).pos)
        let events = run(&r, steps: 1)
        #expect(events.contains { if case .colonistTaken(ids[3], .skitter, taker, _) = $0 { true } else { false } })
        #expect(r.line == Array(ids.prefix(3)))
        #expect(try r.req(colonist: ids[3]).state == .lost)
    }

    @Test func aGleanerCanSnatchTheTailOfTheLine() throws {
        var r = quietRun()
        r.orb.invulnerableTimer = 1e9
        let ids = r.formLine(3)
        let gleaner = try r.addEnemy(.gleaner, at: r.req(colonist: ids[2]).pos - Vec2(30, 0))
        let events = run(&r, steps: seconds(1)) { if case .colonistSeized = $0 { true } else { false } }
        #expect(events.contains { if case .colonistSeized(ids[2], gleaner, _) = $0 { true } else { false } })
        #expect(r.line == [ids[0], ids[1]])
    }

    @Test func deliveringALineScoresMoreForEachColonistInIt() throws {
        var r = quietRun()
        let ids = r.formLine(5)
        r.orb.pos = Vec2(860, 300)
        let events = run(&r, steps: seconds(0.5), input: RedoubtInput(move: Vec2(1, 0)))
        let delivered = events.compactMap { if case .colonistDelivered(let id, _, let n, let points) = $0 { [id, n, points] } else { nil } }
        #expect(delivered == [[ids[0], 1, 500], [ids[1], 2, 1000], [ids[2], 3, 1500], [ids[3], 4, 2000], [ids[4], 5, 2500]])
        #expect(r.score == 7500)
        #expect(r.line.isEmpty)
        #expect(r.colonistsDelivered == 5)
        #expect(r.colonistsSaved == 5)
        #expect(r.colonists.allSatisfy { $0.state == .delivered })
    }

    @Test func aShutAirlockTakesNoDeliveries() throws {
        var r = quietRun()
        r.formLine(2)
        r.airlock.isOpen = false
        r.orb.pos = Vec2(880, 300)
        let events = run(&r, steps: seconds(0.5))
        #expect(!events.contains { $0.isColonistDelivered })
        #expect(r.line.count == 2)
    }

    @Test func everyFourthColonistDeliveredEarnsACharge() throws {
        var r = quietRun()
        r.orb.charges = 0
        r.formLine(3)
        r.orb.pos = Vec2(880, 300)
        var events = run(&r, steps: 1)
        #expect(count(events, "colonistDelivered") == 3)
        #expect(count(events, "chargeEarned") == 0)
        // The fourth of the run, in a later trip, earns one.
        r.orb.pos = Vec2(450, 300)
        r.formLine(6)
        r.orb.pos = Vec2(880, 300)
        events = run(&r, steps: 1)
        #expect(events.filter { $0.kind == "chargeEarned" } == [.chargeEarned(charges: 1), .chargeEarned(charges: 2)])
        #expect(r.orb.charges == 2)
    }

    @Test func chargesStopAtThree() throws {
        var r = quietRun()
        r.orb.charges = 3
        r.formLine(8)
        r.orb.pos = Vec2(880, 300)
        let events = run(&r, steps: 1)
        #expect(count(events, "colonistDelivered") == 8)
        #expect(count(events, "chargeEarned") == 0)
        #expect(r.orb.charges == 3)
    }

    @Test func losingTheOrbScattersTheLine() throws {
        var r = quietRun()
        let ids = r.formLine(4)
        let before = try ids.map { try r.req(colonist: $0).pos }
        r.addEnemy(.skitter, at: r.orb.pos + Vec2(5, 0))
        let events = run(&r, steps: seconds(0.6))
        #expect(events.contains(.lineScattered(count: 4)))
        #expect(r.line.isEmpty)
        for (id, start) in zip(ids, before) {
            #expect(try r.req(colonist: id).state == .sheltering)
            #expect(try distance(r.req(colonist: id).pos, start) > 10)
        }
        // They can be picked up again after the respawn.
        run(&r, steps: seconds(1))
        #expect(r.orb.isAlive)
    }
}
