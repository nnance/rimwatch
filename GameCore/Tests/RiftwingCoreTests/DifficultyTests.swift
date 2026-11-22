// Needs `RiftwingPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Coarse guards on Riftwing's first difficulty curve, measured with the scripted pilots in
/// `RiftwingPilot` over a fixed set of seeds. They pin the shape (an idle rider lost in the
/// first waves, a novice run reaching about wave 5 or 6 with gentle opening waves, a competent
/// run reaching the low teens, every exploit doing worse than playing properly), not exact
/// numbers. The full measurement, over 600 novice games, is `Tools/Harness` with the
/// `riftwing` argument.
@Suite struct RiftwingDifficultyTests {
    private static let seeds: [UInt64] = (0..<12).map { 1000 + UInt64($0) * 7919 }

    struct Game {
        var survival = 0.0
        var wave = 0
        var score = 0
        var isOver = false
        var livesLost: [Int: Int] = [:]
        var dropped: [Int: Int] = [:]
        var lost: [Int: Int] = [:]
        var waveLength: [Int: Double] = [:]

        var scorePerMinute: Double { Double(score) / max(survival / 60, 0.01) }
    }

    static func play(_ skill: RiftwingPilot.Skill, seed: UInt64, maxSeconds: Double) -> Game {
        var r = RiftwingRun(seed: seed)
        var pilot = RiftwingPilot(skill: skill, seed: seed)
        var game = Game()
        var started = 0.0
        for _ in 0..<Int(maxSeconds * 120) {
            for event in r.step(pilot.input(for: r)) {
                let t = Double(r.tick) * RiftwingRun.timeStep
                switch event {
                case .waveStarted: started = t
                case .waveCleared(let w, _, _): game.waveLength[w] = t - started
                case .riderLost: game.livesLost[r.wave, default: 0] += 1
                case .podDropped: game.dropped[r.wave, default: 0] += 1
                case .podLost: game.lost[r.wave, default: 0] += 1
                default: break
                }
            }
            if r.isGameOver { break }
        }
        game.survival = Double(r.tick) * RiftwingRun.timeStep
        game.wave = r.wave
        game.score = r.score
        game.isOver = r.isGameOver
        return game
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    @Test func anIdleRiderIsLostInTheFirstWaves() throws {
        let games = Self.seeds.map { Self.play(.idle, seed: $0, maxSeconds: 400) }
        #expect(games.allSatisfy { $0.isOver && $0.wave <= 2 }, "\(games.map(\.wave))")
        #expect(Self.median(games.map(\.survival)) <= 200)
    }

    /// The novice pilot stands in for a first-time player: it should usually reach wave 5 or 6
    /// (mean 5.3 to 5.9 over 600 games in the harness), with gentle opening waves.
    @Test func aNoviceRunReachesAboutWaveFiveOrSix() throws {
        let games = Self.seeds.map { Self.play(.novice, seed: $0, maxSeconds: 600) }
        let waves = games.map { Double($0.wave) }
        #expect((4...7).contains(Self.median(waves)), "\(waves)")
        #expect(games.allSatisfy { $0.wave >= 2 && $0.wave <= 10 }, "\(waves)")
        // Waves 1 and 2 cost well under a life between them (about 0.35 over 600 games).
        let early = games.reduce(0) { $0 + ($1.livesLost[1] ?? 0) + ($1.livesLost[2] ?? 0) }
        #expect(Double(early) / Double(games.count) <= 0.75, "\(early) lives lost in waves 1 and 2")
        // Few of their pods are lost (about 8% over 600 games).
        let dropped = games.reduce(0) { $0 + ($1.dropped[1] ?? 0) + ($1.dropped[2] ?? 0) }
        let lost = games.reduce(0) { $0 + ($1.lost[1] ?? 0) + ($1.lost[2] ?? 0) }
        #expect(Double(lost) <= 0.18 * Double(dropped), "\(lost) of \(dropped) pods lost in waves 1 and 2")
        // Lives lost rise from the opening waves to the middle ones: no early cliff.
        func rate(_ w: Int) -> Double {
            let reached = games.filter { $0.wave >= w }
            return Double(reached.reduce(0) { $0 + ($1.livesLost[w] ?? 0) }) / Double(max(reached.count, 1))
        }
        #expect(rate(1) < rate(4), "\(rate(1)) then \(rate(4))")
    }

    @Test func aCompetentRunReachesTheLaterWavesAndItsWavesAreAFight() throws {
        let games = Self.seeds.map { Self.play(.competent, seed: $0, maxSeconds: 1200) }
        let waves = games.map { Double($0.wave) }
        #expect((8...15).contains(Self.median(waves)), "\(waves)")
        #expect(games.filter { $0.wave < 6 }.count <= 2, "\(waves)")
        // Hardly a life lost in the first two waves.
        let early = games.reduce(0) { $0 + ($1.livesLost[1] ?? 0) + ($1.livesLost[2] ?? 0) }
        #expect(early <= games.count / 3)
        // Opening waves last long enough to be a fight and not so long they drag: 15 to 50 s.
        for wave in 1...4 {
            let lengths = games.compactMap { $0.waveLength[wave] }
            #expect(!lengths.isEmpty)
            let mean = lengths.reduce(0, +) / Double(lengths.count)
            #expect((15...50).contains(mean), "wave \(wave) lasted \(mean) s")
        }
    }

    /// The exploits the design named, tried by bots: sitting on the top ledge, hovering under
    /// the roof, riding one vent, hiding on a low ledge, bouncing level without committing. None
    /// may outlast or outscore playing properly. The Rift's breath, rising higher with each
    /// breath of a wave that drags on, is what ends the stalls.
    @Test func noExploitOutlastsOrOutscoresProperPlay() throws {
        let seeds = Array(Self.seeds.prefix(8))
        let proper = seeds.map { Self.play(.competent, seed: $0, maxSeconds: 1200) }
        let properSurvival = Self.median(proper.map(\.survival))
        let properRate = Self.median(proper.map(\.scorePerMinute))
        let properWave = Self.median(proper.map { Double($0.wave) })
        for skill in [RiftwingPilot.Skill.topLedgeSitter, .roofHoverer, .ventRider, .lowHider, .levelBouncer] {
            let games = seeds.map { Self.play(skill, seed: $0, maxSeconds: 1200) }
            print("RIFTWING EXPLOIT \(skill): survival \(Self.median(games.map(\.survival))) against \(properSurvival), score a minute \(Self.median(games.map(\.scorePerMinute))) against \(properRate), wave \(Self.median(games.map { Double($0.wave) })) against \(properWave)")
            #expect(games.allSatisfy { $0.isOver }, "\(skill) lasted \(games.map { Int($0.survival) })")
            #expect(Self.median(games.map(\.survival)) < properSurvival, "\(skill)")
            #expect(Self.median(games.map(\.scorePerMinute)) < properRate * 0.6, "\(skill)")
            #expect(Self.median(games.map { Double($0.wave) }) < properWave, "\(skill)")
        }
    }
}
#endif
