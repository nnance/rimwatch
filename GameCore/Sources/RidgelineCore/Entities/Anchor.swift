import GameCore

extension Simulation {
    /// An Anchor flies to the nearest standing outpost, lands on it and drills. If the drilling
    /// finishes, the outpost is destroyed along with any colonists standing at it. Destroying the
    /// Anchor first saves the outpost.
    mutating func updateAnchor(at index: Int, _ dt: Double) {
        var enemy = enemies[index]
        defer { enemies[index] = enemy }

        switch enemy.state {
        case .descending(let outpostID):
            guard isOutpostIntact(outpostID) else {
                enemy.state = .roaming
                return
            }
            let outpost = world.outposts[outpostID]
            let dx = world.delta(from: enemy.pos.x, to: outpost.x)
            let reach = tuning.anchorSpeed * dt
            enemy.pos.x = world.wrap(enemy.pos.x + clamp(dx, -reach, reach))

            let landingY = outpost.groundY + enemy.radius
            let wantedY = abs(dx) > 200 ? world.ceiling - 80 : landingY
            let climb = tuning.anchorDescentSpeed * dt
            enemy.pos.y += clamp(wantedY - enemy.pos.y, -climb, climb)

            if abs(dx) < 3, abs(enemy.pos.y - landingY) < 2 {
                enemy.state = .drilling(outpost: outpostID)
                events.append(.anchorLanded(id: enemy.id, outpost: outpostID))
            }

        case .drilling(let outpostID):
            // Another Anchor may have finished the job first.
            guard isOutpostIntact(outpostID) else {
                enemy.state = .roaming
                return
            }
            outpostIntegrity[outpostID] -= dt / tuning.drillTime
            if outpostIntegrity[outpostID] <= 0 {
                destroyOutpost(outpostID)
                enemy.state = .roaming
            }

        default:
            if let target = nearestIntactOutpost(to: enemy.pos.x) {
                enemy.state = .descending(outpost: target)
                return
            }
            // Nothing left to drill: lift off and drift.
            enemy.pos.x = world.wrap(enemy.pos.x + tuning.anchorSpeed * 0.5 * dt)
            let climb = tuning.anchorDescentSpeed * dt
            enemy.pos.y += clamp(world.ceiling - 120 - enemy.pos.y, -climb, climb)
        }
    }
}
