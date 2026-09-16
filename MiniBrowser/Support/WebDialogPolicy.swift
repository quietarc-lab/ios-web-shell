import Foundation

enum TargetPageAlertCategory: String, Equatable {
    case cookieRetryRequired = "COOKIE_RETRY_REQUIRED"
    case imagePostingRestricted = "IMAGE_POSTING_RESTRICTED"
    case accessRestricted = "ACCESS_RESTRICTED"
    case continuousPosting = "CONTINUOUS_POSTING"
    case imageContinuousPosting = "IMAGE_CONTINUOUS_POSTING"
    case threadPostingUnavailable = "THREAD_POSTING_UNAVAILABLE"
    case imageCountRestricted = "IMAGE_COUNT_RESTRICTED"
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
        // Some target pages omit 「もう」 and/or the final punctuation. Keep
        // those observed exact variants on the same continuous-posting path;
        // embellished or otherwise similar text must remain unknown.
        if normalized == "連続投稿はもうしばらく時間を置いてからお願い致します。" ||
            normalized == "連続投稿はしばらく時間を置いてからお願い致します" ||
            normalized == "連続投稿はしばらく時間を置いてからお願い致します。" {
            return .continuousPosting
        }
        // The image-posting form uses a distinct, exact wording for the same
        // continuous-posting limit. Keep both observed punctuation variants
        // explicit so nearby or embellished messages remain unknown alerts.
        if normalized == "画像連続投稿はもうしばらく時間を置いてからお願い致します" ||
            normalized == "画像連続投稿はもうしばらく時間を置いてからお願い致します。" {
            return .imageContinuousPosting
        }
        if normalized == "このスレッドには書けません" {
            return .threadPostingUnavailable
        }
        if normalized.range(of: #"^画像の投稿が多すぎます\([0-9]+枚\)[。.]$"#,
                            options: .regularExpression) != nil {
            return .imageCountRestricted
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
