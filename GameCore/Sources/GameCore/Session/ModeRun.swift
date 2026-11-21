/// One run of a mode's game: what a `ModeSession` steps. Each mode's simulation conforms; the
/// shared session and screen-flow logic know a run only through this.
public protocol ModeRun: Sendable {
    /// The controls for one step.
    associatedtype Input: Sendable
    /// Things that happened in a step, for the app's visuals, sound and haptics.
    associatedtype Event: Sendable
    /// The mode's tuning numbers.
    associatedtype Config: Sendable

    /// Seconds of game time in one step.
    static var timeStep: Double { get }

    init(seed: UInt64, config: Config)

    /// Advances one `timeStep`.
    mutating func step(_ input: Input) -> [Event]

    /// Nil while the run goes on.
    var ending: RunEnding? { get }
    /// The run's score and progress so far (final once `ending` is set).
    var result: RunResult { get }
}

/// Why a run ended.
public enum RunEnding: Sendable, Equatable {
    /// The player lost (out of lives).
    case defeated
    /// The run's goal was met. Free Play runs never end this way; a campaign chapter can.
    case goalMet
}

/// What a run achieved. The same fields as `HighScoreEntry` on purpose: every planned mode has
/// waves and colonists saved.
public struct RunResult: Sendable, Equatable {
    public var score: Int
    /// The wave reached (0 before the first wave starts).
    public var wave: Int
    /// Colonists brought home.
    public var saved: Int

    public init(score: Int, wave: Int, saved: Int) {
        self.score = score
        self.wave = wave
        self.saved = saved
    }
}
