import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

// Ridgeline's camera and its events turned into visuals.

extension RidgelineMode {
    func updateCamera(_ dt: Double) {
        let player = session.simulation.player
        let target = world.wrap(player.pos.x + player.facing * halfWidth * 2 * Self.lookAhead)
        let previous = cameraX
        cameraX = world.wrap(cameraX + world.delta(from: cameraX, to: target) * (1 - exp(-2.5 * dt)))
        // Never let the ship slip off screen, however fast it flies.
        let limit = halfWidth * 0.7
        let offset = world.delta(from: cameraX, to: player.pos.x)
        if offset > limit { cameraX = world.wrap(player.pos.x - limit) }
        if offset < -limit { cameraX = world.wrap(player.pos.x + limit) }

        // Distant stars drift slowly against the camera.
        starScroll += CGFloat(world.delta(from: previous, to: cameraX)) * pointsPerUnit
        placeStars()

        // Shake moves only the world, never the HUD, and settles in about a third of a second.
        shake *= CGFloat(exp(-9 * dt))
        if shake < 0.2 { shake = 0 }
        let jolt = shake > 0
            ? CGPoint(x: CGFloat.random(in: -1...1) * shake, y: CGFloat.random(in: -1...1) * shake) : .zero
        worldLayer.position = CGPoint(x: size.width / 2 + jolt.x, y: jolt.y)
    }

    /// A jolt for a big moment, in points. Restrained, and nothing with Reduce Motion on.
    func addShake(_ amount: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        shake = min(max(shake, amount), 8)
    }

    /// A bright line that crosses the playfield: a wave arriving, the power coming back.
    func sweepAcross(_ color: RGB, duration: TimeInterval = 0.7) {
        let playHeight = size.height - bandHeight
        guard playHeight > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        sweep.removeAllActions()
        sweep.color = color.uiColor()
        sweep.size = CGSize(width: 3, height: playHeight)
        sweep.anchorPoint = CGPoint(x: 0.5, y: 0)
        sweep.position = CGPoint(x: -10, y: 0)
        sweep.alpha = 0.7
        sweep.isHidden = false
        let move = SKAction.moveTo(x: size.width + 10, duration: duration)
        move.timingMode = .easeInEaseOut
        sweep.run(.sequence([.group([move, .sequence([.wait(forDuration: duration * 0.6),
                                                      .fadeOut(withDuration: duration * 0.4)])]),
                             .hide()]))
    }

    func placeStars() {
        let span = size.width * 1.4
        for star in stars {
            var x = (star.u * span - starScroll * star.depth).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            star.node.position.x = x - (span - size.width) / 2
        }
        var offset = (-starScroll * Self.ridgeDepth).truncatingRemainder(dividingBy: ridgeSpan)
        if offset > 0 { offset -= ridgeSpan }
        for (index, ridge) in ridges.enumerated() {
            ridge.position = CGPoint(x: offset + CGFloat(index) * ridgeSpan, y: 0)
        }
    }

    // MARK: Events

    func color(of role: EntityRole) -> RGB {
        theme.shape(for: role).strokes.first?.color ?? theme.palette.spark
    }

    /// Where an event happened, if it has a place.
    func position(of event: GameEvent) -> Vec2? {
        let sim = session.simulation
        func enemy(_ id: Int) -> Vec2? { sim.enemies.first { $0.id == id }?.pos }
        func colonist(_ id: Int) -> Vec2? { sim.colonists.first { $0.id == id }?.pos }
        func outpost(_ id: Int) -> Vec2? {
            sim.world.outposts.indices.contains(id) ? Vec2(sim.world.outposts[id].x, sim.world.outposts[id].groundY) : nil
        }
        switch event {
        case .playerFired(let at, _), .shockwave(let at), .playerDestroyed(let at, _), .enemyFired(let at),
             .enemyHit(_, let at), .enemyDestroyed(_, _, let at, _), .huskFormed(_, let at), .mineLaid(_, let at),
             .colonistLost(_, let at):
            return at
        case .playerBlinked(_, let to):
            return to
        case .enemySpawned(let id, _), .lancerTelegraph(let id), .lancerCharged(let id):
            return enemy(id)
        case .anchorLanded(_, let id), .outpostDestroyed(let id), .outpostRestored(let id),
             .colonistDelivered(_, let id, _):
            return outpost(id)
        case .colonistGrabbed(let id), .colonistDropped(let id), .colonistCaught(let id), .colonistLanded(let id):
            return colonist(id)
        case .playerOverheated, .shieldCharged, .shieldBroken, .playerRespawned, .extraLife:
            return sim.player.pos
        case .waveStarted, .waveCleared, .blackoutBegan, .blackoutEnded, .gameOver:
            return nil
        }
    }

    /// Stereo position for an event (-1 at the left edge of the view, 1 at the right) and its
    /// loudness for where it happened: full in view, fading to 30% two screens away.
    func placement(for event: GameEvent) -> (pan: Double, gain: Double) {
        guard let pos = position(of: event), halfWidth > 0 else { return (0, 1) }
        let offset = world.delta(from: cameraX, to: pos.x) / halfWidth
        let beyond = max(abs(offset) - 1, 0)
        return (min(max(offset, -1), 1), max(0.3, 1 - beyond * 0.35))
    }

    func isOnScreen(_ pos: Vec2, margin: Double = 0) -> Bool {
        abs(world.delta(from: cameraX, to: pos.x)) < halfWidth + margin
    }

    /// "◀" or "▶" toward a point off screen, or "" when it is in view.
    func pointer(to pos: Vec2) -> String {
        guard !isOnScreen(pos, margin: -20) else { return "" }
        return world.delta(from: cameraX, to: pos.x) < 0 ? "◀ " : " ▶"
    }

    func pointed(_ text: String, toward pos: Vec2) -> String {
        let arrow = pointer(to: pos)
        if arrow.hasPrefix("◀") { return arrow + text }
        return text + arrow
    }

    func handle(_ events: [GameEvent]) {
        guard !events.isEmpty else { return }
        let palette = theme.palette
        let sim = session.simulation
        let tuning = session.tuning
        var delivered: (count: Int, points: Int, outpost: Int)?

        for event in events {
            switch event {
            // Waves
            case .waveStarted(let wave):
                sweepAcross(theme.terrain.ridge)
                callouts.banner("WAVE \(wave)", subtitle: "\(sim.survivingColonists) colonists to protect",
                                color: theme.terrain.ridge)
            case .waveCleared(let wave, let bonus):
                callouts.banner("WAVE \(wave) CLEAR",
                                subtitle: bonus > 0 ? "Survivor bonus +\(groupedDigits(bonus))" : "No survivors",
                                color: palette.hud, subtitleColor: bonus > 0 ? palette.falling : palette.warning)
                hud.flash(.score, at: clock)

            // The ship
            case .playerFired:
                break
            case .playerOverheated:
                callouts.popup("OVERHEAT", at: sim.player.pos, color: palette.warning, scale: 0.9)
                hud.flash(.heat, at: clock)
            case .playerBlinked(let from, let to):
                // A streak, fading afterimages along it, and a pop of sparks at each end.
                effects.trail(from: from, to: to, color: palette.shield, width: 3.5)
                effects.afterimages(of: glyphs.glyph(for: .player, pointsPerUnit: pointsPerUnit), from: from, to: to,
                                    facing: sim.player.facing, color: palette.shield)
                effects.ring(at: to, color: palette.shield, radius: 38, duration: 0.25)
                effects.emit(at: from, EffectsLayer.Emission(count: 10, color: palette.shield, speed: 40...120, life: 0.2...0.35))
                effects.emit(at: to, EffectsLayer.Emission(count: 14, color: palette.shield.lightened(0.4), speed: 90...220,
                                               life: 0.2...0.4))
            case .shockwave(let at):
                // A double ring, a flat blast of sparks racing out, a white flash and a jolt.
                effects.ring(at: at, color: palette.shield, radius: tuning.shockwaveRange, duration: 0.8, width: 2)
                effects.ring(at: at, color: palette.shield.lightened(0.5), radius: tuning.shockwaveRange * 0.6,
                             duration: 0.5, width: 1.4)
                effects.emit(at: at, EffectsLayer.Emission(count: 64, color: palette.shield.lightened(0.3),
                                               speed: 450...800, life: 0.5...0.8, drag: 1.2, size: 1.2...1.8))
                effects.emit(at: at, EffectsLayer.Emission(count: 24, color: RGB(1, 1, 1), look: .dot, speed: 60...220,
                                               life: 0.5...0.8, size: 1.2...2))
                callouts.flash(palette.shield, strength: 0.3)
                addShake(6)
                hud.flash(.shockwaves, at: clock)
            case .shieldCharged:
                effects.ring(at: sim.player.pos, color: palette.shield, radius: 44, duration: 0.5)
                callouts.popup("SHIELD READY", at: sim.player.pos, color: palette.shield, scale: 0.95, life: 1.2)
                hud.flash(.shield, at: clock)
            case .shieldBroken:
                effects.ring(at: sim.player.pos, color: palette.shield, radius: 60)
                effects.emit(at: sim.player.pos, EffectsLayer.Emission(count: 16, color: palette.shield, look: .shard, speed: 80...200,
                                                           life: 0.4...0.6, drag: 2))
                addShake(3)
                callouts.popup("SHIELD DOWN", at: sim.player.pos, color: palette.warning, scale: 0.95, life: 1.1)
                callouts.flash(palette.shield, strength: 0.15)
                hud.flash(.shield, at: clock)
            case .playerDestroyed(let at, _):
                // The hull breaks into tumbling pieces inside a hot burst, with a slow ring.
                let hull = color(of: .player)
                effects.emit(at: at, EffectsLayer.Emission(count: 16, color: hull, look: .shard, speed: 60...220, life: 0.8...1.3,
                                               drag: 1.2, gravity: 90, size: 1...1.5))
                effects.emit(at: at, EffectsLayer.Emission(count: 40, color: palette.spark, speed: 120...380, life: 0.4...0.9))
                effects.emit(at: at, EffectsLayer.Emission(count: 14, color: RGB(1, 1, 1), look: .dot, speed: 20...90,
                                               life: 0.5...0.9, size: 1.2...2))
                effects.ring(at: at, color: hull, radius: 90, duration: 0.6)
                effects.ring(at: at, color: palette.warning, radius: 150, duration: 0.9)
                callouts.flash(palette.warning, strength: 0.28, duration: 0.6)
                addShake(7)
                hud.flash(.lives, at: clock)
            case .playerRespawned:
                // Drawn back in: a ring closes on the ship and sparks gather.
                let spot = sim.player.pos
                effects.ring(at: spot, color: color(of: .player), radius: 16, duration: 0.45, inward: true)
                for index in 0..<12 {
                    let angle = Double(index) / 12 * 2 * .pi
                    let from = Vec2(world.wrap(spot.x + cos(angle) * 70), spot.y + sin(angle) * 70)
                    effects.emit(at: from, EffectsLayer.Emission(count: 1, color: color(of: .player), speed: 150...160, life: 0.4...0.42,
                                                     angle: angle + .pi, spread: 0, drag: 0))
                }
            case .extraLife:
                callouts.notice("EXTRA LIFE", color: palette.falling)
                callouts.popup("1UP", at: sim.player.pos, color: palette.falling, life: 1.2)
                hud.flash(.lives, at: clock)

            // Enemies
            case .enemySpawned(let id, let kind):
                // A warp-in ring, if it arrives where it can be seen. Motes hatch in the Brood's burst.
                if kind != .mote, let pos = sim.enemies.first(where: { $0.id == id })?.pos, isOnScreen(pos, margin: 40) {
                    effects.ring(at: pos, color: color(of: .enemy(kind)), radius: 26, duration: 0.35)
                }
            case .enemyFired:
                break
            case .enemyHit(let id, let at):
                effects.emit(at: at, EffectsLayer.Emission(count: 6, color: palette.spark, speed: 60...160, life: 0.15...0.3))
                // The pulse is applied in updateEnemy, on top of facing and charge stretch.
                enemyNodes[id]?.hitAt = clock
            case .enemyDestroyed(let id, let kind, let at, let points):
                let tint = color(of: .enemy(kind))
                explode(kind, id: id, at: at, tint: tint)
                callouts.popup("+\(groupedDigits(points))", at: at, color: tint.lightened(0.35),
                               scale: kind == .mine || kind == .mote ? 0.7 : 0.85, life: 0.75)
                mineOwners[id] = nil
            case .huskFormed(_, let at):
                effects.emit(at: at, EffectsLayer.Emission(count: 20, color: color(of: .enemy(.husk)), speed: 80...240,
                                               life: 0.4...0.7, drag: 3))
                effects.ring(at: at, color: color(of: .enemy(.husk)), radius: 55, duration: 0.5)
                callouts.popup("HUSK", at: at, color: color(of: .enemy(.husk)), scale: 0.9, life: 1.1)
            case .mineLaid(let id, let at):
                effects.ring(at: at, color: color(of: .enemy(.mine)), radius: 16, duration: 0.3)
                // The Sower that laid it is the one sitting on that spot.
                if let sower = sim.enemies
                    .filter({ $0.kind == .sower })
                    .min(by: { world.distance($0.pos, at) < world.distance($1.pos, at) }),
                    world.distance(sower.pos, at) < 30 {
                    mineOwners[id] = sower.id
                }
            case .lancerTelegraph(let id):
                if let pos = sim.enemies.first(where: { $0.id == id })?.pos {
                    effects.ring(at: pos, color: palette.warning, radius: 36, duration: 0.35)
                    callouts.popup("!", at: pos, color: palette.warning, scale: 1.4, life: 0.7, followID: id)
                }
            case .lancerCharged(let id):
                if let lancer = sim.enemies.first(where: { $0.id == id }) {
                    let reach = tuning.lancerChargeSpeed * tuning.lancerChargeTime
                    let direction = lancer.vel.x >= 0 ? 1.0 : -1.0
                    effects.trail(from: lancer.pos, to: Vec2(lancer.pos.x + direction * reach, lancer.pos.y),
                                  color: color(of: .enemy(.lancer)), duration: tuning.lancerChargeTime)
                    effects.burst(at: lancer.pos, color: color(of: .enemy(.lancer)), count: 8, speed: 120, life: 0.3)
                }
            case .anchorLanded(_, let outpostID):
                let outpost = world.outposts[outpostID]
                let spot = Vec2(outpost.x, outpost.groundY)
                effects.burst(at: spot, color: theme.terrain.ridge, count: 14, speed: 110, life: 0.5)
                effects.ring(at: spot, color: palette.warning, radius: 50, duration: 0.45)
                callouts.notice(pointed("OUTPOST UNDER ATTACK", toward: spot), color: palette.warning, life: 2.6)

            // Colonists
            case .colonistGrabbed(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    callouts.popup("HELP!", at: pos, color: palette.warning, scale: 0.8, life: 1.0)
                    if !isOnScreen(pos) {
                        callouts.notice(pointed("COLONIST TAKEN", toward: pos), color: palette.warning)
                    }
                }
            case .colonistDropped(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    callouts.popup("CATCH!", at: pos, color: palette.falling, scale: 0.8, life: 0.9)
                }
            case .colonistCaught(let id):
                effects.ring(at: sim.player.pos, color: color(of: .colonist), radius: 30, duration: 0.3)
                effects.emit(at: sim.player.pos, EffectsLayer.Emission(count: 10, color: color(of: .colonist), look: .dot,
                                                           speed: 30...90, life: 0.4...0.7, angle: .pi / 2,
                                                           spread: 2, drag: 2))
                callouts.popup("+\(tuning.catchPoints)", at: sim.player.pos, color: palette.falling, scale: 0.9)
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    trailPositions[id] = pos
                    // Drawn in on a beam from where it was caught, so the catch radius reads as
                    // a deliberate pull rather than a snap.
                    catchBeams[id] = (from: pos, at: clock)
                }
            case .colonistDelivered(let id, let outpost, let points):
                delivered = (count: (delivered?.count ?? 0) + 1, points: points, outpost: outpost)
                trailPositions[id] = nil
                catchBeams[id] = nil
            case .colonistLanded(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    effects.emit(at: pos, EffectsLayer.Emission(count: 6, color: theme.terrain.ridge, look: .dot, speed: 20...50,
                                                    life: 0.25...0.4, angle: .pi / 2, spread: 2.4, gravity: 120))
                }
            case .colonistLost(let id, let at):
                // A little figure's worth of light falls away and dims to red.
                effects.emit(at: at, EffectsLayer.Emission(count: 12, color: color(of: .colonist), look: .dot, speed: 20...80,
                                               life: 0.6...1, drag: 1, gravity: 140))
                effects.emit(at: at, EffectsLayer.Emission(count: 8, color: palette.warning, speed: 40...120, life: 0.3...0.5))
                effects.ring(at: at, color: palette.warning, radius: 24, duration: 0.35)
                callouts.popup("LOST", at: at, color: palette.warning, scale: 0.8, life: 1.0)
                trailPositions[id] = nil
                catchBeams[id] = nil
                hud.flash(.colonists, at: clock)

            // Outposts and Blackout
            case .outpostDestroyed(let id):
                let outpost = world.outposts[id]
                // The dome blows apart: pieces thrown up that fall back, smoke-coloured sparks.
                let dome = Vec2(outpost.x, outpost.groundY + 10)
                effects.emit(at: dome, EffectsLayer.Emission(count: 22, color: color(of: .outpost), look: .shard, speed: 120...300,
                                                 life: 0.9...1.4, angle: .pi / 2, spread: 2.2, drag: 0.6,
                                                 gravity: 320, size: 1...1.6))
                effects.emit(at: dome, EffectsLayer.Emission(count: 30, color: theme.terrain.ridge, speed: 80...260, life: 0.5...0.9,
                                                 angle: .pi / 2, spread: 3))
                addShake(isOnScreen(dome) ? 6 : 2)
                effects.ring(at: Vec2(outpost.x, outpost.groundY), color: palette.warning, radius: 90, duration: 0.6)
                callouts.notice(pointed("OUTPOST LOST", toward: Vec2(outpost.x, outpost.groundY)),
                                color: palette.warning, life: 2.4)
            case .outpostRestored(let id):
                let outpost = world.outposts[id]
                let ground = Vec2(outpost.x, outpost.groundY)
                effects.emit(at: ground, EffectsLayer.Emission(count: 24, color: color(of: .outpost), look: .dot, speed: 60...180,
                                                   life: 0.6...1, angle: .pi / 2, spread: 1.2, drag: 1.5, gravity: 80))
                // The drop comes straight down from the top of the sky.
                effects.trail(from: Vec2(outpost.x, world.ceiling), to: ground, color: color(of: .outpost), duration: 0.9)
                effects.ring(at: ground, color: color(of: .outpost), radius: 70)
                callouts.notice(pointed("SUPPLY DROP", toward: ground), color: color(of: .outpost), life: 2.4)
            case .blackoutBegan:
                callouts.banner("BLACKOUT", subtitle: "Every colonist lost. Hold out for supplies.",
                                color: palette.warning, life: 2.8)
                callouts.flash(palette.warning, strength: 0.35, duration: 0.9)
                addShake(5)
            case .blackoutEnded:
                sweepAcross(color(of: .outpost), duration: 1.0)
                callouts.banner("POWER RESTORED", subtitle: "Supplies landed", color: color(of: .outpost),
                                life: 2.2)
                callouts.flash(color(of: .outpost), strength: 0.2, duration: 0.6)
            case .gameOver:
                break
            }
        }

        if let delivered, world.outposts.indices.contains(delivered.outpost) {
            // One callout for the whole group brought home: the points and the multiplier.
            let outpost = world.outposts[delivered.outpost]
            let spot = Vec2(outpost.x, outpost.groundY + 30)
            effects.ring(at: Vec2(outpost.x, outpost.groundY), color: color(of: .colonist), radius: 60, duration: 0.5)
            // A fountain of light from the pad, bigger for more colonists.
            effects.emit(at: Vec2(outpost.x, outpost.groundY + 4), EffectsLayer.Emission(count: 12 + 8 * delivered.count,
                                                                           color: color(of: .colonist), look: .dot,
                                                                           speed: 120...260, life: 0.6...1,
                                                                           angle: .pi / 2, spread: 0.7, drag: 1,
                                                                           gravity: 200))
            callouts.popup("+\(groupedDigits(delivered.points * delivered.count))", at: spot,
                           color: palette.falling, scale: 1.25, life: 1.3)
            let note = delivered.count > 1 ? "\(delivered.count) SAVED ×\(delivered.count)" : "SAVED"
            callouts.popup(note, at: spot, color: color(of: .colonist), scale: 0.9, life: 1.3)
        }
    }

    /// Each enemy goes out its own way.
    func explode(_ kind: EnemyKind, id: Int, at: Vec2, tint: RGB) {
        typealias E = EffectsLayer.Emission
        let spark = theme.palette.spark
        switch kind {
        case .harvester:
            // The pod cracks: hull pieces and a burst of green.
            effects.emit(at: at, E(count: 7, color: tint, look: .shard, speed: 60...160, life: 0.5...0.8,
                                   drag: 1.5, gravity: 120))
            effects.emit(at: at, E(count: 14, color: tint, speed: 90...220, life: 0.3...0.55))
        case .husk:
            // A hard, fast star of magenta spikes.
            effects.emit(at: at, E(count: 14, color: tint, speed: 260...420, life: 0.2...0.35, drag: 4,
                                   size: 1.2...1.6))
            effects.ring(at: at, color: tint, radius: 34, duration: 0.25)
        case .sower:
            // Seeds scatter and fall.
            effects.emit(at: at, E(count: 10, color: tint.lightened(0.4), look: .dot, speed: 40...140,
                                   life: 0.6...0.9, drag: 1, gravity: 160))
            effects.emit(at: at, E(count: 12, color: tint, speed: 80...200, life: 0.3...0.5))
        case .mine:
            effects.emit(at: at, E(count: 10, color: tint, speed: 120...240, life: 0.15...0.3, drag: 5))
            effects.ring(at: at, color: tint, radius: 22, duration: 0.2)
        case .brood:
            // The sac bursts: slow wet blobs, a big ring the Motes scatter out of.
            effects.emit(at: at, E(count: 16, color: tint, look: .dot, speed: 30...120, life: 0.7...1.1,
                                   drag: 2, gravity: 60, size: 1.4...2.2))
            effects.emit(at: at, E(count: 12, color: color(of: .enemy(.mote)), speed: 100...220, life: 0.3...0.5))
            effects.ring(at: at, color: color(of: .enemy(.mote)), radius: 70, duration: 0.45)
        case .mote:
            effects.emit(at: at, E(count: 6, color: tint, look: .dot, speed: 40...110, life: 0.15...0.3))
        case .lancer:
            // It was going fast: the debris keeps going.
            let heading = enemyVelocities[id]?.x ?? 0
            effects.emit(at: at, E(count: 16, color: tint, speed: 160...360, life: 0.3...0.55,
                                   angle: heading < 0 ? .pi : 0, spread: 1.2, drag: 2))
            effects.emit(at: at, E(count: 5, color: tint, look: .shard, speed: 60...140, life: 0.5...0.8))
        case .anchor:
            // Heavy metal: big pieces thrown up and falling, hot sparks, a jolt.
            effects.emit(at: at, E(count: 12, color: tint, look: .shard, speed: 80...220, life: 0.8...1.2,
                                   angle: .pi / 2, spread: 2.4, drag: 0.8, gravity: 300, size: 1.2...1.8))
            effects.emit(at: at, E(count: 26, color: spark, speed: 120...300, life: 0.4...0.8))
            effects.ring(at: at, color: tint, radius: 60, duration: 0.5)
            addShake(isOnScreen(at) ? 4 : 0)
        }
    }
}
