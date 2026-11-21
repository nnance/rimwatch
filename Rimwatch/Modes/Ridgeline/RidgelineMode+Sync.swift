import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

// Ridgeline's per-entity node sync: one sprite per entity, kept in step with the simulation.

extension RidgelineMode {
    func removeAllEntityNodes() {
        playerNode?.removeFromParent()
        playerNode = nil
        for node in enemyNodes.values { node.removeFromParent() }
        for node in colonistNodes.values { node.removeFromParent() }
        for node in projectileNodes.values { node.removeFromParent() }
        for line in telegraphLines.values { line.removeFromParent() }
        for line in links.values { line.removeFromParent() }
        enemyNodes.removeAll()
        colonistNodes.removeAll()
        projectileNodes.removeAll()
        telegraphLines.removeAll()
        links.removeAll()
        mineOwners.removeAll()
        trailPositions.removeAll()
        catchBeams.removeAll()
        lastDrillSpark.removeAll()
        multiplierShown = 0
        multiplierLabel.isHidden = true
    }

    /// Gives a sprite the texture for a role and tint, if it doesn't have it already.
    func dress(_ sprite: EntitySprite, as role: EntityRole, tint: RGB? = nil) {
        guard sprite.texture == nil || sprite.role != role || sprite.tint != tint else { return }
        sprite.role = role
        sprite.tint = tint
        factory.apply(glyphs.glyph(for: role, tint: tint, pointsPerUnit: pointsPerUnit), to: sprite)
    }

    func makeSprite(_ role: EntityRole, z: CGFloat) -> EntitySprite {
        let sprite = EntitySprite()
        sprite.zPosition = z
        dress(sprite, as: role)
        entityLayer.addChild(sprite)
        return sprite
    }

    /// Positions a node at a world point and hides it when it is well off screen.
    func place(_ node: SKNode, at pos: Vec2, margin: Double = 60) {
        let dx = world.delta(from: cameraX, to: pos.x)
        node.isHidden = abs(dx) > halfWidth + margin
        node.position = CGPoint(x: dx, y: pos.y)
    }

    /// Generic create / update / remove pass over a list of entities, keyed by id.
    func syncNodes<Entity: Identifiable>(
        _ nodes: inout [Int: EntitySprite],
        with entities: [Entity],
        include: (Entity) -> Bool = { _ in true },
        make: (Entity) -> EntitySprite,
        update: (Entity, EntitySprite) -> Void
    ) where Entity.ID == Int {
        var seen = Set<Int>()
        seen.reserveCapacity(entities.count)
        for entity in entities where include(entity) {
            seen.insert(entity.id)
            let node = nodes[entity.id] ?? {
                let made = make(entity)
                nodes[entity.id] = made
                return made
            }()
            update(entity, node)
        }
        for (id, node) in nodes where !seen.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    /// Draws (or updates) a thin line between two world points, keyed by `key`. Lines not
    /// touched in a frame are removed by `sync`.
    func link(_ key: String, from a: Vec2, to b: Vec2, color: RGB, alpha: CGFloat, width: CGFloat = 1.2,
                      seen: inout Set<String>) {
        seen.insert(key)
        let line = links[key] ?? {
            let line = SKSpriteNode(color: color.uiColor(), size: CGSize(width: 1, height: 1))
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            linkLayer.addChild(line)
            links[key] = line
            return line
        }()
        let ax = world.delta(from: cameraX, to: a.x)
        let dx = world.delta(from: a.x, to: b.x)
        let dy = b.y - a.y
        let bx = ax + dx
        line.isHidden = (ax < -halfWidth - 40 && bx < -halfWidth - 40) || (ax > halfWidth + 40 && bx > halfWidth + 40)
        line.position = CGPoint(x: ax, y: a.y)
        line.size = CGSize(width: max(hypot(dx, dy), 0.1), height: width / pointsPerUnit)
        line.zRotation = CGFloat(atan2(dy, dx))
        line.color = color.uiColor()
        line.alpha = alpha
    }

    func sync(_ dt: Double, screen: FlowScreen) {
        guard pointsPerUnit > 0 else { return }
        let sim = session.simulation
        // The lights go down over a second and come back over a little more.
        blackoutMix += ((sim.isBlackout ? 1 : 0) - blackoutMix) * min(dt * (sim.isBlackout ? 2.2 : 1.6), 1)
        if abs(blackoutMix - (sim.isBlackout ? 1 : 0)) < 0.01 { blackoutMix = sim.isBlackout ? 1 : 0 }
        terrain.update(cameraX: cameraX, halfWidth: halfWidth, integrity: sim.outpostIntegrity,
                       blackout: blackoutMix, time: clock)
        starLayer.alpha = CGFloat(1 - 0.75 * blackoutMix)
        effects.update(cameraX: cameraX, halfWidth: halfWidth, elapsed: dt)
        syncPlayer(sim.player)
        if sim.player.isAlive, screen == .playing {
            let p = sim.player
            let tail = Vec2(world.wrap(p.pos.x - p.facing * 14), p.pos.y)
            effects.exhaust(at: tail, thrust: lastInput.move, shipVelocity: p.vel, facing: p.facing,
                            color: p.isOverheated ? theme.palette.warning : theme.palette.shield, elapsed: dt)
        }

        let palette = theme.palette
        let player = sim.player
        var telegraphing = Set<Int>()
        var seenLinks = Set<String>()
        enemyPositions.removeAll(keepingCapacity: true)
        enemyVelocities.removeAll(keepingCapacity: true)
        for enemy in sim.enemies {
            enemyPositions[enemy.id] = enemy.pos
            enemyVelocities[enemy.id] = enemy.vel
        }

        syncNodes(&enemyNodes, with: sim.enemies, make: { makeSprite(.enemy($0.kind), z: 3) }) { enemy, node in
            place(node, at: enemy.pos)
            if updateEnemy(enemy, node, player: player, dt: dt) { telegraphing.insert(enemy.id) }
            switch (enemy.kind, enemy.state) {
            case (.harvester, .lifting(let colonistID)):
                // The grip: a flickering beam from the pod down to the colonist.
                if let colonist = sim.colonists.first(where: { $0.id == colonistID }) {
                    link("grip-\(enemy.id)", from: enemy.pos, to: colonist.pos, color: palette.warning,
                         alpha: 0.35 + 0.35 * CGFloat(abs(sin(clock * 20))), width: 2, seen: &seenLinks)
                }
            case (.mine, _):
                // The tether back to the Sower that laid it, fading with distance.
                if let owner = mineOwners[enemy.id], let sower = enemyPositions[owner] {
                    let distance = world.distance(enemy.pos, sower)
                    if distance < 520 {
                        link("tether-\(enemy.id)", from: enemy.pos, to: sower, color: color(of: .enemy(.sower)),
                             alpha: CGFloat(0.3 * (1 - distance / 520)), width: 1, seen: &seenLinks)
                    }
                }
            case (.anchor, .descending(let outpostID)):
                // Homing on its target: a faint plumb line down to the outpost.
                let outpost = world.outposts[outpostID]
                if abs(world.delta(from: enemy.pos.x, to: outpost.x)) < 220 {
                    link("anchor-\(enemy.id)", from: enemy.pos, to: Vec2(outpost.x, outpost.groundY),
                         color: palette.warning, alpha: 0.18 + 0.12 * CGFloat(abs(sin(clock * 6))), width: 1,
                         seen: &seenLinks)
                }
            case (.anchor, .drilling):
                // Sparks fly from the drill bit.
                if isOnScreen(enemy.pos, margin: 40), clock - (lastDrillSpark[enemy.id] ?? 0) > 0.16 {
                    lastDrillSpark[enemy.id] = clock
                    effects.burst(at: Vec2(enemy.pos.x, enemy.pos.y - enemy.radius), color: palette.spark,
                                  count: 3, speed: 70, life: 0.3)
                }
            default:
                break
            }
        }
        for (id, line) in telegraphLines where !telegraphing.contains(id) {
            line.removeFromParent()
            telegraphLines[id] = nil
        }
        for id in lastDrillSpark.keys where enemyPositions[id] == nil { lastDrillSpark[id] = nil }
        for id in mineOwners.keys where enemyPositions[id] == nil { mineOwners[id] = nil }

        // Carried colonists trail behind the ship in a short line, easing into place.
        var trailTargets: [Int: Vec2] = [:]
        if player.isAlive {
            for (slot, id) in player.carried.enumerated() {
                let s = Double(slot)
                let x = world.wrap(player.pos.x - player.facing * (20 + 13 * s))
                // Never below the ground line, however low the ship flies.
                trailTargets[id] = Vec2(x, max(player.pos.y - 13 - 3 * s, world.groundHeight(at: x) + 1))
            }
        }
        let ease = 1 - exp(-10 * dt)
        syncNodes(&colonistNodes, with: sim.colonists, include: { $0.state != .lost },
                  make: { _ in makeSprite(.colonist, z: 2) }) { colonist, node in
            let tint: RGB? = switch colonist.state {
            case .held: palette.warning
            case .falling: palette.falling
            default: nil
            }
            dress(node, as: .colonist, tint: tint)
            // Drawn with normal blending, so a colonist over an outpost pad stays a figure, not a
            // white blob.
            node.blendMode = .alpha
            // A colonist in trouble flashes for attention.
            node.alpha = tint == nil ? 1 : (sin(clock * 18) > 0 ? 1 : 0.45)
            var pos = colonist.pos
            if let target = trailTargets[colonist.id] {
                let current = trailPositions[colonist.id] ?? colonist.pos
                let x = world.wrap(current.x + world.delta(from: current.x, to: target.x) * ease)
                pos = Vec2(x, max(current.y + (target.y - current.y) * ease, world.groundHeight(at: x) + 1))
                if let beam = catchBeams[colonist.id] {
                    let t = (clock - beam.at) / Self.catchPull
                    if t >= 1 {
                        catchBeams[colonist.id] = nil
                    } else {
                        // Eased from the catch point toward the ship, with a bright beam between.
                        let eased = t * t * (3 - 2 * t)
                        let bx = world.wrap(beam.from.x + world.delta(from: beam.from.x, to: pos.x) * eased)
                        pos = Vec2(bx, beam.from.y + (pos.y - beam.from.y) * eased)
                        link("beam-\(colonist.id)", from: player.pos, to: Vec2(pos.x, pos.y + 8),
                             color: color(of: .colonist), alpha: CGFloat(0.9 - 0.6 * t), width: 2.5, seen: &seenLinks)
                    }
                }
                trailPositions[colonist.id] = pos
                link("tow-\(colonist.id)", from: player.pos, to: Vec2(pos.x, pos.y + 12), color: color(of: .colonist),
                     alpha: 0.3, width: 1, seen: &seenLinks)
            } else {
                trailPositions[colonist.id] = nil
            }
            place(node, at: pos)
        }
        syncNodes(&projectileNodes, with: sim.projectiles,
                  make: { makeSprite(.projectile($0.owner), z: 4) }) { shot, node in
            place(node, at: shot.pos, margin: 20)
            switch shot.owner {
            case .player: node.xScale = shot.vel.x < 0 ? -1 : 1
            case .enemy: node.zRotation += CGFloat(dt * 8)
            }
        }
        for (key, line) in links where !seenLinks.contains(key) {
            line.removeFromParent()
            links[key] = nil
        }

        // The carry multiplier rides with the ship once it is worth something.
        let multiplier = player.isAlive ? player.carried.count : 0
        if multiplier >= 2 {
            if multiplier != multiplierShown {
                let (texture, size) = GlowText.texture("×\(multiplier)",
                                                       style: GlowText.Style(size: 17, weight: .bold, tracking: 0.04),
                                                       color: palette.falling)
                multiplierLabel.texture = texture
                multiplierLabel.size = size
                multiplierLabel.blendMode = .add
            }
            multiplierLabel.isHidden = false
            multiplierLabel.setScale((1 + 0.08 * CGFloat(sin(clock * 6))) / pointsPerUnit)
            multiplierLabel.position = CGPoint(x: world.delta(from: cameraX, to: player.pos.x), y: player.pos.y + 26)
        } else {
            multiplierLabel.isHidden = true
        }
        multiplierShown = multiplier

        controls.setAvailable(.blink, player.isAlive && player.blinkCooldown <= 0)
        controls.setAvailable(.shockwave, player.isAlive && player.shockwaves > 0)
        controls.setAvailable(.fire, player.isAlive && !player.isOverheated)
        let readout = HUDReadout(sim)
        controls.setStatus(TouchControls.Status(heat: readout.heat, isOverheated: readout.isOverheated,
                                                blinkReadiness: readout.blinkReadiness,
                                                shockwaves: readout.shockwaves, maxShockwaves: readout.maxShockwaves),
                           time: clock)
    }

    func syncPlayer(_ player: Player) {
        let node = playerNode ?? {
            let made = makeSprite(.player, z: 5)
            let ring = SKSpriteNode()
            factory.apply(factory.glyph(key: "shield-ring", shape: ShapeDescription(scale: 24, strokes: [
                ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: theme.palette.shield),
            ]), pointsPerUnit: pointsPerUnit), to: ring)
            made.addChild(ring)
            made.accessory = ring
            playerNode = made
            return made
        }()
        node.isHidden = !player.isAlive
        guard player.isAlive else { return }
        node.position = CGPoint(x: world.delta(from: cameraX, to: player.pos.x), y: player.pos.y)
        node.xScale = player.facing < 0 ? -1 : 1
        node.zRotation = CGFloat(player.vel.y / tuning.verticalSpeed * 0.18 * player.facing)

        let invulnerable = player.invulnerableTimer > 0
        // Invulnerable: the hull strobes and the shield ring pulses. A charged shield shows a
        // steady ring that breathes gently.
        node.alpha = invulnerable ? (sin(clock * 38) > 0 ? 1 : 0.3) : 1
        if let ring = node.accessory {
            ring.isHidden = !invulnerable && player.shield < 1
            ring.alpha = invulnerable ? 0.5 + 0.4 * CGFloat(sin(clock * 12)) : 0.4 + 0.15 * CGFloat(sin(clock * 3))
        }
    }

    /// Dresses and poses an enemy. Returns true if it is a Lancer showing its charge line.
    @discardableResult
    func updateEnemy(_ enemy: Enemy, _ node: EntitySprite, player: Player, dt: Double) -> Bool {
        let palette = theme.palette
        var tint: RGB?
        var alpha: CGFloat = 1
        var xScale: CGFloat = 1
        var yScale: CGFloat = 1
        var showLine = false
        var lineDirection: CGFloat = 1

        switch enemy.kind {
        case .husk:
            node.zRotation += CGFloat(dt * 4)
        case .mine:
            node.zRotation += CGFloat(dt * 1.5)
            alpha = 0.65 + 0.35 * CGFloat(abs(sin(clock * 4 + Double(enemy.id))))
        case .mote:
            node.zRotation = CGFloat(atan2(enemy.vel.y, enemy.vel.x))
        case .brood:
            // The sac breathes; it swells harder once it has been hit.
            let tense = enemy.hp < tuning.stats(for: .brood).hp
            let breathe = CGFloat(sin(clock * (tense ? 9 : 3) + Double(enemy.id))) * (tense ? 0.09 : 0.05)
            xScale = 1 + breathe
            yScale = 1 - breathe
        case .lancer:
            let towardPlayer: CGFloat = world.delta(from: enemy.pos.x, to: player.pos.x) >= 0 ? 1 : -1
            switch enemy.state {
            case .telegraphing:
                // Winding up: turns red, strobes, and shows the line it will charge along.
                tint = palette.warning
                xScale = towardPlayer
                alpha = sin(clock * 30) > 0 ? 1 : 0.5
                showLine = true
                lineDirection = towardPlayer
            case .charging:
                xScale = enemy.vel.x < 0 ? -1.3 : 1.3
            case .recovering:
                xScale = enemy.vel.x < 0 ? -1 : 1
                alpha = 0.45
            default:
                xScale = enemy.vel.x < 0 ? -1 : 1
            }
        case .anchor:
            if case .drilling = enemy.state {
                node.position.x += CGFloat.random(in: -0.8...0.8)
                tint = sin(clock * 10) > 0 ? nil : palette.warning
            }
        case .harvester:
            if case .lifting = enemy.state { tint = sin(clock * 8) > 0 ? nil : palette.warning }
        case .sower:
            break
        }

        dress(node, as: .enemy(enemy.kind), tint: tint)
        node.alpha = alpha
        // The hit pulse multiplies the scale, so facing and the charge stretch survive it.
        let pulse = hitPulse(node)
        node.xScale = xScale * pulse
        node.yScale = yScale * pulse
        if enemy.kind != .husk, enemy.kind != .mine, enemy.kind != .mote { node.zRotation = 0 }

        guard showLine else { return false }
        let line = telegraphLines[enemy.id] ?? {
            let line = SKSpriteNode(color: palette.warning.uiColor(), size: .zero)
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            line.zPosition = 2.5
            entityLayer.addChild(line)
            telegraphLines[enemy.id] = line
            return line
        }()
        // The line starts just ahead of the Lancer and runs the length of the charge. It is shown
        // whenever any part of it crosses the view, even with the Lancer itself off screen.
        let length = tuning.lancerChargeSpeed * tuning.lancerChargeTime
        let start = world.delta(from: cameraX, to: enemy.pos.x) + 20 * Double(lineDirection)
        let end = start + length * Double(lineDirection)
        let visible = max(start, end) > -halfWidth && min(start, end) < halfWidth
        line.isHidden = !visible
        line.size = CGSize(width: length, height: 1.5 / pointsPerUnit)
        line.position = CGPoint(x: start, y: enemy.pos.y)
        line.xScale = lineDirection
        line.alpha = 0.3 + 0.3 * CGFloat(abs(sin(clock * 15)))
        return true
    }

    func hitPulse(_ node: EntitySprite) -> CGFloat {
        guard let hitAt = node.hitAt else { return 1 }
        let t = clock - hitAt
        if t < Self.hitRise { return 1 + CGFloat(Self.hitPulse * t / Self.hitRise) }
        if t < Self.hitRise + Self.hitFall {
            return 1 + CGFloat(Self.hitPulse * (1 - (t - Self.hitRise) / Self.hitFall))
        }
        node.hitAt = nil
        return 1
    }
}
