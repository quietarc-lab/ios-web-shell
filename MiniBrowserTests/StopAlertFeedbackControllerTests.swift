import XCTest
@testable import MiniBrowser

@MainActor
final class StopAlertFeedbackControllerTests: XCTestCase {
    func testFeedbackStartsOnceAndStopsCleanly() {
        let controller = StopAlertFeedbackController()

        controller.startIfNeeded()
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.pulseCount, 1)

        controller.startIfNeeded()
        XCTAssertEqual(controller.pulseCount, 1)

        controller.stop()
        XCTAssertFalse(controller.isActive)
        controller.stop()
        XCTAssertFalse(controller.isActive)
    }
}
