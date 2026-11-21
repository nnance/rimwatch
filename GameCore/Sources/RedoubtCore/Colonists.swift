import Foundation
import GameCore

// Colonists: where they shelter, the line behind the orb, the airlock, and losing them.
extension RedoubtRun {
    func colonistIndex(_ id: Int) -> Int? {
        colonists.firstIndex { $0.id == id }
    }

    /// Scatters `count` colonists over the floor, clear of the orb, the airlock, the wall and
    /// each other.
    mutating func placeColonists(_ count: Int) {
        let margin = tuning.colonistWallMargin
        for _ in 0..<count {
            var pos = centre
            for _ in 0..<30 {
                pos = Vec2(rng.range(margin...(tuning.arenaWidth - margin)),
                           rng.range(margin...(tuning.arenaHeight - margin)))
                if isClearOfOrb(pos, by: tuning.colonistClearance),
                   distance(pos, airlock.pos) >= tuning.colonistClearance,
                   !colonists.contains(where: { distance($0.pos, pos) < 45 }) {
                    break
                }
            }
            colonists.append(RedoubtColonist(id: takeID(), pos: pos))
        }
    }

    mutating func updateColonists(_ dt: Double) {
        let decay = exp(-tuning.pushDecay * dt)
        for c in colonists.indices where colonists[c].state == .sheltering
            && (colonists[c].vel.x != 0 || colonists[c].vel.y != 0) {
            colonists[c].pos = clampToFloor(colonists[c].pos + colonists[c].vel * dt, radius: tuning.colonistRadius)
            colonists[c].vel = colonists[c].vel * decay
            if colonists[c].vel.length < 1 { colonists[c].vel = .zero }
        }
        guard orb.isAlive else { return }

        // The line: each follower keeps at most one spacing behind the one ahead, like beads on
        // a cord, so the line traces the orb's path round corners.
        var leader = orb.pos
        for id in line {
            guard let c = colonistIndex(id) else { continue }
            let offset = colonists[c].pos - leader
            let d = offset.length
            if d > tuning.lineSpacing {
                colonists[c].pos = leader + offset * (tuning.lineSpacing / d)
            }
            leader = colonists[c].pos
        }

        guard phase == .fighting else { return }
        // Touching a sheltering colonist adds them to the end of the line.
        let reach = tuning.orbRadius + tuning.colonistRadius + tuning.pickupSlack
        for c in colonists.indices where colonists[c].state == .sheltering
            && distance(colonists[c].pos, orb.pos) < reach {
            colonists[c].state = .following
            colonists[c].vel = .zero
            line.append(colonists[c].id)
            events.append(.colonistPickedUp(id: colonists[c].id, at: colonists[c].pos, position: line.count))
        }

        if airlock.isOpen, !line.isEmpty, distance(orb.pos, airlock.pos) < tuning.airlockReach {
            deliverLine()
        }
    }

    /// The whole line goes through the airlock: the nth colonist scores n times the delivery
    /// points, and every `colonistsPerCharge`th delivery of the run earns a Shockwave charge.
    private mutating func deliverLine() {
        for (slot, id) in line.enumerated() {
            guard let c = colonistIndex(id) else { continue }
            let position = slot + 1
            let points = tuning.deliveryPoints * position
            colonists[c].state = .delivered
            colonists[c].claimedBy = nil
            colonists[c].pos = airlock.pos
            colonistsDelivered += 1
            colonistsSaved += 1
            addScore(points)
            events.append(.colonistDelivered(id: id, at: airlock.pos, position: position, points: points))
            if colonistsDelivered % tuning.colonistsPerCharge == 0, orb.charges < tuning.maxCharges {
                orb.charges += 1
                events.append(.chargeEarned(charges: orb.charges))
            }
        }
        line.removeAll()
        if isPowerCut {
            isPowerCut = false
            events.append(.powerCutEnded)
        }
    }

    /// The orb was lost: its followers break away and shelter wherever they land.
    mutating func scatterLine() {
        guard !line.isEmpty else { return }
        let count = line.count
        for id in line {
            guard let c = colonistIndex(id) else { continue }
            let angle = rng.range(0...(2 * .pi))
            colonists[c].state = .sheltering
            colonists[c].vel = unitVector(angle) * tuning.scatterSpeed
        }
        line.removeAll()
        events.append(.lineScattered(count: count))
    }

    /// Taken by the enemy with id `enemy` (a Gleaner that got them away, or whatever reached the
    /// end of the line).
    mutating func loseColonist(at c: Int, takenBy role: RedoubtRole, enemy: Int) {
        markLost(c)
        events.append(.colonistTaken(id: colonists[c].id, by: role, enemy: enemy, at: colonists[c].pos))
        noteLoss()
    }

    mutating func crushColonist(at c: Int, by thresher: Int) {
        if colonists[c].state == .following { line.removeAll { $0 == colonists[c].id } }
        markLost(c)
        events.append(.colonistCrushed(id: colonists[c].id, by: thresher, at: colonists[c].pos))
        noteLoss()
    }

    private mutating func markLost(_ c: Int) {
        colonists[c].state = .lost
        colonists[c].claimedBy = nil
        colonists[c].vel = .zero
    }

    /// Losing every colonist of a wave cuts the power for the next one.
    private mutating func noteLoss() {
        waveLost += 1
        if waveColonists > 0, waveLost == waveColonists {
            powerCutPending = true
            events.append(.allColonistsLost(wave: wave))
        }
    }
}
