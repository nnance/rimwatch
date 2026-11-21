import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// On-screen controls in screen space (points, origin bottom-left). A floating stick appears
/// wherever a thumb lands on the stick side; Fire, Shockwave and Blink sit in the lower corner of
/// the other side. The sides follow the handedness option. Every touch is tracked on its own, so
/// the stick and any buttons can be held together. Nothing reacts inside the crease band.
///
/// Presses are latched: a tap that begins and ends between two frames still reaches the
/// simulation, because the press stays reported until `consumePresses()` is called after a
/// simulation step has seen it.
@MainActor
final class TouchControls: SKNode {
    enum Button: CaseIterable {
        case fire, shockwave, blink
    }

    /// The device-neutral input these controls are producing right now.
    var input: InputState {
        InputState(
            move: stickVector,
            fire: isHeld(.fire) || latched.contains(.fire),
            shockwave: isHeld(.shockwave) || latched.contains(.shockwave),
            blink: isHeld(.blink) || latched.contains(.blink)
        )
    }

    /// Which side the stick is on. The button cluster mirrors to the other side.
    var handedness: GameOptions.Handedness = .stickLeft {
        didSet { if handedness != oldValue { relayout() } }
    }

    /// Where the buttons are, so later layout work (the Duo crease) can keep them clear.
    private(set) var buttonClusterFrame: CGRect = .zero
    /// The region where a touch starts the stick.
    private(set) var stickZone: CGRect = .zero

    private let factory: GlowShapeFactory
    private let palette: Palette
    private var color: RGB { palette.controls }

    private var stickTouch: UITouch?
    private var stickCenter: CGPoint = .zero
    private var stickRestCenter: CGPoint = .zero
    private var stickRadius: CGFloat = 50
    private var stickVector: Vec2 = .zero
    private let stickBase = SKSpriteNode()
    private let stickKnob = SKSpriteNode()

    private var buttonTouches: [ObjectIdentifier: Button] = [:]
    private var buttonNodes: [Button: SKSpriteNode] = [:]
    private var buttonCenters: [Button: CGPoint] = [:]
    private var buttonRadii: [Button: CGFloat] = [:]
    private var available: [Button: Bool] = [.fire: true, .shockwave: true, .blink: true]
    /// Status dots round each button: heat round Fire, recharge round Blink, charges over Shockwave.
    private var gauges: [Button: [SKSpriteNode]] = [:]
    private static let gaugeDots: [Button: Int] = [.fire: 20, .blink: 16, .shockwave: 5]
    /// Fire drawn in the warning colour, shown over Fire while the lance is overheated.
    private let overheatNode = SKSpriteNode()
    private var status = Status()

    struct Status: Equatable {
        var heat = 0.0
        var isOverheated = false
        var blinkReadiness = 1.0
        var shockwaves = 0
        var maxShockwaves = 5
    }

    /// Buttons pressed since the simulation last stepped.
    private var latched: Set<Button> = []
    private var sceneSize: CGSize = .zero
    private var safeArea: UIEdgeInsets = .zero
    /// Scene x range of the crease, kept free of controls.
    private var keepClear: ClosedRange<CGFloat>?

    init(factory: GlowShapeFactory, palette: Palette) {
        self.factory = factory
        self.palette = palette
        super.init()
        addChild(stickBase)
        addChild(stickKnob)
        for button in Button.allCases {
            let node = SKSpriteNode()
            buttonNodes[button] = node
            addChild(node)
            gauges[button] = (0..<(Self.gaugeDots[button] ?? 0)).map { _ in
                let dot = SKSpriteNode(color: .white, size: CGSize(width: 3, height: 3))
                dot.blendMode = .add
                addChild(dot)
                return dot
            }
        }
        overheatNode.isHidden = true
        addChild(overheatNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    /// Lays the controls out for a scene size and safe area. Everything scales with the shorter
    /// side, so the same code works on any display. `keepClear` is a vertical band (the crease of
    /// an open Duo, in scene x) where no control sits and no touch is taken.
    func layout(size: CGSize, safeArea: UIEdgeInsets, keepClear: ClosedRange<CGFloat>? = nil) {
        sceneSize = size
        self.safeArea = safeArea
        self.keepClear = keepClear
        relayout()
    }

    private func relayout() {
        let size = sceneSize
        guard size.width > 0, size.height > 0 else { return }
        let short = min(size.width, size.height)
        let margin = max(14, short * 0.035)
        let left = safeArea.left + margin
        let right = size.width - safeArea.right - margin
        let bottom = safeArea.bottom + margin
        let stickOnLeft = handedness == .stickLeft
        let middleLow = keepClear?.lowerBound ?? size.width / 2
        let middleHigh = keepClear?.upperBound ?? size.width / 2

        stickRadius = min(max(short * 0.12, 40), 72)
        let stickInset = stickRadius * 1.3
        stickRestCenter = CGPoint(x: stickOnLeft ? left + stickInset : right - stickInset, y: bottom + stickInset)
        stickZone = stickOnLeft
            ? CGRect(x: 0, y: 0, width: middleLow, height: size.height)
            : CGRect(x: middleHigh, y: 0, width: size.width - middleHigh, height: size.height)

        let fireRadius = min(max(short * 0.105, 34), 56)
        let smallRadius = fireRadius * 0.68
        let fireCenter = CGPoint(x: stickOnLeft ? right - fireRadius : left + fireRadius, y: bottom + fireRadius)
        let reach = fireRadius + smallRadius + max(10, short * 0.02)
        func around(_ degrees: CGFloat) -> CGPoint {
            // Mirrored left to right when the cluster sits in the lower-left corner.
            let a = (stickOnLeft ? degrees : 180 - degrees) * .pi / 180
            return CGPoint(x: fireCenter.x + reach * cos(a), y: fireCenter.y + reach * sin(a))
        }
        buttonCenters = [.fire: fireCenter, .blink: around(100), .shockwave: around(162)]
        buttonRadii = [.fire: fireRadius, .blink: smallRadius, .shockwave: smallRadius]

        var cluster = CGRect.null
        for button in Button.allCases {
            let center = buttonCenters[button]!, radius = buttonRadii[button]!
            cluster = cluster.union(CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
            let node = buttonNodes[button]!
            factory.apply(factory.glyph(key: "button-\(button)-\(radius)",
                                        shape: Self.buttonShape(button, radius: radius, color: color),
                                        pointsPerUnit: 1), to: node)
            node.position = center
        }
        buttonClusterFrame = cluster
        layoutGauges()

        factory.apply(factory.glyph(key: "stick-base-\(stickRadius)",
                                    shape: ShapeDescription(scale: stickRadius, strokes: [
                                        ShapeStroke(ShapeKit.arc(radius: 1, segments: 48), color: color),
                                    ]), pointsPerUnit: 1), to: stickBase)
        factory.apply(factory.glyph(key: "stick-knob-\(stickRadius)",
                                    shape: ShapeDescription(scale: stickRadius * 0.4, strokes: [
                                        ShapeStroke(ShapeKit.arc(radius: 1, segments: 32), color: color),
                                        ShapeStroke(ShapeKit.arc(radius: 0.45, segments: 20), color: color),
                                    ]), pointsPerUnit: 1), to: stickKnob)
        if stickTouch == nil { stickCenter = stickRestCenter }
        refresh()
    }

    private func layoutGauges() {
        let warning = palette.warning
        if let center = buttonCenters[.fire], let radius = buttonRadii[.fire] {
            factory.apply(factory.glyph(key: "button-fire-hot-\(radius)",
                                        shape: Self.buttonShape(.fire, radius: radius, color: warning),
                                        pointsPerUnit: 1), to: overheatNode)
            overheatNode.position = center
        }
        for button in Button.allCases {
            guard let center = buttonCenters[button], let radius = buttonRadii[button],
                  let dots = gauges[button] else { continue }
            let count = dots.count
            let dotSize = max(2.5, radius * 0.07)
            for (index, dot) in dots.enumerated() {
                let angle: CGFloat
                let ring: CGFloat
                switch button {
                case .fire:
                    // A 260-degree arc, filling clockwise from the lower left.
                    ring = radius + dotSize * 2.2
                    angle = (220 - 260 * CGFloat(index) / CGFloat(max(count - 1, 1))) * .pi / 180
                case .blink:
                    // A full circle, filling clockwise from the top.
                    ring = radius + dotSize * 2.2
                    angle = (90 - 360 * CGFloat(index) / CGFloat(count)) * .pi / 180
                case .shockwave:
                    // Charges as pips in an arc over the top.
                    ring = radius + dotSize * 3
                    angle = (90 + 22 * (CGFloat(count - 1) / 2 - CGFloat(index))) * .pi / 180
                }
                dot.size = button == .shockwave ? CGSize(width: dotSize * 1.9, height: dotSize * 1.9)
                    : CGSize(width: dotSize, height: dotSize)
                dot.zRotation = button == .shockwave ? .pi / 4 : 0
                dot.position = CGPoint(x: center.x + ring * cos(angle), y: center.y + ring * sin(angle))
            }
        }
        refreshGauges(time: 0)
    }

    /// Shows heat round Fire (red and flashing when overheated), Blink's recharge, and how many
    /// Shockwaves are left. Values come from the simulation's public state.
    func setStatus(_ status: Status, time: TimeInterval) {
        self.status = status
        refreshGauges(time: time)
    }

    private func refreshGauges(time: TimeInterval) {
        let flashOn = sin(time * 14) > 0
        if let dots = gauges[.fire] {
            let lit = Int((status.heat * Double(dots.count)).rounded(.up))
            for (index, dot) in dots.enumerated() {
                let hot = status.isOverheated || Double(index) >= Double(dots.count) * 0.7
                dot.color = (hot ? palette.warning : color).uiColor()
                dot.alpha = index < lit ? (status.isOverheated ? (flashOn ? 1 : 0.4) : 0.85) : 0.1
            }
        }
        overheatNode.isHidden = !status.isOverheated
        overheatNode.alpha = flashOn ? 0.9 : 0.45
        if let dots = gauges[.blink] {
            let ready = status.blinkReadiness >= 1
            let lit = Int((status.blinkReadiness * Double(dots.count)).rounded(.down))
            for (index, dot) in dots.enumerated() {
                dot.color = (ready ? palette.shield : color).uiColor()
                dot.alpha = ready ? 0.75 : (index < lit ? 0.6 : 0.1)
            }
        }
        if let dots = gauges[.shockwave] {
            for (index, dot) in dots.enumerated() {
                dot.isHidden = index >= status.maxShockwaves
                dot.color = palette.shield.uiColor()
                dot.alpha = index < status.shockwaves ? 0.9 : 0.12
            }
        }
    }

    /// Dims a button that can't be used right now (Blink cooling down, no Shockwaves left).
    func setAvailable(_ button: Button, _ isAvailable: Bool) {
        guard available[button] != isAvailable else { return }
        available[button] = isAvailable
        refresh()
    }

    // MARK: Touches

    func touchesBegan(_ touches: Set<UITouch>) {
        for touch in touches {
            let p = touch.location(in: self)
            if let keepClear, keepClear.contains(p.x) { continue }
            if let button = button(at: p) {
                buttonTouches[ObjectIdentifier(touch)] = button
                latched.insert(button)
            } else if stickTouch == nil, stickZone.contains(p) {
                stickTouch = touch
                stickCenter = p
                stickVector = .zero
            }
        }
        refresh()
    }

    func touchesMoved(_ touches: Set<UITouch>) {
        guard let stickTouch, touches.contains(stickTouch) else { return }
        let p = stickTouch.location(in: self)
        var dx = p.x - stickCenter.x
        var dy = p.y - stickCenter.y
        let distance = hypot(dx, dy)
        // Past the rim, the base trails the thumb so the stick never runs out of travel.
        if distance > stickRadius {
            let excess = distance - stickRadius
            stickCenter.x += dx / distance * excess
            stickCenter.y += dy / distance * excess
            dx = p.x - stickCenter.x
            dy = p.y - stickCenter.y
        }
        stickVector = Vec2(Double(dx / stickRadius), Double(dy / stickRadius)).clampedToUnit
        refresh()
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches {
            buttonTouches[ObjectIdentifier(touch)] = nil
            if touch === stickTouch {
                stickTouch = nil
                stickVector = .zero
                stickCenter = stickRestCenter
            }
        }
        refresh()
    }

    /// Call after a frame in which the simulation stepped: latched presses have been delivered.
    func consumePresses() {
        latched.removeAll()
    }

    /// Lets go of everything, e.g. when the app loses focus and touch-ups may never arrive.
    func releaseAll() {
        buttonTouches.removeAll()
        latched.removeAll()
        stickTouch = nil
        stickVector = .zero
        stickCenter = stickRestCenter
        refresh()
    }

    /// The button a new touch at `p` should press. A touch close to a button presses it; any other
    /// touch on the right half fires, so the thumb doesn't have to land precisely.
    private func button(at p: CGPoint) -> Button? {
        var best: (Button, CGFloat)?
        for button in Button.allCases {
            guard let center = buttonCenters[button], let radius = buttonRadii[button] else { continue }
            let d = hypot(p.x - center.x, p.y - center.y) / radius
            if d < 1.35, best == nil || d < best!.1 { best = (button, d) }
        }
        if let best { return best.0 }
        // Anywhere else on the button side fires.
        return stickZone.contains(p) ? nil : .fire
    }

    private func isHeld(_ button: Button) -> Bool {
        buttonTouches.values.contains(button)
    }

    private func refresh() {
        let active = stickTouch != nil
        stickBase.position = stickCenter
        stickBase.alpha = active ? 0.55 : 0.18
        stickKnob.position = CGPoint(x: stickCenter.x + CGFloat(stickVector.x) * stickRadius,
                                     y: stickCenter.y + CGFloat(stickVector.y) * stickRadius)
        stickKnob.alpha = active ? 0.9 : 0.22
        for button in Button.allCases {
            let node = buttonNodes[button]!
            let held = isHeld(button)
            let usable = available[button] ?? true
            node.alpha = held ? 0.95 : (usable ? 0.42 : 0.14)
            node.setScale(held ? 0.94 : 1)
        }
    }

    // MARK: Shapes (in points, origin at the button centre)

    private static func buttonShape(_ button: Button, radius: CGFloat, color: RGB) -> ShapeDescription {
        let ring = ShapeStroke(ShapeKit.arc(radius: 1, segments: 48), color: color)
        let icon: [ShapeStroke]
        switch button {
        case .fire:
            // Three forward chevrons.
            icon = [-0.3, 0.0, 0.3].map { x in
                ShapeStroke([Vec2(x - 0.12, 0.28), Vec2(x + 0.12, 0), Vec2(x - 0.12, -0.28)], color: color)
            }
        case .shockwave:
            // A dot inside two rings.
            icon = [
                ShapeStroke(ShapeKit.arc(radius: 0.12, segments: 12), color: color),
                ShapeStroke(ShapeKit.arc(radius: 0.32, segments: 24), color: color),
                ShapeStroke(ShapeKit.arc(radius: 0.52, from: 0.4, to: 2 * .pi - 0.4, segments: 28), color: color),
            ]
        case .blink:
            // A dashed trail ending in an arrowhead.
            icon = [
                ShapeStroke([Vec2(-0.55, 0), Vec2(-0.4, 0)], color: color),
                ShapeStroke([Vec2(-0.28, 0), Vec2(-0.1, 0)], color: color),
                ShapeStroke([Vec2(0.02, 0), Vec2(0.45, 0)], color: color),
                ShapeStroke([Vec2(0.2, 0.25), Vec2(0.47, 0), Vec2(0.2, -0.25)], color: color),
            ]
        }
        return ShapeDescription(scale: Double(radius), strokes: [ring] + icon)
    }
}
