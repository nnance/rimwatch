import Foundation
import GameCore
import RidgelineCore

/// Options and one high-score table per mode, persisted in UserDefaults as JSON (see
/// `SavedSettings`). Audio, haptics and the gamepad read their options from here once they exist.
@MainActor
final class Settings {
    static let shared = Settings()

    /// Every mode with a table, and the mode that owns the table saved before there were modes.
    private static let modes: [ModeID] = [ModeDescriptor.ridgeline.id]
    private static let legacyHighScoreOwner = ModeDescriptor.ridgeline.id

    private let saved: SavedSettings

    init(defaults: UserDefaults = .standard) {
        saved = SavedSettings(store: defaults)
        #if DEBUG
        // Launch with -resetSettings to start from defaults and empty tables.
        if ProcessInfo.processInfo.arguments.contains("-resetSettings") {
            saved.reset(modes: Self.modes)
        }
        #endif
        saved.migrateLegacyHighScores(to: Self.legacyHighScoreOwner)
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
