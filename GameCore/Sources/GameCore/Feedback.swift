/// A physical cue for an event. The app turns each into a Core Haptics pattern, on the phone or on
/// a game controller.
public enum HapticCue: String, Sendable, CaseIterable {
    /// The lightest tick, for things that happen often.
    case tick
    /// A firm single tap: a catch, a delivery, a wave start.
    case tap
    /// Two quick taps: a reward (extra life, shield charged, wave cleared).
    case doubleTap
    /// A sharp knock: a warning (overheat, Lancer wind-up, outpost under attack).
    case warning
    /// A heavy thud: the shield breaking, an outpost lost.
    case impact
    /// A strong blast that sweeps outward and fades: a Shockwave.
    case sweep
    /// A long rumble: losing the ship, Blackout.
    case rumble

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
