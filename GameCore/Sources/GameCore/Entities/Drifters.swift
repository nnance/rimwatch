import Foundation

extension Simulation {
    /// Sowers and Broods cross the world at a steady pace, bobbing up and down. A Sower leaves a
    /// mine behind every few seconds.
    mutating func updateDrifter(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }

        enemy.timer += dt
        enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)

        // Each one bobs on its own rhythm, offset by its id so they don't move in step.
        let bob = sin(enemy.timer * 0.8 + Double(enemy.id))
        let wantedY = world.height * 0.55 + 110 * bob
        let floor = world.groundHeight(at: enemy.pos.x) + enemy.radius + 40
        let climb = 80 * dt
        enemy.pos.y += clamp(clamp(wantedY, floor, world.ceiling) - enemy.pos.y, -climb, climb)

        guard enemy.kind == .sower else { return }
        enemy.fireTimer -= dt
        if enemy.fireTimer <= 0 {
            enemy.fireTimer = tuning.mineInterval
            if enemies.count(where: { $0.kind == .mine }) < tuning.maxMines {
                let id = addEnemy(kind: .mine, at: enemy.pos)
                events.append(.mineLaid(id: id, at: enemy.pos))
            }
        }
    }

    /// A mine stays where it was laid and disappears when its time runs out.
    mutating func updateMine(at index: Int, _ dt: Double) {
        enemies[index].timer -= dt
        if enemies[index].timer <= 0 {
            enemies[index].expired = true
        }
    }
}
