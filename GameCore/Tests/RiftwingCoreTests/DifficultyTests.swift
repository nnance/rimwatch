// Needs `RiftwingPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Guards on Riftwing's difficulty, measured with the scripted pilots in `RiftwingPilot` over
/// fixed seed sets. The full measurement (the novice on three sets of 200 seeds, mean wave 5.3
/// to 5.9 with a median of 5 or 6) is `Tools/Harness` with the `riftwing` argument; these pin
/// the same targets on fewer seeds, with bounds about two standard errors wide.
@Suite struct RiftwingDifficultyTests {
    static func seeds(_ count: Int, from base: UInt64 = 1000) -> [UInt64] {
        (0..<count).map { base + UInt64($0) * 7919 }
    }

    struct Game {
        var survival = 0.0
        var wave = 0
        var score = 0
        var isOver = false
        var livesLost: [Int: Int] = [:]
        var lostTo: [String: Int] = [:]
        var dropped: [Int: Int] = [:]
        var lost: [Int: Int] = [:]
        var lostQuickly: [Int: Int] = [:]
        var waveLength: [Int: Double] = [:]
        var lieTimes: [Double] = []

        var scorePerMinute: Double { Double(score) / max(survival / 60, 0.01) }
    }

    static func play(_ skill: RiftwingPilot.Skill, seed: UInt64, maxSeconds: Double) -> Game {
        var r = RiftwingRun(seed: seed)
        var pilot = RiftwingPilot(skill: skill, seed: seed)
        var game = Game()
        var started = 0.0
        for _ in 0..<Int(maxSeconds * 120) {
            let before = r
            for event in r.step(pilot.input(for: before)) {
                let t = Double(r.tick) * RiftwingRun.timeStep
                switch event {
                case .waveStarted: started = t
                case .waveCleared(let w, _, _): game.waveLength[w] = t - started
                case .riderLost(_, _, let cause):
                    game.livesLost[r.wave, default: 0] += 1
                    let name: String = switch cause {
                    case .rift: "rift"
                    case .breath: "breath"
                    case .mine: "mine"
                    case .clash: "clash"
                    }
                    game.lostTo[name, default: 0] += 1
                case .podDropped: game.dropped[r.wave, default: 0] += 1
                case .podLost(let id, _, let cause):
                    game.lost[r.wave, default: 0] += 1
                    if cause != .rift, let pod = before.pod(id), pod.restedFor < 5 { game.lostQuickly[r.wave, default: 0] += 1 }
                    if cause == .hatched || cause == .carried, let pod = before.pod(id) { game.lieTimes.append(pod.restedFor) }
                case .podFreed(let id, _, _, _):
                    if let pod = before.pod(id) { game.lieTimes.append(pod.restedFor) }
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

    static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }

    /// The novice on the first 60 seeds of the harness's default set, shared by the tests
    /// below (computed once).
    static let novice: [Game] = seeds(60).map { play(.novice, seed: $0, maxSeconds: 1500) }

    @Test func anIdleRiderIsLostInTheFirstWaves() throws {
        let games = Self.seeds(12).map { Self.play(.idle, seed: $0, maxSeconds: 400) }
        #expect(games.allSatisfy { $0.isOver && $0.wave <= 2 }, "\(games.map(\.wave))")
        #expect(Self.median(games.map(\.survival)) <= 200)
    }

    /// The novice pilot stands in for a first-time player: a first game usually reaches wave 5
    /// or 6 (mean 5.5 to 5.65 on each of three sets of 200 seeds in the harness). These 60 seeds
    /// give about 5.3; the bounds are about two standard errors either side of the 600-game
    /// mean.
    @Test func aNoviceRunReachesAboutWaveFiveOrSix() throws {
        let waves = Self.novice.map { Double($0.wave) }
        let mean = Self.mean(waves)
        print("RIFTWING NOVICE mean wave \(mean), median \(Self.median(waves))")
        #expect((5.15...6.05).contains(mean), "\(waves)")
        #expect((5...6).contains(Self.median(waves)), "\(waves)")
        #expect(Self.novice.allSatisfy { $0.isOver && $0.wave >= 2 && $0.wave <= 10 }, "\(waves)")
    }

    /// It flies like a person: a real share of its lives go into the Rift, and pods lie a while
    /// before it reaches them.
    @Test func theNoviceFliesLikeAPerson() throws {
        let lost = Self.novice.reduce(into: [String: Int]()) { total, g in
            for (k, v) in g.lostTo { total[k, default: 0] += v }
        }
        let all = lost.values.reduce(0, +)
        let rift = Double(lost["rift"] ?? 0) / Double(max(all, 1))
        #expect((0.08...0.4).contains(rift), "\(lost)")
        #expect(Self.median(Self.novice.flatMap(\.lieTimes)) >= 2)
    }

    /// Gentle opening waves, then lives lost rise wave by wave with no cliff.
    @Test func noviceLivesLostRiseSteadilyFromGentleOpeningWaves() throws {
        let games = Self.novice
        func rate(_ w: Int) -> Double {
            let reached = games.filter { $0.wave >= w }
            return Double(reached.reduce(0) { $0 + ($1.livesLost[w] ?? 0) }) / Double(max(reached.count, 1))
        }
        let rates = (1...7).map(rate)
        print("RIFTWING NOVICE lives lost per wave \(rates)")
        // Waves 1 and 2 cost well under a life between them (about 0.6 over 600 games).
        #expect(rates[0] + rates[1] <= 0.9, "\(rates)")
        // Rising through the waves most games reach (here 40 or more of the 60): each of waves 3
        // to 5 costs at least nearly what the one before did, and none more than about twice.
        // Fewer games reach waves 6 and 7, so they are held only to costing more than waves 4
        // and 5 did (the harness shows them rising on 600 games).
        for w in 2..<5 {
            #expect(rates[w] >= rates[w - 1] - 0.1, "wave \(w + 1): \(rates)")
            #expect(rates[w] <= max(rates[w - 1], 0.4) * 2.2, "wave \(w + 1): \(rates)")
        }
        #expect(rates[5] > rates[3], "\(rates)")
        #expect(rates[6] > rates[4], "\(rates)")
    }

    /// Rescue starts gently: few pods lost in waves 1 and 2, none lost quickly, and losses grow
    /// in later waves.
    @Test func noviceRescueStartsGentlyAndRamps() throws {
        let games = Self.novice
        let dropped = games.reduce(0) { $0 + ($1.dropped[1] ?? 0) + ($1.dropped[2] ?? 0) }
        let lost = games.reduce(0) { $0 + ($1.lost[1] ?? 0) + ($1.lost[2] ?? 0) }
        let quick = games.reduce(0) { $0 + ($1.lostQuickly[1] ?? 0) + ($1.lostQuickly[2] ?? 0) }
        #expect(Double(lost) <= 0.1 * Double(dropped), "\(lost) of \(dropped) pods lost in waves 1 and 2")
        #expect(Double(quick) <= 0.05 * Double(games.count), "\(quick) lost within 5 s of landing")
        let laterDropped = games.reduce(0) { $0 + ($1.dropped[6] ?? 0) + ($1.dropped[7] ?? 0) }
        let laterLost = games.reduce(0) { $0 + ($1.lost[6] ?? 0) + ($1.lost[7] ?? 0) }
        #expect(Double(laterLost) / Double(max(laterDropped, 1)) > 2 * Double(lost) / Double(max(dropped, 1)))
    }

    @Test func aCompetentRunReachesTheLaterWaves() throws {
        let games = Self.seeds(12).map { Self.play(.competent, seed: $0, maxSeconds: 1500) }
        let waves = games.map { Double($0.wave) }
        #expect(Self.median(waves) >= 9, "\(waves)")
        #expect(games.filter { $0.wave < 6 }.count <= 2, "\(waves)")
        let early = games.reduce(0) { $0 + ($1.livesLost[1] ?? 0) + ($1.livesLost[2] ?? 0) }
        #expect(early <= games.count / 3)
        // Opening waves last long enough to be a fight and not so long they drag.
        for wave in 1...4 {
            let lengths = games.compactMap { $0.waveLength[wave] }
            #expect(!lengths.isEmpty)
            let mean = Self.mean(lengths)
            #expect((15...60).contains(mean), "wave \(wave) lasted \(mean) s")
        }
    }

    /// The novice's mean wave over 600 games in the harness (three sets of 200 seeds), the level
    /// the exploits are measured against. `aNoviceRunReachesAboutWaveFiveOrSix` keeps the novice
    /// there.
    static let noviceLevel = 5.59

    /// The exploits, tried by bots: sitting on the top ledge, hovering under the roof or under
    /// the highest ledge, riding one vent, hiding low, bouncing level without committing,
    /// camping the side seam, and hiding high to stoop on what passes below. None may reach a
    /// mean wave within one wave of the novice's, none may score more a minute than the novice,
    /// and none may survive without limit.
    @Test(arguments: [RiftwingPilot.Skill.topLedgeSitter, .roofHoverer, .underLedgeHoverer, .ventRider, .lowHider,
                      .levelBouncer, .seamCamper, .ambusher])
    func noExploitComesNearTheNovice(_ skill: RiftwingPilot.Skill) throws {
        let games = Self.seeds(40).map { Self.play(skill, seed: $0, maxSeconds: 1500) }
        let wave = Self.mean(games.map { Double($0.wave) })
        let noviceRate = Self.mean(Self.novice.map(\.scorePerMinute))
        let rate = Self.mean(games.map(\.scorePerMinute))
        print("RIFTWING EXPLOIT \(skill): wave \(wave) against \(Self.noviceLevel), score a minute \(rate) against \(noviceRate), longest \(games.map(\.survival).max() ?? 0) s")
        #expect(games.allSatisfy { $0.isOver }, "\(skill) lasted \(games.map { Int($0.survival) })")
        #expect(wave <= Self.noviceLevel - 1, "\(skill)")
        #expect(rate < noviceRate, "\(skill)")
    }
}
#endif
