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

    /// A pod in the air: gravity, a gentle limit on its fall, landing on a ledge, or the Rift.
    private mutating func fall(_ index: Int, _ dt: Double) {
        var pod = pods[index]
        pod.vel.y = max(pod.vel.y - tuning.podGravity * dt, -pod.terminal)
        pod.vel.x *= expo(-1.2 * dt)
        let previous = pod.pos
        pod.pos = pod.pos + pod.vel * dt
        pod.pos.x = wrapX(pod.pos.x)
        let r = tuning.podRadius
        if pod.pos.y > tuning.roof - r {
            pod.pos.y = tuning.roof - r
            pod.vel.y = min(pod.vel.y, 0)
        }
        for (ledgeIndex, ledge) in ledges.enumerated() where ledge.spans(pod.pos.x) {
            if pod.vel.y <= 0, previous.y - r >= ledge.top - 1, pod.pos.y - r < ledge.top {
                pod.pos.y = ledge.top + r
                pod.vel = .zero
                pod.state = .resting(ledge: ledgeIndex)
                pod.hatchIn = director.podLife(forWave: max(wave, 1), tuning: tuning)
                pod.warned = false
                pods[index] = pod
                events.append(.podLanded(id: pod.id, at: pod.pos, ledge: ledgeIndex))
                return
            }
        }
        pods[index] = pod
        if pod.pos.y < tuning.riftLevel { losePod(at: index, cause: .rift) }
    }

    /// The pod lay too long: its colonist is lost and a rig one grade tougher stands up where it
    /// lay, taking off after a moment.
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
        events.append(.podHatched(id: pod.id, opponent: id, role: role, at: stand))
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
