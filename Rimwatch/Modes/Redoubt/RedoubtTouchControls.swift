import GameCore
import RedoubtCore
import SpriteKit
import UIKit

/// Redoubt's touch controls, in screen points: two floating sticks (the shell's `FloatingStick`),
/// move under one thumb and aim under the other, each confined to its own half of the screen,
/// and a Shockwave button above the aim stick's resting place, in reach of that thumb. There is
/// no fire button: pushing the aim stick fires. The Stick side option says which half the move
/// stick takes; the aim stick and the button take the other. Nothing reacts inside the crease band.
///
/// The Shockwave press is latched: a tap that begins and ends between two frames still reaches
/// the run, because it stays reported until `consumePresses()`.
@MainActor
final class RedoubtTouchControls: SKNode, TouchControlSurface {
    var input: RedoubtInput {
        RedoubtInput(move: moveStick.vector, aim: aimStick.vector, shockwave: buttonTouch != nil || latched)
    }

    var handedness: GameOptions.Handedness = .stickLeft {
        didSet { if handedness != oldValue { relayout() } }
    }

    private let factory: GlowShapeFactory
    private let palette: RedoubtPalette
    private let chargeShape: ShapeDescription
    let moveStick: FloatingStick
    let aimStick: FloatingStick
    private let button = SKSpriteNode()
    private var pips: [SKSpriteNode] = []
    private var buttonCenter: CGPoint = .zero
    private var buttonRadius: CGFloat = 30
    private var buttonTouch: UITouch?
    private var latched = false
    private var charges = 1
    private var canUse = true

    private var sceneSize: CGSize = .zero
    private var safeArea: UIEdgeInsets = .zero
    private var keepClear: ClosedRange<CGFloat>?
    /// Where the aim stick and the button sit, for the arena to keep in mind.
    private(set) var buttonFrame: CGRect = .zero

    init(factory: GlowShapeFactory, palette: RedoubtPalette, chargeShape: ShapeDescription, maxCharges: Int) {
        self.factory = factory
        self.palette = palette
        self.chargeShape = chargeShape
        moveStick = FloatingStick(factory: factory, color: palette.controls)
        aimStick = FloatingStick(factory: factory, color: palette.controls)
        super.init()
        for node in moveStick.nodes + aimStick.nodes { addChild(node) }
        addChild(button)
        for _ in 0..<maxCharges {
            let pip = SKSpriteNode()
            addChild(pip)
            pips.append(pip)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func layout(size: CGSize, safeArea: UIEdgeInsets, keepClear: ClosedRange<CGFloat>?) {
        sceneSize = size
        self.safeArea = safeArea
        self.keepClear = keepClear
        relayout()
    }

    /// Everything scales with the shorter side. The sticks rest low in the corners, over the
    /// arena's corners (the least busy part of the floor), and float to wherever a thumb lands in
    /// their half; the button sits above the aim stick's resting place.
    private func relayout() {
        let size = sceneSize
        guard size.width > 0, size.height > 0 else { return }
        let short = min(size.width, size.height)
        let margin = max(8, short * 0.015)
        let left = safeArea.left + margin
        let right = size.width - safeArea.right - margin
        let bottom = safeArea.bottom + margin
        let middleLow = keepClear?.lowerBound ?? size.width / 2
        let middleHigh = keepClear?.upperBound ?? size.width / 2
        let moveOnLeft = handedness == .stickLeft

        let radius = min(max(short * 0.095, 38), 60)
        let restInset = radius * 1.08
        let leftRest = CGPoint(x: left + restInset, y: bottom + restInset)
        let rightRest = CGPoint(x: right - restInset, y: bottom + restInset)
        let leftZone = CGRect(x: 0, y: 0, width: middleLow, height: size.height)
        let rightZone = CGRect(x: middleHigh, y: 0, width: size.width - middleHigh, height: size.height)
        moveStick.layout(radius: radius, rest: moveOnLeft ? leftRest : rightRest, zone: moveOnLeft ? leftZone : rightZone)
        aimStick.layout(radius: radius, rest: moveOnLeft ? rightRest : leftRest, zone: moveOnLeft ? rightZone : leftZone)

        buttonRadius = min(max(short * 0.05, 22), 32)
        let aimRest = moveOnLeft ? rightRest : leftRest
        let towardEdge: CGFloat = moveOnLeft ? 1 : -1
        buttonCenter = CGPoint(x: aimRest.x + towardEdge * radius * 0.35,
                               y: aimRest.y + radius + buttonRadius + max(12, short * 0.025))
        buttonFrame = CGRect(x: buttonCenter.x - buttonRadius, y: buttonCenter.y - buttonRadius,
                             width: buttonRadius * 2, height: buttonRadius * 2)
        RedoubtSprites.dress(button, with: factory.glyph(key: "redoubt-shock-button-\(buttonRadius)",
                                    shape: Self.buttonShape(radius: buttonRadius, color: palette.controls),
                                    pointsPerUnit: 1), factory: factory)
        button.position = buttonCenter
        let pipSize = Double(max(3, buttonRadius * 0.14))
        let glyph = factory.glyph(key: "redoubt-shock-pip-\(pipSize)",
                                  shape: ShapeDescription(scale: pipSize, strokes: chargeShape.strokes), pointsPerUnit: 1)
        let ring = buttonRadius + CGFloat(pipSize) * 2.4
        for (index, pip) in pips.enumerated() {
            RedoubtSprites.dress(pip, with: glyph, factory: factory)
            let angle = (90 + 26 * (CGFloat(pips.count - 1) / 2 - CGFloat(index))) * .pi / 180
            pip.position = CGPoint(x: buttonCenter.x + ring * cos(angle), y: buttonCenter.y + ring * sin(angle))
        }
        refresh()
    }

    /// Charges in hand, and whether the orb can use one now.
    func setStatus(charges: Int, canUse: Bool) {
        guard charges != self.charges || canUse != self.canUse else { return }
        self.charges = charges
        self.canUse = canUse
        refresh()
    }

    // MARK: Touches

    func touchesBegan(_ touches: Set<UITouch>) {
        for touch in touches {
            let p = touch.location(in: self)
            if let keepClear, keepClear.contains(p.x) { continue }
            if buttonTouch == nil, hypot(p.x - buttonCenter.x, p.y - buttonCenter.y) < buttonRadius * 1.35 {
                buttonTouch = touch
                latched = true
                continue
            }
            if moveStick.touchBegan(touch, at: p) { continue }
            _ = aimStick.touchBegan(touch, at: p)
        }
        refresh()
    }

    func touchesMoved(_ touches: Set<UITouch>) {
        let moved = moveStick.touchesMoved(touches, in: self)
        let aimed = aimStick.touchesMoved(touches, in: self)
        if moved || aimed { refresh() }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === buttonTouch { buttonTouch = nil }
            moveStick.touchEnded(touch)
            aimStick.touchEnded(touch)
        }
        refresh()
    }

    func consumePresses() {
        latched = false
    }

    func releaseAll() {
        buttonTouch = nil
        latched = false
        moveStick.release()
        aimStick.release()
        refresh()
    }

    private func refresh() {
        moveStick.refresh()
        aimStick.refresh()
        let held = buttonTouch != nil
        let usable = canUse && charges > 0
        button.alpha = held ? 0.95 : (usable ? 0.5 : 0.13)
        button.setScale(held ? 0.94 : 1)
        for (index, pip) in pips.enumerated() {
            pip.alpha = index < charges ? 0.9 : 0.12
        }
    }

    /// A ring holding a burst: a dot, a ring and four rays.
    private static func buttonShape(radius: CGFloat, color: RGB) -> ShapeDescription {
        var strokes = [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: color),
            ShapeStroke(ShapeKit.arc(radius: 0.14, segments: 12), color: color),
            ShapeStroke(ShapeKit.arc(radius: 0.38, segments: 20), color: color),
        ]
        for i in 0..<4 {
            let a = Double.pi / 4 + Double(i) * Double.pi / 2
            strokes.append(ShapeStroke([Vec2(0.52 * cos(a), 0.52 * sin(a)), Vec2(0.72 * cos(a), 0.72 * sin(a))],
                                       color: color))
        }
        return ShapeDescription(scale: Double(radius), strokes: strokes)
    }
}
