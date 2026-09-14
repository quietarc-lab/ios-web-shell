import Foundation
import XCTest
@testable import MiniBrowser

@MainActor
final class BrowserViewModelTests: XCTestCase {
    func testCatalogReplacementResetsLegacySelectionAndRestrictions() {
        let suiteName = "BrowserViewModelTests.catalogReplacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(49, forKey: "userAgentIndex")
        defaults.set(50, forKey: "userAgentID")
        defaults.set(["50": Date().addingTimeInterval(86_400).timeIntervalSince1970],
                     forKey: "userAgentRestrictionExpiries")

        let model = BrowserViewModel(
            defaults: defaults,
            userAgentGenerator: RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        )

        XCTAssertEqual(model.userAgentButtonTitle, "UA 自動")
        XCTAssertEqual(model.currentUserAgent.id, 1)
        XCTAssertTrue(model.effectiveUserAgent.contains("iPhone"))
        XCTAssertEqual(defaults.integer(forKey: "userAgentIndex"), 0)
        XCTAssertEqual(defaults.integer(forKey: "userAgentID"), 1)
        XCTAssertEqual(defaults.integer(forKey: "userAgentCatalogVersion"),
                       BrowserUserAgent.catalogVersion)
        XCTAssertNil(defaults.object(forKey: "userAgentRestrictionExpiries"))
    }

    func testCurrentCatalogKeepsSelectedProfileAcrossViewModels() {
        let suiteName = "BrowserViewModelTests.catalogPersistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let selectedIndex = 42
        defaults.set(BrowserUserAgent.catalogVersion, forKey: "userAgentCatalogVersion")
        defaults.set(selectedIndex, forKey: "userAgentIndex")
        defaults.set(BrowserUserAgent.all[selectedIndex].id, forKey: "userAgentID")

        let model = BrowserViewModel(
            defaults: defaults,
            userAgentGenerator: RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        )

        XCTAssertEqual(model.userAgentButtonTitle, "UA 自動")
        XCTAssertEqual(model.currentUserAgent.id, BrowserUserAgent.all[selectedIndex].id)
    }

    func testGeneratedLaunchUserAgentRestrictionUsesSaltedKeyWithoutStoringValue() {
        let suiteName = "BrowserViewModelTests.generatedRestriction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(
            defaults: defaults,
            userAgentGenerator: RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        )
        let store = UserAgentRestrictionStore(defaults: defaults)
        let key = store.generatedRestrictionKey(for: model.effectiveUserAgent)
        store.restrict(key)

        let rawEntries = defaults.dictionary(forKey: "userAgentRestrictionExpiries") ?? [:]
        XCTAssertTrue(rawEntries.keys.contains(where: { $0.hasPrefix("generated:") }))
        XCTAssertFalse(rawEntries.keys.contains(model.effectiveUserAgent))
    }

    func testGeneratorFallsBackToUnrestrictedFixedProfile() {
        let suiteName = "BrowserViewModelTests.generatedFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let generator = RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        defaults.set(BrowserUserAgent.catalogVersion, forKey: "userAgentCatalogVersion")
        let candidate = generator.generate(isRestricted: { _ in false })!
        let store = UserAgentRestrictionStore(defaults: defaults)
        store.restrict(store.generatedRestrictionKey(for: candidate.value))

        let model = BrowserViewModel(defaults: defaults, userAgentGenerator: generator)

        XCTAssertEqual(model.userAgentButtonTitle, "UA 1/100")
        XCTAssertEqual(model.effectiveUserAgent, BrowserUserAgent.all[0].value)
    }

    func testSameThreadRepeatStartsOffAndIsNotPersisted() {
        let suiteName = "BrowserViewModelTests.sameThreadRepeat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(
            defaults: defaults,
            userAgentGenerator: RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        )
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

        let model = BrowserViewModel(
            defaults: defaults,
            userAgentGenerator: RuntimeUserAgentGenerator(indexSource: { _ in 0 })
        )
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
