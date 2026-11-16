@testable import GameCore

let idle = InputState()

/// A simulation with no waves, so a test can place exactly the enemies it needs.
func quietSimulation(seed: UInt64 = 7) -> Simulation {
    var sim = Simulation(seed: seed)
    sim.wavesEnabled = false
    return sim
}

/// Steps until `stop` matches an event or `maxSteps` is reached. Returns every event seen.
@discardableResult
func run(
    _ sim: inout Simulation,
    maxSteps: Int,
    input: InputState = idle,
    until stop: (GameEvent) -> Bool = { _ in false }
) -> [GameEvent] {
    var seen: [GameEvent] = []
    for _ in 0..<maxSteps {
        let events = sim.step(input)
        seen += events
        if events.contains(where: stop) { break }
    }
    return seen
}

extension GameEvent {
    /// The case name without its payload, e.g. "enemyDestroyed".
    var kind: String {
        let text = String(describing: self)
        return String(text.prefix { $0 != "(" })
    }

    var isPlayerFired: Bool { if case .playerFired = self { true } else { false } }
    var isPlayerDestroyed: Bool { if case .playerDestroyed = self { true } else { false } }
    var isEnemyDestroyed: Bool { if case .enemyDestroyed = self { true } else { false } }
    var isHuskFormed: Bool { if case .huskFormed = self { true } else { false } }
    var isColonistGrabbed: Bool { if case .colonistGrabbed = self { true } else { false } }
    var isColonistDropped: Bool { if case .colonistDropped = self { true } else { false } }
    var isColonistCaught: Bool { if case .colonistCaught = self { true } else { false } }
    var isColonistDelivered: Bool { if case .colonistDelivered = self { true } else { false } }
    var isColonistLanded: Bool { if case .colonistLanded = self { true } else { false } }
    var isColonistLost: Bool { if case .colonistLost = self { true } else { false } }
    var isGameOver: Bool { if case .gameOver = self { true } else { false } }
}
