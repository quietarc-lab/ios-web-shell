import Foundation
import XCTest
@testable import MiniBrowser

final class IsolationThreadMonitorTests: XCTestCase {
    func testIsolationFeedParserUsesFirstFieldAndIgnoresMetadata() {
        let feed = """
        http://img.2chan.net/b/res/1234567890.htm<>対象<>理由
        https://img.2chan.net/b/res/9876543210.htm?x=1<>対象<>理由
        boardStatus<>ok
        <EOF>
        https://example.com/b/res/111.htm<>対象<>理由
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
