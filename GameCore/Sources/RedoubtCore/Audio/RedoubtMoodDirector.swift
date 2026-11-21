import GameCore

/// Chooses Redoubt's music mood during play. Redoubt is a constant crowd, so the rule follows
/// the structure of the run rather than a threat level:
///
/// - the power cut plays `.blackout`, from the moment the lights fail until a delivery brings
///   them back, both changes at once;
/// - otherwise a wave being fought is `.tension`, the normal state, a bed made to loop for
///   minutes;
/// - the break before the first wave and between waves is `.calm`: the pulse drops out for a
///   breath and comes back with the next wave.
///
/// Every change follows a change in the run (a wave starting or clearing, the power failing or
/// returning), each of which happens at most once a wave, so the mood cannot flap.
public struct RedoubtMoodDirector: Sendable {
    public private(set) var mood: MusicMood = .calm

    public init() {}

    /// The mood for the run as it stands now.
    public static func mood(fighting: Bool, powerCut: Bool) -> MusicMood {
        if powerCut { return .blackout }
        return fighting ? .tension : .calm
    }

    /// Reads the run and returns the mood to play.
    public mutating func update(run: RedoubtRun) -> MusicMood {
        update(fighting: run.phase == .fighting, powerCut: run.isPowerCut)
    }

    /// The same from plain flags (for tests and other callers).
    public mutating func update(fighting: Bool, powerCut: Bool) -> MusicMood {
        mood = Self.mood(fighting: fighting, powerCut: powerCut)
        return mood
    }

    /// Starts over for a new run.
    public mutating func reset() {
        self = RedoubtMoodDirector()
    }
}
