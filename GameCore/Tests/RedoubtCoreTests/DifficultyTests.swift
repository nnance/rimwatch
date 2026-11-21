// Needs `RedoubtPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RedoubtCore

/// Coarse guards on Redoubt's first difficulty curve, measured with the scripted pilots in
/// `RedoubtPilot` over a fixed set of seeds. They pin the shape (an idle orb overrun in the first
/// wave, a novice run reaching waves 5 or 6, a competent run reaching waves 8 to 12 and
/// keeping its colonists early on, circling the wall doing far worse than fighting), not exact
/// numbers. The full measurement, over more seeds, is
/// `Tools/Harness` with the `redoubt` argument.
@Suite struct RedoubtDifficultyTests {
    private static let seeds: [UInt64] = (0..<12).map { 1000 + UInt64($0) * 7919 }

    private struct Run {
        var firstDeath: Double?
        var survival = 0.0
        var wave = 0
        var score = 0
        var isOver = false
        var deathsByWave: [Int: Int] = [:]
        var colonistsByWave: [Int: Int] = [:]
        var savedByWave: [Int: Int] = [:]
        /// Wave 1, while the orb is alive: steps, and the sum over them of how many of eight
        /// 45-degree sectors round the orb hold an enemy within 150 units (how surrounded it is).
        var waveOneSteps = 0
        var waveOneSectors = 0
    }

    /// How many of eight 45-degree sectors round the orb hold an enemy within 150 units (edge to
    /// centre), as the harness measures "surrounded".
    static func blockedSectors(_ r: RedoubtRun) -> Int {
        var sectors = [Bool](repeating: false, count: 8)
        for enemy in r.enemies {
            let offset = enemy.pos - r.orb.pos
            guard offset.length - enemy.radius < 150 else { continue }
            var angle = atan2(offset.y, offset.x)
            if angle < 0 { angle += 2 * .pi }
            sectors[min(Int(angle / (.pi / 4)), 7)] = true
        }
        return sectors.count { $0 }
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
            if r.wave == 1, r.phase == .fighting, r.orb.isAlive {
                result.waveOneSteps += 1
                result.waveOneSectors += blockedSectors(r)
            }
            if r.isGameOver { break }
        }
        result.survival = Double(r.tick) * RedoubtRun.timeStep
        result.wave = r.wave
        result.score = r.score
        result.isOver = r.isGameOver
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

    /// The novice pilot stands in for a first-time player. Since the 13d early-game ease (entry
    /// walls, a gentler crowd and slower debut Spitters) it usually reaches wave 5 or 6, the
    /// owner's target for a first game (before it, wave 3, which matched the owner's own first
    /// games: swarmed in waves 2 and 3).
    @Test func aNoviceRunReachesWaveFiveOrSix() throws {
        let runs = Self.seeds.map { Self.play(.novice, seed: $0, maxSeconds: 400) }
        let waves = runs.map { Double($0.wave) }
        #expect((5...6).contains(Self.median(waves)), "\(waves)")
        #expect(runs.allSatisfy { $0.wave >= 3 && $0.wave <= 8 }, "\(waves)")
        // Waves 1 and 2 are nearly always cleared without loss: well under one life between them
        // on average (about 0.2 over 80 seeds; it was about 1.05).
        let early = runs.reduce(0) { $0 + ($1.deathsByWave[1] ?? 0) + ($1.deathsByWave[2] ?? 0) }
        #expect(Double(early) / Double(runs.count) <= 0.5, "\(early) lives lost in waves 1 and 2")
        // Not surrounded in wave 1: on average under one of eight directions round the orb holds
        // an enemy within 150 units (about 0.7; it was about 1.3 when the crowd landed all over
        // the floor).
        let steps = runs.reduce(0) { $0 + $1.waveOneSteps }
        let sectors = Double(runs.reduce(0) { $0 + $1.waveOneSectors }) / Double(max(steps, 1))
        #expect(sectors <= 1.0, "wave 1: \(sectors) of 8 directions blocked on average")
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

    /// The hole the 13d balance pass closed: laps of the floor hugging the wall, firing at the
    /// nearest enemy, never rescuing. Before the wall-run rule (`RedoubtTuning.wallRunGap`) the
    /// wall circler out-survived the competent pilot (median wave 12, 10 minutes in a third of its
    /// games over 80 seeds). Now it is overrun a wave or two after the novice, and the variants
    /// that turn round when blocked or keep to a smaller loop do no better than the fighter.
    @Test func circlingTheWallIsNoSaferThanFighting() throws {
        let circlers = Self.seeds.map { Self.play(.wallCircler, seed: $0, maxSeconds: 300) }
        let waves = circlers.map { Double($0.wave) }
        // Every game over inside five minutes (the competent pilot lasts about six). Since the
        // early-game ease brings the crowd in from the walls, it does worse than the novice
        // (median wave 4, about 90 seconds, over 80 seeds).
        #expect(circlers.allSatisfy { $0.isOver }, "\(circlers.map { Int($0.survival) })")
        #expect((3...5).contains(Self.median(waves)), "\(waves)")
        #expect(circlers.allSatisfy { $0.wave <= 6 }, "\(waves)")
        #expect(Self.median(circlers.map(\.survival)) <= 130)
        // It scores far less than playing properly (about 220,000 for the competent pilot).
        #expect(Self.median(circlers.map { Double($0.score) }) <= 50_000)

        let seeds = Array(Self.seeds.prefix(6))
        let reversers = seeds.map { Self.play(.reversingCircler, seed: $0, maxSeconds: 420) }
        #expect(reversers.allSatisfy { $0.isOver }, "\(reversers.map { Int($0.survival) })")
        #expect(reversers.allSatisfy { (6...10).contains($0.wave) }, "\(reversers.map(\.wave))")
        #expect(Self.median(reversers.map(\.survival)) <= 300)

        let loopers = seeds.map { Self.play(.innerCircler, seed: $0, maxSeconds: 200) }
        #expect(loopers.allSatisfy { $0.isOver })
        #expect(loopers.allSatisfy { $0.wave <= 5 }, "\(loopers.map(\.wave))")
    }

    /// A Burrow left alive keeps pouring Skitters, so a player can sit at a distance and shoot
    /// them. Pinned so it stays a way to rest and never becomes the best way to score: three
    /// Burrows in wave 14, farmed from across the floor without ever hitting a Burrow, pay
    /// about 7,000 points a minute against about 36,000 for playing on.
    @Test func farmingABurrowPaysFarLessThanPlayingOn() throws {
        var r = quietRun()
        r.wave = 14
        r.orb.pos = Vec2(450, 80)
        for spot in [Vec2(200, 470), Vec2(450, 520), Vec2(700, 470)] { r.addEnemy(.burrow, at: spot) }
        var lost = 0
        for _ in 0..<seconds(60) {
            let orb = r.orb
            var aim = Vec2.zero
            // The nearest Skitter that has walked well clear of the holes, when no Burrow is in
            // the line of fire behind it.
            if let target = r.enemies.filter({ $0.role == .skitter && distance($0.pos, orb.pos) < 250 })
                .min(by: { distance($0.pos, orb.pos) < distance($1.pos, orb.pos) }) {
                let lead = target.pos + target.vel * (distance(target.pos, orb.pos) / r.tuning.shotSpeed) - orb.pos
                let dir = lead * (1 / max(lead.length, 1e-9))
                let clear = r.enemies.filter { $0.role == .burrow }.allSatisfy { burrow in
                    let o = burrow.pos - orb.pos
                    return o.x * dir.x + o.y * dir.y < 0 || abs(o.x * dir.y - o.y * dir.x) > burrow.radius + 12
                }
                if clear { aim = dir }
            }
            lost += count(r.step(RedoubtInput(move: .zero, aim: aim)), "orbDestroyed")
        }
        #expect(lost == 0)
        #expect(r.enemies.count { $0.role == .burrow } == 3)
        // Points a minute: well under a third of playing on.
        #expect(r.score >= 3_000 && r.score <= 10_000, "\(r.score) a minute")
    }
}
#endif
