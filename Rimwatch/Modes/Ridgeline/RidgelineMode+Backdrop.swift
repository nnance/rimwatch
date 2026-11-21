import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

// Ridgeline's ground, sky and title backdrop.

extension RidgelineMode {
    /// Swaps in terrain for the current run's world.
    func replaceTerrain() {
        terrain.removeFromParent()
        terrain = TerrainNode(world: world, glyphs: glyphs)
        worldLayer.addChild(terrain)
        effects.world = world
        if pointsPerUnit > 0 {
            // Normally the ground for this run was drawn in the background while the last one
            // was on (see prepareNextTerrain); drawing it here would stall the first frames.
            let ready = preparedTerrain.flatMap { $0.seed == session.runSeed ? $0.art : nil }
            terrain.rebuild(pointsPerUnit: pointsPerUnit, screenScale: services.geometry.screenScale, prepared: ready)
            preparedTerrain = nil
        }
        prepareNextTerrain()
    }

    /// SpriteKit builds a render pipeline the first time it draws each kind of node (tinted
    /// additive sprites, alpha-blended plates, stroked shapes...), and hidden nodes never do.
    /// Draw one of each, almost invisibly, for a moment while a menu is up, so the first frame of
    /// play doesn't pay for them.
    func warmRenderer() {
        let warm = SKNode()
        warm.alpha = 0.02
        warm.zPosition = -1
        warm.position = CGPoint(x: 4, y: 4)
        let palette = theme.palette
        var sprites: [SKNode] = []
        for (role, blend) in [(EntityRole.player, SKBlendMode.add), (.colonist, .alpha), (.enemy(.harvester), .add)] {
            let sprite = SKSpriteNode()
            factory.apply(glyphs.glyph(for: role, pointsPerUnit: pointsPerUnit), to: sprite)
            sprite.blendMode = blend
            sprites.append(sprite)
        }
        let tinted = SKSpriteNode()
        factory.apply(glyphs.glyph(for: .player, pointsPerUnit: pointsPerUnit), to: tinted)
        tinted.blendMode = .add
        tinted.color = palette.shield.uiColor()
        tinted.colorBlendFactor = 1
        sprites.append(tinted)
        let flat = SKSpriteNode(color: palette.warning.uiColor(), size: CGSize(width: 4, height: 4))
        flat.blendMode = .add
        sprites.append(flat)
        let plate = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 4))
        plate.blendMode = .alpha
        sprites.append(plate)
        let ring = SKShapeNode(circleOfRadius: 3)
        ring.strokeColor = palette.shield.uiColor()
        ring.fillColor = .clear
        ring.blendMode = .add
        sprites.append(ring)
        let text = GlowText.sprite("+150", style: .item(12), color: palette.falling)
        sprites.append(text)
        for node in sprites {
            node.setScale(0.2)
            warm.addChild(node)
        }
        root.addChild(warm)
        warm.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    /// Draws the ground for the next run in the background. The next run's seed is known in
    /// advance, so starting it only swaps in textures that are already made and uploaded.
    func prepareNextTerrain() {
        guard pointsPerUnit > 0 else { return }
        let seed = session.nextRunSeed
        let ppu = pointsPerUnit
        if let ready = preparedTerrain, ready.seed == seed, ready.art.pointsPerUnit == ppu { return }
        if let pending = preparingTerrain, pending.seed == seed, pending.ppu == ppu { return }
        preparingTerrain = (seed, ppu)
        let tuning = session.tuning
        let style = theme.terrain
        let scale = services.geometry.screenScale
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let art = TerrainArt.render(world: World(tuning: tuning, seed: seed), style: style,
                                        pointsPerUnit: ppu, screenScale: scale)
            let prepared = PreparedTerrain(art)
            prepared.preload {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.preparingTerrain?.seed == seed, self.preparingTerrain?.ppu == ppu else {
                            return
                        }
                        self.preparingTerrain = nil
                        self.preparedTerrain = (seed, prepared)
                    }
                }
            }
        }
    }

    func makeStars() {
        var rng = SeededRNG(seed: 42)
        // Far: many, faint and nearly still. Mid: the old field. Near: a few brighter motes.
        let layers: [(count: Int, depth: CGFloat, size: CGFloat, alpha: ClosedRange<Double>)] = [
            (70, 0.04, 1.2, 0.12...0.4), (40, 0.12, 1.6, 0.25...0.65), (14, 0.45, 2.4, 0.35...0.8),
        ]
        for layer in layers {
            for _ in 0..<layer.count {
                let node = SKSpriteNode(color: theme.palette.stars.uiColor(),
                                        size: CGSize(width: layer.size, height: layer.size))
                node.alpha = CGFloat(rng.range(layer.alpha))
                node.blendMode = .add
                starLayer.addChild(node)
                stars.append((CGFloat(rng.range(0...1)), CGFloat(rng.range(0.12...1)), layer.depth, node))
            }
        }
    }

    /// Distant mountains: a periodic ridge line, filled black below so the stars sit behind it.
    func buildRidges(playHeight: CGFloat) {
        ridges.forEach { $0.removeFromParent() }
        ridges = []
        guard playHeight > 0, size.width > 0 else { return }
        ridgeSpan = size.width * 2
        var rng = SeededRNG(seed: 77)
        let waves: [(amplitude: CGFloat, cycles: CGFloat, phase: CGFloat)] = [(0.07, 3, 0), (0.04, 7, 0), (0.02, 17, 0)]
            .map { ($0.0, $0.1, CGFloat(rng.range(0...(2 * .pi)))) }
        let base = playHeight * 0.3
        let line = CGMutablePath()
        let steps = 160
        for i in 0...steps {
            let x = ridgeSpan * CGFloat(i) / CGFloat(steps)
            var y = base
            for w in waves { y += w.amplitude * playHeight * sin(2 * .pi * w.cycles * x / ridgeSpan + w.phase) }
            if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        // The fill (no outline, so its sides never show) hides the stars behind the mountains;
        // only the open ridge line is stroked.
        let fill = CGMutablePath()
        fill.addPath(line)
        fill.addLine(to: CGPoint(x: ridgeSpan, y: 0))
        fill.addLine(to: CGPoint(x: 0, y: 0))
        fill.closeSubpath()
        for _ in 0..<2 {
            let ridge = SKShapeNode(path: fill)
            ridge.fillColor = .black
            ridge.strokeColor = .clear
            ridge.lineWidth = 0
            ridge.zPosition = 1
            let edge = SKShapeNode(path: line)
            edge.strokeColor = theme.terrain.strata.uiColor(alpha: 0.3)
            edge.lineWidth = 1
            ridge.addChild(edge)
            starLayer.addChild(ridge)
            ridges.append(ridge)
        }
    }

    // MARK: Title backdrop

    /// A few craft gliding over the drifting terrain behind the title. Purely decorative: they
    /// are animated here and have nothing to do with a simulation.
    func buildDecor() {
        for decor in decorNodes { decor.sprite.removeFromParent() }
        decorNodes = []
        let cast: [(EntityRole, Double, Double)] = [
            (.player, 0.0, 1.0), (.enemy(.harvester), 1.9, 0.55), (.enemy(.sower), 3.7, 0.4),
            (.enemy(.lancer), 5.1, 0.8), (.enemy(.brood), 2.6, 0.3),
        ]
        for (role, phase, speed) in cast {
            let sprite = SKSpriteNode()
            factory.apply(glyphs.glyph(for: role, pointsPerUnit: pointsPerUnit), to: sprite)
            sprite.alpha = 0.55
            decorLayer.addChild(sprite)
            decorNodes.append((sprite, role, phase, speed))
        }
    }

    func updateBackdrop(_ dt: Double) {
        let previous = cameraX
        cameraX = world.wrap(cameraX + Self.titleDrift * dt)
        starScroll += CGFloat(world.delta(from: previous, to: cameraX)) * pointsPerUnit
        placeStars()
        terrain.update(cameraX: cameraX, halfWidth: halfWidth,
                       integrity: Array(repeating: 1, count: world.outposts.count), blackout: 0, time: clock)
        let span = halfWidth * 2 + 200
        for decor in decorNodes {
            // Each crosses the screen on its own slow loop, bobbing gently.
            let travel = (clock * 60 * decor.speed + decor.phase * 400).truncatingRemainder(dividingBy: span)
            let direction: Double = decor.phase.truncatingRemainder(dividingBy: 2) < 1 ? 1 : -1
            let x = direction * (travel - span / 2)
            // Low over the ground, below the title text and the menu.
            let ground = world.groundHeight(at: world.wrap(cameraX + x))
            let y = ground + 34 + 14 * sin(clock * 0.4 + decor.phase * 2) + decor.phase * 5
            decor.sprite.position = CGPoint(x: x, y: y)
            decor.sprite.xScale = CGFloat(direction)
        }
    }
}
