import GameCore

/// Riftwing's gamepad controls: the left stick or D-pad steers (down dives), A or either
/// shoulder button flaps (once per press), B dives while held. The other buttons do nothing in
/// play. The mode-independent pad logic is in `GameCore/Gamepad.swift`.
extension RiftwingInput {
    /// The buttons that flap.
    public static let flapButtons: Set<PadButton> = [.a, .leftShoulder, .rightShoulder]
    /// The buttons that dive while held.
    public static let diveButtons: Set<PadButton> = [.b]

    /// Gameplay input from a pad's movement (dead zone already applied) and the buttons `held`
    /// (or pressed since the last step).
    public init(move: Vec2, held: Set<PadButton>) {
        self.init(stick: move, flap: !held.isDisjoint(with: Self.flapButtons),
                  dive: !held.isDisjoint(with: Self.diveButtons))
    }

    /// Gameplay input from a pad now: the buttons held, plus any pressed since the last step.
    public init(pad reader: PadReader) {
        self.init(move: PadMapping.move(reader.current), held: reader.playButtons)
    }
}
