import GameCore
import RedoubtCore
import SpriteKit

/// Redoubt's glyphs: the theme's shape for each thing, drawn by the shared factory at the arena's
/// points per unit. Held as a concrete theme, so no lookup crosses an existential.
@MainActor
struct RedoubtGlyphs {
    let factory: GlowShapeFactory
    let theme: CalderDome

    /// The glyph for a thing, optionally recoloured in one colour.
    func glyph(_ thing: RedoubtShape, tint: RGB? = nil, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        var shape = theme.shape(for: thing)
        if let tint { shape = shape.recoloured(tint) }
        return factory.glyph(key: "redoubt|\(thing)|\(tint.map { "\($0)" } ?? "-")", shape: shape,
                             pointsPerUnit: pointsPerUnit)
    }

    /// A shape drawn at `scale` arena units per unit (for markers drawn at a size of their own).
    func glyph(_ thing: RedoubtShape, scale: Double, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        let shape = theme.shape(for: thing)
        return factory.glyph(key: "redoubt|\(thing)|s\(scale)",
                             shape: ShapeDescription(scale: scale, strokes: shape.strokes), pointsPerUnit: pointsPerUnit)
    }
}
