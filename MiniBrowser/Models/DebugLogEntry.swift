import Foundation

struct DebugLogField: Codable, Equatable {
    let key: String
    let value: String
}

struct DebugLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let action: String
    let fields: [DebugLogField]

    init(id: UUID = UUID(), date: Date = Date(), action: String, fields: [(String, String)]) {
        self.id = id
        self.date = date
        self.action = action
        self.fields = fields.map { DebugLogField(key: $0.0, value: LogSanitizer.text($0.1)) }
    }

    var plainText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var lines = [formatter.string(from: date), "ACTION: \(action)"]
        lines.append(contentsOf: fields.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
    }
}

enum LogSanitizer {
    private static let secretAssignmentPattern = #"(?i)(token|password|passwd|secret|authorization|cookie|session|api[_-]?key)=([^&\s]+)"#
    private static let alertMessageMaximumLength = 512

    static func text(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: secretAssignmentPattern) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value,
                                              range: range,
                                              withTemplate: "$1=[REDACTED]")
    }

    static func alertMessage(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        let sanitized = text(singleLine)
        guard sanitized.count > alertMessageMaximumLength else {
            return sanitized
        }
        return String(sanitized.prefix(alertMessageMaximumLength - 1)) + "…"
    }

    static func url(_ url: URL?) -> String {
        guard let url else { return "(none)" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return text(url.absoluteString)
        }
        components.user = nil
        components.password = nil
        components.queryItems = components.queryItems?.map { item in
            let key = item.name.lowercased()
            let secretFragments = ["token", "password", "passwd", "secret", "auth", "session", "cookie", "key"]
            if secretFragments.contains(where: key.contains) {
                return URLQueryItem(name: item.name, value: "[REDACTED]")
            }
            return item
        }
        return components.string ?? text(url.absoluteString)
    }
}
