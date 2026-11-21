import Foundation

public struct Vec2: Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    @inlinable
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    @inlinable
    public var length: Double { hypot(x, y) }

    /// The same direction, with length capped at 1. Used for analogue stick input.
    @inlinable
    public var clampedToUnit: Vec2 {
        let len = length
        return len > 1 ? Vec2(x / len, y / len) : self
    }

    @inlinable
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    @inlinable
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    @inlinable
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
}

/// SplitMix64. Deterministic for a given seed, so a simulation can be replayed exactly.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    @usableFromInline
    var state: UInt64

    @inlinable
    public init(seed: UInt64) {
        state = seed
    }

    @inlinable
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    @inlinable
    public mutating func range(_ bounds: ClosedRange<Double>) -> Double {
        Double.random(in: bounds, using: &self)
    }

    @inlinable
    public mutating func chance(_ probability: Double) -> Bool {
        range(0...1) < probability
    }
}

@inlinable
package func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(max(value, low), high)
}
