import GameCore

public struct ScheduledSpawn: Sendable, Equatable {
    /// Seconds after the wave starts.
    public var delay: Double
    public var kind: EnemyKind
}

/// Decides what each wave contains.
///
/// Each wave has a budget of enemies that grows by about one per wave. Harvesters make up
/// whatever the other kinds leave. A new kind debuts on its own: in its first wave it is the only
/// kind besides Harvesters, and there is just one of it. Mixed waves come between debuts, and
/// each kind's numbers then grow slowly to a cap. Later waves also arrive faster.
///
/// The numbers were tuned with the scripted pilots in `Autopilot` (see `DifficultyTests`).
public struct WaveDirector: Sendable {
    public init() {}

    /// The wave in which each kind first appears. Husks also form from completed abductions at
    /// any time.
    public static let debut: [(kind: EnemyKind, wave: Int)] = [
        (.sower, 2), (.brood, 3), (.lancer, 5), (.anchor, 7), (.husk, 9),
    ]

    private static func cap(for kind: EnemyKind) -> Int {
        switch kind {
        case .sower: 3
        case .brood: 3
        case .lancer: 3
        case .anchor: 2
        case .husk: 4
        default: 0
        }
    }

    /// Enemies in a wave, all kinds together. Never shrinks from one wave to the next.
    public func budget(forWave wave: Int) -> Int {
        wave <= 1 ? 3 : min(3 + wave + wave / 2, 26)
    }

    /// How many of each kind arrive in a wave.
    public func composition(forWave wave: Int) -> [(kind: EnemyKind, count: Int)] {
        let total = budget(forWave: wave)
        var others: [(kind: EnemyKind, count: Int)] = []
        if let debut = Self.debut.first(where: { $0.wave == wave }) {
            // A debut: one of the new kind and Harvesters, nothing else.
            others = [(debut.kind, 1)]
        } else {
            for (kind, first) in Self.debut where first < wave {
                // One more every two waves after the debut wave.
                others.append((kind, min(1 + (wave - first) / 2, Self.cap(for: kind))))
            }
        }
        let harvesters = max(total - others.reduce(0) { $0 + $1.count }, 2)
        return ([(.harvester, harvesters)] + others).filter { $0.count > 0 }
    }

    /// Shrinks the gaps between arrivals in later waves.
    func pace(forWave wave: Int) -> Double {
        max(0.55, 1 - 0.05 * Double(wave - 1))
    }

    public func spawns(forWave wave: Int) -> [ScheduledSpawn] {
        var spawns: [ScheduledSpawn] = []
        let pace = pace(forWave: wave)
        for (kind, count) in composition(forWave: wave) {
            for index in 0..<count {
                let delay: Double = switch kind {
                // Harvesters arrive in pairs, a few seconds apart; the first wave one at a time.
                case .harvester: wave == 1 ? Double(index) * 4.0 : Double(index / 2) * 3.5 * pace
                // Everything else follows once the wave is under way.
                case .sower: (2.0 + Double(index) * 5.0) * pace
                case .brood: (4.0 + Double(index) * 5.0) * pace
                case .lancer: (6.0 + Double(index) * 5.0) * pace
                case .anchor: (8.0 + Double(index) * 10.0) * pace
                default: (5.0 + Double(index) * 4.0) * pace
                }
                spawns.append(ScheduledSpawn(delay: delay, kind: kind))
            }
        }
        return spawns
    }

    /// Harvesters shoot more often in later waves: their fire interval is scaled by this. The
    /// first wave teaches the abduction loop, so its Harvesters shoot rarely.
    public func fireIntervalScale(forWave wave: Int) -> Double {
        wave <= 1 ? 1.8 : max(0.35, 0.85 - 0.06 * Double(wave - 2))
    }
}
