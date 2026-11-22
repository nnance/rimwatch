import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// A crowded gallery (more than the waves ever send at once) must step far inside the 8.3 ms
/// frame at 120 Hz. Tests build without optimisation, so the bound is loose; the harness reports
/// the release figure.
@Suite struct RiftwingPerformanceTests {
    private static func topUp(_ r: inout RiftwingRun, rng: inout SeededRNG) {
        let roles: [RiftwingRole] = [.glider, .striker, .warden, .sower, .striker, .gleaner]
        while r.opponents.count < 14 {
            let role = roles[Int(rng.next() % UInt64(roles.count))]
            r.addOpponent(role, at: Vec2(rng.range(0...899), rng.range(150...560)))
        }
        while r.pods.count(where: { $0.isUnsettled }) < 10 {
            r.dropPod(at: Vec2(rng.range(0...899), rng.range(200...560)), vel: .zero, from: .glider)
        }
        while r.mines.count < 12 {
            let anchor = Vec2(rng.range(0...899), rng.range(200...560))
            r.mines.append(RiftwingMine(id: r.takeID(), sower: 0, anchor: anchor, pos: anchor - Vec2(0, 34)))
        }
    }

    @Test func aCrowdedGalleryStepsWellInsideAFrame() throws {
        var r = quietRun(seed: 21)
        r.rider.invulnerableTimer = .infinity
        var rng = SeededRNG(seed: 5)
        let clock = ContinuousClock()
        var total = Duration.zero
        let steps = 1200
        for step in 0..<steps {
            Self.topUp(&r, rng: &rng)
            let start = clock.now
            _ = r.step(RiftwingInput(stick: Vec2(0.4, 0), flap: step % 14 < 7))
            total += clock.now - start
            if !r.rider.isAlive { r.rider.lives = 3 }
        }
        let micros = Double(total.components.attoseconds) / 1e12 / Double(steps)
            + Double(total.components.seconds) * 1e6 / Double(steps)
        print("RIFTWING PERF \(String(format: "%.1f", micros)) us per step with 14 opponents, 10 pods, 12 mines (this build)")
        #expect(micros < 2000)
    }
}
