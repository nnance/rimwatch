/// What the player is asking for this frame, whichever device it came from.
public struct InputState: Sendable, Equatable {
    /// Stick position: x is thrust left or right, y is climb or dive. Each axis is -1...1.
    public var move: Vec2
    /// Held to fire continuously.
    public var fire: Bool
    /// True while the button is down. The simulation acts once per press.
    public var shockwave: Bool
    /// True while the button is down. The simulation acts once per press.
    public var blink: Bool

    public init(move: Vec2 = .zero, fire: Bool = false, shockwave: Bool = false, blink: Bool = false) {
        self.move = move
        self.fire = fire
        self.shockwave = shockwave
        self.blink = blink
    }
}
