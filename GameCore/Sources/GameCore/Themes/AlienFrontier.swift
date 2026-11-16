import Foundation

/// The first theme: a rust-red frontier planet under a black sky, with neon-bright craft.
public struct AlienFrontier: Theme {
    public init() {}

    public let name = "Alien Frontier"

    public let palette = Palette(
        background: RGB(0, 0, 0),
        stars: RGB(hex: 0x8090B0),
        warning: RGB(hex: 0xFF3030),
        falling: RGB(hex: 0xFFFF80),
        shield: RGB(hex: 0x60B0FF),
        spark: RGB(hex: 0xFFD080),
        controls: RGB(hex: 0x60E0FF),
        hud: RGB(hex: 0x60E0FF)
    )

    public let terrain = TerrainStyle(
        ridge: RGB(hex: 0xFF7A3D),
        strata: RGB(hex: 0x8A3418),
        strataOffsets: [14, 34, 62],
        blackoutRidge: RGB(hex: 0x3A1C10)
    )

    public func shape(for role: EntityRole) -> ShapeDescription {
        switch role {
        case .player: Self.skimmer
        case .enemy(let kind):
            switch kind {
            case .harvester: Self.harvester
            case .husk: Self.husk
            case .sower: Self.sower
            case .mine: Self.mine
            case .brood: Self.brood
            case .mote: Self.mote
            case .lancer: Self.lancer
            case .anchor: Self.anchor
            }
        case .colonist: Self.colonist
        case .outpost: Self.outpost
        case .ruin: Self.ruin
        case .projectile(.player): Self.pulse
        case .projectile(.enemy): Self.spore
        }
    }

    public func displayName(for role: EntityRole) -> String {
        switch role {
        case .player: "Skimmer"
        case .enemy(let kind):
            switch kind {
            case .harvester: "Harvester"
            case .husk: "Husk"
            case .sower: "Sower"
            case .mine: "Mine"
            case .brood: "Brood"
            case .mote: "Mote"
            case .lancer: "Lancer"
            case .anchor: "Anchor"
            }
        case .colonist: "Colonist"
        case .outpost: "Outpost"
        case .ruin: "Ruined outpost"
        case .projectile(.player): "Pulse"
        case .projectile(.enemy): "Spore"
        }
    }

    /// Every event that makes a sound names its patch here. Step 7 synthesises them; the names
    /// are stable identifiers, prefixed with the theme so a second theme can't collide.
    public func sound(for event: GameEvent) -> SoundPatch? {
        let name: String? = switch event {
        case .waveStarted: "wave.start"
        case .waveCleared: "wave.clear"
        case .playerFired: "lance.fire"
        case .playerOverheated: "lance.overheat"
        case .playerBlinked: "blink"
        case .shockwave: "shockwave"
        case .shieldCharged: "shield.charged"
        case .shieldBroken: "shield.break"
        case .playerDestroyed: "player.explode"
        case .playerRespawned: "player.respawn"
        case .extraLife: "life.extra"
        case .enemySpawned(_, let kind): kind == .mote ? "mote.hatch" : "enemy.warp"
        case .enemyFired: "spore.fire"
        case .enemyHit: "enemy.hit"
        case .enemyDestroyed(_, let kind, _, _):
            switch kind {
            case .mine: "mine.pop"
            case .mote: "mote.pop"
            case .brood: "brood.burst"
            case .anchor: "anchor.explode"
            default: "enemy.explode"
            }
        case .huskFormed: "husk.form"
        case .mineLaid: "mine.lay"
        case .lancerTelegraph: "lancer.windup"
        case .lancerCharged: "lancer.charge"
        case .anchorLanded: "anchor.land"
        case .colonistGrabbed: "colonist.grabbed"
        case .colonistDropped: "colonist.dropped"
        case .colonistCaught: "colonist.caught"
        case .colonistDelivered: "colonist.delivered"
        case .colonistLanded: "colonist.landed"
        case .colonistLost: "colonist.lost"
        case .outpostDestroyed: "outpost.destroyed"
        case .outpostRestored: "outpost.supply"
        case .blackoutBegan: "blackout.begin"
        case .blackoutEnded: "blackout.end"
        case .gameOver: "game.over"
        }
        return name.map { SoundPatch(name: "frontier.\($0)") }
    }

    // MARK: Shapes

    private static func v(_ x: Double, _ y: Double) -> Vec2 { Vec2(x, y) }

    /// A swept dart with a split tail.
    static let skimmer: ShapeDescription = {
        let top = [v(1, 0), v(0.25, 0.2), v(-0.5, 0.45), v(-0.9, 0.45), v(-0.62, 0.12), v(-0.78, 0)]
        let hull = top + ShapeKit.mirroredY(top.dropLast().reversed())
        let c = RGB(hex: 0x3FF6FF)
        return ShapeDescription(scale: 18, strokes: [
            ShapeStroke(Array(hull.dropLast()), closed: true, color: c),
            ShapeStroke([v(0.5, 0.02), v(0.15, 0.12), v(-0.15, 0.09)], color: RGB(hex: 0xE0FFFF)),
            ShapeStroke([v(-0.45, 0.25), v(-0.45, -0.25)], color: c),
        ])
    }()

    /// A six-sided pod with three hooked grabbing arms underneath.
    static let harvester: ShapeDescription = {
        let c = RGB(hex: 0x7CFF4F)
        return ShapeDescription(scale: 16, strokes: [
            ShapeStroke([v(-0.85, 0), v(-0.5, 0.55), v(0.5, 0.55), v(0.85, 0), v(0.4, -0.25), v(-0.4, -0.25)],
                        closed: true, color: c),
            ShapeStroke([v(-0.3, 0.2), v(0.3, 0.2)], color: RGB(hex: 0xE8FFB0)),
            ShapeStroke([v(-0.4, -0.25), v(-0.65, -0.72), v(-0.42, -0.95)], color: c),
            ShapeStroke([v(0, -0.25), v(0, -0.95)], color: c),
            ShapeStroke([v(0.4, -0.25), v(0.65, -0.72), v(0.42, -0.95)], color: c),
        ])
    }()

    /// A ragged seven-pointed star around a hollow core.
    static let husk: ShapeDescription = {
        let points = (0..<14).map { i -> Vec2 in
            let radius = i % 2 == 0 ? 1.0 : 0.42
            let angle = Double.pi / 2 + Double(i) * Double.pi / 7
            return Vec2(radius * cos(angle), radius * sin(angle))
        }
        let c = RGB(hex: 0xFF3FD2)
        return ShapeDescription(scale: 15, strokes: [
            ShapeStroke(points, closed: true, color: c),
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 0.25, rotation: -Double.pi / 2), closed: true,
                        color: RGB(hex: 0xFFC0F0)),
        ])
    }()

    /// A flat lens with a seed pod slung underneath.
    static let sower: ShapeDescription = {
        let c = RGB(hex: 0xFFA030)
        return ShapeDescription(scale: 17, strokes: [
            ShapeStroke([v(-1, 0), v(-0.5, 0.35), v(0.5, 0.35), v(1, 0), v(0.5, -0.35), v(-0.5, -0.35)],
                        closed: true, color: c),
            ShapeStroke([v(-0.3, 0.3), v(-0.3, -0.3)], color: c),
            ShapeStroke([v(0.3, 0.3), v(0.3, -0.3)], color: c),
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.18, center: v(0, -0.6)), closed: true,
                        color: RGB(hex: 0xFFE0A0)),
        ])
    }()

    /// A four-pointed caltrop with a ring at its heart.
    static let mine: ShapeDescription = {
        let c = RGB(hex: 0xFF4A3A)
        return ShapeDescription(scale: 8, strokes: [
            ShapeStroke([v(1, 0), v(0.22, 0.22), v(0, 1), v(-0.22, 0.22), v(-1, 0), v(-0.22, -0.22),
                         v(0, -1), v(0.22, -0.22)], closed: true, color: c),
            ShapeStroke(ShapeKit.polygon(sides: 10, radius: 0.32), closed: true, color: RGB(hex: 0xFFB0A0)),
        ])
    }()

    /// A lumpy sac with three Motes curled up inside.
    static let brood: ShapeDescription = {
        let radii = [1.0, 0.86, 0.97, 0.82, 1.0, 0.9, 0.84, 0.98, 0.88]
        let outline = radii.enumerated().map { i, r -> Vec2 in
            let a = 2 * Double.pi * Double(i) / Double(radii.count)
            return Vec2(r * cos(a), r * sin(a))
        }
        let c = RGB(hex: 0xB060FF)
        let inner = RGB(hex: 0xFF7AC8)
        return ShapeDescription(scale: 22, strokes: [
            ShapeStroke(outline, closed: true, color: c),
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 0.22, center: v(-0.35, 0.2)), closed: true, color: inner),
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 0.22, rotation: 1, center: v(0.35, 0.25)), closed: true,
                        color: inner),
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 0.22, rotation: 2, center: v(0, -0.35)), closed: true,
                        color: inner),
        ])
    }()

    /// A small arrowhead with a bright eye.
    static let mote: ShapeDescription = {
        let c = RGB(hex: 0xFF7AC8)
        return ShapeDescription(scale: 8, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 1), closed: true, color: c),
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.2), closed: true, color: RGB(hex: 0xFFE0F0)),
        ])
    }()

    /// A long needle with swept tail barbs. Points the way it is travelling.
    static let lancer: ShapeDescription = {
        let c = RGB(hex: 0xFFE84A)
        return ShapeDescription(scale: 18, strokes: [
            ShapeStroke([v(1, 0), v(0.2, 0.18), v(-0.7, 0.12), v(-1, 0.38), v(-0.84, 0), v(-1, -0.38),
                         v(-0.7, -0.12), v(0.2, -0.18)], closed: true, color: c),
            ShapeStroke([v(0.75, 0), v(-0.6, 0)], color: RGB(hex: 0xFFFFC0)),
        ])
    }()

    /// A squat hull with a threaded drill bit underneath.
    static let anchor: ShapeDescription = {
        let c = RGB(hex: 0xFFC23A)
        return ShapeDescription(scale: 20, strokes: [
            ShapeStroke([v(-0.9, 0.6), v(0.9, 0.6), v(0.6, -0.1), v(-0.6, -0.1)], closed: true, color: c),
            ShapeStroke([v(-0.35, -0.1), v(0, -1), v(0.35, -0.1)], color: c),
            ShapeStroke([v(-0.22, -0.35), v(0.22, -0.45)], color: c),
            ShapeStroke([v(-0.12, -0.6), v(0.12, -0.68)], color: c),
            ShapeStroke([v(0, 0.6), v(0, 0.9)], color: RGB(hex: 0xFFF0C0)),
            ShapeStroke([v(-0.5, 0.25), v(0.5, 0.25)], color: RGB(hex: 0xFFF0C0)),
        ])
    }()

    /// A small figure standing with its feet on the origin, arms raised to wave. A soft mint, not
    /// white: at this size a near-white glow over the outpost pad blows out to a blob.
    static let colonist: ShapeDescription = {
        let c = RGB(hex: 0x7DF0B4)
        return ShapeDescription(scale: 8, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 8, radius: 0.3, center: v(0, 1.65)), closed: true, color: c),
            ShapeStroke([v(0, 1.35), v(0, 0.7)], color: c),
            ShapeStroke([v(-0.35, 0), v(0, 0.7), v(0.35, 0)], color: c),
            ShapeStroke([v(-0.45, 1.5), v(0, 1.15), v(0.45, 1.5)], color: c),
        ])
    }()

    /// A compact ribbed dome with a mast, on a wide landing pad. Colonists stand on the pad either
    /// side of the dome (16 units out and beyond), so the dome is kept narrower than that.
    static let outpost: ShapeDescription = {
        let c = RGB(hex: 0x4FC8FF)
        return ShapeDescription(scale: 10, strokes: [
            // The pad, with raised lips at each end.
            ShapeStroke([v(-4.6, 0.3), v(-4.4, 0), v(4.4, 0), v(4.6, 0.3)], color: c.scaled(0.8)),
            ShapeStroke(ShapeKit.arc(radius: 0.78, from: 0, to: Double.pi, segments: 18), color: c),
            ShapeStroke(ShapeKit.arc(radius: 0.5, from: 0.35, to: Double.pi - 0.35, segments: 10),
                        color: c.scaled(0.7)),
            ShapeStroke([v(-0.16, 0), v(-0.16, 0.3), v(0.16, 0.3), v(0.16, 0)], color: RGB(hex: 0xC0F0FF)),
            ShapeStroke([v(0.42, 0.66), v(0.66, 1.25)], color: c),
            ShapeStroke(ShapeKit.polygon(sides: 6, radius: 0.09, center: v(0.68, 1.31)), closed: true,
                        color: RGB(hex: 0xC0F0FF)),
        ])
    }()

    /// Broken stubs of a dome on a cracked pad.
    static let ruin: ShapeDescription = {
        let c = RGB(hex: 0x3E6A80)
        return ShapeDescription(scale: 10, strokes: [
            ShapeStroke([v(-4.6, 0.3), v(-4.4, 0), v(-0.9, 0)], color: c),
            ShapeStroke([v(0.4, 0), v(4.4, 0), v(4.6, 0.3)], color: c),
            ShapeStroke(ShapeKit.arc(radius: 0.85, from: 0, to: 0.8, segments: 6), color: c),
            ShapeStroke(ShapeKit.arc(radius: 0.85, from: 2.3, to: Double.pi, segments: 6), color: c),
            ShapeStroke([v(-0.3, 0.05), v(0, 0.35), v(0.25, 0.08)], color: c),
        ])
    }()

    /// A short bright streak.
    static let pulse = ShapeDescription(scale: 12, strokes: [
        ShapeStroke([v(-1, 0), v(1, 0)], color: RGB(hex: 0xC8FFFF)),
    ])

    /// A spinning diamond with a hot centre.
    static let spore: ShapeDescription = {
        ShapeDescription(scale: 5, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 1), closed: true, color: RGB(hex: 0xFF5FA0)),
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.35, rotation: Double.pi / 4), closed: true,
                        color: RGB(hex: 0xFFD0E0)),
        ])
    }()
}
