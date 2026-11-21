import Foundation
import GameCore
import RedoubtCore
import SpriteKit
import UIKit

/// Short-lived feedback on the floor, in arena units: spark bursts, small pops, and the big rings
/// (a Shockwave, the orb lost or returning). Everything comes from pools made up front and is
/// moved by hand each frame, with no actions, so a kill rate of several hundred a minute never
/// grows the node count. When a pool is full the oldest entry is reused.
@MainActor
final class RedoubtEffects: SKNode {
    private struct Particle {
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var life = 0.0, maxLife = 1.0, size = 1.0
        var active = false
    }

    private struct Pop {
        var x = 0.0, y = 0.0, radius = 10.0, life = 0.0, maxLife = 0.25
        var active = false
    }

    private struct Ring {
        var x = 0.0, y = 0.0
        var from = 0.0, to = 0.0
        var age = 0.0, duration = 0.4
        var active = false
    }

    static let particleCount = 360
    static let popCount = 32
    static let ringCount = 6

    private var particles = [Particle](repeating: Particle(), count: RedoubtEffects.particleCount)
    private var sparkSprites: [SKSpriteNode] = []
    private var cursor = 0
    private var pops = [Pop](repeating: Pop(), count: RedoubtEffects.popCount)
    private var popSprites: [SKSpriteNode] = []
    private var popCursor = 0
    private var rings = [Ring](repeating: Ring(), count: RedoubtEffects.ringCount)
    private var ringShapes: [[SKShapeNode]] = []
    private var ringCursor = 0
    private var rng = SeededRNG(seed: 0x0DE5_7EFF)
    private var floorBounds = CGRect(x: 0, y: 0, width: 900, height: 600)
    private var pointsPerUnit: CGFloat = 1

    override init() {
        super.init()
        for _ in 0..<Self.particleCount {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            sparkSprites.append(sprite)
        }
        for _ in 0..<Self.popCount {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            popSprites.append(sprite)
        }
        for _ in 0..<Self.ringCount {
            let passes = (0..<3).map { _ -> SKShapeNode in
                let shape = SKShapeNode()
                shape.fillColor = .clear
                shape.blendMode = .add
                shape.isAntialiased = true
                shape.isHidden = true
                addChild(shape)
                return shape
            }
            ringShapes.append(passes)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// White textures, tinted per use, at the arena's scale.
    func setPointsPerUnit(_ ppu: CGFloat, factory: GlowShapeFactory, arena: CGSize) {
        pointsPerUnit = ppu
        floorBounds = CGRect(origin: .zero, size: arena)
        let white = RGB(1, 1, 1)
        let spark = factory.glyph(key: "redoubt-spark", shape: ShapeDescription(scale: 3, strokes: [
            ShapeStroke([Vec2(-1, 0), Vec2(1, 0)], color: white),
        ]), pointsPerUnit: ppu)
        for sprite in sparkSprites { RedoubtSprites.dress(sprite, with: spark, factory: factory) }
        let pop = factory.glyph(key: "redoubt-pop", shape: ShapeDescription(scale: 10, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 24), color: white),
        ]), pointsPerUnit: ppu)
        for sprite in popSprites { RedoubtSprites.dress(sprite, with: pop, factory: factory) }
    }

    func removeAll() {
        for index in particles.indices where particles[index].active {
            particles[index].active = false
            sparkSprites[index].isHidden = true
        }
        for index in pops.indices where pops[index].active {
            pops[index].active = false
            popSprites[index].isHidden = true
        }
        for index in rings.indices {
            rings[index].active = false
            for shape in ringShapes[index] { shape.isHidden = true }
        }
    }

    var activeParticles: Int { particles.count { $0.active } }

    /// Sparks flying out from a point.
    func burst(at pos: Vec2, color: RGB, count: Int, speed: Double = 150, life: Double = 0.45, size: Double = 1) {
        let uiColor = color.uiColor()
        for _ in 0..<count {
            let index = cursor
            cursor = (cursor + 1) % Self.particleCount
            let angle = rng.range(0...(2 * Double.pi))
            let v = rng.range(speed * 0.4...speed * 1.2)
            var p = Particle()
            p.x = pos.x
            p.y = pos.y
            p.vx = cos(angle) * v
            p.vy = sin(angle) * v
            p.maxLife = rng.range(life * 0.6...life)
            p.life = p.maxLife
            p.size = size * rng.range(0.8...1.2)
            p.active = true
            particles[index] = p
            let sprite = sparkSprites[index]
            sprite.color = uiColor
            sprite.isHidden = true
        }
    }

    /// A small ring that swells and fades where something died.
    func pop(at pos: Vec2, color: RGB, radius: Double, life: Double = 0.25) {
        let index = popCursor
        popCursor = (popCursor + 1) % Self.popCount
        pops[index] = Pop(x: pos.x, y: pos.y, radius: radius, life: life, maxLife: life, active: true)
        let sprite = popSprites[index]
        sprite.color = color.uiColor()
        sprite.position = CGPoint(x: pos.x, y: pos.y)
        sprite.isHidden = false
    }

    /// A big ring growing from `from` to `to` units (shrinking with `to` < `from`), re-stroked each
    /// frame so the line stays thin at any size.
    func ring(at pos: Vec2, color: RGB, from: Double, to: Double, duration: Double = 0.45, width: CGFloat = 1) {
        let index = ringCursor
        ringCursor = (ringCursor + 1) % Self.ringCount
        rings[index] = Ring(x: pos.x, y: pos.y, from: from, to: to, age: 0, duration: duration, active: true)
        let ppu = max(pointsPerUnit, 0.01)
        let passes: [(CGFloat, UIColor)] = [
            (7 * width / ppu, color.uiColor(alpha: 0.2)),
            (2.4 * width / ppu, color.uiColor(alpha: 0.85)),
            (1.0 * width / ppu, color.lightened(0.65).uiColor()),
        ]
        for (shape, pass) in zip(ringShapes[index], passes) {
            shape.lineWidth = pass.0
            shape.strokeColor = pass.1
            shape.position = CGPoint(x: pos.x, y: pos.y)
            shape.isHidden = false
            shape.alpha = 1
        }
    }

    func update(elapsed: Double) {
        let dt = min(max(elapsed, 0), 0.1)
        let damping = exp(-2.6 * dt)
        for index in 0..<Self.particleCount where particles[index].active {
            var p = particles[index]
            p.life -= dt
            if p.life <= 0 || !floorBounds.contains(CGPoint(x: p.x, y: p.y)) {
                particles[index].active = false
                sparkSprites[index].isHidden = true
                continue
            }
            p.vx *= damping
            p.vy *= damping
            p.x += p.vx * dt
            p.y += p.vy * dt
            particles[index] = p
            let sprite = sparkSprites[index]
            sprite.isHidden = false
            sprite.position = CGPoint(x: p.x, y: p.y)
            sprite.zRotation = CGFloat(atan2(p.vy, p.vx))
            let t = p.life / p.maxLife
            sprite.alpha = CGFloat(min(1, t * 1.6))
            sprite.xScale = CGFloat(p.size * (0.35 + 0.65 * t))
            sprite.yScale = CGFloat(p.size)
        }
        for index in 0..<Self.popCount where pops[index].active {
            pops[index].life -= dt
            let sprite = popSprites[index]
            guard pops[index].life > 0 else {
                pops[index].active = false
                sprite.isHidden = true
                continue
            }
            let t = 1 - pops[index].life / pops[index].maxLife
            sprite.setScale(CGFloat(pops[index].radius / 10 * (0.6 + 1.2 * t)))
            sprite.alpha = CGFloat(1 - t)
        }
        for index in 0..<Self.ringCount where rings[index].active {
            rings[index].age += dt
            let ring = rings[index]
            let t = min(ring.age / ring.duration, 1)
            let shapes = ringShapes[index]
            guard t < 1 else {
                rings[index].active = false
                for shape in shapes { shape.isHidden = true }
                continue
            }
            let eased = 1 - (1 - t) * (1 - t)
            let r = ring.from + (ring.to - ring.from) * eased
            let path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            let alpha = CGFloat(ring.to < ring.from ? min(1, 0.3 + t) : 1 - t * t)
            for shape in shapes {
                shape.path = path
                shape.alpha = alpha
            }
        }
    }
}
