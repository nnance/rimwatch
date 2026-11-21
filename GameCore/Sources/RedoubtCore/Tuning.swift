import GameCore

/// Size, toughness and worth of one enemy role.
public struct RedoubtRoleStats: Sendable, Equatable {
    public var radius: Double
    /// Shots needed to destroy it. `Int.max` for a role shots cannot destroy.
    public var hp: Int
    /// Points for destroying it.
    public var points: Int
}

/// Every Redoubt gameplay number in one place. The wave makeup is in `RedoubtWaves`.
///
/// Distances are arena units: the floor is `arenaWidth` x `arenaHeight` (900 x 600, a 3:2
/// landscape playfield; the app scales it to fit under a thin HUD strip). Times are seconds,
/// speeds are units per second. The design calls every number here a starting value.
public struct RedoubtTuning: Sendable {
    public init() {}

    // Arena
    public var arenaWidth = 900.0
    public var arenaHeight = 600.0
    /// Seconds before the first wave, and between a wave's clear and the next wave.
    public var firstWaveDelay = 1.5
    public var intermission = 2.0

    // Orb
    public var orbRadius = 10.0
    /// The orb's size for being hit (by an enemy or a shot): a little smaller than it looks, so a
    /// shave in a crowd is forgiven.
    public var orbHitRadius = 7.0
    public var orbMaxSpeed = 280.0
    /// The glide: seconds for the orb's velocity to close about 63% of the gap to what the stick
    /// asks for, speeding up and slowing down alike. Small enough to feel direct; large enough
    /// that it reads as a craft and not a walker.
    public var orbResponse = 0.07
    public var startingLives = 3
    public var maxLives = 5
    /// Seconds the orb is gone after a hit before it comes back at the centre.
    public var respawnDelay = 1.2
    public var respawnInvulnerability = 2.5
    /// On respawn, enemies this close to the centre are shoved away and enemy shots removed.
    public var respawnClearRadius = 150.0
    public var respawnPush = 520.0

    // Fire: continuous while the aim stick is pushed past `aimThreshold`. No heat, no reload.
    public var aimThreshold = 0.3
    public var shotInterval = 0.1
    public var shotSpeed = 900.0
    public var shotRadius = 3.0
    /// Long enough to cross the floor; shots also stop at the wall.
    public var shotLifetime = 1.3

    // Shockwave
    public var startingCharges = 1
    public var maxCharges = 3
    /// Every enemy and enemy shot this close to the orb is destroyed, Threshers and Burrows too.
    public var shockwaveClearRadius = 150.0
    /// Enemies beyond the clear radius but inside this one are pushed away, harder the closer.
    public var shockwavePushRadius = 340.0
    public var shockwavePush = 1000.0
    /// A charge is earned each time this many colonists have been delivered.
    public var colonistsPerCharge = 4

    // Push-back (Shockwave, respawn, shots on a Thresher): a velocity that dies away at this rate.
    public var pushDecay = 5.0

    // Colonists
    public var colonistRadius = 6.0
    /// Extra reach when the orb touches a sheltering colonist, so a near miss counts.
    public var pickupSlack = 6.0
    /// Gap between neighbours in the line (orb to first follower, and so on).
    public var lineSpacing = 17.0
    /// Distance from the airlock's centre within which the orb delivers its line.
    public var airlockReach = 36.0
    /// Width of the airlock's opening in the wall, for the renderer.
    public var airlockWidth = 56.0
    /// A new airlock position is at least this far from the last one.
    public var airlockMinMove = 300.0
    /// Colonists start at least this far from the orb, the airlock and the wall.
    public var colonistClearance = 120.0
    public var colonistWallMargin = 50.0
    /// Speed a scattered colonist is flung at when the orb is lost; it dies away by `pushDecay`.
    public var scatterSpeed = 140.0

    // Arrivals
    /// Nothing appears closer to the orb than this.
    public var safeDistance = 190.0
    /// Seconds an arrival is shown before the enemy appears.
    public var telegraphTime = 1.0
    /// Arrivals keep this far from the wall.
    public var spawnWallMargin = 24.0
    /// Hard cap on enemies on the floor, Burrow spawns included.
    public var maxEnemies = 120
    /// Running the wall. While the orb hugs a wall and runs along it (its centre within
    /// `wallRunGap` of a wall, faster than `wallRunSpeed`, with at least `wallRunAlong` of that
    /// speed along the wall), each top-up group is telegraphed on its path `wallRunReach` ahead
    /// of it instead of at a random side. Added in 13d: without it, laps of the wall while firing
    /// at the nearest enemy were safer than fighting. Set `wallRunGap` to 0 to turn it off.
    public var wallRunGap = 40.0
    public var wallRunSpeed = 100.0
    public var wallRunAlong = 0.9
    public var wallRunReach = 400.0...520.0
    /// The main push and the scatter (`RedoubtWaves.pushAndScatter`), added after the owner's
    /// second play. While a wave has entry walls (`RedoubtWaves.entrySides`), the main push of
    /// its opening crowd lands within `pushDepth` of one of them, thinning out away from the wall
    /// (its distance in from the wall's margin is the depth times a random fraction raised to
    /// `pushFalloff`), so it reads as a front rather than a line. Along the wall each spot is the
    /// nearest one end of `pushAlongDraws` draws, so the push leans toward the end away from the
    /// orb (a random end while the orb is level with the middle). The scatter
    /// (`RedoubtWaves.scatterShare`) lands anywhere at least `scatterClearance` from the orb. The main wall is drawn with each allowed wall weighted
    /// by its distance from the orb raised to `mainWallWeighting` (0: all equally likely), and
    /// each top-up group lands at the farthest from the orb of `groupSpotDraws` clear spots along
    /// the entry walls.
    public var pushDepth = 260.0
    public var pushFalloff = 1.5
    public var pushAlongDraws = 4
    public var scatterClearance = 300.0
    public var mainWallWeighting = 2.0
    public var groupSpotDraws = 6
    /// With `RedoubtWaves.pushAndScatter` off (the first 13d ease): the whole opening crowd lands
    /// within this distance of an entry wall, and the walls are chosen by scoring each its
    /// distance from the orb plus a random amount up to `entrySideJitter`, highest first.
    public var entryBandDepth = 180.0
    public var entrySideJitter = 300.0

    // Skitter: the flood.
    public var skitterSpeed = 50.0
    /// Skitter speed grows by this fraction a wave after the first, up to `skitterMaxScale`.
    public var skitterSpeedGrowth = 0.09
    public var skitterMaxScale = 2.2
    /// Each Skitter's speed is the base times a factor from this range.
    public var skitterSpeedSpread = 0.8...1.2
    /// How much a Skitter wanders off its line to the orb (radians of wobble).
    public var skitterWobble = 0.6

    // Gleaner
    public var gleanerSpeed = 95.0
    public var gleanerDragSpeed = 60.0
    /// Seconds a Husk formed from a Gleaner waits before it hunts.
    public var huskWakeDelay = 1.0

    // Spitter
    public var spitterSpeed = 85.0
    /// The distance from the orb it tries to hold.
    public var spitterRange = 230.0...320.0
    public var spitterFireInterval = 2.0...3.0
    /// Its fire interval is scaled by 1 - this per wave after its debut, down to `spitterMinScale`.
    public var spitterFireGrowth = 0.06
    public var spitterMinScale = 0.45
    /// It holds still and glows this long before each shot.
    public var spitterWindUp = 0.4
    /// It only fires at an orb closer than this.
    public var spitterFireRange = 480.0
    public var spitterShotSpeed = 165.0
    public var spitterShotRadius = 5.0
    public var spitterShotLifetime = 6.0
    /// 0 aims at the orb, 1 leads it fully.
    public var spitterShotLead = 0.3

    // Burrow
    public var burrowSpawnInterval = 2.4
    /// Its spawn interval shrinks by this fraction a wave after its debut, down to `burrowMinScale`.
    public var burrowSpawnGrowth = 0.05
    public var burrowMinScale = 0.6
    /// A Burrow stops pouring while this many of its Skitters are alive.
    public var burrowMaxChildren = 10
    /// While fewer than this many shootable enemies are on the floor, Burrows pour this much
    /// faster (interval multiplied by the scale).
    public var burrowThinFloor = 8
    public var burrowThinFloorScale = 0.4
    /// Burrows open at least this far from the centre (where the orb respawns).
    public var burrowCentreClearance = 160.0

    // Thresher
    public var thresherSpeed = 34.0
    /// How quickly it turns toward the orb (radians a second).
    public var thresherTurnRate = 0.9
    /// Push each shot gives it, along the shot's travel.
    public var thresherShotPush = 42.0

    // Husk
    public var huskAcceleration = 700.0
    public var huskMaxSpeed = 205.0

    // Separation: overlapping enemies are moved apart by this fraction of the overlap each step.
    public var separationStrength = 0.5

    // Scoring
    /// The nth colonist in a delivered line scores n times this.
    public var deliveryPoints = 500
    /// Each colonist still safe when a wave is cleared.
    public var waveBonusPerColonist = 250
    public var extraLifeEvery = 60_000

    public func stats(for role: RedoubtRole) -> RedoubtRoleStats {
        switch role {
        case .skitter: RedoubtRoleStats(radius: 8, hp: 1, points: 50)
        case .gleaner: RedoubtRoleStats(radius: 10, hp: 1, points: 150)
        case .spitter: RedoubtRoleStats(radius: 11, hp: 2, points: 200)
        case .burrow: RedoubtRoleStats(radius: 18, hp: 20, points: 1000)
        case .thresher: RedoubtRoleStats(radius: 17, hp: .max, points: 1500)
        case .husk: RedoubtRoleStats(radius: 9, hp: 1, points: 250)
        }
    }

    /// The largest enemy radius, for grid queries.
    var maxEnemyRadius: Double {
        RedoubtRole.allCases.map { stats(for: $0).radius }.max() ?? 20
    }
}
