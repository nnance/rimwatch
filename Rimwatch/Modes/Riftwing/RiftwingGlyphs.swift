import GameCore
import RiftwingCore
import SpriteKit
import UIKit

/// Riftwing's glyphs: the theme's shape for each thing at the gallery's points per unit, figures
/// at the run's figure scale (`RiftwingTuning.figureScale`) so each is drawn at the size it
/// collides at.
///
/// Figures (the rider, opponents, pods, mines, a freed colonist) are about 17 points across, so
/// they are drawn crisp rather than with the shared factory's wide neon halo, which at that
/// size swallowed the shape: a tight halo, a firm line, a bright core, and every closed outline
/// (wings, bodies, plates, sacs, shells) faintly filled so the figure reads as a solid
/// silhouette. Everything else (the rock, the Rift, markers) uses the shared factory.
@MainActor
struct RiftwingGlyphs {
    let factory: GlowShapeFactory
    let theme: RiftCaves
    let figureScale: Double
    /// Pixels per point the figure textures are drawn at.
    let screenScale: CGFloat
    private let figures = FigureCache()

    init(factory: GlowShapeFactory, theme: RiftCaves, figureScale: Double, screenScale: CGFloat) {
        self.factory = factory
        self.theme = theme
        self.figureScale = figureScale
        self.screenScale = min(max(screenScale, 1), 3)
    }

    /// The figure textures, cached per scale, cleared with the factory's when the scale changes.
    final class FigureCache {
        var glyphs: [String: GlowShapeFactory.Glyph] = [:]
    }

    /// Throws away the figure textures (the gallery's scale changed).
    func clearFigures() {
        figures.glyphs.removeAll()
    }

    /// The glyph for a thing, optionally recoloured in one colour.
    func glyph(_ thing: RiftwingShape, tint: RGB? = nil, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        var shape = theme.shape(for: thing, figureScale: figureScale)
        if let tint { shape = shape.recoloured(tint) }
        let key = "riftwing|\(thing)|\(tint.map { "\($0)" } ?? "-")|x\(figureScale)"
        if thing.isFigure { return figure(key: key, shape: shape, pointsPerUnit: pointsPerUnit) }
        return factory.glyph(key: key, shape: shape, pointsPerUnit: pointsPerUnit)
    }

    /// A shape drawn at `scale` gallery units per unit (for markers drawn at a size of their own).
    func glyph(_ thing: RiftwingShape, scale: Double, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        let shape = theme.shape(for: thing)
        return factory.glyph(key: "riftwing|\(thing)|s\(scale)",
                             shape: ShapeDescription(scale: scale, strokes: shape.strokes), pointsPerUnit: pointsPerUnit)
    }

    /// Any one-off shape (the cavern's rock, the Rift, motes), cached under `key`.
    func glyph(key: String, strokes: [ShapeStroke], scale: Double = 1, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        factory.glyph(key: "riftwing-\(key)", shape: ShapeDescription(scale: scale, strokes: strokes),
                      pointsPerUnit: pointsPerUnit)
    }

    // MARK: Crisp figures

    /// Line widths and blur in screen points for a figure: about a third of the shared halo.
    enum FigureStyle {
        static let haloWidth: CGFloat = 2.6
        static let haloBlur: CGFloat = 3.2
        static let lineWidth: CGFloat = 1.7
        static let lineBlur: CGFloat = 1.0
        static let coreWidth: CGFloat = 0.9
        static let fillAlpha: CGFloat = 0.2
        static let padding: CGFloat = 6
    }

    private func figure(key: String, shape: ShapeDescription, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        let cacheKey = "\(key)@\(pointsPerUnit)"
        if let glyph = figures.glyphs[cacheKey] { return glyph }
        let glyph = Self.renderFigure(shape, pointsPerUnit: pointsPerUnit, screenScale: screenScale)
        figures.glyphs[cacheKey] = glyph
        return glyph
    }

    static func renderFigure(_ shape: ShapeDescription, pointsPerUnit: CGFloat, screenScale: CGFloat) -> GlowShapeFactory.Glyph {
        let bounds = shape.bounds
        let k = CGFloat(shape.scale) * pointsPerUnit
        let pad = FigureStyle.padding
        let width = CGFloat(bounds.max.x - bounds.min.x) * k + 2 * pad
        let height = CGFloat(bounds.max.y - bounds.min.y) * k + 2 * pad
        func point(_ v: Vec2) -> CGPoint {
            CGPoint(x: CGFloat(v.x - bounds.min.x) * k + pad, y: height - (CGFloat(v.y - bounds.min.y) * k + pad))
        }
        let image = GlowShapeFactory.image(size: CGSize(width: width, height: height), scale: screenScale) { context in
            context.setLineJoin(.round)
            context.setLineCap(.round)
            // Fills first, under every line, so a body never hides a wing's edge.
            for stroke in shape.strokes where stroke.closed {
                let path = CGMutablePath()
                path.addLines(between: stroke.points.map(point))
                path.closeSubpath()
                context.setFillColor(stroke.color.cgColor(alpha: Double(FigureStyle.fillAlpha)))
                context.addPath(path)
                context.fillPath()
            }
            for stroke in shape.strokes {
                let path = CGMutablePath()
                path.addLines(between: stroke.points.map(point))
                if stroke.closed { path.closeSubpath() }
                context.saveGState()
                context.setShadow(offset: .zero, blur: FigureStyle.haloBlur, color: stroke.color.cgColor(alpha: 0.7))
                context.setStrokeColor(stroke.color.cgColor(alpha: 0.3))
                context.setLineWidth(FigureStyle.haloWidth)
                context.addPath(path)
                context.strokePath()
                context.setShadow(offset: .zero, blur: FigureStyle.lineBlur, color: stroke.color.cgColor(alpha: 0.9))
                context.setStrokeColor(stroke.color.cgColor())
                context.setLineWidth(FigureStyle.lineWidth)
                context.addPath(path)
                context.strokePath()
                context.setShadow(offset: .zero, blur: 0, color: nil)
                context.setStrokeColor(stroke.color.lightened(0.7).cgColor())
                context.setLineWidth(FigureStyle.coreWidth)
                context.addPath(path)
                context.strokePath()
                context.restoreGState()
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return GlowShapeFactory.Glyph(
            texture: texture,
            size: CGSize(width: width / pointsPerUnit, height: height / pointsPerUnit),
            anchorPoint: CGPoint(x: (CGFloat(-bounds.min.x) * k + pad) / width,
                                 y: (CGFloat(-bounds.min.y) * k + pad) / height))
    }
}

/// The one way Riftwing gives a sprite a texture. `GlowShapeFactory.apply` sets the sprite's
/// `size`, which in SpriteKit includes the sprite's scale, so dressing resets the scale to 1
/// first and the result never depends on what the sprite carried before. The caller sets
/// whatever scale it wants afterwards.
@MainActor
enum RiftwingSprites {
    static func dress(_ sprite: SKSpriteNode, with glyph: GlowShapeFactory.Glyph, factory: GlowShapeFactory) {
        sprite.xScale = 1
        sprite.yScale = 1
        factory.apply(glyph, to: sprite)
        if let pooled = sprite as? RiftwingMode.PoolSprite { pooled.glyph = glyph }
    }
}
