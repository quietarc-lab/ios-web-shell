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

    func testAlertMessageIsSingleLineAndRetainsDiagnosticText() {
        let message = LogSanitizer.alertMessage("未知の\nエラー token=abc123")
        XCTAssertEqual(message, "未知の\\nエラー token=[REDACTED]")
        XCTAssertFalse(message.contains("\n"))
    }

    func testAlertMessageIsBounded() {
        let message = LogSanitizer.alertMessage(String(repeating: "あ", count: 600))
        XCTAssertEqual(message.count, 512)
        XCTAssertTrue(message.hasSuffix("…"))
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

    func testUserAgentCatalogDiagnosticShowsRestrictionsAndAvailableIDsWithoutRawValues() {
        let catalog = [
            BrowserUserAgent(id: 1, name: "Safari iPhone", value: "raw-ua-one"),
            BrowserUserAgent(id: 2, name: "Chrome iPad", value: "raw-ua-two"),
            BrowserUserAgent(id: 3, name: "Firefox iPhone", value: "raw-ua-three")
        ]
        let snapshot = UserAgentCatalogDiagnostic.snapshot(
            catalog: catalog,
            restrictedKeys: ["2", "generated:legacy", "999"],
            expiryByID: [2: Date(timeIntervalSince1970: 1_000_000)],
            selectedID: 1
        )

        XCTAssertTrue(snapshot.contains("TOTAL_COUNT: 3"))
        XCTAssertTrue(snapshot.contains("AVAILABLE_COUNT: 2"))
        XCTAssertTrue(snapshot.contains("RESTRICTED_COUNT: 1"))
        XCTAssertTrue(snapshot.contains("UNKNOWN_RESTRICTION_COUNT: 2"))
        XCTAssertTrue(snapshot.contains("RESTRICTED_IDS: 2"))
        XCTAssertTrue(snapshot.contains("2=Chrome iPad@"))
        XCTAssertTrue(snapshot.contains("AVAILABLE_IDS: 1,3"))
        XCTAssertTrue(snapshot.contains("AVAILABLE: 1=Safari iPhone;3=Firefox iPhone"))
        XCTAssertTrue(snapshot.contains("SELECTED_ID: 1"))
        XCTAssertTrue(snapshot.contains("SELECTED_NAME: Safari iPhone"))
        XCTAssertFalse(snapshot.contains("raw-ua-one"))
        XCTAssertFalse(snapshot.contains("raw-ua-two"))
        XCTAssertFalse(snapshot.contains("raw-ua-three"))
    }
}
