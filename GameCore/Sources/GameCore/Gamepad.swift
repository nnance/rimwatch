/// Gamepad logic that doesn't depend on any controller framework. The app reads a physical (or,
/// in debug builds, a simulated) controller into a `PadSnapshot`; everything from there on, the
/// stick dead zone, merging the D-pad with the stick, which face button does what, press edges
/// and menu navigation with hold-to-repeat, happens here.

/// The face buttons and the menu button, named by position on an extended gamepad.
public enum PadButton: String, Sendable, Hashable, CaseIterable {
    /// The bottom face button.
    case a
    /// The right face button.
    case b
    /// The left face button.
    case x
    /// The top face button.
    case y
    /// The menu (start) button.
    case menu
}

/// The state of a controller at one moment.
public struct PadSnapshot: Sendable, Equatable {
    /// Left thumbstick, each axis -1...1, up and right positive. Raw: no dead zone applied.
    public var stick: Vec2
    /// D-pad, each axis -1, 0 or 1 (an analogue D-pad may report values in between).
    public var dpad: Vec2
    /// The buttons held down.
    public var buttons: Set<PadButton>

    public init(stick: Vec2 = .zero, dpad: Vec2 = .zero, buttons: Set<PadButton> = []) {
        self.stick = stick
        self.dpad = dpad
        self.buttons = buttons
    }

    public static let neutral = PadSnapshot()

    public func isDown(_ button: PadButton) -> Bool { buttons.contains(button) }
}

/// How pad state becomes gameplay input.
public enum PadMapping {
    /// Stick deflection below this reads as centred. Worn sticks rest a little off centre.
    public static let deadZone = 0.18

    /// The stick with a radial dead zone, rescaled so movement starts at zero just outside it and
    /// still reaches full deflection at the rim.
    public static func stick(_ raw: Vec2, deadZone: Double = deadZone) -> Vec2 {
        let length = raw.length
        guard length > deadZone else { return .zero }
        let clamped = min(length, 1)
        let scaled = (clamped - deadZone) / (1 - deadZone)
        return Vec2(raw.x / length * scaled, raw.y / length * scaled)
    }

    /// Flight from the stick and the D-pad together: each axis takes whichever has the larger
    /// deflection, so either can fly the ship and neither cancels the other. Length capped at 1.
    public static func move(_ snapshot: PadSnapshot) -> Vec2 {
        let stick = stick(snapshot.stick)
        let dpad = Vec2(clamp(snapshot.dpad.x, -1, 1), clamp(snapshot.dpad.y, -1, 1))
        func pick(_ s: Double, _ d: Double) -> Double { abs(d) > abs(s) ? d : s }
        return Vec2(pick(stick.x, dpad.x), pick(stick.y, dpad.y)).clampedToUnit
    }

    /// The button that does `action` in a layout. Fire is always A.
    public static func button(for action: PadAction, layout: GameOptions.GamepadLayout) -> PadButton {
        switch (action, layout) {
        case (.fire, _): .a
        case (.blink, .standard), (.shockwave, .swapped): .b
        case (.shockwave, .standard), (.blink, .swapped): .x
        }
    }

    /// Gameplay input for buttons that are `held` (or were pressed since the last step).
    public static func input(move: Vec2, held: Set<PadButton>, layout: GameOptions.GamepadLayout) -> InputState {
        InputState(
            move: move,
            fire: held.contains(button(for: .fire, layout: layout)),
            shockwave: held.contains(button(for: .shockwave, layout: layout)),
            blink: held.contains(button(for: .blink, layout: layout))
        )
    }
}

/// The gameplay actions a face button can be given.
public enum PadAction: Sendable, Hashable, CaseIterable {
    case fire, blink, shockwave
}

/// A device-neutral menu command: from a gamepad, or from the debug notifications.
public enum MenuCommand: String, Sendable, Hashable, CaseIterable {
    case up, down, left, right, activate, back, pause
}

/// Follows one controller from snapshot to snapshot. Snapshots arrive whenever the controller
/// changes (several can arrive between two frames); presses are latched so a tap that starts and
/// ends between frames is still seen, once by gameplay and once by the menus.
public struct PadReader: Sendable {
    public private(set) var current = PadSnapshot.neutral
    /// Buttons pressed since gameplay last stepped.
    private var playLatched: Set<PadButton> = []
    /// Buttons pressed since the menus last looked.
    private var pressEdges: Set<PadButton> = []
    private var directions = MenuDirectionTracker()
    /// Buttons gameplay ignores until they have been let go once: they were down when a menu
    /// activation started play (the A that chose Play or Resume is not also a shot).
    private var suppressed: Set<PadButton> = []

    public init() {}

    /// A new controller state. Buttons that went down are latched.
    public mutating func receive(_ snapshot: PadSnapshot) {
        let pressed = snapshot.buttons.subtracting(current.buttons)
        // Letting go of a suppressed button frees it.
        suppressed.formIntersection(snapshot.buttons)
        playLatched.formUnion(pressed)
        pressEdges.formUnion(pressed)
        directions.receive(dpad: snapshot.dpad, stick: snapshot.stick)
        current = snapshot
    }

    /// The controller went away: forget everything it was holding.
    public mutating func reset() {
        self = PadReader()
    }

    /// Gameplay input now: the buttons held, plus any pressed since the last simulation step.
    public func input(layout: GameOptions.GamepadLayout) -> InputState {
        var held = current.buttons
        if !playLatched.isEmpty { held.formUnion(playLatched) }
        if !suppressed.isEmpty { held.subtract(suppressed) }
        return PadMapping.input(move: PadMapping.move(current), held: held, layout: layout)
    }

    /// A menu activation is starting play (Play chosen, Resume chosen): any button down now is
    /// ignored by gameplay until it has been let go, and presses latched so far are dropped.
    /// Not for the end of the countdown: a button pressed during the countdown is meant for play.
    public mutating func suppressHeldButtons() {
        suppressed = current.buttons
        playLatched.removeAll()
    }

    /// A new screen or menu appeared: presses and pushes made before it are dropped, and a
    /// direction still held doesn't move its selection until it is let go or changed.
    public mutating func screenChanged() {
        pressEdges.removeAll()
        directions.ignoreHeld()
    }

    /// Call after a frame in which the simulation stepped: latched presses have been delivered.
    public mutating func consumePlayPresses() {
        playLatched.removeAll()
    }

    /// The menu button was pressed since the last call. Clears that press. For use during play,
    /// where only the menu button means anything to the menus.
    public mutating func takePausePress() -> Bool {
        let pressed = pressEdges.contains(.menu)
        pressEdges.removeAll()
        directions.ignoreHeld()
        return pressed
    }

    /// Menu commands for a frame of `elapsed` seconds: a step for each new push of the stick or
    /// D-pad (and hold-to-repeat), A to activate, B to go back, the menu button to pause or
    /// resume. Clears the presses it reports.
    public mutating func menuCommands(elapsed: Double) -> [MenuCommand] {
        var commands = directions.steps(elapsed: elapsed).map(\.command)
        if pressEdges.contains(.a) { commands.append(.activate) }
        if pressEdges.contains(.b) { commands.append(.back) }
        if pressEdges.contains(.menu) { commands.append(.pause) }
        pressEdges.removeAll()
        return commands
    }
}

/// A direction in a menu.
public enum MenuDirection: Sendable, Hashable {
    case up, down, left, right

    public var command: MenuCommand {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }

    /// The stick must pass this to count as a direction in a menu...
    public static let stickPress = 0.55
    /// ...and fall below this to let go, so a stick resting near the threshold doesn't chatter.
    public static let stickRelease = 0.35
    /// A D-pad axis counts as pressed at this deflection (an analogue D-pad reports in between).
    public static let dpadPress = 0.5
    /// On a diagonal, the other axis must beat the held one by this much to take over, so a
    /// thumb resting near 45 degrees doesn't flip between the two directions.
    public static let axisSwitchMargin = 0.2
    /// A stick push counts as left or right only when its horizontal part is this many times its
    /// vertical part (within about 27 degrees of horizontal). Anything more diagonal is up or
    /// down: moving the selection by mistake is harmless, changing an option's value is not.
    public static let horizontalDominance = 2.0

    /// How far `v` pushes along a direction (negative when pushing the other way).
    static func along(_ v: Vec2, _ direction: MenuDirection) -> Double {
        switch direction {
        case .up: v.y
        case .down: -v.y
        case .right: v.x
        case .left: -v.x
        }
    }

    /// Deflection on the axis that `direction` is not on.
    static func across(_ v: Vec2, _ direction: MenuDirection) -> Double {
        switch direction {
        case .up, .down: abs(v.x)
        case .left, .right: abs(v.y)
        }
    }

    /// The D-pad's direction. A fresh diagonal picks the stronger axis (vertical on a tie, since
    /// menus are lists); a direction already held (`previous`) keeps winning while its button
    /// stays down, so rolling onto a diagonal and back doesn't change it.
    static func dpad(_ dpad: Vec2, previous: MenuDirection? = nil) -> MenuDirection? {
        if let previous, along(dpad, previous) >= dpadPress { return previous }
        return axis(dpad, threshold: dpadPress)
    }

    /// The stick's direction: pushed past `stickPress`, or still past `stickRelease` in the
    /// direction it was already held (`previous`), unless the other axis has clearly taken over.
    /// A fresh diagonal reads as vertical unless it is clearly horizontal.
    static func stick(_ stick: Vec2, previous: MenuDirection? = nil) -> MenuDirection? {
        if let previous {
            let held = along(stick, previous)
            let across = across(stick, previous)
            let overtaken = switch previous {
            // Turning to left or right needs a clearly horizontal stick, from any direction.
            case .up, .down: across >= held * horizontalDominance
            case .left, .right: across >= held + axisSwitchMargin
            }
            if held >= stickRelease, !overtaken { return previous }
        }
        guard stick.length >= stickPress else { return nil }
        if abs(stick.x) >= abs(stick.y) * horizontalDominance { return stick.x > 0 ? .right : .left }
        return stick.y > 0 ? .up : .down
    }

    /// The direction a snapshot is pushing: the D-pad first, then the stick with hysteresis.
    /// `previous` is the direction currently held, which the stick keeps until it falls below
    /// `stickRelease`.
    public static func of(_ snapshot: PadSnapshot, previous: MenuDirection?) -> MenuDirection? {
        dpad(snapshot.dpad, previous: previous) ?? stick(snapshot.stick, previous: previous)
    }

    private static func axis(_ v: Vec2, threshold: Double) -> MenuDirection? {
        if abs(v.y) >= abs(v.x) {
            guard abs(v.y) >= threshold, v.y != 0 else { return nil }
            return v.y > 0 ? .up : .down
        }
        guard abs(v.x) >= threshold else { return nil }
        return v.x > 0 ? .right : .left
    }
}

/// Menu steps from two direction sources, the D-pad and the stick.
///
/// - A step happens on each new push of either source (a direction appearing, or changing), even
///   one that begins and ends between frames, and otherwise only by hold-to-repeat.
/// - The D-pad keeps its direction while that button stays down, so rolling onto a diagonal and
///   back is not a new push; letting the held button go while another stays down is a turn,
///   and steps at once.
/// - One source pushed the way the other is already holding is not a new push (the stick and
///   the D-pad pushed together give one step).
/// - The most recently pushed source that is still held supplies the direction that repeats:
///   after `initialDelay`, then every `interval`.
/// - Letting go of a source never steps. If the other source is still held, it takes over the
///   repeat, starting again from the full `initialDelay`.
public struct MenuDirectionTracker: Sendable {
    public static let initialDelay = 0.38
    public static let interval = 0.11

    public enum Source: Sendable, Hashable { case dpad, stick }

    private var dpad: MenuDirection?
    private var stick: MenuDirection?
    /// Sources held when a screen appeared: they don't repeat until let go or changed.
    private var ignored: Set<Source> = []
    /// Steps from pushes since the last look.
    private var pushes: [MenuDirection] = []
    /// The source supplying the repeat, and its timer.
    private var repeatSource: Source?
    private var timer = 0.0
    /// The repeat (re)started since the last look; that frame's elapsed time came before it.
    private var restarted = false

    public init() {}

    /// The direction repeating now, if any.
    public var held: MenuDirection? { repeatSource.flatMap(direction) }

    private func direction(_ source: Source) -> MenuDirection? {
        guard !ignored.contains(source) else { return nil }
        return source == .dpad ? dpad : stick
    }

    public mutating func receive(dpad dpadValue: Vec2, stick stickValue: Vec2) {
        let newDpad = MenuDirection.dpad(dpadValue, previous: dpad)
        let newStick = MenuDirection.stick(stickValue, previous: stick)
        let heldBefore = (dpad: direction(.dpad), stick: direction(.stick))
        let changes: [(Source, MenuDirection?, MenuDirection?)] = [(.dpad, dpad, newDpad), (.stick, stick, newStick)]
        dpad = newDpad
        stick = newStick
        var pushedNow: Set<MenuDirection> = []
        for (source, oldDirection, new) in changes {
            if new == nil { ignored.remove(source) }
            guard let new, new != oldDirection else { continue }
            ignored.remove(source)
            let other: Source = source == .dpad ? .stick : .dpad
            // The other source already holds this way, or pushed it in this same update.
            let otherHeld = other == .dpad ? heldBefore.dpad : heldBefore.stick
            let duplicate = pushedNow.contains(new) || otherHeld == new
            if duplicate {
                // A changed direction without a step: if this source supplies the repeat, the
                // repeat waits the full delay again rather than stepping the new way at once.
                if repeatSource == source { startRepeat(source) }
                continue
            }
            // A new push: one step now, and this source takes over the repeat.
            pushedNow.insert(new)
            pushes.append(new)
            startRepeat(source)
        }
        // The repeating source was let go: the other one, if held, takes over from scratch.
        if let source = repeatSource, direction(source) == nil {
            let other: Source = source == .dpad ? .stick : .dpad
            if direction(other) != nil { startRepeat(other) } else { repeatSource = nil }
        }
    }

    private mutating func startRepeat(_ source: Source) {
        repeatSource = source
        timer = Self.initialDelay
        restarted = true
    }

    /// Steps for a frame of `elapsed` seconds: the pushes since the last call, then the repeat.
    public mutating func steps(elapsed: Double) -> [MenuDirection] {
        var steps = pushes
        pushes.removeAll()
        if let held {
            if restarted {
                restarted = false
            } else {
                timer -= elapsed
                if timer <= 0 {
                    steps.append(held)
                    // Never more than one repeat a frame, even after a long frame.
                    timer = max(timer + Self.interval, Self.interval * 0.5)
                }
            }
        }
        restarted = false
        return steps
    }

    /// Drops pushes not yet looked at, and ignores whatever is held now until it is let go or
    /// changed (a menu appearing under a thumb still pushing).
    public mutating func ignoreHeld() {
        pushes.removeAll()
        if dpad != nil { ignored.insert(.dpad) }
        if stick != nil { ignored.insert(.stick) }
        repeatSource = nil
    }
}
