import GameCore

/// Redoubt's gamepad controls: the left stick or D-pad moves, the right stick aims (and fires
/// while pushed), either shoulder button sends a Shockwave. The face buttons and triggers do
/// nothing in play. The mode-independent pad logic is in `GameCore/Gamepad.swift`.
extension RedoubtInput {
    /// The buttons that send a Shockwave.
    public static let shockwaveButtons: Set<PadButton> = [.leftShoulder, .rightShoulder]

    /// Gameplay input from a pad's movement, aim (dead zone already applied) and the buttons
    /// `held` (or pressed since the last step).
    public init(move: Vec2, aim: Vec2, held: Set<PadButton>) {
        self.init(move: move, aim: aim, shockwave: !held.isDisjoint(with: Self.shockwaveButtons))
    }

    /// Gameplay input from a pad now: the buttons held, plus any pressed since the last step.
    public init(pad reader: PadReader) {
        self.init(move: PadMapping.move(reader.current), aim: reader.rightStick, held: reader.playButtons)
    }
}
