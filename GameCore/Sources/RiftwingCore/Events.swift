import GameCore

/// Things that happened during a Riftwing step, for sound, haptics, banners, popups and
/// effects. The run never reads them back. Positions are playfield units.
public enum RiftwingEvent: Sendable, Equatable {
    // Waves and the cavern
    /// A wave began in this layout (an index into `RiftwingCavern.layouts`).
    case waveStarted(wave: Int, layout: Int)
    /// Every rig is down and every pod settled. `freed` colonists scored `bonus`.
    case waveCleared(wave: Int, freed: Int, bonus: Int)
    /// The rock starts to rumble: the next wave is in a new layout. The break is longer.
    case cavernShifting(from: Int, to: Int)
    /// The new ledges and vents are in place.
    case cavernShifted(layout: Int)
    /// Every colonist of this wave was lost: the next wave is flown in the dark.
    case allColonistsLost(wave: Int)
    case lampsFailed
    /// A colonist freed in the dark brought the lamps back.
    case lampsRestored
    /// The wave has dragged on: gas will rise from the Rift to `level` after the warning.
    case riftWarning(level: Double)
    /// The breath's last step: after this longer warning the gas fills the whole gallery to the
    /// roof (`level`), taking everything not protected; then the cycle starts again from the
    /// lowest step. Sent instead of `riftWarning` for that step.
    case riftFillWarning(level: Double)
    /// The gas is rising.
    case riftBreathed(level: Double)
    /// The gas has sunk back into the Rift.
    case riftSettled

    // The rider
    /// One flap; `fromLedge` when it took off from a ledge.
    case flapped(at: Vec2, fromLedge: Bool)
    case landed(at: Vec2, ledge: Int)
    /// Its head struck a ledge's underside.
    case bumpedLedge(at: Vec2)
    /// It flew up into the roof and was knocked down a little (nothing clings to the roof).
    case bumpedRoof(at: Vec2)
    case diveBegan(at: Vec2)
    /// The dive was let go: the wings start to open.
    case wingsOpening(at: Vec2)
    /// The wings are open again: it can flap.
    case wingsOpened(at: Vec2)
    case ventEntered(vent: Int, at: Vec2)
    /// It met an opponent from above. `stoop` when it was diving.
    case clashWon(opponent: Int, role: RiftwingRole, at: Vec2, stoop: Bool)
    /// Near level: both thrown apart.
    case clashBounced(opponent: Int, role: RiftwingRole, at: Vec2)
    /// It met an opponent from below (a life lost follows unless it was protected).
    case clashLost(opponent: Int, role: RiftwingRole, at: Vec2)
    /// It met a Gleaner from below and was bumped away, unhurt.
    case gleanerBumped(opponent: Int, at: Vec2)
    case riderLost(at: Vec2, livesLeft: Int, cause: RiftwingLossCause)
    case riderRespawned(at: Vec2, ledge: Int)
    case extraLife(lives: Int)

    // Opponents
    /// A glow in a tunnel mouth: an opponent flies out here after the telegraph time.
    case arrivalTelegraphed(id: Int, role: RiftwingRole, side: RiftwingSide, at: Vec2)
    case opponentArrived(id: Int, role: RiftwingRole, at: Vec2)
    /// A Warden (or a Striker or Warden hatched tougher) dived.
    case opponentDived(id: Int, role: RiftwingRole, at: Vec2)
    /// It took a blow and stayed on its rig, `blowsLeft` to go.
    case opponentHit(id: Int, role: RiftwingRole, at: Vec2, blowsLeft: Int)
    /// Knocked off (a rig drops a pod: `podDropped` follows) or destroyed (a Gleaner). Scores
    /// `points`, of which `stoopBonus` for the height fallen in a stoop.
    case opponentDestroyed(id: Int, role: RiftwingRole, at: Vec2, points: Int, stoopBonus: Int)
    /// Lost without a blow: into the Rift or the breath. No pod, no points.
    case opponentFell(id: Int, role: RiftwingRole, at: Vec2, cause: RiftwingFallCause)
    /// A Gleaner left at the end of a wave, or flew off through a mouth with nothing.
    case opponentWithdrew(id: Int, role: RiftwingRole, at: Vec2)
    case mineLaid(id: Int, by: Int, at: Vec2)
    case mineCleared(id: Int, at: Vec2, reason: RiftwingMineEnd)

    // Pods
    case podDropped(id: Int, at: Vec2, from: RiftwingRole)
    case podLanded(id: Int, at: Vec2, ledge: Int)
    /// Freed from a ledge (or a Gleaner's grip): the `order`th this wave, scoring `points`.
    case podFreed(id: Int, at: Vec2, order: Int, points: Int)
    /// Caught in the air: double points.
    case podCaught(id: Int, at: Vec2, order: Int, points: Int)
    /// A Gleaner has hold of it.
    case podSeized(id: Int, by: Int, at: Vec2)
    /// A Gleaner lifted it and is carrying it to a mouth.
    case podCarried(id: Int, by: Int, at: Vec2)
    case podLost(id: Int, at: Vec2, cause: RiftwingPodLoss)
    /// It will hatch into `becomes` in `RiftwingTuning.hatchWarning` seconds.
    case hatchWarning(id: Int, at: Vec2, becomes: RiftwingRole)
    case podHatched(id: Int, opponent: Int, role: RiftwingRole, at: Vec2)

    case gameOver(score: Int)
}

/// What cost the rider a life.
public enum RiftwingLossCause: Sendable, Equatable {
    /// Met an opponent from below.
    case clash(opponent: Int, role: RiftwingRole)
    case mine(id: Int)
    /// Fell into the Rift.
    case rift
    /// Caught low in the Rift's breath.
    case breath
}

/// How an opponent fell without a blow.
public enum RiftwingFallCause: Sendable, Equatable {
    case rift
    case breath
}

/// How a pod's colonist was lost.
public enum RiftwingPodLoss: Sendable, Equatable {
    /// It fell into the Rift.
    case rift
    /// It lay too long and hatched.
    case hatched
    /// A Gleaner carried it out through a tunnel mouth.
    case carried
    /// The breath caught it low.
    case breath
}

/// Why a mine went.
public enum RiftwingMineEnd: Sendable, Equatable {
    /// Its Sower was struck down.
    case sowerDown
    /// It was the oldest of its Sower's and a new one was laid, or it timed out.
    case expired
    /// The wave ended.
    case waveEnded
    /// The rider touched it.
    case struck
}
