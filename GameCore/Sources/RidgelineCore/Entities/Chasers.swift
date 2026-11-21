import Foundation
import GameCore

extension Simulation {
    /// Husks and Motes steer straight at the player, taking the short way round the world.
    /// `jitter` adds a random shove each step, which makes Motes weave.
    mutating func updateChaser(
        at index: Int,
        _ dt: Double,
        acceleration: Double,
        maxSpeed: Double,
        jitter: Double
    ) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }

        // Still waking (a Husk that has just formed): drift to a stop.
        if enemy.timer > 0 {
            enemy.timer -= dt
            enemy.vel = enemy.vel * exp(-3 * dt)
            enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
            return
        }

        if player.isAlive {
            let dx = world.delta(from: enemy.pos.x, to: player.pos.x)
            let dy = player.pos.y - enemy.pos.y
            let distance = hypot(dx, dy)
            if distance > 1 {
                enemy.vel = enemy.vel + Vec2(dx / distance, dy / distance) * (acceleration * dt)
            }
        } else {
            // Nothing to chase: coast to a stop.
            enemy.vel = enemy.vel * exp(-1.5 * dt)
        }
        if jitter > 0 {
            enemy.vel = enemy.vel + Vec2(rng.range(-1...1), rng.range(-1...1)) * (jitter * dt)
        }

        let speed = enemy.vel.length
        if speed > maxSpeed {
            enemy.vel = enemy.vel * (maxSpeed / speed)
        }

        enemy.pos.x = world.wrap(enemy.pos.x + enemy.vel.x * dt)
        let floor = world.groundHeight(at: enemy.pos.x) + enemy.radius
        enemy.pos.y = clamp(enemy.pos.y + enemy.vel.y * dt, floor, world.ceiling)
    }
}
