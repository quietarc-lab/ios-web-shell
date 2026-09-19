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
        let catalog = [
            BrowserUserAgent(id: 1,
                             name: "Safari iPhone",
                             value: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7)"),
            BrowserUserAgent(id: 2,
                             name: "Chrome iPad",
                             value: "Mozilla/5.0 (iPad; CPU OS 18_7)")
        ]
        let order = AutomaticUserAgentRotation.makeOrder(
            catalog: catalog,
            restrictedIDs: []
        )
        XCTAssertEqual(order.count, catalog.count)
        let previous = catalog[order[0]]
        let next = catalog[order[1]]
        XCTAssertNotEqual(previous.browserFamily, next.browserFamily)
        XCTAssertNotEqual(previous.deviceFamily, next.deviceFamily)
    }

    func testOrderRelaxesConstraintsWhenOnlyOneFamilyRemains() {
        let safari = BrowserUserAgent.all.filter { $0.browserFamily == "Safari" }
        let order = AutomaticUserAgentRotation.makeOrder(catalog: safari,
                                                          restrictedIDs: [])
        XCTAssertEqual(order.count, safari.count)
        XCTAssertEqual(Set(order).count, safari.count)
        XCTAssertTrue(order.dropFirst().allSatisfy { index in
            let previousIndex = order[order.firstIndex(of: index)! - 1]
            return safari[index].deviceFamily != safari[previousIndex].deviceFamily
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
