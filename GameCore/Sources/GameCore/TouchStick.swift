import Foundation

/// A floating touch stick as numbers: a thumb landing in its zone puts the stick's centre there,
/// dragging gives an analogue vector, and dragging past the rim pulls the centre along behind
/// the thumb so the stick never runs out of travel. Letting go puts it back at rest. The app
/// draws it and feeds it touch positions (screen points, y up); a mode can have one or two, each
/// with its own zone.
///
/// No dead zone: the vector is the thumb's offset over the radius, capped at length 1.
public struct TouchStick: Sendable, Equatable {
    /// Where a touch may start the stick: x in `minX..<maxX`, y in `minY..<maxY`.
    public struct Zone: Sendable, Equatable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public static let none = Zone(minX: 0, minY: 0, maxX: 0, maxY: 0)

        /// Half-open, as a CoreGraphics rectangle's `contains`.
        public func contains(_ p: Vec2) -> Bool {
            p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
        }
    }

    public private(set) var zone = Zone.none
    public private(set) var radius = 50.0
    /// Where the stick sits while no thumb is on it.
    public private(set) var rest = Vec2.zero
    /// Where the stick's centre is now: `rest`, or under the thumb that started it.
    public private(set) var center = Vec2.zero
    /// The thumb's offset from the centre over the radius, length at most 1. Zero while idle.
    public private(set) var vector = Vec2.zero
    /// A thumb is on the stick.
    public private(set) var isActive = false

    public init() {}

    /// New geometry. An idle stick moves to its new rest position; one in use keeps its centre.
    public mutating func layout(zone: Zone, radius: Double, rest: Vec2) {
        self.zone = zone
        self.radius = radius
        self.rest = rest
        if !isActive { center = rest }
    }

    /// A thumb landed at `p`. The stick takes it (returns true) when it is free and `p` is in its
    /// zone; its centre jumps to `p`.
    public mutating func begin(at p: Vec2) -> Bool {
        guard !isActive, zone.contains(p) else { return false }
        isActive = true
        center = p
        vector = .zero
        return true
    }

    /// The thumb moved to `p`.
    public mutating func move(to p: Vec2) {
        guard isActive else { return }
        var dx = p.x - center.x
        var dy = p.y - center.y
        let distance = hypot(dx, dy)
        // Past the rim, the centre trails the thumb.
        if distance > radius {
            let excess = distance - radius
            center.x += dx / distance * excess
            center.y += dy / distance * excess
            dx = p.x - center.x
            dy = p.y - center.y
        }
        vector = Vec2(dx / radius, dy / radius).clampedToUnit
    }

    /// The thumb lifted (or the touch was lost): back to rest.
    public mutating func end() {
        isActive = false
        vector = .zero
        center = rest
    }

    /// Picks the stick a thumb landing at `p` starts: the first free one whose zone holds it.
    /// Returns its index, or nil. With two sticks in separate zones each thumb gets its own.
    public static func begin(_ sticks: inout [TouchStick], at p: Vec2) -> Int? {
        for index in sticks.indices where sticks[index].begin(at: p) { return index }
        return nil
    }
}
