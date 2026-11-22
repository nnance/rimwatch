import GameCore

extension RiftwingRun {
    // MARK: Contact

    /// A rig's height for the clash: its height, except that within `roofBand` of the roof every
    /// rig counts as level, so pressing against the roof wins nothing.
    public func clashHeight(_ body: RiftwingBody) -> Double {
        min(body.pos.y, tuning.roof - body.radius - tuning.roofBand)
    }

    /// How the rider meeting an opponent comes out, by height: above by more than the margin
    /// wins, below by more loses, between bounces.
    public enum ClashOutcome: Sendable, Equatable {
        case win, bounce, lose
    }

    /// The clash rule on its own, for the rider at `rider` meeting `opponent`. `leniency` changes
    /// the margin on the losing side only: an opponent must be that much more clearly above to
    /// win (`RiftwingWaves.leniency(ease:)`); a negative leniency narrows it, never below level.
    public func clashOutcome(rider: RiftwingBody, opponent: RiftwingBody, leniency: Double = 0) -> ClashOutcome {
        let diff = clashHeight(rider) - clashHeight(opponent)
        if diff > tuning.clashMargin { return .win }
        if diff < -max(tuning.clashMargin + leniency, 0) { return .lose }
        return .bounce
    }

    mutating func resolveContacts() {
        guard rider.isAlive else { return }
        // Pods the rider reaches are freed (caught, if still falling).
        let reach = rider.body.radius + tuning.podRadius + tuning.podSlack
        for index in pods.indices where pods[index].isUnsettled && pods[index].isCatchable
            && wrapDistance(pods[index].pos, rider.body.pos) < reach {
            freePod(at: index)
        }

        // Opponents, lowest index first so the outcome never depends on anything else.
        for index in opponents.indices {
            guard rider.isAlive else { return }
            let o = opponents[index]
            guard !o.isDead, o.clashCooldown <= 0,
                  wrapDistance(o.pos, rider.body.pos) < rider.body.radius + o.body.radius else { continue }
            if o.role == .gleaner {
                meetGleaner(index)
            } else {
                clash(index)
            }
        }

        // Mines.
        guard rider.isAlive, !rider.isInvulnerable else { return }
        let mineReach = tuning.riderMineRadius + tuning.mineRadius
        if let hit = mines.firstIndex(where: { wrapDistance($0.pos, rider.body.pos) < mineReach }) {
            let mine = mines.remove(at: hit)
            events.append(.mineCleared(id: mine.id, at: mine.pos, reason: .struck))
            loseRider(cause: .mine(id: mine.id))
        }
    }

    /// The rider meets a rig.
    private mutating func clash(_ index: Int) {
        let o = opponents[index]
        let at = Vec2(wrapX(rider.body.pos.x + dxWrap(rider.body.pos.x, o.pos.x) / 2), (rider.body.pos.y + o.pos.y) / 2)
        // A rider clinging to a ceiling gets none of the early opponents' leniency or mercy, but
        // the clash is judged by the ordinary rule: nothing makes it harder to win or easier to
        // lose than that.
        let clinging = isRiderClinging
        let leniency = director.leniency(ease: clinging ? 0 : o.ease)
        var outcome = clashOutcome(rider: rider.body, opponent: o.body, leniency: leniency)
        if outcome == .lose, rider.isInvulnerable { outcome = .bounce }
        // Wave 1 is for learning the controls: a rider standing on a ledge in it is never beaten,
        // nor thrown off its ledge by the meeting (`bounce(_:at:)`).
        let standingGrace = rider.body.isGrounded && wave <= director.standingGraceWaves
        if outcome == .lose, standingGrace { outcome = .bounce }
        if outcome == .lose, !clinging, rng.chance(director.mercy(ease: o.ease)) {
            outcome = .bounce
        }
        opponents[index].clashCooldown = tuning.clashCooldown
        switch outcome {
        case .win:
            let stoop = rider.body.isDiving
            events.append(.clashWon(opponent: o.id, role: o.role, at: at, stoop: stoop))
            rider.body.vel.y = max(rider.body.vel.y, tuning.winLift)
            if stoop || o.blows <= 1 {
                let fallen = max(rider.body.diveStart - rider.body.pos.y, 0)
                let bonus = stoop ? stoopBonus(fallen: fallen) : 0
                knockOff(index, bonus: bonus)
            } else {
                // A tough rig takes the blow and tumbles away.
                opponents[index].blows -= 1
                opponents[index].state = .staggered(remaining: tuning.staggerTime)
                opponents[index].body.isDiving = false
                opponents[index].body.ledge = nil
                let away: Double = dxWrap(rider.body.pos.x, o.pos.x) >= 0 ? 1 : -1
                opponents[index].body.vel = Vec2(away * tuning.bounceSpeed, -tuning.bounceSpeed * 0.5)
                addScore(tuning.hitPoints)
                events.append(.opponentHit(id: o.id, role: o.role, at: o.pos, blowsLeft: opponents[index].blows))
            }
        case .bounce:
            bounce(index, at: at)
        case .lose:
            events.append(.clashLost(opponent: o.id, role: o.role, at: at))
            opponents[index].body.vel.y = max(opponents[index].body.vel.y, tuning.winLift)
            opponents[index].body.isDiving = false
            loseRider(cause: .clash(opponent: o.id, role: o.role))
        }
    }

    /// Near level: both are thrown apart, sideways, the higher a little up and the lower a
    /// little down. Neither stays on a ledge, except a rider standing on one in the waves where
    /// standing is never beaten (`RiftwingWaves.standingGraceWaves`): it keeps its footing, and
    /// the opponent alone is thrown up and away.
    private mutating func bounce(_ index: Int, at: Vec2) {
        let o = opponents[index]
        let side: Double = dxWrap(o.pos.x, rider.body.pos.x) >= 0 ? 1 : -1
        let riderHigher = clashHeight(rider.body) >= clashHeight(o.body)
        let keepsFooting = rider.body.isGrounded && wave <= director.standingGraceWaves
        if !keepsFooting {
            rider.body.vel.x = side * tuning.bounceSpeed
            rider.body.vel.y += riderHigher ? tuning.bounceLift : -tuning.bounceLift
            rider.body.ledge = nil
        }
        opponents[index].body.vel.x = -side * tuning.bounceSpeed
        opponents[index].body.vel.y += riderHigher ? -tuning.bounceLift : tuning.bounceLift
        opponents[index].body.ledge = nil
        opponents[index].body.isDiving = false
        if keepsFooting {
            // The opponent alone is thrown: up as well as away, so one standing on the same ledge
            // does not land straight back on it and walk into the rider again, and it cannot
            // meet the rider again until it has had time to get clear.
            opponents[index].body.vel.y = max(opponents[index].body.vel.y, tuning.winLift)
            opponents[index].clashCooldown = max(opponents[index].clashCooldown, tuning.footingCooldown)
        }
        events.append(.clashBounced(opponent: o.id, role: o.role, at: at))
    }

    /// Points for a stoop: by the height fallen since the dive began, in 50s, up to the cap.
    public func stoopBonus(fallen: Double) -> Int {
        let raw = Int(fallen * tuning.stoopPointsPerUnit)
        return min(raw / 50 * 50, tuning.stoopBonusCap)
    }

    /// A rig is knocked off: it scores, its colonist drops in a pod, and a Sower's mines go
    /// with it.
    private mutating func knockOff(_ index: Int, bonus: Int) {
        let o = opponents[index]
        opponents[index].isDead = true
        let points = tuning.stats(for: o.role).points + bonus
        addScore(points)
        events.append(.opponentDestroyed(id: o.id, role: o.role, at: o.pos, points: points, stoopBonus: bonus))
        if o.role == .sower { clearMines(of: o.id, reason: .sowerDown) }
        if o.role.isRig {
            let away: Double = dxWrap(rider.body.pos.x, o.pos.x) >= 0 ? 1 : -1
            dropPod(at: o.pos, vel: o.body.vel, from: o.role, ease: o.ease, away: away)
        }
    }

    /// The rider meets a Gleaner: from above or level it is destroyed (and a pod it holds is
    /// freed); from below it bumps the rider away, unhurt.
    private mutating func meetGleaner(_ index: Int) {
        let o = opponents[index]
        opponents[index].clashCooldown = tuning.clashCooldown
        let diff = clashHeight(rider.body) - o.pos.y
        if diff >= -tuning.clashMargin {
            let at = o.pos
            events.append(.clashWon(opponent: o.id, role: o.role, at: at, stoop: rider.body.isDiving))
            opponents[index].isDead = true
            let points = tuning.stats(for: .gleaner).points
            addScore(points)
            events.append(.opponentDestroyed(id: o.id, role: o.role, at: at, points: points, stoopBonus: 0))
            if let pod = pods.firstIndex(where: { $0.state == .seized(by: o.id) }) { freePod(at: pod) }
            gleanerNextAt = max(gleanerNextAt, waveClock + director.gleanerGap)
        } else {
            let side: Double = dxWrap(o.pos.x, rider.body.pos.x) >= 0 ? 1 : -1
            rider.body.vel = Vec2(side * tuning.gleanerBumpSpeed * 0.6, -tuning.gleanerBumpSpeed * 0.8)
            rider.body.ledge = nil
            events.append(.gleanerBumped(opponent: o.id, at: rider.body.pos))
        }
    }
}
