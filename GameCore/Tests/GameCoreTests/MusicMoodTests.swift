import Foundation
import Testing
@testable import GameCore

@Suite struct MusicMoodTests {
    @Test func aWaveArrivingTurnsTheMusicTenseAndQuietCalmsIt() {
        var director = MusicMoodDirector()
        director.reset()
        #expect(director.update(elapsed: 0.1, threat: 0, wave: 1, blackout: false) == .tension)
        // Still threatening: stays tense.
        for _ in 0..<100 { _ = director.update(elapsed: 0.1, threat: 2, wave: 1, blackout: false) }
        #expect(director.mood == .tension)
        // Quiet for long enough: calms.
        for _ in 0..<60 { _ = director.update(elapsed: 0.1, threat: 0.2, wave: 1, blackout: false) }
        #expect(director.mood == .calm)
    }

    @Test func aThreatFlickeringAroundTheThresholdsDoesNotFlap() {
        var director = MusicMoodDirector()
        var changes = 0
        var last = director.mood
        var times: [Double] = []
        var t = 0.0
        for step in 0..<6000 {
            // Swings between quiet and dangerous every half second, for ten minutes.
            let threat = (step / 5) % 2 == 0 ? 0.0 : 3.0
            let mood = director.update(elapsed: 0.1, threat: threat, wave: 1, blackout: false)
            t += 0.1
            if mood != last { changes += 1; times.append(t); last = mood }
        }
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 >= MusicMoodDirector.minimumHold - 1e-9 })
        #expect(changes <= Int(600 / MusicMoodDirector.minimumHold))
    }

    @Test func blackoutIsImmediateBothWays() {
        var director = MusicMoodDirector()
        director.reset()
        _ = director.update(elapsed: 0.1, threat: 3, wave: 2, blackout: false)
        #expect(director.update(elapsed: 0.1, threat: 3, wave: 2, blackout: true) == .blackout)
        #expect(director.update(elapsed: 0.1, threat: 3, wave: 2, blackout: false) == .tension)
    }

    @Test func threatCountsNearbyEnemiesAbductionsAndFallingColonists() {
        var sim = quietSimulation()
        #expect(MusicMoodDirector.threat(in: sim) == 0)
        sim.addEnemy(kind: .husk, at: Vec2(sim.player.pos.x + 100, sim.player.pos.y))
        #expect(MusicMoodDirector.threat(in: sim) == 1)
        // Far away it doesn't count.
        sim.addEnemy(kind: .husk, at: Vec2(sim.world.wrap(sim.player.pos.x + 3000), sim.player.pos.y))
        #expect(MusicMoodDirector.threat(in: sim) == 1)
    }

    #if DEBUG
    /// A competent player's game moves between calm and tension several times, never faster than
    /// the minimum hold.
    @Test func aRealGameMovesBetweenCalmAndTension() {
        for seed: UInt64 in [1, 2, 3] {
            var sim = Simulation(seed: seed)
            var bot = Autopilot(skill: .competent, seed: seed)
            var director = MusicMoodDirector()
            director.reset()
            var last = director.mood
            var times: [Double] = []
            var counts: [MusicMood: Int] = [:]
            let steps = Int(480 / Simulation.timeStep)
            for step in 0..<steps where !sim.isGameOver {
                _ = sim.step(bot.input(for: sim))
                guard step % 4 == 0 else { continue }
                let mood = director.update(elapsed: 4 * Simulation.timeStep, sim: sim)
                if mood != last {
                    times.append(Double(step) * Simulation.timeStep)
                    counts[mood, default: 0] += 1
                    last = mood
                }
            }
            let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
            print("MOOD seed \(seed): \(times.count) changes over \(Int(Double(sim.tick) * Simulation.timeStep)) s, waves \(sim.wave), \(counts), min gap \(gaps.min() ?? 0)")
            #expect((counts[.calm] ?? 0) >= 2, "seed \(seed): \(counts)")
            #expect((counts[.tension] ?? 0) >= 2, "seed \(seed): \(counts)")
            #expect(gaps.allSatisfy { $0 >= MusicMoodDirector.minimumHold - 0.05 } || sim.isBlackout)
        }
    }
    #endif
}
