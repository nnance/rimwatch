import GameCore

/// What the player is asking for this step, whichever device it came from.
public struct RedoubtInput: Sendable, Equatable {
    /// Movement stick, each axis -1...1, y up. Its length is the speed asked for (capped at 1).
    public var move: Vec2
    /// Aim stick, each axis -1...1. The orb fires along it while its length is past the tuning's
    /// `aimThreshold`; there is no fire button.
    public var aim: Vec2
    /// True while the button is down. The run acts once per press.
    public var shockwave: Bool

    public init(move: Vec2 = .zero, aim: Vec2 = .zero, shockwave: Bool = false) {
        self.move = move
        self.aim = aim
        self.shockwave = shockwave
    }
}
