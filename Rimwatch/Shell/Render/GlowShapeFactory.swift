import GameCore
import SpriteKit
import UIKit

/// Turns shapes into textures once, with a neon look: a wide soft halo, a coloured line and
/// a thin near-white core, meant to be drawn additively on black.
///
/// Textures are rendered for a given number of screen points per world unit, so lines stay the
/// same thin width on any display. When that scale changes the cache is thrown away.
@MainActor
final class GlowShapeFactory {
    struct Glyph {
        let texture: SKTexture
        /// Size in the units the texture was rendered for (world units, or points at scale 1).
        let size: CGSize
        let anchorPoint: CGPoint
    }

    /// Line widths and blur in screen points.
    nonisolated enum Style {
        static let coreWidth: CGFloat = 1.1
        static let lineWidth: CGFloat = 2.0
        static let haloWidth: CGFloat = 3.0
        static let haloBlur: CGFloat = 9
        static let lineBlur: CGFloat = 3.5
        /// Room around a shape for its halo.
        static let padding: CGFloat = 12
    }

    private var cache: [String: Glyph] = [:]
    private let screenScale: CGFloat

    init(screenScale: CGFloat) {
        // Glow is soft anyway; 2x keeps memory down on 3x screens without visible loss.
        self.screenScale = min(screenScale, 2)
    }

    /// Every texture made so far, for preloading.
    var cachedTextures: [SKTexture] { cache.values.map(\.texture) }

    func clear() {
        cache.removeAll()
    }

    /// The glyph for any shape, cached under `key`.
    func glyph(key: String, shape: ShapeDescription, pointsPerUnit: CGFloat) -> Glyph {
        let cacheKey = "\(key)@\(pointsPerUnit)"
        if let glyph = cache[cacheKey] { return glyph }
        let glyph = render(shape, pointsPerUnit: pointsPerUnit)
        cache[cacheKey] = glyph
        return glyph
    }

    func apply(_ glyph: Glyph, to sprite: SKSpriteNode) {
        sprite.texture = glyph.texture
        sprite.size = glyph.size
        sprite.anchorPoint = glyph.anchorPoint
        sprite.blendMode = .add
    }

    private func render(_ shape: ShapeDescription, pointsPerUnit: CGFloat) -> Glyph {
        let bounds = shape.bounds
        let pointsPerShapeUnit = CGFloat(shape.scale) * pointsPerUnit
        let pad = Style.padding
        let width = CGFloat(bounds.max.x - bounds.min.x) * pointsPerShapeUnit + 2 * pad
        let height = CGFloat(bounds.max.y - bounds.min.y) * pointsPerShapeUnit + 2 * pad

        func point(_ v: Vec2) -> CGPoint {
            CGPoint(x: CGFloat(v.x - bounds.min.x) * pointsPerShapeUnit + pad,
                    y: height - (CGFloat(v.y - bounds.min.y) * pointsPerShapeUnit + pad))
        }

        let image = Self.image(size: CGSize(width: width, height: height), scale: screenScale) { context in
            for stroke in shape.strokes {
                let path = CGMutablePath()
                path.addLines(between: stroke.points.map(point))
                if stroke.closed { path.closeSubpath() }
                Self.strokeGlow(path, color: stroke.color, in: context)
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return Glyph(
            texture: texture,
            size: CGSize(width: width / pointsPerUnit, height: height / pointsPerUnit),
            anchorPoint: CGPoint(
                x: (CGFloat(-bounds.min.x) * pointsPerShapeUnit + pad) / width,
                y: (CGFloat(-bounds.min.y) * pointsPerShapeUnit + pad) / height
            )
        )
    }

    // MARK: Drawing helpers, shared with the terrain and the controls

    /// Safe off the main thread (terrain is pre-rendered in the background).
    nonisolated static func image(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    /// Strokes `path` as a glowing line. `strength` scales the brightness of every pass.
    nonisolated static func strokeGlow(_ path: CGPath, color: RGB, strength: Double = 1, in context: CGContext) {
        context.saveGState()
        context.setLineJoin(.round)
        context.setLineCap(.round)

        context.setShadow(offset: .zero, blur: Style.haloBlur, color: color.cgColor(alpha: 0.9 * strength))
        context.setStrokeColor(color.cgColor(alpha: 0.35 * strength))
        context.setLineWidth(Style.haloWidth)
        context.addPath(path)
        context.strokePath()

        context.setShadow(offset: .zero, blur: Style.lineBlur, color: color.cgColor(alpha: strength))
        context.setStrokeColor(color.cgColor(alpha: strength))
        context.setLineWidth(Style.lineWidth)
        context.addPath(path)
        context.strokePath()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(color.lightened(0.65).cgColor(alpha: strength))
        context.setLineWidth(Style.coreWidth)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}
