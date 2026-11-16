public struct ScheduledSpawn: Sendable, Equatable {
    /// Seconds after the wave starts.
    public var delay: Double
    public var kind: EnemyKind
}

/// Decides what each wave contains. New enemy types are introduced one wave at a time.
public struct WaveDirector: Sendable {
    public init() {}

    /// How many of each kind arrive in a wave.
    public func composition(forWave wave: Int) -> [(kind: EnemyKind, count: Int)] {
        let all: [(kind: EnemyKind, count: Int)] = [
            (.harvester, min(4 + wave, 12)),
            (.sower, wave >= 2 ? min(wave / 2, 3) : 0),
            (.brood, wave >= 3 ? min((wave - 1) / 2, 3) : 0),
            (.lancer, wave >= 4 ? min((wave - 2) / 2, 3) : 0),
            (.anchor, wave >= 8 ? 2 : (wave >= 5 ? 1 : 0)),
            (.husk, wave >= 6 ? min(wave - 5, 4) : 0),
        ]
        return all.filter { $0.count > 0 }
    }

    public func spawns(forWave wave: Int) -> [ScheduledSpawn] {
        var spawns: [ScheduledSpawn] = []
        for (kind, count) in composition(forWave: wave) {
            for index in 0..<count {
                let delay: Double = switch kind {
                // Harvesters arrive in pairs, three seconds apart.
                case .harvester: Double(index / 2) * 3.0
                // Everything else follows once the wave is under way.
                case .sower: 2.0 + Double(index) * 5.0
                case .brood: 4.0 + Double(index) * 5.0
                case .lancer: 6.0 + Double(index) * 4.0
                case .anchor: 8.0 + Double(index) * 10.0
                default: 5.0 + Double(index) * 4.0
                }
                spawns.append(ScheduledSpawn(delay: delay, kind: kind))
            }
        }
        return spawns
    }
}
