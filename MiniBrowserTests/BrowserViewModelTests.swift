import Foundation
import XCTest
@testable import MiniBrowser

@MainActor
final class BrowserViewModelTests: XCTestCase {
    func testCatalogMigrationPreservesSelectionAndRestrictions() {
        let suiteName = "BrowserViewModelTests.catalogMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(49, forKey: "userAgentIndex")
        defaults.set(50, forKey: "userAgentID")
        defaults.set(["60": Date().addingTimeInterval(86_400).timeIntervalSince1970,
                      "generated:legacy": Date().addingTimeInterval(86_400).timeIntervalSince1970],
                     forKey: "userAgentRestrictionExpiries")

        let model = BrowserViewModel(defaults: defaults)

        XCTAssertEqual(model.currentUserAgent.id, 50)
        XCTAssertEqual(model.userAgentButtonTitle, "UA 50/299")
        XCTAssertEqual(model.effectiveUserAgent, BrowserUserAgent.all[49].value)
        XCTAssertEqual(defaults.integer(forKey: "userAgentIndex"), 49)
        XCTAssertEqual(defaults.integer(forKey: "userAgentID"), 50)
        XCTAssertEqual(defaults.integer(forKey: "userAgentCatalogVersion"),
                       BrowserUserAgent.catalogVersion)
        let entries = defaults.dictionary(forKey: "userAgentRestrictionExpiries") ?? [:]
        XCTAssertNotNil(entries["60"])
        XCTAssertNotNil(entries["generated:legacy"])
    }

    func testCurrentCatalogKeepsSelectedProfileAcrossViewModels() {
        let suiteName = "BrowserViewModelTests.catalogPersistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let selectedIndex = 42
        defaults.set(BrowserUserAgent.catalogVersion, forKey: "userAgentCatalogVersion")
        defaults.set(selectedIndex, forKey: "userAgentIndex")
        defaults.set(BrowserUserAgent.all[selectedIndex].id, forKey: "userAgentID")

        let model = BrowserViewModel(defaults: defaults)

        XCTAssertEqual(model.userAgentButtonTitle, "UA 43/300")
        XCTAssertEqual(model.currentUserAgent.id, BrowserUserAgent.all[selectedIndex].id)
    }

    func testFixedCatalogIsUsedAtLaunch() {
        let suiteName = "BrowserViewModelTests.fixedLaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(defaults: defaults)

        XCTAssertEqual(model.userAgentButtonTitle, "UA 1/300")
        XCTAssertEqual(model.effectiveUserAgent, BrowserUserAgent.all[0].value)
    }

    func testLegacyGeneratedRestrictionDoesNotAffectFixedCatalogSelection() {
        let suiteName = "BrowserViewModelTests.legacyGenerated.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserAgentRestrictionStore(defaults: defaults)
        store.restrict(store.generatedRestrictionKey(for: "legacy-value"))
        let model = BrowserViewModel(defaults: defaults)

        XCTAssertEqual(model.userAgentButtonTitle, "UA 1/300")
        XCTAssertEqual(model.effectiveUserAgent, BrowserUserAgent.all[0].value)
    }

    func testMissingSavedIDRepairsIndexAndIDWithoutClearingRestrictions() {
        let suiteName = "BrowserViewModelTests.missingSavedID.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(149, forKey: "userAgentIndex")
        defaults.set(9999, forKey: "userAgentID")
        defaults.set(["250": Date().addingTimeInterval(86_400).timeIntervalSince1970],
                     forKey: "userAgentRestrictionExpiries")

        let model = BrowserViewModel(defaults: defaults)

        XCTAssertEqual(model.currentUserAgent.id, 150)
        XCTAssertEqual(defaults.integer(forKey: "userAgentIndex"), 149)
        XCTAssertEqual(defaults.integer(forKey: "userAgentID"), 150)
        XCTAssertNotNil(defaults.dictionary(forKey: "userAgentRestrictionExpiries")?["250"])
    }

    func testSameThreadRepeatStartsOffAndIsNotPersisted() {
        let suiteName = "BrowserViewModelTests.sameThreadRepeat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(defaults: defaults)
        XCTAssertFalse(model.sameThreadRepeatEnabled)
        model.toggleSameThreadRepeat()
        XCTAssertTrue(model.sameThreadRepeatEnabled)
        XCTAssertNil(defaults.object(forKey: "sameThreadRepeatEnabled"))
    }

    func testSameThreadRepeatUsesShortTimingProfileWithoutChangingRegularDelay() {
        XCTAssertEqual(BrowserViewModel.sameThreadRepeatMinimumDelayNanoseconds,
                       250_000_000)
        XCTAssertEqual(BrowserViewModel.sameThreadRepeatSubmitDelayNanoseconds, 0)
    }

    func testMultiThreadToggleStartsOffIsNotPersistedAndIsExclusive() {
        let suiteName = "BrowserViewModelTests.multiThreadToggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(defaults: defaults)
        XCTAssertFalse(model.multiThreadEnabled)
        XCTAssertFalse(model.multiThreadSessionActive)

        model.toggleMultiThread()
        XCTAssertTrue(model.multiThreadEnabled)
        XCTAssertNil(defaults.object(forKey: "multiThreadEnabled"))

        model.toggleSameThreadRepeat()
        XCTAssertFalse(model.multiThreadEnabled)
        XCTAssertTrue(model.sameThreadRepeatEnabled)
    }
}
