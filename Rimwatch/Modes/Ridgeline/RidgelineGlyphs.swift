import GameCore
import RidgelineCore
import SpriteKit

/// Ridgeline's entity glyphs: the theme's shape for each role, drawn by the shared factory.
@MainActor
struct RidgelineGlyphs {
    let factory: GlowShapeFactory
    let theme: any Theme

    /// The glyph for an entity role, optionally recoloured in one colour.
    func glyph(for role: EntityRole, tint: RGB? = nil, pointsPerUnit: CGFloat) -> GlowShapeFactory.Glyph {
        var shape = theme.shape(for: role)
        if let tint { shape = shape.recoloured(tint) }
        return factory.glyph(key: "\(role)|\(tint.map { "\($0)" } ?? "-")", shape: shape, pointsPerUnit: pointsPerUnit)
    }
}
