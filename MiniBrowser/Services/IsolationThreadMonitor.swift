import Foundation

enum IsolationThreadMonitorError: Error, Equatable {
    case invalidResponse
    case emptyResponse
    case decodingFailed
    case notModifiedWithoutBaseline
}

struct ModerationThreadSnapshot: Equatable, Sendable {
    let isolatedIDs: Set<String>
    let deletedIDs: Set<String>

    static let empty = ModerationThreadSnapshot(isolatedIDs: [], deletedIDs: [])
}

/// Parses the plain-text isolation feed and the Futaba thread links captured
/// in an automatic-post draft. Only exact img.2chan.net/b/res/<id>.htm links
/// are accepted; unrelated URLs and surrounding text are ignored.
enum IsolationThreadURLParser {
    private static let targetHost = "img.2chan.net"
    private static let targetPathPattern = #"^/b/res/(\d+)\.htm$"#
    private static let bodyURLPattern =
        #"(?i)https?://img\.2chan\.net/b/res/(\d+)\.htm(?:[?#][^\s<>"']*)?(?=$|[\s<>"'、。！？,.;:!?\)\]\}])"#

    static func threadID(from url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == targetHost,
              let match = url.path.range(of: targetPathPattern,
                                         options: .regularExpression) else {
            return nil
        }
        let path = String(url.path[match])
        guard let id = path.split(separator: "/").last?
            .split(separator: ".").first.map(String.init),
              !id.isEmpty else {
            return nil
        }
        return id
    }

    static func threadIDs(inPostBody body: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: bodyURLPattern) else {
            return []
        }
        let range = NSRange(body.startIndex..., in: body)
        return Set(regex.matches(in: body, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: body) else {
                return nil
            }
            return String(body[idRange])
        })
    }

    /// Replaces only exact board-B thread URL tokens for one source thread.
    /// Surrounding prose and every other URL are retained byte-for-byte.
    static func replacingThreadURL(inPostBody body: String,
                                   sourceThreadID: String,
                                   with replacementURL: URL) -> String? {
        guard !sourceThreadID.isEmpty,
              let replacementThreadID = threadID(from: replacementURL) else {
            return nil
        }
        guard let regex = try? NSRegularExpression(pattern: bodyURLPattern) else {
            return nil
        }

        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, range: range)
        let replaced = NSMutableString(string: body)
        var didReplace = false
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: body),
                  String(body[idRange]) == sourceThreadID else {
                continue
            }
            let replacement = "https://img.2chan.net/b/res/\(replacementThreadID).htm"
            replaced.replaceCharacters(in: match.range, with: replacement)
            didReplace = true
        }
        return didReplace ? String(replaced) : nil
    }

    /// The Futapo `img_b_isolation.txt` feed stores the thread URL before the
    /// first `<>` separator. The moderation state is field 16 (zero-based
    /// index 15): 2 means isolated and 1 means deleted. Metadata, malformed
    /// rows, unknown state values, and the `<EOF>` terminator are ignored.
    static func moderationSnapshot(inIsolationFeed text: String) -> ModerationThreadSnapshot {
        var isolatedIDs = Set<String>()
        var deletedIDs = Set<String>()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let fields = String(rawLine).components(separatedBy: "<>")
            guard fields.count > 15,
                  let state = Int(fields[15].trimmingCharacters(in: .whitespacesAndNewlines)),
                  state == 1 || state == 2 else {
                continue
            }
            let firstField = fields[0]
            guard let url = URL(string: firstField.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let id = threadID(from: url) else {
                continue
            }
            if state == 2 {
                isolatedIDs.insert(id)
            } else {
                deletedIDs.insert(id)
            }
        }
        return ModerationThreadSnapshot(isolatedIDs: isolatedIDs, deletedIDs: deletedIDs)
    }

    /// Compatibility helper for callers that only need the isolation subset.
    static func threadIDs(inIsolationFeed text: String) -> Set<String> {
        moderationSnapshot(inIsolationFeed: text).isolatedIDs
    }
}

/// Scripts used only during the bounded recovery path after an isolated
/// multi-thread target is detected. They report normalized URLs and a small
/// starter-image data URL; page text and image bytes never enter diagnostics.
enum IsolationRecoveryService {
    static let sourceThreadMonitorScript = PageMarkerNamespace.neutralize(#"""
    (() => {
      "use strict";
      const handler = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.miniBrowserHandwriting;
      if (!handler || window.__pageSessionIsolationRecoveryMonitorInstalled) return;
      window.__pageSessionIsolationRecoveryMonitorInstalled = true;
      const pageToken = typeof window.__miniBrowserPageToken === "string"
        ? window.__miniBrowserPageToken : "";
      const sent = new Set();
      let pollingTicks = 0;
      let timer = null;
      let observer = null;

      const stopMonitoring = () => {
        if (timer !== null) clearInterval(timer);
        if (observer) observer.disconnect();
        timer = null;
        observer = null;
      };

      const reportNoCandidate = () => {
        stopMonitoring();
        handler.postMessage({
          type: "isolationRecoveryNoCandidate",
          pageToken
        });
      };

      const send = url => {
        if (!url || sent.has(url)) return;
        sent.add(url);
        handler.postMessage({
          type: "isolationRecoveryCandidate",
          pageToken,
          threadURL: url
        });
        stopMonitoring();
      };

      const hasImmediatelyPrecedingNextLine = anchor => {
        const linkText = String(anchor.innerText || anchor.textContent || "")
          .replace(/\s+/g, " ").trim();
        if (!linkText) return false;

        let container = anchor.parentElement;
        for (let depth = 0; container && depth < 6; depth += 1) {
          const renderedText = String(container.innerText || "").replace(/\r\n?/g, "\n");
          const lines = renderedText.split("\n");
          const linkLineIndex = lines.findIndex(line => line.includes(linkText));
          if (linkLineIndex > 0) {
            const precedingLine = String(lines[linkLineIndex - 1] || "")
              .trim().replace(/^>\s*/, "");
            if (precedingLine === "次") return true;
          }
          container = container.parentElement;
        }
        return false;
      };

      const inspect = () => {
        const anchors = Array.from(document.querySelectorAll("a[href]"));
        for (const anchor of anchors) {
          let url;
          try { url = new URL(anchor.href, location.href); } catch (_) { continue; }
          if (url.hostname.toLowerCase() !== "img.2chan.net" ||
              !/^\/b\/res\/\d+\.htm$/.test(url.pathname)) continue;
          if (hasImmediatelyPrecedingNextLine(anchor)) {
            send(url.origin + url.pathname + url.search + url.hash);
            return;
          }
        }
      };

      observer = new MutationObserver(inspect);
      observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
      timer = setInterval(() => {
        inspect();
        pollingTicks += 1;
        if (pollingTicks >= 240) reportNoCandidate();
      }, 500);
      inspect();
    })();
    """#)

    static let replacementStarterImageCaptureScript = PageMarkerNamespace.neutralize(#"""
    (() => {
      "use strict";
      const handler = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.miniBrowserHandwriting;
      if (!handler || window.__pageSessionIsolationRecoveryImageCaptureInstalled) return;
      window.__pageSessionIsolationRecoveryImageCaptureInstalled = true;
      const pageToken = typeof window.__miniBrowserPageToken === "string"
        ? window.__miniBrowserPageToken : "";
      let attempts = 0;
      const finish = (ready, dataURL) => {
        handler.postMessage({
          type: "isolationRecoveryImage",
          pageToken,
          ready: Boolean(ready),
          dataURL: typeof dataURL === "string" ? dataURL : ""
        });
      };
      const capture = () => {
        attempts += 1;
        const image = document.querySelector("#minibrowser-targetpage-starter img");
        if (!(image instanceof HTMLImageElement) ||
            !image.complete || image.naturalWidth <= 0 || image.naturalHeight <= 0) {
          if (attempts < 100) setTimeout(capture, 100);
          else finish(false, "");
          return;
        }
        try {
          const scale = Math.min(1, 400 / Math.max(image.naturalWidth, image.naturalHeight));
          const canvas = document.createElement("canvas");
          canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
          canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
          const context = canvas.getContext("2d");
          if (!context) { finish(false, ""); return; }
          context.drawImage(image, 0, 0, canvas.width, canvas.height);
          finish(true, canvas.toDataURL("image/jpeg", 0.82));
        } catch (_) {
          finish(false, "");
        }
      };
      capture();
    })();
    """#)
}

/// Native, conditional-GET access to Futapo's img_b isolation feed. The
/// monitor deliberately exposes only normalized thread IDs to the caller and
/// never stores or logs the feed contents.
actor IsolationThreadMonitor {
    static let defaultEndpointURL = URL(
        string: "https://futapo.futakuro.com/data/img_b_isolation.txt"
    )!

    private let session: URLSession
    private let endpointURL: URL
    private var entityTag: String?
    private var lastModified: String?
    private var lastSuccessfulSnapshot: ModerationThreadSnapshot?

    init(session: URLSession? = nil,
         endpointURL: URL = IsolationThreadMonitor.defaultEndpointURL) {
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.endpointURL = endpointURL
    }

    func fetchModerationSnapshot(userAgent: String) async throws -> ModerationThreadSnapshot {
        var request = Self.makeRequest(for: endpointURL, userAgent: userAgent)
        if let entityTag {
            request.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IsolationThreadMonitorError.invalidResponse
        }

        if http.statusCode == 304 {
            guard let lastSuccessfulSnapshot else {
                throw IsolationThreadMonitorError.notModifiedWithoutBaseline
            }
            return lastSuccessfulSnapshot
        }

        guard http.statusCode == 200 else {
            throw IsolationThreadMonitorError.invalidResponse
        }
        guard !data.isEmpty else {
            throw IsolationThreadMonitorError.emptyResponse
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS) else {
            throw IsolationThreadMonitorError.decodingFailed
        }
        // A successful HTTP status alone is not enough: a captive portal or
        // edge error page can also be returned as 200. The feed's terminator
        // is a stable structural marker; retain the previous valid snapshot
        // instead of clearing it when that marker is absent.
        guard text.contains("<EOF>") else {
            throw IsolationThreadMonitorError.decodingFailed
        }

        let snapshot = IsolationThreadURLParser.moderationSnapshot(inIsolationFeed: text)
        entityTag = http.value(forHTTPHeaderField: "ETag")
        lastModified = http.value(forHTTPHeaderField: "Last-Modified")
        lastSuccessfulSnapshot = snapshot
        return snapshot
    }

    func fetchIsolatedThreadIDs(userAgent: String) async throws -> Set<String> {
        let snapshot = try await fetchModerationSnapshot(userAgent: userAgent)
        return snapshot.isolatedIDs
    }

    nonisolated static func makeRequest(for url: URL,
                                        userAgent: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
