import GameCore

/// Decides which of a frame's events are voiced, so the constant small sounds of flight never
/// pile up and never cover what matters. The theme says what each event sounds like; this says
/// whether to play it. It knows nothing about the sounds themselves.
///
/// Every event is in one of three tiers:
/// - **Urgent:** a clash lost, a life lost, a pod lost or seized, the hatch warning, the Rift's
///   warning, the lamps failing, every colonist of a wave lost, game over. Always voiced (once
///   per kind per frame), whatever else is happening.
/// - **Normal:** the rest of what changes the game: waves, clashes, stoops, rescues, dives,
///   hatching, the cavern shifting.
/// - **Small:** the steady sounds of flight and the cavern: flaps, landing, bumping a ledge,
///   vents, mines laid, pods landing, arrival glows, an opponent falling, the gas settling.
///
/// Rules, applied to the events of one frame (one or more simulation steps, told apart by the
/// run's tick):
/// - **One sound per kind of event per frame.**
/// - **Repeats are spaced.** A kind with a gap in `gapTicks` is voiced at most once in that
///   many steps: flaps at most `flapGapTicks` apart (ten a second, faster than a person taps),
///   landings and bumps a quarter of a second apart, and so on.
/// - **Urgent cues clear the air.** For `hushTicks` steps after an urgent cue, small sounds are
///   silent, so a warning is never heard through a flutter of flaps.
/// - **A frame has a budget.** At most `frameBudget` sounds a frame; urgent cues do not count
///   against it and are never refused. Small sounds also stop once the frame has used
///   `smallBudget`, leaving room for what follows in the same frame.
/// - **Versions:** a flap in the air takes one of the theme's pitches at random, never the same
///   twice running, so six a second never sound like a machine.
/// - **Anything unknown is silent:** an event added to the game after this was written makes no
///   sound until it is given a kind here.
///
/// Deterministic: the same events at the same ticks give the same answers.
public struct RiftwingSoundDirector: Sendable {
    public enum Tier: Int, Sendable, Comparable {
        case small, normal, urgent

        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// The run's tick at the frame being voiced; -1 before the first.
    private var frameTick = -1
    /// Kinds already voiced this frame, and how many sounds.
    private var voiced: Set<Int> = []
    private var frameCount = 0
    /// The tick each kind was last voiced at.
    private var lastTick: [Int: Int] = [:]
    /// Small sounds are silent until this tick.
    private var hushUntil = Int.min / 2
    private var random: UInt64 = 0x51F1_5EED_CAFE_F00D
    private var lastFlap = -1

    /// Flaps in the air are voiced at most this often (in 120 Hz steps): ten a second, which no
    /// person taps, so in play every flap is heard, but a stuck or scripted stream stays light.
    public static let flapGapTicks = 12
    /// After an urgent cue, small sounds stay silent this long (a quarter of a second).
    public static let hushTicks = 30
    /// Most sounds a frame (urgent ones are not counted and never refused).
    public static let frameBudget = 4
    /// Small sounds are refused once a frame has this many.
    public static let smallBudget = 2
    /// Pitches the theme offers for a flap (the theme wraps larger numbers).
    public static let pitchVariants = RiftCaves.flapVariants

    public init() {}

    /// Starts over for a new run.
    public mutating func reset() {
        self = RiftwingSoundDirector()
    }

    /// The version of the sound to play for `event`, which `run` has just produced, or nil to
    /// stay silent. Pass the variant to `RiftwingTheme.sound(for:variant:)`.
    public mutating func variant(for event: RiftwingEvent, in run: RiftwingRun) -> Int? {
        variant(for: event, tick: run.tick)
    }

    /// The same from the run's `tick` after the frame's steps.
    public mutating func variant(for event: RiftwingEvent, tick: Int) -> Int? {
        if tick != frameTick {
            frameTick = tick
            voiced.removeAll(keepingCapacity: true)
            frameCount = 0
        }
        guard let kind = Self.kind(of: event) else { return nil }
        let tier = Self.tier(of: event)
        if tier == .small {
            if tick < hushUntil || frameCount >= Self.smallBudget { return nil }
        } else if tier == .normal, frameCount >= Self.frameBudget {
            return nil
        }
        if let gap = Self.gapTicks(of: event), let last = lastTick[kind], tick - last < gap { return nil }
        guard voiced.insert(kind).inserted else { return nil }
        lastTick[kind] = tick
        if tier == .urgent {
            hushUntil = tick + Self.hushTicks
        } else {
            frameCount += 1
        }
        if case .flapped(_, false) = event {
            lastFlap = nextPitch(after: lastFlap)
            return lastFlap
        }
        return 0
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

    /// How much an event matters to the ear (see the type's notes).
    public static func tier(of event: RiftwingEvent) -> Tier {
        switch event {
        case .clashLost, .riderLost, .podLost, .podSeized, .hatchWarning, .riftWarning, .riftFillWarning, .lampsFailed,
             .allColonistsLost, .gameOver:
            .urgent
        case .flapped, .landed, .bumpedLedge, .bumpedRoof, .ventEntered, .mineLaid, .podLanded, .arrivalTelegraphed,
             .opponentFell, .riftSettled:
            .small
        default:
            .normal
        }
    }

    /// The shortest spacing, in steps, between two sounds of an event's kind; nil for none
    /// beyond one a frame.
    static func gapTicks(of event: RiftwingEvent) -> Int? {
        switch event {
        case .flapped(_, false): flapGapTicks
        case .flapped(_, true): 18
        case .landed: 30
        case .bumpedLedge, .bumpedRoof: 30
        case .ventEntered: 120
        case .mineLaid: 30
        case .arrivalTelegraphed: 48
        case .opponentDived: 36
        case .clashBounced, .gleanerBumped: 12
        case .podLanded: 12
        case .opponentFell: 24
        default: nil
        }
    }

    /// The kind an event counts as for "one per frame" and for spacing: its case, with a flap
    /// from a ledge apart from one in the air, and the bounce off a Gleaner the same as a level
    /// bounce (they play one sound). Nil for an event that is never voiced, including any this
    /// was not written to know.
    static func kind(of event: RiftwingEvent) -> Int? {
        switch event {
        case .waveStarted: 1
        case .waveCleared: 2
        case .cavernShifting: 3
        case .cavernShifted: 4
        case .allColonistsLost: 5
        case .lampsFailed: 6
        case .lampsRestored: 7
        case .riftWarning, .riftFillWarning: 8
        case .riftBreathed: 9
        case .riftSettled: 10
        case .flapped(_, let fromLedge): fromLedge ? 12 : 11
        case .landed: 13
        case .bumpedLedge, .bumpedRoof: 14
        case .diveBegan: 15
        case .wingsOpening: 16
        case .ventEntered: 17
        case .clashBounced, .gleanerBumped: 18
        case .clashLost: 19
        case .riderLost: 20
        case .riderRespawned: 21
        case .extraLife: 22
        case .arrivalTelegraphed: 23
        case .opponentDived: 24
        case .opponentHit: 25
        case .opponentDestroyed: 26
        case .opponentFell: 27
        case .mineLaid: 28
        case .mineCleared(_, _, let reason):
            switch reason {
            case .sowerDown, .expired: 29
            case .waveEnded, .struck: nil
            }
        case .podDropped: 30
        case .podLanded: 31
        case .podFreed: 32
        case .podCaught: 33
        case .podSeized: 34
        case .podCarried: 35
        case .podLost: 36
        case .hatchWarning: 37
        case .podHatched: 38
        case .gameOver: 39
        // Silent on purpose (see `RiftCaves.soundName(for:variant:)`), and anything unknown.
        default: nil
        }
    }
}
