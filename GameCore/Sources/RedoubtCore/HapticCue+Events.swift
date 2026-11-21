import GameCore

extension HapticCue {
    /// The feel of a Redoubt event, if any. Empty until step 13c supplies the mapping; the app
    /// already routes every event through here.
    public static func cue(for event: RedoubtEvent) -> HapticCue? {
        nil
    }
}
