import GameCore

/// Chooses Riftwing's music mood during play, from the structure of the run as Redoubt's does:
///
/// - with the lamps out the music is `.blackout`, from the moment they fail (as a wave starts)
///   until a colonist freed in the dark brings them back, both changes at once;
/// - otherwise a wave being flown is `.tension`, the normal state, made to loop for minutes;
/// - the break before the first wave and between waves (the cavern shifting included) is
///   `.calm`: the wingbeat pulse drops out and comes back with the next wave.
///
/// Every change follows a change in the run (a wave starting or clearing, the lamps failing or
/// coming back), each at most once a wave, so the mood cannot flap. The Rift's breath does not
/// change the music: its own warning and hiss carry it.
public struct RiftwingMoodDirector: Sendable {
    public private(set) var mood: MusicMood = .calm

    public init() {}

    /// The mood for the run as it stands now.
    public static func mood(fighting: Bool, lampsOut: Bool) -> MusicMood {
        if lampsOut { return .blackout }
        return fighting ? .tension : .calm
    }

    /// Reads the run and returns the mood to play.
    public mutating func update(run: RiftwingRun) -> MusicMood {
        update(fighting: run.phase == .fighting, lampsOut: run.isLampsOut)
    }

    /// The same from plain flags (for tests and other callers).
    public mutating func update(fighting: Bool, lampsOut: Bool) -> MusicMood {
        mood = Self.mood(fighting: fighting, lampsOut: lampsOut)
        return mood
    }

    /// Starts over for a new run.
    public mutating func reset() {
        self = RiftwingMoodDirector()
    }
}
