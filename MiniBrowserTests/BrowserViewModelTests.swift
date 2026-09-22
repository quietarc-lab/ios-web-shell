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

    func testThreadAvailabilityProbeRequiresEligibleStructuralResult() {
        let available = BrowserViewModel.threadAvailability(from: [
            "eligible": true,
            "hasThread": true,
            "hasForm": true
        ])
        XCTAssertEqual(available?.hasThread, true)
        XCTAssertEqual(available?.hasForm, true)

        let dropped = BrowserViewModel.threadAvailability(from: [
            "eligible": true,
            "hasThread": false,
            "hasForm": false
        ])
        XCTAssertEqual(dropped?.hasThread, false)
        XCTAssertEqual(dropped?.hasForm, false)

        XCTAssertNil(BrowserViewModel.threadAvailability(from: [
            "eligible": false,
            "hasThread": false,
            "hasForm": false
        ]))
        XCTAssertNil(BrowserViewModel.threadAvailability(from: [
            "eligible": true,
            "hasThread": true
        ]))
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
        XCTAssertEqual(BrowserViewModel.sameUserAgentMultiThreadSubmitDelayNanoseconds,
                       500_000_000)
    }

    func testIsolationStopStartsOnAndIsNotPersisted() {
        let suiteName = "BrowserViewModelTests.isolationStopToggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserViewModel(defaults: defaults)
        XCTAssertTrue(model.isolationStopEnabled)

        model.toggleIsolationStop()

        XCTAssertFalse(model.isolationStopEnabled)
        XCTAssertNil(defaults.object(forKey: "isolationStopEnabled"))
    }

    func testModerationStopNoticeUsesReasonSpecificMessages() {
        let isolated = IsolationStopNotice(threadID: "123", mode: "SAME_THREAD")
        XCTAssertEqual(isolated.kind, .isolated)
        XCTAssertEqual(isolated.kind.alertTitle, "隔離検知")
        XCTAssertEqual(isolated.kind.alertMessage,
                       "隔離検知のため自動投稿を停止しました")
        XCTAssertEqual(isolated.kind.automaticStopReason, .isolatedThread)

        let deleted = IsolationStopNotice(threadID: "456",
                                          mode: "MULTI_THREAD",
                                          kind: .deleted)
        XCTAssertEqual(deleted.kind.alertTitle, "削除検知")
        XCTAssertEqual(deleted.kind.alertMessage,
                       "削除検知のため自動投稿を停止しました")
        XCTAssertEqual(deleted.kind.automaticStopReason, .deletedThread)
    }

    func testModerationMatchKeepsIsolationDistinctWhenFeedRowsOverlap() {
        let isolated = BrowserViewModel.moderationMatch(
            targetThreadIDs: ["123", "456"],
            snapshot: ModerationThreadSnapshot(
                isolatedIDs: ["123"],
                deletedIDs: ["123", "456"]
            )
        )
        XCTAssertEqual(isolated?.threadID, "123")
        XCTAssertEqual(isolated?.kind, .isolated)

        let deleted = BrowserViewModel.moderationMatch(
            targetThreadIDs: ["789"],
            snapshot: ModerationThreadSnapshot(
                isolatedIDs: [],
                deletedIDs: ["789"]
            )
        )
        XCTAssertEqual(deleted?.threadID, "789")
        XCTAssertEqual(deleted?.kind, .deleted)

        XCTAssertNil(BrowserViewModel.moderationMatch(
            targetThreadIDs: ["000"],
            snapshot: ModerationThreadSnapshot.empty
        ))
    }

    func testAutomaticFailureStopNoticeUsesPersistentAlertPath() {
        let failure = IsolationStopNotice(
            mode: "SAME_THREAD",
            kind: .automaticFailure(.communicationFailure)
        )

        XCTAssertEqual(failure.kind.alertTitle, "自動投稿停止")
        XCTAssertEqual(failure.kind.alertMessage,
                       "通信に失敗したため自動投稿を停止しました")
        XCTAssertEqual(failure.kind.automaticStopReason, .communicationFailure)
        XCTAssertNil(failure.threadID)
    }

    func testOnlyUnexpectedTerminalStopsRequireUserAlert() {
        XCTAssertTrue(AutomaticPostStopReason.communicationFailure.requiresUserAlert)
        XCTAssertTrue(AutomaticPostStopReason.sceneResumeFailed.requiresUserAlert)
        XCTAssertTrue(AutomaticPostStopReason.unknownAlert.requiresUserAlert)
        XCTAssertFalse(AutomaticPostStopReason.repeatDisabled.requiresUserAlert)
        XCTAssertFalse(AutomaticPostStopReason.threadUnavailable.requiresUserAlert)
        XCTAssertFalse(AutomaticPostStopReason.isolatedThread.requiresUserAlert)
        XCTAssertFalse(AutomaticPostStopReason.deletedThread.requiresUserAlert)
    }

    func testMultiThreadSuccessAndContinuousAPRetryUseOneSecondBuffers() {
        XCTAssertEqual(BrowserViewModel.multiThreadSuccessWaitNanoseconds,
                       1_000_000_000)
        XCTAssertEqual(BrowserViewModel.continuousAPRetryDelayNanoseconds,
                       1_000_000_000)
        XCTAssertEqual(BrowserViewModel.automaticAPCallbackTimeoutNanoseconds,
                       20_000_000_000)
        XCTAssertEqual(AutomaticPostFlowMachine.continuousAPReconnectAttemptLimit, 3)
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
