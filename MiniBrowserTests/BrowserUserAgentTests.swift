import XCTest
@testable import MiniBrowser

final class BrowserUserAgentTests: XCTestCase {
    func testCatalogContainsUpToThreeHundredStableUniqueMobileProfiles() {
        XCTAssertGreaterThanOrEqual(BrowserUserAgent.all.count, 1)
        XCTAssertLessThanOrEqual(BrowserUserAgent.all.count, 300)
        XCTAssertEqual(BrowserUserAgent.all.map(\.id),
                       Array(1...BrowserUserAgent.all.count))
        XCTAssertEqual(Set(BrowserUserAgent.all.map(\.id)).count,
                       BrowserUserAgent.all.count)
        XCTAssertEqual(Set(BrowserUserAgent.all.map(\.name)).count,
                       BrowserUserAgent.all.count)
        XCTAssertEqual(Set(BrowserUserAgent.all.map(\.value)).count,
                       BrowserUserAgent.all.count)
        XCTAssertTrue(BrowserUserAgent.all.allSatisfy { agent in
            agent.value.hasPrefix("Mozilla/5.0 ") &&
                agent.value.contains("AppleWebKit/605.1.15") &&
                agent.value.contains("Mobile/15E148") &&
                (agent.value.contains("(iPhone;") || agent.value.contains("(iPad;"))
        })
        XCTAssertEqual(BrowserUserAgent.all.prefix(100).map(\.id), Array(1...100))
        XCTAssertEqual(BrowserUserAgent.all.filter { $0.value.contains("(iPhone;") }.count,
                       BrowserUserAgent.all.count / 2)
        XCTAssertEqual(BrowserUserAgent.all.filter { $0.value.contains("(iPad;") }.count,
                       BrowserUserAgent.all.count / 2)
    }

    func testExpandedCatalogHasDocumentedFrozenOSVariants() {
        XCTAssertEqual(BrowserUserAgent.all.count, 300)
        XCTAssertEqual(BrowserUserAgent.all[100].value.contains("iPhone OS 18_6"), true)
        XCTAssertEqual(BrowserUserAgent.all[200].value.contains("iPhone OS 18_6_2"), true)
        XCTAssertEqual(BrowserUserAgent.all[299].value.contains("CPU OS 18_6_2"), true)
    }

    func testCatalogVersionMarksAdditiveExpansion() {
        XCTAssertEqual(BrowserUserAgent.catalogVersion, 3)
    }
}
