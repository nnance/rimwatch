import GameCore

// Riftwing plugged into the shared session and screen flow.

/// The session over a Riftwing run.
public typealias RiftwingSession = ModeSession<RiftwingRun>
/// The front end over a Riftwing run.
public typealias RiftwingFrontEnd = ModeFrontEnd<RiftwingRun>

extension RiftwingRun: ModeRun {
    /// What a session builds each run from: the tuning numbers and wave makeup, and in DEBUG
    /// builds switches for testing states no bot reaches by play.
    public struct Config: Sendable {
        public var tuning: RiftwingTuning
        public var waves: RiftwingWaves
        #if DEBUG
        /// DEBUG only: wave n begins with the lamps out, as if every colonist had been lost in
        /// wave n-1 (pending through the break before it). Until then the run plays exactly as
        /// without it. The app can set it from a launch argument.
        public var lampsOutAtWave: Int?
        /// DEBUG only: the run's first wave is this one (its layout, opponents and eases), with
        /// the score at 0. For looking at later waves without playing through them.
        public var startAtWave: Int?
        /// DEBUG only: the Rift's first breath comes this many seconds into every wave.
        public var breathAfter: Double?
        #endif

        public init(tuning: RiftwingTuning = RiftwingTuning(), waves: RiftwingWaves = RiftwingWaves()) {
            self.tuning = tuning
            self.waves = waves
        }
    }

    public init(seed: UInt64, config: Config) {
        var tuning = config.tuning
        #if DEBUG
        if let after = config.breathAfter { tuning.breathAfter = after }
        #endif
        self.init(seed: seed, tuning: tuning, waves: config.waves)
        #if DEBUG
        forcedLampsOutWave = config.lampsOutAtWave
        // Lamps forced out at wave 1 are pending from the start, as if lost in a wave before it.
        if config.lampsOutAtWave == 1 { lampsOutPending = true }
        if let start = config.startAtWave, start > 1 { skipToWave(start) }
        #endif
    }

    public var ending: RunEnding? { isGameOver ? .defeated : nil }

    /// Score, the wave reached, and colonists saved (freed from pods).
    public var result: RunResult { RunResult(score: score, wave: wave, saved: colonistsSaved) }
}

extension ModeSession where Run == RiftwingRun {
    public init(seed: UInt64, tuning: RiftwingTuning = RiftwingTuning()) {
        self.init(seed: seed, config: RiftwingRun.Config(tuning: tuning))
    }

    public var tuning: RiftwingTuning { config.tuning }
}

extension ModeDescriptor {
    /// Steer and flap: no gamepad button layout to choose. The stick side option swaps the
    /// steering stick and the flap side.
    public static let riftwing = ModeDescriptor(id: "riftwing", displayName: "Riftwing",
                                                summary: "Win by height in the Rift caves",
                                                optionRows: [.soundVolume, .musicVolume, .haptics, .handedness])
}
