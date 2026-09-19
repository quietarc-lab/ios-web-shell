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

    func testSnapshotCanExcludeThreadIDsRetainedInPostBody() {
        let targets = (1...3).map { id in
            CatalogPostTarget(
                id: String(id),
                threadURL: URL(string: "https://img.2chan.net/b/res/\(id).htm")!
            )
        }
        let snapshot = CatalogPostSnapshot(sort: .momentum, targets: targets)

        XCTAssertEqual(
            snapshot.excludingThreadIDs(["2"]).targets.map(\.id),
            ["1", "3"]
        )
        XCTAssertEqual(snapshot.excludingThreadIDs([]), snapshot)
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

    func testRefreshedSnapshotDoesNotReintroduceRetainedPostThreadIDs() {
        let first = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        let retained = CatalogPostTarget(
            id: "2",
            threadURL: URL(string: "https://img.2chan.net/b/res/2.htm")!
        )
        let newTarget = CatalogPostTarget(
            id: "3",
            threadURL: URL(string: "https://img.2chan.net/b/res/3.htm")!
        )
        var session = MultiThreadPostSession(
            sessionID: 1,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: [first]),
            comment: "https://img.2chan.net/b/res/2.htm",
            hasImage: false,
            retainedPostThreadIDs: ["2"]
        )

        session.appendUnprocessedTargets(from: CatalogPostSnapshot(
            sort: .momentum,
            targets: [retained, newTarget]
        ))

        XCTAssertEqual(session.snapshot.targets.map(\.id), ["1", "3"])
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

    func testPhaseBatchSizingAndAlternation() {
        XCTAssertEqual(MultiThreadPostPhase.momentum.batchSize, 20)
        XCTAssertEqual(MultiThreadPostPhase.momentum.phaseLimit, 60)
        XCTAssertEqual(MultiThreadPostPhase.catalog.batchSize, 10)
        XCTAssertEqual(MultiThreadPostPhase.catalog.phaseLimit, 30)
        XCTAssertEqual(MultiThreadPostPhase.momentum.next, .catalog)
        XCTAssertEqual(MultiThreadPostPhase.catalog.next, .momentum)
    }

    func testSelectingTargetCountsOnceAndReplacingBatchResetsCursor() {
        let first = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        let second = CatalogPostTarget(
            id: "2",
            threadURL: URL(string: "https://img.2chan.net/b/res/2.htm")!
        )
        var session = MultiThreadPostSession(
            sessionID: 4,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: [first]),
            comment: nil,
            hasImage: false
        )
        session.selectCurrentTarget()
        session.selectCurrentTarget()
        XCTAssertEqual(session.phaseProcessedCount, 1)

        session.replaceSnapshot(with: CatalogPostSnapshot(
            sort: .momentum,
            targets: [second]
        ))
        XCTAssertEqual(session.currentTarget?.id, "2")
        XCTAssertEqual(session.phaseBatchNumber, 2)
        XCTAssertEqual(session.advanceToNextUnprocessed(), nil)
        session.selectCurrentTarget()
        XCTAssertEqual(session.phaseProcessedCount, 2)
    }

    func testSwitchingPhaseResetsPhaseCountAndBatch() {
        let target = CatalogPostTarget(
            id: "1",
            threadURL: URL(string: "https://img.2chan.net/b/res/1.htm")!
        )
        var session = MultiThreadPostSession(
            sessionID: 5,
            snapshot: CatalogPostSnapshot(sort: .momentum, targets: [target]),
            comment: nil,
            hasImage: false
        )
        session.selectCurrentTarget()
        session.switchToNextPhase()
        XCTAssertEqual(session.phase, .catalog)
        XCTAssertEqual(session.phaseProcessedCount, 0)
        XCTAssertEqual(session.phaseBatchNumber, 0)
        XCTAssertNil(session.currentTarget)
    }
}
