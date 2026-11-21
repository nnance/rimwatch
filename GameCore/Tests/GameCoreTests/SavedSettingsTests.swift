import Foundation
import Testing
import GameCore

/// An in-memory store, standing in for UserDefaults.
private final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@Suite struct SavedSettingsTests {
    private static let ridgeline: ModeID = "ridgeline"
    private static let other: ModeID = "other"

    private static func table(_ scores: [Int]) -> HighScoreTable {
        HighScoreTable(entries: scores.map {
            HighScoreEntry(score: $0, wave: 3, date: Date(timeIntervalSince1970: 1_000_000), saved: 1)
        })
    }

    private static func bytes(_ table: HighScoreTable) throws -> Data {
        try JSONEncoder().encode(table)
    }

    @Test func theKeysKeepTheirNamesAndDifferPerMode() {
        #expect(SettingsKeys.options == "rimwatch.options.v1")
        #expect(SettingsKeys.legacyHighScores == "rimwatch.highScores.v1")
        #expect(SettingsKeys.highScores(Self.ridgeline) == "rimwatch.highScores.ridgeline.v1")
        #expect(SettingsKeys.highScores(Self.other) != SettingsKeys.highScores(Self.ridgeline))
        #expect(SettingsKeys.highScores(Self.ridgeline) != SettingsKeys.legacyHighScores)
    }

    @Test func theOldTableMovesToItsOwnerByteForByte() throws {
        let store = MemoryStore()
        let legacy = try Self.bytes(Self.table([900, 400]))
        store.values[SettingsKeys.legacyHighScores] = legacy
        let settings = SavedSettings(store: store)
        settings.migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.data(forKey: SettingsKeys.highScores(Self.ridgeline)) == legacy)
        #expect(store.values[SettingsKeys.legacyHighScores] == nil)
        #expect(settings.highScores(for: Self.ridgeline) == Self.table([900, 400]))
        #expect(settings.highScores(for: Self.other).entries.isEmpty)
        // Running it again changes nothing.
        settings.migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.data(forKey: SettingsKeys.highScores(Self.ridgeline)) == legacy)
        #expect(store.values.count == 1)
    }

    @Test func anExistingModeTableWinsAndTheOldKeyStillGoes() throws {
        let store = MemoryStore()
        let current = try Self.bytes(Self.table([5000]))
        store.values[SettingsKeys.legacyHighScores] = try Self.bytes(Self.table([900]))
        store.values[SettingsKeys.highScores(Self.ridgeline)] = current
        SavedSettings(store: store).migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.data(forKey: SettingsKeys.highScores(Self.ridgeline)) == current)
        #expect(store.values[SettingsKeys.legacyHighScores] == nil)
    }

    @Test func withNoOldTableNothingIsWritten() {
        let store = MemoryStore()
        SavedSettings(store: store).migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.values.isEmpty)
    }

    @Test func anUnreadableOldTableIsCopiedAsItIsAndReadsAsEmpty() {
        let store = MemoryStore()
        let junk = Data("not a table".utf8)
        store.values[SettingsKeys.legacyHighScores] = junk
        let settings = SavedSettings(store: store)
        settings.migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.data(forKey: SettingsKeys.highScores(Self.ridgeline)) == junk)
        #expect(store.values[SettingsKeys.legacyHighScores] == nil)
        #expect(settings.highScores(for: Self.ridgeline).entries.isEmpty)
    }

    @Test func tablesAreSavedPerMode() {
        let settings = SavedSettings(store: MemoryStore())
        settings.setHighScores(Self.table([300]), for: Self.ridgeline)
        settings.setHighScores(Self.table([700]), for: Self.other)
        #expect(settings.highScores(for: Self.ridgeline) == Self.table([300]))
        #expect(settings.highScores(for: Self.other) == Self.table([700]))
    }

    @Test func optionsAreStoredAsBeforeAndMigrationLeavesThemAlone() throws {
        let store = MemoryStore()
        let settings = SavedSettings(store: store)
        #expect(settings.options == GameOptions())
        var options = GameOptions()
        options.adjust(.soundVolume, by: -1, wrap: false)
        settings.options = options
        let stored = try #require(store.data(forKey: SettingsKeys.options))
        #expect(try JSONDecoder().decode(GameOptions.self, from: stored) == options)
        store.values[SettingsKeys.legacyHighScores] = try Self.bytes(Self.table([100]))
        settings.migrateLegacyHighScores(to: Self.ridgeline)
        #expect(store.data(forKey: SettingsKeys.options) == stored)
        #expect(settings.options == options)
    }

    @Test func resetClearsEveryKey() throws {
        let store = MemoryStore()
        let settings = SavedSettings(store: store)
        settings.options = GameOptions()
        store.values[SettingsKeys.legacyHighScores] = try Self.bytes(Self.table([100]))
        settings.setHighScores(Self.table([200]), for: Self.ridgeline)
        settings.setHighScores(Self.table([300]), for: Self.other)
        settings.reset(modes: [Self.ridgeline, Self.other])
        #expect(store.values.isEmpty)
    }

    @Test func userDefaultsIsAStore() throws {
        let suite = "rimwatch.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = try Self.bytes(Self.table([42]))
        defaults.set(legacy, forKey: SettingsKeys.legacyHighScores)
        let settings = SavedSettings(store: defaults)
        settings.migrateLegacyHighScores(to: Self.ridgeline)
        #expect(defaults.data(forKey: SettingsKeys.highScores(Self.ridgeline)) == legacy)
        #expect(defaults.object(forKey: SettingsKeys.legacyHighScores) == nil)
    }
}
