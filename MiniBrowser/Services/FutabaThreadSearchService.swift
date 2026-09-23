import Foundation

enum FutabaThreadSearchError: Error, Equatable {
    case invalidResponse
    case emptyResponse
    case encodingFailed
    case responseParsingFailed
}

struct FutabaSearchThreadCandidate: Equatable, Sendable {
    let threadID: String
    let matchedResponseCount: Int
}

/// Native, non-WebView search access used only by isolated-thread recovery.
/// The service returns parent thread IDs and match counts; it never exposes or
/// stores the searched comments or the raw response document.
actor FutabaThreadSearchService {
    static let defaultEndpointURL = URL(
        string: "https://img.2chan.net/b/futaba.php?guid=on"
    )!
    static let fixedKeyword = "定型 ・ ・"

    private let session: URLSession
    private let endpointURL: URL

    init(session: URLSession? = nil,
         endpointURL: URL = FutabaThreadSearchService.defaultEndpointURL) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.allowsCellularAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            configuration.allowsConstrainedNetworkAccess = true
            self.session = URLSession(configuration: configuration)
        }
        self.endpointURL = endpointURL
    }

    func search(userAgent: String) async throws -> [FutabaSearchThreadCandidate] {
        let request = Self.makeSearchRequest(for: endpointURL,
                                             userAgent: userAgent)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw FutabaThreadSearchError.invalidResponse
        }
        guard !data.isEmpty else {
            throw FutabaThreadSearchError.emptyResponse
        }
        guard let html = String(data: data, encoding: .shiftJIS)
                ?? String(data: data, encoding: .utf8) else {
            throw FutabaThreadSearchError.encodingFailed
        }
        return try Self.parseSearchResponse(html)
    }

    nonisolated static func makeSearchRequest(
        for url: URL = FutabaThreadSearchService.defaultEndpointURL,
        userAgent: String = BrowserUserAgent.all[0].value
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = makeSearchFormBody(keyword: fixedKeyword)
        request.setValue("application/x-www-form-urlencoded; charset=Shift_JIS",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("text/html,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated static func makeSearchFormBody(keyword: String) -> Data? {
        guard let keywordData = keyword.data(using: .shiftJIS) else {
            return nil
        }
        let encodedKeyword = formEncode(keywordData)
        return "mode=search&keyword=\(encodedKeyword)".data(using: .utf8)
    }

    nonisolated static func parseSearchResponse(
        _ html: String
    ) throws -> [FutabaSearchThreadCandidate] {
        guard let objectText = embeddedJSONObject(in: html),
              let data = objectText.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boardCode = root["bbscode"] as? String,
              boardCode.lowercased() == "b" else {
            throw FutabaThreadSearchError.responseParsingFailed
        }
        // Futaba omits `res` entirely when the fixed keyword has no current
        // matches. That is a valid empty search, not a transport/parser
        // failure, so the recovery loop may continue to the next period.
        guard let rawResponses = root["res"] else { return [] }
        guard let responses = rawResponses as? [String: Any] else {
            throw FutabaThreadSearchError.responseParsingFailed
        }

        var counts: [UInt64: Int] = [:]
        for (responseID, rawValue) in responses {
            guard let responseNumber = normalizedThreadNumber(responseID),
                  let response = rawValue as? [String: Any] else {
                continue
            }
            let parentNumber = normalizedThreadNumber(response["resto"]) ?? 0
            let threadNumber = parentNumber > 0 ? parentNumber : responseNumber
            counts[threadNumber, default: 0] += 1
        }

        return counts.keys.sorted().compactMap { number in
            guard let count = counts[number] else { return nil }
            return FutabaSearchThreadCandidate(threadID: String(number),
                                               matchedResponseCount: count)
        }
    }

    /// Applies the recovery ordering rules without retaining search text or
    /// the raw result document. The caller supplies all session-local
    /// exclusions because those sets belong to the posting session.
    nonisolated static func orderedCandidateIDs(
        after sourceID: String,
        candidates: [String],
        excludedIDs: Set<String>,
        moderationExcludedIDs: Set<String>,
        attemptedIDs: Set<String>
    ) -> [String] {
        guard let sourceNumber = UInt64(sourceID) else { return [] }
        var orderedCandidates: [(number: UInt64, id: String)] = []
        for candidateID in Set(candidates) {
            guard let candidateNumber = UInt64(candidateID),
                  candidateNumber > sourceNumber,
                  !excludedIDs.contains(candidateID),
                  !moderationExcludedIDs.contains(candidateID),
                  !attemptedIDs.contains(candidateID) else {
                continue
            }
            orderedCandidates.append((number: candidateNumber, id: candidateID))
        }
        orderedCandidates.sort { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return orderedCandidates.map { $0.1 }
    }

    private nonisolated static func formEncode(_ data: Data) -> String {
        var result = ""
        result.reserveCapacity(data.count * 3)
        for byte in data {
            switch byte {
            case 0x20:
                result.append("+")
            case 0x2A, 0x2D, 0x2E, 0x30...0x39,
                 0x41...0x5A, 0x5F, 0x61...0x7A:
                result.append(contentsOf: String(UnicodeScalar(byte)))
            default:
                result.append(String(format: "%%%02X", byte))
            }
        }
        return result
    }

    private nonisolated static func normalizedThreadNumber(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            let integer = number.uint64Value
            return integer > 0 ? integer : nil
        }
        if let string = value as? String,
           let integer = UInt64(string),
           integer > 0 {
            return integer
        }
        return nil
    }

    private nonisolated static func embeddedJSONObject(in html: String) -> String? {
        guard let marker = html.range(
            of: #"var\s+ret\s*="#,
            options: .regularExpression
        ) else {
            return nil
        }
        var start = marker.upperBound
        while start < html.endIndex,
              html[start].isWhitespace {
            start = html.index(after: start)
        }
        guard start < html.endIndex, html[start] == "{" else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < html.endIndex {
            let character = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(html[start...index])
                }
            }
            index = html.index(after: index)
        }
        return nil
    }
}
