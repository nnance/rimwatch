import Foundation

/// How the game looks and sounds, kept apart from how it plays. The simulation knows entity roles;
/// a `Theme` says what each role looks like. Everything here is device-neutral data: colours are
/// plain RGB numbers and shapes are polylines, so the app decides how to draw them.

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

/// Everything the renderer draws that has a shape of its own.
public enum EntityRole: Sendable, Hashable {
    case player
    case enemy(EnemyKind)
    case colonist
    /// A standing outpost. Its origin is the ground under its centre.
    case outpost
    /// What is left of a destroyed outpost.
    case ruin
    case projectile(Projectile.Owner)

    public static var allCases: [EntityRole] {
        [.player, .colonist, .outpost, .ruin, .projectile(.player), .projectile(.enemy)]
            + EnemyKind.allCases.map { .enemy($0) }
    }
}

/// Colours that are not part of a single shape.
public struct Palette: Sendable, Equatable {
    public var background: RGB
    public var stars: RGB
    /// Lancer wind-up, a colonist in a Harvester's grip, outpost damage.
    public var warning: RGB
    /// A colonist falling free.
    public var falling: RGB
    /// The ship's shield and invulnerability.
    public var shield: RGB
    /// Explosion sparks for enemies; the player's own burst uses the player shape's colour.
    public var spark: RGB
    /// On-screen touch controls.
    public var controls: RGB
    public var hud: RGB

    public init(background: RGB, stars: RGB, warning: RGB, falling: RGB, shield: RGB, spark: RGB,
                controls: RGB, hud: RGB) {
        self.background = background
        self.stars = stars
        self.warning = warning
        self.falling = falling
        self.shield = shield
        self.spark = spark
        self.controls = controls
        self.hud = hud
    }
}

public struct TerrainStyle: Sendable, Equatable {
    /// The bright ridge line along the ground.
    public var ridge: RGB
    /// Fainter lines drawn below the ridge, each this many world units lower.
    public var strata: RGB
    public var strataOffsets: [Double]
    /// Ridge colour during a Blackout.
    public var blackoutRidge: RGB

    public init(ridge: RGB, strata: RGB, strataOffsets: [Double], blackoutRidge: RGB) {
        self.ridge = ridge
        self.strata = strata
        self.strataOffsets = strataOffsets
        self.blackoutRidge = blackoutRidge
    }
}

public protocol Theme: Sendable {
    var name: String { get }
    var palette: Palette { get }
    var terrain: TerrainStyle { get }
    func shape(for role: EntityRole) -> ShapeDescription
    /// A simpler version of a role's shape for drawing very small, such as the lives in the
    /// HUD, where fine details would blur together. Defaults to the full shape.
    func icon(for role: EntityRole) -> ShapeDescription
    func displayName(for role: EntityRole) -> String
    /// The sound to play for an event, if any. See `SoundPatch` (in `Audio/`).
    func sound(for event: GameEvent) -> SoundPatch?
    /// The sound for a menu action, if any.
    func menuSound(_ sound: MenuSound) -> SoundPatch?
    /// Every patch the theme can play, so an app can prepare them all up front.
    var allSounds: [SoundPatch] { get }
    /// The ambient music, or nil for none.
    var music: MusicStyle? { get }
}

extension Theme {
    public func icon(for role: EntityRole) -> ShapeDescription { shape(for: role) }
    public func sound(for event: GameEvent) -> SoundPatch? { nil }
    public func menuSound(_ sound: MenuSound) -> SoundPatch? { nil }
    public var allSounds: [SoundPatch] { [] }
    public var music: MusicStyle? { nil }
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
