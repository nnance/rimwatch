import Foundation
import GameCore

/// The six enemy roles. The theme gives each its look; the logic knows only what it does.
public enum RedoubtRole: String, Sendable, CaseIterable {
    /// The flood: walks at the orb; one shot.
    case skitter
    /// Goes for colonists and drags one to the nearest Burrow or the wall.
    case gleaner
    /// Keeps its distance and fires slow shots.
    case spitter
    /// A hole in the floor that pours out Skitters until destroyed.
    case burrow
    /// Slow and heavy. Shots only push it back; only a Shockwave destroys it.
    case thresher
    /// The fast hunter. Also what a Gleaner becomes when it gets a colonist away.
    case husk

    /// Must be destroyed to clear a wave. Threshers need not be.
    public var holdsWave: Bool { self != .thresher }
}

/// One of the four walls round the floor.
public enum ArenaWall: String, Sendable, CaseIterable {
    case north, south, east, west
}

/// The player's hover orb.
public struct Orb: Sendable, Equatable {
    public var pos: Vec2
    public var vel: Vec2 = .zero
    /// Radians (0 along +x, counterclockwise, y up): the aim while aiming, else the way it moved.
    public var heading = Double.pi / 2
    public var isAlive = true
    public var lives: Int
    /// Shockwave charges.
    public var charges: Int
    /// Seconds of protection left after a respawn.
    public var invulnerableTimer = 0.0
    /// True while the aim stick is pushed (it fires on its own cadence).
    public var isFiring = false

    var fireCooldown = 0.0
    /// Seconds until a lost orb comes back (0 while it is alive).
    public internal(set) var respawnTimer = 0.0
    var shockwaveHeld = false

    public var isInvulnerable: Bool { invulnerableTimer > 0 }
}

/// An enemy on the floor.
public struct RedoubtEnemy: Sendable, Identifiable, Equatable {
    public enum State: Sendable, Equatable {
        /// Skitter, Husk or Thresher going for the orb.
        case hunting
        /// A Husk just formed from a Gleaner, not yet moving.
        case waking(remaining: Double)
        /// Gleaner heading for a colonist (nil: none to go for, it wanders).
        case seeking(colonist: Int?)
        /// Gleaner dragging a colonist to `destination` (a Burrow or the wall).
        case dragging(colonist: Int, destination: Vec2)
        /// Spitter holding its distance.
        case keepingDistance
        /// Spitter about to fire: it holds still. The renderer should make this visible.
        case windingUp(remaining: Double)
        /// Burrow pouring out Skitters.
        case pouring
    }

    public let id: Int
    public var role: RedoubtRole
    public var pos: Vec2
    /// Its own movement (push-back is separate, in `push`).
    public var vel: Vec2 = .zero
    /// Radians, as `Orb.heading`.
    public var heading = 0.0
    public var radius: Double
    public var hp: Int
    public var state: State
    /// Push-back velocity from shots, a Shockwave or a respawn, dying away over time.
    public var push: Vec2 = .zero

    /// Per-enemy speed factor (Skitters) or strafe direction (Spitters).
    var trait = 1.0
    /// General clock: fire timer, spawn timer, wobble phase.
    var timer = 0.0
    /// Seconds since a Gleaner seized the colonist it is dragging.
    var held = 0.0
    /// Id of the Burrow that poured it out, if any.
    var parent: Int?
    var isDead = false
}

/// A shot in flight.
public struct RedoubtShot: Sendable, Identifiable, Equatable {
    public enum Owner: Sendable, Equatable {
        case orb
        case enemy
    }

    public let id: Int
    public var owner: Owner
    public var pos: Vec2
    public var vel: Vec2
    public var radius: Double

    var timeLeft: Double
}

/// A colonist on the floor.
public struct RedoubtColonist: Sendable, Identifiable, Equatable {
    public enum State: Sendable, Equatable {
        /// Waiting where they are for the orb.
        case sheltering
        /// In the orb's line; `RedoubtRun.line` gives the order.
        case following
        /// Being dragged away by the Gleaner with this id.
        case seized(by: Int)
        /// Through the airlock.
        case delivered
        /// Taken (by a Gleaner or off the end of the line) or crushed by a Thresher.
        case lost
    }

    public let id: Int
    public var pos: Vec2
    public var state: State = .sheltering
    /// Drift after a scatter, dying away by `pushDecay`.
    public var vel: Vec2 = .zero

    /// Id of the Gleaner on its way to them, so two don't go for the same one.
    var claimedBy: Int?

    /// Still in play this wave: sheltering, following or seized.
    public var isSafeOrSeized: Bool {
        switch state {
        case .sheltering, .following, .seized: true
        case .delivered, .lost: false
        }
    }
}

/// The way out: an opening in one wall. It moves between waves.
public struct Airlock: Sendable, Equatable {
    public var wall: ArenaWall
    /// Centre of the opening, on the wall line.
    public var pos: Vec2
    /// Width of the opening along the wall.
    public var width: Double
    /// Open during a wave (it takes deliveries), shut between waves while it moves.
    public var isOpen: Bool
}

/// An enemy on its way in: shown for `RedoubtTuning.telegraphTime` before it appears.
public struct RedoubtArrival: Sendable, Identifiable, Equatable {
    /// The id the enemy will have.
    public let id: Int
    public var role: RedoubtRole
    public var pos: Vec2
    /// Seconds until it appears.
    public var remaining: Double
}

/// Where a run is between waves.
public enum RedoubtPhase: Sendable, Equatable {
    /// Before the first wave, or between a cleared wave and the next.
    case intermission(remaining: Double)
    /// A wave is on.
    case fighting
}
