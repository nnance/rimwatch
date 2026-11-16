import GameCore
import SpriteKit
import UIKit

/// The scanner: the whole wraparound world in a strip in the top band. It is centred on the
/// camera, so the part of the world on screen is always in the middle (marked by a bracket) and
/// the rest wraps round either side; across the seam nothing jumps. Mapping comes from
/// `ScannerProjection` in GameCore.
///
/// Performance: the terrain silhouette is drawn once per world and size and shown as two copies
/// that slide inside a crop; marks are pooled sprites that are moved, recoloured and hidden, never
/// created per frame (a pool only grows when more things exist than ever before). During a
/// Blackout everything is hidden behind static.
@MainActor
final class ScannerNode: SKNode {
    private let theme: any Theme
    private let factory: GlowShapeFactory

    private var rect: CGRect = .zero
    private var inner: CGRect = .zero
    private var builtWorldKey = ""
    private var builtRectKey = ""

    private var frameSprite: SKSpriteNode?
    private let crop = SKCropNode()
    private let terrainA = SKSpriteNode()
    private let terrainB = SKSpriteNode()
    private let marks = SKNode()
    private let bracketLeft = SKSpriteNode()
    private let bracketRight = SKSpriteNode()
    private let playerMark = SKSpriteNode()
    private var outpostMarks: [SKSpriteNode] = []
    private var enemyMarks: [SKSpriteNode] = []
    private var colonistMarks: [SKSpriteNode] = []
    private var outpostTextures: [ScannerMark.OutpostMark: GlowShapeFactory.Glyph] = [:]

    private let staticLayer = SKNode()
    private var staticDots: [SKSpriteNode] = []
    private let noSignal = SKSpriteNode()
    private var rng = SeededRNG(seed: 99)

    private var markSize: CGFloat = 3

    init(theme: any Theme, factory: GlowShapeFactory) {
        self.theme = theme
        self.factory = factory
        super.init()
        crop.addChild(terrainA)
        crop.addChild(terrainB)
        crop.maskNode = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
        addChild(crop)
        addChild(marks)
        for sprite in [terrainA, terrainB] {
            sprite.anchorPoint = .zero
            sprite.blendMode = .add
        }
        marks.addChild(bracketLeft)
        marks.addChild(bracketRight)
        playerMark.zPosition = 3
        marks.addChild(playerMark)
        addChild(staticLayer)
        staticLayer.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Lays the scanner out in `rect` (scene coordinates) for `world`. Rebuilds textures only
    /// when the size or the world changed.
    func layout(in rect: CGRect, world: World, worldID: Int) {
        guard rect.width > 40, rect.height > 12 else { return }
        let rectKey = "\(rect)"
        let worldKey = "\(worldID)|\(rectKey)"
        guard rectKey != builtRectKey || worldKey != builtWorldKey else { return }
        let sizeChanged = rectKey != builtRectKey
        builtRectKey = rectKey
        builtWorldKey = worldKey
        self.rect = rect
        position = rect.origin
        inner = CGRect(x: 4, y: 3, width: rect.width - 8, height: rect.height - 6)
        markSize = max(2.5, min(inner.height * 0.085, 5))

        if sizeChanged {
            frameSprite?.removeFromParent()
            let frame = GlowFrame.sprite(size: rect.size, color: theme.palette.hud.scaled(0.55), cut: 5)
            frame.position = CGPoint(x: rect.width / 2, y: rect.height / 2)
            frame.alpha = 0.6
            frame.zPosition = -1
            addChild(frame)
            frameSprite = frame
            if let mask = crop.maskNode as? SKSpriteNode {
                mask.size = inner.size
                mask.anchorPoint = .zero
                mask.position = inner.origin
            }
            buildBrackets()
            buildStatic()
            buildMarkTextures()
        }

        let texture = renderTerrain(world: world, size: inner.size)
        for sprite in [terrainA, terrainB] {
            sprite.texture = texture
            sprite.size = inner.size
        }
        for sprite in outpostMarks { sprite.removeFromParent() }
        outpostMarks = world.outposts.map { _ in
            let sprite = SKSpriteNode()
            sprite.zPosition = 1
            marks.addChild(sprite)
            return sprite
        }
    }

    /// Positions everything for this frame.
    func update(_ sim: Simulation, cameraX: Double, halfWidth: Double, time: TimeInterval) {
        guard !builtRectKey.isEmpty else { return }
        let blackout = sim.isBlackout
        crop.isHidden = blackout
        marks.isHidden = blackout
        staticLayer.isHidden = !blackout
        if blackout {
            updateStatic(time)
            return
        }

        let world = sim.world
        let projection = ScannerProjection(world: world, centerX: cameraX)
        let w = inner.width, h = inner.height
        func point(_ p: Vec2) -> CGPoint {
            CGPoint(x: inner.minX + CGFloat(projection.x(p.x)) * w, y: inner.minY + CGFloat(projection.y(p.y)) * h)
        }

        let originX = inner.minX + CGFloat(projection.originX) * w
        terrainA.position = CGPoint(x: originX, y: inner.minY)
        terrainB.position = CGPoint(x: originX - w, y: inner.minY)

        let visible = projection.visibleRange(halfWidth: halfWidth)
        bracketLeft.position = CGPoint(x: inner.minX + CGFloat(visible.lowerBound) * w, y: inner.midY)
        bracketRight.position = CGPoint(x: inner.minX + CGFloat(visible.upperBound) * w, y: inner.midY)

        let flashOn = sin(time * 12) > 0

        for (id, sprite) in outpostMarks.enumerated() where id < world.outposts.count {
            let outpost = world.outposts[id]
            let integrity = id < sim.outpostIntegrity.count ? sim.outpostIntegrity[id] : 1
            guard case .outpost(let state) = ScannerMark.forOutpost(integrity: integrity),
                  let glyph = outpostTextures[state] else { continue }
            if sprite.texture !== glyph.texture { factory.apply(glyph, to: sprite) }
            sprite.position = point(Vec2(outpost.x, outpost.groundY))
            sprite.alpha = state == .damaged ? (flashOn ? 1 : 0.35) : (state == .destroyed ? 0.6 : 0.7)
        }

        var used = 0
        for enemy in sim.enemies {
            let sprite = pooled(&enemyMarks, used, z: 2)
            used += 1
            var color = color(of: .enemy(enemy.kind))
            var size = markSize
            var alpha: CGFloat = 1
            switch enemy.kind {
            case .mine:
                size *= 0.6
                alpha = 0.6
            case .mote:
                size *= 0.75
            case .brood, .anchor:
                size *= 1.3
            case .lancer:
                if case .telegraphing = enemy.state {
                    color = theme.palette.warning
                    alpha = flashOn ? 1 : 0.4
                    size *= 1.3
                }
            case .harvester:
                if case .lifting = enemy.state { alpha = flashOn ? 1 : 0.5 }
            case .husk, .sower:
                break
            }
            sprite.color = color.uiColor()
            sprite.size = CGSize(width: size, height: size)
            // Hunters show as diamonds, everything else as squares.
            sprite.zRotation = enemy.kind == .husk || enemy.kind == .mote ? .pi / 4 : 0
            sprite.alpha = alpha
            sprite.position = point(enemy.pos)
            sprite.isHidden = false
        }
        for index in used..<enemyMarks.count { enemyMarks[index].isHidden = true }

        used = 0
        for colonist in sim.colonists {
            guard case .colonist(let state) = ScannerMark.forColonist(colonist.state) else { continue }
            // Carried colonists ride with the player mark.
            if state == .carried { continue }
            let sprite = pooled(&colonistMarks, used, z: 1.5)
            used += 1
            let color: RGB = switch state {
            case .held: theme.palette.warning
            case .falling: theme.palette.falling
            default: self.color(of: .colonist)
            }
            sprite.color = color.uiColor()
            sprite.size = CGSize(width: markSize * 0.6, height: markSize * 1.1)
            sprite.alpha = state == .grounded ? 0.85 : (flashOn ? 1 : 0.3)
            var p = point(colonist.pos)
            if state == .grounded { p.y += markSize * 0.55 }
            sprite.position = p
            sprite.isHidden = false
        }
        for index in used..<colonistMarks.count { colonistMarks[index].isHidden = true }

        let player = sim.player
        playerMark.isHidden = !player.isAlive
        playerMark.position = point(player.pos)
        playerMark.xScale = player.facing < 0 ? -1 : 1
    }

    // MARK: Building

    private func color(of role: EntityRole) -> RGB {
        theme.shape(for: role).strokes.first?.color ?? theme.palette.hud
    }

    private func pooled(_ pool: inout [SKSpriteNode], _ index: Int, z: CGFloat) -> SKSpriteNode {
        if index < pool.count { return pool[index] }
        let sprite = SKSpriteNode(color: .white, size: CGSize(width: markSize, height: markSize))
        sprite.blendMode = .add
        sprite.zPosition = z
        marks.addChild(sprite)
        pool.append(sprite)
        return sprite
    }

    private func buildBrackets() {
        let h = Double(inner.height) / 2 + 1
        let arm = 3.0
        let color = theme.palette.hud
        let left = ShapeDescription(scale: 1, strokes: [
            ShapeStroke([Vec2(arm, h), Vec2(0, h), Vec2(0, -h), Vec2(arm, -h)], color: color),
        ])
        let right = ShapeDescription(scale: 1, strokes: [
            ShapeStroke([Vec2(-arm, h), Vec2(0, h), Vec2(0, -h), Vec2(-arm, -h)], color: color),
        ])
        factory.apply(factory.glyph(key: "scanner-bracket-l-\(h)", shape: left, pointsPerUnit: 1), to: bracketLeft)
        factory.apply(factory.glyph(key: "scanner-bracket-r-\(h)", shape: right, pointsPerUnit: 1), to: bracketRight)
        bracketLeft.alpha = 0.7
        bracketRight.alpha = 0.7
    }

    private func buildMarkTextures() {
        // Outposts: a small dome, red when under attack, a flat stub when destroyed.
        let s = Double(markSize) * 0.9
        let dome = ShapeKit.arc(radius: 1, from: 0, to: .pi, segments: 10)
        let base = [Vec2(-1.6, 0), Vec2(1.6, 0)]
        func shape(_ color: RGB, _ intact: Bool) -> ShapeDescription {
            ShapeDescription(scale: s, strokes: intact
                ? [ShapeStroke(dome, color: color), ShapeStroke(base, color: color)]
                : [ShapeStroke(base, color: color), ShapeStroke([Vec2(-0.5, 0), Vec2(-0.2, 0.5)], color: color),
                   ShapeStroke([Vec2(0.4, 0), Vec2(0.6, 0.4)], color: color)])
        }
        outpostTextures = [
            .intact: factory.glyph(key: "scanner-outpost-ok-\(s)", shape: shape(color(of: .outpost).scaled(0.75), true),
                                   pointsPerUnit: 1),
            .damaged: factory.glyph(key: "scanner-outpost-hit-\(s)", shape: shape(theme.palette.warning, true),
                                    pointsPerUnit: 1),
            .destroyed: factory.glyph(key: "scanner-outpost-ruin-\(s)", shape: shape(color(of: .ruin), false),
                                      pointsPerUnit: 1),
        ]
        for sprite in outpostMarks { sprite.texture = nil }

        // The player: a bright arrowhead.
        let p = Double(markSize) * 1.3
        let arrow = ShapeDescription(scale: p, strokes: [
            ShapeStroke([Vec2(1, 0), Vec2(-0.8, 0.6), Vec2(-0.4, 0), Vec2(-0.8, -0.6)], closed: true,
                        color: color(of: .player).lightened(0.3)),
        ])
        factory.apply(factory.glyph(key: "scanner-player-\(p)", shape: arrow, pointsPerUnit: 1), to: playerMark)
    }

    private func buildStatic() {
        staticLayer.removeAllChildren()
        staticDots = []
        for _ in 0..<44 {
            let dot = SKSpriteNode(color: theme.palette.hud.uiColor(), size: CGSize(width: 2, height: 1))
            dot.blendMode = .add
            staticLayer.addChild(dot)
            staticDots.append(dot)
        }
        let size = max(8, min(inner.height * 0.32, 14))
        let (texture, textureSize) = GlowText.texture("NO SIGNAL", style: .item(size), color: theme.palette.warning)
        noSignal.texture = texture
        noSignal.size = textureSize
        noSignal.blendMode = .add
        noSignal.position = CGPoint(x: inner.midX, y: inner.midY)
        staticLayer.addChild(noSignal)
    }

    private func updateStatic(_ time: TimeInterval) {
        for dot in staticDots {
            dot.position = CGPoint(x: inner.minX + CGFloat(rng.range(0...1)) * inner.width,
                                   y: inner.minY + CGFloat(rng.range(0...1)) * inner.height)
            dot.xScale = CGFloat(rng.range(1...6))
            dot.alpha = CGFloat(rng.range(0.1...0.6))
        }
        noSignal.alpha = 0.55 + 0.45 * CGFloat(abs(sin(time * 2.5)))
    }

    /// The ground across the whole world, from x = 0, as a dim ridge over a faint wash.
    private func renderTerrain(world: World, size: CGSize) -> SKTexture {
        let samples = max(Int(size.width), 64)
        let style = theme.terrain
        let image = GlowShapeFactory.image(size: size, scale: 2) { context in
            let path = CGMutablePath()
            var points: [CGPoint] = []
            for i in 0...samples {
                let x = Double(i) / Double(samples) * world.width
                let y = world.groundHeight(at: world.wrap(x)) / world.height
                points.append(CGPoint(x: CGFloat(i) / CGFloat(samples) * size.width,
                                      y: size.height - CGFloat(y) * size.height))
            }
            // A fainter stratum just below the ridge gives the ground some body.
            let stratum = CGMutablePath()
            stratum.addLines(between: points.map { CGPoint(x: $0.x, y: min($0.y + 3, size.height - 0.5)) })
            context.setLineJoin(.round)
            context.setStrokeColor(style.strata.cgColor(alpha: 0.7))
            context.setLineWidth(0.8)
            context.addPath(stratum)
            context.strokePath()
            path.addLines(between: points)
            context.setLineJoin(.round)
            context.setShadow(offset: .zero, blur: 3, color: style.ridge.cgColor(alpha: 0.8))
            context.setStrokeColor(style.ridge.cgColor(alpha: 0.75))
            context.setLineWidth(1)
            context.addPath(path)
            context.strokePath()
        }
        return SKTexture(image: image)
    }
}
