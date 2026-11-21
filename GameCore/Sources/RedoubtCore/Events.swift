import GameCore

/// Things that happened during a Redoubt step, for sound, haptics, banners, popups and
/// particles. The run never reads them back. Positions are arena units.
public enum RedoubtEvent: Sendable, Equatable {
    // Waves
    /// A wave began with this many colonists sheltering on the floor.
    case waveStarted(wave: Int, colonists: Int)
    /// The floor is clear of everything that can be shot. `safe` colonists scored `bonus`.
    case waveCleared(wave: Int, safe: Int, bonus: Int)
    /// The airlock shut for the move between waves.
    case airlockClosed(at: Vec2)
    /// The airlock opened at its new place as a wave began.
    case airlockOpened(wall: ArenaWall, at: Vec2)
    /// Every colonist of this wave is lost: the next wave is fought in the dark.
    case allColonistsLost(wave: Int)
    case powerCutBegan
    /// A delivery brought the power back.
    case powerCutEnded

    // The orb
    case orbFired(at: Vec2, heading: Double)
    /// A shot (the orb's or an enemy's) is gone: where and why, so the renderer can spark it.
    case shotEnded(id: Int, at: Vec2, reason: RedoubtShotEnd)
    case shockwave(at: Vec2, destroyed: Int)
    /// A Shockwave charge was earned by deliveries; `charges` is the new count.
    case chargeEarned(charges: Int)
    case orbDestroyed(at: Vec2, livesLeft: Int, cause: RedoubtHitCause)
    /// Followers broke from the line when the orb was lost.
    case lineScattered(count: Int)
    case orbRespawned(at: Vec2)
    case extraLife(lives: Int)

    // Enemies
    /// An enemy will appear here after the telegraph time.
    case arrivalTelegraphed(id: Int, role: RedoubtRole, at: Vec2)
    case enemyArrived(id: Int, role: RedoubtRole, at: Vec2)
    /// A Burrow poured out a Skitter (no telegraph: the Burrow is the warning).
    case burrowSpawned(burrow: Int, id: Int, at: Vec2)
    /// A Spitter started its wind-up before a shot.
    case spitterWindUp(id: Int, at: Vec2)
    case enemyFired(id: Int, at: Vec2, heading: Double)
    /// Hit but not destroyed (a Burrow or Spitter losing a point, a Thresher pushed back).
    case enemyHit(id: Int, role: RedoubtRole, at: Vec2)
    case enemyDestroyed(id: Int, role: RedoubtRole, at: Vec2, points: Int, byShockwave: Bool)
    /// A Gleaner got its colonist away and became a Husk. It keeps its id.
    case huskFormed(id: Int, at: Vec2)
    /// A Thresher left the floor when the wave was cleared.
    case enemyWithdrew(id: Int, role: RedoubtRole, at: Vec2)

    // Colonists
    /// Joined the line at `position` (1 is right behind the orb).
    case colonistPickedUp(id: Int, at: Vec2, position: Int)
    /// A Gleaner grabbed them (from shelter or off the end of the line).
    case colonistSeized(id: Int, by: Int, at: Vec2)
    /// Their Gleaner was destroyed; they are sheltering where it fell.
    case colonistFreed(id: Int, at: Vec2)
    /// Lost: dragged away by a Gleaner, or taken off the end of the line; `enemy` is the id of the
    /// one responsible and `by` its role.
    case colonistTaken(id: Int, by: RedoubtRole, enemy: Int, at: Vec2)
    /// Crushed by the Thresher with id `by`.
    case colonistCrushed(id: Int, by: Int, at: Vec2)
    /// Through the airlock; `position` in the line, scoring `points`.
    case colonistDelivered(id: Int, at: Vec2, position: Int, points: Int)

    case gameOver(score: Int)
}

/// What touched the orb.
public enum RedoubtHitCause: Sendable, Equatable {
    case enemy(id: Int, role: RedoubtRole)
    case shot(id: Int)
}

/// Why a shot ended.
public enum RedoubtShotEnd: Sendable, Equatable {
    /// It struck an enemy (or, an enemy's shot, the orb).
    case hit
    /// It reached the wall; the event's position is on the wall.
    case wall
    /// Its lifetime ran out.
    case expired
    /// A Shockwave, a respawn or the end of the wave wiped it.
    case cleared
}
