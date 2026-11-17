/// One sitting of the game: the title screen, a run, pausing, and game over. The app drives this
/// and never steps the `Simulation` directly.
///
/// Gameplay needs the playfield (the open inner display). While it is unavailable the session can
/// still be started over, ended or browsed, but it cannot be played or resumed.
public struct GameSession: Sendable {
    public enum Phase: Sendable, Equatable {
        case title
        case playing
        case paused
        /// Counting down to play after a resume.
        case countdown(remaining: Double)
        case gameOver(score: Int)
    }

    /// Seconds between choosing Resume and play starting again.
    public static let resumeCountdown = 3.0
    /// Longest frame the session will simulate, so a stall can't cause a burst of catch-up steps.
    static let maxFrameTime = 0.1

    public let tuning: Tuning
    public private(set) var phase: Phase = .title
    public internal(set) var simulation: Simulation
    public private(set) var isPlayfieldAvailable = true
    /// Final score of the most recent run that ended.
    public private(set) var lastScore: Int?

    private var seed: UInt64
    private var accumulator = 0.0

    /// The seed of the current run's simulation (and its world).
    public var runSeed: UInt64 { seed }

    /// The seed the next new run will use, so its world can be prepared ahead of time.
    public var nextRunSeed: UInt64 {
        seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    public init(seed: UInt64, tuning: Tuning = Tuning()) {
        self.seed = seed
        self.tuning = tuning
        simulation = Simulation(seed: seed, tuning: tuning)
    }

    /// True while a run is in progress, whether playing, paused or counting down.
    public var isInGame: Bool {
        switch phase {
        case .playing, .paused, .countdown: true
        case .title, .gameOver: false
        }
    }

    public var canResume: Bool {
        phase == .paused && isPlayfieldAvailable
    }

    /// Starts a new run from the title or game-over screen. Refused while the playfield is
    /// unavailable.
    @discardableResult
    public mutating func startGame() -> Bool {
        guard isPlayfieldAvailable, !isInGame else { return false }
        newSimulation()
        phase = .playing
        return true
    }

    public mutating func pause() {
        guard phase == .playing || isCountingDown else { return }
        phase = .paused
        accumulator = 0
    }

    /// Begins the countdown back into play. Refused unless paused with the playfield available.
    @discardableResult
    public mutating func resume() -> Bool {
        guard canResume else { return false }
        phase = .countdown(remaining: GameSession.resumeCountdown)
        return true
    }

    /// Throws the current run away and begins again at wave 1. A paused session stays paused, so
    /// this works while the playfield is unavailable.
    public mutating func startOver() {
        switch phase {
        case .paused:
            newSimulation()
        case .playing, .countdown:
            newSimulation()
            phase = .playing
        case .gameOver:
            startGame()
        case .title:
            break
        }
    }

    /// Ends the run and returns to the title screen. Returns the final score, or nil if there was
    /// no run to end.
    @discardableResult
    public mutating func endGame() -> Int? {
        switch phase {
        case .playing, .paused, .countdown:
            lastScore = simulation.score
            phase = .title
            return lastScore
        case .gameOver(let score):
            phase = .title
            return score
        case .title:
            return nil
        }
    }

    /// Tell the session whether the playfield can be used. Losing it pauses at once.
    public mutating func setPlayfieldAvailable(_ available: Bool) {
        isPlayfieldAvailable = available
        if !available {
            pause()
        }
    }

    /// Advances by real elapsed time and returns the events from any simulation steps taken.
    public mutating func update(elapsed: Double, input: InputState) -> [GameEvent] {
        let elapsed = min(max(elapsed, 0), GameSession.maxFrameTime)
        switch phase {
        case .countdown(let remaining):
            let left = remaining - elapsed
            phase = left > 0 ? .countdown(remaining: left) : .playing
            return []

        case .playing:
            accumulator += elapsed
            var events: [GameEvent] = []
            while accumulator >= Simulation.timeStep {
                accumulator -= Simulation.timeStep
                events += simulation.step(input)
                if simulation.isGameOver {
                    lastScore = simulation.score
                    phase = .gameOver(score: simulation.score)
                    accumulator = 0
                    break
                }
            }
            return events

        case .title, .paused, .gameOver:
            return []
        }
    }

    private var isCountingDown: Bool {
        if case .countdown = phase { true } else { false }
    }

    private mutating func newSimulation() {
        // A different but reproducible seed for each run.
        seed = nextRunSeed
        simulation = Simulation(seed: seed, tuning: tuning)
        accumulator = 0
    }
}
