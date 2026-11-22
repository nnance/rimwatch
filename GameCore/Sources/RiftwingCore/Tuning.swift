import GameCore

/// How one opponent role flies, how big it is and what it is worth.
public struct RiftwingRoleStats: Sendable, Equatable {
    /// Collision radius at `RiftwingTuning.figureScale` 1 (scaled by `stats(for:)`).
    public var radius: Double
    /// Blows needed to knock it off its rig. A stoop always takes one.
    public var blows: Int
    /// Points for knocking it off (or destroying it).
    public var points: Int
    /// Top horizontal speed in the air, units a second.
    public var maxSpeed: Double
    /// Horizontal acceleration while steering.
    public var airAccel: Double
    /// Upward push of one flap.
    public var flapImpulse: Double
    /// Shortest gap between two of its flaps (its wingbeat).
    public var flapInterval: Double
}

/// Every Riftwing gameplay number in one place. The wave makeup is in `RiftwingWaves`, the
/// ledge layouts in `RiftwingCavern`.
///
/// Distances are playfield units: the gallery is `width` x `height` (900 x 600, a 3:2 landscape
/// playfield under the app's thin HUD strip), the origin at the bottom-left, y up. The left and
/// right edges join. Times are seconds, speeds units a second. Every number is a starting value.
public struct RiftwingTuning: Sendable {
    public init() {}

    /// Figure size. Every figure (the rider's rig, each opponent, pods, mines, and the reaches
    /// that follow from their sizes) is its base size times this. The app draws them at the same
    /// factor, so what is drawn is what collides. At 1 the rig is 30 units across, 5% of the
    /// gallery's height, as the owner asked after finding Redoubt's first figures too small.
    /// The gallery, ledges, speeds and heights do not follow it.
    public var figureScale = 1.0

    // The gallery
    public var width = 900.0
    public var height = 600.0
    /// A rig or pod whose centre sinks below this has fallen into the Rift.
    public var riftLevel = 20.0
    /// Seconds before the first wave, and the break between waves.
    public var firstWaveDelay = 1.5
    public var intermission = 2.5
    /// Extra break while the cavern shifts to its next layout (every `wavesPerLayout` waves).
    public var shiftPause = 2.0
    public var wavesPerLayout = 3
    /// Thickness of a ledge (its top is the standing surface).
    public var ledgeThickness = 14.0

    // Flight: the rider's rig. Opponents share the gravity and glide and take their speeds from
    // their role's stats.
    public var gravity = 430.0
    /// One flap: upward speed added (capped at `maxRise`), and speed added along the steer.
    public var flapImpulse = 165.0
    public var flapThrust = 45.0
    public var maxRise = 250.0
    /// Steering in the air leans against momentum: this acceleration toward the steer, up to
    /// `maxAirSpeed`; with no steer the rig glides, losing speed at `airDrag` a second.
    public var airAccel = 300.0
    public var maxAirSpeed = 230.0
    public var airDrag = 0.3
    /// Fastest fall with the wings open; faster falls (after a dive) ease back to it.
    public var terminalFall = 290.0
    public var overspeedDrag = 8.0
    /// Running on a ledge.
    public var runSpeed = 150.0
    public var runAccel = 900.0

    // The dive: wings folded.
    public var diveGravity = 1000.0
    public var diveTerminal = 600.0
    /// Share of the usual steering while diving.
    public var diveSteer = 0.35
    /// Seconds the wings take to open after a dive: no flap until then.
    public var wingReopen = 0.25
    /// How far down the stick must be pulled to dive (touch: the floating stick).
    public var diveStickThreshold = 0.6

    // Sizes at figure scale 1.
    /// The rider's rig: 30 units across.
    public var baseRiderRadius = 15.0
    /// The rider is hit by a mine at a slightly smaller size than it is drawn, so a shave is
    /// forgiven. Clashes use the full size.
    public var baseRiderMineRadius = 12.0
    public var basePodRadius = 9.0
    public var baseMineRadius = 9.0
    /// Extra reach when the rider touches a pod, so a near miss counts.
    public var basePodSlack = 5.0
    /// A rig stands with its centre this far above the ledge (its feet), as a share of its
    /// radius; its head is `headShare` of its radius above its centre.
    public var feetShare = 0.8
    public var headShare = 0.6

    public var riderRadius: Double { baseRiderRadius * figureScale }
    public var riderMineRadius: Double { baseRiderMineRadius * figureScale }
    public var podRadius: Double { basePodRadius * figureScale }
    public var mineRadius: Double { baseMineRadius * figureScale }
    public var podSlack: Double { basePodSlack * figureScale }

    // The clash
    /// Within this many units of level, both bounce apart and nobody is hurt.
    public var clashMargin = 8.0
    /// Heights closer to the roof than this count as the roof's level less the band: pressed
    /// against the roof beside an opponent, you are level with it, so sitting at the top wins
    /// nothing.
    public var roofBand = 12.0
    /// Speed each is thrown apart at in a bounce (horizontal), and the vertical part.
    public var bounceSpeed = 210.0
    public var bounceLift = 60.0
    /// After any clash an opponent cannot clash with the rider again for this long.
    public var clashCooldown = 0.35
    /// The winner of a clash springs up at least this fast.
    public var winLift = 140.0
    /// An opponent that takes a blow but stays on its rig tumbles out of control this long.
    public var staggerTime = 0.7
    /// From below a Gleaner bumps the rider away at this speed.
    public var gleanerBumpSpeed = 180.0

    // Lives
    public var startingLives = 3
    public var maxLives = 5
    public var extraLifeEvery = 35_000
    /// Seconds a lost rider is gone before it returns on a ledge away from the fight.
    public var respawnDelay = 1.5
    public var respawnInvulnerability = 2.5

    // Arrivals
    /// Seconds the glow shows in a tunnel mouth before an opponent flies out.
    public var telegraphTime = 1.0
    /// No opponent arrives closer than this to the rider (round the wrap).
    public var safeDistance = 220.0
    /// If no place in the mouths has been clear of the rider for this long (a rider camping the
    /// side seam), an arrival comes anyway, at the place farthest from the rider, after a glow
    /// this long.
    public var arrivalPatience = 2.5
    public var forcedTelegraphTime = 2.0
    /// Heights at which opponents fly in from the mouths.
    public var arrivalHeights = 140.0...540.0
    /// Speed an opponent flies out of a mouth at.
    public var arrivalSpeed = 120.0
    /// A hatched opponent stands still this long before it takes off.
    public var hatchWake = 0.8

    // Pods
    public var podGravity = 240.0
    public var podTerminal = 150.0
    /// Downward speed a pod is knocked away at, and the share of the rig's speed it keeps.
    public var podKnock = 30.0
    public var podInherit = 0.25
    /// Speed across a knocked pod is thrown at, away from the rider who struck, and seconds after
    /// the drop before it can be taken: a mid-air catch means going after the pod, not flying on
    /// through the blow.
    public var podThrow = 60.0
    public var podCatchDelay = 0.4
    /// Seconds a pod rests on a ledge before it hatches, by wave: `podLifeFirst` in wave 1,
    /// `podLifeShrink` less each wave, never under `podLifeFloor`.
    public var podLifeFirst = 15.0
    public var podLifeShrink = 0.8
    public var podLifeFloor = 7.0
    /// Seconds before hatching that the warning is given.
    public var hatchWarning = 4.0
    /// The nth colonist freed in a wave scores n times this; caught in the air, twice that.
    public var rescuePoints = 500
    public var catchMultiplier = 2
    /// Each colonist freed in a wave scores this at its end.
    public var waveBonusPerColonist = 250

    // Scoring a blow
    /// A stoop scores this many points per unit fallen since the dive began (rounded down to
    /// 50s), up to `stoopBonusCap`.
    public var stoopPointsPerUnit = 2.0
    public var stoopBonusCap = 1000
    /// Points for a blow that does not knock a tough opponent off.
    public var hitPoints = 100

    // Vents: columns of rising air from the Rift.
    /// Upward acceleration inside a vent (more than gravity), and the speed it carries up to.
    public var ventLift = 900.0
    public var ventRise = 210.0
    public var ventHalfWidth = 26.0

    // The Rift's breath: if a wave drags on, gas rises part of the way up the gallery.
    /// Seconds into a wave of the first breath's warning, and between later ones.
    public var breathAfter = 50.0
    public var breathRepeat = 15.0
    public var breathWarning = 3.0
    public var breathRise = 1.0
    public var breathHold = 3.0
    public var breathFall = 1.5
    /// The height the gas reaches: anything whose centre is under the gas while it rises or
    /// holds is lost.
    public var breathLevel = 175.0
    /// Each later breath in the same wave rises this much higher, up to the roof: a wave
    /// stalled anywhere (under the roof, on a high ledge, in a vent) is ended in the end.
    public var breathGrowth = 210.0

    // Opponent behaviour (the eases are in `RiftwingWaves`).
    /// Glider: picks a new place to wander to every so often; skips this share of its flaps.
    public var gliderWander = 2.5...5.0
    public var gliderSkip = 0.3
    /// The heights a Glider wanders between.
    public var gliderBand = 250.0...520.0
    /// Striker: the height above the rider it climbs to before coming down, and how close
    /// across it must be to come down.
    public var strikerClimb = 45.0
    public var strikerStrikeReach = 90.0
    /// The longest a Striker's strike lasts, and how long it flies off level after one.
    public var strikerStrikeTime = 1.4
    public var strikerRecover = 1.0
    /// Seconds a Striker keeps trying to get above the rider before it breaks off.
    public var strikerPatience = 3.5
    /// Seconds between a Striker's or Warden's decisions.
    public var hunterReplan = 0.25
    /// Warden: the height above the rider it keeps, and the reach across within which it dives.
    public var wardenHeight = 80.0
    public var wardenDiveReach = 130.0
    /// Gleaner: free flight (it is not on a rig).
    public var gleanerSpeed = 95.0
    public var gleanerCarrySpeed = 80.0
    /// Seconds it holds a pod before lifting it, and the least time a carry takes from the lift
    /// to the tunnel mouth (both at full strength; eased longer early on).
    public var gleanerGrab = 1.0
    public var gleanerMinCarry = 4.0
    /// Sower (its drift speed is its role's top speed): the band it cruises in, a mine every so
    /// often, at most so many at once, its mines' tether, sway and lifetime.
    public var sowerBand = 260.0...470.0
    public var mineInterval = 3.5
    public var minesPerSower = 4
    public var mineTether = 34.0
    public var mineSway = 5.0
    public var mineLifetime = 18.0
    /// A Sower lays no mine this close to the rider.
    public var mineClearance = 110.0
    /// Opponents flap hard below this height, to keep out of the Rift.
    public var opponentFloor = 140.0

    /// A role's stats with its radius at the current figure scale.
    public func stats(for role: RiftwingRole) -> RiftwingRoleStats {
        var stats = baseStats(for: role)
        stats.radius *= figureScale
        return stats
    }

    /// A role's stats at figure scale 1.
    public func baseStats(for role: RiftwingRole) -> RiftwingRoleStats {
        switch role {
        case .glider:
            RiftwingRoleStats(radius: 14, blows: 1, points: 250, maxSpeed: 110, airAccel: 160,
                              flapImpulse: 150, flapInterval: 0.28)
        case .striker:
            RiftwingRoleStats(radius: 14, blows: 1, points: 500, maxSpeed: 165, airAccel: 260,
                              flapImpulse: 165, flapInterval: 0.22)
        case .warden:
            RiftwingRoleStats(radius: 15, blows: 2, points: 750, maxSpeed: 210, airAccel: 320,
                              flapImpulse: 175, flapInterval: 0.18)
        case .gleaner:
            RiftwingRoleStats(radius: 11, blows: 1, points: 300, maxSpeed: 95, airAccel: 300,
                              flapImpulse: 0, flapInterval: 1)
        case .sower:
            RiftwingRoleStats(radius: 15, blows: 1, points: 600, maxSpeed: 80, airAccel: 160,
                              flapImpulse: 150, flapInterval: 0.25)
        }
    }

    /// A size-derived distance (`base` at figure scale 1) at the current figure scale.
    public func figure(_ base: Double) -> Double { base * figureScale }

    /// The roof: the highest a rig's centre can be is this less its radius.
    public var roof: Double { height }
}
