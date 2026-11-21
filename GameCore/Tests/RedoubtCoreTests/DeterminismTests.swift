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
    static func fingerprint(seed: UInt64, skill: RedoubtPilot.Skill, seconds: Double) -> (hash: UInt64, run: RedoubtRun, events: Int) {
        var r = RedoubtRun(seed: seed)
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

    /// Three minutes of the competent pilot on seed 1: waves 1 to 6, five of the six roles,
    /// top-up groups, deliveries, Shockwaves, an extra life and the airlock moving. Debug and
    /// Release builds give the same values. If a deliberate change to the rules, the
    /// tuning, the wave makeup or the pilot breaks it, capture the new values from the printed
    /// line and say so in the commit.
    @Test func aScriptedRunReplaysExactly() throws {
        let (hash, r, events) = Self.fingerprint(seed: 1, skill: .competent, seconds: 180)
        print("REDOUBT GOLDEN hash \(hash) events \(events) score \(r.score) wave \(r.wave) saved \(r.colonistsSaved) delivered \(r.colonistsDelivered) lives \(r.orb.lives) tick \(r.tick)")
        #expect(hash == 12_757_582_349_164_082_327)
        #expect(events == 6970)
        #expect(r.score == 105_000)
        #expect(r.wave == 6)
        #expect(r.colonistsSaved == 40)
        #expect(r.colonistsDelivered == 40)
        #expect(r.orb.lives == 4)
        #expect(r.tick == 21_600)
    }
}
#endif
