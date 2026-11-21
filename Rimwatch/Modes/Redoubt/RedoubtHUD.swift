import GameCore
import RedoubtCore
import SpriteKit
import UIKit

/// The thin strip above the arena. Left of the crease: the score and the wave. Right of it: lives
/// as small orbs, Shockwave charges, and the colonists still to save; the shell's pause button
/// sits at the strip's right end. Every sprite is made at layout time and only updated per frame.
@MainActor
final class RedoubtHUD: SKNode {
    enum Flash {
        case lives, charges, colonists
    }

    struct Readout: Equatable {
        var score = 0
        var wave = 0
        var lives = 0
        var charges = 0
        var colonists = 0
        /// Show the colonist count as a warning (see `RedoubtRun.colonistAlarm` in RedoubtCore).
        var colonistAlarm = false
    }

    private let theme: CalderDome
    private let factory: GlowShapeFactory
    /// What the sprites were last built for. Every input to the layout is in it, crease edges
    /// included, so a crease band that arrives after the first layout rebuilds the strip.
    private struct Built: Equatable {
        var strip: CGRect
        var left: ClosedRange<CGFloat>
        var right: ClosedRange<CGFloat>
        var maxLives: Int
        var maxCharges: Int
    }
    private var built: Built?
    private var scoreRow: CharRow?
    private var waveRow: CharRow?
    private var colonistRow: CharRow?
    private let waveLabel = SKSpriteNode()
    private let colonistIcon = SKSpriteNode()
    private var lifeIcons: [SKSpriteNode] = []
    private var chargePips: [SKSpriteNode] = []
    private var flashes: [Flash: TimeInterval] = [:]
    private var last: Readout?

    init(theme: CalderDome, factory: GlowShapeFactory) {
        self.theme = theme
        self.factory = factory
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func flash(_ what: Flash, at time: TimeInterval) {
        flashes[what] = time
    }

    /// `strip` is the HUD's band; `left` and `right` are the x ranges either side of the crease
    /// (the right one ends before the pause button).
    func layout(strip: CGRect, left: ClosedRange<CGFloat>, right: ClosedRange<CGFloat>, maxLives: Int, maxCharges: Int) {
        guard strip.width > 40, strip.height > 10 else { return }
        let wanted = Built(strip: strip, left: left, right: right, maxLives: maxLives, maxCharges: maxCharges)
        guard wanted != built else { return }
        built = wanted
        removeAllChildren()
        lifeIcons = []
        chargePips = []
        last = nil
        let hud = theme.palette.hud
        let y = strip.midY
        let text = max(9, strip.height * 0.5)

        // Left: score, then WAVE n right-aligned at the end of the left half.
        let score = CharRow(capacity: 11, style: GlowText.Style(size: text * 1.15, weight: .semibold, tracking: 0.04),
                            color: hud.lightened(0.35))
        score.position = CGPoint(x: left.lowerBound, y: y)
        addChild(score)
        scoreRow = score
        let waveStyle = GlowText.Style.item(text * 0.9)
        let wave = CharRow(capacity: 3, style: waveStyle, color: hud.lightened(0.3), alignment: .right)
        wave.position = CGPoint(x: left.upperBound, y: y)
        addChild(wave)
        waveRow = wave
        let (waveTex, waveSize) = GlowText.texture("WAVE", style: waveStyle, color: hud.scaled(0.8))
        waveLabel.texture = waveTex
        waveLabel.size = waveSize
        waveLabel.blendMode = .add
        let waveLabelW = GlowText.width(of: "WAVE", style: waveStyle)
        waveLabel.position = CGPoint(x: left.upperBound - wave.measure("88") - text * 0.35 - waveLabelW / 2, y: y)
        addChild(waveLabel)

        // Right: lives, charges, colonists.
        let slots = CGFloat(maxLives + maxCharges) + 4.5
        let room: CGFloat = right.upperBound - right.lowerBound
        let icon: CGFloat = min(strip.height * 0.62, room / slots)
        var x = right.lowerBound + icon * 0.5
        let orb = theme.shape(for: .life)
        let orbSpan = (orb.bounds.max.x - orb.bounds.min.x) * orb.scale
        for _ in 0..<maxLives {
            let sprite = SKSpriteNode()
            RedoubtSprites.dress(sprite, with: iconGlyph("hud-life", orb, factor: Double(icon * 0.92) / orbSpan), factory: factory)
            sprite.zRotation = .pi / 2
            sprite.position = CGPoint(x: x, y: y - icon * 0.08)
            addChild(sprite)
            lifeIcons.append(sprite)
            x += icon
        }
        x += icon * 0.4
        let charge = theme.shape(for: .charge)
        for _ in 0..<maxCharges {
            let sprite = SKSpriteNode()
            RedoubtSprites.dress(sprite, with: iconGlyph("hud-charge", charge, factor: Double(icon * 0.36)), factory: factory)
            sprite.position = CGPoint(x: x, y: y)
            addChild(sprite)
            chargePips.append(sprite)
            x += icon * 0.95
        }
        x += icon * 0.5
        let colonist = theme.shape(for: .colonist)
        let colonistSpan = (colonist.bounds.max.x - colonist.bounds.min.x) * colonist.scale
        RedoubtSprites.dress(colonistIcon, with: iconGlyph("hud-colonist", colonist, factor: Double(icon * 0.85) / colonistSpan), factory: factory)
        colonistIcon.position = CGPoint(x: x, y: y)
        addChild(colonistIcon)
        let count = CharRow(capacity: 3, style: .item(text), color: theme.color(of: .colonist).lightened(0.2))
        count.position = CGPoint(x: x + icon * 0.6, y: y)
        addChild(count)
        colonistRow = count
    }

    private func iconGlyph(_ key: String, _ shape: ShapeDescription, factor: Double) -> GlowShapeFactory.Glyph {
        factory.glyph(key: "redoubt-\(key)-\(Int(factor * 1000))",
                      shape: ShapeDescription(scale: shape.scale * factor, strokes: shape.strokes), pointsPerUnit: 1)
    }

    func update(_ r: Readout, time: TimeInterval) {
        guard built != nil else { return }
        func pulse(_ what: Flash) -> CGFloat {
            guard let at = flashes[what] else { return 0 }
            let t = time - at
            guard t < 1.2 else {
                flashes[what] = nil
                return 0
            }
            return CGFloat(0.5 + 0.5 * cos(t * 18)) * CGFloat(1 - t / 1.2)
        }
        let blinkOn = sin(time * 10) > 0
        if last?.score != r.score { scoreRow?.set(groupedDigits(r.score)) }
        if last?.wave != r.wave { waveRow?.set("\(r.wave)") }
        let lives = pulse(.lives)
        for (index, sprite) in lifeIcons.enumerated() {
            sprite.isHidden = index >= r.lives
            sprite.setScale(1 + 0.35 * lives)
        }
        let charges = pulse(.charges)
        for (index, sprite) in chargePips.enumerated() {
            sprite.alpha = index < r.charges ? 0.95 : 0.15
            sprite.setScale(1 + 0.35 * charges)
        }
        // Colonists: red and blinking only in danger (the power is out, or about to go).
        let alarm = r.colonistAlarm
        colonistRow?.set("\(r.colonists)",
                         color: alarm ? theme.palette.warning : theme.color(of: .colonist).lightened(0.2))
        colonistRow?.alpha = alarm ? (blinkOn ? 1 : 0.4) : 1
        colonistIcon.alpha = alarm ? (blinkOn ? 0.8 : 0.25) : 0.9
        colonistIcon.setScale(1 + 0.3 * pulse(.colonists))
        last = r
    }
}
