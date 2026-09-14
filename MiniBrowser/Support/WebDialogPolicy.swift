import Foundation

enum TargetPageAlertCategory: String, Equatable {
    case cookieRetryRequired = "COOKIE_RETRY_REQUIRED"
    case imagePostingRestricted = "IMAGE_POSTING_RESTRICTED"
    case accessRestricted = "ACCESS_RESTRICTED"
    case continuousPosting = "CONTINUOUS_POSTING"
    case threadPostingUnavailable = "THREAD_POSTING_UNAVAILABLE"
}

enum TargetPageAlertClassifier {
    private static let targetHost = "img.2chan.net"
    private static let accessRestrictionPattern =
        #"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?はアクセス規制中です$"#

    static func category(host: String?, message: String) -> TargetPageAlertCategory? {
        guard host?.lowercased() == targetHost else { return nil }

        let normalized = message
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        if normalized == "cookieを有効にしてもう一度送信してください" {
            return .cookieRetryRequired
        }
        if normalized == "あなたのipアドレスからは画像を投稿できません" {
            return .imagePostingRestricted
        }
        if normalized.range(of: accessRestrictionPattern,
                            options: .regularExpression) != nil {
            return .accessRestricted
        }
        if normalized == "連続投稿はもうしばらく時間を置いてからお願い致します。" {
            return .continuousPosting
        }
        if normalized == "このスレッドには書けません" {
            return .threadPostingUnavailable
        }
        return nil
    }
}

enum WebDialogPolicy {
    static func shouldAutoDismissAlert(host: String?, message: String) -> Bool {
        // Site-side errors, including the target page's Cookie error, must
        // remain visible so the user can diagnose the current state.
        _ = host
        _ = message
        return false
    }
}
