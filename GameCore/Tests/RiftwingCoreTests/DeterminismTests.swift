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
                            tuning: RiftwingTuning = RiftwingTuning()) -> (hash: UInt64, run: RiftwingRun, events: Int) {
        var r = RiftwingRun(seed: seed, tuning: tuning)
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

    /// Three minutes of the competent pilot on seed 1: waves 1 to 6, the cavern's first shift,
    /// four of the five roles and two extra lives. Debug and Release builds give the same values
    /// (`GOLDEN=1 .build/release/Harness riftwing` prints them from a release build). If a
    /// deliberate change to the rules, the tuning, the wave table or the pilot breaks it, capture
    /// the new values from the printed line and say so in the commit. First captured for 15a.
    @Test func aScriptedRunReplaysExactly() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180)
        print("RIFTWING GOLDEN hash \(hash) events \(events) score \(r.score) wave \(r.wave) saved \(r.colonistsSaved) lives \(r.rider.lives) tick \(r.tick)")
        #expect(hash == 9_537_427_139_909_576_491)
        #expect(events == 840)
        #expect(r.score == 79_100)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 25)
        #expect(r.rider.lives == 5)
        #expect(r.tick == 21_600)
    }
}
#endif
