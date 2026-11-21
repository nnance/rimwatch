import GameCore
import SpriteKit

/// A line of glow text built from one cached texture per character, for values that change while
/// playing (score, counters). Changing the text reassigns textures to a fixed pool of sprites, so
/// nothing is rendered or allocated per frame once each character has been seen.
@MainActor
final class CharRow: SKNode {
    enum Alignment {
        case left, center, right
    }

    private var sprites: [SKSpriteNode] = []
    private let style: GlowText.Style
    private var text = ""
    private var color: RGB
    private var advances: [Character: CGFloat] = [:]
    var alignment: Alignment {
        didSet { if alignment != oldValue { place() } }
    }

    /// Width of the current text, in points.
    private(set) var width: CGFloat = 0

    init(capacity: Int, style: GlowText.Style, color: RGB, alignment: Alignment = .left) {
        self.style = style
        self.color = color
        self.alignment = alignment
        super.init()
        for _ in 0..<capacity {
            let sprite = SKSpriteNode()
            sprite.blendMode = .add
            sprite.isHidden = true
            addChild(sprite)
            sprites.append(sprite)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Shows `text` (cut to the capacity). Does nothing if neither text nor colour changed.
    func set(_ text: String, color: RGB? = nil) {
        let color = color ?? self.color
        guard text != self.text || color != self.color else { return }
        self.text = text
        self.color = color
        place()
    }

    /// The width `text` would take in this row's style.
    func measure(_ text: String) -> CGFloat {
        text.reduce(0) { $0 + advance(of: $1) }
    }

    private func advance(of ch: Character) -> CGFloat {
        if let known = advances[ch] { return known }
        let measured = GlowText.width(of: String(ch), style: style) + style.size * style.tracking
        advances[ch] = measured
        return measured
    }

    private func place() {
        let chars = Array(text.prefix(sprites.count))
        width = chars.reduce(0) { $0 + advance(of: $1) }
        var x: CGFloat = switch alignment {
        case .left: 0
        case .center: -width / 2
        case .right: -width
        }
        for (index, sprite) in sprites.enumerated() {
            guard index < chars.count, chars[index] != " " else {
                sprite.isHidden = true
                if index < chars.count { x += advance(of: chars[index]) }
                continue
            }
            let ch = chars[index]
            let (texture, size) = GlowText.texture(String(ch), style: style, color: color)
            sprite.texture = texture
            sprite.size = size
            sprite.isHidden = false
            let a = advance(of: ch)
            sprite.position = CGPoint(x: x + a / 2, y: 0)
            x += a
        }
    }
}
