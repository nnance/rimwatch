import GameCore

/// A stand-in run for the shared session tests: each step counts, scores 10 points and echoes its
/// input as the event. It ends after `endAfter` steps, the way its config says.
struct CountingRun: ModeRun {
    struct Config: Sendable, Equatable {
        var endAfter: Int
        var ending: RunEnding = .goalMet
        var savedEvery = 3
    }

    /// A power of two, so step counts come out exact.
    static let timeStep = 1.0 / 32

    let seed: UInt64
    let config: Config
    var steps = 0

    init(seed: UInt64, config: Config) {
        self.seed = seed
        self.config = config
    }

    mutating func step(_ input: Int) -> [Int] {
        steps += 1
        return [input]
    }

    var ending: RunEnding? { steps >= config.endAfter ? config.ending : nil }

    var result: RunResult {
        RunResult(score: steps * 10, wave: steps / 10, saved: steps / config.savedEvery)
    }
}

typealias CountingSession = ModeSession<CountingRun>
typealias CountingFrontEnd = ModeFrontEnd<CountingRun>
