import GameCore

extension RiftwingRun {
    // MARK: Pods

    /// A knocked-off rig's colonist drops in a pod: knocked downward (the winner springs up),
    /// thrown clear across away from the winner (`away`, 1 or -1, 0 for none) and keeping a
    /// little of the rig's speed, and it cannot be taken for `RiftwingTuning.podCatchDelay`, so a
    /// mid-air catch means going after it rather than flying on through the blow.
    /// A pod from a role in one of its first appearances (`ease` above 0) falls more slowly
    /// (`RiftwingWaves.podFallEase`), so early catches are within a new player's reach.
    @discardableResult
    mutating func dropPod(at pos: Vec2, vel: Vec2, from role: RiftwingRole, ease: Double = 0, away: Double = 0) -> Int {
        let id = takeID()
        var pod = RiftwingPod(id: id, pos: pos, from: role)
        pod.terminal = tuning.podTerminal * (1 - director.podFallEase * min(max(ease, 0), 1))
        pod.vel = Vec2(vel.x * tuning.podInherit + away * tuning.podThrow,
                       min(vel.y * tuning.podInherit, 0) - tuning.podKnock)
        pod.catchableIn = tuning.podCatchDelay
        let eased = min(max(ease, 0), 1)
        if eased > 0 {
            pod.hoverLeft = director.podHoverEase * eased
            if director.podDriftEase > 0 {
                pod.drift = director.podDriftEase * eased
                pod.driftLedge = driftTarget(for: pod)
            }
        }
        pods.append(pod)
        waveDropped += 1
        events.append(.podDropped(id: id, at: pos, from: role))
        return id
    }

    mutating func updatePods(_ dt: Double) {
        var index = 0
        while index < pods.count {
            defer { index += 1 }
            if pods[index].catchableIn > 0 { pods[index].catchableIn = max(pods[index].catchableIn - dt, 0) }
            switch pods[index].state {
            case .falling:
                fall(index, dt)
            case .resting(let ledge):
                pods[index].hatchIn -= dt
                pods[index].restedFor += dt
                if !pods[index].warned, pods[index].hatchIn <= tuning.hatchWarning {
                    pods[index].warned = true
                    events.append(.hatchWarning(id: pods[index].id, at: pods[index].pos, becomes: hatchRole(for: pods[index])))
                }
                if pods[index].hatchIn <= 0 { hatch(index, ledge: ledge) }
            case .seized, .freed, .lost:
                break
            }
        }
    }

    /// A pod in the air: it moves (`movePod`), lands on a ledge it meets from above, or is lost
    /// to the Rift.
    private mutating func fall(_ index: Int, _ dt: Double) {
        var pod = pods[index]
        if let ledgeIndex = movePod(&pod, dt) {
            pod.vel = .zero
            pod.state = .resting(ledge: ledgeIndex)
            pod.hatchIn = director.podLife(forWave: max(wave, 1), tuning: tuning)
            pod.warned = false
            pods[index] = pod
            events.append(.podLanded(id: pod.id, at: pod.pos, ledge: ledgeIndex))
            return
        }
        pods[index] = pod
        if pod.pos.y < tuning.riftLevel { losePod(at: index, cause: .rift) }
    }

    /// One step of a falling pod's flight: gravity and its gentle limit, its drift toward the
    /// ledge it is aimed at (else its speed across dies away), the Rift's heat holding an early
    /// pod up over open Rift, the roof, and the rock of the ledges. Rock stops a pod as it stops
    /// a rig: it lands on a ledge it meets from above (its centre above the middle of the rock),
    /// and is stopped by a ledge's underside and by its sides, so its centre is never inside
    /// rock. Returns the ledge it landed on, standing on it; the caller makes it rest there.
    /// Pure, so `driftTarget(for:)` can run a pod's whole fall ahead of time.
    func movePod(_ pod: inout RiftwingPod, _ dt: Double) -> Int? {
        let r = tuning.podRadius
        pod.vel.y = max(pod.vel.y - tuning.podGravity * dt, -pod.terminal)
        if let l = pod.driftLedge, l < ledges.count, !ledges[l].spans(pod.pos.x) || abs(pod.vel.x) > pod.drift {
            // Drifting toward the ledge below: across toward its nearer end, a little way in.
            let ledge = ledges[l]
            let x = clamp(pod.pos.x, ledge.minX + 20, ledge.maxX - 20)
            let want = clamp(dxWrap(pod.pos.x, x) * 2, -pod.drift, pod.drift)
            pod.vel.x += clamp(want - pod.vel.x, -400 * dt, 400 * dt)
        } else {
            pod.vel.x *= expo(-1.2 * dt)
        }
        let previous = pod.pos
        pod.pos = pod.pos + pod.vel * dt
        pod.pos.x = wrapX(pod.pos.x)
        // Over open Rift (no ledge below), its heat holds an early pod up for a while before it
        // sinks in: at the hover height, or where it is if it is already lower. One aimed at a
        // ledge drifts on toward it while it is held (its aim was chosen knowing this, so it
        // reaches that ledge from above); one with nowhere to drift is held still.
        if pod.hoverLeft > 0, pod.vel.y < 0,
           !ledges.contains(where: { $0.spans(previous.x) && $0.top <= previous.y }) {
            let hold = min(tuning.riftLevel + director.podHoverHeight, previous.y)
            if pod.pos.y < hold {
                pod.hoverLeft -= dt
                pod.vel.y = 0
                pod.pos.y = hold
                if pod.driftLedge == nil {
                    pod.vel.x = 0
                    pod.pos.x = previous.x
                    return nil
                }
            }
        }
        if pod.pos.y > tuning.roof - r {
            pod.pos.y = tuning.roof - r
            pod.vel.y = min(pod.vel.y, 0)
        }
        for (index, ledge) in ledges.enumerated() where ledge.spans(pod.pos.x) {
            let top = ledge.top, bottom = ledge.top - tuning.ledgeThickness
            guard pod.pos.y - r < top, pod.pos.y + r > bottom else { continue }
            let fromAbove = previous.y - r >= top - 1
            let fromBelow = previous.y + r <= bottom + 1
            if fromAbove || (!fromBelow && pod.pos.y >= (top + bottom) / 2) {
                if fromAbove, pod.vel.y > 0 { continue }
                pod.pos.y = top + r
                return index
            } else if fromBelow {
                // Its top meets the underside.
                pod.pos.y = bottom - r
                pod.vel.y = min(pod.vel.y, 0)
            } else {
                // It came in at the side: it stops against it, and falls on past.
                pod.pos.x = dxWrap(ledge.midX, previous.x) < 0 ? ledge.minX - 0.01 : ledge.maxX + 0.01
                pod.vel.x = 0
            }
        }
        return nil
    }

    /// The ledge an early pod should drift toward: the one nearest it across (round the join)
    /// that its fall, drifting toward that ledge, actually brings it onto from above (its whole
    /// fall is run ahead, with the same steps as `movePod`); nil if it reaches none, and then it
    /// does not drift.
    func driftTarget(for pod: RiftwingPod) -> Int? {
        let r = tuning.podRadius
        var candidates: [(index: Int, gap: Double)] = []
        for (index, ledge) in ledges.enumerated() where ledge.top < pod.pos.y - r {
            let x = clamp(pod.pos.x, ledge.minX + 20, ledge.maxX - 20)
            candidates.append((index, abs(dxWrap(pod.pos.x, x))))
        }
        candidates.sort { $0.gap != $1.gap ? $0.gap < $1.gap : $0.index < $1.index }
        for (index, _) in candidates {
            var trial = pod
            trial.driftLedge = index
            if landing(of: trial, aimedAt: index) { return index }
        }
        return nil
    }

    /// True when `pod`, falling as it is, lands on ledge `target`.
    private func landing(of start: RiftwingPod, aimedAt target: Int) -> Bool {
        var pod = start
        let ledge = ledges[target]
        let dt = Self.timeStep
        for _ in 0..<Int(90 / dt) {
            if let landed = movePod(&pod, dt) { return landed == target }
            if pod.pos.y - tuning.podRadius < ledge.top - 1 || pod.pos.y < tuning.riftLevel { return false }
            // Over the ledge and slow enough across that it can no longer leave it, with no other
            // rock between: it will land there.
            let travel = abs(pod.vel.x) / 1.2
            let lo = pod.pos.x - travel, hi = pod.pos.x + travel
            guard ledge.spans(pod.pos.x), abs(pod.vel.x) <= pod.drift, lo >= ledge.minX, hi <= ledge.maxX else { continue }
            var between = false
            for (i, other) in ledges.enumerated() where i != target && other.top > ledge.top {
                let reach: Double = pod.pos.y + tuning.podRadius
                if other.top - tuning.ledgeThickness < reach, other.maxX >= lo, other.minX <= hi { between = true }
            }
            if !between { return true }
        }
        return false
    }

    /// The pod lay too long: its colonist is lost and a rig one grade tougher stands up where it
    /// lay, taking off after a moment: of the tougher kind once that kind has had its debut (else
    /// of its own kind), with as much of that kind's early ease as the rider's rescues earn
    /// (`hatchedEase`).
    private mutating func hatch(_ index: Int, ledge: Int) {
        let pod = pods[index]
        losePod(at: index, cause: .hatched)
        let role = hatchRole(for: pod)
        let stats = tuning.stats(for: role)
        let stand = Vec2(pod.pos.x, ledges[ledge].top + stats.radius * tuning.feetShare)
        let id = addOpponent(role, at: stand, heading: rider.body.pos.x >= pod.pos.x ? 1 : -1)
        let o = opponents.count - 1
        opponents[o].body.vel = .zero
        opponents[o].body.ledge = ledge
        opponents[o].state = .waking(remaining: tuning.hatchWake)
        opponents[o].hatched = true
        // Its kind's early ease, kept only for a rider who frees colonists: leaving pods to hatch
        // is no way to fill the gallery with gentle opponents.
        let ease = hatchedEase(of: role)
        opponents[o].ease = ease
        opponents[o].speed = stats.maxSpeed * speedScale(role, ease: ease)
        events.append(.podHatched(id: pod.id, opponent: id, role: role, at: stand))
    }

    /// The ease a rig of `role` hatching now flies with: its kind's ease this wave, times the
    /// share it keeps for the colonists the rider has freed in this wave and the last
    /// (`RiftwingWaves.hatchedEaseShare(freed:settled:)`).
    func hatchedEase(of role: RiftwingRole) -> Double {
        let kind = director.ease(of: role, inWave: max(wave, 1))
        let freed = waveFreed + previousWaveFreed
        let settled = waveFreed + waveLost + previousWaveFreed + previousWaveLost
        return kind * director.hatchedEaseShare(freed: freed, settled: settled)
    }

    /// What a pod would hatch into now: one grade tougher, but its own kind until the tougher
    /// kind has had its debut wave.
    public func hatchRole(for pod: RiftwingPod) -> RiftwingRole {
        let tougher = pod.from.hatchesInto
        guard let debut = director.debut(of: tougher), debut <= max(wave, 1) else { return pod.from }
        return tougher
    }

    /// A pod's colonist is lost.
    mutating func losePod(at index: Int, cause: RiftwingPodLoss) {
        guard pods[index].isUnsettled else { return }
        pods[index].state = .lost
        pods[index].vel = .zero
        waveLost += 1
        events.append(.podLost(id: pods[index].id, at: pods[index].pos, cause: cause))
    }

    /// The rider reached a pod: its colonist is freed. The nth freed this wave scores n times the
    /// rescue points, twice that if the pod was caught in the air. A Gleaner holding it lets go
    /// and leaves. Freeing one in the dark brings the lamps back.
    mutating func freePod(at index: Int) {
        let pod = pods[index]
        guard pod.isUnsettled else { return }
        let caught = pod.state == .falling
        if case .seized(let gleanerID) = pod.state, let g = opponents.firstIndex(where: { $0.id == gleanerID && !$0.isDead }) {
            opponents[g].state = .leaving(exitX: nearestMouth(opponents[g].pos.x))
        }
        pods[index].state = .freed
        pods[index].vel = .zero
        waveFreed += 1
        colonistsSaved += 1
        let points = tuning.rescuePoints * waveFreed * (caught ? max(tuning.catchMultiplier, 1) : 1)
        addScore(points)
        events.append(caught ? .podCaught(id: pod.id, at: pod.pos, order: waveFreed, points: points)
                             : .podFreed(id: pod.id, at: pod.pos, order: waveFreed, points: points))
        if isLampsOut {
            isLampsOut = false
            events.append(.lampsRestored)
        }
    }
}
