import GameCore

/// Ridgeline's gamepad controls: which face button fires, Blinks or sends a Shockwave, and the
/// `InputState` a pad produces. The mode-independent pad logic is in `GameCore/Gamepad.swift`.

extension PadMapping {
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

extension PadReader {
    /// Gameplay input now: the buttons held, plus any pressed since the last simulation step.
    public func input(layout: GameOptions.GamepadLayout) -> InputState {
        PadMapping.input(move: PadMapping.move(current), held: playButtons, layout: layout)
    }
}
