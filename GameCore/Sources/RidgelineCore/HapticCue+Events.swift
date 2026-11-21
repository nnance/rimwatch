import GameCore

/// Which `HapticCue` each Ridgeline event is felt as.
extension HapticCue {
    /// The cue for an event, or nil for events that should not be felt. Firing is left out on
    /// purpose: it repeats ten times a second.
    public static func cue(for event: GameEvent) -> HapticCue? {
        switch event {
        case .playerFired, .enemyFired, .enemySpawned, .mineLaid, .colonistLanded, .playerRespawned:
            nil
        case .enemyHit:
            .tick
        case .enemyDestroyed(_, let kind, _, _):
            kind == .mine || kind == .mote ? .tick : .tap
        case .waveStarted, .colonistCaught, .colonistDelivered, .playerBlinked, .outpostRestored:
            .tap
        case .waveCleared, .extraLife, .shieldCharged, .blackoutEnded:
            .doubleTap
        case .playerOverheated, .lancerTelegraph, .anchorLanded, .colonistGrabbed, .colonistDropped,
             .huskFormed:
            .warning
        case .shockwave:
            .sweep
        case .shieldBroken, .lancerCharged, .colonistLost, .outpostDestroyed:
            .impact
        case .playerDestroyed, .blackoutBegan, .gameOver:
            .rumble
        }
    }
}
