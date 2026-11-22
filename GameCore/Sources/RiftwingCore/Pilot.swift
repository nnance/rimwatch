import GameCore

// Testing and DEBUG aid only: compiled out of release builds, so it never ships in the app.
// (The tuning harness builds GameCore in release with `-Xswiftc -DDEBUG`.)
#if DEBUG
import Foundation

/// A scripted Riftwing player, for testing and debugging only: the difficulty harness and the
/// regression tests measure the mode with it. It reads only what a player sees on screen (the
/// run's public state and the gallery's shape) and keeps a little state of its own (re-plan
/// timers, a seeded random source, whether its flap control is down), so it is deterministic
/// for a given seed. Like a person, it must let go of flap between flaps.
public struct RiftwingPilot: Sendable {
    public enum Skill: String, Sendable, CaseIterable {
        /// Never touches the controls.
        case idle
        /// The stand-in for a first-time player: flaps to stay airborne at a comfortable height,
        /// goes for the nearest opponent and tries to come at it from above but misjudges the
        /// height by a random amount each time, picks up pods when they are close, flees an
        /// opponent above it only some of the time, never dives, ignores mines, and re-plans
        /// only about three times a second, so it reacts late.
        case novice
        /// Plays well: re-plans ten times a second, keeps height over its target and comes
        /// down on it, stoops when high above, gets out from under threats, catches falling
        /// pods, frees pods before they hatch, goes for Gleaners holding pods, steers round
        /// mines, rides vents when it has far to climb, and keeps out of the gas.
        case competent
        /// Exploit: flies to the highest ledge and stands on it, never rescuing.
        case topLedgeSitter
        /// Exploit: flaps to stay pressed against the roof, holding its place.
        case roofHoverer
        /// Exploit: flies into the nearest vent and rides it, flapping only to keep out of the
        /// Rift.
        case ventRider
        /// Exploit: flies to the lowest ledge and sits on it.
        case lowHider
        /// Exploit: chases the nearest opponent at its own height, never trying to get above
        /// it, so most meetings bounce.
        case levelBouncer
    }

    public let skill: Skill
    private var rng: SeededRNG
    private var replanIn = 0.0
    private var goal = Vec2(450, 350)
    /// The speed across of what it is chasing, so it keeps up rather than trailing.
    private var goalVel = 0.0
    private var flapDown = false
    private var sinceFlap = 9.0
    private var diving = false
    private var flapGap = 0.2
    private var heightError = 20.0
    private var lazy = false
    /// Its goal is a pod: it will go lower than usual for it.
    private var chasingPod = false
    /// Where it was last steering for (for tracing).
    public private(set) var lastTarget = Vec2.zero
    /// Exploit bots: the ledge or vent it settled on.
    private var spot: Int?

    public init(skill: Skill, seed: UInt64) {
        self.skill = skill
        rng = SeededRNG(seed: seed ^ 0x51F7_0B07_7A11_0003)
    }

    public mutating func input(for run: RiftwingRun) -> RiftwingInput {
        sinceFlap += RiftwingRun.timeStep
        guard run.rider.isAlive, !run.isGameOver else {
            flapDown = false
            diving = false
            spot = nil
            return RiftwingInput()
        }
        switch skill {
        case .idle: return RiftwingInput()
        case .novice: return noviceInput(run)
        case .competent: return competentInput(run)
        case .topLedgeSitter: return sitterInput(run, high: true)
        case .lowHider: return sitterInput(run, high: false)
        case .roofHoverer: return roofInput(run)
        case .ventRider: return ventInput(run)
        case .levelBouncer: return bouncerInput(run)
        }
    }

    // MARK: Novice

    private mutating func noviceInput(_ run: RiftwingRun) -> RiftwingInput {
        let me = run.rider.body
        replanIn -= RiftwingRun.timeStep
        if replanIn <= 0 {
            replanIn = rng.range(0.28...0.42)
            flapGap = rng.range(0.17...0.3)
            heightError = rng.chance(0.15) ? rng.range(-15...5) : rng.range(0...45)
            lazy = rng.chance(0.15)
            goal = noviceGoal(run)
        }
        var low = chasingPod ? 85.0 : 110.0
        if run.breath != .calm { low = min(run.breathLevel + 35, run.tuning.roof - 20) }
        let target = routed(run, me, Vec2(goal.x, max(goal.y, low)))
        let steer = steerTo(run, me, target.x, speed: 190)
        let lookahead = lazy ? 0.08 : 0.16
        let panic = me.pos.y < 75
        let flap = flapControl(run, me, targetY: target.y, lookahead: panic ? 0.25 : lookahead,
                               gap: panic ? 0.16 : flapGap)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap)
    }

    private mutating func noviceGoal(_ run: RiftwingRun) -> Vec2 {
        let me = run.rider.body
        chasingPod = false
        let rigs = run.opponents.filter { $0.role.isRig && !isWaking($0) }
        // An opponent above and close: it tries to climb away, some of the time.
        if let threat = rigs.filter({ run.wrapDistance($0.pos, me.pos) < 110 && $0.pos.y > me.pos.y + 6 })
            .min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }), rng.chance(0.5) {
            let away: Double = run.dxWrap(threat.pos.x, me.pos.x) >= 0 ? 1 : -1
            return Vec2(run.wrapX(me.pos.x + away * 150), min(threat.pos.y + 50, 560))
        }
        // A pod close by, or one about to hatch (it is flashing) not too far off.
        if let pod = run.pods.filter({ p in
            guard isFreeable(p) else { return false }
            let gap = run.wrapDistance(p.pos, me.pos)
            if case .resting = p.state, p.hatchIn < run.tuning.hatchWarning { return true }
            return gap < 230
        })
            .min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }) {
            chasingPod = true
            return Vec2(pod.pos.x, pod.pos.y - 12)
        }
        // A Gleaner with a pod, if it is not far.
        if let gleaner = run.opponents.first(where: { $0.role == .gleaner && holdsPod($0) && run.wrapDistance($0.pos, me.pos) < 300 }) {
            return Vec2(gleaner.pos.x, gleaner.pos.y + 10)
        }
        // The nearest opponent, from above as it judges it.
        if var target = rigs.min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }) {
            // It steers a little ahead of a moving opponent, as anyone chasing does.
            target.body.pos.x = run.wrapX(target.pos.x + target.vel.x * 0.3)
            let dx = run.dxWrap(me.pos.x, target.pos.x)
            if me.pos.y > target.pos.y + 12, abs(dx) < 50 {
                return Vec2(target.pos.x, target.pos.y + rng.range(0...26))
            }
            // Well above it: it does not chase upward, but keeps its height a little way off
            // and waits for the opponent to come down.
            if target.pos.y > me.pos.y + 30 {
                let away: Double = dx >= 0 ? -1 : 1
                return Vec2(run.wrapX(me.pos.x + (abs(dx) < 160 ? away * 80 : 0)), min(max(me.pos.y, 200), 430))
            }
            let want = target.pos.y + heightError
            // Still below where it means to be and already close across: it climbs first.
            if me.pos.y < want - 15, abs(dx) < 110 {
                return Vec2(me.pos.x, want)
            }
            return Vec2(target.pos.x, want)
        }
        // Nothing about: drift at a comfortable height.
        return Vec2(run.wrapX(me.pos.x + rng.range(-150...150)), rng.range(260...420))
    }

    // MARK: Competent

    private mutating func competentInput(_ run: RiftwingRun) -> RiftwingInput {
        let me = run.rider.body
        replanIn -= RiftwingRun.timeStep
        if replanIn <= 0 {
            replanIn = 0.1
            goal = competentGoal(run)
        }
        let low = run.breath == .calm ? (chasingPod ? 55.0 : 105.0) : min(run.breathLevel + 45, run.tuning.roof - 20)
        var target = Vec2(goal.x, max(goal.y, diving ? -1e9 : low))
        // Mines: keep a clear berth of the ones near the path.
        let ahead = me.pos + me.vel * 0.3
        for mine in run.mines where run.wrapDistance(mine.pos, ahead) < 75 || run.wrapDistance(mine.pos, me.pos) < 60 {
            let away: Double = run.dxWrap(mine.pos.x, me.pos.x) >= 0 ? 1 : -1
            target = Vec2(run.wrapX(me.pos.x + away * 90), me.pos.y >= mine.pos.y ? mine.anchor.y + 35 : mine.pos.y - 45)
            diving = false
        }
        if diving, me.pos.y < max(low + 120, 230) { diving = false }
        if !diving { target = routed(run, me, target) }
        lastTarget = target
        let steer = steerTo(run, me, target.x, speed: diving ? 120 : 225, with: target.x == goal.x ? goalVel : 0)
        let flap = diving ? false : flapControl(run, me, targetY: target.y, lookahead: 0.14, gap: 0.11)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap, dive: diving)
    }

    private mutating func competentGoal(_ run: RiftwingRun) -> Vec2 {
        let me = run.rider.body
        let myHeight = run.clashHeight(me)
        goalVel = 0
        chasingPod = false
        let rigs = run.opponents.filter { $0.role.isRig }

        // A falling pod it can reach before it lands or is lost, unless something is right on it.
        let crowded = rigs.contains { run.wrapDistance($0.pos, me.pos) < 75 && run.clashHeight($0.body) > myHeight - 4 }
        if !crowded, let spot = reachablePod(run) {
            diving = false
            chasingPod = true
            return spot
        }

        // A threat: a rig at or above its height, close and closing.
        if !run.rider.isInvulnerable, let threat = rigs.filter({ o in
            guard !isWaking(o) else { return false }
            let gap = run.wrapDistance(o.pos, me.pos)
            let dx = abs(run.dxWrap(me.pos.x, o.pos.x))
            // Close and at or above it, or coming down on it from above.
            let close = gap < 120 && run.clashHeight(o.body) > myHeight - 4
            let stooping = dx < 100 && o.pos.y > me.pos.y + 10 && o.pos.y - me.pos.y < 320 && (o.vel.y < -80 || o.body.isDiving)
            // A Warden high above and close across can dive at any moment.
            let poised = o.role == .warden && dx < 120 && o.pos.y > me.pos.y + 50 && o.pos.y - me.pos.y < 260
            return close || stooping || poised
        }).min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }) {
            diving = false
            let away: Double = run.dxWrap(threat.pos.x, me.pos.x) >= 0 ? 1 : -1
            let roofy = threat.pos.y > run.tuning.roof - 60
            let falling = threat.vel.y < -80 || threat.body.isDiving
            // Out from under a falling one sideways; above a close one if it can.
            let y = roofy || falling ? me.pos.y : threat.pos.y + 55
            return Vec2(run.wrapX(me.pos.x + away * 150), y)
        }


        // A Gleaner holding a pod.
        if let gleaner = run.opponents.first(where: { $0.role == .gleaner && holdsPod($0) }) {
            diving = false
            goalVel = gleaner.vel.x
            return Vec2(gleaner.pos.x, gleaner.pos.y + 12)
        }

        // A pod about to hatch, or a pod close by.
        if let pod = run.pods.filter({ p in
            guard case .resting = p.state else { return false }
            return p.hatchIn < 7 || run.wrapDistance(p.pos, me.pos) < 200
        }).min(by: { $0.hatchIn < $1.hatchIn }) {
            diving = false
            return Vec2(pod.pos.x, pod.pos.y - 12)
        }

        // Attack the rig it can best get above.
        let attackable = rigs.filter { !isWaking($0) || run.wrapDistance($0.pos, me.pos) < 200 }
        if let target = attackable.min(by: { cost(run, $0) < cost(run, $1) }) {
            let dx = run.dxWrap(me.pos.x, target.pos.x)
            let above = me.pos.y - target.pos.y
            let lead = Vec2(run.wrapX(target.pos.x + target.vel.x * 0.25), target.pos.y)
            goalVel = target.vel.x
            if diving {
                if above > 4, abs(dx) < 55 { return lead }
                diving = false
            }
            if above > 110, abs(dx) < 30, target.pos.y > 250 {
                diving = true
                return lead
            }
            if above > 12, abs(dx) < 50 {
                return Vec2(lead.x, target.pos.y + 18)
            }
            let over = min(target.pos.y + 50, run.tuning.roof - me.radius - 2)
            // Far to climb and a vent on the way: ride it.
            if over - me.pos.y > 160, let vent = run.vents.min(by: { abs(run.dxWrap(me.pos.x, $0.x)) < abs(run.dxWrap(me.pos.x, $1.x)) }),
               abs(run.dxWrap(me.pos.x, vent.x)) < 130, me.pos.y < vent.top - 40 {
                return Vec2(vent.x, over)
            }
            return Vec2(target.pos.x, over)
        }

        // Pods left.
        if let pod = run.pods.filter({ isFreeable($0) }).min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }) {
            return Vec2(pod.pos.x, pod.pos.y - 12)
        }
        diving = false
        return Vec2(450, 380)
    }

    /// Where to meet the nearest falling pod it can reach before the pod lands or is lost.
    private func reachablePod(_ run: RiftwingRun) -> Vec2? {
        let me = run.rider.body
        var best: (Vec2, Double)?
        for pod in run.pods where pod.state == .falling {
            let gap = run.wrapDistance(pod.pos, me.pos)
            let t = gap / 230
            let y = max(pod.pos.y + max(pod.vel.y, -pod.terminal) * t, pod.pos.y - pod.terminal * t)
            guard gap < 360, y > run.tuning.riftLevel + 25 else { continue }
            if best == nil || gap < best!.1 {
                best = (Vec2(run.wrapX(pod.pos.x + pod.vel.x * t), y - 10), gap)
            }
        }
        return best?.0
    }

    /// How awkward a target is: its distance, plus a penalty for each unit it is above.
    private func cost(_ run: RiftwingRun, _ o: RiftwingOpponent) -> Double {
        let me = run.rider.body
        return run.wrapDistance(o.pos, me.pos) + max(o.pos.y - me.pos.y, 0) * 1.5 + (o.blows > 1 ? 60 : 0)
    }

    // MARK: Exploits

    private mutating func sitterInput(_ run: RiftwingRun, high: Bool) -> RiftwingInput {
        let me = run.rider.body
        let ledges = run.ledges
        if spot == nil || spot! >= ledges.count {
            spot = ledges.indices.max { high ? ledges[$0].top < ledges[$1].top : ledges[$0].top > ledges[$1].top }
        }
        let ledge = ledges[spot!]
        if me.ledge == spot {
            // Stay in the middle of it.
            let dx = ledge.midX - me.pos.x
            return RiftwingInput(stick: Vec2(abs(dx) > 20 ? clamp(dx / 40, -1, 1) : 0, 0))
        }
        let target = Vec2(ledge.midX, ledge.top + 40)
        let steer = steerTo(run, me, target.x, speed: 160)
        let over = abs(run.dxWrap(me.pos.x, target.x)) < 40
        let flap = flapControl(run, me, targetY: over ? ledge.top + 15 : target.y, lookahead: 0.25, gap: 0.14)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap)
    }

    private mutating func roofInput(_ run: RiftwingRun) -> RiftwingInput {
        let me = run.rider.body
        let steer = clamp(-me.vel.x / 60, -1, 1)
        let flap = flapControl(run, me, targetY: run.tuning.roof - 5, lookahead: 0.3, gap: 0.12)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap)
    }

    private mutating func ventInput(_ run: RiftwingRun) -> RiftwingInput {
        let me = run.rider.body
        if spot == nil || spot! >= run.vents.count {
            spot = run.vents.indices.min { abs(run.dxWrap(me.pos.x, run.vents[$0].x)) < abs(run.dxWrap(me.pos.x, run.vents[$1].x)) }
        }
        let vent = run.vents[spot!]
        let steer = steerTo(run, me, vent.x, speed: 120)
        let inColumn = abs(run.dxWrap(me.pos.x, vent.x)) < run.tuning.ventHalfWidth
        let flap = flapControl(run, me, targetY: inColumn ? 70 : vent.top - 60, lookahead: 0.3, gap: 0.14)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap)
    }

    private mutating func bouncerInput(_ run: RiftwingRun) -> RiftwingInput {
        let me = run.rider.body
        replanIn -= RiftwingRun.timeStep
        if replanIn <= 0 {
            replanIn = 0.1
            if let target = run.opponents.filter({ $0.role.isRig })
                .min(by: { run.wrapDistance($0.pos, me.pos) < run.wrapDistance($1.pos, me.pos) }) {
                goal = target.pos
            } else {
                goal = Vec2(450, 350)
            }
        }
        let steer = steerTo(run, me, goal.x, speed: 200)
        let flap = flapControl(run, me, targetY: max(goal.y, 100), lookahead: 0.2, gap: 0.11)
        return RiftwingInput(stick: Vec2(steer, 0), flap: flap)
    }

    // MARK: Helpers

    /// Routes round a ledge between the rig and `target`: rather than climbing into a ledge's
    /// underside or dropping onto its top, it heads for the nearer end and passes it, climbing or
    /// dropping only once clear of the rock.
    private func routed(_ run: RiftwingRun, _ me: RiftwingBody, _ target: Vec2) -> Vec2 {
        let r = me.radius
        let feet = r * run.tuning.feetShare, head = r * run.tuning.headShare
        for ledge in run.ledges {
            let bottom = ledge.top - run.tuning.ledgeThickness
            let leftEnd = ledge.minX - r - 20, rightEnd = ledge.maxX + r + 20
            let overMe = me.pos.x > ledge.minX - r && me.pos.x < ledge.maxX + r
            let overTarget = target.x > ledge.minX - r && target.x < ledge.maxX + r
            let climbing = target.y > ledge.top && me.pos.y + head < bottom + 4
            let dropping = target.y < bottom && me.pos.y - feet > ledge.top - 4
            guard climbing || dropping, overMe || overTarget else { continue }
            // The end to pass: toward the target if it is beyond the ledge, else the nearer.
            let goLeft: Bool
            if overTarget {
                goLeft = abs(run.dxWrap(me.pos.x, leftEnd)) < abs(run.dxWrap(me.pos.x, rightEnd))
            } else {
                goLeft = run.dxWrap(me.pos.x, target.x) < 0
            }
            let end = goLeft ? leftEnd : rightEnd
            if overMe {
                // Under (or over) the rock: get out sideways first, holding clear of it.
                let y = climbing ? min(target.y, bottom - head - 6) : max(target.y, ledge.top + feet + 8)
                return Vec2(run.wrapX(end), climbing ? y : max(y, me.pos.y))
            }
            if overTarget, abs(run.dxWrap(me.pos.x, end)) < 90 {
                // Beside it: climb or drop past the end before going over (or under).
                return Vec2(run.wrapX(end), target.y)
            }
        }
        // A vent's rising air holds it up: to go down, it slips out of the column first.
        if target.y < me.pos.y - 30 {
            for vent in run.vents where me.pos.y < vent.top + 10 {
                let dx = run.dxWrap(vent.x, me.pos.x)
                let clear = run.tuning.ventHalfWidth + r * 0.5 + 12
                guard abs(dx) < clear else { continue }
                let side: Double = abs(run.dxWrap(vent.x, target.x)) > 4 ? (run.dxWrap(vent.x, target.x) > 0 ? 1 : -1) : (dx >= 0 ? 1 : -1)
                return Vec2(run.wrapX(vent.x + side * (clear + 6)), me.pos.y)
            }
        }
        return target
    }

    /// Presses flap when the rig will sink below `targetY` within `lookahead` seconds, at most
    /// once every `gap` seconds, letting go between presses.
    private mutating func flapControl(_ run: RiftwingRun, _ me: RiftwingBody, targetY: Double, lookahead: Double,
                                      gap: Double) -> Bool {
        if flapDown {
            flapDown = false
            return false
        }
        guard sinceFlap >= gap else { return false }
        let g = run.tuning.gravity
        let predicted = me.pos.y + me.vel.y * lookahead - 0.5 * g * lookahead * lookahead
        guard predicted < targetY || (me.isGrounded && targetY > me.pos.y + 20) else { return false }
        flapDown = true
        sinceFlap = 0
        return true
    }

    /// The steer that brings the rig over `x` (round the join) without overshooting.
    private func steerTo(_ run: RiftwingRun, _ me: RiftwingBody, _ x: Double, speed: Double, with vx: Double = 0) -> Double {
        let dx = run.dxWrap(me.pos.x, x)
        let desired = clamp(vx + dx * 2.2, -speed, speed)
        return clamp((desired - me.vel.x) / 45, -1, 1)
    }

    private func isWaking(_ o: RiftwingOpponent) -> Bool {
        if case .waking = o.state { true } else { false }
    }

    private func holdsPod(_ o: RiftwingOpponent) -> Bool {
        switch o.state {
        case .grabbing, .carrying: true
        default: false
        }
    }

    private func isFreeable(_ pod: RiftwingPod) -> Bool {
        switch pod.state {
        case .falling, .resting, .seized: true
        case .freed, .lost: false
        }
    }
}
#endif
