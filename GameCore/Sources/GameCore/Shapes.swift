import Foundation

/// Colours and shapes as device-neutral data: colours are plain RGB numbers and shapes are
/// polylines, so the app decides how to draw them. A mode's theme builds its look from these.

/// A colour as red, green and blue in 0...1.
public struct RGB: Sendable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From a 0xRRGGBB literal.
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// Moves the colour toward white by `amount` (0...1).
    public func lightened(_ amount: Double) -> RGB {
        RGB(r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount)
    }

    public func scaled(_ factor: Double) -> RGB {
        RGB(r * factor, g * factor, b * factor)
    }
}

/// One line of a shape. Points are in unit coordinates: x points the way the entity faces (+1 is
/// forward), y is up, and the entity's position is the origin.
public struct ShapeStroke: Sendable, Equatable {
    public var points: [Vec2]
    /// Joins the last point back to the first.
    public var closed: Bool
    public var color: RGB

    public init(_ points: [Vec2], closed: Bool = false, color: RGB) {
        self.points = points
        self.closed = closed
        self.color = color
    }
}

/// The look of one entity role: some strokes and the size they are drawn at.
public struct ShapeDescription: Sendable, Equatable {
    public var strokes: [ShapeStroke]
    /// World units per unit coordinate. A stroke point at (1, 0) is drawn `scale` units ahead of
    /// the entity's position.
    public var scale: Double

    public init(scale: Double, strokes: [ShapeStroke]) {
        self.scale = scale
        self.strokes = strokes
    }

    /// The smallest rectangle in unit coordinates that holds every point, as (min, max).
    public var bounds: (min: Vec2, max: Vec2) {
        var low = Vec2(Double.infinity, Double.infinity)
        var high = Vec2(-Double.infinity, -Double.infinity)
        for stroke in strokes {
            for p in stroke.points {
                low = Vec2(Swift.min(low.x, p.x), Swift.min(low.y, p.y))
                high = Vec2(Swift.max(high.x, p.x), Swift.max(high.y, p.y))
            }
        }
        if strokes.allSatisfy({ $0.points.isEmpty }) { return (.zero, .zero) }
        return (low, high)
    }

    /// The same shape with every stroke in one colour.
    public func recoloured(_ color: RGB) -> ShapeDescription {
        ShapeDescription(scale: scale, strokes: strokes.map { ShapeStroke($0.points, closed: $0.closed, color: color) })
    }
}

/// Helpers for building shapes.
public enum ShapeKit {
    /// Points around a circle or arc, counter-clockwise from `start` radians.
    public static func arc(center: Vec2 = .zero, radius: Double, from start: Double = 0,
                           to end: Double = 2 * Double.pi, segments: Int = 24) -> [Vec2] {
        (0...segments).map { i in
            let a = start + (end - start) * Double(i) / Double(segments)
            return Vec2(center.x + radius * cos(a), center.y + radius * sin(a))
        }
    }

    /// A closed regular polygon.
    public static func polygon(sides: Int, radius: Double, rotation: Double = 0, center: Vec2 = .zero) -> [Vec2] {
        (0..<sides).map { i in
            let a = rotation + 2 * Double.pi * Double(i) / Double(sides)
            return Vec2(center.x + radius * cos(a), center.y + radius * sin(a))
        }
    }

    /// Mirrors points top to bottom, for symmetrical hulls.
    public static func mirroredY(_ points: [Vec2]) -> [Vec2] {
        points.map { Vec2($0.x, -$0.y) }
    }
}
