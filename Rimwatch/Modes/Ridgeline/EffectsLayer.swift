import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// Short-lived event feedback in the world: particles, expanding rings, Blink trails and
/// afterimages. Everything is anchored at world positions and re-placed relative to the camera
/// every frame, so it stays correct across the world seam.
///
/// Particles come from one fixed pool of sprites made up front and moved by hand each frame
/// (no per-particle actions), so heavy action never grows the node count: when the pool is full
/// the oldest particle is reused. Rings and afterimages are capped the same way.
@MainActor
final class EffectsLayer: SKNode {
    /// How a particle is drawn.
    enum Look {
        /// A short streak that points along its motion and shrinks as it dies.
        case spark
        /// A soft round dot.
        case dot
        /// A tumbling fragment of hull.
        case shard
    }

    /// A batch of particles from one point.
    struct Emission {
        var count: Int
        var color: RGB
        var look: Look = .spark
        var speed: ClosedRange<Double> = 80...200
        var life: ClosedRange<Double> = 0.3...0.6
        /// Direction in radians and the spread around it (2π for all round).
        var angle = 0.0
        var spread = 2 * Double.pi
        /// Per-second velocity decay.
        var drag = 2.0
        /// Downward acceleration in units per second squared.
        var gravity = 0.0
        /// Sprite scale at birth.
        var size: ClosedRange<Double> = 0.8...1.2
        /// Random offset from the origin.
        var jitter = 0.0
        /// Added to every particle's velocity (a moving source).
        var inherit = Vec2.zero
        /// Brightness at birth, 0...1.
        var alpha = 1.0
    }

    private struct Particle {
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var life = 0.0, maxLife = 1.0
        var drag = 0.0, gravity = 0.0, spin = 0.0, size = 1.0
        var look = Look.spark
        var alpha = 1.0
        var active = false
    }

    private struct Effect {
        let node: SKNode
        let worldX: Double
        let worldY: Double
    }

    static let poolSize = 480
    static let maxRings = 24
    static let maxGhosts = 10

    var world: World
    private let factory: GlowShapeFactory
    private var effects: [Effect] = []
    private var pointsPerUnit: CGFloat = 1
    private var particles = [Particle](repeating: Particle(), count: EffectsLayer.poolSize)
    private var sprites: [SKSpriteNode] = []
    private var cursor = 0
    private var rng = SeededRNG(seed: 0xEFFEC7)
    private var textures: [Look: GlowShapeFactory.Glyph] = [:]
    /// Exhaust carried over between frames, in particles.
    private var exhaustDebt = 0.0

    init(world: World, factory: GlowShapeFactory) {
        self.world = world
        self.factory = factory
        super.init()
        for _ in 0..<Self.poolSize {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            sprites.append(sprite)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func setPointsPerUnit(_ value: CGFloat) {
        pointsPerUnit = value
        // White glyphs, tinted per particle.
        let white = RGB(1, 1, 1)
        textures[.spark] = factory.glyph(key: "particle-spark", shape: ShapeDescription(scale: 3.5, strokes: [
            ShapeStroke([Vec2(-1, 0), Vec2(1, 0)], color: white),
        ]), pointsPerUnit: value)
        textures[.dot] = factory.glyph(key: "particle-dot", shape: ShapeDescription(scale: 1.6, strokes: [
            ShapeStroke(ShapeKit.polygon(sides: 6, radius: 1), closed: true, color: white),
        ]), pointsPerUnit: value)
        textures[.shard] = factory.glyph(key: "particle-shard", shape: ShapeDescription(scale: 6, strokes: [
            ShapeStroke([Vec2(-1, -0.2), Vec2(0.2, 0.25), Vec2(1, -0.1)], color: white),
        ]), pointsPerUnit: value)
        for index in particles.indices where particles[index].active {
            applyTexture(particles[index].look, to: sprites[index])
        }
    }

    private func applyTexture(_ look: Look, to sprite: SKSpriteNode) {
        guard let glyph = textures[look] else { return }
        sprite.texture = glyph.texture
        sprite.size = glyph.size
        sprite.anchorPoint = glyph.anchorPoint
    }

    func removeAll() {
        effects.forEach { $0.node.removeFromParent() }
        effects.removeAll()
        for index in particles.indices {
            particles[index].active = false
            sprites[index].isHidden = true
        }
    }

    /// Particles in use, for the debug stats.
    var activeParticles: Int { particles.count { $0.active } }

    // MARK: Particles

    func emit(at pos: Vec2, _ e: Emission) {
        for _ in 0..<e.count {
            let index = cursor
            cursor = (cursor + 1) % Self.poolSize
            let angle = e.angle + rng.range(-0.5...0.5) * e.spread
            let speed = rng.range(e.speed)
            var p = Particle()
            p.x = world.wrap(pos.x + rng.range(-1...1) * e.jitter)
            p.y = pos.y + rng.range(-1...1) * e.jitter
            p.vx = cos(angle) * speed + e.inherit.x
            p.vy = sin(angle) * speed + e.inherit.y
            p.maxLife = rng.range(e.life)
            p.life = p.maxLife
            p.drag = e.drag
            p.gravity = e.gravity
            p.spin = e.look == .shard ? rng.range(-14...14) : 0
            p.size = rng.range(e.size)
            p.look = e.look
            p.alpha = e.alpha
            p.active = true
            particles[index] = p
            let sprite = sprites[index]
            applyTexture(e.look, to: sprite)
            sprite.color = e.color.uiColor()
            sprite.zRotation = CGFloat(angle)
            sprite.isHidden = true
        }
    }

    /// Sparks flying out from a point.
    func burst(at pos: Vec2, color: RGB, count: Int, speed: Double = 160, life: TimeInterval = 0.55) {
        emit(at: pos, Emission(count: count, color: color, speed: speed * 0.5...speed * 1.2,
                               life: life * 0.6...life, drag: 2.5))
    }

    /// Engine exhaust behind the ship: `thrust` is the stick (each axis -1...1). The plume
    /// streams away from the direction of thrust and grows with it; idle, the engine flickers.
    func exhaust(at tail: Vec2, thrust: Vec2, shipVelocity: Vec2, facing: Double, color: RGB, elapsed: Double) {
        let strength = min(thrust.length, 1)
        let direction: Double
        if strength > 0.15 {
            direction = atan2(-thrust.y, -thrust.x)
        } else {
            direction = facing > 0 ? Double.pi : 0
        }
        exhaustDebt += elapsed * (14 + 110 * strength)
        let count = Int(exhaustDebt)
        guard count > 0 else { return }
        exhaustDebt -= Double(count)
        emit(at: tail, Emission(count: count, color: color, look: strength > 0.15 ? .spark : .dot,
                                speed: (40 + 160 * strength)...(70 + 240 * strength),
                                life: 0.1...(0.14 + 0.16 * strength), angle: direction, spread: 0.45,
                                drag: 4, size: (0.3 + 0.15 * strength)...(0.45 + 0.3 * strength), jitter: 1.5,
                                inherit: shipVelocity * 0.5, alpha: 0.35 + 0.35 * strength))
    }

    // MARK: Rings, trails, afterimages

    /// A ring that grows from a point to `radius` world units (or shrinks to it from far out with
    /// `inward`). The circle is re-stroked every frame at its current radius, so the line stays
    /// thin and crisp however large it gets.
    func ring(at pos: Vec2, color: RGB, radius: Double, duration: TimeInterval = 0.4, inward: Bool = false,
              width: CGFloat = 1) {
        let ppu = max(pointsPerUnit, 0.01)
        let passes: [(width: CGFloat, color: UIColor)] = [
            (6 * width / ppu, color.uiColor(alpha: 0.18)),
            (2.2 * width / ppu, color.uiColor(alpha: 0.85)),
            (1.0 * width / ppu, color.lightened(0.65).uiColor()),
        ]
        let container = SKNode()
        let strokes = passes.map { pass -> SKShapeNode in
            let shape = SKShapeNode()
            shape.lineWidth = pass.width
            shape.strokeColor = pass.color
            shape.fillColor = .clear
            shape.blendMode = .add
            shape.isAntialiased = true
            container.addChild(shape)
            return shape
        }
        let (from, to) = inward ? (radius * 6, radius) : (radius * 0.1, radius)
        let grow = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = min(Double(elapsed) / duration, 1)
            let eased = 1 - (1 - t) * (1 - t)
            let r = from + (to - from) * eased
            let path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            for shape in strokes { shape.path = path }
            node.alpha = CGFloat(inward ? min(1, 0.3 + t) * (t > 0.85 ? (1 - t) / 0.15 : 1) : 1 - t)
        }
        container.run(grow)
        add(container, at: pos, life: duration, kind: .ring)
    }

    /// A fading streak between two points, for Blink and charges.
    func trail(from: Vec2, to: Vec2, color: RGB, duration: TimeInterval = 0.35, width: CGFloat = 2.5) {
        let dx = world.delta(from: from.x, to: to.x)
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        let sprite = SKSpriteNode(color: color.uiColor(), size: CGSize(width: length, height: width / pointsPerUnit))
        sprite.blendMode = .add
        sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        sprite.zRotation = atan2(dy, dx)
        sprite.run(.group([.fadeOut(withDuration: duration), .scaleY(to: 0.2, duration: duration)]))
        let container = SKNode()
        container.addChild(sprite)
        add(container, at: from, life: duration, kind: .ring)
    }

    /// Fading copies of a shape along a path: the ship's afterimages after a Blink.
    func afterimages(of glyph: GlowShapeFactory.Glyph, from: Vec2, to: Vec2, facing: Double, count: Int = 4,
                     color: RGB, duration: TimeInterval = 0.4) {
        let dx = world.delta(from: from.x, to: to.x)
        for index in 0..<count {
            let t = Double(index) / Double(count)
            let sprite = SKSpriteNode()
            factory.apply(glyph, to: sprite)
            sprite.color = color.uiColor()
            sprite.colorBlendFactor = 0.6
            sprite.blendMode = .add
            sprite.xScale = facing < 0 ? -1 : 1
            sprite.alpha = 0.15 + 0.45 * t
            let life = duration * (0.5 + 0.5 * t)
            sprite.run(.fadeOut(withDuration: life))
            let at = Vec2(world.wrap(from.x + dx * t), from.y + (to.y - from.y) * t)
            add(sprite, at: at, life: life, kind: .ghost)
        }
    }

    // MARK: Frame

    func update(cameraX: Double, halfWidth: Double, elapsed: Double) {
        effects.removeAll { $0.node.parent == nil }
        for effect in effects {
            effect.node.position = CGPoint(x: world.delta(from: cameraX, to: effect.worldX), y: effect.worldY)
        }
        let dt = min(max(elapsed, 0), 0.1)
        let top = world.height
        for index in particles.indices where particles[index].active {
            var p = particles[index]
            p.life -= dt
            // Particles never rise into the HUD band; they die at the top of the world.
            if p.life <= 0 || p.y > top {
                particles[index].active = false
                sprites[index].isHidden = true
                continue
            }
            let damping = exp(-p.drag * dt)
            p.vx *= damping
            p.vy = p.vy * damping - p.gravity * dt
            p.x = world.wrap(p.x + p.vx * dt)
            p.y += p.vy * dt
            particles[index] = p

            let sprite = sprites[index]
            let dx = world.delta(from: cameraX, to: p.x)
            guard abs(dx) < halfWidth + 30 else {
                sprite.isHidden = true
                continue
            }
            sprite.isHidden = false
            sprite.position = CGPoint(x: dx, y: p.y)
            let t = p.life / p.maxLife
            sprite.alpha = CGFloat(min(1, t * 1.6) * p.alpha)
            switch p.look {
            case .spark:
                sprite.zRotation = CGFloat(atan2(p.vy, p.vx))
                sprite.xScale = CGFloat(p.size * (0.35 + 0.65 * t))
                sprite.yScale = CGFloat(p.size)
            case .dot:
                sprite.setScale(CGFloat(p.size * (0.5 + 0.5 * t)))
            case .shard:
                sprite.zRotation += CGFloat(p.spin * dt)
                sprite.setScale(CGFloat(p.size))
            }
        }
    }

    private enum Kind { case ring, ghost }

    private func add(_ node: SKNode, at pos: Vec2, life: TimeInterval, kind: Kind) {
        addChild(node)
        node.run(.sequence([.wait(forDuration: life + 0.05), .removeFromParent()]))
        effects.append(Effect(node: node, worldX: pos.x, worldY: pos.y))
        // Never more than a handful at once: the oldest goes first.
        let cap = kind == .ring ? Self.maxRings : Self.maxGhosts
        let isKind: (Effect) -> Bool = { kind == .ring ? !($0.node is SKSpriteNode) : $0.node is SKSpriteNode }
        var live = effects.filter { $0.node.parent != nil && isKind($0) }
        while live.count > cap {
            live.removeFirst().node.removeFromParent()
        }
    }
}
