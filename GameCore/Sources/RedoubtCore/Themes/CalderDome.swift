import Foundation
import GameCore

/// Redoubt's first theme: the floor of a breached outpost dome on Calder, seen from above, in the
/// same neon world as Ridgeline. The orb wears the Watch's cyan, colonists the same mint as
/// Ridgeline's, and the Husk is Ridgeline's Husk; the walls and floor markings are a restrained
/// steel blue so the crowd stands out.
///
/// Each enemy has its own colour and silhouette, so a role reads in a crowd of 90 at a few points
/// across: the Skitter a small orange bug, the Gleaner a yellow open claw, the Spitter a violet
/// turret with a barrel, the Burrow a dark ring in the floor, the Thresher a big crimson hull with
/// a toothed blade, the Husk a magenta star. Silent for now: sounds and music come in step 13c.
public struct CalderDome: RedoubtTheme {
    public init() {}

    public let name = "Calder Dome"

    public let palette = RedoubtPalette(
        background: RGB(0, 0, 0),
        wall: RGB(hex: 0x3E6E9A),
        floor: RGB(hex: 0x1C3550),
        warning: RGB(hex: 0xFF3030),
        reward: RGB(hex: 0xFFFF80),
        shockwave: RGB(hex: 0x60B0FF),
        shield: RGB(hex: 0x60B0FF),
        controls: RGB(hex: 0x60E0FF),
        hud: RGB(hex: 0x60E0FF),
        heading: RGB(hex: 0xFF7A3D)
    )

    public func shape(for thing: RedoubtShape) -> ShapeDescription {
        switch thing {
        case .orb, .life: Self.orb
        case .colonist: Self.colonist
        case .enemy(let role):
            switch role {
            case .skitter: Self.skitter
            case .gleaner: Self.gleaner
            case .spitter: Self.spitter
            case .burrow: Self.burrow
            case .thresher: Self.thresher
            case .husk: Self.husk
            }
        case .orbShot: Self.orbShot
        case .enemyShot: Self.enemyShot
        case .airlockOpen: Self.airlockOpen
        case .airlockShut: Self.airlockShut
        case .arrival: Self.arrival
        case .charge: Self.charge
        }
    }

    public func displayName(for role: RedoubtRole) -> String {
        switch role {
        case .skitter: "Skitter"
        case .gleaner: "Gleaner"
        case .spitter: "Spitter"
        case .burrow: "Burrow"
        case .thresher: "Thresher"
        case .husk: "Husk"
        }
    }

    // MARK: Shapes

    private static func v(_ x: Double, _ y: Double) -> Vec2 { Vec2(x, y) }
    private static func mirrored(_ points: [Vec2]) -> [Vec2] { ShapeKit.mirroredY(points) }

    /// The Watch's cyan, as on Ridgeline's ship.
    static let cyan = RGB(hex: 0x3FF6FF)
    /// Ridgeline's colonist mint.
    static let mint = RGB(hex: 0x7DF0B4)

    /// A ring hull round a pale seat, with a pointed emitter at the front (the aim) and two hover
    /// struts behind. Radius 10, as the orb.
    static let orb: ShapeDescription = {
        let strut = cyan.scaled(0.75)
        return ShapeDescription(scale: 10, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 32), color: cyan),
            ShapeStroke(ShapeKit.polygon(sides: 10, radius: 0.42), closed: true, color: RGB(hex: 0xD8FFFF)),
            ShapeStroke([v(0.9, 0.42), v(1.6, 0), v(0.9, -0.42)], color: cyan),
            ShapeStroke([v(0.42 * cos(2.3), 0.42 * sin(2.3)), v(cos(2.3), sin(2.3))], color: strut),
            ShapeStroke([v(0.42 * cos(2.3), -0.42 * sin(2.3)), v(cos(2.3), -sin(2.3))], color: strut),
        ])
    }()

    /// Ridgeline's waving figure seen from above: a head, the line of the shoulders, both arms up.
    static let colonist: ShapeDescription = {
        ShapeDescription(scale: 6.5, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 8, radius: 0.36, center: v(0, 0.1)), closed: true, color: mint),
            ShapeStroke(ShapeKit.arc(center: v(0, 0.1), radius: 0.78, from: 3.6, to: 5.82, segments: 8), color: mint),
            ShapeStroke([v(-0.7, -0.24), v(-1.0, 0.72)], color: mint),
            ShapeStroke([v(0.7, -0.24), v(1.0, 0.72)], color: mint),
        ])
    }()

    /// The flood: a small diamond body with four short legs. Few strokes, so sixty of them
    /// overlapping stay a field of bugs and not a blob.
    static let skitter: ShapeDescription = {
        let c = RGB(hex: 0xFF8A2A)
        return ShapeDescription(scale: 8, strokes: [
            ShapeStroke([v(1, 0), v(0.1, 0.42), v(-0.75, 0), v(0.1, -0.42)], closed: true, color: c),
            ShapeStroke([v(0.3, 0.32), v(0.72, 0.85)], color: c),
            ShapeStroke([v(0.3, -0.32), v(0.72, -0.85)], color: c),
            ShapeStroke([v(-0.28, 0.25), v(-0.72, 0.8)], color: c),
            ShapeStroke([v(-0.28, -0.25), v(-0.72, -0.8)], color: c),
        ])
    }()

    /// The grabber: an open claw reaching forward, two hooked pincers and a pale eye.
    static let gleaner: ShapeDescription = {
        let c = RGB(hex: 0xF5E83A)
        let tip = [v(0.2475, 0.4635), v(0.8, 0.66), v(1.15, 0.32), v(0.88, 0.12)]
        return ShapeDescription(scale: 10, strokes: [
            ShapeStroke(ShapeKit.arc(center: v(-0.25, 0), radius: 0.68, from: 0.75, to: 2 * Double.pi - 0.75,
                                     segments: 16), color: c),
            ShapeStroke(tip, color: c),
            ShapeStroke(mirrored(tip), color: c),
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.2, center: v(-0.3, 0)), closed: true,
                        color: RGB(hex: 0xFFF8B0)),
        ])
    }()

    /// The shooter: a squat hexagonal turret with a long barrel and muzzle, and a pale core.
    static let spitter: ShapeDescription = {
        let c = RGB(hex: 0xB070FF)
        return ShapeDescription(scale: 11, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 6, radius: 0.75, rotation: Double.pi / 6), closed: true, color: c),
            ShapeStroke([v(0.64, 0.17), v(1.42, 0.17)], color: c),
            ShapeStroke([v(0.64, -0.17), v(1.42, -0.17)], color: c),
            ShapeStroke([v(1.42, 0.32), v(1.42, -0.32)], color: c),
            ShapeStroke(ShapeKit.polygon(sides: 8, radius: 0.28), closed: true, color: RGB(hex: 0xE6CCFF)),
        ])
    }()

    /// A hole torn in the floor: a ragged rim, two darker rings stepping down into it (offset, so
    /// the far wall of the pit shows) and cracks running out. The Skitters' dark orange: it is
    /// where they come from. Drawn unrotated.
    static let burrow: ShapeDescription = {
        let c = RGB(hex: 0xC8642E)
        let jitter = [0.0, 0.1, -0.08, 0.12, -0.05, 0.08, -0.12, 0.04, 0.11, -0.07, 0.06, -0.1, 0.09, -0.03]
        let rim = jitter.enumerated().map { i, j -> Vec2 in
            let a = 2 * Double.pi * Double(i) / Double(jitter.count)
            return v((1 + j) * cos(a), (1 + j) * sin(a))
        }
        let cracks = [0.4, 1.7, 2.9, 4.1, 5.3].map { a in
            ShapeStroke([v(1.02 * cos(a), 1.02 * sin(a)), v(1.3 * cos(a + 0.08), 1.3 * sin(a + 0.08))],
                        color: c.scaled(0.8))
        }
        return ShapeDescription(scale: 18, strokes: [
            ShapeStroke(rim, closed: true, color: c),
            ShapeStroke(ShapeKit.polygon(sides: 12, radius: 0.58, center: v(0, 0.1)), closed: true,
                        color: RGB(hex: 0x9A4420)),
            ShapeStroke(ShapeKit.polygon(sides: 10, radius: 0.26, center: v(0, 0.2)), closed: true,
                        color: RGB(hex: 0x6A2A14)),
        ] + cracks)
    }()

    /// The heavy: a big crimson hull with a double plate and a toothed crushing blade across the
    /// front.
    static let thresher: ShapeDescription = {
        let c = RGB(hex: 0xFF3355)
        let hull = [v(0.85, 0.55), v(0.45, 0.95), v(-0.6, 0.95), v(-0.95, 0.6),
                    v(-0.95, -0.6), v(-0.6, -0.95), v(0.45, -0.95), v(0.85, -0.55)]
        let plate = [v(0.48, 0.34), v(0.24, 0.58), v(-0.44, 0.58), v(-0.64, 0.34),
                     v(-0.64, -0.34), v(-0.44, -0.58), v(0.24, -0.58), v(0.48, -0.34)]
        let blade = (0...8).map { i in v(i % 2 == 0 ? 1.02 : 1.28, -1.0 + 0.25 * Double(i)) }
        return ShapeDescription(scale: 17, strokes: [
            ShapeStroke(hull, closed: true, color: c),
            ShapeStroke(plate, closed: true, color: RGB(hex: 0xFF9AAE)),
            ShapeStroke(blade, color: c),
            ShapeStroke([v(0.85, 0.3), v(1.02, 0.5)], color: c),
            ShapeStroke([v(0.85, -0.3), v(1.02, -0.5)], color: c),
        ])
    }()

    /// Ridgeline's Husk: a ragged seven-pointed magenta star round a hollow core, a little
    /// sharper.
    static let husk: ShapeDescription = {
        let points = (0..<14).map { i -> Vec2 in
            let radius = i % 2 == 0 ? 1.0 : 0.36
            let angle = Double(i) * Double.pi / 7
            return Vec2(radius * cos(angle), radius * sin(angle))
        }
        return ShapeDescription(scale: 11, strokes: [
            ShapeStroke(points, closed: true, color: RGB(hex: 0xFF3FD2)),
            ShapeStroke(ShapeKit.polygon(sides: 3, radius: 0.25), closed: true, color: RGB(hex: 0xFFC0F0)),
        ])
    }()

    /// A bright streak along the line of fire, long enough that ten a second read as a stream.
    static let orbShot = ShapeDescription(scale: 11, strokes: [
        ShapeStroke([v(-1, 0), v(1, 0)], color: RGB(hex: 0xC8FFFF)),
    ])

    /// The Spitter's slow shot: a hot pink diamond with a pale centre, like Ridgeline's spore.
    static let enemyShot = ShapeDescription(scale: 6, strokes: [
        ShapeStroke(ShapeKit.polygon(sides: 4, radius: 1), closed: true, color: RGB(hex: 0xFF5FA0)),
        ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.38, rotation: Double.pi / 4), closed: true,
                    color: RGB(hex: 0xFFD0E0)),
    ])

    /// The open airlock in colonist mint: door posts, two chevrons pointing out through the
    /// opening, and a faint arc at the reach that delivers a line (36 of its 56-unit width).
    static let airlockOpen: ShapeDescription = {
        let reach = 36.0 / 56.0
        return ShapeDescription(scale: 56, strokes: [
            ShapeStroke([v(-0.5, -0.12), v(-0.5, 0.3)], color: mint),
            ShapeStroke([v(0.5, -0.12), v(0.5, 0.3)], color: mint),
            ShapeStroke([v(-0.22, 0.62), v(0, 0.44), v(0.22, 0.62)], color: mint),
            ShapeStroke([v(-0.22, 0.38), v(0, 0.2), v(0.22, 0.38)], color: mint),
            ShapeStroke(ShapeKit.arc(radius: reach, from: 0.15, to: Double.pi - 0.15, segments: 20),
                        color: mint.scaled(0.45)),
        ])
    }()

    /// The shut airlock: a bar across the opening between its posts, in a lit wall colour.
    static let airlockShut: ShapeDescription = {
        let c = RGB(hex: 0x6E9CC8)
        return ShapeDescription(scale: 56, strokes: [
            ShapeStroke([v(-0.5, -0.12), v(-0.5, 0.22)], color: c),
            ShapeStroke([v(0.5, -0.12), v(0.5, 0.22)], color: c),
            ShapeStroke([v(-0.5, 0.05), v(0.5, 0.05)], color: c),
            ShapeStroke([v(-0.12, 0.05), v(0, 0.16), v(0.12, 0.05)], color: c.scaled(0.7)),
        ])
    }()

    /// Four corner brackets closing on a centre cross: a target lock. White, tinted by role.
    static let arrival: ShapeDescription = {
        let white = RGB(1, 1, 1)
        let corner = [v(-1, 0.45), v(-1, 1), v(-0.45, 1)]
        let corners = [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)].map { sx, sy in
            ShapeStroke(corner.map { v(-$0.x * sx, $0.y * sy) }, color: white)
        }
        return ShapeDescription(scale: 1, strokes: corners + [
            ShapeStroke([v(-0.2, 0), v(0.2, 0)], color: white),
            ShapeStroke([v(0, -0.2), v(0, 0.2)], color: white),
        ])
    }()

    /// A Shockwave charge: a dot of energy in a ring.
    static let charge = ShapeDescription(scale: 1, strokes: [
        ShapeStroke(ShapeKit.arc(radius: 1, segments: 20), color: RGB(hex: 0x60B0FF)),
        ShapeStroke(ShapeKit.arc(radius: 0.4, segments: 12), color: RGB(hex: 0x60B0FF)),
    ])
}
