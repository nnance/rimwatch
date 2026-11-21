import Foundation
import GameCore

/// Options and one high-score table per mode, persisted in UserDefaults as JSON (see
/// `SavedSettings`). Audio, haptics and the gamepad read their options from here once they exist.
@MainActor
final class Settings {
    private let saved: SavedSettings

    /// `modes` is every mode with a table; `legacyHighScoreOwner` is the mode that owns the table
    /// saved before there were modes. The shared instance (`Settings.shared`) is made where the
    /// modes are known.
    init(modes: [ModeID], legacyHighScoreOwner: ModeID, defaults: UserDefaults = .standard) {
        saved = SavedSettings(store: defaults)
        #if DEBUG
        // Launch with -resetSettings to start from defaults and empty tables.
        if ProcessInfo.processInfo.arguments.contains("-resetSettings") {
            saved.reset(modes: modes)
        }
        #endif
        saved.migrateLegacyHighScores(to: legacyHighScoreOwner)
    }

    var options: GameOptions {
        get { saved.options }
        set { saved.options = newValue }
    }

    func highScores(for mode: ModeID) -> HighScoreTable {
        saved.highScores(for: mode)
    }

    func setHighScores(_ table: HighScoreTable, for mode: ModeID) {
        saved.setHighScores(table, for: mode)
    }
}
