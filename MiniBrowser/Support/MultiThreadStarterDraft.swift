import Foundation

/// Pure validation and composition helpers for the URL-only multi-thread
/// starter draft. The source draft must remain a single board-B thread URL;
/// enriched comments are therefore never enriched twice.
enum MultiThreadStarterDraft {
    struct Source: Equatable, Sendable {
        let url: URL
        let threadID: String
        let urlText: String
    }

    static func source(from comment: String?) -> Source? {
        guard let comment else { return nil }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
             let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
             components.query == nil,
             components.fragment == nil,
             components.user == nil,
             components.password == nil,
             components.port == nil,
              let threadID = IsolationThreadURLParser.threadID(from: url),
              url.path.range(of: #"^/b/res/\d+\.htm$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Source(url: url, threadID: threadID, urlText: trimmed)
    }

    static func appendingBody(_ body: String, to source: Source) -> String? {
        let normalized = normalizeBody(body)
        guard !normalized.isEmpty else { return nil }
        return "\(source.urlText)\n\(normalized)"
    }

    static func normalizeBody(_ body: String) -> String {
        let lineNormalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = lineNormalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
