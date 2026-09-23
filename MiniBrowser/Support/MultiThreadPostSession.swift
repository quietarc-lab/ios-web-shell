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

enum MultiThreadPostPhase: String, CaseIterable, Hashable, Sendable {
    case momentum
    case catalog

    var sort: ThreadListSort {
        switch self {
        case .momentum: .momentum
        case .catalog: .list
        }
    }

    var batchSize: Int {
        switch self {
        case .momentum: 20
        case .catalog: 10
        }
    }

    var phaseLimit: Int {
        switch self {
        case .momentum: 60
        case .catalog: 30
        }
    }

    var next: MultiThreadPostPhase {
        switch self {
        case .momentum: .catalog
        case .catalog: .momentum
        }
    }
}

/// Main-actor boundary used by BrowserViewModel. The compatibility overloads
/// keep lightweight test providers source-compatible while the coordinator can
/// request a specific sort for each alternating batch.
@MainActor
protocol AutomaticCatalogProvider: AnyObject {
    func currentPostSnapshot(limit: Int) -> CatalogPostSnapshot
    func refreshPostSnapshot(excludingIDs: Set<String>, limit: Int) async throws -> CatalogPostSnapshot
    func currentPostSnapshot(sort: ThreadListSort, limit: Int) -> CatalogPostSnapshot
    func refreshPostSnapshot(sort: ThreadListSort,
                             excludingIDs: Set<String>,
                             limit: Int) async throws -> CatalogPostSnapshot
    func beginAutomaticSortDisplay(_ sort: ThreadListSort)
    func endAutomaticSortDisplay()
    func excludeThread(id: String)
    func markThreadRead(id: String)
    func resetOpenHistory()
}

/// Keep existing test and integration providers source-compatible while the
/// coordinator gains the ability to persist a six-hour catalog exclusion and
/// to reflect successful continuous posts in the catalog's read history.
@MainActor
extension AutomaticCatalogProvider {
    func currentPostSnapshot(sort: ThreadListSort,
                             limit: Int) -> CatalogPostSnapshot {
        currentPostSnapshot(limit: limit)
    }

    func refreshPostSnapshot(sort: ThreadListSort,
                             excludingIDs: Set<String>,
                             limit: Int) async throws -> CatalogPostSnapshot {
        try await refreshPostSnapshot(excludingIDs: excludingIDs, limit: limit)
    }

    func beginAutomaticSortDisplay(_ sort: ThreadListSort) {}
    func endAutomaticSortDisplay() {}
    func excludeThread(id: String) {}
    func markThreadRead(id: String) {}
    func resetOpenHistory() {}
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
    var phase: MultiThreadPostPhase
    /// Number of selected targets in the current phase. Selection includes
    /// successful posts and every supported skip disposition.
    var phaseProcessedCount: Int
    var phaseBatchNumber: Int
    var emptyPhases: Set<MultiThreadPostPhase>
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
        self.phase = .momentum
        self.phaseProcessedCount = 0
        self.phaseBatchNumber = 1
        self.emptyPhases = []
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

    var phaseLimitReached: Bool {
        phaseProcessedCount >= phase.phaseLimit
    }

    mutating func recordAcceptedPost() {
        postsSinceUserAgentChange += 1
    }

    mutating func resetUserAgentPostCount() {
        postsSinceUserAgentChange = 0
    }

    mutating func markCurrentProcessed() {
        guard let target = currentTarget else { return }
        guard processedThreadIDs.insert(target.id).inserted else { return }
        phaseProcessedCount += 1
    }

    /// Marks the currently selected target once. A target is selected before
    /// navigation/availability checks, so a later skip cannot consume a
    /// second phase slot.
    mutating func selectCurrentTarget() {
        markCurrentProcessed()
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

    mutating func replaceSnapshot(with refreshed: CatalogPostSnapshot) {
        snapshot = CatalogPostSnapshot(sort: phase.sort,
                                       targets: refreshed.targets.filter {
                                           !processedThreadIDs.contains($0.id) &&
                                           !retainedPostThreadIDs.contains($0.id)
                                       })
        currentIndex = 0
        currentTargetID = snapshot.targets.first?.id
        continuousRestrictionHandoffUsed = false
        phaseBatchNumber += 1
    }

    mutating func switchToNextPhase() {
        phase = phase.next
        phaseProcessedCount = 0
        phaseBatchNumber = 0
        currentIndex = 0
        currentTargetID = nil
        snapshot = CatalogPostSnapshot(sort: phase.sort, targets: [])
        continuousRestrictionHandoffUsed = false
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
