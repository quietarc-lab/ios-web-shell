import XCTest
@testable import MiniBrowser

final class MultiThreadPostSessionTests: XCTestCase {
    func testSnapshotDeduplicatesTargetsAndPreservesCatalogOrder() {
        let first = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        let second = CatalogPostTarget(
            id: "2",
            threadURL: URL(string: "https://img.2chan.net/b/res/2.htm")!
        )
        let snapshot = CatalogPostSnapshot(sort: .momentum,
                                           targets: [first, second, first])
        XCTAssertEqual(snapshot.targets.map(\.id), ["1", "2"])
    }

    func testSessionAdvancesOnlyToUnprocessedTargets() {
        let targets = (1...3).map { id in
            CatalogPostTarget(
                id: String(id),
                threadURL: URL(string: "https://img.2chan.net/b/res/\(id).htm")!
            )
        }
        var session = MultiThreadPostSession(
            sessionID: 9,
            snapshot: CatalogPostSnapshot(sort: .list, targets: targets),
            comment: "draft",
            hasImage: true
        )
        session.markCurrentProcessed()
        XCTAssertEqual(session.advanceToNextUnprocessed()?.id, "2")
        session.markCurrentProcessed()
        XCTAssertEqual(session.advanceToNextUnprocessed()?.id, "3")
        session.markCurrentProcessed()
        XCTAssertNil(session.advanceToNextUnprocessed())
    }

    func testRefreshedSnapshotAddsOnlyNewUnprocessedIDs() {
        let first = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        let second = CatalogPostTarget(
            id: "2",
            threadURL: URL(string: "https://img.2chan.net/b/res/2.htm")!
        )
        var session = MultiThreadPostSession(
            sessionID: 1,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: [first]),
            comment: nil,
            hasImage: true
        )
        session.markCurrentProcessed()
        session.appendUnprocessedTargets(from: CatalogPostSnapshot(
            sort: .momentum,
            targets: [first, second]
        ))
        XCTAssertEqual(session.snapshot.targets.map(\.id), ["1", "2"])
        XCTAssertEqual(session.advanceToNextUnprocessed()?.id, "2")
    }

    func testTwoAcceptedPostsRequestUserAgentRotationAndSkippedTargetsDoNotCount() {
        let target = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        var session = MultiThreadPostSession(
            sessionID: 2,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: [target]),
            comment: nil,
            hasImage: true
        )

        XCTAssertFalse(session.shouldRotateUserAgent)
        XCTAssertEqual(MultiThreadPostSession.userAgentPostBatchLimit, 2)
        session.markCurrentProcessed()
        XCTAssertEqual(session.postsSinceUserAgentChange, 0)
        session.recordAcceptedPost()
        XCTAssertFalse(session.shouldRotateUserAgent)
        session.recordAcceptedPost()
        XCTAssertTrue(session.shouldRotateUserAgent)

        session.resetUserAgentPostCount()
        XCTAssertFalse(session.shouldRotateUserAgent)
    }

    func testCatalogTargetRetainsReplyCountForStaleCompletedEntries() {
        let target = CatalogPostTarget(
            id: "1000",
            threadURL: URL(string: "https://img.2chan.net/b/res/1000.htm")!,
            replyCount: 1_000
        )

        XCTAssertTrue(target.isReplyLimitReached)
        XCTAssertEqual(target.replyCount, 1_000)
    }

    func testContinuousRestrictionHandoffIsPerTargetAndResetsOnAdvance() {
        let targets = (1...2).map { id in
            CatalogPostTarget(
                id: String(id),
                threadURL: URL(string: "https://img.2chan.net/b/res/\(id).htm")!
            )
        }
        var session = MultiThreadPostSession(
            sessionID: 3,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: targets),
            comment: "draft",
            hasImage: false
        )

        XCTAssertFalse(session.continuousRestrictionHandoffUsed)
        session.continuousRestrictionHandoffUsed = true
        session.markCurrentProcessed()
        XCTAssertEqual(session.advanceToNextUnprocessed()?.id, "2")
        XCTAssertFalse(session.continuousRestrictionHandoffUsed)
    }
}
