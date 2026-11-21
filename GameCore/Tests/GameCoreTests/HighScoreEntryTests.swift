import Foundation
import Testing
@testable import GameCore

@Suite struct HighScoreEntryTests {
    @Test func olderSavedTablesDecodeWithoutLoss() throws {
        // A table saved before `saved` existed.
        let json = #"{"entries":[{"score":4200,"wave":5,"date":700000000},{"score":900,"wave":2,"date":700000500}]}"#
        let table = try JSONDecoder().decode(HighScoreTable.self, from: Data(json.utf8))
        #expect(table.entries.map(\.score) == [4200, 900])
        #expect(table.entries.map(\.wave) == [5, 2])
        #expect(table.entries.map(\.saved) == [0, 0])
        #expect(table.entries[0].date == Date(timeIntervalSinceReferenceDate: 700_000_000))
    }

    @Test func newEntriesRoundTrip() throws {
        let table = HighScoreTable(entries: [HighScoreEntry(score: 10, wave: 3, date: Date(timeIntervalSinceReferenceDate: 5),
                                                            saved: 7)])
        let decoded = try JSONDecoder().decode(HighScoreTable.self, from: JSONEncoder().encode(table))
        #expect(decoded == table)
        #expect(decoded.entries[0].saved == 7)
    }

    @Test func latestEntryIsTheMostRecentlyDated() {
        let table = HighScoreTable(entries: [
            HighScoreEntry(score: 500, wave: 1, date: Date(timeIntervalSinceReferenceDate: 100)),
            HighScoreEntry(score: 900, wave: 2, date: Date(timeIntervalSinceReferenceDate: 50)),
            HighScoreEntry(score: 300, wave: 1, date: Date(timeIntervalSinceReferenceDate: 300)),
        ])
        #expect(table.latestIndex == 2)
        #expect(table.best?.score == 900)
        #expect(HighScoreTable().latestIndex == nil)
    }

    @Test func shortDateIsLocaleFree() {
        let utc = TimeZone(identifier: "UTC")!
        // 2001-01-01 plus 700,000,000 s is 2023-03-08, 20:26 UTC.
        #expect(shortDate(Date(timeIntervalSinceReferenceDate: 700_000_000), timeZone: utc) == "8 Mar 2023")
    }
}
