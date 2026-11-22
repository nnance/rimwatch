import GameCore
import RiftwingCore
import SpriteKit

/// Riftwing's glyphs: the theme's shape for each thing, drawn by the shared factory at the
/// gallery's points per unit, figures at the run's figure scale (`RiftwingTuning.figureScale`)
/// so each is drawn at the size it collides at.
@MainActor
struct RiftwingGlyphs {
    let factory: GlowShapeFactory
    let theme: RiftCaves
    let figureScale: Double

    /// The glyph for a thing, optionally recoloured in one colour.
    func glyph(_ thing: RiftwingShape, tint: RGB? = nil, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        var shape = theme.shape(for: thing, figureScale: figureScale)
        if let tint { shape = shape.recoloured(tint) }
        return factory.glyph(key: "riftwing|\(thing)|\(tint.map { "\($0)" } ?? "-")|x\(figureScale)", shape: shape,
                             pointsPerUnit: pointsPerUnit)
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
