import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// The small pause button on the gameplay screen: top corner, below the band kept for the
/// scanner, away from the touch controls. Its touch target is at least 44 pt.
@MainActor
final class PauseButton: SKNode {
    private let glyph = SKSpriteNode()
    private(set) var hitFrame: CGRect = .zero
    private var builtRadius: CGFloat = 0
    private let theme: any Theme

    init(theme: any Theme) {
        self.theme = theme
        super.init()
        addChild(glyph)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// `topY` is the lowest edge of the reserved top band, in scene coordinates.
    func layout(size: CGSize, safeArea: UIEdgeInsets, topY: CGFloat) {
        let radius: CGFloat = 15
        let margin = max(12, min(size.width, size.height) * 0.03)
        let center = CGPoint(x: size.width - safeArea.right - margin - 22, y: topY - 8 - 22)
        position = center
        hitFrame = CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52)
        guard radius != builtRadius else { return }
        builtRadius = radius
        let color = theme.palette.controls
        let shape = ShapeDescription(scale: Double(radius), strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 36), color: color),
            ShapeStroke([Vec2(-0.25, -0.38), Vec2(-0.25, 0.38)], color: color),
            ShapeStroke([Vec2(0.25, -0.38), Vec2(0.25, 0.38)], color: color),
        ])
        let factory = GlowShapeFactory(theme: theme, screenScale: 2)
        factory.apply(factory.glyph(key: "pause-button", shape: shape, pointsPerUnit: 1), to: glyph)
        glyph.alpha = 0.55
    }

    func setPressed(_ pressed: Bool) {
        glyph.alpha = pressed ? 1 : 0.55
        glyph.setScale(pressed ? 0.92 : 1)
    }
}

/// The resume countdown: a large digit in the middle of the playfield.
@MainActor
final class CountdownNode: SKNode {
    private var shown: Int?
    private var sprite: SKSpriteNode?
    private let theme: any Theme

    init(theme: any Theme) {
        self.theme = theme
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func show(remaining: Double, size: CGSize) {
        let count = max(Int(remaining.rounded(.up)), 1)
        position = CGPoint(x: size.width / 2, y: size.height / 2)
        // Each second the digit pops in and fades as it shrinks.
        let fraction = CGFloat(remaining - floor(remaining))
        sprite?.alpha = 0.6 + 0.4 * (fraction == 0 ? 1 : fraction)
        sprite?.setScale(0.85 + 0.25 * (fraction == 0 ? 1 : fraction))
        guard count != shown else { return }
        shown = count
        sprite?.removeFromParent()
        let size = min(size.width, size.height) * 0.3
        let made = GlowText.sprite("\(count)", style: .heading(size), color: theme.palette.hud)
        addChild(made)
        sprite = made
    }

    func hide() {
        shown = nil
        sprite?.removeFromParent()
        sprite = nil
    }
}

/// Shown on a phone without a hinge.
@MainActor
final class MadeForDuoNode: SKNode {
    private var builtFor: CGSize = .zero
    private let theme: any Theme

    init(theme: any Theme) {
        self.theme = theme
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func layout(size: CGSize) {
        guard size != builtFor else { return }
        builtFor = size
        removeAllChildren()
        let short = min(size.width, size.height)
        let heading = min(max(short * 0.11, 28), 56)
        let body = min(max(short * 0.042, 14), 20)
        var lines: [(String, GlowText.Style, RGB)] = [
            ("RIMWATCH", .heading(heading), theme.terrain.ridge),
            ("Made for iPhone Duo", .item(body * 1.2), theme.palette.hud),
            ("Rimwatch plays on the inner display", .body(body), theme.palette.hud.lightened(0.3)),
            ("of a folding iPhone Duo.", .body(body), theme.palette.hud.lightened(0.3)),
        ]
        #if DEBUG
        lines.append(("Debug: launch with -hinge open to test here.", .body(body * 0.8), theme.palette.falling))
        #endif
        let spacing: [CGFloat] = [heading * 1.6, body * 2.4, body * 1.6, body * 2.4, body * 1.6]
        let total = spacing.prefix(lines.count).reduce(0, +)
        var y = size.height / 2 + total / 2
        for (index, line) in lines.enumerated() {
            let sprite = GlowText.sprite(line.0, style: line.1, color: line.2)
            sprite.position = CGPoint(x: size.width / 2, y: y - spacing[index] / 2)
            addChild(sprite)
            y -= spacing[index]
        }
    }
}
