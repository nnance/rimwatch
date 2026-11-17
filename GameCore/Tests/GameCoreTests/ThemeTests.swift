import Testing
@testable import GameCore

@Suite struct ThemeTests {
    let theme: any Theme = AlienFrontier()

    @Test func everyRoleHasAVisibleShape() {
        for role in EntityRole.allCases {
            let shape = theme.shape(for: role)
            #expect(shape.scale > 0, "\(role)")
            #expect(!shape.strokes.isEmpty, "\(role)")
            for stroke in shape.strokes {
                #expect(stroke.points.count >= 2, "\(role)")
                // A stroke must be bright enough to see on black.
                #expect(max(stroke.color.r, stroke.color.g, stroke.color.b) > 0.2, "\(role)")
            }
            let bounds = shape.bounds
            #expect(bounds.max.x > bounds.min.x || bounds.max.y > bounds.min.y, "\(role)")
        }
    }

    @Test func allCasesCoversEveryEnemyAndBothProjectileOwners() {
        let roles = EntityRole.allCases
        for kind in EnemyKind.allCases {
            #expect(roles.contains(.enemy(kind)))
        }
        #expect(roles.contains(.projectile(.player)))
        #expect(roles.contains(.projectile(.enemy)))
        #expect(Set(roles).count == roles.count)
    }

    @Test func shapesAreRoughlyTheSizeOfTheirHitboxes() {
        let tuning = Tuning()
        let player = theme.shape(for: .player)
        #expect(player.scale >= tuning.playerRadius)
        for kind in EnemyKind.allCases {
            let shape = theme.shape(for: .enemy(kind))
            let radius = tuning.stats(for: kind).radius
            let bounds = shape.bounds
            let halfWidth = (bounds.max.x - bounds.min.x) / 2 * shape.scale
            #expect(halfWidth >= radius * 0.6, "\(kind)")
            #expect(halfWidth <= radius * 2, "\(kind)")
        }
    }

    @Test func colonistAndOutpostStandOnTheirOrigin() {
        #expect(theme.shape(for: .colonist).bounds.min.y >= 0)
        #expect(theme.shape(for: .outpost).bounds.min.y >= 0)
        #expect(theme.shape(for: .ruin).bounds.min.y >= 0)
    }

    /// Colonists stand 16 units either side of an outpost's centre (and further out in later
    /// slots). The dome and mast must stay clear of them so they read on their own.
    @Test func colonistsStandClearOfTheOutpostDome() {
        let colonist = theme.shape(for: .colonist)
        let colonistHalfWidth = max(-colonist.bounds.min.x, colonist.bounds.max.x) * colonist.scale
        let outpost = theme.shape(for: .outpost)
        // Everything above pad level (the pad itself runs under the colonists' feet).
        let raised = outpost.strokes.flatMap(\.points).filter { $0.y > 0.35 }
        let domeHalfWidth = raised.map { abs($0.x) * outpost.scale }.max() ?? 0
        #expect(domeHalfWidth + colonistHalfWidth + 2 <= 16)
        // The pad reaches past the second standing slot (30 units out).
        let padHalfWidth = max(-outpost.bounds.min.x, outpost.bounds.max.x) * outpost.scale
        #expect(padHalfWidth >= 30 + colonistHalfWidth)
    }

    @Test func everyRoleHasADistinctName() {
        let names = EntityRole.allCases.map { theme.displayName(for: $0) }
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func colourHelpers() {
        #expect(RGB(hex: 0xFF8000) == RGB(1, 128.0 / 255, 0))
        #expect(RGB(0, 0, 0).lightened(1) == RGB(1, 1, 1))
        #expect(theme.shape(for: .player).recoloured(RGB(1, 0, 0)).strokes.allSatisfy { $0.color == RGB(1, 0, 0) })
    }

    @Test func aThemeWithoutSoundsIsSilentAndTheFirstThemeNamesItsPatches() {
        struct Plain: Theme {
            let base = AlienFrontier()
            var name: String { "Plain" }
            var palette: Palette { base.palette }
            var terrain: TerrainStyle { base.terrain }
            func shape(for role: EntityRole) -> ShapeDescription { base.shape(for: role) }
            func displayName(for role: EntityRole) -> String { base.displayName(for: role) }
        }
        #expect(Plain().sound(for: .extraLife) == nil)
        #expect(theme.sound(for: .extraLife)?.name == "frontier.life.extra")
        #expect(theme.sound(for: .extraLife)?.layers.isEmpty == false)
    }
}
