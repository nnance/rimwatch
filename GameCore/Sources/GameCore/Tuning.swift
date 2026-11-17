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
    public var respawnInvulnerability = 3.0

    // Pulse lance
    public var shotSpeed = 1500.0
    public var shotLifetime = 0.45
    public var shotInterval = 0.1
    public var shotRadius = 3.0
    public var heatPerShot = 0.06
    public var coolingRate = 0.45
    /// An overheated lance fires again once heat falls to this level.
    public var overheatRecovery = 0.45

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
    /// Generous on purpose: catching is the rescuer's skill, and on a touch screen a near miss
    /// should count. The app draws the colonist being pulled in, so it reads as a catch beam.
    public var catchRadius = 40.0
    public var gravity = 180.0
    public var terminalFallSpeed = 210.0
    /// A colonist dropped from higher than this does not survive the landing. A Harvester shot
    /// just after its grab drops its colonist safely; one shot higher up needs a catch.
    public var safeFallHeight = 100.0
    public var deliveryRadius = 44.0
    public var deliveryAltitude = 80.0

    // Harvester
    public var harvesterSpeed = 90.0
    public var harvesterDescentSpeed = 60.0
    /// Horizontal distance from its target at which a Harvester starts to descend.
    public var harvesterDescendRange = 120.0
    public var grabHeight = 18.0
    public var liftSpeed = 30.0
    public var harvesterFireInterval = 1.7...3.1
    public var harvesterFireRange = 380.0
    public var roamSpeed = 60.0
    /// Abductions speed up as the waves go on. A Harvester's approach (travel and descent) is
    /// multiplied by 1 + `abductionGrowthPerWave` for each wave after the first, up to
    /// `abductionMaxScale`; its lift by 1 + `liftGrowthPerWave` a wave, up to the same cap. Wave
    /// 1 stays gentle; waves before `abductionGrowthStart` are unchanged, so new players learn
    /// rescues at the base speeds. Fast approaches mean more grabs than a ship can prevent; a lift slow
    /// enough to reach means the colonist is high when its Harvester dies, so only a catch saves
    /// them: a player who only shoots drifts toward Blackout, a rescuer doesn't.
    public var abductionGrowthPerWave = 0.6
    public var liftGrowthPerWave = 0.1
    public var abductionMaxScale = 3.5
    /// The first wave that is faster than the base speeds.
    public var abductionGrowthStart = 5

    // Husk
    public var huskAcceleration = 340.0
    public var huskMaxSpeed = 270.0
    /// A Husk that has just formed waits this long before it starts hunting.
    public var huskWakeDelay = 4.0

    // Sower and its mines
    public var sowerSpeed = 70.0
    public var mineInterval = 3.0
    public var mineLifetime = 12.0
    public var maxMines = 12

    // Brood and the Motes it bursts into
    public var broodSpeed = 40.0
    public var motesPerBrood = 3
    public var moteBurstSpeed = 200.0
    public var moteAcceleration = 520.0
    public var moteMaxSpeed = 280.0
    /// Random sideways shove that makes Motes weave.
    public var moteJitter = 700.0

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
    public var enemyShotSpeed = 270.0
    public var enemyShotLifetime = 3.0
    public var enemyShotRadius = 4.0
    /// How far ahead of a moving ship enemies aim: 0 aims at the ship, 1 leads it fully.
    public var enemyShotLead = 0.5

    // Waves
    public var firstWaveDelay = 3.0
    public var waveInterval = 2.0
    /// New enemies appear at least this far from the player.
    public var spawnClearance = 700.0
    /// With no colonists or no outposts left, a supply drop arrives after this long.
    public var supplyDelay = 25.0

    // Scoring
    public var catchPoints = 250
    public var deliveryPoints = 500
    public var waveBonusPerColonist = 100
    public var extraLifeEvery = 40_000

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
