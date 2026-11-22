import GameCore

extension RiftwingRun {
    // MARK: Opponents

    mutating func updateOpponents(_ dt: Double) {
        var index = 0
        while index < opponents.count {
            defer { index += 1 }
            guard !opponents[index].isDead else { continue }
            opponents[index].clashCooldown = max(0, opponents[index].clashCooldown - dt)
            opponents[index].flapCooldown -= dt
            if opponents[index].role == .gleaner {
                updateGleaner(index, dt)
                continue
            }
            var control = RigControl()
            switch opponents[index].state {
            case .waking(let remaining):
                // Standing where it hatched; it takes off with a flap when it wakes.
                if remaining - dt <= 0 {
                    opponents[index].state = .flying
                    control.flap = true
                } else {
                    opponents[index].state = .waking(remaining: remaining - dt)
                }
            case .staggered(let remaining):
                // Tumbling: no control at all.
                opponents[index].state = remaining - dt <= 0 ? .flying : .staggered(remaining: remaining - dt)
            case .flying:
                control = rigBehaviour(index, dt)
            case .seeking, .grabbing, .carrying, .leaving:
                break
            }
            var body = opponents[index].body
            let wasDiving = body.isDiving
            _ = fly(&body, control, flight(for: opponents[index]), dt)
            opponents[index].body = body
            if body.isDiving, !wasDiving {
                events.append(.opponentDived(id: opponents[index].id, role: opponents[index].role, at: body.pos))
            }
            if body.pos.y < tuning.riftLevel {
                opponentFell(at: index, cause: .rift)
            }
        }
    }

    /// An opponent's flight numbers: its role's, at its eased speed.
    func flight(for opponent: RiftwingOpponent) -> FlightParams {
        let stats = tuning.stats(for: opponent.role)
        return FlightParams(maxSpeed: opponent.speed, airAccel: stats.airAccel, flapImpulse: stats.flapImpulse,
                            flapThrust: tuning.flapThrust * 0.5, maxRise: tuning.maxRise, runSpeed: tuning.runSpeed * 0.6)
    }

    /// What a rig's role does this step.
    private mutating func rigBehaviour(_ index: Int, _ dt: Double) -> RigControl {
        switch opponents[index].role {
        case .glider: gliderBehaviour(index, dt)
        case .striker: strikerBehaviour(index, dt)
        case .warden: wardenBehaviour(index, dt)
        case .sower: sowerBehaviour(index, dt)
        case .gleaner: RigControl()
        }
    }

    /// The lowest height an opponent lets itself sink to: out of the Rift, and above the gas
    /// while the Rift is about to breathe or breathing.
    private var opponentFloor: Double {
        breath == .calm || isBreathFilling ? tuning.opponentFloor : min(max(tuning.opponentFloor, breathLevel + 45), tuning.roof - 40)
    }

    /// The highest a hunter climbs: just under the roof's band, where a meeting would be level.
    private func roofLine(_ o: RiftwingOpponent) -> Double {
        tuning.roof - o.body.radius - tuning.roofBand - 6
    }

    /// The highest the centre of a rig of `radius` can be at `x`, at about height `y`: just
    /// under the lowest rock above it there (a ledge's underside, or the roof).
    func ceilingHeight(at x: Double, above y: Double, radius: Double) -> Double {
        let head = radius * tuning.headShare
        var cap = tuning.roof - radius
        for ledge in ledges where ledge.spans(x) {
            let bottom = ledge.top - tuning.ledgeThickness
            if bottom >= y + head - 1 { cap = min(cap, bottom - head) }
        }
        return cap
    }

    /// The rider is up against rock (the roof or a ledge's underside), where it cannot climb.
    var isRiderPinned: Bool {
        rider.isAlive && rider.body.pos.y
            > ceilingHeight(at: rider.body.pos.x, above: rider.body.pos.y - 1, radius: rider.body.radius) - tuning.pinnedBand
    }

    /// The rider has stayed up against rock for `RiftwingTuning.pinnedPatience`: hunters come up
    /// under the same rock after it and hover there, gently, while it bobs from bumping the rock.
    private var riderCamping: Bool { riderPinnedFor >= tuning.pinnedPatience }

    /// The rider is camping: pinned against rock for `pinnedPatience`, or staying within
    /// `stillRadius` of one place for `gliderDrawAfter`. Opponents show it no leniency or mercy.
    public var isRiderCamping: Bool {
        rider.isAlive && (riderPinnedFor >= tuning.pinnedPatience || riderStillFor >= tuning.gliderDrawAfter)
    }

    /// The rider is pressed up near the roof (but not camping there): a hunter could at best
    /// meet it level, so it hangs back below.
    private var riderAtRoof: Bool {
        rider.body.pos.y > tuning.roof - rider.body.radius - tuning.roofBand - 15
    }

    /// The highest a hunter can be over the rider, under the rock the rider is under.
    private func hunterCap(_ o: RiftwingOpponent) -> Double {
        ceilingHeight(at: rider.body.pos.x, above: rider.body.pos.y - 5, radius: o.body.radius)
    }

    /// Where a hunter heads for `goal`: if a ledge overhead stands between it and a goal above
    /// that is not under the same ledge, it first goes out past the ledge's nearer end.
    private func routeRound(_ o: RiftwingOpponent, _ goal: Vec2) -> Vec2 {
        let head = o.body.radius * tuning.headShare
        guard goal.y > o.pos.y + 10, let ledge = ledges.first(where: { l in
            let bottom = l.top - tuning.ledgeThickness
            return l.spans(o.pos.x) && bottom >= o.pos.y + head - 1 && bottom < goal.y
        }) else { return goal }
        if ledge.spans(goal.x), goal.y < ledge.top { return goal }
        let left = ledge.minX - o.body.radius - 20, right = ledge.maxX + o.body.radius + 20
        let toward = dxWrap(o.pos.x, goal.x)
        let x = ledge.spans(goal.x) ? (abs(dxWrap(o.pos.x, left)) < abs(dxWrap(o.pos.x, right)) ? left : right)
            : (toward < 0 ? left : right)
        return Vec2(wrapX(x), o.pos.y)
    }

    /// Flap as `flapToHold` would, but never into the rock above: only when the flap's rise
    /// stops short of it, so a hunter holds steady under a ceiling instead of bobbing.
    private mutating func flapUnderRock(_ index: Int, height: Double) -> Bool {
        let o = opponents[index]
        let ceiling = ceilingHeight(at: o.pos.x, above: o.pos.y, radius: o.body.radius)
        let impulse = tuning.stats(for: o.role).flapImpulse
        let v = max(o.body.vel.y, min(o.body.vel.y + impulse, tuning.maxRise))
        let apex = o.pos.y + (v > 0 ? v * v / (2 * tuning.gravity) : 0)
        if apex > ceiling - 0.5, o.pos.y > opponentFloor + 10 { return false }
        return flapToHold(index, height: height)
    }

    /// Steer toward `x` round the join, braking so it does not overshoot.
    private func steer(_ body: RiftwingBody, toward x: Double, speed: Double) -> Double {
        let dx = dxWrap(body.pos.x, x)
        let desired = clamp(dx * 2.5, -speed, speed)
        return clamp((desired - body.vel.x) / 50, -1, 1)
    }

    /// Flap if it will sink below `height` soon, no faster than its wingbeat. Below the
    /// opponent floor it always tries.
    private mutating func flapToHold(_ index: Int, height: Double, lookahead: Double = 0.25) -> Bool {
        let o = opponents[index]
        guard o.flapCooldown <= 0, !o.body.isDiving, o.body.reopen == 0 else { return false }
        let target = max(height, opponentFloor)
        // Low down it looks further ahead, so a fall is caught before it reaches the Rift.
        let ahead = o.body.pos.y < opponentFloor + 60 ? max(lookahead, 0.45) : lookahead
        let predicted = o.body.pos.y + o.body.vel.y * ahead - 0.5 * tuning.gravity * ahead * ahead
        let falling = o.body.pos.y < opponentFloor + 80 && o.body.vel.y < -100
        guard predicted < target || falling else { return false }
        let interval = tuning.stats(for: o.role).flapInterval
        opponents[index].flapCooldown = falling || o.body.pos.y < opponentFloor ? interval * 0.6 : interval
        return true
    }

    /// Glider: wanders to a new place every few seconds, flapping lazily and skipping some
    /// flaps, so it holds height badly. It pays the rider little attention: early on it will not
    /// flap up into a rider just above it, and a rider that stays put for
    /// `RiftwingTuning.gliderDrawAfter` draws its wandering to about the rider's height.
    private mutating func gliderBehaviour(_ index: Int, _ dt: Double) -> RigControl {
        opponents[index].timer -= dt
        let o = opponents[index]
        if o.timer <= 0 || wrapDistance(o.goal, o.pos) < 30 {
            if rider.isAlive, riderStillFor >= tuning.gliderDrawAfter {
                // A rider that stays put draws it: it wanders about the rider's height nearby,
                // so no perch is safe from clashes for long.
                let y = min(rider.body.pos.y + rng.range(-10...35), tuning.roof - o.body.radius)
                opponents[index].goal = Vec2(wrapX(rider.body.pos.x + rng.range(-140...140)), max(y, tuning.opponentFloor))
                opponents[index].timer = rng.range(1.5...3)
            } else {
                // Early on it keeps lower in the gallery, so a new player finds it below them.
                let band = tuning.gliderBand
                let top = max(band.upperBound - director.gliderBandEase * o.ease, band.lowerBound)
                opponents[index].goal = Vec2(rng.range(0...tuning.width), rng.range(band.lowerBound...top))
                opponents[index].timer = rng.range(tuning.gliderWander)
            }
        }
        let goal = routeRound(o, opponents[index].goal)
        var control = RigControl(steer: steer(o.body, toward: goal.x, speed: o.speed) * 0.7)
        let urgent = o.pos.y < opponentFloor + 80 && o.body.vel.y < -100
        if flapToHold(index, height: goal.y, lookahead: 0.2) {
            var skip = tuning.gliderSkip + director.gliderSkipEase * o.ease
            // Early on it does not flap up into a rider just above it (unless the rider is
            // camping there).
            if rider.isAlive, !isRiderCamping, abs(dxWrap(o.pos.x, rider.body.pos.x)) < 90,
               (0...70).contains(rider.body.pos.y - o.pos.y) {
                skip += director.gliderShyEase * o.ease
            }
            control.flap = urgent || o.pos.y < opponentFloor + 40 || !rng.chance(min(skip, 1))
        }
        return control
    }

    /// Striker: climbs to a height above the rider, then commits to a strike: it stops
    /// flapping and comes down on the rider, tracking it, until it is well below or the strike
    /// has run its time. Then it recovers, flying off level for a moment (when it is open to a
    /// blow from above), and climbs again. Below the rider and close, it backs off sideways
    /// while it climbs; with the rider up against rock it comes up under the same rock after it.
    private mutating func strikerBehaviour(_ index: Int, _ dt: Double) -> RigControl {
        opponents[index].timer -= dt
        opponents[index].phaseTime += dt
        let o = opponents[index]
        guard rider.isAlive else {
            opponents[index].phase = .climbing
            if o.timer <= 0 {
                opponents[index].timer = 1
                opponents[index].goal = Vec2(rng.range(0...tuning.width), rng.range(250...480))
            }
            let goal = opponents[index].goal
            var control = RigControl(steer: steer(o.body, toward: goal.x, speed: o.speed))
            control.flap = flapToHold(index, height: goal.y)
            return control
        }
        let target = rider.body.pos
        let above = o.pos.y - target.y
        let dx = dxWrap(o.pos.x, target.x)
        switch o.phase {
        case .striking:
            if above < -30 || o.phaseTime > tuning.strikerStrikeTime || o.pos.y < opponentFloor + 20 {
                opponents[index].phase = .recovering
                opponents[index].phaseTime = 0
                opponents[index].goal = Vec2(wrapX(o.pos.x - (dx >= 0 ? 1 : -1) * 200), max(o.pos.y, opponentFloor + 30))
            } else {
                // Glide down on it, tracking it; flap only to keep out of the Rift.
                var control = RigControl(steer: steer(o.body, toward: target.x, speed: o.speed) * tuning.strikerStrikeSteer)
                control.flap = flapToHold(index, height: opponentFloor)
                return control
            }
        case .recovering:
            if o.phaseTime > tuning.strikerRecover * (1 + director.strikerRecoverEase * o.ease) {
                opponents[index].phase = .climbing
                opponents[index].phaseTime = 0
                opponents[index].timer = 0
            }
        case .climbing:
            if o.phaseTime > tuning.strikerPatience {
                // It could not get above in time: it breaks off and flies away level for a moment.
                opponents[index].phase = .recovering
                opponents[index].phaseTime = 0
                opponents[index].goal = Vec2(wrapX(o.pos.x - (dx >= 0 ? 1 : -1) * 200),
                                             max(min(o.pos.y - 40, roofLine(o) - 60), opponentFloor + 30))
            } else if o.timer <= 0 {
                opponents[index].timer = tuning.hunterReplan + director.strikerReplanEase * o.ease
                let climb = tuning.strikerClimb * (1 - director.strikerClimbEase * o.ease)
                let reach = tuning.strikerStrikeReach * (1 - director.strikerReachEase * o.ease)
                let cap = hunterCap(o) - 3
                if riderCamping {
                    // The rider stays up against rock: it comes up under the same rock beside
                    // it, then across at it, holding steady while the rider bobs.
                    if o.pos.y < cap - 25, abs(dx) < 110 {
                        opponents[index].goal = Vec2(wrapX(target.x - (dx >= 0 ? 1 : -1) * 160), cap)
                    } else {
                        opponents[index].goal = Vec2(target.x, cap)
                    }
                } else if riderAtRoof {
                    // Nothing is won level at the roof: it breaks off to a place below and away,
                    // fixed when it turns, so a rider coming down can catch it there.
                    opponents[index].phase = .recovering
                    opponents[index].phaseTime = 0
                    opponents[index].goal = Vec2(wrapX(target.x - (dx >= 0 ? 1 : -1) * 150), target.y - 110)
                } else if above > 15, abs(dx) < reach {
                    opponents[index].phase = .striking
                    opponents[index].phaseTime = 0
                } else if above < 0, abs(dx) < 130 {
                    // Under it: get out from beneath while climbing.
                    opponents[index].goal = Vec2(wrapX(target.x - (dx >= 0 ? 1 : -1) * 170), min(target.y + climb, cap))
                } else {
                    opponents[index].goal = Vec2(target.x, min(target.y + climb, roofLine(o), cap))
                }
            }
        }
        let goal = routeRound(o, opponents[index].goal)
        var control = RigControl(steer: steer(o.body, toward: goal.x, speed: o.speed))
        control.flap = flapUnderRock(index, height: goal.y)
        return control
    }

    /// Warden: keeps well above the rider and lines up across from it; when it is high above
    /// and close across it dives, pulling out once level or past.
    private mutating func wardenBehaviour(_ index: Int, _ dt: Double) -> RigControl {
        opponents[index].timer -= dt
        let o = opponents[index]
        var diving = o.body.isDiving
        if rider.isAlive {
            let target = rider.body.pos
            let above = o.pos.y - target.y
            let dx = dxWrap(o.pos.x, target.x)
            if diving, above < 4 || abs(dx) > 70 || o.pos.y < opponentFloor + 60 {
                diving = false
            }
            if o.timer <= 0 {
                opponents[index].timer = tuning.hunterReplan + director.wardenReplanEase * o.ease
                if !diving, o.body.reopen == 0, above > 60, abs(dx) < tuning.wardenDiveReach * 0.5,
                   target.y > opponentFloor + 40, rng.chance(1 - director.wardenDiveEase * o.ease) {
                    diving = true
                }
                let cap = hunterCap(o) - 3
                if riderCamping {
                    // Staying up against rock: it comes up under the same rock beside it, then
                    // across.
                    if o.pos.y < cap - 25, abs(dx) < 110 {
                        opponents[index].goal = Vec2(wrapX(target.x - (dx >= 0 ? 1 : -1) * 160), cap)
                    } else {
                        opponents[index].goal = Vec2(target.x, cap)
                    }
                } else if riderAtRoof {
                    opponents[index].goal = Vec2(wrapX(target.x - (dx >= 0 ? 1 : -1) * 160), target.y - 120)
                } else {
                    let high = min(max(target.y + tuning.wardenHeight, 220), roofLine(o), cap)
                    opponents[index].goal = Vec2(target.x, high)
                }
            }
        } else {
            diving = false
            if o.timer <= 0 {
                opponents[index].timer = 1
                opponents[index].goal = Vec2(rng.range(0...tuning.width), rng.range(300...500))
            }
        }
        let goal = diving ? rider.body.pos : routeRound(o, opponents[index].goal)
        var control = RigControl(steer: steer(o.body, toward: goal.x, speed: o.speed), dive: diving)
        if !diving { control.flap = flapUnderRock(index, height: goal.y) }
        return control
    }

    /// Sower: drifts across the gallery in its band, laying a mine every few seconds (never
    /// close to the rider), at most a few at once; the oldest goes when a new one is laid.
    private mutating func sowerBehaviour(_ index: Int, _ dt: Double) -> RigControl {
        opponents[index].timer -= dt
        opponents[index].mineTimer -= dt
        let o = opponents[index]
        if o.timer <= 0 {
            opponents[index].timer = rng.range(5...8)
            opponents[index].goal.y = rng.range(tuning.sowerBand)
        }
        if o.mineTimer <= 0 {
            if !rider.isAlive || wrapDistance(o.pos, rider.body.pos) > tuning.mineClearance {
                layMine(by: index)
                opponents[index].mineTimer = tuning.mineInterval * (1 + director.sowerIntervalEase * o.ease)
            } else {
                opponents[index].mineTimer = 0.5
            }
        }
        let desired = o.drift * o.speed
        var control = RigControl(steer: clamp((desired - o.body.vel.x) / 40, -1, 1))
        control.flap = flapToHold(index, height: opponents[index].goal.y)
        return control
    }

    private mutating func layMine(by index: Int) {
        let sower = opponents[index]
        let anchor = Vec2(sower.pos.x, sower.pos.y - sower.body.radius * 0.5)
        let id = takeID()
        let phase = rng.range(0...(2 * .pi))
        let mine = RiftwingMine(id: id, sower: sower.id, anchor: anchor,
                                pos: minePosition(anchor: anchor, phase: phase, age: 0), age: 0, phase: phase)
        mines.append(mine)
        events.append(.mineLaid(id: id, by: sower.id, at: mine.pos))
        let limit = max(tuning.minesPerSower - Int((director.sowerMinesEase * sower.ease).rounded()), 1)
        let own = mines.filter { $0.sower == sower.id }
        if own.count > limit, let oldest = own.first, let at = mines.firstIndex(where: { $0.id == oldest.id }) {
            events.append(.mineCleared(id: oldest.id, at: oldest.pos, reason: .expired))
            mines.remove(at: at)
        }
    }

    /// Where a mine hangs: below its anchor on the tether, swaying.
    func minePosition(anchor: Vec2, phase: Double, age: Double) -> Vec2 {
        Vec2(wrapX(anchor.x + sine(phase + age * 2 * .pi * 0.6) * tuning.mineSway), anchor.y - tuning.mineTether)
    }

    mutating func updateMines(_ dt: Double) {
        guard !mines.isEmpty else { return }
        var kept: [RiftwingMine] = []
        kept.reserveCapacity(mines.count)
        for var mine in mines {
            mine.age += dt
            if mine.age >= tuning.mineLifetime {
                events.append(.mineCleared(id: mine.id, at: mine.pos, reason: .expired))
                continue
            }
            mine.pos = minePosition(anchor: mine.anchor, phase: mine.phase, age: mine.age)
            kept.append(mine)
        }
        mines = kept
    }

    // MARK: Gleaners

    /// Gleaner: free flight, not on a rig. It goes for a resting pod, holds it a moment, then
    /// carries it to the nearer tunnel mouth, slowly enough that the carry always takes at
    /// least the wave's minimum time. With nothing to go for, it leaves.
    private mutating func updateGleaner(_ index: Int, _ dt: Double) {
        var o = opponents[index]
        let carryHeight = tuning.figure(o.body.radius + tuning.basePodRadius)
        switch o.state {
        case .seeking(let target):
            var podIndex = target.flatMap { id in pods.firstIndex { $0.id == id } }
            if let p = podIndex, !isResting(pods[p]) { podIndex = nil }
            if podIndex == nil {
                podIndex = nearestRestingPod(to: o.pos)
                o.state = .seeking(pod: podIndex.map { pods[$0].id })
            }
            guard let p = podIndex else {
                o.state = .leaving(exitX: nearestMouth(o.pos.x))
                break
            }
            let spot = Vec2(pods[p].pos.x, pods[p].pos.y + carryHeight)
            moveFreely(&o.body, toward: spot, speed: o.speed, dt)
            if wrapDistance(o.pos, spot) < 4 {
                o.body.pos = spot
                o.body.vel = .zero
                pods[p].state = .seized(by: o.id)
                o.state = .grabbing(pod: pods[p].id, remaining: director.gleanerGrab(forWave: max(wave, 1), tuning: tuning))
                events.append(.podSeized(id: pods[p].id, by: o.id, at: pods[p].pos))
            }
        case .grabbing(let podID, let remaining):
            guard let p = pods.firstIndex(where: { $0.id == podID }), pods[p].state == .seized(by: o.id) else {
                o.state = .seeking(pod: nil)
                break
            }
            if remaining - dt <= 0 {
                let exit = nearestMouth(o.pos.x)
                let across = abs(exit - o.pos.x)
                let minimum = director.gleanerMinCarry(forWave: max(wave, 1), tuning: tuning)
                o.speed = min(tuning.gleanerCarrySpeed * director.gleanerSpeedScale(forWave: max(wave, 1)),
                              across / max(minimum, 1e-9))
                o.state = .carrying(pod: podID, exitX: exit)
                events.append(.podCarried(id: podID, by: o.id, at: pods[p].pos))
            } else {
                o.state = .grabbing(pod: podID, remaining: remaining - dt)
            }
        case .carrying(let podID, let exitX):
            guard let p = pods.firstIndex(where: { $0.id == podID }), pods[p].state == .seized(by: o.id) else {
                o.state = .leaving(exitX: nearestMouth(o.pos.x))
                break
            }
            // Straight across to the mouth (not round the join), rising a little.
            let dir: Double = exitX > o.pos.x ? 1 : -1
            o.body.vel = Vec2(dir * o.speed, o.pos.y < 470 ? 18 : 0)
            o.body.pos = o.body.pos + o.body.vel * dt
            o.body.facing = dir
            pods[p].pos = Vec2(o.pos.x, o.pos.y - carryHeight)
            if (dir > 0 && o.pos.x >= exitX) || (dir < 0 && o.pos.x <= exitX) {
                opponents[index] = o
                losePod(at: p, cause: .carried)
                gleanerGone(index)
                return
            }
        case .leaving(let exitX):
            let dir: Double = exitX > o.pos.x ? 1 : -1
            o.body.vel = Vec2(dir * o.speed, 0)
            o.body.pos = o.body.pos + o.body.vel * dt
            o.body.facing = dir
            if (dir > 0 && o.pos.x >= exitX) || (dir < 0 && o.pos.x <= exitX) {
                opponents[index] = o
                gleanerGone(index)
                return
            }
        case .flying, .waking, .staggered:
            o.state = .seeking(pod: nil)
        }
        opponents[index] = o
        // The pod it holds hangs below it.
        if case .grabbing(let podID, _) = o.state, let p = pods.firstIndex(where: { $0.id == podID }) {
            pods[p].pos = Vec2(o.pos.x, o.pos.y - carryHeight)
        }
    }

    /// A Gleaner flew out through a mouth (carrying or not): the next may come after the gap.
    private mutating func gleanerGone(_ index: Int) {
        let o = opponents[index]
        opponents[index].isDead = true
        events.append(.opponentWithdrew(id: o.id, role: o.role, at: o.pos))
        gleanerNextAt = max(gleanerNextAt, waveClock + director.gleanerGap)
    }

    private func isResting(_ pod: RiftwingPod) -> Bool {
        if case .resting = pod.state { true } else { false }
    }

    /// The resting pod nearest `p` that no Gleaner is after.
    private func nearestRestingPod(to p: Vec2) -> Int? {
        var best: Int?
        var bestGap = Double.infinity
        for (index, pod) in pods.enumerated() where isResting(pod) {
            let claimed = opponents.contains {
                !$0.isDead && $0.role == .gleaner && $0.state == .seeking(pod: pod.id)
            }
            guard !claimed else { continue }
            let gap = wrapDistance(pod.pos, p)
            if gap < bestGap {
                bestGap = gap
                best = index
            }
        }
        return best
    }

    /// The x of the nearer tunnel mouth: the left edge (0) or the right (the gallery's width).
    func nearestMouth(_ x: Double) -> Double {
        x < tuning.width / 2 ? 0 : tuning.width
    }

    /// Free flight (a Gleaner): straight at `target` round the join, easing in at the end.
    private func moveFreely(_ body: inout RiftwingBody, toward target: Vec2, speed: Double, _ dt: Double) {
        let offset = Vec2(dxWrap(body.pos.x, target.x), target.y - body.pos.y)
        let gap = offset.length
        guard gap > 1e-9 else { return }
        let step = min(speed * dt, gap)
        body.vel = offset * (speed / gap)
        body.pos = body.pos + offset * (step / gap)
        body.pos.x = wrapX(body.pos.x)
        if abs(offset.x) > 1 { body.facing = offset.x > 0 ? 1 : -1 }
    }

    // MARK: Losing opponents

    /// An opponent lost without a blow: no pod, no points. A Gleaner's pod falls if it was
    /// holding one.
    mutating func opponentFell(at index: Int, cause: RiftwingFallCause) {
        let o = opponents[index]
        guard !o.isDead else { return }
        opponents[index].isDead = true
        events.append(.opponentFell(id: o.id, role: o.role, at: o.pos, cause: cause))
        releasePod(heldBy: o)
        if o.role == .sower { clearMines(of: o.id, reason: .sowerDown) }
        if o.role == .gleaner { gleanerNextAt = max(gleanerNextAt, waveClock + director.gleanerGap) }
    }

    /// The pod a Gleaner held drops and falls again.
    mutating func releasePod(heldBy o: RiftwingOpponent) {
        for index in pods.indices where pods[index].state == .seized(by: o.id) {
            pods[index].state = .falling
            pods[index].vel = .zero
        }
    }

    mutating func clearMines(of sower: Int, reason: RiftwingMineEnd) {
        for mine in mines where mine.sower == sower {
            events.append(.mineCleared(id: mine.id, at: mine.pos, reason: reason))
        }
        mines.removeAll { $0.sower == sower }
    }
}
