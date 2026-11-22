// The golden run needs `RiftwingPilot`, which only exists in debug builds.
#if DEBUG
import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Same seed and inputs give the same run, and a pinned hash of a scripted run catches any change
/// to Riftwing's behaviour.
@Suite struct RiftwingDeterminismTests {
    /// FNV-1a over every event's full description and the step it came in, plus the final
    /// counters, for `seconds` of play by `skill`.
    static func fingerprint(seed: UInt64, skill: RiftwingPilot.Skill, seconds: Double,
                            tuning: RiftwingTuning = RiftwingTuning(),
                            waves: RiftwingWaves = RiftwingWaves()) -> (hash: UInt64, run: RiftwingRun, events: Int) {
        var r = RiftwingRun(seed: seed, tuning: tuning, waves: waves)
        var pilot = RiftwingPilot(skill: skill, seed: seed)
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
        mix("\(r.score) \(r.wave) \(r.colonistsSaved) \(r.rider.lives) \(r.tick)")
        return (hash, r, total)
    }

    @Test func theSameSeedAndInputsGiveTheSameRun() throws {
        let a = Self.fingerprint(seed: 77, skill: .competent, seconds: 60)
        let b = Self.fingerprint(seed: 77, skill: .competent, seconds: 60)
        #expect(a.hash == b.hash)
        #expect(a.events == b.events)
        #expect(a.run.opponents == b.run.opponents)
        #expect(a.run.pods == b.run.pods)
        let c = Self.fingerprint(seed: 78, skill: .competent, seconds: 60)
        #expect(c.hash != a.hash)
    }

    /// Up to 330 s of the competent pilot on seed 1: since 2026-11-22 it loses its last life in
    /// wave 6, 135 s in, so the run covers waves 1 to 6, the first cavern shift and four roles
    /// (before, it reached wave 10, with both shifts and all five roles; that run is still pinned
    /// by `withGentleDebutsReplaysTheGameBeforeFullStrengthDebuts`). Debug and Release builds give the
    /// same values (`GOLDEN=1 .build/release/Harness riftwing` prints them from a release
    /// build). If a deliberate change to the rules, the tuning, the wave table or the pilot breaks
    /// it, capture the new values from the printed line and say so in the commit. First captured
    /// for 15a; re-captured after the check's fixes, and again (extended from 180 s) after the
    /// breath, ceiling, clash and tuning changes, and again after the pod, pinned, resting and
    /// mercy changes and the retuning that followed them, and again after the last round of
    /// corrections (no ramming rule or harder knock, hatched rigs eased for a rider who frees
    /// colonists, the standing rider's footing, the Warden's early dives, the extra life back at
    /// 35,000, and the pilots' routing), and again when the figures grew by half
    /// (`RiftwingTuning.figureScale` 1.5; the run now reaches wave 10), and again when the
    /// forgiveness of lost clashes was taken out (2026-11-22: `clashMercy` and
    /// `standingGraceWaves` 0; the pilot now loses its last life in wave 10, 305 s in), and
    /// again later that day when every kind came to fly at full strength from its debut and the
    /// clash leniency went from 16.1 to 12 (the values before are kept by
    /// `withGentleDebutsReplaysTheGameBeforeFullStrengthDebuts`).
    @Test func aScriptedRunReplaysExactly() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 330)
        print("RIFTWING GOLDEN hash \(hash) events \(events) score \(r.score) wave \(r.wave) saved \(r.colonistsSaved) lives \(r.rider.lives) tick \(r.tick)")
        #expect(hash == 647_307_081_655_133_869)
        #expect(events == 730)
        #expect(r.score == 69_800)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 24)
        #expect(r.rider.lives == 0)
        #expect(r.tick == 16_239)
    }

    /// With `RiftwingWaves.withGentleDebuts` the run is exactly the game between the two
    /// changes of 2026-11-22 (no forgiveness of lost clashes; gentle debuts and a leniency of
    /// 16.1): the golden values captured when the forgiveness was taken out.
    @Test func withGentleDebutsReplaysTheGameBeforeFullStrengthDebuts() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 330, waves: .withGentleDebuts)
        #expect(hash == 7_540_357_914_633_432_388)
        #expect(events == 1548)
        #expect(r.score == 166_750)
        #expect(r.wave == 10)
        #expect(r.colonistsSaved == 51)
        #expect(r.rider.lives == 0)
        #expect(r.tick == 36_614)
    }

    /// With `RiftwingTuning.figureScale` at 1 and the beginner's forgiveness back
    /// (`RiftwingWaves.withBeginnerForgiveness`) the run is exactly the game before the figures
    /// grew by half: the golden values captured for the last round of corrections.
    @Test func figureScaleOneReplaysTheGameBeforeTheFiguresGrew() throws {
        var tuning = RiftwingTuning()
        tuning.figureScale = 1
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 330, tuning: tuning,
                                                 waves: .withBeginnerForgiveness)
        #expect(hash == 17_106_605_481_073_300_803)
        #expect(events == 1483)
        #expect(r.score == 108_100)
        #expect(r.wave == 8)
        #expect(r.colonistsSaved == 37)
        #expect(r.rider.lives == 5)
        #expect(r.tick == 39_600)
    }
}
#endif
