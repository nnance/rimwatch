import Foundation
import Testing
@testable import GameCore

@Suite struct MenuNavigationTests {
    @Test func dPadBeatsTheStickAndDiagonalsPickTheStrongerAxis() {
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 1), dpad: Vec2(0, -1)), previous: nil) == .down)
        // A fresh stick push is horizontal only when clearly so; a diagonal reads as vertical.
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.95, 0.4)), previous: nil) == .right)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.9, 0.6)), previous: nil) == .up)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(-0.3, -0.9)), previous: nil) == .down)
        #expect(MenuDirection.of(PadSnapshot(dpad: Vec2(1, 1)), previous: nil) == .up)
    }

    @Test func theStickNeedsAFirmPushAndHasHysteresis() {
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 0.4)), previous: nil) == nil)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 0.6)), previous: nil) == .up)
        // Once held, it stays held until the stick falls below the release threshold.
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 0.4)), previous: .up) == .up)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 0.3)), previous: .up) == nil)
    }

    private let frame = 1.0 / 60

    /// Runs `seconds` of frames and returns each step with the time it happened.
    private func run(_ reader: inout PadReader, seconds: Double) -> [(Double, MenuCommand)] {
        var steps: [(Double, MenuCommand)] = []
        var t = 0.0
        while t < seconds - 1e-9 {
            for command in reader.menuCommands(elapsed: frame) { steps.append((t, command)) }
            t += frame
        }
        return steps
    }

    @Test func holdingRepeatsAfterADelayThenSteadily() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        let steps = run(&reader, seconds: 1.0)
        #expect(steps.allSatisfy { $0.1 == .down })
        #expect(steps.first?.0 == 0)
        // Nothing until the initial delay has passed.
        #expect(steps.dropFirst().allSatisfy { $0.0 >= MenuDirectionTracker.initialDelay - frame })
        // Then about one step per interval: 1 + (1.0 - 0.38) / 0.11 is about 6.6.
        #expect(steps.count >= 6 && steps.count <= 8, "\(steps.count) steps")
    }

    @Test func releasingAndPushingAgainStepsAtOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [.up])
        #expect(reader.menuCommands(elapsed: frame) == [])
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: frame) == [])
        reader.receive(PadSnapshot(stick: Vec2(0, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [.up])
        // Changing direction is a new push too.
        reader.receive(PadSnapshot(stick: Vec2(-1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.left])
    }

    @Test func aLongFrameRepeatsOnlyOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [.down])
        #expect(reader.menuCommands(elapsed: 2.0) == [.down])
        #expect(reader.menuCommands(elapsed: frame) == [])
    }

    @Test func aPushIsNotAlsoARepeatInALongFrame() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: 2.0) == [.down])
    }

    // Mixing the stick and the D-pad.

    @Test func aStickTapWhileTheDPadIsHeldStepsOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [.down])
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(0, -1)))
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        #expect(reader.menuCommands(elapsed: frame) == [])
    }

    @Test func aDPadTapWhileTheStickIsHeldStepsOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(0, -1)))
        reader.receive(PadSnapshot(stick: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.down])
        #expect(reader.menuCommands(elapsed: frame) == [])
    }

    @Test func releasingTheDPadWhileTheStickIsHeldDoesNotStep() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(0, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [.up])
        // The D-pad, pushed last, repeats while held.
        let held = run(&reader, seconds: 0.5)
        #expect(!held.isEmpty && held.allSatisfy { $0.1 == .up })
        // Letting it go: no step now; the stick takes over after the full initial delay.
        reader.receive(PadSnapshot(stick: Vec2(1, 0)))
        let after = run(&reader, seconds: 0.6)
        #expect(after.allSatisfy { $0.1 == .right })
        #expect(after.first.map { $0.0 >= MenuDirectionTracker.initialDelay - frame } == true,
                "first step at \(String(describing: after.first?.0))")
    }

    @Test func releasingTheStickWhileTheDPadIsHeldDoesNotStep() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [.down, .right])
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [])
        let after = run(&reader, seconds: 0.6)
        #expect(after.first?.1 == .down)
        #expect(after.first.map { $0.0 >= MenuDirectionTracker.initialDelay - frame } == true)
    }

    @Test func releasingBothGivesNothing() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(0, 1)))
        _ = reader.menuCommands(elapsed: frame)
        reader.receive(PadSnapshot(stick: Vec2(1, 0)))
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: frame) == [])
        #expect(run(&reader, seconds: 1).isEmpty)
    }

    @Test func tapsFromBothSourcesBetweenFramesCountOnceEach() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        reader.receive(PadSnapshot())
        reader.receive(PadSnapshot(stick: Vec2(-1, 0)))
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: frame) == [.down, .left])
        #expect(run(&reader, seconds: 1).isEmpty)
    }

    @Test func aDirectionHeldWhenAScreenAppearsWaitsForANewPush() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0, -1)))
        reader.screenChanged()
        #expect(run(&reader, seconds: 1).isEmpty)
        // A D-pad push still works while the stick stays ignored...
        reader.receive(PadSnapshot(stick: Vec2(0, -1), dpad: Vec2(1, 0)))
        reader.receive(PadSnapshot(stick: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        #expect(run(&reader, seconds: 1).isEmpty)
        // ...and the stick moved to a new direction counts.
        reader.receive(PadSnapshot(stick: Vec2(0, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [.up])
    }

    // Diagonals.

    /// Feeds `snapshots` one per frame, in a loop, for `seconds`, and returns every step.
    private func feed(_ reader: inout PadReader, _ snapshots: [PadSnapshot], seconds: Double) -> [MenuCommand] {
        var steps: [MenuCommand] = []
        var t = 0.0
        var index = 0
        while t < seconds - 1e-9 {
            reader.receive(snapshots[index % snapshots.count])
            steps += reader.menuCommands(elapsed: frame)
            index += 1
            t += frame
        }
        return steps
    }

    @Test func aStickRestingOnADiagonalDoesNotChatter() {
        var reader = PadReader()
        // A thumb at 45 degrees, wobbling a hair either side every frame.
        let wobble = [PadSnapshot(stick: Vec2(0.71, 0.69)), PadSnapshot(stick: Vec2(0.69, 0.71))]
        let steps = feed(&reader, wobble, seconds: 0.3)
        #expect(steps == [.up], "\(steps)")
        // Held on: only the steady repeat, always the same way.
        let held = feed(&reader, wobble, seconds: 1)
        #expect(held.allSatisfy { $0 == .up } && held.count <= 9, "\(held)")
        // A clearly horizontal push still switches.
        reader.receive(PadSnapshot(stick: Vec2(0.95, 0.3)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
    }

    @Test func theStickAxisNeedsAMarginToTakeOver() {
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.6, 0.75)), previous: .right) == .right)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.45, 0.85)), previous: .right) == .up)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.69, 0.71)), previous: nil) == .up)
    }

    @Test func aDPadRollingOntoADiagonalAndBackIsNotANewPush() {
        var reader = PadReader()
        // Right, then rolling between up-right and right.
        let roll = [PadSnapshot(dpad: Vec2(1, 0)), PadSnapshot(dpad: Vec2(1, 1))]
        #expect(feed(&reader, roll, seconds: 0.3) == [.right])
        // Starting on the diagonal (read as up): letting up go while right stays down is a turn,
        // and steps at once; rocking back onto the diagonal after that is not.
        var fromDiagonal = PadReader()
        let rollBack = [PadSnapshot(dpad: Vec2(1, 1)), PadSnapshot(dpad: Vec2(1, 0))]
        #expect(feed(&fromDiagonal, rollBack, seconds: 0.3) == [.up, .right])
        // Letting go and pressing another button is still a push.
        fromDiagonal.receive(PadSnapshot())
        fromDiagonal.receive(PadSnapshot(dpad: Vec2(0, -1)))
        #expect(fromDiagonal.menuCommands(elapsed: frame) == [.down])
    }

    @Test func aDPadRolledFromOneDirectionToAnotherTurnsAtOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [.up])
        reader.receive(PadSnapshot(dpad: Vec2(1, 1)))
        #expect(reader.menuCommands(elapsed: frame) == [])
        reader.receive(PadSnapshot(dpad: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        // Rolling back onto the diagonal keeps right, and back onto right again is nothing new.
        reader.receive(PadSnapshot(dpad: Vec2(1, 1)))
        reader.receive(PadSnapshot(dpad: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [])
    }

    @Test func aNoisyDiagonalStickNeverChangesAValue() {
        // Thumbs pushed toward each corner, within 12 degrees of 45, ramping in with jitter, held
        // and let go, over many seeds: the selection may move, an option value must not.
        var horizontal = 0
        var vertical = 0
        for seed in 1...200 {
            var rng = SeededRNG(seed: UInt64(seed))
            var reader = PadReader()
            for _ in 0..<6 {
                let corner = Double(Int(rng.next() % 4))
                let angle = (45 + rng.range(-12...12) + 90 * corner) * Double.pi / 180
                let reach = rng.range(0.6...1.0)
                let frames = Int(rng.range(4...40))
                for f in 0..<frames {
                    let ramp = min(1, Double(f + 1) / 4)
                    let wobble = rng.range(-3...3) * Double.pi / 180
                    let r = reach * ramp * rng.range(0.97...1.0)
                    reader.receive(PadSnapshot(stick: Vec2(cos(angle + wobble) * r, sin(angle + wobble) * r)))
                    for command in reader.menuCommands(elapsed: frame) {
                        if command == .left || command == .right { horizontal += 1 } else { vertical += 1 }
                    }
                }
                reader.receive(PadSnapshot())
                _ = reader.menuCommands(elapsed: frame)
            }
        }
        #expect(horizontal == 0, "\(horizontal) horizontal steps")
        #expect(vertical > 0)
    }

    @Test func theStickAndDPadPushedTogetherStepOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0), dpad: Vec2(1, 0)))
        #expect(reader.menuCommands(elapsed: frame) == [.right])
        #expect(run(&reader, seconds: MenuDirectionTracker.initialDelay - 2 * frame).isEmpty)
        // The same, arriving as two snapshots within one frame.
        var split = PadReader()
        split.receive(PadSnapshot(dpad: Vec2(0, -1)))
        split.receive(PadSnapshot(stick: Vec2(0, -1), dpad: Vec2(0, -1)))
        #expect(split.menuCommands(elapsed: frame) == [.down])
        // Pushed different ways, they still step once each.
        var different = PadReader()
        different.receive(PadSnapshot(stick: Vec2(0, 1), dpad: Vec2(1, 0)))
        #expect(different.menuCommands(elapsed: frame) == [.right, .up])
    }
}
