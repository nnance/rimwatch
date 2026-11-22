import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Riftwing's look: everything has a shape, the roles can be told apart by colour, figures are
/// drawn at the size they collide at, and the wing pose follows the body so a flap reads.
@Suite struct RiftwingThemeTests {
    let theme = RiftCaves()

    @Test func everythingDrawnHasAShape() throws {
        for thing in RiftwingShape.allCases {
            let shape = theme.shape(for: thing)
            #expect(!shape.strokes.isEmpty, "\(thing)")
            #expect(shape.scale > 0, "\(thing)")
            #expect(shape.strokes.allSatisfy { $0.points.count >= 2 }, "\(thing)")
        }
        for role in RiftwingRole.allCases {
            #expect(!theme.displayName(for: role).isEmpty)
        }
    }

    /// CIELAB (D65) of a colour, for judging how far apart two colours look.
    static func lab(_ c: RGB) -> (l: Double, a: Double, b: Double) {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(c.r), g = linear(c.g), bl = linear(c.b)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * bl
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// How different two colours look (CIE76 delta E): about 2 is just noticeable; the red
    /// Striker against the warning red, the first version, was 20.
    static func difference(_ a: RGB, _ b: RGB) -> Double {
        let p = lab(a), q = lab(b)
        return ((p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
    }

    /// Every role, the rider, pods, mines and the warning red are clearly apart: at a glance, at
    /// 17 points, on black, not merely unequal.
    @Test func everyRoleHasItsOwnColour() throws {
        var named: [(String, RGB)] = RiftwingRole.allCases.map { ("\($0)", theme.color(of: $0)) }
        named += [("rider", theme.color(of: .rider(.spread))), ("pod", theme.color(of: .pod)),
                  ("mine", theme.color(of: .mine)), ("warning", theme.palette.warning)]
        var closest = (Double.infinity, "")
        for i in named.indices {
            for j in named.indices where j > i {
                let d = Self.difference(named[i].1, named[j].1)
                if d < closest.0 { closest = (d, "\(named[i].0)-\(named[j].0)") }
                #expect(d >= 36, "\(named[i].0) and \(named[j].0) are only \(Int(d)) apart")
            }
        }
        print("COLOURS riftwing: closest pair \(closest.1) at \(Int(closest.0))")
    }

    @Test func aRolesColourIsTheSameInEveryPose() throws {
        for pose in RiftwingWingPose.allCases {
            #expect(theme.color(of: .rider(pose)) == theme.color(of: .rider(.spread)), "\(pose)")
            for role in RiftwingRole.allCases {
                #expect(theme.color(of: .opponent(role, pose)) == theme.color(of: role), "\(role) \(pose)")
            }
        }
    }

    @Test func itSharesItsWorldWithTheOtherModes() throws {
        // The Watch's cyan, the colonists' mint and the Husk's magenta.
        #expect(theme.color(of: .rider(.spread)) == RGB(hex: 0x3FF6FF))
        #expect(theme.color(of: .pod) == RGB(hex: 0x7DF0B4))
        #expect(theme.color(of: .glider) == RGB(hex: 0xFF3FD2))
    }

    /// The rig is drawn at the size it collides at: its frame spans its diameter (30 units, 5% of
    /// the gallery's height, at figure scale 1), and no pose reaches far past its radius. Width
    /// and height are checked apart, so a figure drawn too narrow or too flat fails.
    @Test func figuresAreAboutAsBigAsTheyCollide() throws {
        let tuning = RiftwingTuning()
        func reach(_ thing: RiftwingShape, scale: Double = 1) -> Double {
            let shape = theme.shape(for: thing, figureScale: scale)
            let b = shape.bounds
            return max(abs(b.min.x), abs(b.max.x), abs(b.min.y), abs(b.max.y)) * shape.scale
        }
        /// Width and height in gallery units at figure scale 1.
        func spans(_ thing: RiftwingShape) -> (width: Double, height: Double) {
            let shape = theme.shape(for: thing, figureScale: 1)
            return ((shape.bounds.max.x - shape.bounds.min.x) * shape.scale,
                    (shape.bounds.max.y - shape.bounds.min.y) * shape.scale)
        }
        /// Each of width and height at least `wide` and `tall` diameters' worth of `radius`.
        func expectSpans(_ thing: RiftwingShape, radius: Double, wide: Double, tall: Double) {
            let s = spans(thing)
            #expect(s.width >= 2 * radius * wide, "\(thing) is \(s.width) wide for radius \(radius)")
            #expect(s.height >= 2 * radius * tall, "\(thing) is \(s.height) tall for radius \(radius)")
            #expect(s.width <= 2 * radius * 1.4 && s.height <= 2 * radius * 1.4, "\(thing) is \(s)")
        }
        for pose in RiftwingWingPose.allCases {
            // A dive folds the wings flat, so a folded rig is allowed to be low.
            let tall = pose == .folded ? 0.4 : 0.6
            #expect(reach(.rider(pose)) >= tuning.baseRiderRadius * 0.9, "\(pose)")
            #expect(reach(.rider(pose)) <= tuning.baseRiderRadius * 1.3, "\(pose)")
            expectSpans(.rider(pose), radius: tuning.baseRiderRadius, wide: 0.9, tall: tall)
            for role in RiftwingRole.allCases {
                let radius = tuning.baseStats(for: role).radius
                #expect(reach(.opponent(role, pose)) >= radius * 0.9, "\(role) \(pose)")
                #expect(reach(.opponent(role, pose)) <= radius * 1.4, "\(role) \(pose)")
                expectSpans(.opponent(role, pose), radius: radius, wide: role == .gleaner ? 0.6 : 0.9,
                            tall: role == .gleaner ? 0.6 : tall)
            }
        }
        #expect(spans(.rider(.spread)).width * tuning.figureScale / tuning.height >= 0.045)
        expectSpans(.pod, radius: tuning.basePodRadius, wide: 0.7, tall: 0.9)
        expectSpans(.mine, radius: tuning.baseMineRadius, wide: 0.9, tall: 0.9)
        expectSpans(.freedColonist, radius: tuning.basePodRadius, wide: 0.45, tall: 0.75)
        #expect(reach(.pod) >= tuning.basePodRadius * 0.9 && reach(.pod) <= tuning.basePodRadius * 1.3)
        #expect(reach(.mine) >= tuning.baseMineRadius * 0.9 && reach(.mine) <= tuning.baseMineRadius * 1.3)
        // The figure scale grows every figure with it.
        #expect(abs(reach(.rider(.spread), scale: 2) - 2 * reach(.rider(.spread))) < 1e-9)
    }

    /// Standing on a ledge, the drawn feet are where the run puts them.
    @Test func aStandingRigsFeetAreOnTheLedge() throws {
        let tuning = RiftwingTuning()
        for pose in [RiftwingWingPose.perched, .striding] {
            let shape = theme.shape(for: .rider(pose))
            #expect(abs(shape.bounds.min.y + tuning.feetShare) < 0.03, "\(pose)")
        }
    }

    @Test func theWingPoseFollowsTheBody() throws {
        var body = RiftwingBody(pos: Vec2(100, 300), radius: 15)
        body.sinceFlap = 0
        #expect(RiftwingWingPose.of(body) == .swept)
        body.sinceFlap = 0.12
        #expect(RiftwingWingPose.of(body) == .raised)
        body.sinceFlap = 1
        #expect(RiftwingWingPose.of(body) == .spread)
        body.isDiving = true
        #expect(RiftwingWingPose.of(body) == .folded)
        body.isDiving = false
        body.reopen = 0.1
        #expect(RiftwingWingPose.of(body) == .raised)
        body.reopen = 0
        body.ledge = 0
        #expect(RiftwingWingPose.of(body) == .perched)
        // Running, it strides and stands by turns as it goes.
        body.vel = Vec2(150, 0)
        var poses: Set<RiftwingWingPose> = []
        for step in 0..<10 {
            body.pos.x = 100 + Double(step) * 4
            poses.insert(RiftwingWingPose.of(body))
        }
        #expect(poses == [.perched, .striding])
    }

    /// A flap in a run shows as a beat: the stroke, the recovery, then the glide.
    @Test func aFlapInARunReadsAsABeat() throws {
        var run = quietRun()
        run.step(flapPress)
        #expect(RiftwingWingPose.of(run.rider.body) == .swept)
        var poses: [RiftwingWingPose] = []
        for _ in 0..<60 {
            run.step(still)
            let pose = RiftwingWingPose.of(run.rider.body)
            if poses.last != pose { poses.append(pose) }
        }
        #expect(Array(poses.prefix(3)) == [.swept, .raised, .spread])
    }

    @Test func theShellStyleComesFromThePalette() throws {
        let style = theme.shellStyle
        #expect(style.background == theme.palette.background)
        #expect(style.text == theme.palette.hud)
        #expect(style.heading == theme.palette.heading)
    }
}
