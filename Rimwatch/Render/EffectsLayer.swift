import Foundation
import GameCore
import SpriteKit
import UIKit

/// Short-lived event feedback: spark bursts, expanding rings and Blink trails. Each effect is
/// anchored at a world position and re-placed relative to the camera every frame. Richer particles
/// arrive with the polish step.
@MainActor
final class EffectsLayer: SKNode {
    private struct Effect {
        let node: SKNode
        let worldX: Double
        let worldY: Double
    }

    var world: World
    private let factory: GlowShapeFactory
    private var effects: [Effect] = []
    private var pointsPerUnit: CGFloat = 1

    init(world: World, factory: GlowShapeFactory) {
        self.world = world
        self.factory = factory
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func setPointsPerUnit(_ value: CGFloat) {
        pointsPerUnit = value
    }

    func removeAll() {
        effects.forEach { $0.node.removeFromParent() }
        effects.removeAll()
    }

    /// Sparks flying out from a point.
    func burst(at pos: Vec2, color: RGB, count: Int, speed: Double = 160, life: TimeInterval = 0.55) {
        let spark = factory.glyph(
            key: "spark-\(color)",
            shape: ShapeDescription(scale: 3, strokes: [ShapeStroke([Vec2(-1, 0), Vec2(1, 0)], color: color)]),
            pointsPerUnit: pointsPerUnit
        )
        let container = SKNode()
        for index in 0..<count {
            let sprite = SKSpriteNode()
            factory.apply(spark, to: sprite)
            let angle = Double(index) / Double(count) * 2 * .pi + Double.random(in: -0.3...0.3)
            let distance = speed * life * Double.random(in: 0.5...1.1)
            sprite.zRotation = angle
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: life)
            move.timingMode = .easeOut
            sprite.run(.group([move, .fadeOut(withDuration: life), .scaleX(to: 0.3, duration: life)]))
            container.addChild(sprite)
        }
        add(container, at: pos, life: life)
    }

    /// A ring that grows from a point to `radius` world units. The circle is re-stroked every frame
    /// at its current radius, so the line stays thin and crisp however large it gets: a soft wide
    /// halo, the coloured line and a near-white core, all fixed widths in screen points.
    func ring(at pos: Vec2, color: RGB, radius: Double, duration: TimeInterval = 0.4) {
        let ppu = max(pointsPerUnit, 0.01)
        let passes: [(width: CGFloat, color: UIColor)] = [
            (6 / ppu, color.uiColor(alpha: 0.18)),
            (2.2 / ppu, color.uiColor(alpha: 0.85)),
            (1.0 / ppu, color.lightened(0.65).uiColor()),
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
        let start = radius * 0.1
        let grow = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = min(Double(elapsed) / duration, 1)
            // Ease out: fast at first, settling at full size.
            let eased = 1 - (1 - t) * (1 - t)
            let r = start + (radius - start) * eased
            let path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            for shape in strokes { shape.path = path }
            node.alpha = CGFloat(1 - t)
        }
        container.run(grow)
        add(container, at: pos, life: duration)
    }

    /// A fading streak between two points, for Blink.
    func trail(from: Vec2, to: Vec2, color: RGB, duration: TimeInterval = 0.35) {
        let dx = world.delta(from: from.x, to: to.x)
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        let sprite = SKSpriteNode(color: color.uiColor(), size: CGSize(width: length, height: 2.5 / pointsPerUnit))
        sprite.blendMode = .add
        sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        sprite.zRotation = atan2(dy, dx)
        sprite.run(.group([.fadeOut(withDuration: duration), .scaleY(to: 0.2, duration: duration)]))
        let container = SKNode()
        container.addChild(sprite)
        add(container, at: from, life: duration)
    }

    func update(cameraX: Double) {
        effects.removeAll { $0.node.parent == nil }
        for effect in effects {
            effect.node.position = CGPoint(x: world.delta(from: cameraX, to: effect.worldX), y: effect.worldY)
        }
    }

    private func add(_ node: SKNode, at pos: Vec2, life: TimeInterval) {
        addChild(node)
        node.run(.sequence([.wait(forDuration: life + 0.05), .removeFromParent()]))
        effects.append(Effect(node: node, worldX: pos.x, worldY: pos.y))
    }
}
