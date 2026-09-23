import XCTest
@testable import MiniBrowser

final class AutomaticPostFlowTests: XCTestCase {
    private let generation: UInt64 = 42

    func testPreparationStartsReadinessAfterAllSignals() {
        var machine = AutomaticPostFlowMachine()
        XCTAssertEqual(machine.begin(generationID: generation,
                                     oldPageToken: "old",
                                     hasComment: true,
                                     hasImage: false), .none)

        XCTAssertEqual(machine.handle(.markAPCompleted(generationID: generation)), .none)
        XCTAssertEqual(machine.handle(.markReloadCompleted(generationID: generation)), .none)
        XCTAssertEqual(machine.handle(.markCookieObserved(generationID: generation)), .none)
        XCTAssertEqual(machine.handle(.markCompactReady(generationID: generation,
                                                         pageToken: "new",
                                                         hasComment: true,
                                                         canSubmit: true)),
                       .startSubmitReadiness(attempt: 1, reason: .initial))
        XCTAssertEqual(machine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 1,
                                                  reason: .initial))
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "new",
            ready: true,
            stableForMilliseconds: 500
        )), .scheduleSubmitDelay)
        XCTAssertEqual(machine.handle(.initialSubmitDelayElapsed(generationID: generation)),
                       .submit(attempt: 1))
        XCTAssertEqual(machine.state,
                       .submitting(generationID: generation, attempt: 1))
    }

    func testPreparationDiagnosticsIdentifyMissingStagesWithoutContent() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: true,
                          hasImage: true)

        let initial = Dictionary(uniqueKeysWithValues: machine.preparationDiagnosticFields)
        XCTAssertEqual(initial["AP_READY"], "NO")
        XCTAssertEqual(initial["RELOAD_READY"], "NO")
        XCTAssertEqual(initial["COOKIE_READY"], "NO")
        XCTAssertEqual(initial["COMPACT_READY"], "NO")
        XCTAssertEqual(initial["HANDWRITING_READY"], "NO")
        XCTAssertTrue(initial["MISSING_STAGES"]?.contains("AP_READY") == true)
        XCTAssertFalse(initial.keys.contains("COMMENT"))

        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        let beforeImage = Dictionary(uniqueKeysWithValues: machine.preparationDiagnosticFields)
        XCTAssertEqual(beforeImage["MISSING_STAGES"], "HANDWRITING_READY")
    }

    func testReadinessRequiresStableReadySignal() {
        var machine = readyForReadinessMachine()
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: 499
        )), .none)
        XCTAssertEqual(machine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 1,
                                                  reason: .initial))
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: false,
            stableForMilliseconds: 0
        )), .none)
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: 500
        )), .scheduleSubmitDelay)
    }

    func testReadinessTimeoutStopsWithoutSubmitting() {
        var machine = readyForReadinessMachine()
        XCTAssertEqual(machine.handle(.submitReadinessTimedOut(generationID: generation)),
                       .stopped(.preparationTimeout))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation, reason: .preparationTimeout))
        XCTAssertEqual(machine.handle(.initialSubmitDelayElapsed(generationID: generation)),
                       .none)
    }

    func testSubmitResponseTimeoutRetriesOnceWhenNoFormSubmitWasObserved() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let firstSubmissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: firstSubmissionID
        )), .startSubmitReadiness(attempt: 1, reason: .submitResponseRetry))
        XCTAssertTrue(machine.submitResponseRetryUsed)
        XCTAssertTrue(machine.awaitingSubmitResponseRetry)
        XCTAssertEqual(machine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 1,
                                                  reason: .submitResponseRetry))

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: firstSubmissionID
        )), .none)

        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        )), .scheduleSubmitDelay)
        XCTAssertEqual(machine.handle(.initialSubmitDelayElapsed(generationID: generation)),
                       .submit(attempt: 1))
        let retrySubmissionID = try XCTUnwrap(machine.currentSubmissionID)
        XCTAssertNotEqual(retrySubmissionID, firstSubmissionID)

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: retrySubmissionID
        )), .stopped(.submitResponseTimeout))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                 reason: .submitResponseTimeout))
    }

    func testCookieRetryResponseTimeoutRequestsOneCookieRefresh() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        _ = machine.handleAlert(.cookieRetryRequired, generationID: generation)
        _ = machine.handle(.cookieAlertDismissed(generationID: generation))
        _ = submitAfterReadiness(&machine)
        let cookieRetrySubmissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: cookieRetrySubmissionID
        )), .startSubmitReadiness(attempt: 2, reason: .submitResponseRetry))
        _ = submitAfterReadiness(&machine)
        let responseRetrySubmissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: responseRetrySubmissionID
        )), .startCookieRefreshAfterTimeout)
        XCTAssertTrue(machine.cookieRefreshAfterTimeoutUsed)
        XCTAssertEqual(machine.state,
                       .waitingForCookieRefresh(generationID: generation, attempt: 2))
    }

    func testLateCompletionDuringResponseRetrySuppressesSecondClick() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: submissionID
        )), .startSubmitReadiness(attempt: 1, reason: .submitResponseRetry))
        XCTAssertTrue(machine.canAcceptPostCompletion)
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)), .succeeded)
        XCTAssertEqual(machine.state, .succeeded(generationID: generation))
        XCTAssertFalse(machine.awaitingSubmitResponseRetry)
        XCTAssertEqual(machine.handle(.initialSubmitDelayElapsed(generationID: generation)),
                       .none)
    }

    func testLateFormSubmitDuringResponseRetryRestoresResponseWaitWithoutClick() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)

        _ = machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: submissionID
        ))
        XCTAssertTrue(machine.awaitingSubmitResponseRetry)
        XCTAssertEqual(machine.handle(.submitObserved(
            generationID: generation,
            submissionID: submissionID
        )), .none)
        XCTAssertEqual(machine.state,
                       .submitting(generationID: generation, attempt: 1))
        XCTAssertTrue(machine.submitEventObserved)
        XCTAssertFalse(machine.awaitingSubmitResponseRetry)
        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: submissionID
        )), .stopped(.submitResponseTimeout))
    }

    func testResponseRetryClearsLateCompletionWindowWhenRetryClickStarts() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let firstSubmissionID = try XCTUnwrap(machine.currentSubmissionID)
        _ = machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: firstSubmissionID
        ))
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        )), .scheduleSubmitDelay)
        _ = machine.handle(.initialSubmitDelayElapsed(generationID: generation))
        XCTAssertFalse(machine.awaitingSubmitResponseRetry)
        XCTAssertTrue(machine.canAcceptPostCompletion)
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)), .succeeded)
    }

    func testSubmitResponseTimeoutStopsWhenFormSubmitWasObserved() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitObserved(
            generationID: generation,
            submissionID: submissionID
        )), .none)
        XCTAssertTrue(machine.submitEventObserved)
        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: submissionID
        )), .stopped(.submitResponseTimeout))
    }

    func testStaleSubmitObservationAndTimeoutAreIgnored() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)

        XCTAssertEqual(machine.handle(.submitObserved(
            generationID: generation + 1,
            submissionID: submissionID
        )), .none)
        XCTAssertFalse(machine.submitEventObserved)
        XCTAssertEqual(machine.handle(.submitObserved(
            generationID: generation,
            submissionID: submissionID + 1
        )), .none)
        XCTAssertFalse(machine.submitEventObserved)
        XCTAssertEqual(machine.handle(.submitResponseTimedOut(
            generationID: generation,
            submissionID: submissionID + 1
        )), .none)
        XCTAssertEqual(machine.state,
                       .submitting(generationID: generation, attempt: 1))
    }

    func testCookieAlertRetriesOnceWithoutConsumingIPBranch() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        XCTAssertEqual(machine.handleAlert(.cookieRetryRequired, generationID: generation).autoDismiss,
                       true)
        XCTAssertEqual(machine.state,
                       .waitingForCookieRetry(generationID: generation, attempt: 1))
        XCTAssertEqual(machine.handle(.cookieAlertDismissed(generationID: generation)),
                       .startSubmitReadiness(attempt: 2, reason: .cookieRetry))
        XCTAssertEqual(submitAfterReadiness(&machine), .submit(attempt: 2))

        XCTAssertEqual(machine.handleAlert(.cookieRetryRequired, generationID: generation).effect,
                       .stopped(.knownAlertAfterLimit))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation, reason: .knownAlertAfterLimit))
    }

    func testIPAlertUsesAPOnlyAndMakesNextAttemptTerminal() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        XCTAssertEqual(machine.handleAlert(.imagePostingRestricted,
                                           generationID: generation).effect,
                       .startIPReconnect)
        XCTAssertTrue(machine.ipRetryUsed)
        XCTAssertTrue(machine.ipRetryIsTerminal)
        XCTAssertEqual(machine.handle(.ipReconnectCompleted(generationID: generation,
                                                             success: true)),
                       .startSubmitReadiness(attempt: 2, reason: .ipRetry))
        XCTAssertEqual(submitAfterReadiness(&machine), .submit(attempt: 2))
        XCTAssertEqual(machine.handleAlert(.imagePostingRestricted,
                                           generationID: generation).effect,
                       .stopped(.knownAlertAfterLimit))
    }

    func testCookieThenIPUsesTheThirdAttempt() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        _ = machine.handleAlert(.cookieRetryRequired, generationID: generation)
        _ = machine.handle(.cookieAlertDismissed(generationID: generation))
        _ = submitAfterReadiness(&machine)
        XCTAssertEqual(machine.handleAlert(.imagePostingRestricted,
                                           generationID: generation).effect,
                       .startIPReconnect)
        XCTAssertEqual(machine.handle(.ipReconnectCompleted(generationID: generation,
                                                             success: true)),
                       .startSubmitReadiness(attempt: 3, reason: .ipRetry))
        XCTAssertEqual(submitAfterReadiness(&machine), .submit(attempt: 3))
    }

    func testAccessRestrictionStopsCurrentGenerationAndRequestsNextFlow() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let result = machine.handleAlert(.accessRestricted, generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startNextAutomaticFlow)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation, reason: .accessRestricted))
    }

    func testThreadPostingUnavailableStopsAndKeepsAlertVisible() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let result = machine.handleAlert(.threadPostingUnavailable,
                                         generationID: generation)

        XCTAssertFalse(result.autoDismiss)
        XCTAssertEqual(result.effect, .stopped(.unknownAlert))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation, reason: .unknownAlert))
    }

    func testImageCountRestrictionInSameThreadStartsNextUAFlow() {
        var machine = sameThreadReadyMachine()
        let result = machine.handleAlert(.imageCountRestricted,
                                         generationID: generation)

        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startNextAutomaticFlow)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .imageCountRestricted))
    }

    func testSameThreadModeSurvivesUAHandoffGeneration() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: false,
                          hasImage: true,
                          sameThreadRepeat: true)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: false,
                                              canSubmit: true))
        _ = machine.handle(.markHandwritingReady(generationID: generation,
                                                  pageToken: "page",
                                                  ready: true))
        _ = submitAfterReadiness(&machine)

        XCTAssertTrue(machine.isSameThreadRepeat)
        let result = machine.handleAlert(.imageCountRestricted,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startNextAutomaticFlow)
    }

    func testImageCountRestrictionOutsideSameThreadRemainsNormalAlert() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let result = machine.handleAlert(.imageCountRestricted,
                                         generationID: generation)

        XCTAssertFalse(result.autoDismiss)
        XCTAssertEqual(result.effect, .stopped(.unknownAlert))
    }

    func testImageContinuousRestrictionInSameThreadStartsNextUAFlow() {
        var machine = sameThreadReadyMachine()
        let result = machine.handleAlert(.imageContinuousPosting,
                                         generationID: generation)

        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startNextAutomaticFlow)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .imageCountRestricted))
    }

    func testImageContinuousRestrictionOutsideSameThreadRemainsNormalAlert() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let result = machine.handleAlert(.imageContinuousPosting,
                                         generationID: generation)

        XCTAssertFalse(result.autoDismiss)
        XCTAssertEqual(result.effect, .stopped(.unknownAlert))
    }

    func testSameThreadContinuousPostingUsesAPImmediately() {
        var machine = sameThreadReadyMachine()
        let result = machine.handleAlert(.continuousPosting,
                                         generationID: generation)

        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startContinuousAPReconnect)
        XCTAssertEqual(machine.state,
                       .waitingForContinuousAPRetry(generationID: generation,
                                                     attempt: 1))
    }

    func testContinuousAPUnchangedRetriesTwiceThenStops() {
        var machine = sameThreadReadyMachine()
        _ = machine.handleAlert(.continuousPosting, generationID: generation)

        XCTAssertEqual(machine.continuousAPReconnectAttempts, 1)
        XCTAssertEqual(machine.handle(.continuousAPReconnectUnchanged(
            generationID: generation
        )), .scheduleContinuousAPReconnectRetry)
        XCTAssertEqual(machine.continuousAPReconnectAttempts, 2)
        XCTAssertEqual(machine.state,
                       .waitingForContinuousAPRetry(generationID: generation,
                                                     attempt: 1))

        XCTAssertEqual(machine.handle(.continuousAPReconnectUnchanged(
            generationID: generation
        )), .scheduleContinuousAPReconnectRetry)
        XCTAssertEqual(machine.continuousAPReconnectAttempts, 3)

        XCTAssertEqual(machine.handle(.continuousAPReconnectUnchanged(
            generationID: generation
        )), .stopped(.communicationFailure))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .communicationFailure))
    }

    func testContinuousAPFailureStopsWithoutUnchangedIPBuffer() {
        var machine = sameThreadReadyMachine()
        _ = machine.handleAlert(.continuousPosting, generationID: generation)

        XCTAssertEqual(machine.handle(.continuousAPReconnectCompleted(
            generationID: generation,
            success: false
        )), .stopped(.communicationFailure))
        XCTAssertEqual(machine.continuousAPReconnectAttempts, 1)
    }

    func testFinalContinuousPostingUsesAPOnlyAndFourthAttempt() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        _ = machine.handleAlert(.cookieRetryRequired, generationID: generation)
        _ = machine.handle(.cookieAlertDismissed(generationID: generation))
        _ = submitAfterReadiness(&machine)
        _ = machine.handleAlert(.imagePostingRestricted, generationID: generation)
        _ = machine.handle(.ipReconnectCompleted(generationID: generation, success: true))
        _ = submitAfterReadiness(&machine)
        XCTAssertEqual(machine.currentAttempt, 3)

        let alertResult = machine.handleAlert(.continuousPosting, generationID: generation)
        XCTAssertTrue(alertResult.autoDismiss)
        XCTAssertEqual(alertResult.effect, .startContinuousAPReconnect)
        XCTAssertEqual(machine.state,
                       .waitingForContinuousAPRetry(generationID: generation, attempt: 3))
        XCTAssertEqual(machine.handle(.continuousAPReconnectCompleted(
            generationID: generation,
            success: true
        )), .startSubmitReadiness(attempt: 4, reason: .continuousAPRetry))
        XCTAssertEqual(submitAfterReadiness(&machine), .submit(attempt: 4))
        XCTAssertEqual(machine.currentAttempt, 4)
    }

    func testContinuousPostingBeforeFinalAttemptKeepsSameUAAndUsesReadiness() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let alertResult = machine.handleAlert(.continuousPosting, generationID: generation)
        XCTAssertTrue(alertResult.autoDismiss)
        XCTAssertEqual(machine.state,
                       .waitingForContinuousRetry(generationID: generation, attempt: 1))
        XCTAssertEqual(machine.handle(.continuousAlertDismissed(generationID: generation)),
                       .startSubmitReadiness(attempt: 2, reason: .continuousRetry))
        XCTAssertEqual(submitAfterReadiness(&machine), .submit(attempt: 2))
    }

    func testFourthAttemptKnownAlertStopsWithoutFifthSubmit() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        _ = machine.handleAlert(.cookieRetryRequired, generationID: generation)
        _ = machine.handle(.cookieAlertDismissed(generationID: generation))
        _ = submitAfterReadiness(&machine)
        _ = machine.handleAlert(.imagePostingRestricted, generationID: generation)
        _ = machine.handle(.ipReconnectCompleted(generationID: generation, success: true))
        _ = submitAfterReadiness(&machine)
        _ = machine.handleAlert(.continuousPosting, generationID: generation)
        _ = machine.handle(.continuousAPReconnectCompleted(generationID: generation,
                                                            success: true))
        _ = submitAfterReadiness(&machine)

        XCTAssertEqual(machine.handleAlert(.continuousPosting, generationID: generation).effect,
                       .stopped(.knownAlertAfterLimit))
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation, reason: .knownAlertAfterLimit))
        XCTAssertEqual(machine.handle(.continuousAlertDismissed(generationID: generation)), .none)
    }

    func testCompletionAndFailuresStopFurtherEvents() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)), .succeeded)
        XCTAssertEqual(machine.handleAlert(.cookieRetryRequired, generationID: generation).autoDismiss,
                       false)

        machine = readyMachine(hasComment: true, hasImage: false)
        XCTAssertEqual(machine.handle(.fail(generationID: generation,
                                             reason: .preparationTimeout)),
                       .stopped(.preparationTimeout))
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)), .none)
    }

    func testSubmissionSeedIsPreservedAsFirstOperationIdentity() throws {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: true,
                          hasImage: false,
                          submissionIDSeed: 100)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        _ = submitAfterReadiness(&machine)
        XCTAssertEqual(try XCTUnwrap(machine.currentSubmissionID), 100)
    }

    func testForceTerminateInvalidatesLateAutomaticEvents() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)
        machine.forceTerminate(generationID: generation)

        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .communicationFailure))
        XCTAssertFalse(machine.isActive)
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)), .none)
        XCTAssertEqual(machine.handle(.submitObserved(generationID: generation,
                                                       submissionID: submissionID)), .none)
        XCTAssertEqual(machine.handleAlert(.cookieRetryRequired,
                                           generationID: generation).effect,
                       .none)
    }

    func testStaleGenerationAndOldPageTokenAreIgnored() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: "same-page-before-reload",
                          hasComment: true,
                          hasImage: false)
        XCTAssertEqual(machine.handle(.markCompactReady(generationID: generation,
                                                         pageToken: "same-page-before-reload",
                                                         hasComment: true,
                                                         canSubmit: true)), .none)
        XCTAssertEqual(machine.handle(.markCompactReady(generationID: generation + 1,
                                                         pageToken: "new",
                                                         hasComment: true,
                                                         canSubmit: true)), .none)
        XCTAssertEqual(machine.pageToken, nil)
        XCTAssertTrue(machine.isStalePageToken("same-page-before-reload"))
        XCTAssertEqual(machine.handle(.markCompactReady(generationID: generation,
                                                         pageToken: "new",
                                                         hasComment: true,
                                                         canSubmit: true)), .none)
        XCTAssertEqual(machine.pageToken, "new")
    }

    func testStaleReadinessTokenIsIgnored() {
        var machine = readyForReadinessMachine()
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "stale",
            ready: true,
            stableForMilliseconds: 500
        )), .none)
        XCTAssertEqual(machine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 1,
                                                  reason: .initial))
    }

    func testImagePreparationRequiresHandwritingReady() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: false,
                          hasImage: true)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        XCTAssertEqual(machine.handle(.markCompactReady(generationID: generation,
                                                         pageToken: "page",
                                                         hasComment: false,
                                                         canSubmit: true)), .none)
        XCTAssertEqual(machine.handle(.markHandwritingReady(generationID: generation,
                                                             pageToken: "page",
                                                             ready: true)),
                       .startSubmitReadiness(attempt: 1, reason: .initial))
    }

    func testSameThreadRepeatUsesExistingPageAndRepeatReadinessReason() {
        var machine = AutomaticPostFlowMachine()
        let repeatGeneration = generation + 1
        XCTAssertEqual(machine.beginSameThreadRepeat(
            generationID: repeatGeneration,
            pageToken: "page",
            hasComment: true,
            hasImage: false
        ), .none)
        XCTAssertEqual(machine.handle(.markCompactReady(
            generationID: repeatGeneration,
            pageToken: "page",
            hasComment: true,
            canSubmit: true
        )), .startSubmitReadiness(attempt: 1, reason: .sameThreadRepeat))
        XCTAssertEqual(machine.state,
                       .waitingForSubmitReadiness(generationID: repeatGeneration,
                                                  attempt: 1,
                                                  reason: .sameThreadRepeat))
    }

    func testSameThreadRepeatRejectsStaleGenerationAndPageToken() {
        var machine = AutomaticPostFlowMachine()
        let repeatGeneration = generation + 1
        _ = machine.beginSameThreadRepeat(generationID: repeatGeneration,
                                          pageToken: "page",
                                          hasComment: false,
                                          hasImage: true)
        XCTAssertEqual(machine.handle(.markCompactReady(
            generationID: repeatGeneration + 1,
            pageToken: "page",
            hasComment: false,
            canSubmit: true
        )), .none)
        XCTAssertEqual(machine.handle(.markCompactReady(
            generationID: repeatGeneration,
            pageToken: "old-page",
            hasComment: false,
            canSubmit: true
        )), .none)
        XCTAssertEqual(machine.state, .preparing(generationID: repeatGeneration))
        XCTAssertEqual(machine.handle(.markCompactReady(
            generationID: repeatGeneration,
            pageToken: "page",
            hasComment: false,
            canSubmit: true
        )), .none)
        XCTAssertEqual(machine.handle(.markHandwritingReady(
            generationID: repeatGeneration,
            pageToken: "page",
            ready: true
        )), .startSubmitReadiness(attempt: 1, reason: .sameThreadRepeat))
    }

    func testSceneSuspendAndResumeKeepsGenerationAndReadinessState() throws {
        var machine = readyForReadinessMachine()
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: 499
        )), .none)
        XCTAssertTrue(machine.suspendForScene(generationID: generation))
        XCTAssertTrue(machine.isSceneSuspended)
        XCTAssertEqual(machine.handle(.submitReadinessTimedOut(generationID: generation)), .none)
        XCTAssertEqual(machine.resumeForScene(generationID: generation),
                       .restartReadiness(attempt: 1, reason: .initial))
        XCTAssertFalse(machine.isSceneSuspended)
        XCTAssertEqual(machine.generationID, generation)
        XCTAssertEqual(machine.currentAttempt, 1)
    }

    func testSceneResumeWhileSubmittingOnlyRestoresResponseMonitoring() throws {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let submissionID = try XCTUnwrap(machine.currentSubmissionID)
        XCTAssertTrue(machine.suspendForScene(generationID: generation))
        XCTAssertEqual(machine.handle(.submitObserved(generationID: generation,
                                                       submissionID: submissionID)),
                       .none)
        XCTAssertEqual(machine.handle(.postCompleted(generationID: generation)),
                       .succeeded)
        XCTAssertEqual(machine.resumeForScene(generationID: generation), .none)
        XCTAssertEqual(machine.currentSubmissionID, submissionID)
        XCTAssertEqual(machine.state, .succeeded(generationID: generation))

        var monitoringMachine = readyMachine(hasComment: true, hasImage: false)
        let monitoringSubmissionID = try XCTUnwrap(
            monitoringMachine.currentSubmissionID
        )
        XCTAssertTrue(monitoringMachine.suspendForScene(generationID: generation))
        XCTAssertEqual(monitoringMachine.resumeForScene(generationID: generation),
                       .restartResponseMonitoring(attempt: 1,
                                                  submissionID: monitoringSubmissionID))
    }

    func testSceneResumeRequiresMatchingGenerationAndIsIdempotent() {
        var machine = readyForReadinessMachine()
        XCTAssertFalse(machine.suspendForScene(generationID: generation + 1))
        XCTAssertTrue(machine.suspendForScene(generationID: generation))
        XCTAssertEqual(machine.resumeForScene(generationID: generation + 1), .none)
        XCTAssertEqual(machine.resumeForScene(generationID: generation),
                       .restartReadiness(attempt: 1, reason: .initial))
        XCTAssertEqual(machine.resumeForScene(generationID: generation), .none)
    }

    func testSceneResumeConvertsDeferredCookieAndContinuousAlertsToReadiness() {
        var cookieMachine = readyMachine(hasComment: true, hasImage: false)
        let cookieAlert = cookieMachine.handleAlert(.cookieRetryRequired,
                                                    generationID: generation)
        XCTAssertTrue(cookieAlert.autoDismiss)
        XCTAssertTrue(cookieMachine.suspendForScene(generationID: generation))
        XCTAssertEqual(cookieMachine.resumeForScene(generationID: generation),
                       .restartReadiness(attempt: 2, reason: .cookieRetry))
        XCTAssertEqual(cookieMachine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 2,
                                                  reason: .cookieRetry))

        var continuousMachine = readyMachine(hasComment: true, hasImage: false)
        let continuousAlert = continuousMachine.handleAlert(.continuousPosting,
                                                            generationID: generation)
        XCTAssertTrue(continuousAlert.autoDismiss)
        XCTAssertTrue(continuousMachine.suspendForScene(generationID: generation))
        XCTAssertEqual(continuousMachine.resumeForScene(generationID: generation),
                       .restartReadiness(attempt: 2, reason: .continuousRetry))
        XCTAssertEqual(continuousMachine.state,
                       .waitingForSubmitReadiness(generationID: generation,
                                                  attempt: 2,
                                                  reason: .continuousRetry))
    }

    func testEmptyCandidateStopsWithoutSubmitting() {
        var machine = AutomaticPostFlowMachine()
        XCTAssertEqual(machine.begin(generationID: generation,
                                     oldPageToken: nil,
                                     hasComment: false,
                                     hasImage: false),
                       .stopped(.noContent))
        XCTAssertFalse(machine.isActive)
    }

    func testMultiThreadNavigationCarriesPreparationAndSkipsUnavailableThread() {
        var machine = AutomaticPostFlowMachine()
        XCTAssertEqual(machine.beginMultiThreadNavigation(
            generationID: generation,
            oldPageToken: "old-page",
            hasComment: true,
            hasImage: false
        ), .none)
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCompactReady(
            generationID: generation,
            pageToken: "new-page",
            hasComment: true,
            canSubmit: true
        ))
        XCTAssertEqual(machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "new-page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        )), .scheduleSubmitDelay)
        _ = machine.handle(.initialSubmitDelayElapsed(generationID: generation))

        let result = machine.handleAlert(.threadPostingUnavailable,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .skipCurrentThread)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .threadPostingUnavailable))
    }

    func testMultiThreadMissingThreadAlertSkipsCurrentTarget() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.beginMultiThreadNavigation(
            generationID: generation,
            oldPageToken: "old-page",
            hasComment: true,
            hasImage: false
        )
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCompactReady(
            generationID: generation,
            pageToken: "new-page",
            hasComment: true,
            canSubmit: true
        ))
        _ = machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "new-page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        ))
        _ = machine.handle(.initialSubmitDelayElapsed(generationID: generation))

        let result = machine.handleAlert(.threadNotFound,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .skipCurrentThread)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .threadUnavailable))
    }

    func testSameThreadMissingThreadAlertRemainsTerminalUnknownAlert() {
        var machine = readyMachine(hasComment: true, hasImage: false)
        let result = machine.handleAlert(.threadNotFound,
                                         generationID: generation)
        XCTAssertFalse(result.autoDismiss)
        XCTAssertEqual(result.effect, .stopped(.unknownAlert))
    }

    func testMultiThreadReplyLimitSkipsCurrentTarget() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.beginMultiThreadNavigation(
            generationID: generation,
            oldPageToken: "old-page",
            hasComment: true,
            hasImage: false
        )
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCompactReady(
            generationID: generation,
            pageToken: "new-page",
            hasComment: true,
            canSubmit: true
        ))
        _ = machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "new-page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        ))
        _ = machine.handle(.initialSubmitDelayElapsed(generationID: generation))

        let result = machine.handleAlert(.replyLimitReached,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .skipCurrentThread)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .knownAlertAfterLimit))
    }

    func testMultiThreadNavigationUsesDedicatedSameUserAgentReadinessReason() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.beginMultiThreadNavigation(
            generationID: generation,
            oldPageToken: "old-page",
            hasComment: true,
            hasImage: false
        )
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        let readiness = machine.handle(.markCompactReady(
            generationID: generation,
            pageToken: "new-page",
            hasComment: true,
            canSubmit: true
        ))

        XCTAssertEqual(
            readiness,
            .startSubmitReadiness(attempt: 1, reason: .sameUserAgentMultiThread)
        )
        XCTAssertEqual(machine.lastSubmitReadinessReason,
                       .sameUserAgentMultiThread)
    }

    func testMultiThreadSkipsUnavailableTargetDuringPreparation() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.beginMultiThreadNavigation(
            generationID: generation,
            oldPageToken: "old-page",
            hasComment: true,
            hasImage: false
        )

        XCTAssertEqual(
            machine.skipCurrentThread(reason: .threadUnavailable),
            .skipCurrentThread
        )
        XCTAssertEqual(
            machine.state,
            .stopped(generationID: generation, reason: .threadUnavailable)
        )
    }

    func testMultiThreadImageRestrictionRequestsNextUA() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: false,
                          hasImage: true,
                          multiThread: true)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: false,
                                              canSubmit: true))
        _ = machine.handle(.markHandwritingReady(generationID: generation,
                                                  pageToken: "page",
                                                  ready: true))
        _ = submitAfterReadiness(&machine)

        let result = machine.handleAlert(.imageCountRestricted,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .startNextAutomaticFlow)
    }

    func testMultiThreadContinuousPostingKeepsCurrentGenerationRetryRules() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: true,
                          hasImage: false,
                          multiThread: true)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        _ = submitAfterReadiness(&machine)

        let first = machine.handleAlert(.continuousPosting, generationID: generation)
        XCTAssertTrue(first.autoDismiss)
        XCTAssertEqual(first.effect, .none)
        XCTAssertEqual(machine.handle(.continuousAlertDismissed(generationID: generation)),
                       .startSubmitReadiness(attempt: 2, reason: .continuousRetry))
    }

    func testMultiThreadRepeatedContinuousPostingRequestsUAHandoffAfterLimit() {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: true,
                          hasImage: false,
                          multiThread: true)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        _ = submitAfterReadiness(&machine)

        _ = machine.handleAlert(.continuousPosting, generationID: generation)
        _ = machine.handle(.continuousAlertDismissed(generationID: generation))
        _ = submitAfterReadiness(&machine)

        let result = machine.handleAlert(.continuousPosting,
                                         generationID: generation)
        XCTAssertTrue(result.autoDismiss)
        XCTAssertEqual(result.effect, .handoffAfterContinuousLimit)
        XCTAssertEqual(machine.state,
                       .stopped(generationID: generation,
                                reason: .knownAlertAfterLimit))
    }

    private func readyForReadinessMachine() -> AutomaticPostFlowMachine {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: true,
                          hasImage: false)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        return machine
    }

    private func readyMachine(hasComment: Bool,
                              hasImage: Bool) -> AutomaticPostFlowMachine {
        var machine = AutomaticPostFlowMachine()
        _ = machine.begin(generationID: generation,
                          oldPageToken: nil,
                          hasComment: hasComment,
                          hasImage: hasImage)
        _ = machine.handle(.markAPCompleted(generationID: generation))
        _ = machine.handle(.markReloadCompleted(generationID: generation))
        _ = machine.handle(.markCookieObserved(generationID: generation))
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: hasComment,
                                              canSubmit: true))
        if hasImage {
            _ = machine.handle(.markHandwritingReady(generationID: generation,
                                                      pageToken: "page",
                                                      ready: true))
        }
        _ = submitAfterReadiness(&machine)
        return machine
    }

    private func sameThreadReadyMachine() -> AutomaticPostFlowMachine {
        var machine = AutomaticPostFlowMachine()
        _ = machine.beginSameThreadRepeat(generationID: generation,
                                           pageToken: "page",
                                           hasComment: true,
                                           hasImage: false)
        _ = machine.handle(.markCompactReady(generationID: generation,
                                              pageToken: "page",
                                              hasComment: true,
                                              canSubmit: true))
        _ = submitAfterReadiness(&machine)
        return machine
    }

    @discardableResult
    private func submitAfterReadiness(_ machine: inout AutomaticPostFlowMachine)
        -> AutomaticPostFlowEffect {
        let readinessEffect = machine.handle(.submitReadinessObserved(
            generationID: generation,
            pageToken: "page",
            ready: true,
            stableForMilliseconds: AutomaticPostFlowMachine.readinessStableMilliseconds
        ))
        XCTAssertEqual(readinessEffect, .scheduleSubmitDelay)
        return machine.handle(.initialSubmitDelayElapsed(generationID: generation))
    }
}
