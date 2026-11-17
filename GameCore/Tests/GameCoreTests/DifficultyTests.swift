// Needs `Autopilot`, which only exists in debug builds.
#if DEBUG
import Testing
@testable import GameCore

/// Coarse guards on the difficulty curve, measured with the scripted pilots in `Autopilot` over a
/// fixed set of seeds. They pin the shape (a gentle opening, a novice run that ends early, a
/// competent run that reaches the middle waves), not exact numbers, so a later change to
/// `Tuning` or `WaveDirector` that wrecks the curve fails here. The full measurement, over many
/// more seeds, is the headless harness described in the step 7 report.
@Suite struct DifficultyTests {
    private static let seeds: [UInt64] = (0..<12).map { 1000 + UInt64($0) * 7919 }

    private struct Run {
        var firstDeath: Double?
        var survival: Double
        var wave: Int
        /// Colonists still alive when wave 6 started, if it did.
        var aliveAtWave6: Int?
        /// The wave in which the first Blackout began, if one did.
        var blackoutWave: Int?
        var blackoutEnded = false
    }

    private static func play(_ skill: Autopilot.Skill, seed: UInt64, maxSeconds: Double) -> Run {
        var sim = Simulation(seed: seed)
        var pilot = Autopilot(skill: skill, seed: seed)
        var run = Run(survival: 0, wave: 0)
        for _ in 0..<Int(maxSeconds * 120) {
            let events = sim.step(pilot.input(for: sim))
            for event in events {
                switch event {
                case .playerDestroyed:
                    if run.firstDeath == nil { run.firstDeath = Double(sim.tick) * Simulation.timeStep }
                case .waveStarted(6):
                    run.aliveAtWave6 = sim.survivingColonists
                case .blackoutBegan:
                    if run.blackoutWave == nil { run.blackoutWave = sim.wave }
                case .blackoutEnded:
                    run.blackoutEnded = true
                default:
                    break
                }
            }
            if sim.isGameOver { break }
        }
        run.survival = Double(sim.tick) * Simulation.timeStep
        run.wave = sim.wave
        return run
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    @Test func theOpeningTeachesRatherThanKills() {
        let runs = Self.seeds.map { Self.play(.idle, seed: $0, maxSeconds: 120) }
        let firstDeaths = runs.map { $0.firstDeath ?? $0.survival }
        // A ship that never touches the controls is not lost in the first half minute, and
        // usually lasts to about 40 seconds.
        #expect(firstDeaths.min()! >= 28)
        #expect(Self.median(firstDeaths) >= 34)
        #expect(runs.allSatisfy { $0.survival >= 42 })
    }

    @Test func aNoviceRunEndsInTheEarlyWaves() {
        let runs = Self.seeds.map { Self.play(.novice, seed: $0, maxSeconds: 420) }
        let waves = runs.map { Double($0.wave) }
        #expect((3...6).contains(Self.median(waves)))
        #expect(runs.allSatisfy { $0.wave >= 2 })
        // Abductions stay at their base speed until wave 5, so a new player rarely loses
        // everyone.
        #expect(runs.filter { $0.blackoutWave != nil }.count <= 1)
    }

    @Test func aCompetentRunReachesTheMiddleWavesAndKeepsItsColonists() {
        let runs = Self.seeds.map { Self.play(.competent, seed: $0, maxSeconds: 600) }
        let waves = runs.map { Double($0.wave) }
        // Usually wave 8 to 12; nobody falls in the opening waves, and the curve has no plateau
        // that lets a good player fly on for ever.
        #expect((7...14).contains(Self.median(waves)))
        #expect(runs.allSatisfy { $0.wave >= 4 })
        #expect(runs.filter { $0.wave >= 20 }.count <= 1)
        // Most colonists are still alive going into wave 6.
        let alive = runs.compactMap(\.aliveAtWave6).map(Double.init)
        #expect(alive.count >= runs.count / 2)
        #expect(Self.median(alive) >= 7)
        // A pilot who rescues rarely sees a Blackout, and never early.
        #expect(runs.filter { $0.blackoutWave != nil }.count <= 3)
        #expect(runs.allSatisfy { ($0.blackoutWave ?? 99) >= 6 })
    }

    @Test func aPilotWhoOnlyShootsRunsIntoBlackoutAndCanRecover() {
        // Same fighting skill as the competent pilot, but it never catches or delivers.
        let runs = Self.seeds.map { Self.play(.shooter, seed: $0, maxSeconds: 600) }
        let blackouts = runs.compactMap(\.blackoutWave).map(Double.init)
        #expect(blackouts.count >= runs.count * 3 / 8, "\(blackouts.count) of \(runs.count) runs saw a Blackout")
        // Somewhere in the middle waves, not in the opening.
        #expect(blackouts.allSatisfy { $0 >= 5 })
        #expect((6...9).contains(Self.median(blackouts)))
        // A supply drop usually ends it.
        #expect(runs.filter(\.blackoutEnded).count >= blackouts.count / 2)
    }

    @Test func abductionsSpeedUpFromTheFifthWave() {
        var sim = quietSimulation()
        sim.wave = 4
        #expect(sim.abductionScale == 1 && sim.liftScale == 1)
        sim.wave = 6
        #expect(sim.abductionScale > 1.5 && sim.liftScale > 1)
        sim.wave = 40
        #expect(sim.abductionScale == sim.tuning.abductionMaxScale)
    }

    @Test func holdingFireOverheatsOnlyAfterAGoodFewSeconds() {
        var sim = quietSimulation()
        let firing = InputState(fire: true)
        let heating = run(&sim, maxSteps: 120 * 20, input: firing) { $0 == .playerOverheated }
        #expect(heating.contains(.playerOverheated))
        let heldFor = Double(sim.tick) * Simulation.timeStep
        #expect(heldFor >= 5 && heldFor <= 10)

        let overheatedAt = sim.tick
        run(&sim, maxSteps: 120 * 5, input: firing) { $0.isPlayerFired }
        let lockout = Double(sim.tick - overheatedAt) * Simulation.timeStep
        #expect(lockout >= 0.8 && lockout <= 1.5)
    }

    @Test func harvestersOnlyShootFromWellInsideTheScreen() {
        // The visible half-width is about 480 world units on the Duo and 490 in the letterbox.
        #expect(Tuning().harvesterFireRange <= 420)
    }

    @Test func aColonistDroppedMidAbductionIsCatchable() {
        let tuning = Tuning()
        // Shot loose just after the grab: lands safely even if nobody catches it.
        #expect(tuning.safeFallHeight >= 90)

        // From high up it takes long enough to fall that a ship a screen away can get under it.
        var sim = quietSimulation()
        sim.player.pos.x = sim.world.wrap(sim.colonists[0].pos.x + 2000)
        let ground = sim.colonists[0].pos.y
        sim.colonists[0].pos.y = ground + 350
        sim.colonists[0].state = .falling(speed: 0, from: 350)
        let start = sim.tick
        run(&sim, maxSteps: 120 * 10) { $0.isColonistLost || $0.isColonistLanded }
        let fallTime = Double(sim.tick - start) * Simulation.timeStep
        #expect(fallTime * tuning.maxSpeed >= 1000)
    }
}
#endif
