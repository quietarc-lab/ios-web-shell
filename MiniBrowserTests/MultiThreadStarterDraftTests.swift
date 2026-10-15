import Foundation
import XCTest
@testable import MiniBrowser

final class MultiThreadStarterDraftTests: XCTestCase {
    func testSourceAcceptsTrimmedHTTPAndHTTPSBoardBURLs() throws {
        let https = try XCTUnwrap(
            MultiThreadStarterDraft.source(
                from: "\n https://img.2chan.net/b/res/123.htm \n"
            )
        )
        XCTAssertEqual(https.threadID, "123")
        XCTAssertEqual(https.urlText, "https://img.2chan.net/b/res/123.htm")

        let http = try XCTUnwrap(
            MultiThreadStarterDraft.source(
                from: "http://img.2chan.net/b/res/456.htm"
            )
        )
        XCTAssertEqual(http.threadID, "456")
    }

    func testSourceRejectsTextMultipleURLsAttachmentsAndForeignBoards() {
        let invalid = [
            "https://img.2chan.net/b/res/123.htm 追加本文",
            "https://img.2chan.net/b/res/123.htm\nhttps://img.2chan.net/b/res/456.htm",
            "https://img.2chan.net/b/res/123.htm\n[file.jpg]",
            "https://img.2chan.net/b/res/123.htm?guid=on",
            "https://img.2chan.net/b/res/123.htm#post",
            "https://example.com/b/res/123.htm",
            "https://img.2chan.net/c/res/123.htm",
            "https://img.2chan.net/b/res/not-a-number.htm"
        ]
        for comment in invalid {
            XCTAssertNil(MultiThreadStarterDraft.source(from: comment), comment)
        }
    }

    func testAppendingBodyPreservesURLAndLineBreaks() throws {
        let source = try XCTUnwrap(
            MultiThreadStarterDraft.source(
                from: " https://img.2chan.net/b/res/123.htm "
            )
        )
        XCTAssertEqual(
            MultiThreadStarterDraft.appendingBody("\r\n一行目\r\n二行目\r\n", to: source),
            "https://img.2chan.net/b/res/123.htm\n一行目\n二行目"
        )
        XCTAssertNil(MultiThreadStarterDraft.appendingBody("\n  \n", to: source))
    }

    func testAlreadyEnrichedCommentIsNotASecondSource() {
        XCTAssertNil(MultiThreadStarterDraft.source(
            from: "https://img.2chan.net/b/res/123.htm\n本文"
        ))
    }
}
