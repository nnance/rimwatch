// The golden run needs `RedoubtPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RedoubtCore

/// Same seed and inputs give the same run, and a pinned hash of a scripted run catches any change
/// to Redoubt's behaviour.
@Suite struct RedoubtDeterminismTests {
    /// FNV-1a over every event's full description and the step it came in, plus the final
    /// counters, for `seconds` of play by `skill`.
    static func fingerprint(seed: UInt64, skill: RedoubtPilot.Skill, seconds: Double,
                            waves: RedoubtWaves = RedoubtWaves(),
                            tuning: RedoubtTuning = RedoubtTuning()) -> (hash: UInt64, run: RedoubtRun, events: Int) {
        var r = RedoubtRun(seed: seed, tuning: tuning, waves: waves)
        var pilot = RedoubtPilot(skill: skill, seed: seed)
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var total = 0
        func mix(_ text: String) {
            for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        }
        for _ in 0..<Int(seconds * 120) {
            let events = r.step(pilot.input(for: r))
            total += events.count
            for event in events { mix("\(r.tick) \(event);") }
            if r.isGameOver { break }
        }
        mix("\(r.score) \(r.wave) \(r.colonistsSaved) \(r.colonistsDelivered) \(r.orb.lives) \(r.tick)")
        return (hash, r, total)
    }

    @Test func theSameSeedAndInputsGiveTheSameRun() throws {
        let a = Self.fingerprint(seed: 77, skill: .competent, seconds: 60)
        let b = Self.fingerprint(seed: 77, skill: .competent, seconds: 60)
        #expect(a.hash == b.hash)
        #expect(a.events == b.events)
        #expect(a.run.enemies == b.run.enemies)
        #expect(a.run.colonists == b.run.colonists)
        let c = Self.fingerprint(seed: 78, skill: .competent, seconds: 60)
        #expect(c.hash != a.hash)
    }

    /// Three minutes of the competent pilot on seed 1: waves 1 to 7, five of the six roles,
    /// top-up groups, deliveries, Shockwaves, an extra life and the airlock moving. Debug and
    /// Release builds give the same values. If a deliberate change to the rules, the
    /// tuning, the wave makeup or the pilot breaks it, capture the new values from the printed
    /// line and say so in the commit. Last captured for Refinement 6 (Gleaners through the wave
    /// with a least seizure time, the Spitters' and Burrows' eases counted in their own
    /// appearances: `RedoubtWaves.gleanersThroughWave`); before that for the Gleaners' ramp (their
    /// ease counted in the waves that send them: `RedoubtWaves.gleanerRampEase`); before that for the Burrows' ease (one Burrow pouring
    /// slowly in its debut wave, and debut Spitters back to twice the interval:
    /// `RedoubtWaves.burrowDebutSlowdown`); before that for the Gleaners' ease (late-landing,
    /// slow-dragging Gleaners in their first waves: `RedoubtWaves.gleanerDebutDelay`); before
    /// that when the figures grew by half
    /// (`RedoubtTuning.figureScale` 1.5) with the balance that came with them; before that after
    /// the owner's second play, for the main push and the scatter (`RedoubtWaves.pushAndScatter`);
    /// before that in 13d for the early-game
    /// ease (crowds from entry walls, a gentler early crowd, slower debut Spitters) and the
    /// wall-run rule.
    @Test func aScriptedRunReplaysExactly() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180)
        print("REDOUBT GOLDEN hash \(hash) events \(events) score \(r.score) wave \(r.wave) saved \(r.colonistsSaved) delivered \(r.colonistsDelivered) lives \(r.orb.lives) tick \(r.tick)")
        #expect(hash == 6_031_587_515_073_249_023)
        #expect(events == 7486)
        #expect(r.score == 111_200)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 42)
        #expect(r.colonistsDelivered == 41)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtWaves.beforeGleanersThroughWave` the run is exactly the game at 6e7d6e3,
    /// before Refinement 6: the golden values captured for the Gleaners' ramp.
    @Test func turningOffRefinementSixReplaysTheGameBeforeIt() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180,
                                                 waves: RedoubtWaves.beforeGleanersThroughWave)
        #expect(hash == 11_798_742_744_692_382_655)
        #expect(events == 7351)
        #expect(r.score == 110_200)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 41)
        #expect(r.colonistsDelivered == 41)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtWaves.beforeGleanerRamp` the run is exactly the game before the Gleaners'
    /// ramp: the golden values captured for the Burrows' ease.
    @Test func turningOffTheGleanersRampReplaysTheGameBeforeIt() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180,
                                                 waves: RedoubtWaves.beforeGleanerRamp)
        #expect(hash == 15_979_148_527_682_004_257)
        #expect(events == 7354)
        #expect(r.score == 106_950)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 39)
        #expect(r.colonistsDelivered == 39)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtWaves.beforeBurrowEase` the run is exactly the game before the Burrows'
    /// ease: the golden values captured for the Gleaners' ease.
    @Test func turningOffTheBurrowsEaseReplaysTheGameBeforeIt() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180,
                                                 waves: RedoubtWaves.beforeBurrowEase)
        #expect(hash == 15_480_360_641_026_318_134)
        #expect(events == 7248)
        #expect(r.score == 110_600)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 42)
        #expect(r.colonistsDelivered == 42)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtWaves.beforeGleanerEase` the run is exactly the game before the Gleaners'
    /// ease: the golden values captured when the figures grew.
    @Test func turningOffTheGleanersEaseReplaysTheGameBeforeIt() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180,
                                                 waves: RedoubtWaves.beforeGleanerEase)
        #expect(hash == 10_641_542_555_866_601_042)
        #expect(events == 7290)
        #expect(r.score == 105_650)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 38)
        #expect(r.colonistsDelivered == 38)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtTuning.figureScale` at 1 (and the balance changes that came with the bigger
    /// figures undone) the run is exactly the game before the figures grew: the golden values
    /// captured for the main push and the scatter.
    @Test func figureScaleOneReplaysTheGameBeforeTheFiguresGrew() throws {
        var tuning = RedoubtTuning()
        tuning.figureScale = 1
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180,
                                                 waves: RedoubtWaves.beforeFiguresGrew, tuning: tuning)
        #expect(hash == 1_857_457_665_820_620_754)
        #expect(events == 6847)
        #expect(r.score == 103_650)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 40)
        #expect(r.colonistsDelivered == 40)
        #expect(r.orb.lives == 3)
        #expect(r.tick == 21_600)
    }

    /// With `RedoubtWaves.pushAndScatter` off (and the figures at their old size) the run is
    /// exactly the 13d game: the golden values captured before the main push and the scatter
    /// came in.
    @Test func turningOffThePushAndScatterReplaysThe13dGame() throws {
        var waves = RedoubtWaves.beforeFiguresGrew
        waves.pushAndScatter = false
        var tuning = RedoubtTuning()
        tuning.figureScale = 1
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180, waves: waves, tuning: tuning)
        #expect(hash == 16_656_838_565_572_388_220)
        #expect(events == 7053)
        #expect(r.score == 107_250)
        #expect(r.wave == 7)
        #expect(r.colonistsSaved == 42)
        #expect(r.colonistsDelivered == 39)
        #expect(r.orb.lives == 3)
    }
}
#endif
