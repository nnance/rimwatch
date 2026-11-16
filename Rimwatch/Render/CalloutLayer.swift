import GameCore
import SpriteKit
import UIKit

/// Text feedback in screen space, so it stays a readable size whatever the world scale:
/// - popups float up from a point in the world ("+250", "SHIELD DOWN") and follow the camera;
/// - a banner announces big moments (a wave starting or cleared, Blackout) in one half of the
///   playfield, clear of the crease;
/// - a notice gives a one-line status (extra life, supply drop, outpost under attack) in the
///   other half, below the pause button.
/// All of these are short-lived nodes made when their event happens, never per frame.
@MainActor
final class CalloutLayer: SKNode {
    private struct Popup {
        let node: SKNode
        var worldX: Double
        var worldY: Double
        /// Screen offset that keeps it clear of popups that appeared beside it.
        let lift: CGFloat
        let born: TimeInterval
        /// An enemy to follow, if the popup belongs to something that moves.
        let followID: Int?
        /// Half the text's width, to keep it inside the playfield's sides.
        let halfWidth: CGFloat
    }

    var world: World
    private let theme: any Theme
    private var popups: [Popup] = []
    private var banner: SKNode?
    private var notice: SKNode?
    private let flashSprite = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))

    private var size: CGSize = .zero
    private var playfield: CGRect = .zero
    private var clock: TimeInterval = 0
    private var pointsPerUnit: CGFloat = 1
    private var bannerCenter: CGPoint = .zero
    private var noticeCenter: CGPoint = .zero
    private var bannerWidth: CGFloat = 200
    private var noticeWidth: CGFloat = 200
    private var textSize: CGFloat = 13

    init(world: World, theme: any Theme) {
        self.world = world
        self.theme = theme
        super.init()
        flashSprite.anchorPoint = .zero
        flashSprite.blendMode = .add
        flashSprite.alpha = 0
        flashSprite.zPosition = -1
        addChild(flashSprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// `playfield` is the area below the top band. `keepClear` is the crease band, if any.
    func layout(size: CGSize, playfield: CGRect, pointsPerUnit: CGFloat, keepClear: ClosedRange<CGFloat>?,
                pauseButtonFrame: CGRect) {
        self.size = size
        self.playfield = playfield
        self.pointsPerUnit = pointsPerUnit
        flashSprite.size = size
        let short = min(size.width, size.height)
        textSize = min(max(short * 0.034, 11), 17)
        let margin: CGFloat = 12
        if let keepClear, size.width > size.height {
            let left = CGRect(x: playfield.minX + margin, y: playfield.minY,
                              width: keepClear.lowerBound - margin - playfield.minX - margin, height: playfield.height)
            let right = CGRect(x: keepClear.upperBound + margin, y: playfield.minY,
                               width: playfield.maxX - keepClear.upperBound - 2 * margin, height: playfield.height)
            bannerCenter = CGPoint(x: left.midX, y: playfield.maxY - playfield.height * 0.3)
            bannerWidth = left.width
            noticeCenter = CGPoint(x: right.midX, y: min(pauseButtonFrame.minY - textSize * 1.6,
                                                         playfield.maxY - playfield.height * 0.22))
            noticeWidth = right.width - pauseButtonFrame.width * 0.2
        } else {
            bannerCenter = CGPoint(x: playfield.midX, y: playfield.maxY - playfield.height * 0.3)
            bannerWidth = playfield.width - 2 * margin
            noticeCenter = CGPoint(x: playfield.midX, y: bannerCenter.y - textSize * 5)
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

    // MARK: Kinds of callout

    /// Text that rises from a world point and fades. `scale` enlarges it relative to the base
    /// size. A popup that appears next to a recent one is stacked above (or below) it, so both stay
    /// readable; every popup is kept inside the playfield. `followID` names an enemy to follow.
    func popup(_ text: String, at pos: Vec2, color: RGB, scale: CGFloat = 1, life: TimeInterval = 0.9,
               followID: Int? = nil) {
        let sprite = GlowText.sprite(text, style: .item(textSize * scale), color: color)
        // Measured before the pop-in scale below, which `size` would include.
        let textWidth = sprite.size.width - 2 * GlowText.padding
        let container = SKNode()
        container.addChild(sprite)
        let rise = SKAction.moveBy(x: 0, y: textSize * Self.riseLines, duration: life)
        rise.timingMode = .easeOut
        sprite.setScale(0.6)
        sprite.run(.group([rise, .sequence([.scale(to: 1.05, duration: 0.12), .scale(to: 1, duration: 0.1)]),
                           .sequence([.wait(forDuration: life * 0.55), .fadeOut(withDuration: life * 0.45)])]))
        addChild(container)
        container.run(.sequence([.wait(forDuration: life + 0.05), .removeFromParent()]))
        let base = anchor(worldX: pos.x, worldY: pos.y)
        let popup = Popup(node: container, worldX: pos.x, worldY: pos.y,
                          lift: freeLift(at: base, worldX: pos.x, width: textWidth), born: clock, followID: followID,
                          halfWidth: textWidth * 1.05 / 2)
        popups.append(popup)
        place(popup)
    }

    /// How far a popup's text rises over its life, in lines of text.
    private static let riseLines: CGFloat = 1.8
    /// Vertical space one stacked popup takes.
    private var slot: CGFloat { textSize * 1.45 }
    /// The lowest and highest anchor a popup may have, so its text never leaves the playfield
    /// (it starts half a line above its anchor and rises).
    private var anchorRange: ClosedRange<CGFloat> {
        let low = playfield.minY + textSize
        let high = playfield.maxY - textSize * (Self.riseLines + 1.3)
        return low...max(low, high)
    }

    /// The lowest anchor a popup may have at world x: clear of the ground line there, so its
    /// text never sits on the terrain or the colonists standing on it.
    private func groundLimit(at worldX: Double) -> CGFloat {
        let ground = CGFloat(world.groundHeight(at: world.wrap(worldX))) * pointsPerUnit
        return min(max(anchorRange.lowerBound, ground + textSize * 1.6), anchorRange.upperBound)
    }

    /// Screen anchor for a world point, clamped into the playfield above the local ground.
    private func anchor(worldX: Double, worldY: Double) -> CGPoint {
        let dx = world.delta(from: lastCameraX, to: worldX)
        let y = min(max(CGFloat(worldY) * pointsPerUnit, groundLimit(at: worldX)), anchorRange.upperBound)
        return CGPoint(x: size.width / 2 + CGFloat(dx) * pointsPerUnit, y: y)
    }

    /// The first stacking offset whose spot is not taken by a popup that appeared there recently.
    /// Stacks go upward first; a slot is only used below the anchor when there is no room above,
    /// and never below the local ground line.
    private func freeLift(at base: CGPoint, worldX: Double, width: CGFloat) -> CGFloat {
        let recent = popups.filter { $0.node.parent != nil && clock - $0.born < 0.8 }
        let taken = recent.map { popup -> (x: CGFloat, y: CGFloat, half: CGFloat) in
            let p = anchor(worldX: popup.worldX, worldY: popup.worldY)
            return (clampedX(p.x, halfWidth: popup.halfWidth), p.y + popup.lift, popup.halfWidth)
        }
        let half = width * 1.05 / 2
        let x = clampedX(base.x, halfWidth: half)
        let candidates: [CGFloat] = [0, 1, 2, 3, 4, -1, -2].map { $0 * slot }
        let lowest = groundLimit(at: worldX)
        for lift in candidates {
            let y = base.y + lift
            guard y >= lowest - 0.5, y <= anchorRange.upperBound + 0.5 else { continue }
            let clash = taken.contains { abs($0.x - x) < $0.half + half + 6 && abs($0.y - y) < slot * 0.95 }
            if !clash { return lift }
        }
        return 0
    }

    /// A large announcement with an optional second line. Replaces any banner already showing.
    func banner(_ title: String, subtitle: String? = nil, color: RGB, subtitleColor: RGB? = nil,
                life: TimeInterval = 2.2) {
        banner?.removeFromParent()
        let container = SKNode()
        container.position = bannerCenter
        var headingSize = textSize * 2.1
        let natural = GlowText.width(of: title, style: .heading(headingSize))
        if natural > bannerWidth { headingSize = max(headingSize * bannerWidth / natural, textSize) }
        let heading = GlowText.sprite(title, style: .heading(headingSize), color: color)
        container.addChild(heading)
        if let subtitle {
            var subSize = textSize * 1.1
            let subNatural = GlowText.width(of: subtitle, style: .item(subSize))
            if subNatural > bannerWidth { subSize = max(subSize * bannerWidth / subNatural, 9) }
            let line = GlowText.sprite(subtitle, style: .item(subSize), color: subtitleColor ?? theme.palette.hud)
            line.position = CGPoint(x: 0, y: -headingSize * 0.95)
            container.addChild(line)
        }
        container.alpha = 0
        container.setScale(1.15)
        container.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.2)]),
            .wait(forDuration: life),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
        addChild(container)
        banner = container
    }

    /// A one-line status message. Replaces any notice already showing.
    func notice(_ text: String, color: RGB, life: TimeInterval = 2.0) {
        notice?.removeFromParent()
        var size = textSize * 1.05
        let natural = GlowText.width(of: text, style: .item(size))
        if natural > noticeWidth { size = max(size * noticeWidth / natural, 9) }
        let sprite = GlowText.sprite(text, style: .item(size), color: color)
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

    /// Washes the whole screen with a colour that fades out.
    func flash(_ color: RGB, strength: CGFloat = 0.25, duration: TimeInterval = 0.45) {
        flashSprite.removeAllActions()
        flashSprite.color = color.uiColor()
        flashSprite.alpha = strength
        flashSprite.run(.fadeOut(withDuration: duration))
    }

    /// Re-places popups for the camera. `positions` gives the current place of followed enemies.
    func update(cameraX: Double, elapsed: TimeInterval, positions: [Int: Vec2]) {
        clock += elapsed
        lastCameraX = cameraX
        popups.removeAll { $0.node.parent == nil }
        for index in popups.indices {
            if let id = popups[index].followID, let pos = positions[id] {
                popups[index].worldX = pos.x
                popups[index].worldY = pos.y
            }
            place(popups[index])
        }
    }

    private var lastCameraX = 0.0

    /// An x that keeps text of this half-width inside the playfield's sides.
    private func clampedX(_ x: CGFloat, halfWidth: CGFloat) -> CGFloat {
        let inset = min(halfWidth + 4, playfield.width / 2)
        return min(max(x, playfield.minX + inset), playfield.maxX - inset)
    }

    private func place(_ popup: Popup) {
        let base = anchor(worldX: popup.worldX, worldY: popup.worldY)
        // Off the side of the playfield it is simply not shown; near a side it is nudged in.
        popup.node.isHidden = base.x < playfield.minX + 8 || base.x > playfield.maxX - 8
        popup.node.position = CGPoint(x: clampedX(base.x, halfWidth: popup.halfWidth), y: base.y + popup.lift)
    }
}
