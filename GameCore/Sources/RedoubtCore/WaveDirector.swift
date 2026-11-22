import GameCore

/// One enemy a wave sends in. In `RedoubtWaves.spawns(forWave:)`, `delay` is its place in the
/// opening ripple; in `RedoubtWaves.arrivals(forWave:)`, the second of the wave it lands at the
/// latest; held back in `RedoubtRun.pending`, the second of the wave its telegraph starts at the
/// latest.
public struct RedoubtSpawn: Sendable, Equatable {
    public var delay: Double
    public var role: RedoubtRole
    /// For a late arrival held back in `RedoubtRun.pending`: whether the opening-crowd spawn it
    /// came from is scattered (`RedoubtWaves.isScattered`), so it lands where that spawn would.
    public var scattered = false
    /// For a Gleaner coming in through the wave (`RedoubtWaves.gleanersThroughWave`): its
    /// telegraph starts as soon as this share of the wave's Skitter quota has been sent in, if
    /// that comes before `delay`. Nil: on the clock alone.
    public var afterQuotaSpent: Double? = nil
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

    /// The waves as they were before Refinement 6 (at 6e7d6e3): every Gleaner of a wave landing
    /// together, in the early waves a few seconds after the opening crowd, and dragging more
    /// slowly in their first waves with no least time to a loss; the Spitters' and Burrows' eases
    /// counted in wave numbers; debut Spitter shots as fast and as well aimed as any. With this
    /// the game is exactly the one before.
    public static var beforeGleanersThroughWave: RedoubtWaves {
        var waves = RedoubtWaves()
        waves.gleanersThroughWave = false
        waves.seizeTimes = []
        waves.seizeTimeFloor = 0
        waves.gleanerDebutDragSlowdown = 6
        waves.easeByAppearance = false
        waves.spitterDebutShotSpeed = 1
        waves.spitterDebutLead = 1
        waves.spitterCounts = []
        return waves
    }

    /// The waves as they were before the Gleaners' ramp: their ease counted in waves (gone by
    /// wave 7, a cliff, since Gleaners come only in waves 2, 4, 7, 9 and on), Gleaners landing
    /// late always with the main push, and quiet runs (wave 0) dragging at the debut crawl. With
    /// this the game is exactly the one before.
    public static var beforeGleanerRamp: RedoubtWaves {
        var waves = RedoubtWaves.beforeGleanersThroughWave
        waves.gleanerRamp = false
        return waves
    }

    /// The waves as they were before the Burrows' ease: debut Spitters 3.8 times slower, easing
    /// over four waves, and two Burrows pouring at the full rate from their debut. With this the
    /// game is exactly the one before.
    public static var beforeBurrowEase: RedoubtWaves {
        var waves = RedoubtWaves.beforeGleanerRamp
        waves.spitterDebutSlowdown = 3.8
        waves.spitterEaseWaves = 4
        waves.burrowDebutSlowdown = 1
        waves.burrowsAtDebut = 2
        return waves
    }

    /// The waves as they were before the Gleaners' ease: every Gleaner of the opening crowd lands
    /// with the rest of it and drags at the full speed from its debut.
    public static var beforeGleanerEase: RedoubtWaves {
        var waves = RedoubtWaves.beforeBurrowEase
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
    /// rate over their next appearances by `spitterRampEase` (over `spitterEaseWaves` wave
    /// numbers with `easeByAppearance` off). Before 13d: 1 (no slowdown); before the figures
    /// grew: 2; before the Burrows' ease: 3.8 (which left debut Spitters nearly silent).
    public var spitterDebutSlowdown = 2.0
    public var spitterEaseWaves = 4.0
    /// Burrows pour Skitters this many times more slowly in their debut wave (5), easing back to
    /// the normal rate over their next appearances by `burrowRampEase` (over `burrowEaseWaves`
    /// wave numbers with `easeByAppearance` off), so wave 5 is no cliff for a first-time player.
    /// `beforeBurrowEase` sets it to 1, the game before.
    public var burrowDebutSlowdown = 2.0
    public var burrowEaseWaves = 3.0
    /// True: the Spitters' and Burrows' eases are counted in each role's own appearances (the
    /// waves whose opening crowd has that role: `appearance(of:inWave:)`), as the Gleaners' is.
    /// False (`beforeGleanersThroughWave`): counted in wave numbers from the debut, so Spitters,
    /// which come in waves 3, 4 and then 7, lost the rest of their ease between 4 and 7 while
    /// their number doubled, and Burrows (5, 7, 9) theirs by wave 8.
    public var easeByAppearance = true
    /// How much of the Spitters' debut ease (`spitterDebutSlowdown`, `spitterDebutShotSpeed`,
    /// `spitterDebutLead`) is left in each of their appearances, first to last (0 after the last
    /// entry): waves 3, 4, 7, 9, 10 and on.
    public var spitterRampEase: [Double] = [1, 0.75, 0.2]
    /// How much of the Burrows' debut ease (`burrowDebutSlowdown`) is left in each of their
    /// appearances: waves 5, 7, 9 and on.
    public var burrowRampEase: [Double] = [1, 0.5, 0.2]
    /// A debut Spitter's shot flies at this multiple of `RedoubtTuning.spitterShotSpeed`, easing
    /// back to the full speed by `spitterRampEase`, so a first-time player has longer to see it
    /// coming. 1 is the game before.
    public var spitterDebutShotSpeed = 0.8
    /// A debut Spitter leads the orb by this multiple of `RedoubtTuning.spitterShotLead` (0: aims
    /// where the orb is), easing back to the full lead by `spitterRampEase`, so moving is enough
    /// to dodge its first shots. 1 is the game before.
    public var spitterDebutLead = 0.5
    /// Spitters in each of their appearances after the first (waves 4, 7, 9, 10 and on), the last
    /// entry holding; empty: one more a wave after their debut, from 2, up to 8 (waves 4, 7 and
    /// 9 on: 3, 6 and 8).
    public var spitterCounts: [Int] = [2, 6, 7, 8]
    /// Burrows the Burrows' debut wave sends (2 before the Burrows' ease). With two, slowing
    /// their pour alone (even three times) still left wave 5 at about 1.3 lives lost for the
    /// novice pilot; with one it is about 0.9.
    public var burrowsAtDebut = 1

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
    /// and a seized colonist is dragged `gleanerDebutDragSlowdown` times more slowly. Both ease
    /// back to nothing over the Gleaners' next appearances by `gleanerRampEase`.
    /// `beforeGleanerEase` sets the first two to 0 and 1, the game before.
    public var gleanerDebutDelay = 7.0
    /// 1 since Refinement 6: the least seizure time (`seizeTimeDebut`) does its work instead.
    public var gleanerDebutDragSlowdown = 1.0
    /// How much of the ease is left in each of the Gleaners' waves (`gleanerWave(_:)`: the waves
    /// that send Gleaners, 2, 4, 7, 9, 10 and on), first to last; 0 after the last entry, and in
    /// a wave without Gleaners (and a quiet run's wave 0). So the player meets them a little
    /// sooner and a little faster each time, the full speed from their sixth wave (11): late by
    /// 7, 4.9, 3.85, 2.8 and 1.4 s and dragging at 10, 13, 16, 20 and 30 units a second in waves
    /// 2, 4, 7, 9 and 10, then on time at 60. (Counted in waves, as before the ramp, the ease
    /// was gone by wave 7: a cliff.) Since Refinement 6 the delay is `gleanerFirstArrival` and
    /// the drag slowdown 1, so this only matters with `beforeGleanersThroughWave`.
    public var gleanerRampEase: [Double] = [1, 0.7, 0.55, 0.4, 0.2]
    /// True: the ease follows `gleanerRampEase`. False (`beforeGleanerRamp`): it is counted in
    /// waves from the debut over `gleanerEaseWaves` (gone by wave 7, a cliff, since waves 5 and 6
    /// send no Gleaners; at its fullest in wave 0 too).
    public var gleanerRamp = true
    /// Whether an opening-crowd spawn landing late (the early waves' Gleaners) follows the
    /// scatter rule of the spawn it came from (`isScattered`). False, deliberately: late arrivals
    /// always land with the main push, along the entry walls while the wave has them (from wave
    /// 8, when it has none, anywhere on the floor clear of the orb, like the rest of the crowd). Letting them scatter was measured
    /// (novice pilot, 160 seeds on two seed sets) to cost a first-time player about a sixth of a
    /// wave, and it puts Gleaners beside colonists: the first seizure came earlier and some drags
    /// took no time at all, against the owner's wish that colonists go later and more slowly.
    public var lateArrivalsScatter = false
    /// Waves from the debut the ease lasts with `gleanerRamp` off.
    public var gleanerEaseWaves = 5.0

    /// Gleaners through the wave (Refinement 6, decided by the owner: every seizure came in one
    /// burst when a wave's Gleaners landed, and from wave 9 most colonists were gone in its first
    /// seconds). True: the first `gleanerFirstGroup` of a wave's Gleaners land `gleanerDelay`
    /// after the opening crowd; each of the rest is telegraphed once its share of the wave's
    /// Skitter quota has been sent in (spread evenly up to `gleanerSpreadEnd` of it), or at the
    /// latest `gleanerFallbackGap` seconds after the one before it, so they come in ones and twos
    /// through the wave, sooner for a player who clears the floor fast, and never hold a finished
    /// wave open (with the quota spent, all of them are due). False
    /// (`beforeGleanersThroughWave`): all of them land together.
    public var gleanersThroughWave = true
    /// How many of a wave's Gleaners land first, `gleanerDelay` after the opening crowd.
    public var gleanerFirstGroup = 1
    /// With `gleanersThroughWave`: seconds after the opening crowd that a wave's first Gleaners
    /// land (`gleanerDelay`), in each of the Gleaners' appearances, first to last; 0 (with the
    /// opening crowd) after the last entry. It replaces `gleanerDebutDelay` and `gleanerRampEase`.
    public var gleanerFirstArrival: [Double] = [10, 9, 8, 6, 4, 2, 1]
    /// The shares of the wave's Skitter quota at which the first and the last of the Gleaners
    /// after the first group are due; the ones between are spaced evenly.
    public var gleanerSpreadStart = 0.35
    public var gleanerSpreadEnd = 0.8
    /// Most seconds between one Gleaner coming in through the wave and the next, however slowly
    /// the quota goes, so a wave whose floor is not being cleared still gets them.
    public var gleanerFallbackGap = 8.0
    /// The least time from a seizure to the colonist being lost, in seconds, in each of the
    /// Gleaners' appearances, first to last (waves 2, 4, 7, 9, 10 and on); after the last entry,
    /// and in a wave without Gleaners, `seizeTimeFloor`, which holds for good. A Gleaner closer
    /// to the wall than that drags more slowly to fit, so the pair always visibly creeps toward
    /// the wall and a seizure can always be answered. Empty and 0
    /// (`beforeGleanersThroughWave`): none, so a colonist beside a wall could be lost at once.
    public var seizeTimes: [Double] = [8, 7, 6, 5.5, 5, 4.5, 4, 3.5]
    public var seizeTimeFloor = 3.0

    /// The wave the Gleaners first come in.
    private static let gleanerDebut = debut.first { $0.role == .gleaner }?.wave ?? 2

    /// True when a wave's opening crowd has Gleaners (`composition(forWave:)`): their debut, and
    /// every later wave that is not another role's debut.
    public func sendsGleaners(_ wave: Int) -> Bool {
        crowdCount(of: .gleaner, inWave: wave) > 0
    }

    /// Which of the Gleaners' waves a wave is: 0 for their debut (wave 2), 1 for the next wave
    /// that sends them (4), then 2 (7), 3 (9), 4 (10) and so on; nil for a wave without them.
    public func gleanerWave(_ wave: Int) -> Int? {
        appearance(of: .gleaner, inWave: wave)
    }

    /// Which of a role's appearances a wave is, counted from the wave makeup itself
    /// (`composition(forWave:)`): 0 for the first wave whose opening crowd has it, 1 for the next,
    /// and so on; nil for a wave whose opening crowd has none.
    public func appearance(of role: RedoubtRole, inWave wave: Int) -> Int? {
        guard crowdCount(of: role, inWave: wave) > 0 else { return nil }
        return (1..<max(wave, 1)).count { crowdCount(of: role, inWave: $0) > 0 }
    }

    /// How much of a ramp is left in an appearance (0 for none, or past the last entry).
    private static func rampShare(_ ramp: [Double], _ appearance: Int?) -> Double {
        guard let appearance, appearance < ramp.count else { return 0 }
        return min(max(ramp[appearance], 0), 1)
    }

    /// How much of the Spitters' debut ease is left in a wave (0 with `easeByAppearance` off:
    /// the shot eases belong to Refinement 6).
    private func spitterEase(forWave wave: Int) -> Double {
        easeByAppearance ? Self.rampShare(spitterRampEase, appearance(of: .spitter, inWave: wave)) : 0
    }

    /// A Spitter shot's speed in a wave, as a multiple of `RedoubtTuning.spitterShotSpeed`.
    public func spitterShotSpeedScale(forWave wave: Int) -> Double {
        1 + (spitterDebutShotSpeed - 1) * spitterEase(forWave: wave)
    }

    /// How much a Spitter leads the orb in a wave, as a multiple of `RedoubtTuning.spitterShotLead`.
    public func spitterLeadScale(forWave wave: Int) -> Double {
        1 + (spitterDebutLead - 1) * spitterEase(forWave: wave)
    }

    /// The least seconds from a seizure to the colonist's loss in a wave (`seizeTimes`), never
    /// under `seizeTimeFloor`.
    public func seizeTime(forWave wave: Int) -> Double {
        let floor = max(seizeTimeFloor, 0)
        guard let index = gleanerWave(wave), index < seizeTimes.count else { return floor }
        return max(seizeTimes[index], floor)
    }

    /// A wave's opening spawns with the second each lands at (at the latest): the ripple, and
    /// for Gleaners their delay; with `gleanersThroughWave`, all but the first group of Gleaners
    /// are spread through the wave by the quota (`RedoubtSpawn.afterQuotaSpent`), on a clock
    /// fallback.
    public func arrivals(forWave wave: Int) -> [RedoubtSpawn] {
        let opening = spawns(forWave: wave)
        guard gleanersThroughWave else {
            return opening.map { RedoubtSpawn(delay: landing(of: $0, inWave: wave), role: $0.role) }
        }
        let gleaners = opening.count { $0.role == .gleaner }
        let first = min(max(gleanerFirstGroup, 1), gleaners)
        let rest = gleaners - first
        var seen = 0
        var lastFirst = 0.0
        return opening.map { spawn in
            guard spawn.role == .gleaner else { return RedoubtSpawn(delay: spawn.delay, role: spawn.role) }
            seen += 1
            if seen <= first {
                lastFirst = landing(of: spawn, inWave: wave)
                return RedoubtSpawn(delay: lastFirst, role: .gleaner)
            }
            let k = seen - first
            let start = min(max(gleanerSpreadStart, 0), 1), end = min(max(gleanerSpreadEnd, start), 1)
            let share = rest > 1 ? start + (end - start) * Double(k - 1) / Double(rest - 1) : start
            return RedoubtSpawn(delay: lastFirst + max(gleanerFallbackGap, 0) * Double(k), role: .gleaner,
                                afterQuotaSpent: share)
        }
    }

    /// How much of the Gleaners' ease is left in a wave: 1 in their first wave, 0 once it is
    /// over and in a wave without Gleaners.
    private func gleanerEase(forWave wave: Int) -> Double {
        guard gleanerRamp else {
            return max(0, 1 - Double(max(wave - Self.gleanerDebut, 0)) / max(gleanerEaseWaves, 1e-9))
        }
        guard let index = gleanerWave(wave), index < gleanerRampEase.count else { return 0 }
        return min(max(gleanerRampEase[index], 0), 1)
    }

    /// Seconds after the rest of the opening crowd that its Gleaners land in a wave (with
    /// `gleanersThroughWave`, its first group: `gleanerFirstArrival`).
    public func gleanerDelay(forWave wave: Int) -> Double {
        if gleanersThroughWave {
            guard let index = gleanerWave(wave), index < gleanerFirstArrival.count else { return 0 }
            return max(gleanerFirstArrival[index], 0)
        }
        return max(gleanerDebutDelay, 0) * gleanerEase(forWave: wave)
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

    /// How many of a role a wave's opening crowd has (0: none). The one source of the wave
    /// makeup: `composition(forWave:)` and every role's appearances (`appearance(of:inWave:)`)
    /// are read from it.
    public func crowdCount(of role: RedoubtRole, inWave wave: Int) -> Int {
        guard role != .skitter else {
            let others = Self.debut.reduce(0) { $0 + crowdCount(of: $1.role, inWave: wave) }
            return max(floorCrowd(forWave: wave) - others, 10)
        }
        guard isInCrowd(role, wave) else { return 0 }
        guard let first = Self.debut.first(where: { $0.role == role })?.wave else { return 0 }
        if wave == first, role == .burrow { return burrowsAtDebut }
        if wave > first, role == .spitter, !spitterCounts.isEmpty {
            // Counted in the Spitters' own appearances.
            let index = (1..<wave).count { isInCrowd(.spitter, $0) }
            return max(spitterCounts[min(index, spitterCounts.count) - 1], 1)
        }
        return Self.count(of: role, wave: wave, first: first)
    }

    /// Whether a role (not Skitters) is in a wave's opening crowd: its debut, alone, and every
    /// later wave that is not another role's debut.
    private func isInCrowd(_ role: RedoubtRole, _ wave: Int) -> Bool {
        if let debut = Self.debut.first(where: { $0.wave == wave }) {
            return debut.role == role && (role != .burrow || burrowsAtDebut > 0)
        }
        guard let first = Self.debut.first(where: { $0.role == role })?.wave else { return false }
        return first < wave
    }

    /// The opening crowd's makeup: Skitters first, then the other roles in the order they debut.
    public func composition(forWave wave: Int) -> [(role: RedoubtRole, count: Int)] {
        ([RedoubtRole.skitter] + Self.debut.map(\.role))
            .map { (role: $0, count: crowdCount(of: $0, inWave: wave)) }
            .filter { $0.count > 0 }
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

    /// Spitter fire interval in a wave, as a multiple of the base: shortening by
    /// `RedoubtTuning.spitterFireGrowth` a wave after their debut, times what is left of the
    /// debut slowdown (by appearance: `spitterRampEase`).
    public func spitterFireScale(forWave wave: Int, tuning: RedoubtTuning) -> Double {
        let since = Double(max(wave - 3, 0))
        let ease = easeByAppearance ? spitterEase(forWave: wave) : max(0, 1 - since / max(spitterEaseWaves, 1e-9))
        let slowdown = 1 + (spitterDebutSlowdown - 1) * ease
        return max(1 - tuning.spitterFireGrowth * since, tuning.spitterMinScale) * slowdown
    }

    /// Burrow spawn interval in a wave, as a multiple of the base: shortening by
    /// `RedoubtTuning.burrowSpawnGrowth` a wave after their debut, times what is left of the
    /// debut slowdown (by appearance: `burrowRampEase`).
    public func burrowSpawnScale(forWave wave: Int, tuning: RedoubtTuning) -> Double {
        let first = Self.debut.first { $0.role == .burrow }?.wave ?? 5
        let since = Double(max(wave - first, 0))
        let ease = easeByAppearance ? Self.rampShare(burrowRampEase, appearance(of: .burrow, inWave: wave))
            : max(0, 1 - since / max(burrowEaseWaves, 1e-9))
        let slowdown = 1 + (max(burrowDebutSlowdown, 1) - 1) * ease
        return max(1 - tuning.burrowSpawnGrowth * since, tuning.burrowMinScale) * slowdown
    }
}
