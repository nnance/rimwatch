import Foundation

public struct HighScoreEntry: Sendable, Equatable, Codable {
    public var score: Int
    /// The wave the run reached.
    public var wave: Int
    public var date: Date
    /// Colonists brought home during the run. Tables saved before this was recorded decode as 0.
    public var saved: Int

    public init(score: Int, wave: Int, date: Date, saved: Int = 0) {
        self.score = score
        self.wave = wave
        self.date = date
        self.saved = saved
    }

    private enum CodingKeys: String, CodingKey {
        case score, wave, date, saved
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(Int.self, forKey: .score)
        wave = try c.decode(Int.self, forKey: .wave)
        date = try c.decode(Date.self, forKey: .date)
        saved = try c.decodeIfPresent(Int.self, forKey: .saved) ?? 0
    }
}

/// The local high-score table: the best `capacity` scores, highest first. An equal score ranks
/// below the one already there, so the earlier run keeps its place.
public struct HighScoreTable: Sendable, Equatable, Codable {
    public static let capacity = 10

    public private(set) var entries: [HighScoreEntry] = []

    /// Keeps the valid entries, best first, at most `capacity` of them. Equal scores keep their
    /// order (the earlier run stays above).
    public init(entries: [HighScoreEntry] = []) {
        let valid = entries.filter { $0.score > 0 && $0.wave >= 0 && $0.saved >= 0 }
        let ranked = valid.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)
        self.entries = Array(ranked.prefix(Self.capacity))
    }

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    /// Stored tables go through the same normalisation as `init(entries:)`: an entry that fails
    /// to decode is dropped rather than losing the whole table.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try c.decodeIfPresent([LenientEntry].self, forKey: .entries) ?? []
        self.init(entries: stored.compactMap(\.entry))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
    }

    private struct LenientEntry: Decodable {
        let entry: HighScoreEntry?

        init(from decoder: any Decoder) throws {
            entry = try? HighScoreEntry(from: decoder)
        }
    }

    /// The best score so far, if any.
    public var best: HighScoreEntry? { entries.first }

    /// Index of the most recently set entry (latest date), if any. Ties go to the higher rank.
    public var latestIndex: Int? {
        guard !entries.isEmpty else { return nil }
        var best = 0
        for index in entries.indices where entries[index].date > entries[best].date {
            best = index
        }
        return best
    }

    /// Whether a score would get a place in the table. A score of zero never does.
    public func qualifies(_ score: Int) -> Bool {
        score > 0 && (entries.count < Self.capacity || score > entries[entries.count - 1].score)
    }

    /// Adds an entry if it qualifies. Returns its rank (0 is the top), or nil if it didn't place.
    @discardableResult
    public mutating func insert(_ entry: HighScoreEntry) -> Int? {
        guard qualifies(entry.score) else { return nil }
        let index = entries.firstIndex { $0.score < entry.score } ?? entries.count
        entries.insert(entry, at: index)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        return index
    }
}

/// "12,340": digits grouped in threes, without depending on the device locale.
public func groupedDigits(_ value: Int) -> String {
    let digits = String(abs(value))
    var out = ""
    for (index, ch) in digits.enumerated() {
        if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return value < 0 ? "-" + out : out
}

/// "16 Nov 2026" in the device's time zone, without depending on the device locale.
public func shortDate(_ date: Date, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.day, .month, .year], from: date)
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
    return "\(parts.day ?? 1) \(month) \(parts.year ?? 2000)"
}
