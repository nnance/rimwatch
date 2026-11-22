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

    @Test func everyRoleHasItsOwnColour() throws {
        let colours = RiftwingRole.allCases.map { theme.color(of: $0) }
        #expect(Set(colours).count == RiftwingRole.allCases.count)
        // And none is the rider's, a pod's or a mine's.
        #expect(!colours.contains(theme.color(of: .rider(.spread))))
        #expect(!colours.contains(theme.color(of: .pod)))
        #expect(!colours.contains(theme.color(of: .mine)))
        #expect(theme.color(of: .pod) != theme.color(of: .mine))
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
    /// the gallery's height, at figure scale 1), and no pose reaches far past its radius.
    @Test func figuresAreAboutAsBigAsTheyCollide() throws {
        let tuning = RiftwingTuning()
        func reach(_ thing: RiftwingShape, scale: Double = 1) -> Double {
            let shape = theme.shape(for: thing, figureScale: scale)
            let b = shape.bounds
            return max(abs(b.min.x), abs(b.max.x), abs(b.min.y), abs(b.max.y)) * shape.scale
        }
        func span(_ thing: RiftwingShape) -> Double {
            let shape = theme.shape(for: thing, figureScale: tuning.figureScale)
            return (shape.bounds.max.x - shape.bounds.min.x) * shape.scale
        }
        for pose in RiftwingWingPose.allCases {
            #expect(reach(.rider(pose)) >= tuning.riderRadius * 0.9, "\(pose)")
            #expect(reach(.rider(pose)) <= tuning.riderRadius * 1.3, "\(pose)")
            for role in RiftwingRole.allCases {
                let radius = tuning.stats(for: role).radius
                #expect(reach(.opponent(role, pose)) >= radius * 0.9, "\(role) \(pose)")
                #expect(reach(.opponent(role, pose)) <= radius * 1.4, "\(role) \(pose)")
            }
        }
        #expect(span(.rider(.spread)) >= 2 * tuning.riderRadius * 0.9)
        #expect(span(.rider(.spread)) / tuning.height >= 0.045)
        #expect(reach(.pod) >= tuning.podRadius * 0.9 && reach(.pod) <= tuning.podRadius * 1.3)
        #expect(reach(.mine) >= tuning.mineRadius * 0.9 && reach(.mine) <= tuning.mineRadius * 1.3)
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
