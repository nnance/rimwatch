extension Simulation {
    /// A Lancer cruises until the player comes within range, winds up while matching the
    /// player's altitude, then charges flat across the screen. After a charge it needs a moment
    /// to recover, which is the safe time to shoot it.
    mutating func updateLancer(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }

        let dx = world.delta(from: enemy.pos.x, to: player.pos.x)

        switch enemy.state {
        case .telegraphing(let remaining):
            let climb = tuning.lancerTrackSpeed * dt
            enemy.pos.y += clamp(player.pos.y - enemy.pos.y, -climb, climb)
            let left = remaining - dt
            if left > 0 {
                enemy.state = .telegraphing(remaining: left)
            } else {
                enemy.vel = Vec2((dx >= 0 ? 1 : -1) * tuning.lancerChargeSpeed, 0)
                enemy.state = .charging(remaining: tuning.lancerChargeTime)
                events.append(.lancerCharged(id: enemy.id))
            }

        case .charging(let remaining):
            enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
            let left = remaining - dt
            if left > 0 {
                enemy.state = .charging(remaining: left)
            } else {
                enemy.vel = Vec2((enemy.vel.x >= 0 ? 1 : -1) * tuning.lancerPatrolSpeed, 0)
                enemy.state = .recovering(remaining: tuning.lancerRecovery)
            }

        case .recovering(let remaining):
            enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
            let left = remaining - dt
            enemy.state = left > 0 ? .recovering(remaining: left) : .patrolling

        default:
            enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
            let climb = 60 * dt
            enemy.pos.y += clamp(world.height * 0.6 - enemy.pos.y, -climb, climb)
            if player.isAlive, abs(dx) < tuning.lancerRange {
                enemy.state = .telegraphing(remaining: tuning.lancerTelegraph)
                events.append(.lancerTelegraph(id: enemy.id))
            }
        }

        let floor = world.groundHeight(at: enemy.pos.x) + enemy.radius
        enemy.pos.y = clamp(enemy.pos.y, floor, world.ceiling)
    }
}
