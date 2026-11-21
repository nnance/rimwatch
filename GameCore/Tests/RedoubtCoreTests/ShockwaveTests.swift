import Testing
import GameCore
@testable import RedoubtCore

@Suite struct ShockwaveTests {
    private let press = RedoubtInput(shockwave: true)

    @Test func itClearsEverythingNearTheOrb() throws {
        var r = quietRun()
        let skitter = r.addEnemy(.skitter, at: r.orb.pos + Vec2(100, 0))
        let thresher = r.addEnemy(.thresher, at: r.orb.pos + Vec2(0, 120))
        let burrow = r.addEnemy(.burrow, at: r.orb.pos + Vec2(-130, 0))
        r.shots.append(RedoubtShot(id: r.takeID(), owner: .enemy, pos: r.orb.pos + Vec2(0, -100), vel: Vec2(50, 0),
                                   radius: 5, timeLeft: 5))
        let events = r.step(press)
        #expect(events.contains(.shockwave(at: Vec2(450, 300), destroyed: 3)))
        for id in [skitter, thresher, burrow] {
            #expect(r.enemy(id) == nil)
            #expect(events.contains { if case .enemyDestroyed(id, _, _, _, true) = $0 { true } else { false } })
        }
        #expect(r.shots.isEmpty)
        #expect(r.orb.charges == 0)
        // Only a Shockwave destroys a Thresher, and it is worth the most.
        #expect(r.score == 50 + 1500 + 1000)
    }

    @Test func itPushesTheRestBack() throws {
        var r = quietRun()
        let near = r.addEnemy(.skitter, at: r.orb.pos + Vec2(200, 0))
        let far = r.addEnemy(.skitter, at: r.orb.pos + Vec2(-400, 0))
        let burrow = r.addEnemy(.burrow, at: r.orb.pos + Vec2(0, 220))
        r.enemies[r.index(of: burrow)].timer = 1e9
        _ = r.step(press)
        #expect(try r.req(enemy: near).push.x > 100)
        #expect(try r.req(enemy: far).push == .zero)
        #expect(try r.req(enemy: burrow).push == .zero)
        // Against the same Skitter left alone, it ends up well back.
        var calm = quietRun()
        let twin = calm.addEnemy(.skitter, at: calm.orb.pos + Vec2(200, 0))
        try calm.enemies[calm.index(of: twin)].trait = r.req(enemy: near).trait
        try calm.enemies[calm.index(of: twin)].timer = r.req(enemy: near).timer - RedoubtRun.timeStep
        run(&r, steps: seconds(0.5))
        run(&calm, steps: seconds(0.5) + 1)
        #expect(try distance(r.req(enemy: near).pos, r.orb.pos) > distance(calm.req(enemy: twin).pos, calm.orb.pos) + 60)
        #expect(try r.req(enemy: burrow).pos == r.orb.pos + Vec2(0, 220))
    }

    @Test func oneShockwavePerPressAndNoneWithoutACharge() throws {
        var r = quietRun()
        r.orb.charges = 2
        let held = run(&r, steps: seconds(1), input: press)
        #expect(count(held, "shockwave") == 1)
        run(&r, steps: 1)
        _ = r.step(press)
        #expect(r.orb.charges == 0)
        run(&r, steps: 1)
        let empty = run(&r, steps: 2, input: press)
        #expect(count(empty, "shockwave") == 0)
    }

    @Test func eachLifeStartsWithAtLeastOneCharge() throws {
        var r = quietRun()
        r.orb.charges = 0
        r.addEnemy(.skitter, at: r.orb.pos)
        run(&r, steps: seconds(2)) { if case .orbRespawned = $0 { true } else { false } }
        #expect(r.orb.charges == 1)
        // Charges in hand are kept.
        var kept = quietRun()
        kept.orb.charges = 3
        kept.addEnemy(.skitter, at: kept.orb.pos)
        run(&kept, steps: seconds(2)) { if case .orbRespawned = $0 { true } else { false } }
        #expect(kept.orb.charges == 3)
    }
}
