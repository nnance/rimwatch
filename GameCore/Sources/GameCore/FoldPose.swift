/// How the phone is held, as far as the game cares.
public enum FoldPose: Sendable, Equatable {
    /// Fully or partially open: the inner display is in use and the game can be played.
    case open
    /// Folded shut: only the outer display is available.
    case closed
    /// A phone without a hinge.
    case noHinge

    public var isPlayfieldAvailable: Bool { self == .open }
}
