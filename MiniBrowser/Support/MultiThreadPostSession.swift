import Foundation

/// A lightweight catalog entry retained by a multi-thread posting session.
/// Display-only fields (thumbnail and opener text) deliberately stay out of
/// the session so the draft remains the only content held in memory.
struct CatalogPostTarget: Identifiable, Equatable, Sendable {
    let id: String
    let threadURL: URL
    /// Reply count captured with the catalog snapshot. The catalog parser
    /// already omits completed (1,000+ reply) threads, but retaining the
    /// value lets a running session discard a stale snapshot entry safely.
    let replyCount: Int

    init(id: String, threadURL: URL, replyCount: Int = 0) {
        self.id = id
        self.threadURL = threadURL
        self.replyCount = max(0, replyCount)
    }

    var isReplyLimitReached: Bool {
        replyCount >= 1_000
    }
}

struct CatalogPostSnapshot: Equatable, Sendable {
    let sort: ThreadListSort
    let targets: [CatalogPostTarget]

    init(sort: ThreadListSort, targets: [CatalogPostTarget]) {
        self.sort = sort
        var seen = Set<String>()
        self.targets = targets.filter { target in
            guard !target.id.isEmpty, !seen.contains(target.id) else { return false }
            seen.insert(target.id)
            return true
        }
    }

    /// Returns a copy with targets referenced by the retained post body
    /// removed.  The catalog order and sort are preserved so this filtering
    /// can be applied both to the initial snapshot and to the one-shot refresh.
    func excludingThreadIDs(_ excludedIDs: Set<String>) -> CatalogPostSnapshot {
        guard !excludedIDs.isEmpty else { return self }
        return CatalogPostSnapshot(
            sort: sort,
            targets: targets.filter { !excludedIDs.contains($0.id) }
        )
    }
}

/// Main-actor boundary used by BrowserViewModel. Keeping this as a small
/// protocol lets the browser coordinate a one-shot refresh without coupling
/// its posting state machine to catalog cell presentation state.
@MainActor
protocol AutomaticCatalogProvider: AnyObject {
    func currentPostSnapshot(limit: Int) -> CatalogPostSnapshot
    func refreshPostSnapshot(excludingIDs: Set<String>, limit: Int) async throws -> CatalogPostSnapshot
    func excludeThread(id: String)
    func markThreadRead(id: String)
}

/// Keep existing test and integration providers source-compatible while the
/// coordinator gains the ability to persist a six-hour catalog exclusion and
/// to reflect successful continuous posts in the catalog's read history.
@MainActor
extension AutomaticCatalogProvider {
    func excludeThread(id: String) {}
    func markThreadRead(id: String) {}
}

/// Session state is intentionally independent from a page-level generation.
/// A UA handoff or a navigation creates a new generation while this value
/// keeps the target order and in-memory draft intact.
struct MultiThreadPostSession: Equatable, Sendable {
    static let userAgentPostBatchLimit = 2

    let sessionID: UInt64
    var snapshot: CatalogPostSnapshot
    var currentIndex: Int
    var processedThreadIDs: Set<String>
    let comment: String?
    let hasImage: Bool
    /// Thread IDs found in the retained post body. These targets are never
    /// selected by this multi-thread session, including its one-shot refresh.
    let retainedPostThreadIDs: Set<String>
    var catalogRefreshUsed: Bool
    var stopRequested: Bool
    var currentGenerationID: UInt64?
    var currentTargetID: String?
    /// Number of targets whose site completion marker was accepted since the
    /// current UA was selected. Skipped targets do not consume this quota.
    var postsSinceUserAgentChange: Int
    /// A short continuous-posting restriction is allowed one UA handoff for
    /// the current target. If that same target reports the restriction again
    /// under the next UA generation, only the target is skipped and the
    /// session continues with the remaining snapshot.
    var continuousRestrictionHandoffUsed: Bool

    init(sessionID: UInt64,
         snapshot: CatalogPostSnapshot,
         comment: String?,
         hasImage: Bool,
         retainedPostThreadIDs: Set<String> = []) {
        self.sessionID = sessionID
        self.snapshot = snapshot
        self.currentIndex = 0
        self.processedThreadIDs = []
        self.comment = comment?.isEmpty == false ? comment : nil
        self.hasImage = hasImage
        self.retainedPostThreadIDs = retainedPostThreadIDs
        self.catalogRefreshUsed = false
        self.stopRequested = false
        self.currentGenerationID = nil
        self.currentTargetID = snapshot.targets.first?.id
        self.postsSinceUserAgentChange = 0
        self.continuousRestrictionHandoffUsed = false
    }

    var currentTarget: CatalogPostTarget? {
        guard snapshot.targets.indices.contains(currentIndex) else { return nil }
        return snapshot.targets[currentIndex]
    }

    var unprocessedTargets: [CatalogPostTarget] {
        snapshot.targets.filter { !processedThreadIDs.contains($0.id) }
    }

    var shouldRotateUserAgent: Bool {
        postsSinceUserAgentChange >= Self.userAgentPostBatchLimit
    }

    mutating func recordAcceptedPost() {
        postsSinceUserAgentChange += 1
    }

    mutating func resetUserAgentPostCount() {
        postsSinceUserAgentChange = 0
    }

    mutating func markCurrentProcessed() {
        guard let target = currentTarget else { return }
        processedThreadIDs.insert(target.id)
    }

    mutating func advanceToNextUnprocessed() -> CatalogPostTarget? {
        guard !snapshot.targets.isEmpty else { return nil }
        var index = max(0, currentIndex + 1)
        while index < snapshot.targets.count {
            let target = snapshot.targets[index]
            if !processedThreadIDs.contains(target.id) {
                currentIndex = index
                currentTargetID = target.id
                continuousRestrictionHandoffUsed = false
                return target
            }
            index += 1
        }
        return nil
    }

    mutating func appendUnprocessedTargets(from refreshed: CatalogPostSnapshot) {
        let existing = Set(snapshot.targets.map(\.id))
        let additions = refreshed.targets.filter {
            !existing.contains($0.id) &&
            !processedThreadIDs.contains($0.id) &&
            !retainedPostThreadIDs.contains($0.id)
        }
        guard !additions.isEmpty else { return }
        snapshot = CatalogPostSnapshot(sort: snapshot.sort,
                                       targets: snapshot.targets + additions)
    }
}
