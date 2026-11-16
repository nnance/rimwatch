extension Simulation {
    /// A Harvester picks a colonist, flies over, descends, grabs them and lifts them to the top of
    /// the world. If it gets there, the colonist is lost and the Harvester becomes a Husk.
    mutating func updateHarvester(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }

        switch enemy.state {
        case .seeking(let targetID):
            var target = targetID.flatMap { colonistIndex($0) }
            if let t = target, colonists[t].state != .grounded || colonists[t].claimedBy != enemy.id {
                target = nil
            }
            if target == nil {
                target = claimNearestColonist(for: enemy)
                enemy.state = .seeking(target: target.map { colonists[$0].id })
            }
            guard let t = target else {
                enemy.state = .roaming
                enemy.vel = Vec2(rng.chance(0.5) ? tuning.roamSpeed : -tuning.roamSpeed, 0)
                return
            }

            let colonist = colonists[t]
            let dx = world.delta(from: enemy.pos.x, to: colonist.pos.x)
            let reach = tuning.harvesterSpeed * dt
            enemy.pos.x = world.wrap(enemy.pos.x + clamp(dx, -reach, reach))

            let hoverY = colonist.pos.y + tuning.grabHeight
            let wantedY = abs(dx) > tuning.harvesterDescendRange ? world.ceiling - 60 : hoverY
            let climb = tuning.harvesterDescentSpeed * dt
            enemy.pos.y += clamp(wantedY - enemy.pos.y, -climb, climb)

            if abs(dx) < 4, abs(enemy.pos.y - hoverY) < 3 {
                colonists[t].state = .held(by: enemy.id)
                colonists[t].claimedBy = nil
                enemy.state = .lifting(colonist: colonist.id)
                events.append(.colonistGrabbed(id: colonist.id))
            }

        case .lifting(let colonistID):
            guard let t = colonistIndex(colonistID), colonists[t].state == .held(by: enemy.id) else {
                enemy.state = .seeking(target: nil)
                return
            }
            enemy.pos.y += tuning.liftSpeed * dt
            colonists[t].pos = Vec2(enemy.pos.x, enemy.pos.y - tuning.grabHeight)
            if enemy.pos.y >= world.ceiling {
                colonists[t].state = .lost
                events.append(.colonistLost(id: colonistID, at: colonists[t].pos))
                turnIntoHusk(&enemy)
                events.append(.huskFormed(id: enemy.id, at: enemy.pos))
                return
            }

        case .roaming:
            // Check twice a second whether a colonist has become available again.
            if tick % 60 == 0, colonists.contains(where: { $0.state == .grounded && $0.claimedBy == nil }) {
                enemy.state = .seeking(target: nil)
                return
            }
            enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
            let climb = tuning.harvesterDescentSpeed * dt
            enemy.pos.y += clamp(world.ceiling - 100 - enemy.pos.y, -climb, climb)

        default:
            break
        }

        enemy.fireTimer -= dt
        if enemy.fireTimer <= 0 {
            enemy.fireTimer = rng.range(tuning.harvesterFireInterval)
            fireEnemyShot(from: enemy.pos)
        }
    }

    /// Reserves the closest colonist nobody else is after, and returns its index.
    private mutating func claimNearestColonist(for enemy: Enemy) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, colonist) in colonists.enumerated()
        where colonist.state == .grounded && colonist.claimedBy == nil {
            let distance = abs(world.delta(from: enemy.pos.x, to: colonist.pos.x))
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        guard let index = best?.index else { return nil }
        colonists[index].claimedBy = enemy.id
        return index
    }
}
