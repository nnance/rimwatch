// Needs `RedoubtPilot`, which only exists in debug builds.
#if DEBUG
import Testing
import GameCore
@testable import RedoubtCore

/// The owner's central requirement: "a constant stream of firing and waves of enemies". With the
/// competent pilot clearing the floor as fast as it can, the floor is still rarely near empty
/// while a wave is on: the director keeps topping it up from the wave's quota, and only the last
/// few of a wave need hunting down.
@Suite struct RedoubtFeelTests {
    private static let seeds: [UInt64] = (0..<6).map { 1000 + UInt64($0) * 7919 }

    @Test func theFloorIsRarelyNearEmptyInTheOpeningWaves() {
        var steps = [Int](repeating: 0, count: 5)
        var sparse = [Int](repeating: 0, count: 5)
        var empty = [Int](repeating: 0, count: 5)
        var total = [Int](repeating: 0, count: 5)
        for seed in Self.seeds {
            var r = RedoubtRun(seed: seed)
            var pilot = RedoubtPilot(skill: .competent, seed: seed)
            while !r.isGameOver, r.wave <= 4, r.tick < 120 * 400 {
                _ = r.step(pilot.input(for: r))
                guard r.phase == .fighting, (1...4).contains(r.wave) else { continue }
                let shootable = r.enemies.count { $0.role.holdsWave }
                steps[r.wave] += 1
                total[r.wave] += shootable
                if shootable < 5 { sparse[r.wave] += 1 }
                if shootable == 0 { empty[r.wave] += 1 }
            }
        }
        for wave in 1...4 {
            #expect(steps[wave] > 0)
            let n = Double(max(steps[wave], 1))
            #expect(Double(sparse[wave]) / n < 0.15, "wave \(wave): fewer than 5 for \(Double(sparse[wave]) / n)")
            #expect(Double(empty[wave]) / n < 0.03, "wave \(wave): none for \(Double(empty[wave]) / n)")
            // A crowd, not a handful.
            #expect(Double(total[wave]) / n >= 10, "wave \(wave): mean \(Double(total[wave]) / n)")
            // Each opening wave lasts long enough to be a fight: at least 20 seconds on average.
            #expect(n / Double(Self.seeds.count) / 120 >= 20, "wave \(wave) lasted \(n / Double(Self.seeds.count) / 120) s")
        }
    }
}
#endif
