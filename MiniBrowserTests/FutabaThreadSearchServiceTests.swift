import Foundation
import XCTest
@testable import MiniBrowser

final class FutabaThreadSearchServiceTests: XCTestCase {
    func testSearchRequestUsesExactShiftJISForm() throws {
        let request = FutabaThreadSearchService.makeSearchRequest(
            userAgent: "UA test"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded; charset=Shift_JIS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "UA test")
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
            "mode=search&keyword=%92%E8%8C%5E+%81E+%81E"
        )
    }

    func testParserGroupsRepliesByParentThread() throws {
        let html = #"""
        <script>var ret={"bbscode":"b","res":{
          "1471412468":{"resto":"1471412405","com":"child"},
          "1471412478":{"resto":"1471412405","com":"child2"},
          "1471412500":{"resto":"0","com":"root"},
          "1471412501":{"resto":0,"com":"root2"}
        }};</script>
        """#

        XCTAssertEqual(
            try FutabaThreadSearchService.parseSearchResponse(html),
            [
                FutabaSearchThreadCandidate(threadID: "1471412405",
                                            matchedResponseCount: 2),
                FutabaSearchThreadCandidate(threadID: "1471412500",
                                            matchedResponseCount: 1),
                FutabaSearchThreadCandidate(threadID: "1471412501",
                                            matchedResponseCount: 1)
            ]
        )
    }

    func testParserHandlesBracesAndEscapedQuotesInComments() throws {
        let html = #"var ret={"bbscode":"b","res":{"147":{"resto":"0","com":"} \"quoted\""}}};"#
        XCTAssertEqual(
            try FutabaThreadSearchService.parseSearchResponse(html),
            [FutabaSearchThreadCandidate(threadID: "147", matchedResponseCount: 1)]
        )
    }

    func testParserRejectsWrongBoardAndBrokenJSON() {
        XCTAssertThrowsError(try FutabaThreadSearchService.parseSearchResponse(
            #"var ret={"bbscode":"news","res":{}};"#
        ))
        XCTAssertThrowsError(try FutabaThreadSearchService.parseSearchResponse(
            "var ret={\"bbscode\":\"b\",\"res\":{"
        ))
    }

    func testParserTreatsMissingResultsAsAnEmptySearch() throws {
        XCTAssertEqual(
            try FutabaThreadSearchService.parseSearchResponse(
                #"var ret={"dispname":0,"bbscode":"b"};"#
            ),
            []
        )
    }

    func testCandidateOrderingFiltersSourceAndExcludedIDs() {
        XCTAssertEqual(
            FutabaThreadSearchService.orderedCandidateIDs(
                after: "100",
                candidates: ["99", "102", "101", "101", "103", "bad"],
                excludedIDs: ["101"],
                moderationExcludedIDs: ["103"],
                attemptedIDs: []
            ),
            ["102"]
        )
    }
}
