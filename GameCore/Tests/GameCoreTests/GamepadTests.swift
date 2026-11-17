import Foundation
import Testing
@testable import GameCore

@Suite struct PadMappingTests {
    @Test func stickInsideTheDeadZoneReadsAsCentred() {
        #expect(PadMapping.stick(Vec2(0.1, -0.1)) == .zero)
        #expect(PadMapping.stick(Vec2(0, PadMapping.deadZone)) == .zero)
    }

    @Test func stickOutsideTheDeadZoneIsRescaledToReachFullDeflection() {
        let full = PadMapping.stick(Vec2(1, 0))
        #expect(abs(full.x - 1) < 1e-9)
        let justOutside = PadMapping.stick(Vec2(0, PadMapping.deadZone + 0.01))
        #expect(justOutside.y > 0 && justOutside.y < 0.02)
        // A corner reading longer than 1 is capped, keeping its direction.
        let corner = PadMapping.stick(Vec2(1, 1))
        #expect(abs(corner.length - 1) < 1e-9)
        #expect(abs(corner.x - corner.y) < 1e-9)
    }

    @Test func dPadAndStickMerge() {
        // The D-pad alone flies at full speed.
        #expect(PadMapping.move(PadSnapshot(dpad: Vec2(-1, 0))) == Vec2(-1, 0))
        // Each axis takes the larger deflection, so the D-pad doesn't cancel the stick.
        let merged = PadMapping.move(PadSnapshot(stick: Vec2(0, 0.6), dpad: Vec2(1, 0)))
        #expect(merged.x > 0.7 && merged.y > 0.3)
        #expect(merged.length <= 1 + 1e-9)
        // The stick wins an axis where it is pushed harder than the D-pad.
        let stickWins = PadMapping.move(PadSnapshot(stick: Vec2(0, -1), dpad: Vec2(0, 0.5)))
        #expect(stickWins.y < -0.99)
        #expect(PadMapping.move(.neutral) == .zero)
    }

    @Test func layoutsSwapBlinkAndShockwave() {
        let b: Set<PadButton> = [.b]
        let x: Set<PadButton> = [.x]
        let standardB = PadMapping.input(move: .zero, held: b, layout: .standard)
        #expect(standardB.blink && !standardB.shockwave && !standardB.fire)
        let standardX = PadMapping.input(move: .zero, held: x, layout: .standard)
        #expect(standardX.shockwave && !standardX.blink)
        let swappedB = PadMapping.input(move: .zero, held: b, layout: .swapped)
        #expect(swappedB.shockwave && !swappedB.blink)
        let swappedX = PadMapping.input(move: .zero, held: x, layout: .swapped)
        #expect(swappedX.blink && !swappedX.shockwave)
        for layout in GameOptions.GamepadLayout.allCases {
            let a = PadMapping.input(move: .zero, held: [.a], layout: layout)
            #expect(a.fire && !a.blink && !a.shockwave)
        }
        // Y and the menu button do nothing in play.
        #expect(PadMapping.input(move: .zero, held: [.y, .menu], layout: .standard) == InputState())
    }
}

@Suite struct PadReaderTests {
    @Test func heldButtonsReachGameplay() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0), buttons: [.a]))
        let input = reader.input(layout: .standard)
        #expect(input.fire)
        #expect(input.move.x > 0.99)
        reader.consumePlayPresses()
        #expect(reader.input(layout: .standard).fire, "still held")
    }

    @Test func aTapBetweenFramesIsLatchedUntilTheSimulationSteps() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.b]))
        reader.receive(PadSnapshot())
        #expect(reader.input(layout: .standard).blink)
        reader.consumePlayPresses()
        #expect(!reader.input(layout: .standard).blink)
    }

    @Test func pressEdgesBecomeMenuCommandsOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.a]))
        #expect(reader.menuCommands(elapsed: 0.016) == [.activate])
        // Still held: no second activation.
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        reader.receive(PadSnapshot())
        reader.receive(PadSnapshot(buttons: [.b]))
        reader.receive(PadSnapshot(buttons: [.b, .menu]))
        #expect(reader.menuCommands(elapsed: 0.016) == [.back, .pause])
    }

    @Test func aDPadTapBetweenFramesStillMoves() {
        var reader = PadReader()
        reader.receive(PadSnapshot(dpad: Vec2(0, -1)))
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: 0.016) == [.down])
        #expect(reader.menuCommands(elapsed: 0.016) == [])
    }

    @Test func aStickFlickBetweenFramesStillMoves() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0.9, 0)))
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: 0.016) == [.right])
        // A push inside the threshold is not a flick.
        reader.receive(PadSnapshot(stick: Vec2(0.4, 0)))
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: 0.016) == [])
    }

    @Test func thePausePressDuringPlayIsTakenOnce() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.menu]))
        #expect(reader.takePausePress() == true)
        #expect(reader.takePausePress() == false)
    }

    @Test func aStickStillPushedWhenAMenuOpensDoesNotMoveIt() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0, -1), buttons: [.menu]))
        #expect(reader.takePausePress() == true)
        // The pause menu is now showing; the stick is still down from flying.
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        #expect(reader.menuCommands(elapsed: 1.0) == [])
        // Let go and push again: now it moves.
        reader.receive(PadSnapshot())
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        reader.receive(PadSnapshot(stick: Vec2(0, -1)))
        #expect(reader.menuCommands(elapsed: 0.016) == [.down])
    }

    @Test func buttonsHeldWhenPlayStartsAreIgnoredUntilLetGo() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.a]))
        // A chose Play: the same press must not also fire.
        reader.suppressHeldButtons()
        #expect(!reader.input(layout: .standard).fire)
        reader.consumePlayPresses()
        #expect(!reader.input(layout: .standard).fire, "still held from the menu")
        reader.receive(PadSnapshot())
        reader.receive(PadSnapshot(buttons: [.a]))
        #expect(reader.input(layout: .standard).fire, "a fresh press fires")
    }

    @Test func aTapLatchedBeforePlayStartsIsDropped() {
        var reader = PadReader()
        reader.receive(PadSnapshot(buttons: [.a]))
        reader.receive(PadSnapshot())
        reader.suppressHeldButtons()
        #expect(!reader.input(layout: .standard).fire)
    }

    @Test func aNewScreenDropsEarlierPressesAndHeldDirections() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(0, -1), buttons: [.a]))
        reader.screenChanged()
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        #expect(reader.menuCommands(elapsed: 1) == [])
        reader.receive(PadSnapshot())
        reader.receive(PadSnapshot(buttons: [.a]))
        #expect(reader.menuCommands(elapsed: 0.016) == [.activate])
    }

    @Test func resetForgetsEverything() {
        var reader = PadReader()
        reader.receive(PadSnapshot(stick: Vec2(1, 0), buttons: [.a, .menu]))
        reader.reset()
        #expect(reader.input(layout: .standard) == InputState())
        #expect(reader.menuCommands(elapsed: 0.016) == [])
        #expect(reader.current == .neutral)
    }
}

@Suite struct MenuNavigationTests {
    @Test func dPadBeatsTheStickAndDiagonalsPickTheStrongerAxis() {
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0, 1), dpad: Vec2(0, -1)), previous: nil) == .down)
        #expect(MenuDirection.of(PadSnapshot(stick: Vec2(0.9, 0.6)), previous: nil) == .right)
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
}

@Suite struct FrontEndMenuCommandTests {
    private func frontEnd(pose: FoldPose = .open) -> FrontEnd {
        FrontEnd(session: GameSession(seed: 3), pose: pose)
    }

    /// Runs the player out of lives, so the game-over screen shows.
    private func die(_ fe: inout FrontEnd) {
        fe.session.simulation.player.lives = 1
        fe.session.simulation.addEnemy(kind: .husk, at: fe.session.simulation.player.pos, state: .hunting)
        _ = fe.update(elapsed: 0.05, input: InputState())
    }

    /// Lets the screen settle past the activation grace, then sends `command`.
    @discardableResult
    private func press(_ fe: inout FrontEnd, _ command: MenuCommand) -> [FrontEnd.Effect] {
        _ = fe.update(elapsed: FrontEnd.activationGrace(for: fe.screen) + 0.01, input: InputState())
        return fe.handle(command).effects
    }

    @Test func padCommandsNavigateTheTitleIntoPlay() {
        var fe = frontEnd()
        #expect(fe.menu?.selectedItem?.command == .play)
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.command == .options)
        fe.handle(.up)
        #expect(press(&fe, .activate) == [.newRun])
        #expect(fe.screen == .playing)
    }

    @Test func pauseTogglesBetweenPlayAndThePauseMenu() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.handle(.pause)
        #expect(fe.screen == .paused)
        #expect(fe.menu?.kind == .pause)
        #expect(fe.menu?.selectedItem?.command == .resume)
        fe.handle(.pause)
        guard case .countdown = fe.screen else {
            Issue.record("expected the countdown, got \(fe.screen)")
            return
        }
        // Pausing again during the countdown works too.
        fe.handle(.pause)
        #expect(fe.screen == .paused)
    }

    @Test func pauseCannotResumeWhileClosed() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.setPose(.closed)
        #expect(fe.screen == .paused)
        fe.handle(.pause)
        #expect(fe.screen == .paused)
        // Resume is disabled, so the selection is on Options and moving skips Resume.
        #expect(fe.menu?.selectedItem?.command == .options)
        fe.handle(.up)
        fe.handle(.up)
        fe.handle(.up)
        #expect(fe.menu?.selectedItem?.command == .highScores)
    }

    @Test func playIsRefusedWhileClosed() {
        var fe = frontEnd(pose: .closed)
        #expect(fe.menu?.selectedItem?.command == .options)
        // Up skips the disabled Play and wraps to High scores.
        fe.handle(.up)
        #expect(fe.menu?.selectedItem?.command == .highScores)
        fe.handle(.down)
        press(&fe, .activate)
        #expect(fe.screen == .options)
        // Options and back work while closed.
        press(&fe, .back)
        #expect(fe.screen == .title)
    }

    @Test func leftAndRightStepTheSelectedOption() {
        var fe = frontEnd()
        fe.perform(.options)
        while fe.menu?.selectedItem?.command != .option(.gamepadLayout) { fe.handle(.down) }
        #expect(fe.handle(.right) == FrontEnd.CommandResult(accepted: true, effects: [.optionsChanged]))
        #expect(fe.options.gamepadLayout == .swapped)
        fe.handle(.left)
        #expect(fe.options.gamepadLayout == .standard)
        // Left and right do nothing on an item that isn't an option.
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.command == .back)
        #expect(fe.handle(.right) == .ignored)
        press(&fe, .activate)
        #expect(fe.screen == .title)
    }

    @Test func pauseDoesNothingOnOtherScreens() {
        var fe = frontEnd()
        fe.handle(.pause)
        #expect(fe.screen == .title)
    }

    @Test func losingTheControllerPausesPlayButNotMenus() {
        var fe = frontEnd()
        fe.controllerDisconnected()
        #expect(fe.screen == .title)
        press(&fe, .activate)
        fe.controllerDisconnected()
        #expect(fe.screen == .paused)
        #expect(fe.isUnrequestedPause)
    }

    @Test func padActivationWaitsForTheGraceAfterEveryScreenChange() {
        var fe = frontEnd()
        // Straight after launch the title ignores A and B.
        #expect(fe.handle(.activate) == .ignored)
        #expect(fe.screen == .title)
        _ = fe.update(elapsed: 0.2, input: InputState())
        #expect(fe.handle(.activate) == .ignored)
        _ = fe.update(elapsed: 0.2, input: InputState())
        #expect(fe.handle(.activate) == FrontEnd.CommandResult(accepted: true, effects: [.newRun]))
        // Game over: mashing fire at the moment of death doesn't skip the screen.
        let idBefore = fe.screenID
        die(&fe)
        #expect(fe.screenID != idBefore)
        guard case .gameOver = fe.screen else {
            Issue.record("expected game over, got \(fe.screen)")
            return
        }
        #expect(fe.handle(.activate) == .ignored)
        #expect(fe.screenTime == 0)
        // Game over holds off longer than other screens: mashing for a second does nothing.
        #expect(FrontEnd.activationGrace(for: fe.screen) == FrontEnd.gameOverGrace)
        for _ in 0..<10 {
            _ = fe.update(elapsed: 0.1, input: InputState())
            #expect(fe.handle(.activate) == .ignored)
        }
        guard case .gameOver = fe.screen else {
            Issue.record("the game-over summary went away early")
            return
        }
        press(&fe, .activate)
        #expect(fe.screen == .title)
        // Moving the selection is never held back.
        fe.handle(.down)
        #expect(fe.menu?.selectedItem?.command == .options)
    }

    @Test func theCountdownTickingIsNotAScreenChange() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.handle(.pause)
        press(&fe, .pause)
        let id = fe.screenID
        _ = fe.update(elapsed: 0.1, input: InputState())
        _ = fe.update(elapsed: 0.1, input: InputState())
        #expect(fe.screenID == id)
        #expect(abs(fe.screenTime - 0.2) < 1e-9)
    }

    @Test func touchIsHeldBackOnGameOverAndOnAForcedPause() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.setPose(.closed)
        #expect(fe.isUnrequestedPause)
        #expect(!fe.acceptsTouchActivation)
        // A touch on Start over (index 1) straight after closing does nothing.
        #expect(fe.choose(1) == [])
        #expect(fe.screen == .paused)
        _ = fe.update(elapsed: FrontEnd.activationGrace, input: InputState())
        #expect(fe.acceptsTouchActivation)

        // A pause the player asked for takes touches at once.
        var asked = frontEnd()
        press(&asked, .activate)
        asked.requestPause()
        #expect(!asked.isUnrequestedPause)
        #expect(asked.acceptsTouchActivation)

        // Game over holds touches back too; the title doesn't.
        var dead = frontEnd()
        press(&dead, .activate)
        die(&dead)
        #expect(!dead.acceptsTouchActivation)
        #expect(dead.choose(0) == [])
        _ = dead.update(elapsed: 1.0, input: InputState())
        #expect(!dead.acceptsTouchActivation, "game over holds touches for 1.2 s")
        _ = dead.update(elapsed: 0.2, input: InputState())
        dead.choose(0)
        #expect(dead.screen == .title)
        #expect(dead.acceptsTouchActivation)
    }

    @Test func closingWhilePausedRestartsTheGraceOnlyIfThePauseWasForced() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.requestPause()
        _ = fe.update(elapsed: 1, input: InputState())
        let id = fe.screenID
        fe.setPose(.closed)
        // Already on the pause menu: nothing new appeared, and Options is selected, not Start over.
        #expect(fe.screenID == id)
        #expect(fe.menu?.selectedItem?.command == .options)
    }

    @Test func handleSaysWhetherACommandWasAccepted() {
        var fe = frontEnd()
        _ = fe.update(elapsed: 1, input: InputState())
        // Moving: accepted when the selection moved.
        #expect(fe.handle(.down).accepted)
        // Left and right on a plain item change nothing.
        #expect(!fe.handle(.right).accepted)
        // Back with nothing to back out of.
        #expect(!fe.handle(.back).accepted)
        // Pause on the title does nothing.
        #expect(!fe.handle(.pause).accepted)
        // Activate opens Options; back inside the grace is ignored, then accepted.
        #expect(fe.handle(.activate).accepted)
        #expect(!fe.handle(.back).accepted)
        _ = fe.update(elapsed: 0.4, input: InputState())
        #expect(fe.handle(.back).accepted)
        #expect(fe.screen == .title)
        // A menu with a single item: moving is not accepted.
        var dead = frontEnd()
        press(&dead, .activate)
        die(&dead)
        _ = dead.update(elapsed: FrontEnd.gameOverGrace, input: InputState())
        #expect(!dead.handle(.down).accepted)
        #expect(dead.handle(.activate).accepted)
    }

    @Test func continueIsDimmedUntilTheGameOverHoldOffEnds() {
        var fe = frontEnd()
        press(&fe, .activate)
        die(&fe)
        #expect(fe.menu?.items.first?.isEnabled == false)
        #expect(fe.menu?.selectedItem == nil)
        _ = fe.update(elapsed: FrontEnd.gameOverGrace - 0.05, input: InputState())
        #expect(fe.menu?.items.first?.isEnabled == false)
        _ = fe.update(elapsed: 0.1, input: InputState())
        #expect(fe.menu?.items.first?.isEnabled == true)
        #expect(fe.menu?.selectedItem?.command == .proceed)
    }

    @Test func resumeStaysTheDefaultWhenItIsAllowed() {
        var fe = frontEnd()
        press(&fe, .activate)
        fe.setPose(.closed)
        #expect(fe.menu?.selectedItem?.command == .options)
        fe.setPose(.open)
        #expect(fe.menu?.selectedItem?.command == .resume)
    }
}

@Suite struct HapticCueSweepTests {
    @Test func shockwaveIsASweepAndKillsAreLight() {
        #expect(HapticCue.cue(for: .shockwave(at: .zero)) == .sweep)
        #expect(HapticCue.cue(for: .enemyDestroyed(id: 1, kind: .mote, at: .zero, points: 1)) == .tick)
    }
}
