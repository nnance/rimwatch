import Testing
import GameCore
@testable import RiftwingCore

let still = RiftwingInput()
let flapPress = RiftwingInput(flap: true)

/// A run with no waves, mid-fight, so a test can place exactly what it needs. The rider stands
/// on the first layout's start ledge (x 425, top 250).
func quietRun(seed: UInt64 = 7, tuning: RiftwingTuning = RiftwingTuning(), waves: RiftwingWaves = RiftwingWaves()) -> RiftwingRun {
    var run = RiftwingRun(seed: seed, tuning: tuning, waves: waves)
    run.wavesEnabled = false
    run.phase = .fighting
    run.wave = 1
    return run
}

/// Steps until `stop` matches an event or `maxSteps` is reached. Returns every event seen.
@discardableResult
func run(
    _ run: inout RiftwingRun,
    steps maxSteps: Int,
    input: RiftwingInput = still,
    until stop: (RiftwingEvent) -> Bool = { _ in false }
) -> [RiftwingEvent] {
    var seen: [RiftwingEvent] = []
    for _ in 0..<maxSteps {
        let events = run.step(input)
        seen += events
        if events.contains(where: stop) { break }
    }
    return seen
}

/// Steps with `input(run)` chosen afresh each step.
@discardableResult
func run(
    _ run: inout RiftwingRun,
    steps maxSteps: Int,
    control: (RiftwingRun) -> RiftwingInput,
    until stop: (RiftwingEvent) -> Bool = { _ in false }
) -> [RiftwingEvent] {
    var seen: [RiftwingEvent] = []
    for _ in 0..<maxSteps {
        let events = run.step(control(run))
        seen += events
        if events.contains(where: stop) { break }
    }
    return seen
}

func seconds(_ s: Double) -> Int { Int((s * 120).rounded()) }

extension RiftwingRun {
    /// Puts the rider in the air at `p`, still, protected from nothing.
    mutating func placeRider(at p: Vec2, vel: Vec2 = .zero) {
        rider.body.pos = p
        rider.body.vel = vel
        rider.body.ledge = nil
        rider.body.isDiving = false
        rider.body.reopen = 0
        rider.invulnerableTimer = 0
    }

    /// Takes the rider out of the gallery for good (down, never returning), to watch opponents
    /// on their own.
    mutating func removeRider() {
        rider.isAlive = false
        rider.respawnTimer = .infinity
        rider.body.pos = Vec2(-1000, -1000)
    }

    /// Adds an opponent of `role` at `p`, flying, at full strength unless `ease` says otherwise.
    @discardableResult
    mutating func place(_ role: RiftwingRole, at p: Vec2, vel: Vec2 = .zero, ease: Double = 0) -> Int {
        let id = addOpponent(role, at: p)
        let i = opponents.count - 1
        opponents[i].body.vel = vel
        opponents[i].ease = ease
        return id
    }

    /// Holds an opponent still where it is (no behaviour) by making it stagger forever.
    mutating func freeze(_ id: Int) {
        if let i = opponents.firstIndex(where: { $0.id == id }) {
            opponents[i].state = .staggered(remaining: .infinity)
        }
    }

    func index(of id: Int) -> Int { opponents.firstIndex { $0.id == id }! }

    func req(opponent id: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> RiftwingOpponent {
        try #require(opponent(id), "opponent \(id) is gone", sourceLocation: sourceLocation)
    }

    func req(pod id: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> RiftwingPod {
        try #require(pod(id), "pod \(id) is gone", sourceLocation: sourceLocation)
    }
}

extension RiftwingEvent {
    /// The case name without its payload, e.g. "clashWon".
    var kind: String {
        let text = String(describing: self)
        return String(text.prefix { $0 != "(" })
    }
}

func count(_ events: [RiftwingEvent], _ kind: String) -> Int {
    events.count { $0.kind == kind }
}

func has(_ events: [RiftwingEvent], _ kind: String) -> Bool {
    events.contains { $0.kind == kind }
}

/// A size at figure scale 1 (`base`) at the tuning's figure scale: test geometry measured against
/// a rig's body grows with the figures.
func fig(_ base: Double) -> Double { RiftwingTuning().figure(base) }
