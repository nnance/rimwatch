import GameCore

/// One enemy a wave sends in: its telegraph starts `delay` seconds after the wave begins.
public struct RedoubtSpawn: Sendable, Equatable {
    public var delay: Double
    public var role: RedoubtRole
}

/// Decides what each Redoubt wave contains.
///
/// The floor is never allowed to go quiet while a wave lasts:
/// - A wave opens with `floorCrowd` enemies (18 in wave 1, rising to the full 20 + 8 a wave
///   times `crowdScale` by wave 7, capped at 90), all telegraphed in its first second: most in a
///   main push along the wave's entry walls (`entrySides`: one wall in waves 1 to 4, more later), a share growing by
///   wave scattered over the rest of the floor (`scatterShare`), anywhere from wave 8.
/// - It also has a quota of Skitters (`quota`). Whenever the shootable enemies on the floor (and
///   on their way in) fall below `floorTarget`, the run telegraphs another group of them at once,
///   from one of the wave's entry walls, at its end far from the orb (any side from wave 8), until
///   the quota is spent. Burrows pour out more on top.
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

    /// The wave makeup as it was before the figures grew (`RedoubtTuning.figureScale` 1.5):
    /// with this and a figure scale of 1 the game is exactly the one before.
    public static var beforeFiguresGrew: RedoubtWaves {
        var waves = RedoubtWaves.beforeGleanerEase
        waves.crowdScale = 1
        waves.quotaFirst = 90
        waves.quotaGrowth = 25
        waves.crowdEaseStart = 0.9
        waves.crowdEaseGrowth = 0.015
        waves.spitterDebutSlowdown = 2
        return waves
    }

    /// The waves as they were before the Gleaners' ease: every Gleaner of the opening crowd lands
    /// with the rest of it and drags at the full speed from its debut.
    public static var beforeGleanerEase: RedoubtWaves {
        var waves = RedoubtWaves()
        waves.gleanerDebutDelay = 0
        waves.gleanerDebutDragSlowdown = 1
        return waves
    }

    /// The balance that came with the bigger figures (`RedoubtTuning.figureScale` 1.5): bigger
    /// enemies are easier to hit, so waves went faster, and a bigger orb (and bigger Spitter
    /// shots) in a crowd covering more of the floor is easier to hit. The opening crowd (and the
    /// floor target) are scaled by `crowdScale` (still capped at 90, 1 before the figures grew)
    /// and the Skitter quota starts at `quotaFirst` in wave 1 and grows by `quotaGrowth` a wave
    /// (90 and 25 before), so waves last about as long as before;
    /// with them the crowd ease starts lower and grows faster (`crowdEaseStart`,
    /// `crowdEaseGrowth`), so wave 1 still opens with 18, and debut Spitters fire more slowly
    /// (`spitterDebutSlowdown`). `beforeFiguresGrew` holds the values from before.
    public var crowdScale = 1.1
    public var quotaFirst = 126.0
    public var quotaGrowth = 28.0

    // The early-game ease (13d, after the owner's first play: a first-time player was swarmed in
    // waves 2 and 3). Each is a plain number to change or undo.

    /// How many walls each wave's crowd comes in from, by wave (wave 1 first; the last entry
    /// holds for every later wave). The main push of the opening crowd lands in a band along
    /// those walls (the rest is scattered: `scatterShare`) and the top-up groups come from them,
    /// so early on the orb has open floor to back into. See `pushAndScatter` for how the walls
    /// are chosen. 4 is anywhere on the floor (as before 13d, every wave).
    public var entrySides: [Int] = [1, 1, 1, 1, 2, 3, 3, 4]
    /// The opening crowd and the Skitter quota are scaled by this in wave 1, rising by
    /// `crowdEaseGrowth` a wave to the full numbers (wave 7 on). Before 13d: 1 and 0. Before the
    /// figures grew: 0.9 and 0.015 (full from wave 8).
    public var crowdEaseStart = 0.82
    public var crowdEaseGrowth = 0.03
    /// Spitters fire this many times more slowly in their debut wave, easing back to the normal
    /// rate over `spitterEaseWaves` waves. Before 13d: 1 (no slowdown); before the figures
    /// grew: 2.
    public var spitterDebutSlowdown = 3.8
    public var spitterEaseWaves = 4.0

    /// The main push and the scatter (after the owner's second play: the whole crowd along one
    /// wall, the same wall wave after wave, looked artificial). While a wave has entry walls, its
    /// main wall is never the one the orb is nearest nor the last wave's main wall, and is drawn
    /// at random from the rest (the farther ones likelier: `RedoubtTuning.mainWallWeighting`); most of the opening crowd lands in a deep, loose band along the
    /// entry walls, and the share `scatterShare` of it is scattered over the whole floor, kept
    /// `RedoubtTuning.scatterClearance` from the orb. False gives the one-wall entry of the first
    /// 13d ease exactly: the far walls favoured, the whole crowd in a 180-unit band.
    public var pushAndScatter = true
    /// The share of the opening crowd scattered over the floor, by wave (wave 1 first; the last
    /// entry holds for every later wave). Only used while the wave has entry walls: from wave 8,
    /// the whole crowd is anywhere on the floor anyway.
    public var scatterShare: [Double] = [0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6, 1]

    /// The Gleaners' ease (after the owner's third play: nearly every colonist of a wave was
    /// taken in its first few seconds, where Ridgeline takes them late and slowly in its early
    /// stages). In the Gleaners' debut wave the opening crowd's Gleaners land
    /// `gleanerDebutDelay` seconds after the rest of it (their telegraphs start that much later),
    /// and a seized colonist is dragged `gleanerDebutDragSlowdown` times more slowly; both ease
    /// back to nothing over `gleanerEaseWaves` waves (by wave 8). `beforeGleanerEase` sets the
    /// first two to 0 and 1, the game before.
    public var gleanerDebutDelay = 7.0
    public var gleanerDebutDragSlowdown = 6.0
    public var gleanerEaseWaves = 5.0

    /// How far a wave is into the Gleaners' ease: 1 in their debut wave (and before), easing to
    /// 0 over `gleanerEaseWaves` waves.
    private func gleanerEase(forWave wave: Int) -> Double {
        let first = Self.debut.first { $0.role == .gleaner }?.wave ?? 1
        return max(0, 1 - Double(max(wave - first, 0)) / max(gleanerEaseWaves, 1e-9))
    }

    /// Seconds after the rest of the opening crowd that its Gleaners land in a wave.
    public func gleanerDelay(forWave wave: Int) -> Double {
        max(gleanerDebutDelay, 0) * gleanerEase(forWave: wave)
    }

    /// Seconds after a wave begins that one of its opening spawns lands: its place in the
    /// ripple, and the Gleaners' delay on top for a Gleaner.
    public func landing(of spawn: RedoubtSpawn, inWave wave: Int) -> Double {
        spawn.delay + (spawn.role == .gleaner ? gleanerDelay(forWave: wave) : 0)
    }

    /// Gleaners' drag speed in a wave, as a multiple of `RedoubtTuning.gleanerDragSpeed`.
    public func gleanerDragScale(forWave wave: Int) -> Double {
        1 / (1 + (max(gleanerDebutDragSlowdown, 1e-9) - 1) * gleanerEase(forWave: wave))
    }

    /// Walls the crowd comes in from in a wave (4: anywhere).
    public func entrySides(forWave wave: Int) -> Int {
        guard !entrySides.isEmpty else { return 4 }
        return entrySides[min(max(wave - 1, 0), entrySides.count - 1)]
    }

    /// The share of a wave's opening crowd scattered over the floor rather than coming in with
    /// the main push (0 when `pushAndScatter` is off, 1 when the wave has no entry walls).
    public func scatterShare(forWave wave: Int) -> Double {
        guard entrySides(forWave: wave) < 4 else { return 1 }
        guard pushAndScatter, !scatterShare.isEmpty else { return 0 }
        return min(max(scatterShare[min(max(wave - 1, 0), scatterShare.count - 1)], 0), 1)
    }

    /// Which of a wave's opening spawns (by index into `spawns(forWave:)`) are scattered: spread
    /// evenly through the list so every role has its share.
    public func isScattered(_ index: Int, forWave wave: Int) -> Bool {
        let share = scatterShare(forWave: wave)
        return (Double(index + 1) * share).rounded(.down) > (Double(index) * share).rounded(.down)
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

    /// Enemies on the floor at the start of a wave, all roles together: 20 + 8 a wave times
    /// `crowdScale`, less the early ease: 18 in wave 1, the full 75 in wave 7, capped at 90 (from
    /// wave 9). Before the figures grew: 18 in wave 1, the full 76 in wave 8, 90 from wave 10.
    public func floorCrowd(forWave wave: Int) -> Int {
        Int(min(Double(20 + 8 * max(wave - 1, 0)) * crowdEase(forWave: wave) * crowdScale, 90).rounded())
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
        Int((min(quotaFirst + quotaGrowth * Double(max(wave - 1, 0)), 400) * crowdEase(forWave: wave)).rounded())
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
