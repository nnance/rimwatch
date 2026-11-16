import GameCore
import SpriteKit
import UIKit

/// Text drawn in the game's neon style and cached as textures: a soft coloured halo with a bright
/// line on top. Headings use outlined letters, so they read as glowing tubes like the shapes.
@MainActor
enum GlowText {
    struct Style: Hashable {
        var size: CGFloat
        var weight: UIFont.Weight = .regular
        /// Outlined letters instead of filled ones.
        var outline = false
        /// Extra letter spacing, as a fraction of the size.
        var tracking: CGFloat = 0.04

        static func heading(_ size: CGFloat) -> Style { Style(size: size, weight: .bold, outline: true, tracking: 0.16) }
        static func item(_ size: CGFloat) -> Style { Style(size: size, weight: .medium, tracking: 0.06) }
        static func body(_ size: CGFloat) -> Style { Style(size: size, weight: .regular, tracking: 0.03) }
    }

    private static var cache: [String: (SKTexture, CGSize)] = [:]
    static let padding: CGFloat = 10

    /// A sprite showing `text`, centred on its position.
    static func sprite(_ text: String, style: Style, color: RGB) -> SKSpriteNode {
        let (texture, size) = render(text, style: style, color: color)
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.blendMode = .add
        return sprite
    }

    /// The width the text will take, without padding.
    static func width(of text: String, style: Style) -> CGFloat {
        NSAttributedString(string: text, attributes: attributes(style, color: RGB(1, 1, 1), pass: 0))
            .size().width
    }

    private static func font(_ style: Style) -> UIFont {
        // Outlined headings use Avenir Next: unlike the system font, its letters have no
        // overlapping contours, so the outline shows no stray inner lines.
        if style.outline, let avenir = UIFont(name: "AvenirNext-DemiBold", size: style.size) { return avenir }
        let base = UIFont.systemFont(ofSize: style.size, weight: style.weight)
        // Tabular digits, so scores line up.
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]],
        ])
        return UIFont(descriptor: descriptor, size: style.size)
    }

    private static func attributes(_ style: Style, color: RGB, pass: Int) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(style),
            .kern: style.size * style.tracking,
        ]
        if style.outline {
            attrs[.strokeColor] = pass == 0 ? color.uiColor() : color.lightened(0.6).uiColor()
            // Positive stroke width: outline only, as a percentage of the font size.
            attrs[.strokeWidth] = pass == 0 ? 4.0 : 1.6
        } else {
            attrs[.foregroundColor] = pass == 0 ? color.uiColor() : color.lightened(0.55).uiColor()
        }
        return attrs
    }

    /// The cached texture for `text` and its size in points (padding included).
    static func texture(_ text: String, style: Style, color: RGB) -> (texture: SKTexture, size: CGSize) {
        let (texture, size) = render(text, style: style, color: color)
        return (texture, size)
    }

    private static func render(_ text: String, style: Style, color: RGB) -> (SKTexture, CGSize) {
        let key = "\(text)|\(style.size)|\(style.weight.rawValue)|\(style.outline)|\(style.tracking)|\(color)"
        if let hit = cache[key] { return hit }
        if cache.count > 400 { cache.removeAll() }

        let measured = NSAttributedString(string: text, attributes: attributes(style, color: color, pass: 0)).size()
        let size = CGSize(width: ceil(measured.width) + 2 * padding, height: ceil(measured.height) + 2 * padding)
        let image = GlowShapeFactory.image(size: size, scale: 3) { context in
            let origin = CGPoint(x: padding, y: padding)
            // Round joins, so outlined letters have no miter spikes at sharp corners.
            context.setLineJoin(.round)
            context.setMiterLimit(1)
            context.setShadow(offset: .zero, blur: style.size * 0.35, color: color.cgColor(alpha: 0.95))
            NSAttributedString(string: text, attributes: attributes(style, color: color, pass: 0)).draw(at: origin)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            NSAttributedString(string: text, attributes: attributes(style, color: color, pass: 1)).draw(at: origin)
        }
        let texture = SKTexture(image: image)
        cache[key] = (texture, size)
        return (texture, size)
    }
}

/// Glowing outlines for menu buttons and panels: a rectangle with cut corners.
@MainActor
enum GlowFrame {
    private static var cache: [String: SKTexture] = [:]

    static func sprite(size: CGSize, color: RGB, cut: CGFloat = 10) -> SKSpriteNode {
        let pad = GlowShapeFactory.Style.padding
        let key = "\(Int(size.width))x\(Int(size.height))|\(cut)|\(color)"
        let texture = cache[key] ?? {
            let full = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
            let image = GlowShapeFactory.image(size: full, scale: 2) { context in
                let r = CGRect(x: pad, y: pad, width: size.width, height: size.height)
                let c = min(cut, r.height / 2, r.width / 2)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: r.minX + c, y: r.minY))
                path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
                path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
                path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
                path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
                path.closeSubpath()
                GlowShapeFactory.strokeGlow(path, color: color, strength: 0.8, in: context)
            }
            let made = SKTexture(image: image)
            if cache.count > 200 { cache.removeAll() }
            cache[key] = made
            return made
        }()
        let sprite = SKSpriteNode(texture: texture,
                                  size: CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad))
        sprite.blendMode = .add
        return sprite
    }
}
