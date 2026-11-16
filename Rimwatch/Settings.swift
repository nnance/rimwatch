import Foundation
import GameCore

/// Options and the high-score table, persisted in UserDefaults as JSON. Audio, haptics and the
/// gamepad read their options from here once they exist.
@MainActor
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let options = "rimwatch.options.v1"
        static let highScores = "rimwatch.highScores.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        // Launch with -resetSettings to start from defaults and an empty table.
        if ProcessInfo.processInfo.arguments.contains("-resetSettings") {
            defaults.removeObject(forKey: Key.options)
            defaults.removeObject(forKey: Key.highScores)
        }
        #endif
    }

    var options: GameOptions {
        get { load(GameOptions.self, Key.options) ?? GameOptions() }
        set { save(newValue, Key.options) }
    }

    var highScores: HighScoreTable {
        get { load(HighScoreTable.self, Key.highScores) ?? HighScoreTable() }
        set { save(newValue, Key.highScores) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
