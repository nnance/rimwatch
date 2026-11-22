import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

// Riftwing's per-frame sync: every entity in the run gets a sprite from a fixed pool, by index,
// in plain loops. A sprite is re-textured only when what it shows changes (its `look`), from
// glyphs looked up once per scale. Anything overlapping a side edge is drawn again on the other
// side, since the edges join.

extension RiftwingMode {
    /// Gallery units per unit coordinate the arrival arrow's texture is drawn at.
    static let arrivalGlyphScale = 16.0
    static let poses = RiftwingWingPose.allCases

    static func index(of role: RiftwingRole) -> Int {
        RiftwingRole.allCases.firstIndex(of: role) ?? 0
    }

    static func index(of pose: RiftwingWingPose) -> Int {
        poses.firstIndex(of: pose) ?? 0
    }

    /// The glyphs the frame loop uses, by look.
    struct Looks {
        /// By pose.
        var riders: [GlowShapeFactory.Glyph] = []
        /// By role, then pose x 2 (the odd ones a Warden that has lost its armour).
        var opponents: [[GlowShapeFactory.Glyph]] = []
        /// Calm, and flashing a warning (about to hatch, or in a Gleaner's grip).
        var pods: [GlowShapeFactory.Glyph] = []
        var mine: GlowShapeFactory.Glyph?
        var roleColors: [UIColor] = []
    }

    func makeLooks() -> Looks {
        var looks = Looks()
        let ppu = pointsPerUnit
        looks.riders = Self.poses.map { glyphs.glyph(.rider($0), pointsPerUnit: ppu) }
        for role in RiftwingRole.allCases {
            var byPose: [GlowShapeFactory.Glyph] = []
            for pose in Self.poses {
                let glyph = glyphs.glyph(.opponent(role, pose), pointsPerUnit: ppu)
                byPose.append(glyph)
                // A Warden that has taken a blow has lost its armour: drawn dim, in one colour.
                byPose.append(role == .warden
                    ? glyphs.glyph(.opponent(role, pose), tint: theme.color(of: role).scaled(0.6), pointsPerUnit: ppu)
                    : glyph)
            }
            looks.opponents.append(byPose)
            looks.roleColors.append(theme.color(of: role).uiColor())
        }
        looks.pods = [glyphs.glyph(.pod, pointsPerUnit: ppu), glyphs.glyph(.pod, tint: theme.palette.warning, pointsPerUnit: ppu)]
        looks.mine = glyphs.glyph(.mine, pointsPerUnit: ppu)
        return looks
    }

    func sync(_ run: RiftwingRun, elapsed dt: Double, screen: FlowScreen) {
        guard pointsPerUnit > 0 else { return }
        if looks.riders.isEmpty { looks = makeLooks() }
        syncDarkness(run, dt: dt)
        syncLedges(run, dt: dt)
        syncMotes(run.vents, dt: dt)
        syncRift(RiftState(run, tuning: tuning), dt: dt)
        syncCamping(run)

        wrapCandidates.removeAll(keepingCapacity: true)
        syncRider(run)
        var links = syncOpponents(run, links: 0)
        links = syncPods(run, links: links, dt: dt)
        links = syncMines(run, links: links)
        var i = links
        while i < shownLinks {
            linkSprites[i].isHidden = true
            i += 1
        }
        shownLinks = links
        syncArrivals(run)
        mirrorAcrossJoin()

        effects.update(elapsed: dt)
        controls.setStatus(diving: run.rider.isAlive && run.rider.body.isDiving, alive: run.rider.isAlive, time: clock)

        // Frozen (paused, game over, a menu): the shake holds still where it was.
        guard dt > 0 else { return }
        // Shake moves only the gallery, never the HUD, and settles in about a third of a second.
        shake *= CGFloat(exp(-9 * dt))
        if shake < 0.2 { shake = 0 }
        galleryLayer.position = shake > 0
            ? CGPoint(x: galleryOrigin.x + CGFloat.random(in: -1...1) * shake,
                      y: galleryOrigin.y + CGFloat.random(in: -1...1) * shake)
            : galleryOrigin
    }

    func addShake(_ amount: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        shake = min(max(shake, amount), 7)
    }

    /// A rig's tilt: nose down in a dive, and a little up or down with its climb or fall
    /// otherwise; level on a ledge.
    private func tilt(of body: RiftwingBody) -> CGFloat {
        if body.isGrounded { return 0 }
        let pitch = body.isDiving ? -0.6 : min(max(body.vel.y / 700, -0.22), 0.22)
        return CGFloat(pitch * body.facing)
    }

    /// The cavern has noticed a rider staying put (`RiftwingRun.isRiderCamping`): a red ring
    /// closes on it and a word says so when it starts (at most once in eight seconds).
    private func syncCamping(_ run: RiftwingRun) {
        let camping = run.isRiderCamping && run.rider.isAlive
        // At most once in eight seconds, so it stays a hint and never a nag.
        if camping, !wasCamping, clock - campingCueAt > 8 {
            campingCueAt = clock
            let at = run.rider.pos
            effects.ring(at: at, color: theme.palette.warning, from: 60, to: 18, duration: 0.5, width: 0.8)
            popup(.hunted, at: at)
        }
        wasCamping = camping
    }

    // MARK: The rider

    private func syncRider(_ run: RiftwingRun) {
        let rider = run.rider
        riderSprite.isHidden = !rider.isAlive
        shieldSprite.isHidden = !rider.isAlive || !rider.isInvulnerable
        guard rider.isAlive else { return }
        let body = rider.body
        let look = Self.index(of: RiftwingWingPose.of(body))
        if look != riderSprite.look {
            RiftwingSprites.dress(riderSprite, with: looks.riders[look], factory: factory)
            riderSprite.look = look
        }
        riderSprite.position = CGPoint(x: body.pos.x, y: body.pos.y)
        // A recoil after a clash: squashed for a moment, then springing back.
        let since = clock - riderKickAt
        let squash: CGFloat = since < 0.22 ? riderKick * CGFloat(1 - since / 0.22) : 0
        riderSprite.xScale = CGFloat(body.facing) * (1 + squash)
        riderSprite.yScale = 1 - squash
        riderSprite.zRotation = tilt(of: body)
        // Protected after returning: it strobes inside a pulsing ring.
        riderSprite.alpha = rider.isInvulnerable ? (sin(clock * 30) > 0 ? 1 : 0.35) : 1
        wrapCandidates.append(riderSprite)
        if rider.isInvulnerable {
            shieldSprite.position = riderSprite.position
            shieldSprite.alpha = 0.5 + 0.35 * CGFloat(sin(clock * 12))
            shieldSprite.setScale(1 + 0.05 * CGFloat(sin(clock * 6)))
            wrapCandidates.append(shieldSprite)
        }
    }

    // MARK: Opponents

    /// Returns the next free link index (a Gleaner's grip on a pod uses one).
    private func syncOpponents(_ run: RiftwingRun, links: Int) -> Int {
        var linkIndex = links
        let opponents = run.opponents
        let count = min(opponents.count, opponentSprites.count)
        notePoolOverflow("opponents", needed: opponents.count, pool: opponentSprites.count)
        let wake = tuning.hatchWake
        let checkHits = !hitAt.isEmpty
        var i = 0
        while i < count {
            let opponent = opponents[i]
            let sprite = opponentSprites[i]
            let body = opponent.body
            var pose = RiftwingWingPose.of(body)
            var scale: CGFloat = 1
            var alpha: CGFloat = 1
            var rotation = tilt(of: body)
            var wounded = false
            switch opponent.state {
            case .waking(let remaining):
                // Just hatched: it grows to its full size on the ledge, flickering, before it flies.
                pose = .perched
                let t = CGFloat(1 - remaining / wake)
                scale = 0.5 + 0.5 * t
                alpha = sin(clock * 24) > 0 ? 1 : 0.45
            case .staggered:
                // Took a blow and stayed on: tumbling out of control.
                rotation = CGFloat(clock * 14 + Double(opponent.id))
                alpha = sin(clock * 20) > 0 ? 1 : 0.6
            case .grabbing:
                scale = 1 + 0.1 * CGFloat(abs(sin(clock * 10)))
            case .flying, .seeking, .carrying, .leaving:
                break
            }
            if opponent.role == .gleaner {
                // Not a rig: its wings buzz, faster with a pod in its grip.
                let carrying: Bool
                if case .carrying = opponent.state { carrying = true } else { carrying = false }
                let rate = carrying ? 44.0 : 30.0
                pose = sin(clock * rate + Double(opponent.id)) > 0 ? .raised : .swept
                rotation = 0
            }
            if opponent.role == .warden, opponent.blows < tuning.stats(for: .warden).blows { wounded = true }
            let look = Self.index(of: pose) * 2 + (wounded ? 1 : 0)
            let roleIndex = Self.index(of: opponent.role)
            let combined = roleIndex * 100 + look
            if combined != sprite.look {
                RiftwingSprites.dress(sprite, with: looks.opponents[roleIndex][look], factory: factory)
                sprite.look = combined
            }
            let depth = Self.depth(of: opponent.role)
            if sprite.zPosition != depth { sprite.zPosition = depth }
            if checkHits, let hit = hitAt[opponent.id] { scale *= hitPulse(since: hit) }
            // In the dark: a faint outline outside the pool of light, glinting now and then.
            alpha *= darkVisibility(at: body.pos, seed: opponent.id)
            sprite.isHidden = false
            sprite.position = CGPoint(x: body.pos.x, y: body.pos.y)
            sprite.xScale = scale * CGFloat(body.facing)
            sprite.yScale = scale
            sprite.zRotation = rotation
            sprite.alpha = alpha
            wrapCandidates.append(sprite)

            // A Gleaner's grip: a flickering red line down to the pod it holds.
            switch opponent.state {
            case .grabbing(let podID, _), .carrying(let podID, _):
                if linkIndex < linkSprites.count, let pod = run.pod(podID) {
                    setLink(linkIndex, from: body.pos, to: pod.pos, run: run, color: theme.palette.warning,
                            alpha: 0.45 + 0.4 * CGFloat(abs(sin(clock * 18))), width: 1.6)
                    linkIndex += 1
                }
            default:
                break
            }
            i += 1
        }
        while i < shownOpponents {
            opponentSprites[i].isHidden = true
            i += 1
        }
        shownOpponents = count
        return linkIndex
    }

    /// A falling pod leaves a faint mint trail, so its line down is easy to follow.
    private func podTrail(_ pod: RiftwingPod) {
        guard trailDue <= 0 else { return }
        effects.spray(at: pod.pos + Vec2(0, tuning.podRadius * 0.8), angle: Double.pi / 2, spread: 0.4,
                      color: theme.color(of: .pod).scaled(0.7), count: 1, speed: 20, life: 0.35, size: 0.6, drag: 3)
    }

    /// Grows briefly when hit, then settles.
    private func hitPulse(since hit: TimeInterval) -> CGFloat {
        let t = clock - hit
        if t < 0.05 { return 1 + 0.35 * CGFloat(t / 0.05) }
        if t < 0.2 { return 1 + 0.35 * CGFloat(1 - (t - 0.05) / 0.15) }
        return 1
    }

    // MARK: Pods

    /// A falling pod wobbles; a resting one breathes, and in its last seconds flashes red, faster
    /// and faster, and trembles (it shows through the dark then); one in a Gleaner's grip
    /// flashes red. Freed and lost pods are gone.
    private func syncPods(_ run: RiftwingRun, links: Int, dt: Double) -> Int {
        let pods = run.pods
        trailDue -= dt
        let warning = tuning.hatchWarning
        var shown = 0
        for pod in pods {
            guard shown < podSprites.count else {
                notePoolOverflow("pods", needed: run.podsInPlay, pool: podSprites.count)
                break
            }
            var look = 0
            var alpha: CGFloat = 1
            var scale: CGFloat = 1
            var rotation: CGFloat = 0
            var offset = 0.0
            var depth = Depth.pod
            var squash: CGFloat = 0
            if pod.isCatchable, uncatchablePods.remove(pod.id) != nil {
                // It can be taken now: a mint pop says so.
                effects.pop(at: pod.pos, color: theme.color(of: .pod), radius: 16 * tuning.figureScale, life: 0.3)
                scale = 1.25
            }
            switch pod.state {
            case .freed, .lost:
                continue
            case .falling:
                rotation = CGFloat(0.3 * sin(clock * 7 + Double(pod.id)))
                if !pod.isCatchable {
                    uncatchablePods.insert(pod.id)
                    // Just knocked loose and thrown clear: dim and spinning until it can be taken,
                    // when it brightens with a pop (`podBecameCatchable`).
                    alpha = 0.45
                    rotation = CGFloat(clock * 16)
                } else if pod.hoverLeft > 0, abs(pod.vel.y) < 0.001 {
                    // Held up over the Rift by its heat (the run stops its fall while it holds
                    // it, at whatever height that is): it shimmers, and in its last two seconds
                    // it shudders and flashes red, about to drop in.
                    offset = 0
                    rotation = 0
                    scale = 1 + 0.08 * CGFloat(sin(clock * 8 + Double(pod.id)))
                    if pod.hoverLeft < 2 {
                        look = sin(clock * (10 + 16 * (2 - pod.hoverLeft))) > 0 ? 1 : 0
                        offset = 1.4 * sin(clock * 55)
                        depth = Depth.litPod
                    }
                }
                if dt > 0 { podTrail(pod) }
            case .resting:
                if pod.hatchIn <= warning {
                    let urgency = 1 - max(pod.hatchIn, 0) / warning
                    let rate = 7 + 22 * urgency
                    look = sin(clock * rate) > -0.35 ? 1 : 0
                    offset = 1.2 * urgency * sin(clock * 60)
                    scale = 1 + CGFloat(0.12 * urgency)
                    depth = Depth.litPod
                } else {
                    scale = 1 + 0.05 * CGFloat(sin(clock * 3 + Double(pod.id)))
                }
                if let landed = podLandedAt[pod.id] {
                    // A squash as it lands, then a bounce back.
                    let t = clock - landed
                    if t < 0.3 {
                        squash = CGFloat(0.28 * sin(t / 0.3 * Double.pi) * (1 - t / 0.3))
                    } else {
                        podLandedAt[pod.id] = nil
                    }
                }
            case .seized:
                look = sin(clock * 16) > 0 ? 1 : 0
                alpha = 0.9
            }
            let sprite = podSprites[shown]
            if look != sprite.look {
                RiftwingSprites.dress(sprite, with: looks.pods[look], factory: factory)
                sprite.look = look
            }
            if sprite.zPosition != depth { sprite.zPosition = depth }
            sprite.isHidden = false
            sprite.position = CGPoint(x: pod.pos.x + offset, y: pod.pos.y - Double(squash) * tuning.podRadius * 0.6)
            sprite.xScale = scale * (1 + squash)
            sprite.yScale = scale * (1 - squash)
            sprite.zRotation = rotation
            sprite.alpha = alpha
            wrapCandidates.append(sprite)
            shown += 1
        }
        if trailDue <= 0 { trailDue = 0.06 }
        var i = shown
        while i < shownPods {
            podSprites[i].isHidden = true
            i += 1
        }
        shownPods = shown
        return links
    }

    // MARK: Mines

    /// Each mine turns slowly on its tether, hanging from where its Sower laid it.
    private func syncMines(_ run: RiftwingRun, links: Int) -> Int {
        var linkIndex = links
        let mines = run.mines
        let count = min(mines.count, mineSprites.count)
        notePoolOverflow("mines", needed: mines.count, pool: mineSprites.count)
        guard let glyph = looks.mine else { return linkIndex }
        let tether = theme.color(of: .mine).scaled(0.7)
        var i = 0
        while i < count {
            let mine = mines[i]
            let sprite = mineSprites[i]
            if sprite.look != 0 {
                RiftwingSprites.dress(sprite, with: glyph, factory: factory)
                sprite.look = 0
            }
            sprite.isHidden = false
            sprite.position = CGPoint(x: mine.pos.x, y: mine.pos.y)
            sprite.zRotation = CGFloat(clock * 1.4 + Double(mine.id))
            sprite.setScale(1 + 0.06 * CGFloat(sin(clock * 5 + Double(mine.id))))
            sprite.alpha = darkVisibility(at: mine.pos, seed: mine.id + 50)
            wrapCandidates.append(sprite)
            if linkIndex < linkSprites.count {
                setLink(linkIndex, from: mine.anchor, to: mine.pos, run: run, color: tether, alpha: 0.7, width: 1.2)
                linkIndex += 1
            }
            i += 1
        }
        while i < shownMines {
            mineSprites[i].isHidden = true
            i += 1
        }
        shownMines = count
        return linkIndex
    }

    /// A thin glowing line between two gallery points, the short way round the join.
    func setLink(_ index: Int, from a: Vec2, to b: Vec2, run: RiftwingRun, color: RGB, alpha: CGFloat, width: CGFloat) {
        let line = linkSprites[index]
        let dx = run.dxWrap(a.x, b.x), dy = b.y - a.y
        line.isHidden = false
        line.position = CGPoint(x: a.x, y: a.y)
        line.size = CGSize(width: max(hypot(dx, dy), 0.1), height: width / pointsPerUnit)
        line.zRotation = CGFloat(atan2(dy, dx))
        line.color = color.uiColor()
        line.alpha = alpha
        wrapCandidates.append(line)
    }

    // MARK: Arrivals

    /// An opponent on its way in: a glow in its tunnel mouth at its height, in its role's colour,
    /// brightening over the second before it flies out, with arrows pointing into the gallery;
    /// both strobe in the last quarter second.
    private func syncArrivals(_ run: RiftwingRun) {
        let arrivals = run.arrivals
        let count = min(arrivals.count, arrivalSprites.count)
        notePoolOverflow("arrivals", needed: arrivals.count, pool: arrivalSprites.count)
        var i = 0
        while i < count {
            let arrival = arrivals[i]
            let sprite = arrivalSprites[i]
            let glow = arrivalGlows[i]
            let roleIndex = Self.index(of: arrival.role)
            let color = looks.roleColors[roleIndex]
            if sprite.look != roleIndex {
                sprite.color = color
                glow.color = color
                sprite.look = roleIndex
            }
            // The glow runs its whole time (longer for a forced arrival).
            let t = min(max(1 - arrival.remaining / max(arrival.glowTime, 0.01), 0), 1)
            let strobe = arrival.remaining < 0.25 && sin(clock * 50) <= 0
            let inward: CGFloat = arrival.side == .left ? 1 : -1
            let edge = arrival.side == .left ? 0.0 : tuning.width
            let radius = tuning.stats(for: arrival.role).radius
            sprite.isHidden = false
            sprite.position = CGPoint(x: edge + Double(inward) * (radius * 0.9 + 10 * t), y: arrival.pos.y)
            let size = CGFloat(radius * 0.9 / Self.arrivalGlyphScale)
            sprite.xScale = inward * size
            sprite.yScale = size
            sprite.alpha = strobe ? 0.3 : CGFloat(0.35 + 0.65 * t)
            glow.isHidden = false
            glow.position = CGPoint(x: edge, y: arrival.pos.y)
            let glowSize = CGFloat(radius * (3 + 2.5 * t))
            glow.size = CGSize(width: glowSize * 1.3, height: glowSize * 2)
            glow.alpha = strobe ? 0.25 : CGFloat(0.25 + 0.6 * t)
            i += 1
        }
        while i < shownArrivals {
            arrivalSprites[i].isHidden = true
            arrivalGlows[i].isHidden = true
            i += 1
        }
        shownArrivals = count
    }

    // MARK: The join

    /// The left and right edges join, so anything overlapping one is drawn again just past the
    /// other, by a ghost copying its look. The masks outside the gallery hide what falls past
    /// either edge.
    private func mirrorAcrossJoin() {
        let width = CGFloat(tuning.width)
        var used = 0
        for sprite in wrapCandidates {
            let frame = sprite.frame
            let shift: CGFloat
            if frame.minX < 0 {
                shift = width
            } else if frame.maxX > width {
                shift = -width
            } else {
                continue
            }
            guard used < ghostSprites.count else {
                notePoolOverflow("ghosts", needed: used + 1, pool: ghostSprites.count)
                break
            }
            let ghost = ghostSprites[used]
            used += 1
            if let source = sprite as? PoolSprite, let glyph = source.glyph {
                if ghost.texture !== glyph.texture { RiftwingSprites.dress(ghost, with: glyph, factory: factory) }
                ghost.xScale = source.xScale
                ghost.yScale = source.yScale
                ghost.colorBlendFactor = source.colorBlendFactor
            } else {
                // A plain line.
                ghost.texture = nil
                ghost.glyph = nil
                ghost.xScale = 1
                ghost.yScale = 1
                ghost.anchorPoint = sprite.anchorPoint
                ghost.size = sprite.size
                ghost.colorBlendFactor = 1
                ghost.blendMode = sprite.blendMode
            }
            ghost.color = sprite.color
            ghost.zRotation = sprite.zRotation
            ghost.alpha = sprite.alpha
            ghost.zPosition = sprite.zPosition
            ghost.position = CGPoint(x: sprite.position.x + shift, y: sprite.position.y)
            ghost.isHidden = false
        }
        var i = used
        while i < shownGhosts {
            ghostSprites[i].isHidden = true
            i += 1
        }
        shownGhosts = used
    }

    /// DEBUG: says once per run when a pool is too small for what the run holds.
    func notePoolOverflow(_ pool: String, needed: Int, pool size: Int) {
        #if DEBUG
        guard needed > size, !overflowedPools.contains(pool) else { return }
        overflowedPools.insert(pool)
        debugLog("[Rimwatch riftwing] \(pool) pool of \(size) exceeded: \(needed) needed")
        #endif
    }
}
