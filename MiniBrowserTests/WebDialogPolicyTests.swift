import XCTest
@testable import MiniBrowser

final class WebDialogPolicyTests: XCTestCase {
    func testSiteAlertsAreNeverAutoDismissed() {
        XCTAssertFalse(WebDialogPolicy.shouldAutoDismissAlert(
            host: "img.2chan.net",
            message: "cookieを有効にしてもう一度送信してください"
        ))
        XCTAssertFalse(WebDialogPolicy.shouldAutoDismissAlert(
            host: "IMG.2CHAN.NET",
            message: "cookieを有効にして\nもう一度送信してください"
        ))
        XCTAssertFalse(WebDialogPolicy.shouldAutoDismissAlert(
            host: "img.2chan.net",
            message: "cookieが無いので投稿できません"
        ))
        XCTAssertFalse(WebDialogPolicy.shouldAutoDismissAlert(
            host: "example.com",
            message: "cookieを有効にしてもう一度送信してください"
        ))
    }

    func testTargetPageAlertClassifierOnlyRecordsKnownTargetErrors() {
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "cookieを有効にして\nもう一度送信してください"
            ),
            .cookieRetryRequired
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "あなたのIPアドレスからは画像を投稿できません"
            ),
            .imagePostingRestricted
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "KD182249032014.au-net.ne.jp はアクセス規制中です"
            ),
            .accessRestricted
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "連続投稿はもうしばらく\n時間を置いてからお願い致します。"
            ),
            .continuousPosting
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "連続投稿はしばらく\n時間を置いてからお願い致します"
            ),
            .continuousPosting
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "連続投稿はしばらく時間を置いてからお願い致します。"
            ),
            .continuousPosting
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "画像連続投稿はもうしばらく\n時間を置いてからお願い致します"
            ),
            .imageContinuousPosting
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "画像連続投稿はもうしばらく時間を置いてからお願い致します。"
            ),
            .imageContinuousPosting
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "このスレッドには\n書けません"
            ),
            .threadPostingUnavailable
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "画像の投稿が多すぎます(11枚)."
            ),
            .imageCountRestricted
        )
        XCTAssertEqual(
            TargetPageAlertClassifier.category(
                host: "img.2chan.net",
                message: "画像の投稿が多すぎます( 11 枚 )。"
            ),
            .imageCountRestricted
        )
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "example.com",
            message: "cookieを有効にしてもう一度送信してください"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "任意のエラー本文"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "cookieを有効にしてもう一度送信してください。"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "あなたのIPアドレスからは画像を投稿できません（再試行）"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "KD182249032014.au-net.ne.jp はアクセス規制中です（再試行）"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "アクセス規制中です"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "example.com",
            message: "連続投稿はもうしばらく時間を置いてからお願い致します。"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "このスレッドには書けません。"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "example.com",
            message: "このスレッドには書けません"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "画像の投稿が多すぎます(11枚). 再試行してください"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "画像連続投稿はもうしばらく時間を置いてからお願い致します（再試行）"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "img.2chan.net",
            message: "連続投稿はしばらく時間を置いてからお願い致します（再試行）"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "example.com",
            message: "画像連続投稿はもうしばらく時間を置いてからお願い致します"
        ))
        XCTAssertNil(TargetPageAlertClassifier.category(
            host: "example.com",
            message: "画像の投稿が多すぎます(11枚)."
        ))
    }
}
