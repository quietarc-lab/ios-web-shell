import XCTest
@testable import MiniBrowser

final class AutomaticUserAgentRotationTests: XCTestCase {
    func testOrderContainsEveryUnrestrictedProfileOnce() {
        let restricted: Set<Int> = [1, 100, 250]
        let order = AutomaticUserAgentRotation.makeOrder(
            catalog: BrowserUserAgent.all,
            restrictedIDs: restricted
        )

        XCTAssertEqual(order.count, BrowserUserAgent.all.count - restricted.count)
        XCTAssertEqual(Set(order).count, order.count)
        XCTAssertFalse(order.contains { restricted.contains(BrowserUserAgent.all[$0].id) })
    }

    func testOrderPrefersDifferentBrowserAndDeviceFamilies() {
        let order = AutomaticUserAgentRotation.makeOrder(
            catalog: BrowserUserAgent.all,
            restrictedIDs: []
        )
        for pair in zip(order, order.dropFirst()) {
            let previous = BrowserUserAgent.all[pair.0]
            let next = BrowserUserAgent.all[pair.1]
            XCTAssertFalse(previous.browserFamily == next.browserFamily &&
                           previous.deviceFamily == next.deviceFamily)
        }
    }

    func testOrderRelaxesConstraintsWhenOnlyOneFamilyRemains() {
        let safari = BrowserUserAgent.all.filter { $0.browserFamily == "Safari" }
        let order = AutomaticUserAgentRotation.makeOrder(catalog: safari,
                                                          restrictedIDs: [])
        XCTAssertEqual(order.count, safari.count)
        XCTAssertEqual(Set(order).count, safari.count)
        XCTAssertTrue(order.dropFirst().allSatisfy { index in
            BrowserUserAgent.all[index].deviceFamily !=
                BrowserUserAgent.all[order[order.firstIndex(of: index)! - 1]].deviceFamily
        })
    }

    func testOrderIsEmptyWhenAllProfilesAreRestricted() {
        let restricted = Set(BrowserUserAgent.all.map(\.id))
        XCTAssertTrue(AutomaticUserAgentRotation.makeOrder(
            catalog: BrowserUserAgent.all,
            restrictedIDs: restricted
        ).isEmpty)
    }
}
