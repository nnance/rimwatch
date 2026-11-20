import GameCore
import SpriteKit
import UIKit

/// The readouts in the top band, beside the scanner. Three compact rows on the left (score and
/// wave; lives and Shockwave charges; colonists alive and the carry multiplier) and three slim
/// meters on the right (lance heat, shield, Blink). Values come from a `HUDReadout`; the node
/// never touches the simulation. Every sprite is made at layout time and only updated per frame.
@MainActor
final class HUDNode: SKNode {
    enum Flash {
        case lives, shield, heat, shockwaves, colonists, score
    }

    private let theme: any Theme
    private let factory: GlowShapeFactory
    private var rect: CGRect = .zero
    private var built = false

    private var scoreRow: CharRow?
    private var waveRow: CharRow?
    private var survivorRow: CharRow?
    private var carryRow: CharRow?
    private var multiplierRow: CharRow?
    private let waveLabel = SKSpriteNode()
    private let colonistIcon = SKSpriteNode()
    private var lifeIcons: [SKSpriteNode] = []
    private var shockPips: [SKSpriteNode] = []

    private struct Meter {
        let label = SKSpriteNode()
        let alertLabel = SKSpriteNode()
        let frame = SKSpriteNode()
        let fill = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
        var width: CGFloat = 0
    }
    private var heat = Meter()
    private var shield = Meter()
    private var blink = Meter()

    private var flashes: [Flash: TimeInterval] = [:]
    private var last: HUDReadout?
    private var maxLives = 5

    init(theme: any Theme, factory: GlowShapeFactory) {
        self.theme = theme
        self.factory = factory
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    private var hud: RGB { theme.palette.hud }
    private var warning: RGB { theme.palette.warning }
    private var highlight: RGB { theme.palette.falling }

    /// Makes something pulse briefly (an extra life, a broken shield).
    func flash(_ what: Flash, at time: TimeInterval) {
        flashes[what] = time
    }

    /// Builds every sprite for a rectangle of the scene. Called on layout changes only.
    func layout(in rect: CGRect, maxLives: Int, maxShockwaves: Int) {
        guard rect.width > 40, rect.height > 16 else { return }
        guard rect != self.rect || !built || maxLives != self.maxLives || shockPips.count != maxShockwaves
        else { return }
        self.rect = rect
        self.maxLives = maxLives
        built = true
        removeAllChildren()
        lifeIcons = []
        shockPips = []
        last = nil
        position = rect.origin

        let rowH = rect.height / 3
        let small = max(8, min(rowH * 0.62, 15))
        let leftW = rect.width * 0.56
        let gap = max(4, rowH * 0.3)
        func rowY(_ row: Int) -> CGFloat { rect.height - rowH * (CGFloat(row) + 0.5) }

        // Row 1: score on the left, wave on the right of the left column.
        let waveStyle = GlowText.Style.item(small)
        let (waveTex, waveSize) = GlowText.texture("WAVE", style: waveStyle, color: hud.scaled(0.8))
        waveLabel.texture = waveTex
        waveLabel.size = waveSize
        waveLabel.blendMode = .add
        let waveDigits = CharRow(capacity: 3, style: waveStyle, color: hud.lightened(0.3), alignment: .right)
        let waveDigitsW = waveDigits.measure("88")
        waveDigits.position = CGPoint(x: leftW, y: rowY(0))
        let waveLabelW = GlowText.width(of: "WAVE", style: waveStyle)
        waveLabel.position = CGPoint(x: leftW - waveDigitsW - small * 0.35 - waveLabelW / 2, y: rowY(0))
        addChild(waveLabel)
        addChild(waveDigits)
        waveRow = waveDigits

        let scoreRoom = leftW - waveDigitsW - waveLabelW - small
        // Score digits are about 0.62 em wide; size the score so nine characters fit.
        let scoreSize = max(9, min(rowH * 1.02, scoreRoom / (9 * 0.66)))
        let score = CharRow(capacity: 11, style: GlowText.Style(size: scoreSize, weight: .semibold, tracking: 0.04),
                            color: hud.lightened(0.35))
        score.position = CGPoint(x: 0, y: rowY(0))
        addChild(score)
        scoreRow = score

        // Row 2: lives as small ships, then Shockwave charges as rings. The ships lie level, so
        // each takes a slot and a bit to stay clear of the next.
        let lifeSlot: CGFloat = 1.3
        let slots = CGFloat(maxLives) * lifeSlot + CGFloat(maxShockwaves) + 1.5
        let icon: CGFloat = min(rowH * 0.95, leftW / slots)
        let shipShape = theme.icon(for: .player)
        let shipSpan = (shipShape.bounds.max.x - shipShape.bounds.min.x) * shipShape.scale
        for index in 0..<maxLives {
            let sprite = SKSpriteNode()
            factory.apply(iconGlyph("hud-life", shipShape, factor: Double(icon * 0.95) / shipSpan), to: sprite)
            // Level and facing right, as the ship flies: it is drawn side-on, so standing it on
            // its tail would read as a rocket.
            sprite.position = CGPoint(x: icon * lifeSlot * (CGFloat(index) + 0.5), y: rowY(1))
            addChild(sprite)
            lifeIcons.append(sprite)
        }
        let pipShape = ShapeDescription(scale: 1, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 20), color: theme.palette.shield),
            ShapeStroke(ShapeKit.arc(radius: 0.4, segments: 12), color: theme.palette.shield),
        ])
        let pipStart = icon * (CGFloat(maxLives) * lifeSlot + 0.5)
        for index in 0..<maxShockwaves {
            let sprite = SKSpriteNode()
            factory.apply(iconGlyph("hud-shock", pipShape, factor: Double(icon * 0.34)), to: sprite)
            sprite.position = CGPoint(x: pipStart + icon * (CGFloat(index) + 0.5), y: rowY(1))
            addChild(sprite)
            shockPips.append(sprite)
        }

        // Row 3: colonists still alive, then how many are aboard and their multiplier.
        let colonistShape = theme.shape(for: .colonist)
        let colonistH = (colonistShape.bounds.max.y - colonistShape.bounds.min.y) * colonistShape.scale
        factory.apply(iconGlyph("hud-colonist", colonistShape, factor: Double(rowH * 0.8) / colonistH),
                      to: colonistIcon)
        colonistIcon.position = CGPoint(x: icon * 0.5, y: rowY(2) - rowH * 0.4)
        colonistIcon.blendMode = .alpha
        addChild(colonistIcon)
        let survivors = CharRow(capacity: 3, style: .item(small), color: hud.lightened(0.3))
        survivors.position = CGPoint(x: icon * 1.1, y: rowY(2))
        addChild(survivors)
        survivorRow = survivors
        let carry = CharRow(capacity: 9, style: .item(small), color: highlight)
        carry.position = CGPoint(x: icon * 1.1 + survivors.measure("888") + gap, y: rowY(2))
        addChild(carry)
        carryRow = carry
        let multiplier = CharRow(capacity: 4, style: GlowText.Style(size: small * 1.15, weight: .bold, tracking: 0.04),
                                 color: highlight)
        multiplier.position = CGPoint(x: carry.position.x + carry.measure("ABOARD 8") + gap * 0.6, y: rowY(2))
        addChild(multiplier)
        multiplierRow = multiplier

        // Right column: three meters.
        let meterX = leftW + gap * 2
        let labelStyle = GlowText.Style.body(max(8, small * 0.85))
        let labelW = ["HEAT", "SHIELD", "BLINK"].map { GlowText.width(of: $0, style: labelStyle) }.max() ?? 30
        let barX = meterX + labelW + gap
        let barW = max(rect.width - barX - 2, 12)
        let barH = max(3, rowH * 0.32)
        func makeMeter(_ title: String, alert: String?, color: RGB, row: Int) -> Meter {
            var meter = Meter()
            let y = rowY(row)
            let (tex, size) = GlowText.texture(title, style: labelStyle, color: color.scaled(0.85))
            meter.label.texture = tex
            meter.label.size = size
            meter.label.blendMode = .add
            meter.label.anchorPoint = CGPoint(x: 0, y: 0.5)
            meter.label.position = CGPoint(x: meterX - GlowText.padding, y: y)
            addChild(meter.label)
            if let alert {
                let alertColor = row == 0 ? warning : highlight
                let (alertTex, alertSize) = GlowText.texture(alert, style: labelStyle, color: alertColor)
                meter.alertLabel.texture = alertTex
                meter.alertLabel.size = alertSize
                meter.alertLabel.blendMode = .add
                meter.alertLabel.anchorPoint = CGPoint(x: 0, y: 0.5)
                meter.alertLabel.position = meter.label.position
                meter.alertLabel.isHidden = true
                addChild(meter.alertLabel)
            }
            let frame = GlowFrame.sprite(size: CGSize(width: barW, height: barH + 3), color: color.scaled(0.6), cut: 2)
            frame.position = CGPoint(x: barX + barW / 2, y: y)
            frame.alpha = 0.55
            addChild(frame)
            meter.fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            meter.fill.size = CGSize(width: barW - 3, height: barH - 1)
            meter.fill.position = CGPoint(x: barX + 1.5, y: y)
            meter.fill.color = color.uiColor()
            meter.fill.blendMode = .add
            addChild(meter.fill)
            meter.width = barW - 3
            return meter
        }
        heat = makeMeter("HEAT", alert: "HOT", color: hud, row: 0)
        shield = makeMeter("SHIELD", alert: "READY", color: theme.palette.shield, row: 1)
        blink = makeMeter("BLINK", alert: nil, color: theme.palette.controls, row: 2)

    }

    /// A shape drawn at `factor` times its own size, in points (glyphs at 1 point per unit are
    /// sized in points, which is what the HUD lives in).
    private func iconGlyph(_ key: String, _ shape: ShapeDescription, factor: Double) -> GlowShapeFactory.Glyph {
        let scaled = ShapeDescription(scale: shape.scale * factor, strokes: shape.strokes)
        return factory.glyph(key: "\(key)-\(Int(factor * 1000))", shape: scaled, pointsPerUnit: 1)
    }

    /// Updates every readout. Cheap when nothing changed.
    func update(_ r: HUDReadout, time: TimeInterval) {
        guard built else { return }
        func pulse(_ what: Flash, duration: TimeInterval = 1.2) -> CGFloat {
            guard let at = flashes[what] else { return 0 }
            let t = time - at
            guard t < duration else {
                flashes[what] = nil
                return 0
            }
            return CGFloat(0.5 + 0.5 * cos(t * 18)) * CGFloat(1 - t / duration)
        }
        let blinkOn = sin(time * 14) > 0

        scoreRow?.set(groupedDigits(r.score))
        scoreRow?.alpha = 0.9 + 0.1 * pulse(.score)
        waveRow?.set("\(r.wave)")

        let livesPulse = pulse(.lives)
        for (index, sprite) in lifeIcons.enumerated() {
            sprite.isHidden = index >= r.lives
            sprite.alpha = 0.85
            sprite.setScale(1 + 0.35 * livesPulse)
        }
        let shockPulse = pulse(.shockwaves)
        for (index, sprite) in shockPips.enumerated() {
            sprite.alpha = index < r.shockwaves ? 0.95 : 0.15
            sprite.setScale(1 + 0.3 * shockPulse)
        }

        // Colonists: red during a Blackout (none left), dim when few remain.
        let survivorColor = r.survivors == 0 ? warning : hud.lightened(0.3)
        survivorRow?.set("\(r.survivors)", color: survivorColor)
        colonistIcon.alpha = r.survivors == 0 ? (blinkOn ? 0.8 : 0.25) : 0.9
        survivorRow?.alpha = r.survivors == 0 ? (blinkOn ? 1 : 0.4) : 1
        if r.carried > 0 {
            carryRow?.set("ABOARD \(r.carried)")
            carryRow?.isHidden = false
            multiplierRow?.isHidden = r.multiplier < 2
            multiplierRow?.set("×\(r.multiplier)")
            multiplierRow?.setScale(1 + 0.08 * CGFloat(sin(time * 6)))
        } else {
            carryRow?.isHidden = true
            multiplierRow?.isHidden = true
        }

        // Heat: the bar warms toward the warning colour; overheated, it flashes red with "HOT".
        let heatColor = r.isOverheated ? warning : mix(hud, warning, max(0, (r.heat - 0.55) / 0.45))
        heat.fill.color = heatColor.uiColor()
        heat.fill.xScale = CGFloat(max(r.heat, 0.001))
        heat.fill.alpha = r.isOverheated ? (blinkOn ? 1 : 0.35) : 0.85
        heat.label.isHidden = r.isOverheated
        heat.alertLabel.isHidden = !r.isOverheated
        heat.alertLabel.alpha = blinkOn ? 1 : 0.5

        let shieldPulse = pulse(.shield)
        let full = r.shield >= 1
        shield.fill.xScale = CGFloat(max(r.shield, 0.001))
        shield.fill.alpha = full ? 0.75 + 0.25 * CGFloat(sin(time * 4)) : 0.55
        shield.fill.color = (shieldPulse > 0 && !full ? warning : theme.palette.shield).uiColor()
        shield.label.isHidden = full
        shield.alertLabel.isHidden = !full
        shield.label.alpha = 0.85 + 0.15 * shieldPulse

        blink.fill.xScale = CGFloat(max(r.blinkReadiness, 0.001))
        blink.fill.alpha = r.blinkReadiness >= 1 ? 0.9 : 0.35
        blink.label.alpha = r.blinkReadiness >= 1 ? 1 : 0.5
        last = r
    }

    private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}
