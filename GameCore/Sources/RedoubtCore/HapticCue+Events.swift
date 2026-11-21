import GameCore

/// Which `HapticCue` each Redoubt event is felt as.
extension HapticCue {
    /// The cue for an event, or nil for events that should not be felt. Redoubt is a constant
    /// crowd, so the routine is left out on purpose: no cue per shot fired (ten a second), per
    /// Skitter killed (several hundred a minute), per hit (a Thresher or a Burrow takes ten a
    /// second), per arrival or per Spitter wind-up (eight Spitters would make a constant
    /// buzz). What remains is what matters, weighted as in Ridgeline: a tap for a catch-sized
    /// moment, a double tap for a reward, a warning knock for a colonist in danger, an impact for
    /// a heavy kill or a colonist lost, a sweep for the Shockwave and a rumble for losing the
    /// orb, the power failing and the end.
    public static func cue(for event: RedoubtEvent) -> HapticCue? {
        switch event {
        case .orbFired, .shotEnded, .arrivalTelegraphed, .enemyArrived, .burrowSpawned, .spitterWindUp,
             .enemyFired, .enemyHit, .enemyWithdrew, .airlockOpened, .airlockClosed, .lineScattered,
             .orbRespawned, .allColonistsLost:
            nil
        case .enemyDestroyed(_, let role, _, _, let byShockwave):
            switch role {
            case .skitter: nil
            // The Shockwave's own sweep covers the small fry it clears.
            case .gleaner, .spitter, .husk: byShockwave ? nil : .tap
            case .burrow, .thresher: .impact
            }
        case .colonistPickedUp:
            .tick
        // One cue per delivery, however long the line: every delivery has a first colonist.
        case .colonistDelivered(_, _, let position, _):
            position == 1 ? .doubleTap : nil
        case .waveStarted, .colonistFreed, .chargeEarned:
            .tap
        case .waveCleared, .extraLife, .powerCutEnded:
            .doubleTap
        case .colonistSeized, .huskFormed:
            .warning
        case .colonistTaken, .colonistCrushed:
            .impact
        case .shockwave:
            .sweep
        case .orbDestroyed, .powerCutBegan, .gameOver:
            .rumble
        }
    }
}
