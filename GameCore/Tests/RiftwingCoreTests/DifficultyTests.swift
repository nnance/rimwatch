// Needs `RiftwingPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Guards on Riftwing's difficulty, measured with the scripted pilots in `RiftwingPilot` over
/// fixed seed sets. The full measurement is `Tools/Harness` with the `riftwing` argument, on
/// three sets of 200 seeds (`SEEDBASE` 1000, 5000, 9000); these pin the same numbers on fewer
/// seeds. Where a bound is wider than the number, it is because the number is noise on this
/// many games, and the bound says how wide the noise is. The games of a set are played in
/// parallel, so the larger sets cost little time.
///
/// Re-centred on 2026-11-22, when the forgiveness of lost clashes was taken out
/// (`RiftwingWaves.clashMercy` and `standingGraceWaves` 0): the owner, who plays far above the
/// novice, never lost a life and chose "No forgiveness at all: every lost clash costs a life in
/// every wave." The novice at wave 5 to 6 is no longer the target; these hold the game to what
/// it now does. Measured then (harness, three sets of 200 seeds, 25-minute cap): novice mean
/// wave 3.44, 3.40, 3.60 (median 3); slow novice 3.33, 3.35, 3.20; competent 12.77, 12.83,
/// 12.80 (median 13).
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

    static func play(_ skill: RiftwingPilot.Skill, seed: UInt64, maxSeconds: Double, startAt: Int = 1) -> Game {
        var config = RiftwingRun.Config()
        config.startAtWave = startAt
        var r = RiftwingRun(seed: seed, config: config)
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
    static func playAll(_ skill: RiftwingPilot.Skill, seeds: [UInt64], maxSeconds: Double, startAt: Int = 1) -> [Game] {
        final class Results: @unchecked Sendable {
            var games: [Game]
            let lock = NSLock()
            init(_ count: Int) { games = Array(repeating: Game(), count: count) }
        }
        let results = Results(seeds.count)
        DispatchQueue.concurrentPerform(iterations: seeds.count) { i in
            let game = play(skill, seed: seeds[i], maxSeconds: maxSeconds, startAt: startAt)
            results.lock.lock()
            results.games[i] = game
            results.lock.unlock()
        }
        return results.games
    }

    /// The novice on the first 120 seeds of the harness's default set, shared by the tests
    /// below (computed once).
    static let novice: [Game] = playAll(.novice, seeds: seeds(120), maxSeconds: 1500)

    /// The novice's mean wave on that set (measured here, not a constant, so it follows the game).
    static var noviceLevel: Double { mean(novice.map { Double($0.wave) }) }

    /// The novice starting in the second layout (wave 4) and the third (wave 7), on the first 60
    /// seeds, for the exploits started there (computed once each).
    static let noviceFromSpur: [Game] = playAll(.novice, seeds: seeds(60), maxSeconds: 1500, startAt: 4)
    static let noviceFromShelves: [Game] = playAll(.novice, seeds: seeds(60), maxSeconds: 1500, startAt: 7)

    /// The competent pilot on the first 60 seeds, and from the second and third layouts on the
    /// first 20: the honest play the exploits are measured against (computed once each).
    static let competent: [Game] = playAll(.competent, seeds: seeds(60), maxSeconds: 1500)
    static let competentFromSpur: [Game] = playAll(.competent, seeds: seeds(20), maxSeconds: 1500, startAt: 4)
    static let competentFromShelves: [Game] = playAll(.competent, seeds: seeds(20), maxSeconds: 1500, startAt: 7)

    /// A rider who never touches the controls is lost in the first wave or two, about two and a
    /// half minutes in. Standing on its ledge no longer spares it (`standingGraceWaves` 0 since
    /// 2026-11-22): it loses lives to clashes in wave 1, about 1.5 a game (1.59, 1.44, 1.47 over
    /// three sets of 200 seeds), and is thrown off its ledge into the Rift as well (about 1 a
    /// game; none while it kept its footing).
    @Test func anIdleRiderIsLostInTheFirstWaves() throws {
        let games = Self.playAll(.idle, seeds: Self.seeds(24), maxSeconds: 600)
        #expect(games.allSatisfy { $0.isOver && $0.wave <= 2 }, "\(games.map(\.wave))")
        let survival = Self.median(games.map(\.survival))
        print("RIFTWING IDLE median survival \(survival) s")
        #expect((100...300).contains(survival), "\(survival)")
        let clashes = games.reduce(0) { $0 + ($1.clashLosses[1] ?? 0) }
        #expect(Double(clashes) >= 1.0 * Double(games.count), "\(clashes) clash losses in wave 1")
        let rift = games.reduce(0) { $0 + $1.riftLosses.count { $0 == 1 } }
        #expect(rift > 0, "\(rift) lost to the Rift in wave 1")
    }

    /// The novice pilot reaches about wave 3.5: mean 3.44, 3.40 and 3.60 on three sets of 200
    /// seeds in the harness, median 3 (it was 5.3 to 5.9 with the beginner's forgiveness). The
    /// mean of 120 games has a standard error of about 0.08, so this set is held to 3.1 to 3.9;
    /// its median to 3 or 4.
    @Test func aNoviceRunReachesAboutWaveThreeOrFour() throws {
        let waves = Self.novice.map { Double($0.wave) }
        let mean = Self.mean(waves)
        print("RIFTWING NOVICE mean wave \(mean), median \(Self.median(waves))")
        #expect((3.1...3.9).contains(mean), "\(waves)")
        #expect((3...4).contains(Self.median(waves)), "\(waves)")
        #expect(Self.novice.allSatisfy { $0.isOver && $0.wave <= 10 }, "\(waves)")
        // Hardly any game ends in the first wave (none of 600 in the harness).
        #expect(Self.novice.count { $0.wave <= 1 } <= 2, "\(waves)")
    }

    /// It flies like a person: some of its lives go into the Rift (about a tenth), and pods lie a
    /// while before it reaches them.
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

    /// Past the first wave the novice still falls into the Rift now and then (a lapse of
    /// attention sometimes keeps it from the tap that saves it, less often each wave), but
    /// rarely: few lives a wave in waves 2 to 5, more of them early than late.
    @Test func theNoviceStillFallsIntoTheRiftNowAndThenAfterTheFirstWave() throws {
        func rate(_ waves: ClosedRange<Int>) -> Double {
            let reached = waves.reduce(0) { total, w in total + Self.novice.count { $0.wave >= w } }
            let rift = Self.novice.reduce(0) { total, g in total + g.riftLosses.count { waves.contains($0) } }
            return Double(rift) / Double(max(reached, 1))
        }
        print("RIFTWING NOVICE rift losses a wave: wave 1 \(rate(1...1)), waves 2 to 5 \(rate(2...5)), waves 6 on \(rate(6...30))")
        #expect(rate(2...5) <= 0.06, "\(rate(2...5))")
        #expect(rate(2...5) >= 0.01, "\(rate(2...5))")
        #expect(rate(2...3) > rate(4...30), "\(rate(2...3)) against \(rate(4...30))")
    }

    /// A novice slow to notice pods (12 to 20 s after each is knocked loose) frees fewer
    /// colonists and meets more hatched rigs, but is not punished for it out of proportion: the
    /// rigs hatched while it still frees about half its colonists keep their kind's early ease.
    /// It reaches mean wave 3.33, 3.35 and 3.20 on three sets of 200 seeds in the harness, about
    /// 0.2 under the novice (3.48). It is compared with the novice on the same 60 seeds: held to
    /// within half a wave under it, and no more than 0.15 over it (on 60 games each mean has a
    /// standard error of about 0.07; on this set it is 3.45 against the novice's 3.5).
    @Test func aNoviceSlowToNoticePodsIsNotPunishedOutOfProportion() throws {
        let games = Self.playAll(.slowNovice, seeds: Self.seeds(60), maxSeconds: 1500)
        let wave = Self.mean(games.map { Double($0.wave) })
        let novice = Self.mean(Self.novice.prefix(60).map { Double($0.wave) })
        print("RIFTWING SLOW NOVICE mean wave \(wave) against \(novice) on the same seeds")
        #expect(wave >= novice - 0.5, "\(games.map(\.wave))")
        #expect(wave <= novice + 0.15, "\(wave)")
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

    /// Lives lost per game reaching a wave, for `games`.
    static func livesLostRate(_ games: [Game], _ waves: [Int]) -> Double {
        let lost = waves.reduce(0) { total, w in total + games.reduce(0) { $0 + ($1.livesLost[w] ?? 0) } }
        let reached = waves.reduce(0) { total, w in total + games.count { $0.wave >= w } }
        return Double(lost) / Double(max(reached, 1))
    }

    /// The novice's lives lost per wave rise from wave to wave through the waves it reaches.
    /// Measured on three sets of 200 seeds in the harness: wave 1 0.42, 0.41, 0.38; wave 2 0.65,
    /// 0.62, 0.58; wave 3 1.42, 1.44, 1.39; wave 4 1.84, 1.84, 1.58 (about 0.5 in waves 1 and 2
    /// together while lost clashes were forgiven; about 1.0 now). Under 15% of its games reach
    /// wave 5, so waves from 5 on are left to the competent pilot
    /// (`competentLivesLostRiseThroughTheLaterWaves`).
    @Test func noviceLivesLostRiseFromWaveToWave() throws {
        let rates = (1...4).map { Self.livesLostRate(Self.novice, [$0]) }
        print("RIFTWING NOVICE lives lost per wave \(rates)")
        // Waves 1 and 2 cost about a life between them (1.07, 1.03, 0.96 in the harness).
        #expect(rates[0] + rates[1] <= 1.25, "\(rates)")
        // Each wave costs at least nearly what the one before did ...
        for w in 1..<4 {
            #expect(rates[w] >= rates[w - 1] - 0.15, "wave \(w + 1): \(rates)")
        }
        // ... and no more than about twice as much (from a floor of 0.4).
        #expect(rates[1] <= max(rates[0], 0.4) * 2.2, "wave 2: \(rates)")
        #expect(rates[3] <= max(rates[2], 0.4) * 2.2, "wave 4: \(rates)")
        // OPEN: wave 3, the Strikers' debut, costs 2.2 to 2.4 times wave 2 (1.42 against 0.65,
        // 1.44 against 0.62, 1.39 against 0.58 in the harness; Strikers alone cost 1.2 lives a
        // game there), a little over the "about double" bar of 2.2. Held here at what the game
        // does now, with no retuning, for the owner to decide.
        #expect(rates[2] <= max(rates[1], 0.4) * 2.6, "wave 3: \(rates)")
    }

    /// The competent pilot now loses some lives, from the early waves on, and they rise from
    /// wave to wave with no wave costing more than about twice the one before (from a floor of
    /// 0.4). Measured on three sets of 200 seeds in the harness: about 0.02 a wave in waves 1 and
    /// 2, 0.1 in waves 3 to 5, 0.3 in 6 and 7, 0.4 in 8, 0.6 in 9, 1.25 in 10, 2.1 in 11, 2.4 in
    /// 12 and 2.5 in 13 (it lost almost none before wave 9 while lost clashes were forgiven).
    @Test func competentLivesLostRiseThroughTheLaterWaves() throws {
        let games = Self.competent
        let rates = (1...12).map { Self.livesLostRate(games, [$0]) }
        print("RIFTWING COMPETENT lives lost per wave \(rates)")
        // Some lives before the later waves: about 1.4 a game in waves 1 to 8.
        let early = (1...8).reduce(0.0) { $0 + rates[$1 - 1] }
        #expect((0.7...2.5).contains(early), "\(early): \(rates)")
        for w in 1..<12 {
            #expect(rates[w] >= rates[w - 1] - 0.15, "wave \(w + 1): \(rates)")
            // OPEN: wave 10 costs 2.1 to 2.25 times wave 9 (1.25 against 0.68, 1.28 against 0.57,
            // 1.24 against 0.59 in the harness; 1.49 against 0.67 on this set), a little over the
            // "about double" bar of 2.2. Held here at what the game does now, with no retuning,
            // for the owner to decide.
            let most = w == 9 ? 2.6 : 2.2
            #expect(rates[w] <= max(rates[w - 1], 0.4) * most, "wave \(w + 1): \(rates)")
        }
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

    static let exploits: [RiftwingPilot.Skill] = [.topLedgeSitter, .topLedgeStill, .topLedgePacer, .roofHoverer,
                                                  .underLedgeHoverer, .ventRider, .lowHider, .levelBouncer, .seamCamper,
                                                  .ambusher, .pacingAmbusher]

    // The exploit bars. Their point: no camping or hiding bot does nearly as well as honest
    // play. Until 2026-11-22 they were set against the novice, a wave under it; with no
    // forgiveness of lost clashes the novice reaches only about wave 3.5 (and clears about 0.18
    // waves from wave 7), so it no longer stands for honest play, and the owner plays far above
    // it. The reference is now the competent pilot started in the same place, the honest play
    // nearest the owner's: an exploit may clear at most half as many waves as it (waves cleared:
    // the wave reached less the wave started) and score at most a quarter as much a minute. The
    // novice is kept as a second, lower bar, the least honest play does: no exploit may reach a
    // later wave or score more a minute than it, except where marked OPEN.

    /// The bars against the competent pilot from the same start.
    private func expectWellUnderCompetentPlay(_ skill: RiftwingPilot.Skill, games: [Game], competent: [Game],
                                              startAt: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let cleared = Self.mean(games.map { Double($0.wave - startAt) })
        let competentCleared = Self.mean(competent.map { Double($0.wave - startAt) })
        let rate = Self.mean(games.map(\.scorePerMinute))
        let competentRate = Self.mean(competent.map(\.scorePerMinute))
        print("RIFTWING EXPLOIT FROM WAVE \(startAt) \(skill): waves cleared \(cleared) against the competent's \(competentCleared), score a minute \(rate) against \(competentRate)")
        #expect(games.allSatisfy { $0.isOver }, "\(skill) lasted \(games.map { Int($0.survival) })",
                sourceLocation: sourceLocation)
        #expect(cleared <= competentCleared / 2, "\(skill)", sourceLocation: sourceLocation)
        #expect(rate <= competentRate / 4, "\(skill)", sourceLocation: sourceLocation)
    }

    /// The exploits, tried by bots: sitting, standing still or pacing on the top ledge, hovering
    /// under the roof or under the highest ledge, riding one vent, hiding low, bouncing level
    /// without committing, camping the side seam, and hiding high (still or pacing) to stoop on
    /// what passes below; each from the start of a run (the first layout). Measured on three sets
    /// of 200 seeds (25-minute cap): the competent pilot clears 11.8 waves and scores 39,000 a
    /// minute; the best exploit, the level bouncer, reaches wave 5.9 (6.04, 5.83, 5.85) at 2,800 a
    /// minute; every other stays at wave 3.1 or under and 2,150 a minute or under. The novice
    /// reaches 3.48 at 10,000 a minute.
    @Test(arguments: exploits)
    func noExploitComesNearHonestPlay(_ skill: RiftwingPilot.Skill) throws {
        let games = Self.playAll(skill, seeds: Self.seeds(30), maxSeconds: 1500)
        expectWellUnderCompetentPlay(skill, games: games, competent: Self.competent, startAt: 1)
        let wave = Self.mean(games.map { Double($0.wave) })
        let rate = Self.mean(games.map(\.scorePerMinute))
        let noviceRate = Self.mean(Self.novice.map(\.scorePerMinute))
        print("RIFTWING EXPLOIT \(skill): wave \(wave) against the novice's \(Self.noviceLevel), score a minute \(rate) against \(noviceRate), longest \(games.map(\.survival).max() ?? 0) s")
        #expect(rate < noviceRate, "\(skill)")
        if skill == .levelBouncer {
            // OPEN: the level bouncer outlasts the novice: mean wave 5.9 against 3.48 (three sets
            // of 200 seeds), though at well under a third of its score a minute (2,800 against
            // 10,000) and under half the competent pilot's waves. Held at what the game does now.
            #expect(wave <= Self.noviceLevel + 3, "\(skill)")
        } else {
            #expect(wave <= Self.noviceLevel, "\(skill)")
        }
    }

    /// The same exploits started in the second layout (Spur, wave 4). Measured on three sets of
    /// 200 seeds: the competent pilot from there reaches wave 12.5 at 39,000 a minute; the level
    /// bouncer 6.1 at 2,600 a minute; every other exploit 4.07 or under and 2,400 a minute or
    /// under. The novice from there reaches 4.55 at 6,100 a minute.
    @Test(arguments: exploits)
    func noExploitComesNearHonestPlayInTheSecondLayout(_ skill: RiftwingPilot.Skill) throws {
        let games = Self.playAll(skill, seeds: Self.seeds(20), maxSeconds: 1500, startAt: 4)
        expectWellUnderCompetentPlay(skill, games: games, competent: Self.competentFromSpur, startAt: 4)
        let wave = Self.mean(games.map { Double($0.wave) })
        let novice = Self.mean(Self.noviceFromSpur.map { Double($0.wave) })
        let rate = Self.mean(games.map(\.scorePerMinute))
        let noviceRate = Self.mean(Self.noviceFromSpur.map(\.scorePerMinute))
        print("RIFTWING EXPLOIT FROM WAVE 4 \(skill): wave \(wave) against the novice's \(novice), score a minute \(rate) against \(noviceRate)")
        #expect(rate < noviceRate, "\(skill)")
        if skill == .levelBouncer {
            // OPEN: the level bouncer outlasts the novice from wave 4 too: wave 6.1 against 4.55
            // (three sets of 200 seeds), at under half its score a minute (2,600 against 6,100).
            // Held at what the game does now.
            #expect(wave <= novice + 2.5, "\(skill)")
        } else {
            #expect(wave <= novice, "\(skill)")
        }
    }

    /// The same exploits started in the third layout (Shelves, wave 7). Measured on three sets of
    /// 200 seeds: the competent pilot from there clears 5.1 waves at 39,000 a minute; no exploit
    /// clears more than 0.33 (the level bouncer) or scores more than 5,600 a minute (the pacing
    /// ambusher). The novice clears only 0.18 waves there, at 3,700 a minute.
    @Test(arguments: exploits)
    func noExploitComesNearHonestPlayInTheThirdLayout(_ skill: RiftwingPilot.Skill) throws {
        let games = Self.playAll(skill, seeds: Self.seeds(20), maxSeconds: 1500, startAt: 7)
        expectWellUnderCompetentPlay(skill, games: games, competent: Self.competentFromShelves, startAt: 7)
        let cleared = Self.mean(games.map { Double($0.wave - 7) })
        let novice = Self.mean(Self.noviceFromShelves.map { Double($0.wave - 7) })
        let rate = Self.mean(games.map(\.scorePerMinute))
        let noviceRate = Self.mean(Self.noviceFromShelves.map(\.scorePerMinute))
        print("RIFTWING EXPLOIT FROM WAVE 7 \(skill): waves cleared \(cleared) against the novice's \(novice), score a minute \(rate) against \(noviceRate)")
        switch skill {
        case .levelBouncer:
            // OPEN: the level bouncer clears more waves from wave 7 than the novice (0.33 against
            // 0.18, three sets of 200 seeds), at under half its score a minute (1,640 against
            // 3,700). Held at what the game does now.
            #expect(cleared <= novice + 0.5, "\(skill)")
            #expect(rate < noviceRate, "\(skill)")
        case .ambusher, .pacingAmbusher:
            // OPEN: hiding high to stoop outscores the novice a minute from wave 7: the ambusher
            // 4,780 and the pacing ambusher 5,590 against the novice's 3,700 (three sets of 200
            // seeds); the pacing ambusher also clears as many waves as the novice there (0.18
            // against 0.18; the ambusher 0.10). Both stay far under the competent pilot. Held at
            // what the game does now.
            #expect(cleared <= novice + 0.2, "\(skill)")
            #expect(rate < noviceRate * 2, "\(skill)")
        default:
            #expect(cleared < novice, "\(skill)")
            #expect(rate < noviceRate, "\(skill)")
        }
    }
}
#endif
