import GameCore

// Testing and DEBUG aid only: compiled out of release builds, so it never ships in the app.
// (The tuning harness builds GameCore in release with `-Xswiftc -DDEBUG`.)
#if DEBUG
import Foundation

/// A scripted Redoubt player, for testing and debugging only: the difficulty harness and the
/// regression tests measure the mode with it. It reads only public run state (what a player
/// sees on screen) and keeps a little state of its own (re-plan timers, a seeded random
/// source), so it is deterministic for a given seed.
public struct RedoubtPilot: Sendable {
    public enum Skill: String, Sendable, CaseIterable {
        /// Never touches the sticks.
        case idle
        /// Aims roughly at the nearest enemy and holds the stick there, wanders toward colonists
        /// it sees close by, goes to the airlock with two or more in tow, backs away from the
        /// single nearest enemy (ignoring the rest of the crowd), re-plans only about four times
        /// a second, and now and then panics with a Shockwave.
        case novice
        /// Re-plans ten times a second: aims (with lead) at the most pressing enemy, steers
        /// between the crowd with a repulsion field, collects colonists and takes the line to
        /// the airlock, keeps out of Spitter shots and uses Shockwave when hemmed in.
        case competent
        /// Fights as the competent pilot does but never goes for colonists or the airlock and
        /// leaves Gleaners alone unless they come close, so colonists are lost. Since the 13d
        /// tuning it seldom loses a whole wave's colonists, so it does not reliably reach the power
        /// cut; the app's `-powerCutAtWave` forces one.
        case shooter
        /// The kiting tactic, kept as a regression guard (13d): flies laps of the floor hugging
        /// the wall (its centre 12 units in, 2 more than its radius) at top speed, always
        /// counterclockwise, aiming with lead at the nearest enemy shots can destroy. Never
        /// rescues; fires a Shockwave only when something is about to touch it. Before 13d it
        /// out-survived the competent pilot and lasted 10 minutes in about a third of its games.
        case wallCircler
        /// The same, on a smaller loop well inside the wall (190 units in).
        case innerCircler
        /// The wall loop, but it turns round whenever something is within 50 units ahead.
        case reversingCircler
    }

    public let skill: Skill
    private var rng: SeededRNG
    private var replanIn = 0.0
    private var held = RedoubtInput()
    /// Novice: where it is wandering to.
    private var wander: Vec2?
    /// Circlers: the corner of the loop it is heading for, which way round it goes, and how long
    /// before it may turn round again.
    private var corner: Int?
    private var clockwise = false
    private var turnCooldown = 0.0

    public init(skill: Skill, seed: UInt64) {
        self.skill = skill
        rng = SeededRNG(seed: seed ^ 0x5EED_0D0B_7000_0002)
    }

    public mutating func input(for run: RedoubtRun) -> RedoubtInput {
        guard run.orb.isAlive, !run.isGameOver else { return RedoubtInput() }
        switch skill {
        case .idle: return RedoubtInput()
        case .novice: return noviceInput(run)
        case .competent, .shooter: return competentInput(run)
        case .wallCircler, .innerCircler, .reversingCircler: return circlerInput(run)
        }
    }

    // MARK: Novice

    private mutating func noviceInput(_ run: RedoubtRun) -> RedoubtInput {
        replanIn -= RedoubtRun.timeStep
        guard replanIn <= 0 else { return held }
        replanIn = rng.range(0.2...0.3)
        let orb = run.orb
        let live = run.enemies

        var aim = Vec2.zero
        if let target = live.min(by: { d($0.pos, orb.pos) < d($1.pos, orb.pos) }) {
            // Aims where it is now, a good way off.
            let angle = atan2(target.pos.y - orb.pos.y, target.pos.x - orb.pos.x) + rng.range(-0.35...0.35)
            aim = unitVector(angle)
        }

        var goal: Vec2
        if run.line.count >= 2, run.airlock.isOpen {
            goal = run.airlock.pos
        } else if let colonist = run.colonists
            .filter({ $0.state == .sheltering && d($0.pos, orb.pos) < 260 })
            .min(by: { d($0.pos, orb.pos) < d($1.pos, orb.pos) }) {
            goal = colonist.pos
        } else {
            if wander == nil || d(wander!, orb.pos) < 40 || rng.chance(0.1) {
                wander = Vec2(rng.range(100...(run.arenaSize.x - 100)), rng.range(100...(run.arenaSize.y - 100)))
            }
            goal = wander!
        }
        var move = unit(goal - orb.pos) * 0.85
        // Backs away from the one nearest thing coming at it, without weighing the rest of the
        // crowd (so it often backs into something else).
        if let close = live.filter({ $0.role != .burrow && d($0.pos, orb.pos) < 90 })
            .min(by: { d($0.pos, orb.pos) < d($1.pos, orb.pos) }) {
            move = unit(orb.pos - close.pos)
            goal = orb.pos + move
        }
        // Panics with a Shockwave when something is right on it, now and then.
        let onTop = live.contains { $0.role != .burrow && d($0.pos, orb.pos) - $0.radius < 30 }
        held = RedoubtInput(move: move, aim: aim, shockwave: onTop && rng.chance(0.4))
        return held
    }

    // MARK: Circlers

    private mutating func circlerInput(_ run: RedoubtRun) -> RedoubtInput {
        let dt = RedoubtRun.timeStep
        turnCooldown -= dt
        replanIn -= dt
        guard replanIn <= 0 else {
            held.shockwave = false
            return held
        }
        replanIn = 0.05
        let orb = run.orb
        let tuning = run.tuning
        let size = run.arenaSize
        // The loop's corners, counterclockwise from bottom-left.
        let inset = skill == .innerCircler ? 190.0 : 12.0
        let corners = [Vec2(inset, inset), Vec2(size.x - inset, inset),
                       Vec2(size.x - inset, size.y - inset), Vec2(inset, size.y - inset)]
        if corner == nil {
            // Start at the nearest corner (also after a respawn: see below).
            corner = corners.indices.min { d(corners[$0], orb.pos) < d(corners[$1], orb.pos) }
        }
        if d(corners[corner!], orb.pos) < 24 {
            corner = (corner! + (clockwise ? 3 : 1)) % 4
        }
        // Back at the centre after a respawn: rejoin the loop at the nearest corner.
        if d(orb.pos, run.centre) < 20 {
            corner = corners.indices.min { d(corners[$0], orb.pos) < d(corners[$1], orb.pos) }
        }
        var move = unit(corners[corner!] - orb.pos)
        if skill == .reversingCircler, turnCooldown <= 0 {
            // Something in the way ahead: turn round and head for the corner behind.
            let blocked = run.enemies.contains { enemy in
                let offset = enemy.pos - orb.pos
                let dist = offset.length - enemy.radius
                return dist < 50 && dist > 0 && (offset.x * move.x + offset.y * move.y) > 0.6 * offset.length
            }
            if blocked {
                clockwise.toggle()
                corner = (corner! + (clockwise ? 3 : 1)) % 4
                move = unit(corners[corner!] - orb.pos)
                turnCooldown = 0.6
            }
        }

        var aim = Vec2.zero
        // The nearest thing shots can destroy (a Thresher only when nothing else is left).
        let shootable = run.enemies.filter { $0.role != .thresher }
        if let target = (shootable.isEmpty ? run.enemies : shootable)
            .min(by: { d($0.pos, orb.pos) < d($1.pos, orb.pos) }) {
            let flight = d(target.pos, orb.pos) / tuning.shotSpeed
            let lead = target.pos + (target.vel + target.push) * flight
            aim = unit(lead - orb.pos)
        }
        var shockwave = false
        if orb.charges > 0, !orb.isInvulnerable {
            shockwave = run.enemies.contains {
                $0.role != .burrow && d($0.pos, orb.pos) - $0.radius - tuning.orbRadius < 10
            }
        }
        held = RedoubtInput(move: move, aim: aim, shockwave: shockwave)
        return held
    }

    // MARK: Competent

    private mutating func competentInput(_ run: RedoubtRun) -> RedoubtInput {
        replanIn -= RedoubtRun.timeStep
        guard replanIn <= 0 else {
            // The Shockwave press lasts one step; the sticks are held between re-plans.
            held.shockwave = false
            return held
        }
        replanIn = 0.1
        let orb = run.orb
        let tuning = run.tuning

        // Aim: the most pressing target, led for the shot's flight.
        var aim = Vec2.zero
        if let target = run.enemies.min(by: { urgency($0, run) < urgency($1, run) }) {
            let flight = d(target.pos, orb.pos) / tuning.shotSpeed
            let lead = target.pos + (target.vel + target.push) * flight
            let angle = atan2(lead.y - orb.pos.y, lead.x - orb.pos.x) + rng.range(-0.04...0.04)
            aim = unitVector(angle)
        }

        // Where it wants to be.
        let goal = competentGoal(run)
        var move = unit(goal - orb.pos) * min(d(goal, orb.pos) / 40, 1)

        // Repulsion from enemies (more from the dangerous and the close), shots on a collision
        // course, Threshers and the wall.
        var push = Vec2.zero
        for enemy in run.enemies {
            let offset = orb.pos - enemy.pos
            let dist = max(offset.length - enemy.radius - tuning.orbRadius, 1)
            let range: Double = switch enemy.role {
            case .thresher: 130
            case .husk: 150
            case .burrow: 70
            default: 95
            }
            guard dist < range else { continue }
            // Squared by hand: an optimised build turns `pow(x, 2)` into `x * x`, which can round
            // differently from the library call and split Debug from Release runs.
            let closeness = (range - dist) / range
            let weight = closeness * closeness * (enemy.role == .husk || enemy.role == .thresher ? 3 : 2)
            push = push + unit(offset) * weight
        }
        for arrival in run.arrivals where d(arrival.pos, orb.pos) < 110 {
            push = push + unit(orb.pos - arrival.pos) * 0.6
        }
        for shot in run.shots where shot.owner == .enemy {
            // Closest approach within the next second.
            let rel = orb.pos - shot.pos
            let rv = shot.vel - orb.vel
            let speed2 = rv.x * rv.x + rv.y * rv.y
            let t = speed2 > 0 ? min(max((rel.x * rv.x + rel.y * rv.y) / speed2, 0), 1.0) : 0
            let miss = rel - rv * t
            let gap = miss.length - shot.radius - tuning.orbRadius
            guard gap < 22 else { continue }
            // Step sideways out of its path.
            let side = miss.length > 0.1 ? unit(miss) : unit(Vec2(-rv.y, rv.x))
            push = push + side * (3 * (1.1 - t))
        }
        let wall = 50.0
        if orb.pos.x < wall { push.x += (wall - orb.pos.x) / wall }
        if orb.pos.x > run.arenaSize.x - wall { push.x -= (orb.pos.x - (run.arenaSize.x - wall)) / wall }
        if orb.pos.y < wall { push.y += (wall - orb.pos.y) / wall }
        if orb.pos.y > run.arenaSize.y - wall { push.y -= (orb.pos.y - (run.arenaSize.y - wall)) / wall }
        // Near the airlock with a line, the wall does not push it away.
        if !run.line.isEmpty, d(orb.pos, run.airlock.pos) < 120 {
            push = push - wallPushToward(run.airlock, orb.pos, wall: wall, size: run.arenaSize)
        }
        move = (move + push * 1.6).clampedToUnit

        // Shockwave when hemmed in or about to be touched.
        var shockwave = false
        if orb.charges > 0, !orb.isInvulnerable {
            let near = run.enemies.filter { d($0.pos, orb.pos) - $0.radius < 70 }
            let touching = run.enemies.contains { d($0.pos, orb.pos) - $0.radius - tuning.orbRadius < 10 && $0.role != .burrow }
            let thresher = run.enemies.contains { $0.role == .thresher && d($0.pos, orb.pos) - $0.radius < 45 }
            if near.count >= 6 || touching || thresher { shockwave = true }
        }

        held = RedoubtInput(move: move, aim: aim, shockwave: shockwave)
        return held
    }

    /// The wall push the field adds near the airlock's wall, so it can be taken back out.
    private func wallPushToward(_ airlock: Airlock, _ p: Vec2, wall: Double, size: Vec2) -> Vec2 {
        switch airlock.wall {
        case .west: p.x < wall ? Vec2((wall - p.x) / wall, 0) : .zero
        case .east: p.x > size.x - wall ? Vec2(-(p.x - (size.x - wall)) / wall, 0) : .zero
        case .south: p.y < wall ? Vec2(0, (wall - p.y) / wall) : .zero
        case .north: p.y > size.y - wall ? Vec2(0, -(p.y - (size.y - wall)) / wall) : .zero
        }
    }

    /// Lower is more pressing: close things, things closing fast, Gleaners with a colonist.
    private func urgency(_ enemy: RedoubtEnemy, _ run: RedoubtRun) -> Double {
        var u = d(enemy.pos, run.orb.pos)
        switch enemy.role {
        case .thresher:
            // Shots only push it; worth it only when it is close.
            u = u < 140 ? u * 1.2 : u + 2000
        case .husk: u *= 0.6
        case .gleaner:
            // The shooter leaves Gleaners be until they are close enough to matter.
            if skill == .shooter {
                if u > 80 { u += 5000 }
                break
            }
            if case .dragging = enemy.state { u *= 0.4 } else { u *= 0.7 }
        case .burrow:
            // Left for later while the crowd is thick; the first thing to close once it thins.
            let others = run.enemies.count { $0.role != .burrow && $0.role != .thresher }
            u *= others < 6 ? 0.3 : 1.3
        case .spitter: u *= 0.9
        case .skitter: break
        }
        return u
    }

    /// Collect colonists, take the line out, else keep to open floor.
    private func competentGoal(_ run: RedoubtRun) -> Vec2 {
        let orb = run.orb
        let sheltering = skill == .shooter ? [] : run.colonists.filter { $0.state == .sheltering }
        let nearest = sheltering.min { d($0.pos, orb.pos) < d($1.pos, orb.pos) }
        let airlockPoint = insetAirlock(run)
        if skill != .shooter, !run.line.isEmpty, run.airlock.isOpen {
            // Head out with a long line, with nobody else left to fetch, or when the airlock is
            // nearer than the next colonist.
            if run.line.count >= 4 || nearest == nil
                || d(airlockPoint, orb.pos) < d(nearest!.pos, orb.pos) * 0.8 {
                return airlockPoint
            }
        }
        if let nearest { return nearest.pos }
        // Nothing to collect: the most open of a few spots.
        var best = run.centre
        var bestScore = -Double.infinity
        for fx in [0.25, 0.5, 0.75] {
            for fy in [0.3, 0.5, 0.7] {
                let p = Vec2(run.arenaSize.x * fx, run.arenaSize.y * fy)
                let crowd = run.enemies.reduce(0.0) { $0 + 1 / max(d($1.pos, p), 30) }
                let score = -crowd * 1000 - d(p, orb.pos) * 0.002
                if score > bestScore {
                    bestScore = score
                    best = p
                }
            }
        }
        return best
    }

    private func insetAirlock(_ run: RedoubtRun) -> Vec2 {
        let a = run.airlock
        return switch a.wall {
        case .north: Vec2(a.pos.x, a.pos.y - 14)
        case .south: Vec2(a.pos.x, a.pos.y + 14)
        case .east: Vec2(a.pos.x - 14, a.pos.y)
        case .west: Vec2(a.pos.x + 14, a.pos.y)
        }
    }

    // MARK: Helpers

    private func d(_ a: Vec2, _ b: Vec2) -> Double { (a - b).length }

    private func unit(_ v: Vec2) -> Vec2 {
        let len = v.length
        return len > 1e-9 ? v * (1 / len) : .zero
    }
}
#endif
