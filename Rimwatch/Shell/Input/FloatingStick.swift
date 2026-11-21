import GameCore
import SpriteKit
import UIKit

/// A floating touch stick on screen: a ring that jumps to wherever a thumb lands in its zone and a
/// knob that follows the thumb, reporting an analogue `vector`. The logic is `TouchStick` in
/// GameCore; this draws it and tracks the one touch driving it. A mode can make one (Ridgeline's
/// flight stick) or two (move and aim), each confined to its own zone.
///
/// It owns two sprites, `nodes`, which the owner adds to its own layer; positions are in that
/// layer's coordinates (scene points, origin bottom left).
@MainActor
final class FloatingStick {
    let base = SKSpriteNode()
    let knob = SKSpriteNode()
    var nodes: [SKNode] { [base, knob] }

    /// Length 0...1, up and right positive. Zero while no thumb is on it.
    var vector: Vec2 { stick.vector }
    var isActive: Bool { stick.isActive }
    /// Where a touch may start it.
    private(set) var zone: CGRect = .zero

    private let factory: GlowShapeFactory
    private let color: RGB
    private var stick = TouchStick()
    private var touch: UITouch?
    private var radius: CGFloat { CGFloat(stick.radius) }

    init(factory: GlowShapeFactory, color: RGB) {
        self.factory = factory
        self.color = color
    }

    /// Size, resting place and zone. Renders the ring and knob for the radius.
    func layout(radius: CGFloat, rest: CGPoint, zone: CGRect) {
        self.zone = zone
        stick.layout(zone: TouchStick.Zone(minX: Double(zone.minX), minY: Double(zone.minY),
                                           maxX: Double(zone.maxX), maxY: Double(zone.maxY)),
                     radius: Double(radius), rest: Vec2(Double(rest.x), Double(rest.y)))
        factory.apply(factory.glyph(key: "stick-base-\(radius)",
                                    shape: ShapeDescription(scale: radius, strokes: [
                                        ShapeStroke(ShapeKit.arc(radius: 1, segments: 48), color: color),
                                    ]), pointsPerUnit: 1), to: base)
        factory.apply(factory.glyph(key: "stick-knob-\(radius)",
                                    shape: ShapeDescription(scale: radius * 0.4, strokes: [
                                        ShapeStroke(ShapeKit.arc(radius: 1, segments: 32), color: color),
                                        ShapeStroke(ShapeKit.arc(radius: 0.45, segments: 20), color: color),
                                    ]), pointsPerUnit: 1), to: knob)
        refresh()
    }

    /// A touch went down at `p` (in the owner's coordinates). Returns true if the stick took it.
    func touchBegan(_ touch: UITouch, at p: CGPoint) -> Bool {
        guard stick.begin(at: Vec2(Double(p.x), Double(p.y))) else { return false }
        self.touch = touch
        refresh()
        return true
    }

    /// Follows the stick's touch if it is among `touches`. Returns true if it moved.
    func touchesMoved(_ touches: Set<UITouch>, in layer: SKNode) -> Bool {
        guard let touch, touches.contains(touch) else { return false }
        let p = touch.location(in: layer)
        stick.move(to: Vec2(Double(p.x), Double(p.y)))
        refresh()
        return true
    }

    /// A touch lifted or was cancelled. Returns true if it was the stick's.
    @discardableResult
    func touchEnded(_ touch: UITouch) -> Bool {
        guard touch === self.touch else { return false }
        release()
        return true
    }

    /// Lets go, e.g. when touch-ups may never arrive.
    func release() {
        touch = nil
        stick.end()
        refresh()
    }

    /// Draws the ring and knob where the stick is: faint at rest, brighter while held.
    func refresh() {
        let active = stick.isActive
        let center = CGPoint(x: CGFloat(stick.center.x), y: CGFloat(stick.center.y))
        base.position = center
        base.alpha = active ? 0.55 : 0.18
        knob.position = CGPoint(x: center.x + CGFloat(stick.vector.x) * radius,
                                y: center.y + CGFloat(stick.vector.y) * radius)
        knob.alpha = active ? 0.9 : 0.22
    }
}
