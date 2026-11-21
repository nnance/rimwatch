import GameCore

// Redoubt plugged into the shared session and screen flow.

/// The session over a Redoubt run.
public typealias RedoubtSession = ModeSession<RedoubtRun>
/// The front end over a Redoubt run.
public typealias RedoubtFrontEnd = ModeFrontEnd<RedoubtRun>

extension RedoubtRun: ModeRun {
    public init(seed: UInt64, config: RedoubtTuning) {
        self.init(seed: seed, tuning: config)
    }

    public var ending: RunEnding? { isGameOver ? .defeated : nil }

    /// Score, the wave reached, and colonists saved (delivered, or safe when their wave cleared).
    public var result: RunResult { RunResult(score: score, wave: wave, saved: colonistsSaved) }
}

extension ModeSession where Run == RedoubtRun {
    public init(seed: UInt64, tuning: RedoubtTuning = RedoubtTuning()) {
        self.init(seed: seed, config: tuning)
    }

    public var tuning: RedoubtTuning { config }
}

extension ModeDescriptor {
    /// Twin sticks: no gamepad button layout to choose.
    public static let redoubt = ModeDescriptor(id: "redoubt", displayName: "Redoubt",
                                               summary: "Hold the dome floor and lead colonists out",
                                               optionRows: [.soundVolume, .musicVolume, .haptics, .handedness])
}
