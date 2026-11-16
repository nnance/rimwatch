public struct EnemyStats: Sendable {
    public var radius: Double
    /// Lance hits needed to destroy it.
    public var hp: Int
    public var points: Int
}

/// Every gameplay number in one place. Distances are world units (one unit is roughly one point
/// on the inner display), times are seconds, speeds are units per second.
public struct Tuning: Sendable {
    public init() {}

    // World
    public var worldWidth = 7200.0
    public var worldHeight = 600.0
    /// Entities cannot rise above `worldHeight - ceilingMargin`.
    public var ceilingMargin = 40.0
    public var outpostCount = 5
    public var colonistsPerOutpost = 2

    // Player flight
    public var thrust = 1500.0
    public var drag = 1.4
    public var maxSpeed = 560.0
    public var verticalSpeed = 330.0
    public var playerRadius = 12.0
    public var startingLives = 3
    public var maxLives = 5
    public var respawnDelay = 1.5
    public var respawnInvulnerability = 2.5

    // Pulse lance
    public var shotSpeed = 1500.0
    public var shotLifetime = 0.45
    public var shotInterval = 0.1
    public var shotRadius = 3.0
    public var heatPerShot = 0.07
    public var coolingRate = 0.4
    /// An overheated lance fires again once heat falls to this level.
    public var overheatRecovery = 0.35

    // Shockwave: destroys every enemy and enemy shot within range of the ship.
    public var startingShockwaves = 3
    public var maxShockwaves = 5
    public var shockwaveRange = 480.0
    /// One charge is awarded each time this many waves have started.
    public var wavesPerShockwave = 3

    // Blink: an instant short dash.
    public var blinkDistance = 220.0
    public var blinkCooldown = 2.5
    public var blinkInvulnerability = 0.25

    // Shield: full at 1, absorbs one hit, refilled by bringing colonists home.
    public var shieldPerDelivery = 0.5
    public var shieldBreakInvulnerability = 1.0

    // Colonists
    public var catchRadius = 26.0
    public var gravity = 220.0
    public var terminalFallSpeed = 260.0
    /// A colonist dropped from higher than this does not survive the landing.
    public var safeFallHeight = 150.0
    public var deliveryRadius = 44.0
    public var deliveryAltitude = 80.0

    // Harvester
    public var harvesterSpeed = 90.0
    public var harvesterDescentSpeed = 60.0
    /// Horizontal distance from its target at which a Harvester starts to descend.
    public var harvesterDescendRange = 120.0
    public var grabHeight = 18.0
    public var liftSpeed = 45.0
    public var harvesterFireInterval = 2.5...4.5
    public var harvesterFireRange = 500.0
    public var roamSpeed = 60.0

    // Husk
    public var huskAcceleration = 420.0
    public var huskMaxSpeed = 300.0

    // Sower and its mines
    public var sowerSpeed = 70.0
    public var mineInterval = 3.0
    public var mineLifetime = 12.0
    public var maxMines = 12

    // Brood and the Motes it bursts into
    public var broodSpeed = 40.0
    public var motesPerBrood = 4
    public var moteBurstSpeed = 200.0
    public var moteAcceleration = 700.0
    public var moteMaxSpeed = 340.0
    /// Random sideways shove that makes Motes weave.
    public var moteJitter = 900.0

    // Lancer
    public var lancerPatrolSpeed = 50.0
    /// Horizontal distance at which a Lancer notices the player and winds up.
    public var lancerRange = 520.0
    public var lancerTelegraph = 0.8
    /// How fast it matches the player's altitude while winding up.
    public var lancerTrackSpeed = 260.0
    public var lancerChargeSpeed = 900.0
    public var lancerChargeTime = 1.1
    public var lancerRecovery = 2.0

    // Anchor
    public var anchorSpeed = 70.0
    public var anchorDescentSpeed = 50.0
    /// Seconds of drilling that destroy an outpost.
    public var drillTime = 15.0
    /// Colonists standing this close to an outpost are lost with it.
    public var outpostBlastRadius = 70.0

    // Enemy shots
    public var enemyShotSpeed = 240.0
    public var enemyShotLifetime = 3.0
    public var enemyShotRadius = 4.0

    // Waves
    public var firstWaveDelay = 1.0
    public var waveInterval = 2.0
    /// New enemies appear at least this far from the player.
    public var spawnClearance = 700.0
    /// With no colonists or no outposts left, a supply drop arrives after this long.
    public var supplyDelay = 25.0

    // Scoring
    public var catchPoints = 250
    public var deliveryPoints = 500
    public var waveBonusPerColonist = 100
    public var extraLifeEvery = 10_000

    public func stats(for kind: EnemyKind) -> EnemyStats {
        switch kind {
        case .harvester: EnemyStats(radius: 14, hp: 1, points: 150)
        case .husk: EnemyStats(radius: 13, hp: 1, points: 250)
        case .sower: EnemyStats(radius: 15, hp: 1, points: 200)
        case .mine: EnemyStats(radius: 8, hp: 1, points: 25)
        case .brood: EnemyStats(radius: 20, hp: 2, points: 300)
        case .mote: EnemyStats(radius: 7, hp: 1, points: 75)
        case .lancer: EnemyStats(radius: 12, hp: 1, points: 350)
        case .anchor: EnemyStats(radius: 18, hp: 3, points: 500)
        }
    }
}
