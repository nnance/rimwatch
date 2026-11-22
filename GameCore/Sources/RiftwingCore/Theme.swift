import Foundation
import GameCore

/// How Riftwing looks and sounds, kept apart from how it plays. The run knows roles; a
/// `RiftwingTheme` says what each looks and sounds like. Everything here is device-neutral data
/// (colours are plain RGB numbers, shapes are polylines from GameCore's `Shapes.swift`, sounds
/// are `SoundPatch` data), so the app decides how to draw and play it.
///
/// Shapes are seen from the side. In unit coordinates +x is the way the thing faces (the app
/// mirrors a figure facing left) and +y is up; the origin is its position. A figure's `scale` is
/// gallery units per unit coordinate at `RiftwingTuning.figureScale` 1, equal to its collision
/// radius, so a unit coordinate of 1 is its radius (draw figures with
/// `shape(for:figureScale:)`). A rig standing on a ledge has its feet at -`feetShare` (0.8).

/// The wings' pose, so a flap reads as a beat: swept down on the stroke, raised on the recovery,
/// spread in the glide, folded in a dive; perched or striding on a ledge.
public enum RiftwingWingPose: String, Sendable, Hashable, CaseIterable {
    /// The recovery after a stroke, or the wings opening after a dive.
    case raised
    /// Gliding.
    case spread
    /// The down stroke of a flap.
    case swept
    /// Folded tight along the frame: a dive.
    case folded
    /// Standing on a ledge, wings folded over the frame.
    case perched
    /// Running on a ledge (alternates with `perched` as it goes).
    case striding

    /// Seconds of the down stroke after a flap, then of the recovery.
    public static let strokeTime = 0.08
    public static let recoveryTime = 0.18

    /// The pose a rig's body is in. `stride` is how far along a ledge counts as one step.
    public static func of(_ body: RiftwingBody, stride: Double = 9) -> RiftwingWingPose {
        if body.isGrounded {
            guard abs(body.vel.x) > 20 else { return .perched }
            let step = Int((body.pos.x / max(stride, 1)).rounded(.down))
            return step.isMultiple(of: 2) ? .striding : .perched
        }
        if body.isDiving { return .folded }
        if body.reopen > 0 { return .raised }
        if body.sinceFlap < strokeTime { return .swept }
        if body.sinceFlap < recoveryTime { return .raised }
        return .spread
    }
}

/// Everything the renderer draws with a shape of its own.
public enum RiftwingShape: Sendable, Hashable {
    /// The player's flap-wing rig.
    case rider(RiftwingWingPose)
    /// An opponent. The Gleaner, not on a rig, uses only `.raised` and `.swept` (its buzzing
    /// wings); other poses draw it with its wings level.
    case opponent(RiftwingRole, RiftwingWingPose)
    /// A pod holding a colonist.
    case pod
    /// A mine (its tether is drawn by the app, from the anchor).
    case mine
    /// The arrow in a tunnel mouth while an opponent is on its way in, pointing into the
    /// gallery (+x). White, so the app can tint it by role. Not a figure: unit size.
    case arrival
    /// A life in the HUD: the rig gliding. Not a figure: unit size.
    case life
    /// The colonists-saved icon in the HUD: a pod. Not a figure: unit size.
    case colonist

    /// Drawn at the figure scale (`RiftwingTuning.figureScale`), so it matches its collision
    /// size.
    public var isFigure: Bool {
        switch self {
        case .rider, .opponent, .pod, .mine: true
        case .arrival, .life, .colonist: false
        }
    }

    public static var allCases: [RiftwingShape] {
        RiftwingWingPose.allCases.map { .rider($0) }
            + RiftwingRole.allCases.flatMap { role in RiftwingWingPose.allCases.map { .opponent(role, $0) } }
            + [.pod, .mine, .arrival, .life, .colonist]
    }
}

/// Colours that are not part of a single shape.
public struct RiftwingPalette: Sendable, Equatable {
    public var background: RGB
    /// Ledge outlines.
    public var rock: RGB
    /// The roof, the tunnel mouths and the faint marks on the rock.
    public var rockFaint: RGB
    /// The Rift's glow along the bottom.
    public var rift: RGB
    /// The Rift's breath.
    public var gas: RGB
    /// The motes of rising air over a vent.
    public var vent: RGB
    /// A pod about to hatch, a life lost, danger.
    public var warning: RGB
    /// Points popups and other good news.
    public var reward: RGB
    /// Protection after returning.
    public var shield: RGB
    /// On-screen touch controls.
    public var controls: RGB
    public var hud: RGB
    /// Wave banners and menu headings.
    public var heading: RGB

    public init(background: RGB, rock: RGB, rockFaint: RGB, rift: RGB, gas: RGB, vent: RGB, warning: RGB,
                reward: RGB, shield: RGB, controls: RGB, hud: RGB, heading: RGB) {
        self.background = background
        self.rock = rock
        self.rockFaint = rockFaint
        self.rift = rift
        self.gas = gas
        self.vent = vent
        self.warning = warning
        self.reward = reward
        self.shield = shield
        self.controls = controls
        self.hud = hud
        self.heading = heading
    }
}

public protocol RiftwingTheme: Sendable {
    var name: String { get }
    var palette: RiftwingPalette { get }
    /// The shape at figure scale 1.
    func shape(for thing: RiftwingShape) -> ShapeDescription
    func displayName(for role: RiftwingRole) -> String
    /// The sound for an event, if any (see `SoundPatch` in GameCore's `Audio/`).
    func sound(for event: RiftwingEvent) -> SoundPatch?
    /// The sound for an event in one of its versions. `variant` is, for a flap in the air, which
    /// of the theme's pitches (any integer; the theme wraps it). Other events ignore it.
    /// `RiftwingSoundDirector` chooses it.
    func sound(for event: RiftwingEvent, variant: Int) -> SoundPatch?
    func menuSound(_ sound: MenuSound) -> SoundPatch?
    /// Every patch the theme can play, so an app can prepare them all up front.
    var allSounds: [SoundPatch] { get }
    var music: MusicStyle? { get }
}

extension RiftwingTheme {
    public func sound(for event: RiftwingEvent) -> SoundPatch? { nil }
    public func sound(for event: RiftwingEvent, variant: Int) -> SoundPatch? { sound(for: event) }
    public func menuSound(_ sound: MenuSound) -> SoundPatch? { nil }
    public var allSounds: [SoundPatch] { [] }
    public var music: MusicStyle? { nil }

    /// The shape as drawn in the gallery: a figure's scale is multiplied by `figureScale`.
    public func shape(for thing: RiftwingShape, figureScale: Double) -> ShapeDescription {
        var shape = shape(for: thing)
        if thing.isFigure { shape.scale *= figureScale }
        return shape
    }

    /// The main colour of a shape: its role colour (the rider's, an opponent's, a pod's, a
    /// mine's), whatever the pose.
    public func color(of thing: RiftwingShape) -> RGB {
        let shape = shape(for: thing)
        return shape.strokes.last?.color ?? palette.hud
    }

    /// A role's colour.
    public func color(of role: RiftwingRole) -> RGB { color(of: .opponent(role, .spread)) }

    /// The look the shared screens take from this theme.
    public var shellStyle: ShellStyle {
        var sounds: [MenuSound: SoundPatch] = [:]
        for sound in MenuSound.allCases {
            if let patch = menuSound(sound) { sounds[sound] = patch }
        }
        return ShellStyle(background: palette.background, text: palette.hud, highlight: palette.reward,
                          heading: palette.heading, controls: palette.controls, menuSounds: sounds)
    }
}

/// Riftwing's first theme: the galleries in the caves of Calder's crater wall, in the same neon
/// world as the other two modes. The rider wears the Watch's cyan; pods the colonists' mint;
/// the Glider is the Husk's magenta (it is the first turned rig). Each opponent has its own
/// colour and silhouette: the Glider broad drooping wings with a ragged edge, the Striker narrow
/// swept wings and a spike at the nose, the Warden an armour plate and a crest, the Sower a seed
/// sac slung under its frame, and the Gleaner, not on a rig at all, a round drone with buzzing
/// wings and a hanging claw. The rock is a cool grey-blue so the figures stand out against it,
/// and the Rift glows a hot orange. Its sounds and music are in `Themes/RiftCavesSounds.swift`.
public struct RiftCaves: RiftwingTheme {
    public init() {}

    public let name = "Rift Caves"

    public let palette = RiftwingPalette(
        background: RGB(0, 0, 0),
        rock: RGB(hex: 0x50688C),
        rockFaint: RGB(hex: 0x2C3A52),
        rift: RGB(hex: 0xFF5A1E),
        gas: RGB(hex: 0xB8FF4A),
        vent: RGB(hex: 0xA8DCFF),
        warning: RGB(hex: 0xFF3030),
        reward: RGB(hex: 0xFFFF80),
        shield: RGB(hex: 0x60B0FF),
        controls: RGB(hex: 0x60E0FF),
        hud: RGB(hex: 0x60E0FF),
        heading: RGB(hex: 0xFFB347)
    )

    public func displayName(for role: RiftwingRole) -> String {
        switch role {
        case .glider: "Glider"
        case .striker: "Striker"
        case .warden: "Warden"
        case .gleaner: "Gleaner"
        case .sower: "Sower"
        }
    }

    public func shape(for thing: RiftwingShape) -> ShapeDescription {
        let tuning = RiftwingTuning()
        switch thing {
        case .rider(let pose):
            return ShapeDescription(scale: tuning.baseRiderRadius, strokes: Self.rig(.rider, pose: pose))
        case .opponent(let role, let pose):
            let radius = tuning.baseStats(for: role).radius
            if role == .gleaner { return ShapeDescription(scale: radius, strokes: Self.gleaner(pose: pose)) }
            return ShapeDescription(scale: radius, strokes: Self.rig(Self.style(of: role), pose: pose))
        case .pod:
            return ShapeDescription(scale: tuning.basePodRadius, strokes: Self.pod)
        case .mine:
            return ShapeDescription(scale: tuning.baseMineRadius, strokes: Self.mine)
        case .arrival:
            return ShapeDescription(scale: 1, strokes: Self.arrival)
        case .life:
            return ShapeDescription(scale: 1, strokes: Self.rig(.rider, pose: .spread))
        case .colonist:
            return ShapeDescription(scale: 1, strokes: Self.pod)
        }
    }

    // MARK: Colours

    /// The Watch's cyan, as on Ridgeline's ship and Redoubt's orb.
    static let cyan = RGB(hex: 0x3FF6FF)
    /// The colonists' mint, as in the other two modes.
    static let mint = RGB(hex: 0x7DF0B4)
    /// The Husk's magenta: the Glider is the first turned rig.
    static let magenta = RGB(hex: 0xFF3FD2)
    static let red = RGB(hex: 0xFF3355)
    static let violet = RGB(hex: 0xB070FF)
    static let yellow = RGB(hex: 0xF5E83A)
    static let orange = RGB(hex: 0xFF8A2A)
    static let pink = RGB(hex: 0xFF4F96)

    // MARK: Rigs

    /// What sets one rig apart from another.
    enum RigStyle {
        case rider, glider, striker, warden, sower
    }

    static func style(of role: RiftwingRole) -> RigStyle {
        switch role {
        case .glider: .glider
        case .striker: .striker
        case .warden: .warden
        case .sower, .gleaner: .sower
        }
    }

    private static func v(_ x: Double, _ y: Double) -> Vec2 { Vec2(x, y) }

    /// A one-person frame with two wings, side on: a spar from the tail fin to the nose, the pilot
    /// slung prone beneath it in flight or standing under it on a ledge, and two wings hinged at
    /// the spar, the far one dimmer and a little behind so both read. The role colour is always
    /// the last stroke (the near wing), so `color(of:)` finds it.
    static func rig(_ style: RigStyle, pose: RiftwingWingPose) -> [ShapeStroke] {
        let c: RGB = switch style {
        case .rider: cyan
        case .glider: magenta
        case .striker: red
        case .warden: violet
        case .sower: orange
        }
        let pale = c.lightened(0.7)
        let frame = c.scaled(0.85)
        let far = c.scaled(0.45)
        let grounded = pose == .perched || pose == .striding
        // The spar is raised overhead while it stands, so the pilot fits beneath it.
        let sparY = grounded ? 0.42 : 0.12
        var strokes: [ShapeStroke] = []

        // Wings: root front and back on the spar, the tip by pose; the far wing first.
        let tips: (near: Vec2, far: Vec2)
        var rootFront = v(0.38, sparY), rootBack = v(-0.36, sparY)
        switch pose {
        case .raised: tips = (v(-0.3, 1.12), v(-0.02, 1.0))
        case .spread: tips = (v(-0.62, 0.85), v(-0.32, 0.72))
        case .swept: tips = (v(-0.28, -1.0), v(0.0, -0.88))
        case .folded:
            tips = (v(-1.02, sparY + 0.2), v(-0.92, sparY + 0.32))
            rootFront = v(0.38, sparY + 0.02)
            rootBack = v(-0.35, sparY + 0.02)
        case .perched, .striding:
            tips = (v(-0.92, sparY + 0.28), v(-0.8, sparY + 0.4))
            rootFront = v(0.25, sparY + 0.02)
        }
        let shape = wing(style, front: rootFront, back: rootBack, tip: tips.near)
        let farShape = wing(style, front: rootFront + v(0.06, 0.04), back: rootBack + v(0.06, 0.04), tip: tips.far)
        strokes.append(ShapeStroke(farShape.outline, color: far))

        // The frame: spar, tail fin and nose.
        strokes.append(ShapeStroke([v(-0.88, sparY + 0.04), v(0.86, sparY - 0.04)], color: frame))
        strokes.append(ShapeStroke([v(-0.88, sparY + 0.04), v(-1.02, sparY + 0.32), v(-0.7, sparY + 0.04)], color: frame))
        if style == .striker {
            // A spike at the nose.
            strokes.append(ShapeStroke([v(0.78, sparY + 0.02), v(1.24, sparY - 0.08), v(0.78, sparY - 0.1)], color: c))
        }

        // The pilot.
        if grounded {
            let head = v(0.1, 0.12)
            strokes.append(ShapeStroke(ShapeKit.polygon(sides: 8, radius: 0.15, center: head), closed: true, color: pale))
            strokes.append(ShapeStroke([v(0.08, -0.04), v(0.0, -0.44)], color: pale))
            strokes.append(ShapeStroke([v(0.06, -0.1), v(0.16, sparY - 0.02)], color: pale))
            let legs: [Vec2] = pose == .striding
                ? [v(-0.3, -0.78), v(0.0, -0.44), v(0.32, -0.76)]
                : [v(-0.12, -0.8), v(0.0, -0.44), v(0.14, -0.8)]
            strokes.append(ShapeStroke(legs, color: pale))
            // Struts from the spar down to the harness.
            strokes.append(ShapeStroke([v(-0.3, sparY), v(-0.02, -0.2)], color: frame))
        } else {
            let head = v(0.52, -0.24)
            strokes.append(ShapeStroke(ShapeKit.polygon(sides: 8, radius: 0.19, center: head), closed: true, color: pale))
            strokes.append(ShapeStroke([v(0.32, -0.32), v(-0.66, -0.36)], color: pale))
            strokes.append(ShapeStroke([v(0.04, sparY), v(0.08, -0.32)], color: frame))
        }

        switch style {
        case .warden:
            // An armour plate over the pilot and a crest on the frame.
            let plateCentre = grounded ? v(0.02, -0.22) : v(0.02, -0.3)
            strokes.append(ShapeStroke(ShapeKit.polygon(sides: 6, radius: 0.3, rotation: Double.pi / 6, center: plateCentre),
                                       closed: true, color: c.lightened(0.3)))
            strokes.append(ShapeStroke([v(0.5, sparY - 0.02), v(0.62, sparY + 0.3), v(0.72, sparY - 0.03)], color: c))
        case .sower:
            // A seed sac slung under the frame, with seeds in it.
            let sac = grounded ? v(-0.48, -0.32) : v(-0.42, -0.6)
            strokes.append(ShapeStroke(ShapeKit.polygon(sides: 10, radius: 0.28, center: sac), closed: true, color: c.lightened(0.2)))
            strokes.append(ShapeStroke([sac + v(-0.08, 0.05), sac + v(0.06, -0.06)], color: pink))
            strokes.append(ShapeStroke([v(-0.42, sparY), sac + v(0, 0.28)], color: frame))
        case .rider, .glider, .striker:
            break
        }

        // The near wing last (its role colour). Ribs only where they set a role apart.
        if style == .warden || style == .glider {
            for rib in shape.ribs.dropFirst() { strokes.append(ShapeStroke(rib, color: c.scaled(0.75))) }
        }
        strokes.append(ShapeStroke(shape.outline, color: c))
        return strokes
    }

    /// A wing's outline (front root, tip, back root, with a ragged trailing edge for the Glider)
    /// and its ribs.
    private static func wing(_ style: RigStyle, front: Vec2, back: Vec2, tip: Vec2) -> (outline: [Vec2], ribs: [[Vec2]]) {
        var back = back, tip = tip
        switch style {
        case .glider:
            // Broad and drooping: the back root farther back, the tip a little lower and wider.
            back = back + v(-0.18, 0)
            tip = tip + v(-0.08, tip.y > 0 ? -0.08 : 0.06)
        case .striker:
            // Narrow and swept: a short root, the tip pulled back.
            back = back + v(0.2, 0)
            tip = tip + v(-0.12, 0)
        case .rider, .warden, .sower:
            break
        }
        var outline = [front, tip]
        if style == .glider {
            // A ragged trailing edge from the tip back to the root.
            for i in 1...3 {
                let t = Double(i) / 4
                let p = tip + (back - tip) * t
                let notch = (i % 2 == 0 ? 0.08 : -0.08)
                outline.append(p + v(notch, tip.y > back.y ? -0.06 : 0.06))
            }
        }
        outline.append(back)
        let mid = (front + back) * 0.5
        var ribs = [[mid, mid + (tip - mid) * 0.82]]
        if style == .warden || style == .glider {
            let rear = back + (front - back) * 0.2
            ribs.append([rear, rear + (tip - rear) * 0.7])
        }
        return (outline, ribs)
    }

    /// The Gleaner: not on a rig. A round drone body with a pale eye, two small wings buzzing up
    /// and down, and a claw hanging below for gripping a pod. The body colour is the last stroke.
    static func gleaner(pose: RiftwingWingPose) -> [ShapeStroke] {
        let c = yellow
        let wingTip: (near: Vec2, far: Vec2) = switch pose {
        case .raised: (v(-0.55, 1.05), v(-0.25, 1.0))
        case .swept: (v(-0.55, -0.35), v(-0.25, -0.3))
        default: (v(-0.95, 0.5), v(-0.7, 0.55))
        }
        let root = v(0.0, 0.42)
        return [
            ShapeStroke([root + v(0.15, 0), wingTip.far, root + v(-0.25, 0)], color: c.scaled(0.5)),
            ShapeStroke([v(-0.28, -0.5), v(-0.42, -0.9), v(-0.12, -1.02)], color: c.scaled(0.85)),
            ShapeStroke([v(0.28, -0.5), v(0.42, -0.9), v(0.12, -1.02)], color: c.scaled(0.85)),
            ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.18, center: v(0.22, 0.05)), closed: true,
                        color: RGB(hex: 0xFFF8B0)),
            ShapeStroke([root + v(0.15, 0), wingTip.near, root + v(-0.25, 0)], color: c.lightened(0.2)),
            ShapeStroke(ShapeKit.polygon(sides: 12, radius: 0.58), closed: true, color: c),
        ]
    }

    // MARK: Pods, mines, markers

    /// A capsule with a handle on top and a small figure inside, in the colonists' mint (the
    /// last stroke).
    static let pod: [ShapeStroke] = {
        let shell = ShapeKit.arc(center: Vec2(0, 0.25), radius: 0.62, from: 0, to: Double.pi, segments: 10)
            + ShapeKit.arc(center: Vec2(0, -0.25), radius: 0.62, from: Double.pi, to: 2 * Double.pi, segments: 10)
        let figure = mint.lightened(0.4)
        return [
            ShapeStroke([Vec2(-0.25, 0.92), Vec2(0, 1.05), Vec2(0.25, 0.92)], color: mint.scaled(0.8)),
            ShapeStroke(ShapeKit.polygon(sides: 6, radius: 0.14, center: Vec2(0, 0.3)), closed: true, color: figure),
            ShapeStroke([Vec2(0, 0.16), Vec2(0, -0.22)], color: figure),
            ShapeStroke([Vec2(-0.2, -0.5), Vec2(0, -0.22), Vec2(0.2, -0.5)], color: figure),
            ShapeStroke(shell, closed: true, color: mint),
        ]
    }()

    /// A spiked ball with a hot core: plainly something not to touch. The body is the last stroke.
    static let mine: [ShapeStroke] = {
        var strokes: [ShapeStroke] = []
        for i in 0..<8 {
            let a = Double(i) * Double.pi / 4 + Double.pi / 8
            strokes.append(ShapeStroke([Vec2(0.62 * cos(a), 0.62 * sin(a)), Vec2(1.05 * cos(a), 1.05 * sin(a))],
                                       color: pink.lightened(0.2)))
        }
        strokes.append(ShapeStroke(ShapeKit.polygon(sides: 4, radius: 0.24, rotation: Double.pi / 4), closed: true,
                                   color: RGB(hex: 0xFFD0E0)))
        strokes.append(ShapeStroke(ShapeKit.arc(radius: 0.62, segments: 18), closed: true, color: pink))
        return strokes
    }()

    /// Two chevrons pointing into the gallery. White, tinted by role.
    static let arrival: [ShapeStroke] = {
        let white = RGB(1, 1, 1)
        return [
            ShapeStroke([Vec2(-0.9, 0.7), Vec2(-0.2, 0), Vec2(-0.9, -0.7)], color: white),
            ShapeStroke([Vec2(-0.1, 0.7), Vec2(0.6, 0), Vec2(-0.1, -0.7)], color: white),
        ]
    }()
}
