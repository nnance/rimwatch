import GameCore
import RiftwingCore
import SpriteKit
import UIKit

/// The thin strip above the gallery. Left of the crease: the score and the wave. Right of it:
/// lives as small rigs and the colonists saved this run; the shell's pause button sits at the
/// strip's right end. Every sprite is made at layout time and only updated per frame.
@MainActor
final class RiftwingHUD: SKNode {
    enum Flash {
        case lives, saved
    }

    struct Readout: Equatable {
        var score = 0
        var wave = 0
        var lives = 0
        var saved = 0
        var lampsOut = false
    }

    private let theme: RiftCaves
    private let factory: GlowShapeFactory
    private struct Built: Equatable {
        var strip: CGRect
        var left: ClosedRange<CGFloat>
        var right: ClosedRange<CGFloat>
        var maxLives: Int
    }
    private var built: Built?
    private var scoreRow: CharRow?
    private var waveRow: CharRow?
    private var savedRow: CharRow?
    private let waveLabel = SKSpriteNode()
    private let savedIcon = SKSpriteNode()
    private var lifeIcons: [SKSpriteNode] = []
    private var flashes: [Flash: TimeInterval] = [:]
    private var last: Readout?

    init(theme: RiftCaves, factory: GlowShapeFactory) {
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
    func layout(strip: CGRect, left: ClosedRange<CGFloat>, right: ClosedRange<CGFloat>, maxLives: Int) {
        guard strip.width > 40, strip.height > 10 else { return }
        let wanted = Built(strip: strip, left: left, right: right, maxLives: maxLives)
        guard wanted != built else { return }
        built = wanted
        removeAllChildren()
        lifeIcons = []
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

        // Right: lives as little rigs, then the colonists saved.
        let slots = CGFloat(maxLives) * 1.25 + 4
        let room: CGFloat = right.upperBound - right.lowerBound
        let icon: CGFloat = min(strip.height * 0.8, room / slots)
        var x = right.lowerBound + icon * 0.6
        let rig = theme.shape(for: .life)
        let rigSpan = (rig.bounds.max.x - rig.bounds.min.x) * rig.scale
        for _ in 0..<maxLives {
            let sprite = SKSpriteNode()
            RiftwingSprites.dress(sprite, with: iconGlyph("hud-life", rig, factor: Double(icon * 1.05) / rigSpan), factory: factory)
            sprite.position = CGPoint(x: x, y: y - icon * 0.05)
            addChild(sprite)
            lifeIcons.append(sprite)
            x += icon * 1.25
        }
        x += icon * 0.4
        let pod = theme.shape(for: .colonist)
        let podSpan = (pod.bounds.max.y - pod.bounds.min.y) * pod.scale
        RiftwingSprites.dress(savedIcon, with: iconGlyph("hud-saved", pod, factor: Double(icon * 0.75) / podSpan), factory: factory)
        savedIcon.position = CGPoint(x: x, y: y)
        addChild(savedIcon)
        let count = CharRow(capacity: 4, style: .item(text), color: theme.color(of: .pod).lightened(0.2))
        count.position = CGPoint(x: x + icon * 0.5, y: y)
        addChild(count)
        savedRow = count
    }

    private func iconGlyph(_ key: String, _ shape: ShapeDescription, factor: Double) -> GlowShapeFactory.Glyph {
        factory.glyph(key: "riftwing-\(key)-\(Int(factor * 1000))",
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
        if last?.score != r.score { scoreRow?.set(groupedDigits(r.score)) }
        if last?.wave != r.wave { waveRow?.set("\(r.wave)") }
        let lives = pulse(.lives)
        for (index, sprite) in lifeIcons.enumerated() {
            sprite.isHidden = index >= r.lives
            sprite.setScale(1 + 0.35 * lives)
        }
        if last?.saved != r.saved { savedRow?.set("\(r.saved)") }
        savedIcon.setScale(1 + 0.35 * pulse(.saved))
        // With the lamps out the colonist count dims: free one to bring them back.
        savedIcon.alpha = r.lampsOut ? 0.4 + 0.3 * CGFloat(abs(sin(time * 3))) : 0.95
        last = r
    }
}
