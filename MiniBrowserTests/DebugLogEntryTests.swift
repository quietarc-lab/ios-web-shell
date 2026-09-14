import XCTest
@testable import MiniBrowser

final class DebugLogEntryTests: XCTestCase {
    func testSensitiveAssignmentsAreRedacted() {
        let entry = DebugLogEntry(action: "Test", fields: [
            ("DETAIL", "token=abc123&mode=1 password=hunter2")
        ])
        XCTAssertFalse(entry.plainText.contains("abc123"))
        XCTAssertFalse(entry.plainText.contains("hunter2"))
        XCTAssertTrue(entry.plainText.contains("[REDACTED]"))
    }

    func testSensitiveURLQueryValuesAreRedacted() {
        let url = URL(string: "https://example.com/path?token=abc&normal=ok")!
        let safe = LogSanitizer.url(url)
        XCTAssertFalse(safe.contains("token=abc"))
        XCTAssertTrue(safe.contains("normal=ok"))
    }

    func testPlainTextKeepsMillisecondResolutionForAsyncOrdering() {
        let date = Date(timeIntervalSince1970: 1_000_000.123)
        let entry = DebugLogEntry(date: date, action: "Test", fields: [])
        XCTAssertTrue(entry.plainText.range(of: #"\d{2}:\d{2}:\d{2}\.\d{3}"#,
                                            options: .regularExpression) != nil)
    }

    @MainActor
    func testDebugLogStoreRetainsNewestEntriesWithinCapacity() {
        let suiteName = "DebugLogEntryTests.capacity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DebugLogStore(defaults: defaults, capacity: 2)
        store.append(action: "First", fields: [])
        store.append(action: "Second", fields: [])
        store.append(action: "Third", fields: [])

        XCTAssertEqual(store.entries.map(\.action), ["Second", "Third"])
        XCTAssertTrue(store.plainText(limit: 1).contains("ACTION: Third"))
        XCTAssertFalse(store.plainText(limit: 1).contains("Second"))
    }
}
