import GameCore

/// Maps the wraparound world onto the scanner strip. The strip shows the whole world once,
/// centred on `centerX` (the app passes the camera), so whatever is on screen sits in the middle
/// of the strip and the world wraps round either side of it. Positions come out as fractions of
/// the strip: x in 0...1 from left to right, y in 0...1 from the ground line up.
public struct ScannerProjection: Sendable, Equatable {
    public let worldWidth: Double
    public let worldHeight: Double
    public let centerX: Double

    public init(worldWidth: Double, worldHeight: Double, centerX: Double) {
        self.worldWidth = worldWidth
        self.worldHeight = worldHeight
        self.centerX = centerX
    }

    public init(world: World, centerX: Double) {
        self.init(worldWidth: world.width, worldHeight: world.height, centerX: centerX)
    }

    /// Horizontal position of world `x` on the strip, in 0...1. The centre maps to 0.5; a point
    /// half a world away maps to an end.
    public func x(_ x: Double) -> Double {
        0.5 + Self.delta(from: centerX, to: x, width: worldWidth) / worldWidth
    }

    public func y(_ y: Double) -> Double {
        min(max(y / worldHeight, 0), 1)
    }

    public func point(_ p: Vec2) -> Vec2 {
        Vec2(x(p.x), y(p.y))
    }

    /// Where world x = 0 falls on the strip. A strip-wide picture of the world drawn from x = 0
    /// is placed here and again one strip-width to the left, which covers the strip exactly.
    public var originX: Double {
        x(0)
    }

    /// The strip range covered by the visible part of the world, `halfWidth` world units either
    /// side of the centre. Clamped to the strip when the view is wider than the world.
    public func visibleRange(halfWidth: Double) -> ClosedRange<Double> {
        let half = min(max(halfWidth / worldWidth, 0), 0.5)
        return (0.5 - half)...(0.5 + half)
    }

    private static func delta(from a: Double, to b: Double, width: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: width)
        if d > width / 2 {
            d -= width
        } else if d <= -width / 2 {
            d += width
        }
        return d
    }
}

/// How the scanner should show each thing, by role and state. The app picks colours from the
/// theme; this only says which kind of mark each one gets.
public enum ScannerMark: Sendable, Hashable {
    case player
    case enemy(EnemyKind)
    case colonist(ColonistMark)
    case outpost(OutpostMark)

    public enum ColonistMark: Sendable, Hashable {
        case grounded
        /// In a Harvester's grip.
        case held
        case falling
        /// Riding with the player.
        case carried
    }

    public enum OutpostMark: Sendable, Hashable {
        case intact
        /// Being drilled.
        case damaged
        case destroyed
    }

    /// The mark for a colonist, or nil for one that is lost.
    public static func forColonist(_ state: Colonist.State) -> ScannerMark? {
        switch state {
        case .grounded: .colonist(.grounded)
        case .held: .colonist(.held)
        case .falling: .colonist(.falling)
        case .carried: .colonist(.carried)
        case .lost: nil
        }
    }

    public static func forOutpost(integrity: Double) -> ScannerMark {
        if integrity <= 0 { return .outpost(.destroyed) }
        return integrity < 1 ? .outpost(.damaged) : .outpost(.intact)
    }
}

/// Everything the HUD shows, read from the simulation without changing it.
public struct HUDReadout: Sendable, Equatable {
    public var score: Int
    /// The current wave, at least 1.
    public var wave: Int
    public var lives: Int
    public var shockwaves: Int
    public var maxShockwaves: Int
    /// Lance heat, 0...1.
    public var heat: Double
    public var isOverheated: Bool
    /// Shield charge, 0...1; at 1 it absorbs the next hit.
    public var shield: Double
    /// How far Blink has recharged, 0...1; 1 means ready.
    public var blinkReadiness: Double
    public var carried: Int
    /// Points multiplier for the colonists being carried: each one delivered scores the delivery
    /// points times the number carried. 1 when carrying one or none.
    public var multiplier: Int
    public var survivors: Int
    public var isPlayerAlive: Bool
    public var isBlackout: Bool

    public init(_ sim: Simulation) {
        let player = sim.player
        let tuning = sim.tuning
        score = sim.score
        wave = max(sim.wave, 1)
        lives = max(player.lives, 0)
        shockwaves = player.shockwaves
        maxShockwaves = tuning.maxShockwaves
        heat = min(max(player.heat, 0), 1)
        isOverheated = player.isOverheated
        shield = min(max(player.shield, 0), 1)
        blinkReadiness = tuning.blinkCooldown > 0
            ? 1 - min(max(player.blinkCooldown / tuning.blinkCooldown, 0), 1)
            : 1
        carried = player.carried.count
        multiplier = max(player.carried.count, 1)
        survivors = sim.survivingColonists
        isPlayerAlive = player.isAlive
        isBlackout = sim.isBlackout
    }
}
