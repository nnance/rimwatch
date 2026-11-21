import GameCore

/// Every mode the app can run. The only shell-level file that names a mode.
@MainActor
enum ModeRegistry {
    struct Entry {
        let descriptor: ModeDescriptor
        /// The shell's look while this mode runs.
        let style: ShellStyle
        let make: (ShellServices) -> any ModeDriver

        init<M: GameMode>(_: M.Type) {
            descriptor = M.descriptor
            style = M.shellStyle
            make = { ModeHost<M>(services: $0) }
        }
    }

    static let all: [Entry] = [Entry(RidgelineMode.self)]
    /// The mode the app starts in.
    static var launch: Entry { all[0] }
    /// The mode that owns the high-score table saved before there were modes.
    static let legacyHighScoreOwner: ModeID = RidgelineMode.descriptor.id
}

extension Settings {
    /// The app's settings, with a high-score table for every mode.
    static let shared = Settings(modes: ModeRegistry.all.map(\.descriptor.id),
                                 legacyHighScoreOwner: ModeRegistry.legacyHighScoreOwner)
}
