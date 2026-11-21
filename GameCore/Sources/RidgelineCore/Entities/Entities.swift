import GameCore

public struct Player: Sendable {
    public var pos: Vec2
    public var vel: Vec2 = .zero
    /// +1 facing right, -1 facing left.
    public var facing = 1.0
    /// Lance heat, 0...1.
    public var heat = 0.0
    public var isOverheated = false
    public var lives: Int
    public var isAlive = true
    /// Seconds of protection left after a respawn, a Blink or a broken shield.
    public var invulnerableTimer = 0.0
    /// 0...1. At 1 the shield absorbs the next hit.
    public var shield = 0.0
    public var shockwaves: Int
    /// Seconds until Blink can be used again.
    public var blinkCooldown = 0.0
    /// Ids of the colonists being carried, in the order they were caught.
    public var carried: [Int] = []

    var fireCooldown = 0.0
    var respawnTimer = 0.0
    // Shockwave and Blink trigger on the press, not while held.
    var shockwaveHeld = false
    var blinkHeld = false
}

public struct Colonist: Sendable, Identifiable {
    public enum State: Sendable, Equatable {
        case grounded
        /// Being lifted by the Harvester with this id.
        case held(by: Int)
        /// `from` is the height above the ground at which the fall began.
        case falling(speed: Double, from: Double)
        case carried
        case lost
    }

    public let id: Int
    public var pos: Vec2
    public var state: State = .grounded
    /// Id of the outpost this colonist belongs to.
    public var home: Int

    /// Id of the Harvester on its way to grab this colonist, so two don't chase the same one.
    var claimedBy: Int?
}

public enum EnemyKind: String, Sendable, CaseIterable {
    /// Abducts colonists.
    case harvester
    /// A Harvester that completed an abduction. Chases the player.
    case husk
    /// Drifts across the world laying mines.
    case sower
    /// Stationary, short-lived, deadly to touch.
    case mine
    /// Slow and tough. Bursts into Motes when destroyed.
    case brood
    /// Small, fast, weaving chaser.
    case mote
    /// Winds up, then charges across the screen at the player's altitude.
    case lancer
    /// Lands on an outpost and drills until the outpost is destroyed.
    case anchor
}

public struct Enemy: Sendable, Identifiable {
    public enum State: Sendable, Equatable {
        /// Harvester heading for a colonist (nil until it has picked one).
        case seeking(target: Int?)
        /// Harvester rising with a colonist.
        case lifting(colonist: Int)
        /// Harvester or Anchor with nothing to go after.
        case roaming
        /// Husk or Mote chasing the player.
        case hunting
        /// Sower or Brood crossing the world.
        case drifting
        /// Mine waiting to be touched.
        case armed
        /// Lancer cruising, out of range of the player.
        case patrolling
        /// Lancer winding up. The renderer should make this obvious.
        case telegraphing(remaining: Double)
        case charging(remaining: Double)
        case recovering(remaining: Double)
        /// Anchor on its way down to an outpost.
        case descending(outpost: Int)
        case drilling(outpost: Int)
    }

    public let id: Int
    public var kind: EnemyKind
    public var pos: Vec2
    public var vel: Vec2 = .zero
    public var radius: Double
    public var hp: Int
    public var state: State

    var fireTimer = 0.0
    /// General-purpose clock: a mine's remaining life, a drifter's bobbing phase.
    var timer = 0.0
    /// Set to remove the enemy at the end of the step without scoring it.
    var expired = false
}

public struct Projectile: Sendable, Identifiable {
    public enum Owner: Sendable, Equatable {
        case player
        case enemy
    }

    public let id: Int
    public var pos: Vec2
    public var vel: Vec2
    public var owner: Owner
    public var radius: Double

    var timeLeft: Double
}
