import Foundation
import Testing
import GameCore
@testable import RedoubtCore

/// The design's load: 120 enemies and 60 shots at once. The step must stay far inside the 8.3 ms
/// frame at 120 Hz. Tests build without optimisation, so the bound here is loose; the harness
/// reports the release figure.
@Suite struct RedoubtPerformanceTests {
    /// A floor at the target load, topped back up to it before every step.
    private static func loadedRun() -> RedoubtRun {
        var r = quietRun(seed: 21)
        r.orb.invulnerableTimer = .infinity
        r.orb.pos = Vec2(450, 300)
        return r
    }

    private static func topUp(_ r: inout RedoubtRun, rng: inout SeededRNG) {
        let roles: [RedoubtRole] = [.skitter, .skitter, .skitter, .skitter, .gleaner, .spitter, .husk, .thresher]
        while r.enemies.count < 120 {
            let role = roles[Int(rng.next() % UInt64(roles.count))]
            r.addEnemy(role, at: Vec2(rng.range(20...880), rng.range(20...580)))
        }
        while r.shots.count < 60 {
            let angle = rng.range(0...(2 * .pi))
            let enemy = r.shots.count % 3 == 0
            r.shots.append(RedoubtShot(id: r.takeID(), owner: enemy ? .enemy : .orb,
                                       pos: Vec2(rng.range(40...860), rng.range(40...560)),
                                       vel: Vec2(cos(angle), sin(angle)) * (enemy ? 165 : 900),
                                       radius: enemy ? 5 : 3, timeLeft: 1.2))
        }
    }

    @Test func aFullFloorStepsWellInsideAFrame() throws {
        var r = Self.loadedRun()
        var rng = SeededRNG(seed: 5)
        let clock = ContinuousClock()
        var total = Duration.zero
        let steps = 600
        for _ in 0..<steps {
            Self.topUp(&r, rng: &rng)
            let start = clock.now
            _ = r.step(RedoubtInput(move: Vec2(0.3, 0.2), aim: Vec2(1, 0.4)))
            total += clock.now - start
        }
        let micros = Double(total.components.attoseconds) / 1e12 / Double(steps)
            + Double(total.components.seconds) * 1e6 / Double(steps)
        print("REDOUBT PERF \(String(format: "%.1f", micros)) us per step at 120 enemies and 60 shots (this build)")
        // An unoptimised build is many times slower than the app's; even so, well under a frame.
        #expect(micros < 4000)
    }

    @Test func theGridFindsTheSameHitsAsCheckingEveryEnemy() throws {
        var r = Self.loadedRun()
        var rng = SeededRNG(seed: 9)
        Self.topUp(&r, rng: &rng)
        r.grid.rebuild(r.enemies)
        for enemy in r.enemies.indices {
            var found = false
            r.grid.forEach(near: r.enemies[enemy].pos, reach: 1) { if $0 == enemy { found = true } }
            #expect(found)
        }
        // Every index is filed exactly once.
        var seen: [Int] = []
        r.grid.forEach(minX: 0, minY: 0, maxX: 900, maxY: 600) { seen.append($0) }
        #expect(seen.sorted() == Array(r.enemies.indices))
    }
}
