import Foundation
import GameCore

// How each enemy role moves and acts.
extension RedoubtRun {
    mutating func updateEnemies(_ dt: Double) {
        let decay = exp(-tuning.pushDecay * dt)
        // Enemies a Burrow pours out this step take their first turn next step.
        var index = 0
        let count = enemies.count
        while index < count {
            defer { index += 1 }
            guard !enemies[index].isDead else { continue }
            switch enemies[index].role {
            case .skitter: updateSkitter(at: index, dt)
            case .gleaner: updateGleaner(at: index, dt)
            case .spitter: updateSpitter(at: index, dt)
            case .burrow: updateBurrow(at: index, dt)
            case .thresher: updateThresher(at: index, dt)
            case .husk: updateHusk(at: index, dt)
            }
            guard enemies[index].role != .burrow else { continue }
            var enemy = enemies[index]
            enemy.pos = clampToFloor(enemy.pos + (enemy.vel + enemy.push) * dt, radius: enemy.radius)
            enemy.push = enemy.push * decay
            if enemy.role != .spitter, enemy.vel.x * enemy.vel.x + enemy.vel.y * enemy.vel.y > 1 {
                enemy.heading = atan2(enemy.vel.y, enemy.vel.x)
            }
            enemies[index] = enemy
        }
    }

    /// Unit vector from `a` toward `b`, and the distance between them.
    private func direction(from a: Vec2, to b: Vec2) -> (Vec2, Double) {
        let d = b - a
        let len = d.length
        return len > 1e-9 ? (d * (1 / len), len) : (.zero, 0)
    }

    // MARK: Skitter

    /// Walks at the orb with a wobble, each at its own pace. With the orb gone it slows to a stop.
    private mutating func updateSkitter(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }
        enemy.timer += dt
        guard orb.isAlive else {
            enemy.vel = enemy.vel * exp(-3 * dt)
            return
        }
        let to = orb.pos - enemy.pos
        let angle = atan2(to.y, to.x) + tuning.skitterWobble * sin(enemy.timer * 2.3 + enemy.trait * 10)
        let speed = tuning.skitterSpeed * enemy.trait * director.skitterSpeedScale(forWave: wave, tuning: tuning)
        enemy.vel = unitVector(angle) * speed
    }

    // MARK: Husk

    /// Waits a moment if just formed, then chases the orb hard.
    private mutating func updateHusk(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }
        if case .waking(let remaining) = enemy.state {
            let left = remaining - dt
            enemy.state = left > 0 ? .waking(remaining: left) : .hunting
            enemy.vel = enemy.vel * exp(-6 * dt)
            return
        }
        guard orb.isAlive else {
            enemy.vel = enemy.vel * exp(-1.5 * dt)
            return
        }
        let (dir, _) = direction(from: enemy.pos, to: orb.pos)
        enemy.vel = enemy.vel + dir * (tuning.huskAcceleration * dt)
        let speed = enemy.vel.length
        if speed > tuning.huskMaxSpeed { enemy.vel = enemy.vel * (tuning.huskMaxSpeed / speed) }
    }

    // MARK: Thresher

    /// Lumbers toward the orb, turning slowly. Shots push it (see `damageEnemy`).
    private mutating func updateThresher(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }
        if orb.isAlive {
            let to = orb.pos - enemy.pos
            let wanted = atan2(to.y, to.x)
            var turn = remainder(wanted - enemy.heading, 2 * .pi)
            let maxTurn = tuning.thresherTurnRate * dt
            turn = clamp(turn, -maxTurn, maxTurn)
            enemy.heading += turn
        }
        enemy.vel = unitVector(enemy.heading) * tuning.thresherSpeed
    }

    // MARK: Spitter

    /// Holds a distance from the orb, circling it, and now and then stops, winds up and fires a
    /// slow shot led a little ahead of the orb.
    private mutating func updateSpitter(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }
        let (dir, dist) = direction(from: enemy.pos, to: orb.pos)
        if dist > 0 { enemy.heading = atan2(dir.y, dir.x) }
        switch enemy.state {
        case .windingUp(let remaining):
            enemy.vel = .zero
            let left = remaining - dt
            if left > 0 {
                enemy.state = .windingUp(remaining: left)
            } else {
                enemy.state = .keepingDistance
                enemy.timer = rng.range(tuning.spitterFireInterval) * director.spitterFireScale(forWave: wave, tuning: tuning)
                fireSpitterShot(from: enemy)
            }
        default:
            enemy.timer -= dt
            let range = tuning.spitterRange
            let radial: Double = dist > range.upperBound ? 1 : (dist < range.lowerBound ? -1 : 0)
            let side = Vec2(-dir.y, dir.x) * (0.7 * enemy.trait)
            var move = dir * radial + side
            // Turn back off a wall rather than grind along it.
            let margin = 40.0
            if enemy.pos.x < margin { move.x = abs(move.x) + 0.5 }
            if enemy.pos.x > tuning.arenaWidth - margin { move.x = -abs(move.x) - 0.5 }
            if enemy.pos.y < margin { move.y = abs(move.y) + 0.5 }
            if enemy.pos.y > tuning.arenaHeight - margin { move.y = -abs(move.y) - 0.5 }
            let len = move.length
            enemy.vel = len > 0 ? move * (tuning.spitterSpeed / len) : .zero
            if enemy.timer <= 0, orb.isAlive, dist < tuning.spitterFireRange {
                enemy.state = .windingUp(remaining: tuning.spitterWindUp)
                enemy.vel = .zero
                events.append(.spitterWindUp(id: enemy.id, at: enemy.pos))
            } else if enemy.timer <= 0 {
                enemy.timer = 0.3
            }
        }
    }

    private mutating func fireSpitterShot(from enemy: RedoubtEnemy) {
        guard orb.isAlive else { return }
        let to = orb.pos - enemy.pos
        // Slower and less well led in the Spitters' first appearances (`spitterDebutShotSpeed`,
        // `spitterDebutLead`); both scales are exactly 1 once the ease is over.
        let shotSpeed = tuning.spitterShotSpeed * director.spitterShotSpeedScale(forWave: wave)
        let flight = to.length / shotSpeed * (tuning.spitterShotLead * director.spitterLeadScale(forWave: wave))
        let aim = to + orb.vel * flight
        let len = aim.length
        guard len > 1 else { return }
        let dir = aim * (1 / len)
        let heading = atan2(dir.y, dir.x)
        let muzzle = enemy.pos + dir * (enemy.radius + tuning.figure(2))
        shots.append(RedoubtShot(id: takeID(), owner: .enemy, pos: muzzle, vel: dir * shotSpeed,
                                 radius: tuning.spitterShotRadius, timeLeft: tuning.spitterShotLifetime))
        events.append(.enemyFired(id: enemy.id, at: muzzle, heading: heading))
    }

    // MARK: Burrow

    /// Pours out a Skitter every so often while it has fewer than its limit alive, the floor has
    /// room, and the orb is not close.
    private mutating func updateBurrow(at index: Int, _ dt: Double) {
        enemies[index].timer -= dt
        guard enemies[index].timer <= 0 else { return }
        var interval = tuning.burrowSpawnInterval * director.burrowSpawnScale(forWave: wave, tuning: tuning)
        // With the floor nearly clear (the quota spent, only the hole left), it pours faster, so
        // the end of a wave is a fight with the hole and not a wait.
        if shootableOnFloor < tuning.burrowThinFloor { interval *= tuning.burrowThinFloorScale }
        enemies[index].timer = interval
        let burrow = enemies[index]
        let children = enemies.count { $0.parent == burrow.id && !$0.isDead }
        guard children < tuning.burrowMaxChildren, enemies.count < tuning.maxEnemies,
              isClearOfOrb(burrow.pos, by: tuning.safeDistance) else { return }
        let angle = rng.range(0...(2 * .pi))
        let pos = burrow.pos + unitVector(angle) * (burrow.radius + tuning.figure(4))
        let id = addEnemy(.skitter, at: pos, parent: burrow.id)
        events.append(.burrowSpawned(burrow: burrow.id, id: id, at: pos))
    }

    // MARK: Gleaner

    /// Goes for the nearest colonist no other Gleaner is after (sheltering, or the last in the
    /// line), seizes them on touch and drags them to the nearest Burrow or wall. Getting there
    /// loses the colonist, and the Gleaner becomes a Husk.
    private mutating func updateGleaner(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        enemy.timer += dt
        switch enemy.state {
        case .dragging(let colonistID, let destination):
            guard let c = colonistIndex(colonistID), colonists[c].state == .seized(by: enemy.id) else {
                // Lost their hold (the colonist was crushed): look again.
                enemy.state = .seeking(colonist: nil)
                enemies[index] = enemy
                return
            }
            enemy.held += dt
            // The least time from seizure to loss (`RedoubtWaves.seizeTime`): closer to the wall
            // than that allows, it drags more slowly to fit, and waits there if pushed in early.
            let least = director.seizeTime(forWave: wave)
            let (dir, dist) = direction(from: enemy.pos, to: destination)
            if dist <= 4, enemy.held >= least - 1e-9 {
                enemy.vel = .zero
                enemies[index] = enemy
                loseColonist(at: c, takenBy: .gleaner, enemy: enemy.id)
                becomeHusk(at: index)
                return
            }
            var speed = tuning.gleanerDragSpeed * director.gleanerDragScale(forWave: wave)
            let left = least - enemy.held
            if left > dt { speed = min(speed, dist / left) }
            enemy.vel = dir * min(speed, dist / dt)
            // The colonist trails behind.
            colonists[c].pos = clampToFloor(enemy.pos - dir * (enemy.radius + tuning.colonistRadius - tuning.figure(2)),
                                            radius: tuning.colonistRadius)
        case .seeking(let target):
            var targetIndex = target.flatMap { id in colonistIndex(id) }
            if let t = targetIndex, !isGleanable(t, by: enemy.id) {
                if colonists[t].claimedBy == enemy.id { colonists[t].claimedBy = nil }
                targetIndex = nil
            }
            if targetIndex == nil {
                targetIndex = nearestGleanable(to: enemy.pos, by: enemy.id)
                if let t = targetIndex { colonists[t].claimedBy = enemy.id }
            }
            guard let t = targetIndex else {
                // Nobody to go for: amble about, drifting toward the middle.
                enemy.state = .seeking(colonist: nil)
                let (toMiddle, _) = direction(from: enemy.pos, to: centre)
                let wander = Vec2(cos(enemy.timer * 0.7 + Double(enemy.id)), sin(enemy.timer * 0.9))
                enemy.vel = (toMiddle * 0.5 + wander) * (tuning.gleanerSpeed * 0.5)
                break
            }
            enemy.state = .seeking(colonist: colonists[t].id)
            let (dir, dist) = direction(from: enemy.pos, to: colonists[t].pos)
            if dist < enemy.radius + tuning.colonistRadius {
                seize(colonist: t, gleaner: &enemy)
            } else {
                enemy.vel = dir * tuning.gleanerSpeed
            }
        default:
            enemy.state = .seeking(colonist: nil)
        }
        enemies[index] = enemy
    }

    /// Sheltering, or last in the line; and not claimed by another Gleaner.
    private func isGleanable(_ c: Int, by gleaner: Int) -> Bool {
        let colonist = colonists[c]
        guard colonist.claimedBy == nil || colonist.claimedBy == gleaner else { return false }
        switch colonist.state {
        case .sheltering: return true
        case .following: return line.last == colonist.id
        default: return false
        }
    }

    private func nearestGleanable(to p: Vec2, by gleaner: Int) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for c in colonists.indices where isGleanable(c, by: gleaner) {
            let d = distance(colonists[c].pos, p)
            if d < bestDistance {
                bestDistance = d
                best = c
            }
        }
        return best
    }

    private mutating func seize(colonist c: Int, gleaner: inout RedoubtEnemy) {
        if colonists[c].state == .following, line.last == colonists[c].id { line.removeLast() }
        colonists[c].state = .seized(by: gleaner.id)
        colonists[c].claimedBy = gleaner.id
        colonists[c].vel = .zero
        let destination = dragDestination(from: gleaner.pos, radius: gleaner.radius)
        gleaner.state = .dragging(colonist: colonists[c].id, destination: destination)
        gleaner.held = 0
        gleaner.vel = .zero
        events.append(.colonistSeized(id: colonists[c].id, by: gleaner.id, at: colonists[c].pos))
    }

    /// The nearest Burrow, or the nearest point of the wall (as close as the Gleaner can get).
    func dragDestination(from p: Vec2, radius: Double) -> Vec2 {
        let w = tuning.arenaWidth, h = tuning.arenaHeight
        var best = Vec2(radius, p.y)
        var bestDistance = p.x - radius
        let walls = [
            (Vec2(w - radius, p.y), w - radius - p.x),
            (Vec2(p.x, radius), p.y - radius),
            (Vec2(p.x, h - radius), h - radius - p.y),
        ]
        for (point, d) in walls where d < bestDistance {
            best = point
            bestDistance = d
        }
        best = clampToFloor(best, radius: radius)
        bestDistance = max(bestDistance, 0)
        for enemy in enemies where enemy.role == .burrow && !enemy.isDead {
            // Its rim, where the Gleaner can reach without the Burrow shoving it off.
            let rim = enemy.radius + radius
            let d = max(distance(enemy.pos, p) - rim, 0)
            if d < bestDistance {
                let (dir, len) = direction(from: enemy.pos, to: p)
                best = enemy.pos + (len > 0 ? dir : Vec2(1, 0)) * rim
                bestDistance = d
            }
        }
        return best
    }

    /// A Gleaner that got its colonist away turns into a Husk where it stands, keeping its id.
    private mutating func becomeHusk(at index: Int) {
        let stats = tuning.stats(for: .husk)
        enemies[index].role = .husk
        enemies[index].state = .waking(remaining: tuning.huskWakeDelay)
        enemies[index].radius = stats.radius
        enemies[index].hp = stats.hp
        enemies[index].vel = .zero
        events.append(.huskFormed(id: enemies[index].id, at: enemies[index].pos))
    }

    // MARK: Separation

    /// Moves overlapping enemies apart so the crowd spreads instead of stacking. Burrows do not
    /// move; Threshers barely do.
    mutating func separateEnemies() {
        let strength = tuning.separationStrength
        let reach = 2 * maxEnemyRadius
        // A copy of the grid (it shares storage), so the closure below may move enemies.
        let grid = self.grid
        var i = 0
        while i < enemies.count {
            defer { i += 1 }
            guard !enemies[i].isDead else { continue }
            let a = enemies[i]
            var moveA = Vec2.zero
            grid.forEach(near: a.pos, reach: reach) { j in
                guard j > i else { return }
                let b = enemies[j]
                guard !b.isDead else { return }
                let offset = b.pos - a.pos
                let minGap = a.radius + b.radius
                let d2 = offset.x * offset.x + offset.y * offset.y
                guard d2 < minGap * minGap else { return }
                let d = d2.squareRoot()
                let dir = d > 1e-6 ? offset * (1 / d) : Vec2(1, 0)
                let overlap = (minGap - d) * strength
                let wa = Self.mobility(a.role), wb = Self.mobility(b.role)
                let total = wa + wb
                guard total > 0 else { return }
                moveA = moveA - dir * (overlap * wa / total)
                enemies[j].pos = clampToFloor(b.pos + dir * (overlap * wb / total), radius: b.radius)
            }
            if moveA != .zero {
                enemies[i].pos = clampToFloor(enemies[i].pos + moveA, radius: a.radius)
            }
        }
    }

    private static func mobility(_ role: RedoubtRole) -> Double {
        switch role {
        case .burrow: 0
        case .thresher: 0.1
        default: 1
        }
    }
}
