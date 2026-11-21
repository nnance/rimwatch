import Testing
import GameCore
@testable import RedoubtCore

/// Redoubt's look: every role has a shape, the roles can be told apart by colour, and it shares
/// its world with Ridgeline.
@Suite struct ThemeTests {
    let theme = CalderDome()

    @Test func everythingDrawnHasAShape() throws {
        for thing in RedoubtShape.allCases {
            let shape = theme.shape(for: thing)
            #expect(!shape.strokes.isEmpty, "\(thing)")
            #expect(shape.scale > 0, "\(thing)")
            #expect(shape.strokes.allSatisfy { $0.points.count >= 2 }, "\(thing)")
        }
        for role in RedoubtRole.allCases {
            #expect(!theme.displayName(for: role).isEmpty)
        }
    }

    @Test func everyRoleHasItsOwnColour() throws {
        let colours = RedoubtRole.allCases.map { theme.color(of: .enemy($0)) }
        #expect(Set(colours).count == RedoubtRole.allCases.count)
        // And none is the orb's or a colonist's.
        #expect(!colours.contains(theme.color(of: .orb)))
        #expect(!colours.contains(theme.color(of: .colonist)))
    }

    @Test func itSharesItsWorldWithRidgeline() throws {
        // The Watch's cyan, Ridgeline's colonist mint and Ridgeline's Husk magenta.
        #expect(theme.color(of: .orb) == RGB(hex: 0x3FF6FF))
        #expect(theme.color(of: .colonist) == RGB(hex: 0x7DF0B4))
        #expect(theme.color(of: .enemy(.husk)) == RGB(hex: 0xFF3FD2))
    }

    @Test func shapesAreAboutAsBigAsWhatTheyStandFor() throws {
        let tuning = RedoubtTuning()
        func reach(_ thing: RedoubtShape) -> Double {
            let shape = theme.shape(for: thing, figureScale: tuning.figureScale)
            let b = shape.bounds
            return max(abs(b.min.x), abs(b.max.x), abs(b.min.y), abs(b.max.y)) * shape.scale
        }
        for role in RedoubtRole.allCases {
            let radius = tuning.stats(for: role).radius
            #expect(reach(.enemy(role)) >= radius * 0.9, "\(role)")
            #expect(reach(.enemy(role)) <= radius * 1.8, "\(role)")
        }
        #expect(reach(.orb) >= tuning.orbRadius)
        // The Thresher is the biggest thing that moves (every role but the Burrow, which never
        // does).
        let movers = RedoubtRole.allCases.filter { $0 != .burrow && $0 != .thresher }
        #expect(!movers.isEmpty)
        #expect(movers.allSatisfy { reach(.enemy($0)) < reach(.enemy(.thresher)) })
        // The airlock shape is drawn at its opening's width.
        #expect(abs(theme.shape(for: .airlockOpen, figureScale: tuning.figureScale).scale - tuning.airlockWidth) < 1e-9)
    }

    /// The orb's body (its ring, not the emitter spike in front) is drawn at its radius, so what
    /// the player sees matches `orbRadius` and the smaller hit radius stays a forgiving margin.
    @Test func theOrbIsDrawnAtItsRadius() throws {
        let tuning = RedoubtTuning()
        let shape = theme.shape(for: .orb, figureScale: tuning.figureScale)
        // The body is the largest stroke whose points all lie on one circle round the origin.
        var body = 0.0
        for stroke in shape.strokes {
            let radii = stroke.points.map { $0.length }
            guard let first = radii.first, radii.count >= 8, radii.allSatisfy({ abs($0 - first) < 1e-9 }) else { continue }
            body = max(body, first * shape.scale)
        }
        #expect(abs(body - tuning.orbRadius) < 0.01)
        #expect(tuning.orbHitRadius < body)
    }

    @Test func theShellStyleComesFromThePalette() throws {
        let style = theme.shellStyle
        #expect(style.background == theme.palette.background)
        #expect(style.text == theme.palette.hud)
        #expect(style.heading == theme.palette.heading)
    }
}
