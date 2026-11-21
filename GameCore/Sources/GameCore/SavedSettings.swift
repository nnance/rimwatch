import Foundation

/// Where settings are kept. `UserDefaults` already has all three.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// The keys settings are stored under.
public enum SettingsKeys {
    public static let options = "rimwatch.options.v1"
    /// The single high-score table saved before there were modes. It belonged to Ridgeline.
    public static let legacyHighScores = "rimwatch.highScores.v1"
    /// The mode played last, loaded at the next launch.
    public static let lastMode = "rimwatch.lastMode.v1"

    public static func highScores(_ mode: ModeID) -> String {
        "rimwatch.highScores.\(mode.rawValue).v1"
    }
}

/// Options, one high-score table per mode and the mode played last, stored as JSON.
public struct SavedSettings {
    public let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public var options: GameOptions {
        get { load(GameOptions.self, SettingsKeys.options) ?? GameOptions() }
        nonmutating set { save(newValue, SettingsKeys.options) }
    }

    /// The mode played last, or nil before any mode has been played.
    public var lastMode: ModeID? {
        get { load(ModeID.self, SettingsKeys.lastMode) }
        nonmutating set {
            if let newValue { save(newValue, SettingsKeys.lastMode) } else { store.removeObject(forKey: SettingsKeys.lastMode) }
        }
    }

    public func highScores(for mode: ModeID) -> HighScoreTable {
        load(HighScoreTable.self, SettingsKeys.highScores(mode)) ?? HighScoreTable()
    }

    public func setHighScores(_ table: HighScoreTable, for mode: ModeID) {
        save(table, SettingsKeys.highScores(mode))
    }

    /// Moves the table saved before there were modes to `owner`'s key. The bytes are copied
    /// unchanged, and only if `owner` has no table yet; the old key is removed once the copy
    /// reads back. Does nothing when there is no old table, so it is safe to run at every launch.
    public func migrateLegacyHighScores(to owner: ModeID) {
        guard let legacy = store.data(forKey: SettingsKeys.legacyHighScores) else { return }
        let key = SettingsKeys.highScores(owner)
        if store.data(forKey: key) == nil {
            store.set(legacy, forKey: key)
            guard store.data(forKey: key) == legacy else { return }
        }
        store.removeObject(forKey: SettingsKeys.legacyHighScores)
    }

    /// Clears the options, the remembered mode, the old table and every listed mode's table. Run
    /// it before `migrateLegacyHighScores`.
    public func reset(modes: [ModeID]) {
        store.removeObject(forKey: SettingsKeys.options)
        store.removeObject(forKey: SettingsKeys.lastMode)
        store.removeObject(forKey: SettingsKeys.legacyHighScores)
        for mode in modes {
            store.removeObject(forKey: SettingsKeys.highScores(mode))
        }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
    }
}
