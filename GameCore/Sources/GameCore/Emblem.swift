import Foundation

/// The game's emblem, "The Rim": the crater's rim seen from above as a rough orange ring, a
/// thinner inner ring, and the patrol ship's arrowhead crossing the centre, with four faint stars
/// near the corners, as neon lines on black. The app icon (`Tools/Icon`) and the title screen both
/// draw it from here.
///
/// Coordinates are in a 100 x 100 square with y down and the origin at the top left, as the
/// design was given. Line widths are in the same units.
public enum Emblem {
    /// One line of the emblem.
    public struct Line: Sendable, Equatable {
        public var points: [Vec2]
        public var closed: Bool
        public var color: RGB
        /// In emblem units (the square is 100 across).
        public var width: Double
    }

    /// A small soft dot.
    public struct Star: Sendable, Equatable {
        public var center: Vec2
        public var radius: Double
        /// 0...1: how bright it is.
        public var alpha: Double
    }

    /// The side of the square the emblem is drawn in.
    public static let side = 100.0
    public static let background = RGB(0, 0, 0)

    /// The patrol ship's hull outline: an arrowhead with a split tail, in a mode's unit shape
    /// coordinates (x forward, y up, the ship's position at the origin). A closed polygon, without
    /// the first point repeated. Ridgeline's ship is drawn from this.
    public static let shipHull: [Vec2] = {
        let top = [Vec2(1, 0), Vec2(0.25, 0.2), Vec2(-0.5, 0.45), Vec2(-0.9, 0.45), Vec2(-0.62, 0.12),
                   Vec2(-0.78, 0)]
        let hull = top + ShapeKit.mirroredY(top.dropLast().reversed())
        return Array(hull.dropLast())
    }()

    /// The roughness of the rings: radius offsets, repeated every 16 points.
    public static let jitter: [Double] = [0, 2.2, -1.2, 1.6, -2.0, 0.8, 2.6, -1.6, 0.4, 1.8, -2.4, 1.0, -0.6, 2.0,
                                          -1.8, 0.6]

    public static let centre = Vec2(50, 50)

    /// The rim: a closed 20-point polygon of radius 36, roughened by `jitter`.
    public static let outerRing = Line(
        points: (0..<20).map { i in
            ring(angle: 2 * Double.pi * Double(i) / 20, radius: 36 + jitter[i % 16])
        },
        closed: true, color: RGB(hex: 0xFF7A3D), width: 2.8)

    /// A thinner, darker ring inside the rim: 18 points of radius 27, half as rough, turned a little.
    public static let innerRing = Line(
        points: (0..<18).map { i in
            ring(angle: 2 * Double.pi * Double(i) / 18 + 0.3, radius: 27 + 0.5 * jitter[i % 16])
        },
        closed: true, color: RGB(hex: 0xC2552B), width: 1.5)

    /// How far the ship's nose is turned up from pointing right, in degrees.
    public static let shipAngle = 28.0
    /// Emblem units per unit of the hull's shape coordinates.
    public static let shipScale = 19.0

    /// The ship: the hull outline at `shipScale`, its origin on the centre, nose turned up by
    /// `shipAngle`.
    public static let ship: Line = {
        let angle = shipAngle * Double.pi / 180
        let (c, s) = (cos(angle), sin(angle))
        let points = shipHull.map { p in
            // Turned counter-clockwise in the hull's y-up space, then flipped into y down.
            Vec2(centre.x + shipScale * (p.x * c - p.y * s), centre.y - shipScale * (p.x * s + p.y * c))
        }
        return Line(points: points, closed: true, color: RGB(hex: 0x3FF6FF), width: 2.4)
    }()

    /// The lines in drawing order, back to front.
    public static let lines: [Line] = [outerRing, innerRing, ship]

    public static let starColor = RGB(hex: 0x8090B0)

    /// Four faint stars near the corners.
    public static let stars: [Star] = [
        Star(center: Vec2(13, 15), radius: 1.1, alpha: 0.55),
        Star(center: Vec2(87, 11), radius: 0.8, alpha: 0.4),
        Star(center: Vec2(9, 86), radius: 0.8, alpha: 0.4),
        Star(center: Vec2(89, 88), radius: 1.0, alpha: 0.5),
    ]

    private static func ring(angle: Double, radius: Double) -> Vec2 {
        Vec2(centre.x + radius * cos(angle), centre.y + radius * sin(angle))
    }
}
