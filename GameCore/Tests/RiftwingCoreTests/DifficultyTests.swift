// Needs `RiftwingPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Guards on Riftwing's difficulty, measured with the scripted pilots in `RiftwingPilot` over
/// fixed seed sets. The full measurement (the novice on three sets of 200 seeds, mean wave 5.3
/// to 5.9 with a median of 5 or 6) is `Tools/Harness` with the `riftwing` argument; these pin
/// the same targets on fewer seeds. Where a bound is wider than the target, it is because the
/// number is noise on this many games, and the bound says how wide the noise is. The games of
/// a set are played in parallel, so the larger sets cost little time.
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
        /// Lives lost to clashes, by wave; the wave of each life lost to the Rift.
        var clashLosses: [Int: Int] = [:]
        var riftLosses: [Int] = []

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
                    if name == "clash" { game.clashLosses[r.wave, default: 0] += 1 }
                    if name == "rift" { game.riftLosses.append(r.wave) }
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

    /// Plays `skill` on every seed in parallel, in seed order.
    static func playAll(_ skill: RiftwingPilot.Skill, seeds: [UInt64], maxSeconds: Double) -> [Game] {
        final class Results: @unchecked Sendable {
            var games: [Game]
            let lock = NSLock()
            init(_ count: Int) { games = Array(repeating: Game(), count: count) }
        }
        let results = Results(seeds.count)
        DispatchQueue.concurrentPerform(iterations: seeds.count) { i in
            let game = play(skill, seed: seeds[i], maxSeconds: maxSeconds)
            results.lock.lock()
            results.games[i] = game
            results.lock.unlock()
        }
        return results.games
    }

    /// The novice on the first 120 seeds of the harness's default set, shared by the tests
    /// below (computed once).
    static let novice: [Game] = playAll(.novice, seeds: seeds(120), maxSeconds: 1500)

    /// The novice's mean wave on that set: the level the exploits and the resting novice are
    /// measured against (measured here, not a constant, so it follows the game).
    static var noviceLevel: Double { mean(novice.map { Double($0.wave) }) }

    /// A rider who never touches the controls is not beaten for standing on its ledge in the
    /// first wave; it is lost there in the end to the Rift's breath (and to being bounced off its
    /// ledge into the Rift), about three minutes in.
    @Test func anIdleRiderIsLostInTheFirstWavesButNotForStanding() throws {
        let games = Self.playAll(.idle, seeds: Self.seeds(24), maxSeconds: 600)
        #expect(games.allSatisfy { $0.isOver && $0.wave <= 2 }, "\(games.map(\.wave))")
        let survival = Self.median(games.map(\.survival))
        #expect((120...300).contains(survival), "\(survival)")
        // Clash losses in wave 1 come only after a bounce has thrown it off its ledge.
        let clashes = games.reduce(0) { $0 + ($1.clashLosses[1] ?? 0) }
        #expect(Double(clashes) <= 0.1 * Double(games.count), "\(clashes) clash losses in wave 1")
    }

    /// The novice pilot stands in for a first-time player: a first game usually reaches wave 5
    /// or 6 (mean 5.3 to 5.9 on each of three sets of 200 seeds in the harness). The mean of 120
    /// games has a standard error of about 0.15, so this set is held to the 600-game mean
    /// (about 5.5) give or take three of those; its median to 5 or 6.
    @Test func aNoviceRunReachesAboutWaveFiveOrSix() throws {
        let waves = Self.novice.map { Double($0.wave) }
        let mean = Self.mean(waves)
        print("RIFTWING NOVICE mean wave \(mean), median \(Self.median(waves))")
        #expect((5.05...6.0).contains(mean), "\(waves)")
        #expect((5...6).contains(Self.median(waves)), "\(waves)")
        #expect(Self.novice.allSatisfy { $0.isOver && $0.wave <= 10 }, "\(waves)")
        // Hardly any first game ends in the first wave (about one in two hundred over 600).
        #expect(Self.novice.count { $0.wave <= 1 } <= 2, "\(waves)")
    }

    /// It flies like a person: some of its lives go into the Rift (only a few, nearly all in the
    /// first wave, now that a lapse never stops the tap that saves it once it has learned), and
    /// pods lie a while before it reaches them.
    @Test func theNoviceFliesLikeAPerson() throws {
        let lost = Self.novice.reduce(into: [String: Int]()) { total, g in
            for (k, v) in g.lostTo { total[k, default: 0] += v }
        }
        let all = lost.values.reduce(0, +)
        let rift = Double(lost["rift"] ?? 0) / Double(max(all, 1))
        print("RIFTWING NOVICE lives lost to \(lost)")
        #expect((0.01...0.3).contains(rift), "\(lost)")
        #expect(Self.median(Self.novice.flatMap(\.lieTimes)) >= 2)
    }

    /// Once past the first wave the novice no longer lets a lapse of attention drop it into the
    /// Rift (a person stops doing that within a minute): it loses hardly any lives to the Rift
    /// in waves 2 to 5 (it lost about 0.18 a wave there before).
    @Test func theNoviceStopsLapsingIntoTheRiftAfterTheFirstWave() throws {
        var rift = 0, waves = 0
        for w in 2...5 {
            waves += Self.novice.count { $0.wave >= w }
        }
        for g in Self.novice { rift += g.riftLosses.filter { (2...5).contains($0) }.count }
        let rate = Double(rift) / Double(max(waves, 1))
        print("RIFTWING NOVICE rift losses a wave in waves 2 to 5: \(rate)")
        #expect(rate <= 0.06, "\(rift) in \(waves) waves")
    }

    /// The novice keeps clear of mines once it has had time to see them: flying about for twelve
    /// minutes among eight mines it touches 12 (36 when it ignored them; it is still sloppy).
    @Test func theNoviceKeepsClearOfMinesItHasSeen() throws {
        var tuning = RiftwingTuning()
        tuning.mineLifetime = 10_000
        var hits = 0
        for seed: UInt64 in 1...12 {
            var r = quietRun(seed: seed, tuning: tuning)
            r.placeRider(at: Vec2(450, 330))
            for (i, anchor) in [Vec2(120, 360), Vec2(260, 300), Vec2(330, 440), Vec2(520, 380), Vec2(610, 300),
                                Vec2(700, 440), Vec2(800, 340), Vec2(40, 450)].enumerated() {
                let pos = r.minePosition(anchor: anchor, phase: Double(i), age: 0)
                r.mines.append(RiftwingMine(id: 900 + i, sower: 0, anchor: anchor, pos: pos, age: 0, phase: Double(i)))
            }
            var pilot = RiftwingPilot(skill: .novice, seed: seed)
            for _ in 0..<seconds(60) {
                for event in r.step(pilot.input(for: r)) {
                    if case .riderLost(_, _, .mine) = event { hits += 1 }
                }
                if r.isGameOver { break }
            }
        }
        print("RIFTWING NOVICE mine hits \(hits) in 12 minutes among mines")
        #expect(hits <= 18, "\(hits)")
    }

    /// Lives lost per wave: gentle opening waves, then a steady rise with no cliff.
    @Test func noviceLivesLostRiseSteadilyFromGentleOpeningWaves() throws {
        let games = Self.novice
        func rate(_ waves: [Int]) -> Double {
            let lost = waves.reduce(0) { total, w in total + games.reduce(0) { $0 + ($1.livesLost[w] ?? 0) } }
            let reached = waves.reduce(0) { total, w in total + games.count { $0.wave >= w } }
            return Double(lost) / Double(max(reached, 1))
        }
        let rates = (1...7).map { rate([$0]) }
        print("RIFTWING NOVICE lives lost per wave \(rates)")
        // Waves 1 and 2 cost well under a life between them (about 0.5 over 600 games).
        #expect(rates[0] + rates[1] <= 0.75, "\(rates)")
        // Rising through the waves most games reach: each of waves 3 to 5 costs at least nearly
        // what the one before did, and none more than about twice (from a floor of 0.4, since
        // waves 1 and 2 are kept nearly free).
        for w in 2..<5 {
            #expect(rates[w] >= rates[w - 1] - 0.15, "wave \(w + 1): \(rates)")
            #expect(rates[w] <= max(rates[w - 1], 0.4) * 2.2, "wave \(w + 1): \(rates)")
        }
        // Fewer games reach waves 6 and 7, so they are taken together, against waves 4 and 5
        // together: the later pair costs clearly more.
        #expect(rate([6, 7]) > rate([4, 5]) + 0.15, "\(rate([6, 7])) against \(rate([4, 5]))")
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
        let games = Self.playAll(.competent, seeds: Self.seeds(12), maxSeconds: 1500)
        let waves = games.map { Double($0.wave) }
        print("RIFTWING COMPETENT waves \(waves)")
        #expect((8...15).contains(Self.median(waves)), "\(waves)")
        #expect(games.filter { $0.wave < 6 }.count <= 2, "\(waves)")
        let early = games.reduce(0) { $0 + ($1.livesLost[1] ?? 0) + ($1.livesLost[2] ?? 0) }
        #expect(early <= games.count / 3)
        // Opening waves last long enough to be a fight and not so long they drag.
        for wave in 1...4 {
            let lengths = games.compactMap { $0.waveLength[wave] }
            #expect(!lengths.isEmpty)
            let mean = Self.mean(lengths)
            #expect((15...50).contains(mean), "wave \(wave) lasted \(mean) s")
        }
    }

    /// The bots that exploit the top ledge reach it in every layout: they route round the
    /// ledges in the way instead of climbing into an underside and hovering there.
    @Test(arguments: [RiftwingPilot.Skill.topLedgeSitter, .ambusher, .topLedgeStill, .topLedgePacer, .pacingAmbusher])
    func theTopLedgeBotsReachTheTopLedge(_ skill: RiftwingPilot.Skill) throws {
        for layout in RiftwingCavern.layouts.indices {
            var r = quietRun()
            r.applyLayout(layout)
            let start = r.layout.startLedge
            r.rider.body.pos = RiftwingRun.standingPoint(on: r.ledges[start], radius: r.rider.body.radius, tuning: r.tuning)
            r.rider.body.ledge = start
            let top = r.ledges.indices.max { r.ledges[$0].top < r.ledges[$1].top }!
            var pilot = RiftwingPilot(skill: skill, seed: 5)
            var reached = false
            for _ in 0..<seconds(15) {
                _ = r.step(pilot.input(for: r))
                if r.rider.body.ledge == top {
                    reached = true
                    break
                }
            }
            #expect(reached, "\(skill) in \(r.layout.name): at \(r.rider.pos)")
        }
    }

    /// The exploits, tried by bots: sitting, standing still or pacing on the top ledge, hovering
    /// under the roof or under the highest ledge, riding one vent, hiding low, bouncing level
    /// without committing, camping the side seam, and hiding high (still or pacing) to stoop on
    /// what passes below. None may reach a mean wave within one wave of the novice's (measured
    /// above), none may score more a minute than the novice, and none may survive without
    /// limit.
    @Test(arguments: [RiftwingPilot.Skill.topLedgeSitter, .topLedgeStill, .topLedgePacer, .roofHoverer, .underLedgeHoverer,
                      .ventRider, .lowHider, .levelBouncer, .seamCamper, .ambusher, .pacingAmbusher])
    func noExploitComesNearTheNovice(_ skill: RiftwingPilot.Skill) throws {
        let games = Self.playAll(skill, seeds: Self.seeds(30), maxSeconds: 1500)
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
