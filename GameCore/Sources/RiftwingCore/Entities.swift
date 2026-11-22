import GameCore

/// The five opponent roles. The theme gives each its look; the logic knows only what it does.
public enum RiftwingRole: String, Sendable, CaseIterable {
    /// The first Husk rig: slow, flaps lazily, holds height badly and wanders. One blow.
    case glider
    /// Hunts the rider: climbs to get above it, then comes down. One blow.
    case striker
    /// Fast and patient: keeps height and dives. Two blows, or one stoop.
    case warden
    /// Not on a rig; ignores the rider and carries pods off into a tunnel mouth.
    case gleaner
    /// Drifts across the gallery laying tethered mines.
    case sower

    /// Rides a rig: a Husk that drops a pod when knocked off, and must be down for a wave to end.
    public var isRig: Bool { self != .gleaner }

    /// What a pod from this role hatches into if left too long: one grade tougher.
    public var hatchesInto: RiftwingRole {
        switch self {
        case .glider: .striker
        case .striker, .warden, .sower, .gleaner: .warden
        }
    }
}

/// The two tunnel mouths, at the gallery's sides (which join).
public enum RiftwingSide: String, Sendable, CaseIterable {
    /// Flies in at the left edge, heading right.
    case left
    /// Flies in at the right edge, heading left.
    case right
}

/// The flight state every rig shares: the rider's and each opponent's.
public struct RiftwingBody: Sendable, Equatable {
    public var pos: Vec2
    public var vel: Vec2 = .zero
    public var radius: Double
    /// The ledge it stands on, or nil in the air.
    public var ledge: Int?
    /// Wings folded: falling fast.
    public var isDiving = false
    /// Seconds left before the wings are open again after a dive (no flap until then).
    public var reopen = 0.0
    /// Height where the current dive began.
    public var diveStart = 0.0
    /// 1 facing right, -1 facing left.
    public var facing = 1.0
    /// Seconds since its last flap (for the wing pose).
    public var sinceFlap = 99.0

    public var isGrounded: Bool { ledge != nil }

    public init(pos: Vec2, radius: Double) {
        self.pos = pos
        self.radius = radius
    }
}

/// The player's flap-wing rig.
public struct RiftwingRider: Sendable, Equatable {
    public var body: RiftwingBody
    public var isAlive = true
    public var lives: Int
    /// Seconds of protection left after returning.
    public var invulnerableTimer = 0.0
    /// Seconds until a lost rider returns (0 while alive).
    public internal(set) var respawnTimer = 0.0
    /// The vent it is in, if any.
    public internal(set) var vent: Int?

    var flapHeld = false

    public var pos: Vec2 { body.pos }
    public var vel: Vec2 { body.vel }
    public var isInvulnerable: Bool { invulnerableTimer > 0 }
}

/// An opponent in the gallery.
public struct RiftwingOpponent: Sendable, Identifiable, Equatable {
    public enum State: Sendable, Equatable {
        /// Flying its role's pattern.
        case flying
        /// Just hatched from a pod, standing still before it takes off.
        case waking(remaining: Double)
        /// Took a blow but stayed on its rig: tumbling out of control.
        case staggered(remaining: Double)
        /// Gleaner on its way to a resting pod (nil: none to go for, it leaves).
        case seeking(pod: Int?)
        /// Gleaner holding a pod before lifting it.
        case grabbing(pod: Int, remaining: Double)
        /// Gleaner carrying a pod to a tunnel mouth (`exitX` is 0 or the gallery's width).
        case carrying(pod: Int, exitX: Double)
        /// Gleaner leaving through a tunnel mouth with nothing.
        case leaving(exitX: Double)
    }

    public let id: Int
    public var role: RiftwingRole
    public var body: RiftwingBody
    public var state: State
    /// Blows left before it is knocked off.
    public var blows: Int

    /// The ease left for this role in this wave (1 in its first appearance, 0 at full strength).
    var ease = 0.0
    /// Where it is wandering to (Glider), cruising height (Sower), or its target (hunters).
    var goal: Vec2 = .zero
    var timer = 0.0
    var flapCooldown = 0.0
    /// Its top speed this wave (its role's, eased), or a Gleaner's flying or carrying speed.
    var speed = 0.0
    /// Sower: seconds to its next mine; drift direction.
    var mineTimer = 0.0
    var drift = 1.0
    /// A hunter's part in its pattern, and how long it has been in it.
    var phase: HuntPhase = .climbing
    var phaseTime = 0.0
    /// Seconds before it can clash with the rider again.
    var clashCooldown = 0.0
    /// How many recent bounces off the rider it remembers (each fades over
    /// `RiftwingTuning.rammingMemory` seconds).
    var rammed = 0.0
    /// It came from a hatched pod (not from the wave's table).
    public internal(set) var hatched = false
    var isDead = false

    public var pos: Vec2 { body.pos }
    public var vel: Vec2 { body.vel }
}

/// Where a Striker is in its pattern.
enum HuntPhase: Sendable, Equatable {
    /// Getting above the rider.
    case climbing
    /// Committed: coming down on the rider without flapping.
    case striking
    /// Flying off level after a strike, before it climbs again.
    case recovering
}

/// A pod holding a colonist, dropped by a knocked-off rig.
public struct RiftwingPod: Sendable, Identifiable, Equatable {
    public enum State: Sendable, Equatable {
        /// In the air: catch it for double.
        case falling
        /// On a ledge, hatching when `hatchIn` reaches 0.
        case resting(ledge: Int)
        /// In a Gleaner's grip.
        case seized(by: Int)
        /// Its colonist was freed.
        case freed
        /// Lost: to the Rift, hatching, carried off or the breath.
        case lost
    }

    public let id: Int
    public var pos: Vec2
    public var vel: Vec2 = .zero
    public var state: State = .falling
    /// The role of the rig it fell from: it hatches one grade tougher.
    public var from: RiftwingRole
    /// Seconds left before it hatches while it rests (set when it lands).
    public var hatchIn = 0.0
    /// Seconds it has rested on ledges.
    public var restedFor = 0.0
    /// Its fastest fall (slower for a pod from a role in its first appearances).
    public var terminal = 190.0
    /// Its drift across toward a ledge below while it falls (a pod from a role in its first
    /// appearances), and the ledge.
    var drift = 0.0
    var driftLedge: Int?
    /// Seconds the Rift's heat can still hold it up just above the Rift (a pod from a role in its
    /// first appearances).
    public internal(set) var hoverLeft = 0.0
    var warned = false

    /// Seconds before it can be taken, from its drop (`RiftwingTuning.podCatchDelay`).
    public internal(set) var catchableIn = 0.0

    /// True once it can be taken: not in the moment after it is knocked loose.
    public var isCatchable: Bool { catchableIn <= 0 }

    /// Still in play: falling, resting or seized.
    public var isUnsettled: Bool {
        switch state {
        case .falling, .resting, .seized: true
        case .freed, .lost: false
        }
    }
}

/// A mine hanging on a tether below the point where a Sower laid it.
public struct RiftwingMine: Sendable, Identifiable, Equatable {
    public let id: Int
    /// The Sower that laid it.
    public var sower: Int
    /// Where the tether is fixed.
    public var anchor: Vec2
    /// The mine itself, swaying below the anchor.
    public var pos: Vec2
    var age = 0.0
    var phase = 0.0
}

/// An opponent on its way in: the glow shows in a tunnel mouth for `RiftwingTuning.telegraphTime`.
public struct RiftwingArrival: Sendable, Identifiable, Equatable {
    /// The id the opponent will have.
    public let id: Int
    public var role: RiftwingRole
    public var side: RiftwingSide
    /// Where it will appear (at the edge, at its height).
    public var pos: Vec2
    public var remaining: Double
    /// The whole glow, seconds (`remaining` counts down from it).
    public var glowTime = 1.0
    /// No place in the mouths was clear of the rider for `RiftwingTuning.arrivalPatience`: this
    /// one comes out anyway, at the place farthest from the rider, after a longer glow
    /// (`RiftwingTuning.forcedTelegraphTime`).
    public var isForced = false
    /// Seconds it has waited for a clear place.
    var waited = 0.0
}

/// What the Rift is doing.
public enum RiftwingBreath: Sendable, Equatable {
    case calm
    /// Gas is about to rise.
    case warning(remaining: Double)
    /// Gas rising (from the Rift to the run's `breathLevel`), holding, then falling back.
    case rising(remaining: Double)
    case holding(remaining: Double)
    case falling(remaining: Double)
}

/// Where a run is between waves.
public enum RiftwingPhase: Sendable, Equatable {
    /// Before the first wave, or the break after a wave.
    case intermission(remaining: Double)
    case fighting
}
