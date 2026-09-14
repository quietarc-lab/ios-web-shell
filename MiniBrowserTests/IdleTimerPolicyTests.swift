import XCTest
@testable import MiniBrowser

final class IdleTimerPolicyTests: XCTestCase {
    func testAutomaticProcessingKeepsIdleTimerDisabledInForeground() {
        XCTAssertTrue(IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: true,
            automaticFlowIsActive: true,
            repeatSessionIsActive: false,
            responseVerificationIsActive: false
        ))
    }

    func testRepeatSessionAndResponseVerificationKeepProcessingAwake() {
        XCTAssertTrue(IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: true,
            automaticFlowIsActive: false,
            repeatSessionIsActive: true,
            responseVerificationIsActive: false
        ))
        XCTAssertTrue(IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: true,
            automaticFlowIsActive: false,
            repeatSessionIsActive: false,
            responseVerificationIsActive: true
        ))
    }

    func testIdleTimerIsEnabledOutsideForegroundOrAutomation() {
        XCTAssertFalse(IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: false,
            automaticFlowIsActive: true,
            repeatSessionIsActive: true,
            responseVerificationIsActive: true
        ))
        XCTAssertFalse(IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: true,
            automaticFlowIsActive: false,
            repeatSessionIsActive: false,
            responseVerificationIsActive: false
        ))
    }
}
