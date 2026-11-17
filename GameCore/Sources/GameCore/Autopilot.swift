// Testing and DEBUG aid only: compiled out of release builds, so it never ships in the app.
// (The scratch tuning harness builds GameCore in release with `-Xswiftc -DDEBUG`.)
#if DEBUG
import Foundation

/// A scripted pilot, for testing and debugging only: the difficulty harness and regression tests
/// measure the game with it, and the app's DEBUG `-autopilot` flies with it. It is not an
/// opponent and not part of the game.
///
/// It reads only public simulation state, the same things a player can see on screen, and turns
/// them into an `InputState`. It keeps a little state of its own (reaction delays, heat
/// discipline, a seeded random source), so it is deterministic for a given seed.
public struct Autopilot: Sendable {
    public enum Skill: Sendable, CaseIterable {
        /// Never touches the controls.
        case idle
        /// Flies at the nearest enemy and holds Fire with sloppy aim and slow reactions. Catches a
        /// colonist only if one falls right by it, and never dodges on purpose.
        case novice
        /// Hunts Harvesters (lifting ones first), catches falling colonists and takes them home,
        /// dodges shots, Lancer charges and chasers, uses Blink and Shockwave sensibly and lets
        /// go of Fire before the lance overheats.
        case competent
        /// Fights like `competent` (dodges, Blink, Shockwave, heat discipline, hunts Harvesters
        /// first) but never goes after a falling colonist or flies one home: the player who
        /// shoots well and neglects rescues, the one who runs into Blackout.
        case shooter
    }

    public let skill: Skill
    private var rng: SeededRNG
    /// Novice: the input decided at the last re-plan, held until the next one.
    private var held = InputState()
    private var replanIn = 0.0
    /// Novice: its aim is off by this much.
    private var aimError = 0.0
    /// Novice: the altitude it wanders at with nothing in view.
    private var wanderY = 300.0
    /// Competent: resting the lance until heat falls back.
    private var cooling = false
    /// Competent: when each threat (by shot or enemy id) was first seen. A person needs a moment
    /// to notice something before reacting to it.
    private var noticed: [Int: Double] = [:]
    /// Competent: the steering decided at the last re-plan.
    private var heldMove = Vec2.zero
    private var heldGoal: Goal?

    /// Seconds before the competent pilot reacts to a new threat, and between its re-plans.
    public static let reactionTime = 0.24
    static let replanInterval = 0.1

    public init(skill: Skill, seed: UInt64) {
        self.skill = skill
        rng = SeededRNG(seed: seed ^ 0x5EED_AB0F_0000_0001)
    }

    public mutating func input(for sim: Simulation) -> InputState {
        guard sim.player.isAlive, !sim.isGameOver else { return InputState() }
        switch skill {
        case .idle: return InputState()
        case .novice: return noviceInput(sim)
        case .competent, .shooter: return competentInput(sim)
        }
    }

    // MARK: Novice

    private mutating func noviceInput(_ sim: Simulation) -> InputState {
        replanIn -= Simulation.timeStep
        guard replanIn <= 0 else { return held }
        // Reacts about three times a second.
        replanIn = rng.range(0.25...0.45)
        aimError = rng.range(-45...45)
        let player = sim.player
        let world = sim.world

        // Doesn't read the scanner: only what is on screen counts. With nothing in view it
        // wanders on the way it is facing, drifting up and down.
        let onScreen = sim.enemies.filter {
            $0.kind != .mine && abs(world.delta(from: player.pos.x, to: $0.pos.x)) < 480
        }
        if rng.chance(0.08) { wanderY = rng.range(world.height * 0.25...world.height * 0.85) }
        var targetX = player.pos.x + player.facing * 400
        var targetY = wanderY
        // A colonist falling close by is worth a lunge; otherwise chase the nearest enemy.
        if let falling = sim.colonists.first(where: {
            if case .falling = $0.state { abs(world.delta(from: player.pos.x, to: $0.pos.x)) < 160 } else { false }
        }) {
            targetX = falling.pos.x
            targetY = falling.pos.y
        } else if let enemy = nearest(onScreen, to: player.pos, in: world) {
            let side: Double = world.delta(from: enemy.pos.x, to: player.pos.x) >= 0 ? 1 : -1
            // Never sure how close is too close.
            targetX = enemy.pos.x + side * rng.range(60...300)
            targetY = enemy.pos.y + aimError
        }
        var move = steer(sim, toX: targetX, y: targetY, gain: 0.7)
        if let enemy = nearest(onScreen, to: player.pos, in: world) {
            let toward: Double = world.delta(from: player.pos.x, to: enemy.pos.x) >= 0 ? 1 : -1
            // Turns to face it only some of the time.
            if abs(move.x) < 0.2, rng.chance(0.5) { move.x = 0.2 * toward }
        }
        // Holds Fire the whole time, and now and then mashes an ability.
        held = InputState(move: move, fire: true,
                          shockwave: sim.enemies.contains { world.distance($0.pos, player.pos) < 50 } && rng.chance(0.25),
                          blink: rng.chance(0.03))
        return held
    }

    // MARK: Competent

    private mutating func competentInput(_ sim: Simulation) -> InputState {
        let player = sim.player
        let world = sim.world
        let tuning = sim.tuning
        let now = Double(sim.tick) * Simulation.timeStep
        // Re-plans ten times a second, like a hand on a stick; in between it holds its course.
        replanIn -= Simulation.timeStep
        if replanIn <= 0 || heldGoal == nil {
            replanIn = Self.replanInterval
            if rng.chance(0.15) { aimError = rng.range(-7...7) }
            var g = goal(sim)
            g.y += aimError
            heldGoal = g
            heldMove = steer(sim, toX: g.x, y: g.y, gain: 1)
        }
        let plan = heldGoal!
        var move = heldMove

        // Face whatever it means to shoot. Within range, back off gently (below the stick's
        // turning threshold) rather than turning tail.
        if let facing = plan.facing, plan.inRange {
            if (player.facing > 0) != (facing > 0) {
                move.x = 0.25 * facing
            } else if (move.x > 0) != (facing > 0) {
                move.x = clamp(move.x, -0.14, 0.14)
            }
        }

        // Dodge: shots on a collision course, chasers and mines close by, a Lancer charge. A
        // chaser it already has lined up is shot, not dodged.
        let lined = hasShot(sim)
        let threats = threats(sim)
        var stillThreatening: [Int: Double] = [:]
        for t in threats { stillThreatening[t.id] = noticed[t.id] ?? now }
        noticed = stillThreatening
        var threat = threats
            .filter { now - (noticed[$0.id] ?? now) >= Self.reactionTime }
            .min { $0.time < $1.time }
        if let t = threat, !t.isShot, lined, t.time > 0.08 { threat = nil }
        var blink = false
        if let threat {
            let away = threat.offset.y >= 0 ? -1.0 : 1.0
            let floor = world.groundHeight(at: player.pos.x) + tuning.playerRadius + 2
            // Pinned against the ground or the ceiling: go the other way.
            let dodge = (away < 0 && player.pos.y - floor < 30) ? 1.0 : (away > 0 && world.ceiling - player.pos.y < 30 ? -1.0 : away)
            move.y = dodge
            if threat.time < 0.18, player.blinkCooldown <= 0, player.invulnerableTimer <= 0 {
                blink = true
                // Blink straight up or down out of the line, not into it.
                move = Vec2(0, dodge)
            }
        }

        // Shockwave when crowded, or when something is about to hit and nothing else can help.
        let close = sim.enemies.filter {
            $0.kind != .mine && abs(world.delta(from: player.pos.x, to: $0.pos.x)) < tuning.shockwaveRange * 0.8
        }
        let carryingDanger = !player.carried.isEmpty && threat != nil
        var shockwave = false
        if player.shockwaves > 0, player.invulnerableTimer <= 0 {
            if close.count >= 6 { shockwave = true }
            if let threat, threat.time < 0.12, !blink, player.shield < 1 { shockwave = true }
            if carryingDanger, close.count >= 4 { shockwave = true }
        }

        // Fire at anything lined up ahead, resting the lance before it overheats.
        if cooling, player.heat < 0.45 { cooling = false }
        if player.heat > 0.86 { cooling = true }
        let fire = !cooling && !player.isOverheated && lined

        return InputState(move: move, fire: fire, shockwave: shockwave, blink: blink)
    }

    private struct Goal {
        var x: Double
        var y: Double
        /// Which way to face on arrival, if it means to shoot.
        var facing: Double?
        /// The target is close enough to shoot at.
        var inRange = false
    }

    /// Where to go: catch a falling colonist, take carried ones home, then hunt. The shooter
    /// skips the first two.
    private func goal(_ sim: Simulation) -> Goal {
        let player = sim.player
        let world = sim.world
        let tuning = sim.tuning
        if skill == .shooter { return huntGoal(sim) }

        // A falling colonist it can reach before it lands.
        var bestFall: (colonist: Colonist, eta: Double)?
        for colonist in sim.colonists {
            guard case .falling(let speed, _) = colonist.state else { continue }
            let dx = abs(world.delta(from: player.pos.x, to: colonist.pos.x))
            let ground = world.groundHeight(at: colonist.pos.x)
            let fallTime = fallSeconds(height: colonist.pos.y - ground, speed: speed, tuning: tuning)
            let eta = dx / tuning.maxSpeed + 0.3
            guard eta < fallTime + 0.6 else { continue }
            if bestFall == nil || eta < bestFall!.eta { bestFall = (colonist, eta) }
        }
        // Unless another abduction is about to finish and only this ship can stop it.
        let liftAboutToFinish = sim.enemies.contains { enemy in
            guard case .lifting = enemy.state else { return false }
            return liftSecondsLeft(enemy, sim) < 4 && reachSeconds(enemy, sim) < liftSecondsLeft(enemy, sim)
        }
        if let (colonist, eta) = bestFall, !liftAboutToFinish || eta < 1.5 {
            // Meet it a little below where it is now.
            let ground = world.groundHeight(at: colonist.pos.x)
            let lead = min(eta, 1.2) * 120
            return Goal(x: colonist.pos.x, y: max(colonist.pos.y - lead, ground + 20))
        }

        // An abduction under way comes before the trip home: colonists on board are safe while
        // the ship is, and one being lifted is not.
        let abducting = sim.enemies.contains {
            switch $0.state {
            case .lifting: true
            case .seeking(let target): target != nil && $0.pos.y < world.ceiling - 90
            default: false
            }
        }
        // Take carried colonists home.
        if !player.carried.isEmpty, !abducting, let home = sim.nearestIntactOutpost(to: player.pos.x) {
            let outpost = world.outposts[home]
            // Clear the way: if a threat sits between, still go, the dodge logic handles it.
            return Goal(x: outpost.x, y: outpost.groundY + 35, facing: nil)
        }

        return huntGoal(sim)
    }

    /// Hunt: a Harvester lifting a colonist first (the highest one), then the most pressing
    /// enemy nearby.
    private func huntGoal(_ sim: Simulation) -> Goal {
        let player = sim.player
        let world = sim.world
        let tuning = sim.tuning
        let lifting = sim.enemies.filter {
            if case .lifting = $0.state { true } else { false }
        }
        let target: Enemy?
        if let urgent = lifting.max(by: { $0.pos.y < $1.pos.y }) {
            target = urgent
        } else {
            target = sim.enemies
                .filter { $0.kind != .mine }
                .min { score($0, sim) < score($1, sim) }
        }
        guard let enemy = target else {
            // Nothing to fight: patrol over the nearest outpost.
            if let home = sim.nearestIntactOutpost(to: player.pos.x) {
                return Goal(x: world.outposts[home].x, y: world.height * 0.5)
            }
            return Goal(x: player.pos.x, y: world.height * 0.5)
        }

        let side: Double = world.delta(from: enemy.pos.x, to: player.pos.x) >= 0 ? 1 : -1
        // Chasers come to it; drifters and Harvesters it approaches to a firing distance.
        let standoff: Double = switch enemy.kind {
        case .husk, .mote: 300
        case .lancer: 340
        default: 200
        }
        var y = enemy.pos.y
        // Don't hover in a Lancer's line while it winds up: shoot it from a little off its line
        // only when it isn't about to charge.
        if enemy.kind == .lancer, case .telegraphing = enemy.state { y = enemy.pos.y + 60 }
        let floor = world.groundHeight(at: enemy.pos.x - side * standoff) + tuning.playerRadius + 4
        let distance = abs(world.delta(from: player.pos.x, to: enemy.pos.x))
        return Goal(x: enemy.pos.x + side * standoff, y: clamp(y, floor, world.ceiling), facing: -side,
                    inRange: distance < tuning.shotSpeed * tuning.shotLifetime * 0.85)
    }

    /// Seconds until a lifting Harvester reaches the top with its colonist.
    private func liftSecondsLeft(_ enemy: Enemy, _ sim: Simulation) -> Double {
        let speed = max(sim.tuning.liftSpeed * sim.liftScale, 1)
        return max(sim.world.ceiling - enemy.pos.y, 0) / speed
    }

    /// Seconds for the ship to get within shooting distance of an enemy.
    private func reachSeconds(_ enemy: Enemy, _ sim: Simulation) -> Double {
        let dx = abs(sim.world.delta(from: sim.player.pos.x, to: enemy.pos.x))
        let range = sim.tuning.shotSpeed * sim.tuning.shotLifetime * 0.8
        return max(dx - range, 0) / sim.tuning.maxSpeed + 0.6
    }

    /// Lower is more pressing.
    private func score(_ enemy: Enemy, _ sim: Simulation) -> Double {
        var distance = sim.world.distance(enemy.pos, sim.player.pos)
        switch enemy.state {
        case .seeking(let target) where target != nil:
            // A Harvester closing on a colonist: deal with it before it grabs.
            distance *= 0.6
        case .drilling:
            distance *= 0.4
        case .descending:
            distance *= 0.7
        default:
            break
        }
        if enemy.kind == .husk || enemy.kind == .mote { distance *= 0.8 }
        return distance
    }

    private func fallSeconds(height: Double, speed: Double, tuning: Tuning) -> Double {
        // Close enough: accelerate to terminal speed, then fall at it.
        let h = max(height, 0)
        let toTerminal = max(tuning.terminalFallSpeed - speed, 0) / tuning.gravity
        let distanceToTerminal = speed * toTerminal + 0.5 * tuning.gravity * toTerminal * toTerminal
        if h <= distanceToTerminal {
            let a = 0.5 * tuning.gravity
            return (-speed + sqrt(speed * speed + 4 * a * h)) / (2 * a)
        }
        return toTerminal + (h - distanceToTerminal) / tuning.terminalFallSpeed
    }

    /// True if a shot fired now would meet an enemy.
    private func hasShot(_ sim: Simulation) -> Bool {
        let player = sim.player
        let range = sim.tuning.shotSpeed * sim.tuning.shotLifetime * 0.92
        for enemy in sim.enemies {
            let dx = sim.world.delta(from: player.pos.x, to: enemy.pos.x) * player.facing
            guard dx > -4, dx < range else { continue }
            // Where it will be when the shot gets there.
            let flight = max(dx, 0) / sim.tuning.shotSpeed
            let dy = enemy.pos.y + enemy.vel.y * flight - player.pos.y
            if abs(dy) < enemy.radius + sim.tuning.shotRadius + 2 { return true }
        }
        return false
    }

    private struct Threat {
        var id: Int
        /// Where it is relative to the ship.
        var offset: Vec2
        /// How soon it arrives.
        var time: Double
        var isShot: Bool
    }

    /// Everything on course to touch the ship soon.
    private func threats(_ sim: Simulation) -> [Threat] {
        let player = sim.player
        let world = sim.world
        let tuning = sim.tuning
        guard player.invulnerableTimer <= 0.1 else { return [] }
        var found: [Threat] = []
        func consider(_ id: Int, _ pos: Vec2, _ vel: Vec2, radius: Double, horizon: Double, isShot: Bool = false) {
            let rel = Vec2(world.delta(from: player.pos.x, to: pos.x), pos.y - player.pos.y)
            let rv = Vec2(vel.x - player.vel.x, vel.y)
            let speed2 = rv.x * rv.x + rv.y * rv.y
            let t = speed2 > 0 ? clamp(-(rel.x * rv.x + rel.y * rv.y) / speed2, 0, horizon) : 0
            let closest = Vec2(rel.x + rv.x * t, rel.y + rv.y * t)
            guard closest.length < radius + tuning.playerRadius + 10 else { return }
            found.append(Threat(id: id, offset: rel, time: t, isShot: isShot))
        }
        for shot in sim.projectiles where shot.owner == .enemy {
            consider(shot.id, shot.pos, shot.vel, radius: shot.radius, horizon: 0.7, isShot: true)
        }
        for enemy in sim.enemies {
            switch enemy.kind {
            case .lancer:
                if case .charging = enemy.state {
                    consider(enemy.id, enemy.pos, enemy.vel, radius: enemy.radius + 8, horizon: 0.8)
                } else if case .telegraphing(let left) = enemy.state, left < 0.3 {
                    // It will charge along this altitude.
                    let dir: Double = world.delta(from: enemy.pos.x, to: player.pos.x) >= 0 ? 1 : -1
                    consider(enemy.id, enemy.pos, Vec2(dir * tuning.lancerChargeSpeed, 0), radius: enemy.radius + 8, horizon: 0.8)
                } else {
                    consider(enemy.id, enemy.pos, enemy.vel, radius: enemy.radius, horizon: 0.4)
                }
            default:
                consider(enemy.id, enemy.pos, enemy.vel, radius: enemy.radius + 6, horizon: 0.45)
            }
        }
        return found
    }

    // MARK: Helpers

    /// Stick input that brings the ship to a point and slows it on arrival.
    private func steer(_ sim: Simulation, toX x: Double, y: Double, gain: Double) -> Vec2 {
        let player = sim.player
        let dx = sim.world.delta(from: player.pos.x, to: x)
        let wanted = clamp(dx * 2.2, -sim.tuning.maxSpeed, sim.tuning.maxSpeed)
        let mx = clamp((wanted - player.vel.x) / 120, -1, 1) * gain
        let my = clamp((y - player.pos.y) / 30, -1, 1) * gain
        return Vec2(mx, my)
    }

    private func nearest(_ enemies: [Enemy], to pos: Vec2, in world: World) -> Enemy? {
        enemies.min { world.distance($0.pos, pos) < world.distance($1.pos, pos) }
    }
}
#endif
