import Foundation
import GameCore
import RedoubtCore
import SpriteKit
import UIKit

// Redoubt's per-frame sync: every entity in the run gets a sprite from a fixed pool, by index, in
// plain loops. A sprite is re-textured only when what it shows changes (its `look`), from glyphs
// looked up once per scale, so a busy frame does no string or dictionary work per entity.

extension RedoubtMode {
    /// Arena units per unit coordinate the arrival marker's texture is drawn at: big enough that
    /// the largest marker (a Thresher's, opened up) is never scaled past it.
    static let arrivalGlyphScale = 46.0
    /// The same for the Skitter's quieter marker.
    static let swarmGlyphScale = 14.0

    static func index(of role: RedoubtRole) -> Int {
        switch role {
        case .skitter: 0
        case .gleaner: 1
        case .spitter: 2
        case .burrow: 3
        case .thresher: 4
        case .husk: 5
        }
    }

    /// The glyphs the frame loop uses, by look: enemies (role x 2, the odd ones tinted for a
    /// wind-up), shots (orb, enemy), colonists (calm, in trouble).
    struct Looks {
        var enemies: [GlowShapeFactory.Glyph] = []
        /// Arrival markers: the brackets (roles that matter) and the quiet Skitter seed.
        var arrivalBracket: GlowShapeFactory.Glyph?
        var arrivalSwarm: GlowShapeFactory.Glyph?
        var shots: [GlowShapeFactory.Glyph] = []
        var colonists: [GlowShapeFactory.Glyph] = []
        var roleColors: [UIColor] = []
    }

    func makeLooks() -> Looks {
        var looks = Looks()
        for role in RedoubtRole.allCases.sorted(by: { Self.index(of: $0) < Self.index(of: $1) }) {
            looks.enemies.append(glyphs.glyph(.enemy(role), pointsPerUnit: pointsPerUnit))
            looks.enemies.append(glyphs.glyph(.enemy(role), tint: windUpColor, pointsPerUnit: pointsPerUnit))
            looks.roleColors.append(theme.color(of: .enemy(role)).uiColor())
        }
        looks.shots = [glyphs.glyph(.orbShot, pointsPerUnit: pointsPerUnit),
                       glyphs.glyph(.enemyShot, pointsPerUnit: pointsPerUnit)]
        looks.arrivalBracket = glyphs.glyph(.arrival, scale: Self.arrivalGlyphScale, pointsPerUnit: pointsPerUnit)
        looks.arrivalSwarm = glyphs.glyph(.swarmArrival, scale: Self.swarmGlyphScale, pointsPerUnit: pointsPerUnit)
        looks.colonists = [glyphs.glyph(.colonist, pointsPerUnit: pointsPerUnit),
                           glyphs.glyph(.colonist, tint: theme.palette.warning, pointsPerUnit: pointsPerUnit)]
        return looks
    }

    func sync(_ run: RedoubtRun, elapsed dt: Double, screen: FlowScreen) {
        guard pointsPerUnit > 0 else { return }
        if looks.enemies.isEmpty { looks = makeLooks() }
        let orb = run.orb

        // The power cut: the lights stutter out over about a second when it begins and stutter
        // back when a delivery restores them (`lightsFlicker`, in step with the sounds); otherwise
        // they glide. Shots throw the pool of light forward along the aim, and a Shockwave
        // lights the whole room for a moment.
        var dark = run.isPowerCut ? 1.0 : 0.0
        if let flicker = lightsFlicker {
            let t = clock - flicker.since
            if t >= Self.flickerLength {
                lightsFlicker = nil
            } else {
                dark = Self.flicker(at: t, failing: flicker.failing)
            }
        }
        if lightsFlicker != nil {
            darkMix = dark
        } else {
            darkMix += (dark - darkMix) * min(dt * (run.isPowerCut ? 2.5 : 1.8), 1)
            if abs(darkMix - dark) < 0.01 { darkMix = dark }
        }
        fireLight *= exp(-5 * dt)
        roomLight *= exp(-3 * dt)
        if roomLight < 0.01 { roomLight = 0 }
        darkness.isHidden = darkMix <= 0
        if !darkness.isHidden {
            let lit = orb.isAlive ? orb.pos : run.centre
            let reach = orb.isAlive ? fireLight : 0
            let heading = orb.heading
            darkness.position = CGPoint(x: lit.x + cos(heading) * 95 * reach, y: lit.y + sin(heading) * 95 * reach)
            darkness.zRotation = CGFloat(heading)
            darkness.xScale = CGFloat(1 + 1.9 * reach)
            darkness.yScale = CGFloat(1 + 0.2 * reach)
            darkness.alpha = CGFloat(darkMix * (1 - 0.85 * roomLight))
        }
        wallSprite.alpha = CGFloat(1 - 0.55 * darkMix)
        floorSprite.alpha = CGFloat(0.42 * (1 - 0.6 * darkMix))
        placeAirlock(run.airlock, lineLength: run.line.count, dt: dt)

        syncOrb(orb, run: run, dt: dt)
        var linkCount = 0
        linkCount = syncEnemies(run, links: linkCount)
        syncArrivals(run)
        syncShots(run)
        linkCount = syncColonists(run, links: linkCount)
        var i = linkCount
        while i < shownLinks {
            linkSprites[i].isHidden = true
            i += 1
        }
        shownLinks = linkCount

        updateGhosts(dt)
        effects.update(elapsed: dt)
        controls.setStatus(charges: orb.charges, canUse: orb.isAlive && screen == .playing)

        // Shake moves only the arena, never the HUD, and settles in about a third of a second.
        shake *= CGFloat(exp(-9 * dt))
        if shake < 0.2 { shake = 0 }
        arenaLayer.position = shake > 0
            ? CGPoint(x: arenaOrigin.x + CGFloat.random(in: -1...1) * shake,
                      y: arenaOrigin.y + CGFloat.random(in: -1...1) * shake)
            : arenaOrigin
    }

    func addShake(_ amount: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        shake = min(max(shake, amount), 7)
    }

    // MARK: The orb

    private func syncOrb(_ orb: Orb, run: RedoubtRun, dt: Double) {
        orbSprite.isHidden = !orb.isAlive
        orbAura.isHidden = !orb.isAlive
        muzzleGlow = max(muzzleGlow - CGFloat(dt * 22), 0)
        if orb.isAlive {
            orbSprite.position = CGPoint(x: orb.pos.x, y: orb.pos.y)
            orbAura.position = orbSprite.position
            orbSprite.zRotation = CGFloat(orb.heading)
            // Invulnerable after a respawn: the hull strobes inside a pulsing shield ring.
            let invulnerable = orb.isInvulnerable
            orbSprite.alpha = invulnerable ? (sin(clock * 30) > 0 ? 1 : 0.35) : 1
            orbShield.isHidden = !invulnerable
            orbShield.alpha = 0.55 + 0.35 * CGFloat(sin(clock * 12))
            orbHalo.alpha = 0.26 + 0.1 * CGFloat(sin(clock * 4)) + CGFloat(0.3 * darkMix)
            muzzle.isHidden = muzzleGlow <= 0
            muzzle.alpha = muzzleGlow
            muzzle.setScale(0.8 + 0.5 * muzzleGlow)
            respawnMarker.isHidden = true
        } else {
            // About to come back: a ring closes on the centre.
            let timer = orb.respawnTimer
            respawnMarker.isHidden = run.isGameOver || timer > 0.9 || timer <= 0
            if !respawnMarker.isHidden {
                let t = CGFloat(1 - timer / 0.9)
                respawnMarker.setScale(2.4 - 1.4 * t)
                respawnMarker.alpha = 0.3 + 0.7 * t
                respawnMarker.zRotation = CGFloat(clock * 5)
            }
        }
    }

    // MARK: Enemies

    /// Returns the next free link index (a dragging Gleaner's tether uses one).
    private func syncEnemies(_ run: RedoubtRun, links: Int) -> Int {
        var linkIndex = links
        let enemies = run.enemies
        let count = min(enemies.count, enemySprites.count)
        notePoolOverflow(.enemies, needed: enemies.count, pool: enemySprites.count)
        let warning = theme.palette.warning
        let windUp = tuning.spitterWindUp
        let wake = tuning.huskWakeDelay
        let checkHits = !hitAt.isEmpty
        let inDark = darkMix > 0.3
        var i = 0
        while i < count {
            let enemy = enemies[i]
            let sprite = enemySprites[i]
            let roleIndex = Self.index(of: enemy.role)
            var look = roleIndex * 2
            var xScale: CGFloat = 1
            var yScale: CGFloat = 1
            var alpha: CGFloat = 1
            var rotation = CGFloat(enemy.heading)
            var depth = Self.depth(of: enemy.role)
            switch enemy.role {
            case .skitter, .gleaner:
                if case .dragging(let colonistID, _) = enemy.state, linkIndex < linkSprites.count,
                   let colonist = colonistPosition(colonistID, in: run) {
                    // The grip: a flickering red line to the colonist being dragged away.
                    setLink(linkIndex, from: enemy.pos, to: colonist, color: warning,
                            alpha: 0.4 + 0.4 * CGFloat(abs(sin(clock * 18))), width: 1.8)
                    linkIndex += 1
                }
            case .spitter:
                if case .windingUp(let remaining) = enemy.state {
                    // About to fire: it turns hot, swells and strobes.
                    look += 1
                    let t = CGFloat(1 - remaining / windUp)
                    xScale = 1 + 0.45 * t
                    yScale = xScale
                    alpha = sin(clock * 40) > 0 ? 1 : 0.55
                    // Its glow shows through the dark: the one thing out there it is fair to warn of.
                    if inDark { depth = Depth.darkness + 0.1 }
                }
            case .burrow:
                // The hole closes up as it is shot.
                rotation = 0
                let health = CGFloat(max(enemy.hp, 0)) / CGFloat(tuning.stats(for: .burrow).hp)
                xScale = 0.65 + 0.35 * health
                yScale = xScale
            case .thresher:
                // Pushed back by fire: it rocks back on its tracks.
                let push = CGFloat(enemy.push.length)
                xScale = 1 - min(push / 280, 0.24)
                yScale = 1 + min(push / 700, 0.1)
                // Each hit flashes the plate pale for a moment.
                if checkHits, let hit = hitAt[enemy.id], clock - hit < 0.07 { look += 1 }
            case .husk:
                if case .waking(let remaining) = enemy.state {
                    // Just turned: it grows into its full size, flickering, before it hunts.
                    let t = CGFloat(1 - remaining / wake)
                    xScale = 0.45 + 0.55 * t
                    yScale = xScale
                    alpha = sin(clock * 24) > 0 ? 1 : 0.45
                    rotation = 0
                } else {
                    rotation = CGFloat(clock * 7 + Double(enemy.id))
                }
            }
            if look != sprite.look {
                RedoubtSprites.dress(sprite, with: looks.enemies[look], factory: factory)
                sprite.look = look
            }
            if sprite.zPosition != depth { sprite.zPosition = depth }
            if checkHits, let hit = hitAt[enemy.id] {
                // Heavies under steady fire are hit ten times a second: a small kick, or they
                // would look permanently swollen.
                let kick: CGFloat = switch enemy.role {
                case .thresher: 0.05
                case .burrow: 0.1
                default: 0.3
                }
                let pulse = hitPulse(since: hit, by: kick)
                xScale *= pulse
                yScale *= pulse
            }
            sprite.isHidden = false
            sprite.position = CGPoint(x: enemy.pos.x, y: enemy.pos.y)
            sprite.zRotation = rotation
            sprite.xScale = xScale
            sprite.yScale = yScale
            sprite.alpha = alpha
            i += 1
        }
        while i < shownEnemies {
            enemySprites[i].isHidden = true
            i += 1
        }
        shownEnemies = count
        return linkIndex
    }

    /// Grows briefly when hit, then settles.
    private func hitPulse(since hit: TimeInterval, by kick: CGFloat) -> CGFloat {
        let t = clock - hit
        if t < 0.04 { return 1 + kick * CGFloat(t / 0.04) }
        if t < 0.14 { return 1 + kick * CGFloat(1 - (t - 0.04) / 0.1) }
        return 1
    }

    private func colonistPosition(_ id: Int, in run: RedoubtRun) -> Vec2? {
        for colonist in run.colonists where colonist.id == id { return colonist.pos }
        return nil
    }

    // MARK: Arrivals

    /// Each arrival that matters is a target lock in its role's colour: brackets that close in
    /// and turn over the second before it lands, brightening, and strobe in the last quarter
    /// second. Skitters, which come by the dozen (up to 90 at a late wave's start), get a small
    /// faint seed instead, so the brackets stand out and the floor stays readable; they still
    /// show for the whole warning second.
    private func syncArrivals(_ run: RedoubtRun) {
        let arrivals = run.arrivals
        let count = min(arrivals.count, arrivalSprites.count)
        notePoolOverflow(.arrivals, needed: arrivals.count, pool: arrivalSprites.count)
        let telegraph = tuning.telegraphTime
        guard let bracket = looks.arrivalBracket, let swarm = looks.arrivalSwarm else { return }
        let skitterSize = tuning.stats(for: .skitter).radius * 1.2 / Self.swarmGlyphScale
        var i = 0
        while i < count {
            let arrival = arrivals[i]
            let sprite = arrivalSprites[i]
            let roleIndex = Self.index(of: arrival.role)
            let isSkitter = arrival.role == .skitter
            // A sprite's look is its role; its texture is the seed for Skitters, the brackets for
            // the rest (`dressPools` leaves the look undressed, so this always runs first).
            if sprite.look != roleIndex {
                if sprite.look == PoolSprite.undressed || (sprite.look == 0) != isSkitter {
                    RedoubtSprites.dress(sprite, with: isSkitter ? swarm : bracket, factory: factory)
                }
                sprite.color = looks.roleColors[roleIndex]
                sprite.look = roleIndex
            }
            let t = min(max(1 - arrival.remaining / telegraph, 0), 1)
            let open = (1 - t) * (1 - t)
            let strobe = arrival.remaining < 0.25 && sin(clock * 50) <= 0
            sprite.isHidden = false
            sprite.position = CGPoint(x: arrival.pos.x, y: arrival.pos.y)
            if isSkitter {
                sprite.setScale(CGFloat(skitterSize * (1 + 0.6 * open)))
                sprite.zRotation = 0
                sprite.alpha = strobe ? 0.2 : CGFloat(0.08 + 0.4 * t * t)
            } else {
                // Drawn at most at its texture's own size, so the lines stay thin.
                let size = tuning.stats(for: arrival.role).radius * 1.4 / Self.arrivalGlyphScale
                sprite.setScale(CGFloat(size * (1 + 0.9 * open)))
                sprite.zRotation = CGFloat(open * Double.pi * 0.5)
                sprite.alpha = strobe ? 0.4 : (arrival.remaining < 0.25 ? 1 : CGFloat(0.3 + 0.65 * t * t))
            }
            i += 1
        }
        while i < shownArrivals {
            arrivalSprites[i].isHidden = true
            i += 1
        }
        shownArrivals = count
    }

    // MARK: Shots

    /// Enemy shots take sprites first, so if the pool ever ran short it is the orb's own shots
    /// that go undrawn, never one the player has to dodge.
    private func syncShots(_ run: RedoubtRun) {
        let shots = run.shots
        notePoolOverflow(.shots, needed: shots.count, pool: shotSprites.count)
        let spin = CGFloat(clock * 8)
        let pulse = CGFloat(1 + 0.18 * sin(clock * 16))
        let orbPos = run.orb.pos
        var used = 0
        for pass in 0..<2 {
            let wanted: RedoubtShot.Owner = pass == 0 ? .enemy : .orb
            let look = pass == 0 ? 1 : 0
            var i = 0
            while i < shots.count, used < shotSprites.count {
                let shot = shots[i]
                i += 1
                guard shot.owner == wanted else { continue }
                let sprite = shotSprites[used]
                used += 1
                if look != sprite.look {
                    RedoubtSprites.dress(sprite, with: looks.shots[look], factory: factory)
                    sprite.look = look
                    sprite.zPosition = look == 0 ? Depth.orbShot : Depth.enemyShot
                }
                sprite.isHidden = false
                sprite.position = CGPoint(x: shot.pos.x, y: shot.pos.y)
                sprite.zRotation = look == 0 ? CGFloat(atan2(shot.vel.y, shot.vel.x)) : spin
                if look == 1 {
                    // A Spitter's shot throbs, so it reads as live and dangerous in a crowd.
                    sprite.setScale(pulse)
                } else {
                    // A shot just fired grows its tail as it leaves the emitter, rather than
                    // trailing back through the orb.
                    let dx = shot.pos.x - orbPos.x, dy = shot.pos.y - orbPos.y
                    sprite.xScale = CGFloat(min(max((dx * dx + dy * dy).squareRoot() / 60, 0.3), 1))
                }
            }
        }
        var i = used
        while i < shownShots {
            shotSprites[i].isHidden = true
            i += 1
        }
        shownShots = used
    }

    enum Pool: String {
        case enemies, arrivals, shots, colonists, links
    }

    /// DEBUG: says once per run when a pool is too small for what the run holds (the excess is
    /// not drawn).
    func notePoolOverflow(_ pool: Pool, needed: Int, pool size: Int) {
        #if DEBUG
        guard needed > size, !overflowedPools.contains(pool.rawValue) else { return }
        overflowedPools.insert(pool.rawValue)
        debugLog("[Rimwatch redoubt] \(pool.rawValue) pool of \(size) exceeded: \(needed) needed")
        #endif
    }

    // MARK: Colonists

    /// Sheltering colonists breathe; followers are joined to the orb by a faint cord; one in a
    /// Gleaner's grip flashes red. A new wave's colonists fade in during its last second of
    /// warning. Delivered and lost ones are gone.
    private func syncColonists(_ run: RedoubtRun, links: Int) -> Int {
        var linkIndex = links
        let colonists = run.colonists
        var fadeIn: CGFloat = 1
        if case .intermission(let remaining) = run.phase, remaining <= tuning.telegraphTime {
            fadeIn = CGFloat(1 - remaining / tuning.telegraphTime)
        }
        let mint = theme.color(of: .colonist)
        notePoolOverflow(.colonists, needed: colonists.count, pool: colonistSprites.count)
        var shown = 0
        for colonist in colonists {
            guard shown < colonistSprites.count else { break }
            var look = 0
            var alpha: CGFloat = 1
            var scale: CGFloat = 1
            switch colonist.state {
            case .delivered, .lost:
                continue
            case .sheltering:
                let phase = clock * 3 + Double(colonist.id)
                alpha = 0.8 + 0.2 * CGFloat(sin(phase))
                scale = 1 + 0.08 * CGFloat(sin(phase))
            case .following:
                alpha = 1
            case .seized:
                look = 1
                alpha = sin(clock * 16) > 0 ? 1 : 0.45
            }
            let sprite = colonistSprites[shown]
            if look != sprite.look {
                RedoubtSprites.dress(sprite, with: looks.colonists[look], factory: factory)
                sprite.blendMode = .alpha
                sprite.look = look
            }
            sprite.isHidden = false
            sprite.position = CGPoint(x: colonist.pos.x, y: colonist.pos.y)
            sprite.alpha = alpha * fadeIn
            sprite.setScale(scale)
            shown += 1
        }
        var i = shown
        while i < shownColonists {
            colonistSprites[i].isHidden = true
            i += 1
        }
        shownColonists = shown

        // Where each follower is, for a delivery next frame (the run moves them to the door).
        linePositions.removeAll(keepingCapacity: true)
        for id in run.line {
            if let pos = colonistPosition(id, in: run) { linePositions.append(pos) }
        }

        // The line: a cord from the orb through each follower in order.
        if run.orb.isAlive {
            notePoolOverflow(.links, needed: linkIndex + run.line.count, pool: linkSprites.count)
            var previous = run.orb.pos
            for id in run.line {
                guard linkIndex < linkSprites.count, let pos = colonistPosition(id, in: run) else { break }
                setLink(linkIndex, from: previous, to: pos, color: mint, alpha: 0.4, width: 1.2)
                linkIndex += 1
                previous = pos
            }
        }
        return linkIndex
    }

    /// A thin glowing line between two arena points.
    func setLink(_ index: Int, from a: Vec2, to b: Vec2, color: RGB, alpha: CGFloat, width: CGFloat) {
        let line = linkSprites[index]
        let dx = b.x - a.x, dy = b.y - a.y
        line.isHidden = false
        line.position = CGPoint(x: a.x, y: a.y)
        line.size = CGSize(width: max(hypot(dx, dy), 0.1), height: width / pointsPerUnit)
        line.zRotation = CGFloat(atan2(dy, dx))
        line.color = color.uiColor()
        line.alpha = alpha
    }
}

// MARK: Delivery and the lights

extension RedoubtMode {
    /// The line just delivered runs in through the door, one after another from where each
    /// colonist was last frame (from the orb, for one picked up and delivered at once).
    func sendThroughAirlock(count: Int, door: Vec2) {
        let orb = session.run.orb.pos
        var slot = 0
        for index in 0..<min(count, Self.ghostPool) {
            while slot < ghosts.count, ghosts[slot].active { slot += 1 }
            guard slot < ghosts.count else { return }
            let from = index < linePositions.count ? linePositions[index] : orb
            ghosts[slot] = Ghost(from: from, to: door, delay: 0.06 * Double(index), age: 0, active: true)
        }
    }

    func updateGhosts(_ dt: Double) {
        let mint = theme.color(of: .colonist)
        for index in ghosts.indices where ghosts[index].active {
            ghosts[index].age += dt
            let ghost = ghosts[index]
            let sprite = ghostSprites[index]
            let t = (ghost.age - ghost.delay) / Self.ghostRun
            if t < 0 {
                sprite.isHidden = true
                continue
            }
            if t >= 1 {
                ghosts[index].active = false
                sprite.isHidden = true
                effects.flash(at: ghost.to, radius: 16 * tuning.figureScale, color: mint, life: 0.2, strength: 0.7)
                continue
            }
            let eased = t * t
            sprite.isHidden = false
            sprite.position = CGPoint(x: ghost.from.x + (ghost.to.x - ghost.from.x) * eased,
                                      y: ghost.from.y + (ghost.to.y - ghost.from.y) * eased)
            sprite.setScale(CGFloat(1 - 0.55 * t))
            sprite.alpha = CGFloat(1 - t * t * t)
        }
    }

    static let flickerLength = 1.3

    /// How dark the floor is `t` seconds into the lights failing (ending dark) or coming back
    /// (ending lit): a few stutters, the last landing at about 0.9 s.
    private static let failSteps: [(Double, Double)] = [(0, 0.15), (0.06, 0.85), (0.12, 0.1), (0.26, 0.95),
                                                        (0.33, 0.35), (0.5, 1), (0.58, 0.6), (0.66, 1), (0.82, 0.8),
                                                        (0.9, 1)]
    private static let restoreSteps: [(Double, Double)] = [(0, 1), (0.28, 0.45), (0.34, 1), (0.52, 0.2), (0.6, 0.9),
                                                           (0.72, 0.05), (0.8, 0.55), (0.88, 0)]

    static func flicker(at t: Double, failing: Bool) -> Double {
        let steps = failing ? failSteps : restoreSteps
        var value = steps[0].1
        for step in steps where t >= step.0 { value = step.1 }
        return value
    }
}
