import Foundation

enum ThreadListError: Error {
    case invalidResponse
    case decodingFailed
    case listParseFailed
    case openerParseFailed
}

actor ThreadListService {
    private let session: URLSession
    private var userAgent: String
    private var openerCache: [String: String] = [:]
    private var thumbnailCache: [URL: Data] = [:]

    init(session: URLSession? = nil,
         userAgent: String = BrowserUserAgent.all[0].value) {
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
        self.userAgent = userAgent
    }

    func updateUserAgent(_ value: String) {
        userAgent = value
    }

    func fetchList(sort: ThreadListSort,
                   limit: Int = 60,
                   excludingIDs: Set<String> = []) async throws -> [ThreadListItem] {
        let request = Self.makeListRequest(for: sort.url, userAgent: userAgent)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw ThreadListError.invalidResponse
        }
        guard let html = Self.decodeShiftJIS(data) else {
            throw ThreadListError.decodingFailed
        }
        let items = Self.parseListHTML(html,
                                       baseURL: sort.url,
                                       limit: limit,
                                       excludingIDs: excludingIDs)
        let hasCatalogTable = html.range(
            of: #"<table\b[^>]*\bid\s*=\s*['\"]cattable['\"]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        guard !items.isEmpty || hasCatalogTable else {
            throw ThreadListError.listParseFailed
        }
        return items
    }

    func openerText(for item: ThreadListItem) async throws -> String {
        if let cached = openerCache[item.id] {
            return cached
        }

        let request = Self.makeOpenerRequest(for: item.threadURL, userAgent: userAgent)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206 else {
            throw ThreadListError.invalidResponse
        }
        guard let html = Self.decodeShiftJIS(data) else {
            throw ThreadListError.decodingFailed
        }
        guard let text = Self.parseOpenerHTML(html) else {
            throw ThreadListError.openerParseFailed
        }
        openerCache[item.id] = text
        return text
    }

    func thumbnailData(for item: ThreadListItem,
                       referer: URL) async throws -> Data {
        if let cached = thumbnailCache[item.thumbnailURL] {
            return cached
        }

        var lastError: Error = ThreadListError.invalidResponse
        for attempt in 0..<2 {
            do {
                let request = Self.makeThumbnailRequest(for: item.thumbnailURL,
                                                        referer: referer,
                                                        userAgent: userAgent)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      !data.isEmpty,
                      http.value(forHTTPHeaderField: "Content-Type")?
                        .lowercased().hasPrefix("image/") == true else {
                    throw ThreadListError.invalidResponse
                }
                thumbnailCache[item.thumbnailURL] = data
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0 {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw lastError
    }

    nonisolated static func makeListRequest(for url: URL,
                                            userAgent: String = BrowserUserAgent.all[0].value) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated static func makeOpenerRequest(for url: URL,
                                              userAgent: String = BrowserUserAgent.all[0].value) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated static func makeThumbnailRequest(for url: URL,
                                                 referer: URL,
                                                 userAgent: String = BrowserUserAgent.all[0].value) -> URLRequest {
        var request = URLRequest(url: url)
        // List thumbnails are only 32 px in the UI. A shorter deadline keeps a
        // stalled image from holding up every later cell until the next refresh.
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated static func decodeShiftJIS(_ data: Data) -> String? {
        if let decoded = String(data: data, encoding: .shiftJIS) {
            return decoded
        }
        for count in 1...2 where data.count > count {
            if let decoded = String(data: Data(data.dropLast(count)), encoding: .shiftJIS) {
                return decoded
            }
        }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func parseListHTML(_ html: String,
                                             baseURL: URL,
                                             limit: Int = 60,
                                             excludingIDs: Set<String> = []) -> [ThreadListItem] {
        guard limit > 0,
              let tableRange = html.range(
                of: #"<table\b[^>]*\bid\s*=\s*['\"]cattable['\"][^>]*>([\s\S]*?)</table>"#,
                options: [.regularExpression, .caseInsensitive]
              ) else { return [] }

        let table = String(html[tableRange])
        let cellPattern = #"<td\b[^>]*>(.*?)</td>"#
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern,
                                                       options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsTable = table as NSString
        let cells = cellRegex.matches(in: table, range: NSRange(location: 0, length: nsTable.length))
        var items: [ThreadListItem] = []

        for cellMatch in cells {
            guard items.count < limit else { break }
            guard cellMatch.numberOfRanges > 1 else { continue }
            let cell = nsTable.substring(with: cellMatch.range(at: 1))
            guard let href = firstCapture(in: cell,
                                          pattern: #"href\s*=\s*['\"]([^'\"]*res/(\d+)\.htm)['\"]"#,
                                          index: 1),
                  let id = firstCapture(in: cell,
                                        pattern: #"href\s*=\s*['\"][^'\"]*res/(\d+)\.htm['\"]"#,
                                        index: 1),
                  !excludingIDs.contains(id),
                  let source = firstCapture(in: cell,
                                            pattern: #"<img\b[^>]*\bsrc\s*=\s*['\"]([^'\"]+)['\"]"#,
                                            index: 1),
                  let threadURL = resolvedHTTPSURL(href, relativeTo: baseURL),
                  let thumbnailURL = resolvedHTTPSURL(source, relativeTo: baseURL) else {
                continue
            }
            let replyText = firstCapture(in: cell,
                                         pattern: #"<font\b[^>]*>\s*(\d+)\s*</font>"#,
                                         index: 1)
            let replyCount = Int(replyText ?? "") ?? 0
            // 1000-reply threads cannot receive further replies. They are not
            // useful in the compact thread picker and consume a list slot.
            guard replyCount < 1_000 else { continue }
            items.append(ThreadListItem(id: id,
                                           threadURL: threadURL,
                                           thumbnailURL: thumbnailURL,
                                           replyCount: replyCount,
                                           thumbnailData: nil,
                                           openerText: nil))
        }
        return items
    }

    nonisolated static func parseOpenerHTML(_ html: String) -> String? {
        guard let threadStart = html.range(
            of: #"<div\b[^>]*\bclass\s*=\s*['\"][^'\"]*\bthre\b[^'\"]*['\"][^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let threadHTML = String(html[threadStart.lowerBound...])
        guard let body = firstCapture(in: threadHTML,
                                      pattern: #"<blockquote\b[^>]*>(.*?)</blockquote>"#,
                                      index: 1) else {
            return nil
        }

        var text = body.replacingOccurrences(of: #"<br\s*/?>"#,
                                             with: "\n",
                                             options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#,
                                         with: "",
                                         options: .regularExpression)
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: #"\s+"#,
                                         with: " ",
                                         options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "本文なし" : text
    }

    private nonisolated static func firstCapture(in source: String,
                                                 pattern: String,
                                                 index: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound else {
            return nil
        }
        return nsSource.substring(with: match.range(at: index))
    }

    private nonisolated static func resolvedHTTPSURL(_ value: String,
                                                     relativeTo baseURL: URL) -> URL? {
        guard let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        guard components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "img.2chan.net" else {
            return nil
        }
        return components.url
    }

    private nonisolated static func decodeHTMLEntities(_ source: String) -> String {
        var result = source
        let numericPattern = #"&#(x[0-9a-fA-F]+|\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result,
                                        range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let wholeRange = Range(match.range(at: 0), in: result),
                      let valueRange = Range(match.range(at: 1), in: result) else { continue }
                let raw = String(result[valueRange])
                let number = raw.lowercased().hasPrefix("x")
                    ? UInt32(raw.dropFirst(), radix: 16)
                    : UInt32(raw, radix: 10)
                if let number, let scalar = UnicodeScalar(number) {
                    result.replaceSubrange(wholeRange, with: String(Character(scalar)))
                }
            }
        }
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")
        ] {
            result = result.replacingOccurrences(of: entity,
                                                 with: replacement,
                                                 options: .caseInsensitive)
        }
        return result
    }
}
