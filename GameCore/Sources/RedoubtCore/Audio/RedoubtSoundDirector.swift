import GameCore

/// Decides which of a frame's events are voiced, and in which version, so a crowd of ninety
/// never turns into ninety sounds. The theme says what each event sounds like; this says how
/// many of them to play. It knows nothing about the sounds themselves.
///
/// Rules, applied to the events of one frame (one or more simulation steps, told apart by the
/// run's tick):
/// - **One sound per kind of event per frame.** Ninety arrival markers at a wave's start, eight
///   Skitters dying together, a Thresher hit by two shots in one frame: each is voiced once.
///   Kinds are the event's case, split by role where the role changes the sound (a Skitter's
///   death and a Gleaner's are separate kinds; a Skitter group's arrival and a Spitter's too).
/// - **Arrivals are a murmur.** Each kind of arrival is voiced at most once every
///   `arrivalGapTicks` steps.
/// - **A crowd dying is a rattle.** Skitter deaths are voiced at most once every
///   `skitterGapTicks` steps.
/// - **The Shockwave speaks for what it clears.** Skitters, Gleaners, Spitters and Husks it
///   destroys are silent; a Burrow or a Thresher it destroys still sounds (a Thresher dies no
///   other way).
/// - **Versions:** shots and Skitter deaths take one of the theme's pitches at random, never the
///   same twice running, so ten a second never machine-guns. A Burrow hit says how damaged the
///   Burrow is. A delivery is voiced once, for its first colonist, and says how many colonists
///   were delivered in the frame, so the fanfare can grow with the line.
///
/// Deterministic: the same events against the same runs give the same answers.
public struct RedoubtSoundDirector: Sendable {
    /// The run's tick at the frame being voiced; -1 before the first.
    private var frameTick = -1
    /// Kinds already voiced this frame.
    private var voiced: Set<Int> = []
    /// `colonistsDelivered` when the last frame was voiced, and the difference this frame.
    private var lastDelivered = 0
    private var deliveredThisFrame = 0
    private var random: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var lastFire = -1
    private var lastSkitter = -1
    /// The tick of the last Skitter death voiced, and of the last arrival of each kind.
    private var lastSkitterTick = Int.min / 2
    private var lastArrivalTick: [Int: Int] = [:]

    /// Skitter deaths are voiced at most this often (in 120 Hz steps), however many die: about
    /// 40 a second at most, so a crowd dying reads as a rattle, never a roar.
    public static let skitterGapTicks = 3
    /// Arrivals are voiced at most once a second for each kind (Skitter groups, others): groups
    /// are sent in as fast as the floor empties, and each telegraph is a second long.
    public static let arrivalGapTicks = 120
    /// Pitches the theme offers for shots and Skitter deaths (the theme wraps larger numbers).
    public static let pitchVariants = 3

    public init() {}

    /// Starts over for a new run.
    public mutating func reset() {
        self = RedoubtSoundDirector()
    }

    /// The version of the sound to play for `event`, which `run` has just produced, or nil to
    /// stay silent. Pass the variant to `RedoubtTheme.sound(for:variant:)`.
    public mutating func variant(for event: RedoubtEvent, in run: RedoubtRun) -> Int? {
        variant(for: event, tick: run.tick, delivered: run.colonistsDelivered,
                hp: { id in run.enemy(id)?.hp })
    }

    /// The same from plain numbers: the run's `tick` and `colonistsDelivered` after the frame's
    /// steps, and a lookup of an enemy's remaining hit points.
    public mutating func variant(for event: RedoubtEvent, tick: Int, delivered: Int,
                                 hp: (Int) -> Int?) -> Int? {
        if tick != frameTick {
            frameTick = tick
            voiced.removeAll(keepingCapacity: true)
            // Every delivery produces events, so the director sees every frame that has one, and
            // all deliveries since the last frame it saw happened in this one.
            deliveredThisFrame = delivered >= lastDelivered ? delivered - lastDelivered : delivered
            lastDelivered = delivered
        }
        if case .enemyDestroyed(_, let role, _, _, true) = event, role != .burrow, role != .thresher {
            return nil
        }
        if case .enemyDestroyed(_, .skitter, _, _, _) = event, tick - lastSkitterTick < Self.skitterGapTicks {
            return nil
        }
        let kind = Self.kind(of: event)
        if case .arrivalTelegraphed = event {
            if let last = lastArrivalTick[kind], tick - last < Self.arrivalGapTicks { return nil }
            lastArrivalTick[kind] = tick
        }
        guard voiced.insert(kind).inserted else { return nil }
        switch event {
        case .orbFired:
            lastFire = nextPitch(after: lastFire)
            return lastFire
        case .enemyDestroyed(_, .skitter, _, _, _):
            lastSkitterTick = tick
            lastSkitter = nextPitch(after: lastSkitter)
            return lastSkitter
        case .enemyHit(let id, .burrow, _):
            return Self.burrowStage(hp: hp(id))
        case .colonistDelivered:
            return max(deliveredThisFrame, 1)
        default:
            return 0
        }
    }

    /// A Burrow's damage stage, 0 (fresh) to 2 (nearly closed), from its hit points out of 20.
    static func burrowStage(hp: Int?) -> Int {
        guard let hp else { return 2 }
        if hp > 13 { return 0 }
        return hp > 6 ? 1 : 2
    }

    private mutating func nextPitch(after last: Int) -> Int {
        // A small xorshift: one of the other pitches, never the same twice running.
        random ^= random << 13
        random ^= random >> 7
        random ^= random << 17
        guard last >= 0 else { return Int(random % UInt64(Self.pitchVariants)) }
        let step = 1 + Int(random % UInt64(Self.pitchVariants - 1))
        return (last + step) % Self.pitchVariants
    }

    /// The kind an event counts as for "one per frame": its case, and its role where that
    /// changes the sound.
    static func kind(of event: RedoubtEvent) -> Int {
        func role(_ r: RedoubtRole) -> Int { RedoubtRole.allCases.firstIndex(of: r)! }
        let roles = RedoubtRole.allCases.count
        return switch event {
        case .waveStarted: 1
        case .waveCleared: 2
        case .airlockClosed: 3
        case .airlockOpened: 4
        case .allColonistsLost: 5
        case .powerCutBegan: 6
        case .powerCutEnded: 7
        case .orbFired: 8
        case .shotEnded: 9
        case .shockwave: 10
        case .chargeEarned: 11
        case .orbDestroyed: 12
        case .lineScattered: 13
        case .orbRespawned: 14
        case .extraLife: 15
        case .arrivalTelegraphed(_, let r, _): r == .skitter ? 16 : 17
        case .enemyArrived: 18
        case .burrowSpawned: 19
        case .spitterWindUp: 20
        case .enemyFired: 21
        case .huskFormed: 22
        case .colonistPickedUp: 23
        case .colonistSeized: 24
        case .colonistFreed: 25
        case .colonistTaken: 26
        case .colonistCrushed: 27
        case .colonistDelivered: 28
        case .gameOver: 29
        case .enemyWithdrew: 30
        case .enemyHit(_, let r, _): 100 + role(r)
        case .enemyDestroyed(_, let r, _, _, _): 100 + roles + role(r)
        }
    }
}
