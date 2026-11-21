/// Where a session is: the title screen, a run, pausing, and game over.
public enum SessionPhase: Sendable, Equatable {
    case title
    case playing
    case paused
    /// Counting down to play after a resume.
    case countdown(remaining: Double)
    case gameOver(score: Int)
}

/// One sitting of a mode's game: the title screen, a run, pausing, and game over. The app drives
/// this and never steps the run directly.
///
/// Gameplay needs the playfield (the open inner display). While it is unavailable the session can
/// still be started over, ended or browsed, but it cannot be played or resumed.
///
/// `update` and the properties it touches are `@inlinable`, with their storage behind
/// `@usableFromInline` names, so the per-frame path is specialised for each mode's run in the
/// mode's module and the app instead of going through the generic run's witness table.
public struct ModeSession<Run: ModeRun>: Sendable {
    public typealias Phase = SessionPhase

    /// Seconds between choosing Resume and play starting again.
    public static var resumeCountdown: Double { 3.0 }
    /// Longest frame the session will simulate, so a stall can't cause a burst of catch-up steps.
    @inlinable static var maxFrameTime: Double { 0.1 }

    public let config: Run.Config
    @inlinable public var phase: SessionPhase { _phase }
    public package(set) var run: Run {
        @inlinable get { _run }
        set { _run = newValue }
    }
    public private(set) var isPlayfieldAvailable = true
    /// Final score of the most recent run that ended.
    @inlinable public var lastScore: Int? { _lastScore }
    /// What the most recent run that ended achieved (by game over or by End game).
    @inlinable public var lastResult: RunResult? { _lastResult }
    /// How the most recent run that ended did so, or nil if the player ended it (End game).
    @inlinable public var lastEnding: RunEnding? { _lastEnding }
    /// Run steps taken since the session began, across runs. It only ever goes up, so the app
    /// can tell whether a frame reached a step.
    @inlinable public var stepCount: Int { _stepCount }

    @usableFromInline var _phase: SessionPhase = .title
    @usableFromInline var _run: Run
    @usableFromInline var _lastScore: Int?
    @usableFromInline var _lastResult: RunResult?
    @usableFromInline var _lastEnding: RunEnding?
    @usableFromInline var _stepCount = 0
    @usableFromInline var accumulator = 0.0
    private var seed: UInt64

    /// The seed of the current run (and its world).
    public var runSeed: UInt64 { seed }

    /// The seed the next new run will use, so its world can be prepared ahead of time.
    public var nextRunSeed: UInt64 {
        seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    public init(seed: UInt64, config: Run.Config) {
        self.seed = seed
        self.config = config
        _run = Run(seed: seed, config: config)
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
        newRun()
        _phase = .playing
        return true
    }

    public mutating func pause() {
        guard phase == .playing || isCountingDown else { return }
        _phase = .paused
        accumulator = 0
    }

    /// Begins the countdown back into play. Refused unless paused with the playfield available.
    @discardableResult
    public mutating func resume() -> Bool {
        guard canResume else { return false }
        _phase = .countdown(remaining: Self.resumeCountdown)
        return true
    }

    /// Throws the current run away and begins again at wave 1. A paused session stays paused, so
    /// this works while the playfield is unavailable.
    public mutating func startOver() {
        switch phase {
        case .paused:
            newRun()
        case .playing, .countdown:
            newRun()
            _phase = .playing
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
            let result = run.result
            _lastScore = result.score
            _lastResult = result
            _lastEnding = nil
            _phase = .title
            return lastScore
        case .gameOver(let score):
            _phase = .title
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

    /// Advances by real elapsed time and returns the events from any run steps taken.
    @inlinable
    public mutating func update(elapsed: Double, input: Run.Input) -> [Run.Event] {
        let elapsed = min(max(elapsed, 0), Self.maxFrameTime)
        switch _phase {
        case .countdown(let remaining):
            let left = remaining - elapsed
            _phase = left > 0 ? .countdown(remaining: left) : .playing
            return []

        case .playing:
            accumulator += elapsed
            var events: [Run.Event] = []
            while accumulator >= Run.timeStep {
                accumulator -= Run.timeStep
                events += _run.step(input)
                _stepCount &+= 1
                if let ending = _run.ending {
                    let result = _run.result
                    _lastScore = result.score
                    _lastResult = result
                    _lastEnding = ending
                    _phase = .gameOver(score: result.score)
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

    private mutating func newRun() {
        // A different but reproducible seed for each run.
        seed = nextRunSeed
        _run = Run(seed: seed, config: config)
        accumulator = 0
    }
}
