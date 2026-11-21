import Testing
import GameCore
@testable import RedoubtCore

/// The HUD's colonist warning: red only in danger, calm otherwise.
@Suite struct ReadoutTests {
    static func run(_ states: [RedoubtColonist.State], powerCut: Bool = false, pending: Bool = false) -> RedoubtRun {
        var r = RedoubtRun(seed: 1)
        r.colonists = states.enumerated().map { index, state in
            var c = RedoubtColonist(id: 100 + index, pos: Vec2(100 + 50 * Double(index), 100))
            c.state = state
            return c
        }
        r.isPowerCut = powerCut
        r.powerCutPending = pending
        return r
    }

    @Test func calmWhileAnyoneIsSafe() {
        #expect(!Self.run([.sheltering, .sheltering]).colonistAlarm)
        #expect(!Self.run([.following, .seized(by: 1)]).colonistAlarm)
        #expect(!Self.run([.sheltering, .lost, .delivered]).colonistAlarm)
        // No colonists at all (before the first wave): calm.
        #expect(!Self.run([]).colonistAlarm)
    }

    @Test func alarmedWhenEveryoneLeftIsInAGrip() {
        #expect(Self.run([.seized(by: 1)]).colonistAlarm)
        #expect(Self.run([.seized(by: 1), .seized(by: 2), .lost, .delivered]).colonistAlarm)
    }

    @Test func noneLeftIsCalmOnlyIfSomeoneGotOut() {
        #expect(!Self.run([.delivered, .lost]).colonistAlarm)
        #expect(!Self.run([.delivered, .delivered]).colonistAlarm)
        #expect(Self.run([.lost, .lost]).colonistAlarm)
    }

    @Test func thePowerCutAlwaysAlarms() {
        #expect(Self.run([.sheltering], powerCut: true).colonistAlarm)
        // Due out at the next wave, with the next wave's colonists already safe on the floor.
        #expect(Self.run([.sheltering, .sheltering], pending: true).colonistAlarm)
    }
}
