// Needs `RedoubtPilot`, which only exists in debug builds.
#if DEBUG
import Testing
import GameCore
@testable import RedoubtCore

/// Coarse guards on Redoubt's first difficulty curve, measured with the scripted pilots in
/// `RedoubtPilot` over a fixed set of seeds. They pin the shape (an idle orb overrun in the first
/// wave, a novice run ending in the early waves, a competent run reaching waves 8 to 12 and
/// keeping its colonists early on), not exact numbers. The full measurement, over more seeds, is
/// `Tools/Harness` with the `redoubt` argument.
@Suite struct RedoubtDifficultyTests {
    private static let seeds: [UInt64] = (0..<12).map { 1000 + UInt64($0) * 7919 }

    private struct Run {
        var firstDeath: Double?
        var survival = 0.0
        var wave = 0
        var deathsByWave: [Int: Int] = [:]
        var colonistsByWave: [Int: Int] = [:]
        var savedByWave: [Int: Int] = [:]
    }

    private static func play(_ skill: RedoubtPilot.Skill, seed: UInt64, maxSeconds: Double) -> Run {
        var r = RedoubtRun(seed: seed)
        var pilot = RedoubtPilot(skill: skill, seed: seed)
        var result = Run()
        for _ in 0..<Int(maxSeconds * 120) {
            for event in r.step(pilot.input(for: r)) {
                switch event {
                case .orbDestroyed:
                    if result.firstDeath == nil { result.firstDeath = Double(r.tick) * RedoubtRun.timeStep }
                    result.deathsByWave[r.wave, default: 0] += 1
                case .waveStarted(let wave, let colonists):
                    result.colonistsByWave[wave] = colonists
                case .waveCleared(let wave, let safe, _):
                    result.savedByWave[wave, default: 0] += safe
                case .colonistDelivered:
                    result.savedByWave[r.wave, default: 0] += 1
                default:
                    break
                }
            }
            if r.isGameOver { break }
        }
        result.survival = Double(r.tick) * RedoubtRun.timeStep
        result.wave = r.wave
        return result
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    @Test func anIdleOrbIsOverrunInTheFirstWave() throws {
        let runs = Self.seeds.map { Self.play(.idle, seed: $0, maxSeconds: 60) }
        #expect(runs.allSatisfy { $0.wave == 1 })
        #expect(runs.allSatisfy { (10...25).contains($0.survival) })
        // The first Skitters take a few seconds to cross the floor.
        #expect(runs.allSatisfy { ($0.firstDeath ?? 99) >= 4 })
    }

    @Test func aNoviceRunEndsInTheEarlyWaves() throws {
        let runs = Self.seeds.map { Self.play(.novice, seed: $0, maxSeconds: 300) }
        let waves = runs.map { Double($0.wave) }
        #expect((3...5).contains(Self.median(waves)))
        #expect(runs.allSatisfy { $0.wave >= 2 && $0.wave <= 7 })
    }

    @Test func aCompetentRunReachesTheMiddleWavesAndSavesItsColonistsEarly() throws {
        let runs = Self.seeds.map { Self.play(.competent, seed: $0, maxSeconds: 900) }
        let waves = runs.map { Double($0.wave) }
        #expect((9...13).contains(Self.median(waves)), "\(waves)")
        #expect(runs.allSatisfy { $0.wave >= 7 })
        #expect(runs.filter { $0.wave >= 18 }.count <= 1)
        // Wave 1 is crowded but a careful player loses nothing in it.
        #expect(runs.allSatisfy { ($0.deathsByWave[1] ?? 0) == 0 })
        // Each role's debut is survivable: hardly any lives lost in debut waves.
        let debutDeaths = runs.reduce(0) { total, run in
            total + RedoubtWaves.debut.reduce(0) { $0 + (run.deathsByWave[$1.wave] ?? 0) }
        }
        #expect(debutDeaths <= runs.count / 3, "\(debutDeaths) lives lost in debut waves")
        // Most colonists of the first four waves are saved.
        let colonists = runs.reduce(0) { total, run in total + (1...4).reduce(0) { $0 + (run.colonistsByWave[$1] ?? 0) } }
        let saved = runs.reduce(0) { total, run in total + (1...4).reduce(0) { $0 + (run.savedByWave[$1] ?? 0) } }
        #expect(Double(saved) >= 0.85 * Double(colonists), "\(saved) of \(colonists)")
    }
}
#endif
