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
