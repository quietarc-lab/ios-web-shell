import Foundation

enum SitePostStatus: String, Equatable {
    case sending = "…"
    case completed = "完了"
}

enum AutomaticPostStatus: String, Equatable {
    case preparingUA = "UA準備中"
    case checkingCookie = "Cookie確認中"
    case sending = "投稿中…"
    case cookieRetry = "Cookie確認後に再送"
    case reconnectingAfterIPLimit = "IP制限 → AP再接続中"
    case finalSendAfterIPChange = "IP変更後に最終送信"
    case switchingAfterAccessRestriction = "アクセス規制 → 次のUAへ"
    case switchingAfterContinuousLimit = "連続制限 → 次のUAへ"
    case reconnectingAfterContinuousLimit = "連続制限 → AP再接続中"
    case finalSendAfterContinuousLimit = "AP後に最終送信"
    case waitingForRepeat = "同スレ次回待機"
    case waitingForNextThread = "次スレ待機"
    case navigatingToNextThread = "次スレへ移動中"
    case switchingAfterThreadBatch = "2スレ投稿 → 次のUAへ"
    case refreshingCatalog = "カタログ再取得中"
    case acceptedPendingVerification = "受付済み・反映確認中"
    case completed = "完了"
    case completedUnconfirmed = "完了（反映未確認）"
    case stopped = "自動投稿停止"

    var isFinal: Bool {
        switch self {
        case .completed, .completedUnconfirmed, .stopped:
            return true
        case .preparingUA, .checkingCookie, .sending, .cookieRetry,
             .reconnectingAfterIPLimit, .finalSendAfterIPChange,
             .switchingAfterAccessRestriction, .switchingAfterContinuousLimit,
             .reconnectingAfterContinuousLimit,
             .finalSendAfterContinuousLimit, .waitingForRepeat,
             .waitingForNextThread, .navigatingToNextThread,
             .switchingAfterThreadBatch, .refreshingCatalog,
             .acceptedPendingVerification:
            return false
        }
    }
}
