import Foundation

/// A lightweight catalog entry retained by a multi-thread posting session.
/// Display-only fields (thumbnail and opener text) deliberately stay out of
/// the session so the draft remains the only content held in memory.
struct CatalogPostTarget: Identifiable, Equatable, Sendable {
    let id: String
    let threadURL: URL
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
}

/// Main-actor boundary used by BrowserViewModel. Keeping this as a small
/// protocol lets the browser coordinate a one-shot refresh without coupling
/// its posting state machine to catalog cell presentation state.
@MainActor
protocol AutomaticCatalogProvider: AnyObject {
    func currentPostSnapshot(limit: Int) -> CatalogPostSnapshot
    func refreshPostSnapshot(excludingIDs: Set<String>, limit: Int) async throws -> CatalogPostSnapshot
}

/// Session state is intentionally independent from a page-level generation.
/// A UA handoff or a navigation creates a new generation while this value
/// keeps the target order and in-memory draft intact.
struct MultiThreadPostSession: Equatable, Sendable {
    let sessionID: UInt64
    var snapshot: CatalogPostSnapshot
    var currentIndex: Int
    var processedThreadIDs: Set<String>
    let comment: String?
    let hasImage: Bool
    var catalogRefreshUsed: Bool
    var stopRequested: Bool
    var currentGenerationID: UInt64?
    var currentTargetID: String?

    init(sessionID: UInt64,
         snapshot: CatalogPostSnapshot,
         comment: String?,
         hasImage: Bool) {
        self.sessionID = sessionID
        self.snapshot = snapshot
        self.currentIndex = 0
        self.processedThreadIDs = []
        self.comment = comment?.isEmpty == false ? comment : nil
        self.hasImage = hasImage
        self.catalogRefreshUsed = false
        self.stopRequested = false
        self.currentGenerationID = nil
        self.currentTargetID = snapshot.targets.first?.id
    }

    var currentTarget: CatalogPostTarget? {
        guard snapshot.targets.indices.contains(currentIndex) else { return nil }
        return snapshot.targets[currentIndex]
    }

    var unprocessedTargets: [CatalogPostTarget] {
        snapshot.targets.filter { !processedThreadIDs.contains($0.id) }
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
                return target
            }
            index += 1
        }
        return nil
    }

    mutating func appendUnprocessedTargets(from refreshed: CatalogPostSnapshot) {
        let existing = Set(snapshot.targets.map(\.id))
        let additions = refreshed.targets.filter {
            !existing.contains($0.id) && !processedThreadIDs.contains($0.id)
        }
        guard !additions.isEmpty else { return }
        snapshot = CatalogPostSnapshot(sort: snapshot.sort,
                                       targets: snapshot.targets + additions)
    }
}
