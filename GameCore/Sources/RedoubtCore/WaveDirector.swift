import GameCore

/// One enemy a wave sends in: its telegraph starts `delay` seconds after the wave begins.
public struct RedoubtSpawn: Sendable, Equatable {
    public var delay: Double
    public var role: RedoubtRole
}

/// Decides what each Redoubt wave contains.
///
/// The floor is never allowed to go quiet while a wave lasts:
/// - A wave opens with `floorCrowd` enemies (18 in wave 1, rising to the full 20 + 8 a wave by
///   wave 8, capped at 90), all telegraphed in its first second, along the wave's entry walls
///   (`entrySides`: one wall in waves 1 to 4, more later, anywhere from wave 8).
/// - It also has a quota of Skitters (`quota`). Whenever the shootable enemies on the floor (and
///   on their way in) fall below `floorTarget`, the run telegraphs another group of them at once,
///   from one of the wave's entry walls (any side from wave 8), until the quota is spent. Burrows pour out more on top.
/// - The wave ends when the quota is spent and the floor is clear, so only the last few need
///   hunting down.
/// Each new role debuts in a wave of its own, alongside Skitters only; mixed waves come between
/// debuts, and each role's numbers then grow slowly to a cap. Skitters fill whatever the other
/// roles leave of the opening crowd.
///
/// The numbers were given a first tuning pass with the scripted pilots in `RedoubtPilot` (see
/// `RedoubtDifficultyTests`, `RedoubtFeelTests` and the harness's `redoubt` mode).
public struct RedoubtWaves: Sendable {
    public init() {}

    // The early-game ease (13d, after the owner's first play: a first-time player was swarmed in
    // waves 2 and 3). Each is a plain number to change or undo.

    /// How many walls each wave's crowd comes in from, by wave (wave 1 first; the last entry
    /// holds for every later wave). The opening crowd lands in a band along those walls and the
    /// top-up groups come from them, so early on the orb has open floor to back into. The walls
    /// far from the orb are favoured. 4 is anywhere on the floor (as before 13d, every wave).
    public var entrySides: [Int] = [1, 1, 1, 1, 2, 3, 3, 4]
    /// The opening crowd and the Skitter quota are scaled by this in wave 1, rising by
    /// `crowdEaseGrowth` a wave to the full numbers (wave 8 on). Before 13d: 1 and 0.
    public var crowdEaseStart = 0.9
    public var crowdEaseGrowth = 0.015
    /// Spitters fire this many times more slowly in their debut wave, easing back to the normal
    /// rate over `spitterEaseWaves` waves. Before 13d: 1 (no slowdown).
    public var spitterDebutSlowdown = 2.0
    public var spitterEaseWaves = 4.0

    /// Walls the crowd comes in from in a wave (4: anywhere).
    public func entrySides(forWave wave: Int) -> Int {
        guard !entrySides.isEmpty else { return 4 }
        return entrySides[min(max(wave - 1, 0), entrySides.count - 1)]
    }

    /// The early-game scale on the opening crowd and the quota (1 from the full-crowd wave on).
    public func crowdEase(forWave wave: Int) -> Double {
        min(1, crowdEaseStart + crowdEaseGrowth * Double(max(wave - 1, 0)))
    }

    /// The wave each role first appears in. Husks also form from Gleaners at any time.
    public static let debut: [(role: RedoubtRole, wave: Int)] = [
        (.gleaner, 2), (.spitter, 3), (.burrow, 5), (.thresher, 6), (.husk, 8),
    ]

    /// How many of a role its debut wave sends, and after that: one more every `every` waves
    /// from `base`, up to `cap`.
    private static func count(of role: RedoubtRole, wave: Int, first: Int) -> Int {
        let (atDebut, base, every, cap): (Int, Int, Int, Int) = switch role {
        case .gleaner: (4, 3, 2, 8)
        case .spitter: (3, 2, 1, 8)
        case .burrow: (2, 1, 3, 3)
        case .thresher: (2, 1, 3, 3)
        case .husk: (4, 3, 2, 10)
        case .skitter: (0, 0, 1, 0)
        }
        if wave == first { return atDebut }
        return min(base + (wave - first) / every, cap)
    }

    /// Enemies on the floor at the start of a wave, all roles together: 18 in wave 1, 8 more a
    /// wave less the early ease, the full 76 in wave 8, capped at 90.
    public func floorCrowd(forWave wave: Int) -> Int {
        Int((Double(min(20 + 8 * max(wave - 1, 0), 90)) * crowdEase(forWave: wave)).rounded())
    }

    /// Colonists sheltering when a wave begins: 6 in wave 1, one more every two waves, up to 10.
    public func colonists(forWave wave: Int) -> Int {
        min(6 + max(wave - 1, 0) / 2, 10)
    }

    /// The opening crowd's makeup.
    public func composition(forWave wave: Int) -> [(role: RedoubtRole, count: Int)] {
        var others: [(role: RedoubtRole, count: Int)] = []
        if let debut = Self.debut.first(where: { $0.wave == wave }) {
            // A debut: the new role and Skitters, nothing else.
            others = [(debut.role, Self.count(of: debut.role, wave: wave, first: wave))]
        } else {
            for (role, first) in Self.debut where first < wave {
                others.append((role, Self.count(of: role, wave: wave, first: first)))
            }
        }
        let skitters = max(floorCrowd(forWave: wave) - others.reduce(0) { $0 + $1.count }, 10)
        return ([(.skitter, skitters)] + others).filter { $0.count > 0 }
    }

    /// Shootable enemies the run keeps on the floor (counting those on their way in) while the
    /// wave's quota lasts: the opening crowd's size, so the floor stays as full as it began.
    public func floorTarget(forWave wave: Int) -> Int {
        floorCrowd(forWave: wave)
    }

    /// Skitters a wave sends in after its opening crowd, to keep the floor at `floorTarget`.
    public func quota(forWave wave: Int) -> Int {
        Int((Double(min(90 + 25 * max(wave - 1, 0), 400)) * crowdEase(forWave: wave)).rounded())
    }

    /// Most Skitters telegraphed together in one top-up group.
    public static let groupSize = 6
    /// Shortest gap between two top-up groups, so a burst of kills refills in a ripple.
    public static let groupGap = 0.25

    /// The opening crowd, in the order the telegraphs start: spread over the first 0.8 s so the
    /// floor fills in a ripple rather than all in one frame.
    public func spawns(forWave wave: Int) -> [RedoubtSpawn] {
        var opening: [RedoubtRole] = []
        for (role, count) in composition(forWave: wave) {
            opening += Array(repeating: role, count: count)
        }
        return opening.enumerated().map { index, role in
            RedoubtSpawn(delay: 0.8 * Double(index) / Double(max(opening.count, 1)), role: role)
        }
    }

    /// Skitter speed in a wave, as a multiple of the base.
    public func skitterSpeedScale(forWave wave: Int, tuning: RedoubtTuning) -> Double {
        min(1 + tuning.skitterSpeedGrowth * Double(max(wave - 1, 0)), tuning.skitterMaxScale)
    }

    /// Spitter fire interval in a wave, as a multiple of the base.
    public func spitterFireScale(forWave wave: Int, tuning: RedoubtTuning) -> Double {
        let since = Double(max(wave - 3, 0))
        let slowdown = 1 + (spitterDebutSlowdown - 1) * max(0, 1 - since / max(spitterEaseWaves, 1e-9))
        return max(1 - tuning.spitterFireGrowth * since, tuning.spitterMinScale) * slowdown
    }

    /// Burrow spawn interval in a wave, as a multiple of the base.
    public func burrowSpawnScale(forWave wave: Int, tuning: RedoubtTuning) -> Double {
        max(1 - tuning.burrowSpawnGrowth * Double(max(wave - 5, 0)), tuning.burrowMinScale)
    }
}
