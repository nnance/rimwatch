import Foundation
import GameCore

/// Chooses the music's mood during play from how threatening the moment is, with hysteresis so
/// the music settles rather than flapping:
///
/// - Blackout always plays `.blackout`, at once, and leaving it is immediate too.
/// - Otherwise the music turns tense when the threat rises past `tensionAbove`, and calms once
///   the threat has stayed below `calmBelow` for `calmAfter` seconds.
/// - Apart from Blackout, the mood never changes sooner than `minimumHold` after the last change.
public struct MusicMoodDirector: Sendable {
    public static let tensionAbove = 1.6
    public static let calmBelow = 0.8
    public static let calmAfter = 4.0
    public static let minimumHold = 8.0
    /// Enemies count toward the threat within this distance of the ship (about a screen).
    public static let nearDistance = 650.0
    /// A new wave counts as a threat for this long, so its arrival lifts the music.
    public static let waveArrival = 4.0

    public private(set) var mood: MusicMood = .calm
    /// Seconds since the mood last changed.
    public private(set) var sinceChange = 0.0
    private var quietFor = 0.0
    private var lastWave = 0
    private var sinceWave = Double.infinity

    public init() {}

    /// How dangerous the moment is: nearby enemies by how much harm they can do, plus every
    /// abduction under way and every colonist falling anywhere. Roughly 0 (nothing about) to 5+.
    public static func threat(in sim: Simulation) -> Double {
        var threat = 0.0
        let ship = sim.player.pos
        for enemy in sim.enemies {
            if case .lifting = enemy.state {
                // An abduction anywhere is urgent, wherever the ship is.
                threat += 1.5
                continue
            }
            guard sim.world.distance(ship, enemy.pos) < nearDistance else { continue }
            let weight: Double = switch enemy.kind {
            case .harvester: 0.5
            case .husk: 1.0
            case .sower: 0.5
            case .mine: 0.1
            case .brood: 0.8
            case .mote: 0.4
            case .lancer: enemy.state == .patrolling ? 0.6 : 1.5
            case .anchor: { if case .drilling = enemy.state { 2.0 } else { 0.7 } }()
            }
            threat += weight
        }
        for colonist in sim.colonists {
            if case .falling = colonist.state { threat += 1.0 }
        }
        return threat
    }

    /// Advances by `elapsed` seconds of play and returns the mood to play.
    public mutating func update(elapsed: Double, sim: Simulation) -> MusicMood {
        update(elapsed: elapsed, threat: Self.threat(in: sim), wave: sim.wave, blackout: sim.isBlackout)
    }

    /// The same from plain numbers (for tests and other callers).
    public mutating func update(elapsed: Double, threat: Double, wave: Int, blackout: Bool) -> MusicMood {
        sinceChange += elapsed
        sinceWave += elapsed
        if wave != lastWave {
            lastWave = wave
            sinceWave = 0
        }
        if blackout {
            change(to: .blackout)
            return mood
        }
        // A wave arriving is a threat in itself for a few seconds.
        let level = sinceWave < Self.waveArrival ? max(threat, Self.tensionAbove) : threat
        quietFor = level < Self.calmBelow ? quietFor + elapsed : 0

        switch mood {
        case .blackout:
            // Power is back: straight to whatever the moment calls for.
            change(to: level >= Self.calmBelow ? .tension : .calm)
        case .calm, .title:
            if level >= Self.tensionAbove, sinceChange >= Self.minimumHold { change(to: .tension) }
        case .tension:
            if quietFor >= Self.calmAfter, sinceChange >= Self.minimumHold { change(to: .calm) }
        }
        return mood
    }

    /// Starts over for a new run (calm, ready to change at once).
    public mutating func reset() {
        self = MusicMoodDirector()
        sinceChange = Self.minimumHold
    }

    private mutating func change(to next: MusicMood) {
        guard next != mood else { return }
        mood = next
        sinceChange = 0
    }
}
