import Foundation

/// Values recorded for the automatic cellular-reconnect diagnostics.
///
/// Callback query values are external input. Keep them bounded to a small
/// allow-list so the debug log never receives arbitrary Shortcut payloads.
enum AutomaticAPDiagnostic {
    static func callbackStatus(_ rawValue: String?) -> String {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "success":
            return "SUCCESS"
        case "cancel", "cancelled", "canceled":
            return "CANCEL"
        case "error", "failure", "failed":
            return "ERROR"
        case nil, "":
            return "SUCCESS_DEFAULT"
        default:
            return "OTHER"
        }
    }

    static func errorCode(_ rawValue: String?) -> String {
        guard let rawValue,
              let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-999_999...999_999).contains(value) else {
            return "UNAVAILABLE"
        }
        return String(value)
    }

    static func errorMessagePresent(_ rawValue: String?) -> String {
        guard let rawValue else { return "NO" }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "NO" : "YES"
    }
}
