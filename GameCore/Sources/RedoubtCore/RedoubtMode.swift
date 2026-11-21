import GameCore

// Redoubt plugged into the shared session and screen flow.

/// The session over a Redoubt run.
public typealias RedoubtSession = ModeSession<RedoubtRun>
/// The front end over a Redoubt run.
public typealias RedoubtFrontEnd = ModeFrontEnd<RedoubtRun>

extension RedoubtRun: ModeRun {
    /// What a session builds each run from: the tuning numbers, and in DEBUG builds a switch for
    /// testing.
    public struct Config: Sendable {
        public var tuning: RedoubtTuning
        #if DEBUG
        /// DEBUG only: wave n begins under a power cut, as if every colonist had been lost in wave
        /// n-1 (pending through the break before it), whatever the bot or the balance. Until then
        /// the run plays exactly as without it. The app sets it from `-powerCutAtWave <n>`.
        public var powerCutAtWave: Int?
        #endif

        public init(tuning: RedoubtTuning = RedoubtTuning()) {
            self.tuning = tuning
        }
    }

    public init(seed: UInt64, config: Config) {
        self.init(seed: seed, tuning: config.tuning)
        #if DEBUG
        forcedPowerCutWave = config.powerCutAtWave
        // A cut forced at wave 1 is pending from the start, as if lost in a wave before it.
        if config.powerCutAtWave == 1 { powerCutPending = true }
        #endif
    }

    public var ending: RunEnding? { isGameOver ? .defeated : nil }

    /// Score, the wave reached, and colonists saved (delivered, or safe when their wave cleared).
    public var result: RunResult { RunResult(score: score, wave: wave, saved: colonistsSaved) }
}

extension ModeSession where Run == RedoubtRun {
    public init(seed: UInt64, tuning: RedoubtTuning = RedoubtTuning()) {
        self.init(seed: seed, config: RedoubtRun.Config(tuning: tuning))
    }

    public var tuning: RedoubtTuning { config.tuning }
}

extension ModeDescriptor {
    /// Twin sticks: no gamepad button layout to choose.
    public static let redoubt = ModeDescriptor(id: "redoubt", displayName: "Redoubt",
                                               summary: "Hold the dome floor and lead colonists out",
                                               optionRows: [.soundVolume, .musicVolume, .haptics, .handedness])
}
