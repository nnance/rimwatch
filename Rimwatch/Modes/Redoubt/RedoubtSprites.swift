import SpriteKit

/// The one way Redoubt gives a sprite a texture. `GlowShapeFactory.apply` sets the sprite's
/// `size`, and SpriteKit's `size` includes the sprite's scale: applied to a sprite still carrying
/// a scale (a hit pulse, a wind-up, a breathing colonist, the last occupant of a pooled sprite),
/// the texture would be drawn too big or too small from then on. Dressing resets the scale to 1
/// first, so the result never depends on it; the caller sets whatever scale it wants afterwards.
/// Every texture in `Modes/Redoubt/` goes through here; nothing calls `factory.apply` directly.
@MainActor
enum RedoubtSprites {
    static func dress(_ sprite: SKSpriteNode, with glyph: GlowShapeFactory.Glyph, factory: GlowShapeFactory) {
        sprite.xScale = 1
        sprite.yScale = 1
        factory.apply(glyph, to: sprite)
    }
}
