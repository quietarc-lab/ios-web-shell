import Foundation
import XCTest
@testable import MiniBrowser

final class IsolationThreadMonitorTests: XCTestCase {
    func testModerationFeedParserClassifiesStateFieldAndIgnoresMetadata() {
        func row(_ url: String, state: String) -> String {
            ([url] + Array(repeating: "metadata", count: 14) + [state]).joined(separator: "<>")
        }

        let feed = """
        \(row("http://img.2chan.net/b/res/1234567890.htm", state: "2"))
        \(row("https://img.2chan.net/b/res/9876543210.htm?x=1", state: "1"))
        \(row("https://img.2chan.net/b/res/1111111111.htm", state: "9"))
        boardStatus<>ok
        <EOF>
        https://example.com/b/res/111.htm<>対象<>理由
        """

        XCTAssertEqual(
            IsolationThreadURLParser.moderationSnapshot(inIsolationFeed: feed),
            ModerationThreadSnapshot(
                isolatedIDs: ["1234567890"],
                deletedIDs: ["9876543210"]
            )
        )
        XCTAssertEqual(
            IsolationThreadURLParser.threadIDs(inIsolationFeed: feed),
            ["1234567890"]
        )
    }

    func testModerationFeedParserHandlesDuplicateAndMalformedRows() {
        func row(_ url: String, state: String) -> String {
            ([url] + Array(repeating: "metadata", count: 14) + [state]).joined(separator: "<>")
        }

        let feed = """
        \(row("https://img.2chan.net/b/res/123.htm", state: "2"))
        \(row("https://img.2chan.net/b/res/123.htm", state: "2"))
        \(row("https://img.2chan.net/b/res/456.htm", state: "1"))
        https://img.2chan.net/b/res/not-a-number.htm<>x
        \(row("https://example.com/b/res/789.htm", state: "2"))
        <EOF>
        """

        XCTAssertEqual(
            IsolationThreadURLParser.moderationSnapshot(inIsolationFeed: feed),
            ModerationThreadSnapshot(isolatedIDs: ["123"], deletedIDs: ["456"])
        )
    }

    func testIsolationFeedParserUsesFirstFieldAndIgnoresMetadata() {
        func row(_ url: String) -> String {
            ([url] + Array(repeating: "metadata", count: 14) + ["2"]).joined(separator: "<>")
        }

        let feed = """
        \(row("https://img.2chan.net/b/res/1234567890.htm"))
        \(row("https://img.2chan.net/b/res/9876543210.htm"))
        boardStatus<>ok
        <EOF>
        """

        XCTAssertEqual(
            IsolationThreadURLParser.threadIDs(inIsolationFeed: feed),
            ["1234567890", "9876543210"]
        )
    }

    func testPostBodyParserExtractsAllExactFutabaThreadURLs() {
        let body = """
        参照 https://img.2chan.net/b/res/123.htm?x=1
        http://img.2chan.net/b/res/456.htm。 https://example.com/b/res/789.htm
        malformed https://img.2chan.net/b/res/999.htmx
        """

        XCTAssertEqual(
            IsolationThreadURLParser.threadIDs(inPostBody: body),
            ["123", "456"]
        )
    }

    func testPostBodyReplacementChangesOnlyMatchingThreadURLs() {
        let body = "前 https://img.2chan.net/b/res/123.htm 後 https://img.2chan.net/b/res/456.htm?x=1"
        let replaced = IsolationThreadURLParser.replacingThreadURL(
            inPostBody: body,
            sourceThreadID: "123",
            with: URL(string: "https://img.2chan.net/b/res/789.htm")!
        )
        XCTAssertEqual(
            replaced,
            "前 https://img.2chan.net/b/res/789.htm 後 https://img.2chan.net/b/res/456.htm?x=1"
        )
        XCTAssertNil(IsolationThreadURLParser.replacingThreadURL(
            inPostBody: body,
            sourceThreadID: "999",
            with: URL(string: "https://img.2chan.net/b/res/789.htm")!
        ))
    }

    func testIsolationRecoveryScriptsUseBoundedBridgePayloads() {
        let monitor = IsolationRecoveryService.sourceThreadMonitorScript
        XCTAssertTrue(monitor.contains("isolationRecoveryCandidate"))
        XCTAssertTrue(monitor.contains("normalized.includes(\"次\")"))
        XCTAssertTrue(monitor.contains("linkLineIndex + 1 < lines.length"))
        XCTAssertTrue(monitor.contains("replace(/\\r\\n?/g, \"\\n\")"))
        XCTAssertTrue(monitor.contains("textContent"))
        XCTAssertTrue(monitor.contains("pollingIntervalMs = 1000"))
        XCTAssertTrue(monitor.contains("maxPollingTicks = 300"))
        XCTAssertTrue(monitor.contains("isolationRecoveryNoCandidate"))
        XCTAssertTrue(monitor.contains("MutationObserver"))
        XCTAssertFalse(monitor.contains("innerHTML"))

        let capture = IsolationRecoveryService.replacementStarterImageCaptureScript
        XCTAssertTrue(capture.contains("isolationRecoveryImage"))
        XCTAssertTrue(capture.contains("canvas.toDataURL"))
        XCTAssertTrue(capture.contains("naturalWidth"))
        XCTAssertFalse(capture.contains("form.submit"))
        XCTAssertFalse(capture.contains("input.files"))
    }

    func testThreadURLParserAcceptsHTTPAndHTTPSOnlyForBoardB() {
        XCTAssertEqual(
            IsolationThreadURLParser.threadID(
                from: URL(string: "http://img.2chan.net/b/res/123.htm")!
            ),
            "123"
        )
        XCTAssertNil(IsolationThreadURLParser.threadID(
            from: URL(string: "https://img.2chan.net/b/futaba.htm")!
        ))
        XCTAssertNil(IsolationThreadURLParser.threadID(
            from: URL(string: "https://example.com/b/res/123.htm")!
        ))
        XCTAssertNil(IsolationThreadURLParser.threadID(
            from: URL(string: "https://img.2chan.net/b/res/123.htmx")!
        ))
    }

    func testIsolationFeedRequestUsesConditionalFriendlyHeaders() {
        let request = IsolationThreadMonitor.makeRequest(
            for: IsolationThreadMonitor.defaultEndpointURL,
            userAgent: "UA test"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"),
                       "text/plain,*/*;q=0.1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "UA test")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
}
