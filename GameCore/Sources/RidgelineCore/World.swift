import Foundation
import GameCore

public struct Outpost: Sendable, Equatable, Identifiable {
    public let id: Int
    public let x: Double
    /// Height of the levelled ground the outpost stands on.
    public let groundY: Double
}

/// The planet strip. It wraps horizontally: x runs from 0 up to (not including) `width`, and
/// leaving one edge re-enters at the other. y is 0 at the bottom and increases upward.
public struct World: Sendable {
    public let width: Double
    public let height: Double
    /// Highest y an entity can reach.
    public let ceiling: Double
    public let outposts: [Outpost]

    private struct Harmonic: Sendable {
        let amplitude: Double
        let cycles: Double
        let phase: Double
    }

    private let harmonics: [Harmonic]
    private static let baseGround = 90.0
    private static let minGround = 20.0
    /// Ground is level within `flatInner` of an outpost and blends back to terrain by `flatOuter`.
    private static let flatInner = 50.0
    private static let flatOuter = 120.0

    public init(tuning: Tuning, seed: UInt64) {
        width = tuning.worldWidth
        height = tuning.worldHeight
        ceiling = tuning.worldHeight - tuning.ceilingMargin

        var rng = SeededRNG(seed: seed)
        // Whole numbers of cycles across the world, so the terrain meets itself at the seam.
        let shape: [(amplitude: Double, cycles: Double)] = [(34, 3), (22, 7), (12, 13), (6, 29)]
        let harmonics = shape.map {
            Harmonic(amplitude: $0.amplitude, cycles: $0.cycles, phase: rng.range(0...(2 * .pi)))
        }
        self.harmonics = harmonics

        let spacing = tuning.worldWidth / Double(max(tuning.outpostCount, 1))
        let worldWidth = tuning.worldWidth
        outposts = (0..<tuning.outpostCount).map { index in
            let x = (Double(index) + 0.5) * spacing + rng.range(-spacing * 0.15...spacing * 0.15)
            return Outpost(id: index, x: x, groundY: World.rawHeight(at: x, width: worldWidth, harmonics: harmonics))
        }
    }

    /// Brings any x back into `0..<width`.
    public func wrap(_ x: Double) -> Double {
        let remainder = x.truncatingRemainder(dividingBy: width)
        let wrapped = remainder < 0 ? remainder + width : remainder
        return wrapped >= width ? 0 : wrapped
    }

    /// Shortest signed horizontal distance from `a` to `b`, going round the seam if that is nearer.
    public func delta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: width)
        if d > width / 2 {
            d -= width
        } else if d <= -width / 2 {
            d += width
        }
        return d
    }

    public func distance(_ a: Vec2, _ b: Vec2) -> Double {
        hypot(delta(from: a.x, to: b.x), b.y - a.y)
    }

    public func groundHeight(at x: Double) -> Double {
        let raw = World.rawHeight(at: x, width: width, harmonics: harmonics)
        for outpost in outposts {
            let d = abs(delta(from: x, to: outpost.x))
            guard d < World.flatOuter else { continue }
            if d <= World.flatInner { return outpost.groundY }
            let t = (d - World.flatInner) / (World.flatOuter - World.flatInner)
            let blend = t * t * (3 - 2 * t)
            return outpost.groundY + (raw - outpost.groundY) * blend
        }
        return raw
    }

    private static func rawHeight(at x: Double, width: Double, harmonics: [Harmonic]) -> Double {
        var h = baseGround
        for harmonic in harmonics {
            h += harmonic.amplitude * sin(2 * .pi * harmonic.cycles * x / width + harmonic.phase)
        }
        return max(h, minGround)
    }
}
