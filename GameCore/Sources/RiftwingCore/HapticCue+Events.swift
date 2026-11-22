import GameCore

/// Which `HapticCue` each Riftwing event is felt as.
extension HapticCue {
    /// The cue for an event, or nil for events that should not be felt. Riftwing's routine is
    /// flight, so it is left out on purpose: nothing for a flap (several a second, all game),
    /// landing, bumping a ledge, the dive, vents, a level bounce, arrivals, an opponent's dive,
    /// mines, or pods dropping and landing. What remains, weighted as in Redoubt:
    /// - a tap for a clash won and a wave starting; an impact for a stoop (a heavy blow);
    /// - a double tap for a reward: a pod freed or caught, a wave cleared, an extra life, the
    ///   lamps coming back;
    /// - a warning knock for danger coming: a pod seized by a Gleaner, the hatch warning, the
    ///   Rift's warning;
    /// - an impact for a colonist lost;
    /// - a rumble for a clash lost (the life it costs is not felt twice), any other life lost,
    ///   the cavern shifting, the lamps failing and game over.
    /// An event added to the game later is not felt until it is listed here.
    public static func cue(for event: RiftwingEvent) -> HapticCue? {
        switch event {
        case .clashWon(_, _, _, let stoop):
            stoop ? .impact : .tap
        case .waveStarted:
            .tap
        case .podFreed, .podCaught, .waveCleared, .extraLife, .lampsRestored:
            .doubleTap
        case .podSeized, .hatchWarning, .riftWarning:
            .warning
        case .podLost:
            .impact
        case .clashLost, .cavernShifting, .lampsFailed, .gameOver:
            .rumble
        case .riderLost(_, _, let cause):
            if case .clash = cause { nil } else { .rumble }
        default:
            nil
        }
    }
}
