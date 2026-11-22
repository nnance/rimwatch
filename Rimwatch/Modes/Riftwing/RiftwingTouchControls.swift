import GameCore
import RiftwingCore
import SpriteKit
import UIKit

/// Riftwing's touch controls, in screen points: a floating steering stick (the shell's
/// `FloatingStick`) under one thumb, and the other half of the screen for flapping, where each
/// tap is one flap. Pulling the stick down past the dive threshold and holding it dives (the run
/// reads that from the stick); a chevron under the stick shows the threshold and lights while
/// diving. There is no fire button. The Stick side option says which half the stick takes; the
/// flap half is the other. Nothing reacts inside the crease band.
///
/// Flaps are counted, not held: the run flaps once per press of its flap input, so each tap is
/// offered to the run as a press that lasts until a simulation step has seen it, and a tap that
/// follows straight on from another is offered only after one step has seen the flap let go.
/// Taps that come faster than that wait their turn (at most a couple are kept).
@MainActor
final class RiftwingTouchControls: SKNode, TouchControlSurface {
    var handedness: GameOptions.Handedness = .stickLeft {
        didSet { if handedness != oldValue { relayout() } }
    }

    private let factory: GlowShapeFactory
    private let palette: RiftwingPalette
    private let diveThreshold: Double
    let stick: FloatingStick
    /// The resting marker of the flap half: a wing in a ring that answers each tap.
    private let flapMarker = SKSpriteNode()
    private let diveMarker = SKSpriteNode()
    private var flapZone: CGRect = .zero
    private var flapTouches: [UITouch] = []
    /// Taps not yet seen by a step.
    private var pendingTaps = 0
    /// The flap offered for the coming steps, and what the last step saw.
    private var offered = false
    private var lastSeen = false
    private var tappedAt: TimeInterval = -1
    private var time: TimeInterval = 0
    private var diving = false
    private var stickRadius: CGFloat = 40

    private var sceneSize: CGSize = .zero
    private var safeArea: UIEdgeInsets = .zero
    private var keepClear: ClosedRange<CGFloat>?

    init(factory: GlowShapeFactory, palette: RiftwingPalette, diveThreshold: Double) {
        self.factory = factory
        self.palette = palette
        self.diveThreshold = diveThreshold
        stick = FloatingStick(factory: factory, color: palette.controls)
        super.init()
        for node in stick.nodes { addChild(node) }
        addChild(diveMarker)
        addChild(flapMarker)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// This frame's touch input. The flap is a press for each tap (see the type's note).
    func nextInput() -> RiftwingInput {
        offered = !lastSeen && pendingTaps > 0
        return RiftwingInput(stick: stick.vector, flap: offered, dive: false)
    }

    func layout(size: CGSize, safeArea: UIEdgeInsets, keepClear: ClosedRange<CGFloat>?) {
        sceneSize = size
        self.safeArea = safeArea
        self.keepClear = keepClear
        relayout()
    }

    /// Everything scales with the shorter side. The stick rests low in its corner and floats to
    /// wherever a thumb lands in its half; the flap marker rests low in the other corner.
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
        let stickOnLeft = handedness == .stickLeft

        let radius = min(max(short * 0.095, 38), 60)
        stickRadius = radius
        let restInset = radius * 1.08
        let leftRest = CGPoint(x: left + restInset, y: bottom + restInset + radius * 0.3)
        let rightRest = CGPoint(x: right - restInset, y: bottom + restInset + radius * 0.3)
        let leftZone = CGRect(x: 0, y: 0, width: middleLow, height: size.height)
        let rightZone = CGRect(x: middleHigh, y: 0, width: size.width - middleHigh, height: size.height)
        stick.layout(radius: radius, rest: stickOnLeft ? leftRest : rightRest, zone: stickOnLeft ? leftZone : rightZone)
        flapZone = stickOnLeft ? rightZone : leftZone

        RiftwingSprites.dress(flapMarker, with: factory.glyph(key: "riftwing-flap-\(radius)",
                                                              shape: Self.flapShape(radius: radius * 0.75, color: palette.controls),
                                                              pointsPerUnit: 1), factory: factory)
        flapMarker.position = stickOnLeft ? rightRest : leftRest
        RiftwingSprites.dress(diveMarker, with: factory.glyph(key: "riftwing-dive-\(radius)", shape: ShapeDescription(
            scale: Double(radius) * 0.22, strokes: [
                ShapeStroke([Vec2(-1, 0.4), Vec2(0, -0.4), Vec2(1, 0.4)], color: palette.controls),
                ShapeStroke([Vec2(-1, -0.3), Vec2(0, -1.1), Vec2(1, -0.3)], color: palette.controls),
            ]), pointsPerUnit: 1), factory: factory)
        refresh()
    }

    /// Whether the rider is diving now, to light the dive chevron; `time` is the game clock.
    func setStatus(diving: Bool, time: TimeInterval) {
        self.time = time
        guard diving != self.diving || tappedAt >= 0 else { return }
        self.diving = diving
        refresh()
    }

    // MARK: Touches

    func touchesBegan(_ touches: Set<UITouch>) {
        for touch in touches {
            let p = touch.location(in: self)
            if let keepClear, keepClear.contains(p.x) { continue }
            if stick.touchBegan(touch, at: p) { continue }
            if flapZone.contains(p) {
                flapTouches.append(touch)
                pendingTaps = min(pendingTaps + 1, 2)
                tappedAt = time
            }
        }
        refresh()
    }

    func touchesMoved(_ touches: Set<UITouch>) {
        if stick.touchesMoved(touches, in: self) { refresh() }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches {
            stick.touchEnded(touch)
            flapTouches.removeAll { $0 === touch }
        }
        refresh()
    }

    /// A step has seen this frame's input: a flap offered to it is spent.
    func consumePresses() {
        if offered { pendingTaps = max(pendingTaps - 1, 0) }
        lastSeen = offered
        offered = false
    }

    func releaseAll() {
        flapTouches.removeAll()
        pendingTaps = 0
        stick.release()
        refresh()
    }

    private func refresh() {
        stick.refresh()
        let center = stick.base.position
        diveMarker.position = CGPoint(x: center.x, y: center.y - stickRadius * 0.62)
        diveMarker.alpha = diving ? 0.95 : (stick.isActive ? 0.3 : 0.1)
        diveMarker.setScale(diving ? 1.15 : 1)
        // The flap marker answers each tap with a short swell.
        let since = time - tappedAt
        let pressed = tappedAt >= 0 && since < 0.15
        if !pressed { tappedAt = -1 }
        flapMarker.alpha = !flapTouches.isEmpty || pressed ? 0.8 : 0.2
        flapMarker.setScale(pressed ? 0.9 : 1)
    }

    /// A ring holding a pair of raised wings: tap here to flap.
    private static func flapShape(radius: CGFloat, color: RGB) -> ShapeDescription {
        ShapeDescription(scale: Double(radius), strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: color),
            ShapeStroke([Vec2(-0.08, -0.15), Vec2(-0.55, 0.45), Vec2(-0.35, -0.05)], color: color),
            ShapeStroke([Vec2(0.08, -0.15), Vec2(0.55, 0.45), Vec2(0.35, -0.05)], color: color),
            ShapeStroke([Vec2(-0.3, -0.35), Vec2(0, -0.15), Vec2(0.3, -0.35)], color: color),
        ])
    }
}
