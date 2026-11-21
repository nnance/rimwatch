import GameCore
import SpriteKit
import UIKit

/// Text feedback in screen space, so it stays a readable size whatever the arena's scale:
/// - popups rise from a point on the floor ("+1,500", "LOST") and fade;
/// - a banner announces a wave, its clear or the power cut: a compact line or two along the top of
///   the floor, left of the crease, on a dark band, for about a second, so the floor stays
///   readable while the wave opens;
/// - a notice gives a short status (extra life, charge earned) along the top right of it.
/// Nothing reaches up into the HUD strip above the floor.
/// Each is a short-lived node made when its event happens (a few a second at most), never per
/// frame. The Ridgeline version is tied to its wraparound camera, so Redoubt has its own.
@MainActor
final class RedoubtCallouts: SKNode {
    private struct Popup {
        let node: SKNode
        let at: CGPoint
        let born: TimeInterval
    }

    private var popups: [Popup] = []
    private var banner: SKNode?
    private var notice: SKNode?
    private let flashSprite = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
    private var playfield: CGRect = .zero
    private var bannerCenter: CGPoint = .zero
    private var noticeCenter: CGPoint = .zero
    private var bannerWidth: CGFloat = 200
    private var noticeWidth: CGFloat = 200
    private(set) var textSize: CGFloat = 13
    private var clock: TimeInterval = 0
    private let subtitleColor: RGB

    init(subtitleColor: RGB) {
        self.subtitleColor = subtitleColor
        super.init()
        flashSprite.anchorPoint = .zero
        flashSprite.blendMode = .add
        flashSprite.alpha = 0
        flashSprite.zPosition = -1
        addChild(flashSprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// `playfield` is the arena on screen; `keepClear` the crease band, if any.
    func layout(size: CGSize, playfield: CGRect, keepClear: ClosedRange<CGFloat>?) {
        self.playfield = playfield
        flashSprite.position = playfield.origin
        flashSprite.size = playfield.size
        textSize = min(max(min(size.width, size.height) * 0.032, 11), 17)
        let margin: CGFloat = 12
        if let keepClear, size.width > size.height {
            let left = CGRect(x: playfield.minX + margin, y: playfield.minY,
                              width: keepClear.lowerBound - margin - playfield.minX - margin, height: playfield.height)
            let right = CGRect(x: keepClear.upperBound + margin, y: playfield.minY,
                               width: playfield.maxX - keepClear.upperBound - 2 * margin, height: playfield.height)
            bannerCenter = CGPoint(x: left.midX, y: playfield.maxY - textSize * 1.5)
            bannerWidth = left.width
            noticeCenter = CGPoint(x: right.midX, y: playfield.maxY - textSize * 1.3)
            noticeWidth = right.width
        } else {
            bannerCenter = CGPoint(x: playfield.midX, y: playfield.maxY - textSize * 1.5)
            bannerWidth = playfield.width - 2 * margin
            noticeCenter = CGPoint(x: playfield.midX, y: bannerCenter.y - textSize * 3.2)
            noticeWidth = bannerWidth
        }
    }

    func removeAll() {
        for popup in popups { popup.node.removeFromParent() }
        popups.removeAll()
        banner?.removeFromParent()
        banner = nil
        notice?.removeFromParent()
        notice = nil
        flashSprite.removeAllActions()
        flashSprite.alpha = 0
    }

    /// Text that rises from a screen point and fades, stacked above any popup still showing close
    /// by, and kept inside the arena.
    func popup(_ text: String, at point: CGPoint, color: RGB, scale: CGFloat = 1, life: TimeInterval = 0.9) {
        popups.removeAll { $0.node.parent == nil }
        let sprite = GlowText.sprite(text, style: .item(textSize * scale), color: color)
        let half = (sprite.size.width - 2 * GlowText.padding) / 2
        // A dark silhouette behind the text, so it reads over the glow of the crowd.
        let backing = SKSpriteNode(texture: sprite.texture, size: sprite.size)
        backing.color = .black
        backing.colorBlendFactor = 1
        backing.blendMode = .alpha
        backing.alpha = 0.9
        backing.setScale(1.08)
        backing.zPosition = -0.1
        sprite.addChild(backing)
        let slot = textSize * scale * 1.4
        // Highest start that still ends (after rising) with the text inside the floor.
        let top = playfield.maxY - textSize * 1.6 - textSize * scale * 0.8 - 4
        var y = min(max(point.y + textSize, playfield.minY + textSize), top)
        let x = min(max(point.x, playfield.minX + half + 4), playfield.maxX - half - 4)
        // Stacked above a popup still showing nearby, or below it when there is no room above.
        let step = y + slot * 6 > top ? -slot : slot
        for _ in 0..<6 {
            let clash = popups.contains { clock - $0.born < 0.6 && abs($0.at.x - x) < half + 40 && abs($0.at.y - y) < slot }
            if !clash { break }
            y += step
        }
        y = min(max(y, playfield.minY + textSize), top)
        // Kept out from under a banner or notice showing along the top: moved down below it.
        for shown in [banner, notice] {
            guard let shown, shown.parent != nil else { continue }
            let frame = shown.calculateAccumulatedFrame().insetBy(dx: -half, dy: -textSize * scale)
            if frame.contains(CGPoint(x: x, y: y + textSize * 0.8)) || frame.contains(CGPoint(x: x, y: y)) {
                y = frame.minY - textSize * 1.6 - textSize * scale * 0.6
            }
        }
        let container = SKNode()
        container.position = CGPoint(x: x, y: y)
        container.addChild(sprite)
        let rise = SKAction.moveBy(x: 0, y: textSize * 1.6, duration: life)
        rise.timingMode = .easeOut
        sprite.setScale(0.6)
        sprite.run(.group([rise, .sequence([.scale(to: 1.05, duration: 0.12), .scale(to: 1, duration: 0.1)]),
                           .sequence([.wait(forDuration: life * 0.55), .fadeOut(withDuration: life * 0.45)])]))
        container.run(.sequence([.wait(forDuration: life + 0.05), .removeFromParent()]))
        addChild(container)
        popups.append(Popup(node: container, at: CGPoint(x: x, y: y), born: clock))
    }

    /// A compact announcement along the top of the floor with an optional second line, on a
    /// dark band so it reads over the crowd. Replaces any banner showing. Nothing is drawn outside
    /// the banner's area: text too long for it shrinks, then (the subtitle) wraps onto a second
    /// line, and only then is cut short (`fit`).
    func banner(_ title: String, subtitle: String? = nil, color: RGB, subtitleColor: RGB? = nil,
                life: TimeInterval = 1.1) {
        banner?.removeFromParent()
        let container = SKNode()
        container.position = bannerCenter
        let heading = Self.fit(title, size: textSize * 1.45, minSize: textSize, width: bannerWidth, maxLines: 1,
                               style: GlowText.Style.heading)
        let headingSize = heading.size
        container.addChild(GlowText.sprite(heading.lines[0], style: .heading(headingSize), color: color))
        var width = heading.width
        var height = headingSize * 1.3
        var subHeight: CGFloat = 0
        if let subtitle {
            let sub = Self.fit(subtitle, size: textSize * 0.88, minSize: 9, width: bannerWidth, maxLines: 2,
                               style: GlowText.Style.item)
            let lineColor = subtitleColor ?? self.subtitleColor
            for (index, text) in sub.lines.enumerated() {
                let line = GlowText.sprite(text, style: .item(sub.size), color: lineColor)
                line.position = CGPoint(x: 0, y: -headingSize * 0.9 - CGFloat(index) * sub.size * 1.25)
                container.addChild(line)
            }
            width = max(width, sub.width)
            subHeight = sub.size * 1.3 + CGFloat(sub.lines.count - 1) * sub.size * 1.25
            height += subHeight
        }
        // The band stays inside the banner's half of the floor, clear of the wall.
        let band = SKSpriteNode(color: .black, size: CGSize(width: min(width + textSize * 2, bannerWidth + 12),
                                                             height: height))
        band.alpha = 0.55
        band.position = CGPoint(x: 0, y: headingSize * 0.65 - height / 2)
        band.zPosition = -0.2
        container.addChild(band)
        container.alpha = 0
        container.setScale(1.08)
        container.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1, duration: 0.16)]),
            .wait(forDuration: life),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
        addChild(container)
        banner = container
    }

    /// `text` set to fit `width`: at `size` if it fits, else shrunk toward `minSize`; if it still
    /// does not fit and `maxLines` allows, split at the word break that best balances the lines;
    /// any line still too wide is cut short with an ellipsis. Returns the lines, the size they are
    /// drawn at and the widest line's width (never more than `width`).
    static func fit(_ text: String, size: CGFloat, minSize: CGFloat, width: CGFloat, maxLines: Int,
                    style: (CGFloat) -> GlowText.Style) -> (lines: [String], size: CGFloat, width: CGFloat) {
        let width = max(width, 1)
        func measure(_ line: String, _ size: CGFloat) -> CGFloat { GlowText.width(of: line, style: style(size)) }
        let natural = measure(text, size)
        if natural <= width { return ([text], size, natural) }
        let shrunk = max(size * width / natural, minSize)
        if measure(text, shrunk) <= width { return ([text], shrunk, measure(text, shrunk)) }
        var lines = [text]
        var lineSize = shrunk
        if maxLines >= 2 {
            let words = text.split(separator: " ", omittingEmptySubsequences: true)
            if words.count > 1 {
                var best: [String] = []
                var bestWidest = CGFloat.infinity
                for cut in 1..<words.count {
                    let pair = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
                    let widest = pair.map { measure($0, size) }.max()!
                    if widest < bestWidest { (best, bestWidest) = (pair, widest) }
                }
                lines = best
                // Two lines need less shrinking: as large as fits, from `size` down to `minSize`.
                lineSize = bestWidest <= width ? size : max(size * width / bestWidest, minSize)
            }
        }
        lines = lines.map { truncated($0, size: lineSize, width: width, measure: measure) }
        return (lines, lineSize, lines.map { measure($0, lineSize) }.max() ?? 0)
    }

    /// `line` cut short with an ellipsis until it fits `width`.
    private static func truncated(_ line: String, size: CGFloat, width: CGFloat,
                                  measure: (String, CGFloat) -> CGFloat) -> String {
        guard measure(line, size) > width else { return line }
        var kept = line
        while !kept.isEmpty {
            kept.removeLast()
            let candidate = kept.trimmingCharacters(in: .whitespaces) + "\u{2026}"
            if measure(candidate, size) <= width { return candidate }
        }
        return ""
    }

    /// Renders a banner's text without showing it.
    func prewarmBanner(_ title: String, subtitle: String?, color: RGB) {
        let shown = banner
        banner(title, subtitle: subtitle, color: color)
        banner?.removeFromParent()
        banner = shown
    }

    /// A short status message, on one line where it fits. Replaces any notice showing.
    func notice(_ text: String, color: RGB, life: TimeInterval = 1.8) {
        notice?.removeFromParent()
        // Shrunk to fit its area, then wrapped onto a second line, then cut short (`fit`).
        let fitted = Self.fit(text, size: textSize * 1.05, minSize: 9, width: noticeWidth, maxLines: 2,
                              style: GlowText.Style.item)
        let sprite = SKNode()
        for (index, line) in fitted.lines.enumerated() {
            let node = GlowText.sprite(line, style: .item(fitted.size), color: color)
            node.position = CGPoint(x: 0, y: -CGFloat(index) * fitted.size * 1.25)
            sprite.addChild(node)
        }
        sprite.position = noticeCenter
        sprite.alpha = 0
        sprite.run(.sequence([
            .fadeIn(withDuration: 0.12),
            .repeat(.sequence([.fadeAlpha(to: 0.55, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18)]), count: 2),
            .wait(forDuration: max(life - 0.72, 0.3)),
            .fadeOut(withDuration: 0.35),
            .removeFromParent(),
        ]))
        addChild(sprite)
        notice = sprite
    }

    /// Washes the arena with a colour that fades out.
    func flash(_ color: RGB, strength: CGFloat = 0.25, duration: TimeInterval = 0.45) {
        flashSprite.removeAllActions()
        flashSprite.color = color.uiColor()
        flashSprite.alpha = strength
        flashSprite.run(.fadeOut(withDuration: duration))
    }

    func update(elapsed: TimeInterval) {
        clock += elapsed
    }
}
