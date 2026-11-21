import GameCore

// Ridgeline plugged into the shared session and screen flow.

/// The session over a Ridgeline run. The names predate the shared session logic and are kept so
/// the app and the tests read as before.
public typealias GameSession = ModeSession<Simulation>
/// The front end over a Ridgeline run.
public typealias FrontEnd = ModeFrontEnd<Simulation>

extension Simulation: ModeRun {
    public init(seed: UInt64, config: Tuning) {
        self.init(seed: seed, tuning: config)
    }

    public var ending: RunEnding? { isGameOver ? .defeated : nil }

    public var result: RunResult { RunResult(score: score, wave: wave, saved: colonistsSaved) }
}

extension ModeSession where Run == Simulation {
    public init(seed: UInt64, tuning: Tuning = Tuning()) {
        self.init(seed: seed, config: tuning)
    }

    public var tuning: Tuning { config }

    /// The current run's simulation.
    public package(set) var simulation: Simulation {
        get { run }
        set { run = newValue }
    }
}

extension ModeDescriptor {
    public static let ridgeline = ModeDescriptor(id: "ridgeline", displayName: "Ridgeline")
}

extension Theme {
    /// The look the shared screens take from this theme.
    public var shellStyle: ShellStyle {
        var sounds: [MenuSound: SoundPatch] = [:]
        for sound in MenuSound.allCases {
            if let patch = menuSound(sound) { sounds[sound] = patch }
        }
        return ShellStyle(background: palette.background, text: palette.hud, highlight: palette.falling,
                          heading: terrain.ridge, controls: palette.controls, menuSounds: sounds)
    }
}
