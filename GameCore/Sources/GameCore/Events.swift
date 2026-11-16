/// Things that happened during a simulation step. The renderer, audio and haptics react to these;
/// the simulation itself never reads them back.
public enum GameEvent: Sendable, Equatable {
    case waveStarted(Int)
    /// Every enemy in the wave is gone. `bonus` rewards the colonists still alive.
    case waveCleared(wave: Int, bonus: Int)

    case playerFired(at: Vec2, facing: Double)
    case playerOverheated
    case playerBlinked(from: Vec2, to: Vec2)
    case shockwave(at: Vec2)
    /// Bringing colonists home filled the shield: it will absorb the next hit.
    case shieldCharged
    /// The shield absorbed a hit and is now empty.
    case shieldBroken
    case playerDestroyed(at: Vec2, livesLeft: Int)
    case playerRespawned
    case extraLife

    case enemySpawned(id: Int, kind: EnemyKind)
    case enemyFired(at: Vec2)
    /// Damaged but not destroyed.
    case enemyHit(id: Int, at: Vec2)
    case enemyDestroyed(id: Int, kind: EnemyKind, at: Vec2, points: Int)
    /// A Harvester finished an abduction and became a Husk. The enemy keeps its id.
    case huskFormed(id: Int, at: Vec2)
    case mineLaid(id: Int, at: Vec2)
    /// A Lancer has started winding up for a charge.
    case lancerTelegraph(id: Int)
    case lancerCharged(id: Int)
    case anchorLanded(id: Int, outpost: Int)

    case colonistGrabbed(id: Int)
    /// The colonist was let go in mid-air and is now falling.
    case colonistDropped(id: Int)
    case colonistCaught(id: Int)
    case colonistDelivered(id: Int, outpost: Int, points: Int)
    /// The colonist fell a short way and landed safely without being caught.
    case colonistLanded(id: Int)
    case colonistLost(id: Int, at: Vec2)

    case outpostDestroyed(id: Int)
    /// A supply drop rebuilt the outpost and brought new colonists.
    case outpostRestored(id: Int)
    /// The last colonist is gone.
    case blackoutBegan
    case blackoutEnded

    case gameOver(score: Int)
}
