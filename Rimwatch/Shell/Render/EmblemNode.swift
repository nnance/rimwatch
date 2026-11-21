import GameCore
import SpriteKit
import UIKit

/// The game's emblem ("The Rim", `Emblem` in GameCore) drawn with the glow renderer, for the
/// title screen. Line widths follow the emblem's, scaled to the size it is shown at, so it looks
/// like the app icon.
@MainActor
final class EmblemNode: SKSpriteNode {
    /// Room around the emblem's square for the halos, in points.
    private static let padding: CGFloat = 14
    private static var cache: [CGFloat: SKTexture] = [:]
    private var side: CGFloat = 0

    init() {
        super.init(texture: nil, color: .clear, size: .zero)
        blendMode = .add
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Draws the emblem so its square is `side` points across, centred on the node.
    func show(side newSide: CGFloat) {
        let side = newSide.rounded()
        guard side > 0, side != self.side else { return }
        self.side = side
        texture = Self.texture(side: side)
        size = CGSize(width: side + 2 * Self.padding, height: side + 2 * Self.padding)
    }

    private static func texture(side: CGFloat) -> SKTexture {
        if let texture = cache[side] { return texture }
        let pad = padding
        let scale = side / CGFloat(Emblem.side)
        let full = side + 2 * pad
        // UIKit's drawing context is y down, as the emblem is.
        func point(_ v: Vec2) -> CGPoint { CGPoint(x: pad + CGFloat(v.x) * scale, y: pad + CGFloat(v.y) * scale) }
        let image = GlowShapeFactory.image(size: CGSize(width: full, height: full), scale: 2) { context in
            for star in Emblem.stars {
                let r = CGFloat(star.radius) * scale
                let c = point(star.center)
                context.saveGState()
                context.setShadow(offset: .zero, blur: r * 3, color: Emblem.starColor.cgColor(alpha: star.alpha))
                context.setFillColor(Emblem.starColor.lightened(0.3).cgColor(alpha: star.alpha))
                context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                context.restoreGState()
            }
            for line in Emblem.lines {
                let path = CGMutablePath()
                path.addLines(between: line.points.map(point))
                if line.closed { path.closeSubpath() }
                let width = CGFloat(line.width) * scale
                GlowShapeFactory.strokeGlow(path, color: line.color,
                                            weight: width / GlowShapeFactory.Style.lineWidth, in: context)
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[side] = texture
        return texture
    }
}
