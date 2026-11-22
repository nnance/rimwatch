import GameCore

/// What the player is asking for this step, whichever device it came from.
public struct RiftwingInput: Sendable, Equatable {
    /// The steering stick, each axis -1...1, y up. Its x steers; pulled down past the tuning's
    /// `diveStickThreshold` it dives (touch has no dive button).
    public var stick: Vec2
    /// True while the flap control is down. The rig flaps once per press, never by holding.
    public var flap: Bool
    /// True while a dive button is held (gamepad B). The stick pulled down dives too.
    public var dive: Bool

    public init(stick: Vec2 = .zero, flap: Bool = false, dive: Bool = false) {
        self.stick = stick
        self.flap = flap
        self.dive = dive
    }

    /// The steer, -1...1.
    public var steer: Double { clamp(stick.x, -1, 1) }

    /// True when this input asks for a dive under `tuning`.
    public func wantsDive(_ tuning: RiftwingTuning) -> Bool {
        dive || stick.y <= -tuning.diveStickThreshold
    }
}
