import Testing
import GameCore
@testable import RedoubtCore

let still = RedoubtInput()

/// A run with no waves, mid-fight with the airlock open, so a test can place exactly what it
/// needs. The orb is at the centre (450, 300).
func quietRun(seed: UInt64 = 7) -> RedoubtRun {
    var run = RedoubtRun(seed: seed)
    run.wavesEnabled = false
    run.phase = .fighting
    run.airlock = Airlock(wall: .east, pos: Vec2(900, 300), width: 56, isOpen: true)
    return run
}

/// Steps until `stop` matches an event or `maxSteps` is reached. Returns every event seen.
@discardableResult
func run(
    _ run: inout RedoubtRun,
    steps maxSteps: Int,
    input: RedoubtInput = still,
    until stop: (RedoubtEvent) -> Bool = { _ in false }
) -> [RedoubtEvent] {
    var seen: [RedoubtEvent] = []
    for _ in 0..<maxSteps {
        let events = run.step(input)
        seen += events
        if events.contains(where: stop) { break }
    }
    return seen
}

func seconds(_ s: Double) -> Int { Int((s * 120).rounded()) }

extension RedoubtRun {
    /// Adds a sheltering colonist and counts them in the wave.
    @discardableResult
    mutating func addColonist(at p: Vec2) -> Int {
        let id = takeID()
        colonists.append(RedoubtColonist(id: id, pos: p))
        waveColonists += 1
        return id
    }

    /// Puts `count` colonists in the orb's line, strung out to its left.
    @discardableResult
    mutating func formLine(_ count: Int) -> [Int] {
        var ids: [Int] = []
        for slot in 0..<count {
            let id = addColonist(at: orb.pos - Vec2(tuning.lineSpacing * Double(slot + 1), 0))
            colonists[colonists.count - 1].state = .following
            line.append(id)
            ids.append(id)
        }
        return ids
    }

    func index(of id: Int) -> Int { enemies.firstIndex { $0.id == id }! }

    /// The enemy with this id; a missing one fails the test instead of crashing the run.
    func req(enemy id: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> RedoubtEnemy {
        try #require(enemy(id), "enemy \(id) is gone", sourceLocation: sourceLocation)
    }

    /// The colonist with this id; a missing one fails the test instead of crashing the run.
    func req(colonist id: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> RedoubtColonist {
        try #require(colonist(id), "colonist \(id) is gone", sourceLocation: sourceLocation)
    }
}

extension RedoubtEvent {
    /// The case name without its payload, e.g. "enemyDestroyed".
    var kind: String {
        let text = String(describing: self)
        return String(text.prefix { $0 != "(" })
    }

    var isOrbFired: Bool { if case .orbFired = self { true } else { false } }
    var isOrbDestroyed: Bool { if case .orbDestroyed = self { true } else { false } }
    var isEnemyDestroyed: Bool { if case .enemyDestroyed = self { true } else { false } }
    var isHuskFormed: Bool { if case .huskFormed = self { true } else { false } }
    var isWaveStarted: Bool { if case .waveStarted = self { true } else { false } }
    var isWaveCleared: Bool { if case .waveCleared = self { true } else { false } }
    var isGameOver: Bool { if case .gameOver = self { true } else { false } }
    var isColonistDelivered: Bool { if case .colonistDelivered = self { true } else { false } }
}

func count(_ events: [RedoubtEvent], _ kind: String) -> Int {
    events.count { $0.kind == kind }
}
