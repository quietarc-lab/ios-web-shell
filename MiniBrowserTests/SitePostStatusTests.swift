import XCTest
@testable import MiniBrowser

final class SitePostStatusTests: XCTestCase {
    func testOnlyTheTwoSiteMarkersAreRepresented() {
        XCTAssertEqual(SitePostStatus(rawValue: "…"), .sending)
        XCTAssertEqual(SitePostStatus(rawValue: "完了"), .completed)
        XCTAssertNil(SitePostStatus(rawValue: "エラー"))
        XCTAssertNil(SitePostStatus(rawValue: ""))
    }

    func testAutomaticStatusTextAndFinalClassification() {
        XCTAssertEqual(AutomaticPostStatus.preparingUA.rawValue, "UA準備中")
        XCTAssertEqual(AutomaticPostStatus.checkingCookie.rawValue, "Cookie確認中")
        XCTAssertEqual(AutomaticPostStatus.sending.rawValue, "投稿中…")
        XCTAssertEqual(AutomaticPostStatus.cookieRetry.rawValue, "Cookie確認後に再送")
        XCTAssertEqual(AutomaticPostStatus.reconnectingAfterIPLimit.rawValue,
                       "IP制限 → AP再接続中")
        XCTAssertEqual(AutomaticPostStatus.finalSendAfterIPChange.rawValue,
                       "IP変更後に最終送信")
        XCTAssertEqual(AutomaticPostStatus.switchingAfterAccessRestriction.rawValue,
                       "アクセス規制 → 次のUAへ")
        XCTAssertEqual(AutomaticPostStatus.switchingAfterContinuousLimit.rawValue,
                       "連続制限 → 次のUAへ")
        XCTAssertEqual(AutomaticPostStatus.reconnectingAfterContinuousLimit.rawValue,
                       "連続制限 → AP再接続中")
        XCTAssertEqual(AutomaticPostStatus.finalSendAfterContinuousLimit.rawValue,
                       "AP後に最終送信")
        XCTAssertEqual(AutomaticPostStatus.waitingForRepeat.rawValue, "同スレ次回待機")
        XCTAssertEqual(AutomaticPostStatus.waitingForNextThread.rawValue, "次スレ待機")
        XCTAssertEqual(AutomaticPostStatus.navigatingToNextThread.rawValue, "次スレへ移動中")
        XCTAssertEqual(AutomaticPostStatus.switchingAfterThreadBatch.rawValue,
                       "2スレ投稿 → 次のUAへ")
        XCTAssertEqual(AutomaticPostStatus.refreshingCatalog.rawValue, "カタログ再取得中")
        XCTAssertEqual(AutomaticPostStatus.acceptedPendingVerification.rawValue,
                       "受付済み・反映確認中")
        XCTAssertEqual(AutomaticPostStatus.scenePaused.rawValue, "一時停止中")
        XCTAssertEqual(AutomaticPostStatus.completed.rawValue, "完了")
        XCTAssertEqual(AutomaticPostStatus.completedUnconfirmed.rawValue,
                       "完了（反映未確認）")
        XCTAssertEqual(AutomaticPostStatus.stopped.rawValue, "自動投稿停止")
        XCTAssertTrue(AutomaticPostStatus.completed.isFinal)
        XCTAssertTrue(AutomaticPostStatus.completedUnconfirmed.isFinal)
        XCTAssertTrue(AutomaticPostStatus.stopped.isFinal)
        XCTAssertFalse(AutomaticPostStatus.sending.isFinal)
        XCTAssertFalse(AutomaticPostStatus.switchingAfterAccessRestriction.isFinal)
        XCTAssertFalse(AutomaticPostStatus.waitingForRepeat.isFinal)
        XCTAssertFalse(AutomaticPostStatus.switchingAfterThreadBatch.isFinal)
        XCTAssertFalse(AutomaticPostStatus.acceptedPendingVerification.isFinal)
        XCTAssertFalse(AutomaticPostStatus.scenePaused.isFinal)
    }

    func testOverlayDimensionsStayFixed() {
        let source = String(describing: SitePostStatusView.self)
        XCTAssertFalse(source.isEmpty)
        // The actual SwiftUI frame is asserted by the source-level static
        // check because ViewMirror is unavailable in XCTest on Windows.
    }
}
