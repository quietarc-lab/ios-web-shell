import Foundation

enum AutomaticPostAlert: Equatable {
    case cookieRetryRequired
    case imagePostingRestricted
    case accessRestricted
    case continuousPosting
    case imageContinuousPosting
    case threadPostingUnavailable
    case threadNotFound
    case replyLimitReached
    case imageCountRestricted
}

enum TargetPageAlertDisposition: Equatable {
    case showNormally
    case autoDismiss
}

enum AutomaticPostStopReason: Equatable, Sendable {
    case noContent
    case noAvailableUserAgent
    case accessRestricted
    case preparationTimeout
    case preparationFailed
    case communicationFailure
    case unknownAlert
    case knownAlertAfterLimit
    case retryLimit
    case repeatDisabled
    case imageCountRestricted
    case submitResponseTimeout
    case threadPostingUnavailable
    /// The target document loaded, but did not expose a usable thread/form.
    /// Multi-thread sessions may skip this target and continue with the next
    /// snapshot entry; single-thread flows still treat it as a failure.
    case threadUnavailable
    case catalogRefreshFailed
    /// The Futapo isolation feed confirmed a thread referenced by the active
    /// automatic session. This is a terminal session-level safety stop.
    case isolatedThread
    /// The Futapo moderation feed confirmed that a referenced thread was
    /// deleted. This is a terminal session-level safety stop.
    case deletedThread
    /// The scene could not restore an active automatic session after the app
    /// returned from another app or Shortcuts.
    case sceneResumeFailed
}

extension AutomaticPostStopReason {
    /// Only unexpected terminal failures should require an explicit user
    /// acknowledgement. User-requested stops, normal multi-thread skips,
    /// and moderation stops (which have their own notice) stay silent here.
    var requiresUserAlert: Bool {
        switch self {
        case .repeatDisabled,
             .threadUnavailable,
             .isolatedThread,
             .deletedThread:
            return false
        case .noContent,
             .noAvailableUserAgent,
             .accessRestricted,
             .preparationTimeout,
             .preparationFailed,
             .communicationFailure,
             .unknownAlert,
             .knownAlertAfterLimit,
             .retryLimit,
             .imageCountRestricted,
             .submitResponseTimeout,
             .threadPostingUnavailable,
             .catalogRefreshFailed,
             .sceneResumeFailed:
            return true
        }
    }

    var userAlertMessage: String {
        switch self {
        case .noContent:
            return "投稿内容を準備できなかったため自動投稿を停止しました"
        case .noAvailableUserAgent:
            return "利用可能なUAがなくなったため自動投稿を停止しました"
        case .accessRestricted:
            return "アクセス規制の切り替えに失敗したため自動投稿を停止しました"
        case .preparationTimeout:
            return "投稿準備がタイムアウトしたため自動投稿を停止しました"
        case .preparationFailed:
            return "投稿準備に失敗したため自動投稿を停止しました"
        case .communicationFailure:
            return "通信に失敗したため自動投稿を停止しました"
        case .unknownAlert:
            return "未対応のサイト通知を検知したため自動投稿を停止しました"
        case .knownAlertAfterLimit:
            return "投稿制限の上限に達したため自動投稿を停止しました"
        case .retryLimit:
            return "再試行上限に達したため自動投稿を停止しました"
        case .repeatDisabled:
            return "自動投稿を停止しました"
        case .imageCountRestricted:
            return "画像枚数制限のため自動投稿を停止しました"
        case .submitResponseTimeout:
            return "投稿結果を確認できなかったため自動投稿を停止しました"
        case .threadPostingUnavailable:
            return "このスレッドには書き込めないため自動投稿を停止しました"
        case .threadUnavailable:
            return "スレッドを利用できないため自動投稿を停止しました"
        case .catalogRefreshFailed:
            return "スレッド一覧の取得に失敗したため自動投稿を停止しました"
        case .isolatedThread,
             .deletedThread:
            return "自動投稿を停止しました"
        case .sceneResumeFailed:
            return "復帰処理に失敗したため自動投稿を停止しました"
        }
    }
}

enum AutomaticPostReadinessReason: String, Equatable {
    case initial = "INITIAL"
    case cookieRetry = "COOKIE_RETRY"
    case ipRetry = "IP_RETRY"
    case continuousRetry = "CONTINUOUS_RETRY"
    case continuousAPRetry = "CONTINUOUS_AP_RETRY"
    case sameThreadRepeat = "SAME_THREAD_REPEAT"
    case sameUserAgentMultiThread = "SAME_UA_MULTI_THREAD"
    case submitResponseRetry = "SUBMIT_RESPONSE_RETRY"
}

enum AutomaticPostFlowState: Equatable {
    case idle
    case preparing(generationID: UInt64)
    case waitingForSubmitReadiness(generationID: UInt64,
                                   attempt: Int,
                                   reason: AutomaticPostReadinessReason)
    case waitingToSubmit(generationID: UInt64, attempt: Int)
    case submitting(generationID: UInt64, attempt: Int)
    case waitingForCookieRetry(generationID: UInt64, attempt: Int)
    case waitingForCookieRefresh(generationID: UInt64, attempt: Int)
    case waitingForIPRetry(generationID: UInt64, attempt: Int)
    case waitingForContinuousRetry(generationID: UInt64, attempt: Int)
    case waitingForContinuousAPRetry(generationID: UInt64, attempt: Int)
    case succeeded(generationID: UInt64)
    case stopped(generationID: UInt64, reason: AutomaticPostStopReason)
}

enum AutomaticPostFlowEffect: Equatable {
    case none
    case startSubmitReadiness(attempt: Int, reason: AutomaticPostReadinessReason)
    case scheduleSubmitDelay
    case submit(attempt: Int)
    case startIPReconnect
    case startContinuousAPReconnect
    case scheduleContinuousAPReconnectRetry
    case startCookieRefreshAfterTimeout
    case startNextAutomaticFlow
    /// Multi-thread-only terminal recovery for a repeated short
    /// continuous-posting restriction. The coordinator decides whether this
    /// is the first UA handoff for the target or a per-target skip.
    case handoffAfterContinuousLimit
    case skipCurrentThread
    case succeeded
    case stopped(AutomaticPostStopReason)
}

/// The coordinator uses this value to restart only the gate that was active
/// when the scene became inactive. It deliberately contains no page data.
enum AutomaticPostSceneResumeAction: Equatable {
    case none
    case restartPreparation
    case restartReadiness(attempt: Int, reason: AutomaticPostReadinessReason)
    case restartSubmitDelay
    case restartResponseMonitoring(attempt: Int, submissionID: UInt64)
}

enum AutomaticPostFlowEvent: Equatable {
    case markAPCompleted(generationID: UInt64)
    case markReloadCompleted(generationID: UInt64)
    case markCookieObserved(generationID: UInt64)
    case markCompactReady(generationID: UInt64,
                          pageToken: String,
                          hasComment: Bool,
                          canSubmit: Bool)
    case markHandwritingReady(generationID: UInt64,
                              pageToken: String,
                              ready: Bool)
    case submitReadinessObserved(generationID: UInt64,
                                 pageToken: String,
                                 ready: Bool,
                                 stableForMilliseconds: Int)
    case submitReadinessTimedOut(generationID: UInt64)
    case initialSubmitDelayElapsed(generationID: UInt64)
    case cookieAlertDismissed(generationID: UInt64)
    case continuousAlertDismissed(generationID: UInt64)
    case ipReconnectCompleted(generationID: UInt64, success: Bool)
    case continuousAPReconnectUnchanged(generationID: UInt64)
    case continuousAPReconnectCompleted(generationID: UInt64, success: Bool)
    case submitObserved(generationID: UInt64, submissionID: UInt64)
    case submitResponseTimedOut(generationID: UInt64, submissionID: UInt64)
    case ipSubmitDelayElapsed(generationID: UInt64)
    case postCompleted(generationID: UInt64)
    case fail(generationID: UInt64, reason: AutomaticPostStopReason)
    case reset
}

struct AutomaticPostFlowMachine {
    static let regularAttemptLimit = 3
    static let maximumAttempts = 4
    /// A continuous-post restriction may be caused by an AP shortcut that
    /// returned before the address actually changed. Allow the initial AP
    /// request plus two bounded retries for that specific outcome.
    static let continuousAPReconnectAttemptLimit = 3
    static let readinessStableMilliseconds = 500

    private(set) var state: AutomaticPostFlowState = .idle
    private(set) var generationID: UInt64?
    private(set) var pageToken: String?
    private(set) var cookieRetryUsed = false
    private(set) var ipRetryUsed = false
    private(set) var ipRetryIsTerminal = false
    private(set) var continuousRetryUsed = false
    private(set) var continuousAPReconnectAttempts = 0
    private(set) var requiresHandwriting = false
    private(set) var lastAttempt = 0
    private(set) var isSameThreadRepeat = false
    private(set) var isMultiThread = false
    private(set) var currentSubmissionID: UInt64? = nil
    private(set) var submitEventObserved = false
    private(set) var submitResponseRetryUsed = false
    /// The one bounded recovery that re-reads Cookies after a response
    /// timeout which already followed the site's Cookie retry alert.
    private(set) var cookieRefreshAfterTimeoutUsed = false
    /// A response timeout may race with a site's delayed completion marker.
    /// Keep the timed-out submission identifiable while the one allowed retry
    /// is being prepared so that a late completion can finish the flow without
    /// dispatching a duplicate click.
    private(set) var awaitingSubmitResponseRetry = false
    private(set) var lastSubmitReadinessReason: AutomaticPostReadinessReason = .initial
    private(set) var submitResponseRetryOrigin: AutomaticPostReadinessReason?
    private(set) var isSceneSuspended = false

    private var stalePageToken: String?
    private var apCompleted = false
    private var reloadCompleted = false
    private var cookieObserved = false
    private var compactReady = false
    private var handwritingReady = false
    private var preparationReason: AutomaticPostReadinessReason = .initial

    var isActive: Bool {
        switch state {
        case .preparing, .waitingForSubmitReadiness, .waitingToSubmit,
             .submitting, .waitingForCookieRetry, .waitingForCookieRefresh,
             .waitingForIPRetry,
             .waitingForContinuousRetry, .waitingForContinuousAPRetry:
            return true
        case .idle, .succeeded, .stopped:
            return false
        }
    }

    var currentAttempt: Int? {
        switch state {
        case let .waitingForSubmitReadiness(_, attempt, _),
             let .waitingToSubmit(_, attempt),
             let .submitting(_, attempt),
             let .waitingForCookieRetry(_, attempt),
             let .waitingForCookieRefresh(_, attempt),
             let .waitingForIPRetry(_, attempt),
             let .waitingForContinuousRetry(_, attempt),
             let .waitingForContinuousAPRetry(_, attempt):
            return attempt
        case .idle, .preparing, .succeeded, .stopped:
            return nil
        }
    }

    /// Whether a completion marker may be accepted for the current
    /// generation. Normally this is only true while the submitted click is
    /// active. During the single response-retry window, a site may deliver a
    /// delayed completion marker after the watchdog moved into readiness; in
    /// that narrow case the marker is accepted and the retry click is skipped.
    var canAcceptPostCompletion: Bool {
        switch state {
        case .submitting:
            return true
        case .waitingForSubmitReadiness(_, _, .submitResponseRetry),
             .waitingToSubmit:
            return awaitingSubmitResponseRetry
        default:
            return false
        }
    }

    /// Diagnostic-only readiness flags. The values deliberately contain no
    /// page content, Cookie data, image data, or page token.
    var preparationDiagnosticFields: [(String, String)] {
        let flags: [(String, Bool)] = [
            ("AP_READY", apCompleted),
            ("RELOAD_READY", reloadCompleted),
            ("COOKIE_READY", cookieObserved),
            ("COMPACT_READY", compactReady),
            ("HANDWRITING_READY", handwritingReady)
        ]
        let missing = flags
            .filter { !$0.1 }
            .map { $0.0 }
            .joined(separator: ",")
        return flags.map { ($0.0, $0.1 ? "YES" : "NO") } + [
            ("MISSING_STAGES", missing.isEmpty ? "NONE" : missing)
        ]
    }

    func isStalePageToken(_ token: String) -> Bool {
        guard let stalePageToken,
              pageToken == nil else { return false }
        return stalePageToken == token
    }

    mutating func begin(generationID: UInt64,
                        oldPageToken: String?,
                        hasComment: Bool,
                        hasImage: Bool,
                        multiThread: Bool = false,
                        sameThreadRepeat: Bool = false,
                        cookieRefreshAfterTimeoutUsed: Bool = false,
                        submissionIDSeed: UInt64? = nil) -> AutomaticPostFlowEffect {
        guard hasComment || hasImage else {
            state = .stopped(generationID: generationID, reason: .noContent)
            self.generationID = generationID
            return .stopped(.noContent)
        }

        self.generationID = generationID
        isSceneSuspended = false
        // A UA handoff starts a fresh generation, but it can still belong to
        // the same-thread repeat session. Preserve that mode so image-limit
        // and continuous-post alerts keep their session-specific recovery
        // behavior after the handoff. Multi-thread generations have their
        // own mode and must not be classified as same-thread repeats.
        isSameThreadRepeat = sameThreadRepeat && !multiThread
        isMultiThread = multiThread
        stalePageToken = oldPageToken
        pageToken = nil
        requiresHandwriting = hasImage
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        continuousAPReconnectAttempts = 0
        lastAttempt = 0
        currentSubmissionID = submissionIDSeed.map { $0 > 0 ? $0 - 1 : 0 }
        submitEventObserved = false
        submitResponseRetryUsed = false
        self.cookieRefreshAfterTimeoutUsed = cookieRefreshAfterTimeoutUsed
        awaitingSubmitResponseRetry = false
        lastSubmitReadinessReason = .initial
        submitResponseRetryOrigin = nil
        apCompleted = false
        reloadCompleted = false
        cookieObserved = false
        compactReady = false
        handwritingReady = !hasImage
        state = .preparing(generationID: generationID)
        preparationReason = .initial
        return .none
    }

    /// Starts a generation for a new catalog target after navigation. AP and
    /// Cookie state are intentionally carried over; only the page load and
    /// compact-form/handwriting readiness must be observed again.
    mutating func beginMultiThreadNavigation(generationID: UInt64,
                                             oldPageToken: String?,
                                             hasComment: Bool,
                                             hasImage: Bool,
                                             submissionIDSeed: UInt64? = nil) -> AutomaticPostFlowEffect {
        guard hasComment || hasImage else {
            state = .stopped(generationID: generationID, reason: .noContent)
            self.generationID = generationID
            return .stopped(.noContent)
        }
        self.generationID = generationID
        isSceneSuspended = false
        isSameThreadRepeat = false
        isMultiThread = true
        stalePageToken = oldPageToken
        pageToken = nil
        requiresHandwriting = hasImage
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        continuousAPReconnectAttempts = 0
        lastAttempt = 0
        currentSubmissionID = submissionIDSeed.map { $0 > 0 ? $0 - 1 : 0 }
        submitEventObserved = false
        submitResponseRetryUsed = false
        cookieRefreshAfterTimeoutUsed = false
        awaitingSubmitResponseRetry = false
        lastSubmitReadinessReason = .sameUserAgentMultiThread
        submitResponseRetryOrigin = nil
        // A catalog transition does not delete Cookies or reconnect AP. The
        // navigation itself is the only preparation stage still pending.
        apCompleted = true
        reloadCompleted = false
        cookieObserved = true
        compactReady = false
        handwritingReady = !hasImage
        preparationReason = .sameUserAgentMultiThread
        state = .preparing(generationID: generationID)
        return .none
    }

    mutating func beginSameThreadRepeat(generationID: UInt64,
                                        pageToken: String,
                                        hasComment: Bool,
                                        hasImage: Bool,
                                        submissionIDSeed: UInt64? = nil) -> AutomaticPostFlowEffect {
        guard !pageToken.isEmpty,
              hasComment || hasImage else {
            state = .stopped(generationID: generationID, reason: .noContent)
            self.generationID = generationID
            return .stopped(.noContent)
        }

        self.generationID = generationID
        isSceneSuspended = false
        isSameThreadRepeat = true
        isMultiThread = false
        stalePageToken = nil
        self.pageToken = pageToken
        requiresHandwriting = hasImage
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        continuousAPReconnectAttempts = 0
        lastAttempt = 0
        currentSubmissionID = submissionIDSeed.map { $0 > 0 ? $0 - 1 : 0 }
        submitEventObserved = false
        submitResponseRetryUsed = false
        cookieRefreshAfterTimeoutUsed = false
        awaitingSubmitResponseRetry = false
        lastSubmitReadinessReason = .sameThreadRepeat
        submitResponseRetryOrigin = nil
        // The page, AP state, and Cookie observation are already valid for a
        // same-page repeat. Compact-form and handwriting readiness are still
        // re-established through the bridge before the next click.
        apCompleted = true
        reloadCompleted = true
        cookieObserved = true
        compactReady = false
        handwritingReady = !hasImage
        preparationReason = .sameThreadRepeat
        state = .preparing(generationID: generationID)
        return .none
    }

    /// Suspends generation-local bridge and timer effects while the app scene
    /// is inactive. AP callbacks are still allowed to settle the external
    /// shortcut operation; the coordinator defers any resulting effect until
    /// the scene is active again.
    @discardableResult
    mutating func suspendForScene(generationID: UInt64) -> Bool {
        guard self.generationID == generationID, isActive else { return false }
        isSceneSuspended = true
        return true
    }

    /// Reconnects the state machine to the coordinator without advancing the
    /// generation or creating a new submission identity.
    mutating func resumeForScene(generationID: UInt64) -> AutomaticPostSceneResumeAction {
        guard self.generationID == generationID, isSceneSuspended else {
            return .none
        }
        isSceneSuspended = false
        switch state {
        case .preparing:
            return .restartPreparation
        case let .waitingForSubmitReadiness(_, attempt, reason):
            return .restartReadiness(attempt: attempt, reason: reason)
        case .waitingToSubmit:
            return .restartSubmitDelay
        case let .submitting(_, attempt):
            guard let submissionID = currentSubmissionID else { return .none }
            return .restartResponseMonitoring(attempt: attempt,
                                              submissionID: submissionID)
        case let .waitingForCookieRetry(_, attempt):
            let nextAttempt = attempt + 1
            guard nextAttempt <= Self.regularAttemptLimit else { return .none }
            _ = beginSubmitReadiness(attempt: nextAttempt, reason: .cookieRetry)
            return .restartReadiness(attempt: nextAttempt, reason: .cookieRetry)
        case let .waitingForContinuousRetry(_, attempt):
            let nextAttempt = attempt + 1
            guard nextAttempt <= Self.maximumAttempts else { return .none }
            _ = beginSubmitReadiness(attempt: nextAttempt, reason: .continuousRetry)
            return .restartReadiness(attempt: nextAttempt, reason: .continuousRetry)
        case .idle, .waitingForCookieRefresh,
             .waitingForIPRetry,
             .waitingForContinuousAPRetry, .succeeded, .stopped:
            return .none
        }
    }

    mutating func handle(_ event: AutomaticPostFlowEvent) -> AutomaticPostFlowEffect {
        if case .reset = event {
            reset()
            return .none
        }

        guard let eventGenerationID = event.generationID,
              eventGenerationID == generationID else {
            return .none
        }

        if isSceneSuspended {
            switch event {
            case .markAPCompleted, .markReloadCompleted, .markCookieObserved,
                 .ipReconnectCompleted, .continuousAPReconnectUnchanged,
                 .continuousAPReconnectCompleted, .submitObserved, .postCompleted:
                break
            default:
                return .none
            }
        }

        switch event {
        case .reset:
            return .none

        case .markAPCompleted:
            guard case .preparing = state else { return .none }
            apCompleted = true
            return preparationEffectIfReady()

        case .markReloadCompleted:
            guard case .preparing = state else { return .none }
            reloadCompleted = true
            return preparationEffectIfReady()

        case .markCookieObserved:
            guard case .preparing = state else { return .none }
            cookieObserved = true
            return preparationEffectIfReady()

        case let .markCompactReady(_, token, hasComment, canSubmit):
            guard case .preparing = state,
                  acceptPageToken(token) else {
                return .none
            }
            guard hasComment || requiresHandwriting else {
                return stop(.noContent)
            }
            guard canSubmit else {
                return stop(.preparationFailed)
            }
            compactReady = true
            return preparationEffectIfReady()

        case let .markHandwritingReady(_, token, ready):
            guard case .preparing = state,
                  acceptPageToken(token) else {
                return .none
            }
            guard ready else {
                return stop(.preparationFailed)
            }
            handwritingReady = true
            return preparationEffectIfReady()

        case let .submitReadinessObserved(_, token, ready, stableForMilliseconds):
            guard case let .waitingForSubmitReadiness(_, attempt, _) = state,
                  acceptPageToken(token),
                  ready,
                  stableForMilliseconds >= Self.readinessStableMilliseconds,
                  let generationID else {
                return .none
            }
            state = .waitingToSubmit(generationID: generationID, attempt: attempt)
            return .scheduleSubmitDelay

        case .submitReadinessTimedOut:
            guard case .waitingForSubmitReadiness = state else { return .none }
            return stop(.preparationTimeout)

        case .initialSubmitDelayElapsed:
            guard case let .waitingToSubmit(_, attempt) = state else { return .none }
            return beginSubmit(attempt: attempt)

        case .cookieAlertDismissed:
            guard case let .waitingForCookieRetry(_, attempt) = state,
                  attempt < Self.regularAttemptLimit else {
                return .none
            }
            return beginSubmitReadiness(attempt: attempt + 1, reason: .cookieRetry)

        case .continuousAlertDismissed:
            guard case let .waitingForContinuousRetry(_, attempt) = state,
                  attempt < Self.maximumAttempts else {
                return .none
            }
            return beginSubmitReadiness(attempt: attempt + 1, reason: .continuousRetry)

        case let .ipReconnectCompleted(_, success):
            guard case let .waitingForIPRetry(_, attempt) = state else { return .none }
            guard success else {
                return stop(.communicationFailure)
            }
            return beginSubmitReadiness(attempt: attempt + 1, reason: .ipRetry)

        case .continuousAPReconnectUnchanged:
            guard case .waitingForContinuousAPRetry = state else {
                return .none
            }
            guard continuousAPReconnectAttempts < Self.continuousAPReconnectAttemptLimit else {
                return stop(.communicationFailure)
            }
            continuousAPReconnectAttempts += 1
            return .scheduleContinuousAPReconnectRetry

        case .ipSubmitDelayElapsed:
            return .none

        case let .continuousAPReconnectCompleted(_, success):
            guard case let .waitingForContinuousAPRetry(_, attempt) = state else {
                return .none
            }
            guard success else {
                return stop(.communicationFailure)
            }
            return beginSubmitReadiness(attempt: attempt + 1,
                                        reason: .continuousAPRetry)

        case let .submitObserved(_, submissionID):
            guard currentSubmissionID == submissionID else {
                return .none
            }
            let canAcceptLateSubmit: Bool
            switch state {
            case .submitting:
                canAcceptLateSubmit = true
            case .waitingForSubmitReadiness(_, _, .submitResponseRetry),
                 .waitingToSubmit:
                canAcceptLateSubmit = awaitingSubmitResponseRetry
            default:
                canAcceptLateSubmit = false
            }
            guard canAcceptLateSubmit else { return .none }
            if awaitingSubmitResponseRetry {
                guard let generationID else { return .none }
                state = .submitting(generationID: generationID,
                                    attempt: lastAttempt)
                awaitingSubmitResponseRetry = false
            }
            submitEventObserved = true
            return .none

        case let .submitResponseTimedOut(_, submissionID):
            guard case let .submitting(_, attempt) = state,
                  currentSubmissionID == submissionID else {
                return .none
            }
            guard !submitEventObserved else {
                return stop(.submitResponseTimeout)
            }
            if !submitResponseRetryUsed {
                submitResponseRetryUsed = true
                submitResponseRetryOrigin = lastSubmitReadinessReason
                awaitingSubmitResponseRetry = true
                return beginSubmitReadiness(attempt: attempt,
                                            reason: .submitResponseRetry)
            }
            // A timeout immediately after the site's Cookie retry means the
            // page may still be using the pre-refresh Cookie state. Rebuild
            // the Cookie/page preparation once, retaining the in-memory draft
            // in the coordinator. A later timeout remains terminal.
            guard submitResponseRetryOrigin == .cookieRetry,
                  !cookieRefreshAfterTimeoutUsed,
                  !continuousRetryUsed,
                  !ipRetryUsed else {
                return stop(.submitResponseTimeout)
            }
            cookieRefreshAfterTimeoutUsed = true
            awaitingSubmitResponseRetry = false
            state = .waitingForCookieRefresh(generationID: eventGenerationID,
                                              attempt: attempt)
            return .startCookieRefreshAfterTimeout

        case .postCompleted:
            let canAcceptLateCompletion: Bool
            switch state {
            case .submitting:
                canAcceptLateCompletion = true
            case .waitingForSubmitReadiness(_, _, .submitResponseRetry),
                 .waitingToSubmit:
                canAcceptLateCompletion = awaitingSubmitResponseRetry
            default:
                canAcceptLateCompletion = false
            }
            guard canAcceptLateCompletion else { return .none }
            awaitingSubmitResponseRetry = false
            state = .succeeded(generationID: eventGenerationID)
            return .succeeded

        case let .fail(_, reason):
            return stop(reason)
        }
    }

    mutating func handleAlert(_ alert: AutomaticPostAlert,
                              generationID: UInt64) -> (autoDismiss: Bool,
                                                       effect: AutomaticPostFlowEffect) {
        guard generationID == self.generationID,
              case let .submitting(_, attempt) = state else {
            return (false, .none)
        }

        switch alert {
        case .threadPostingUnavailable:
            guard isMultiThread else {
                return (false, stop(.unknownAlert))
            }
            return (true, skipCurrentThread(reason: .threadPostingUnavailable))

        case .threadNotFound:
            guard isMultiThread else {
                return (false, stop(.unknownAlert))
            }
            return (true, skipCurrentThread(reason: .threadUnavailable))

        case .replyLimitReached:
            guard isMultiThread else {
                return (false, stop(.knownAlertAfterLimit))
            }
            return (true, skipCurrentThread(reason: .knownAlertAfterLimit))

        case .imageCountRestricted, .imageContinuousPosting:
            guard isSameThreadRepeat || isMultiThread else {
                return (false, stop(.unknownAlert))
            }
            state = .stopped(generationID: generationID,
                             reason: .imageCountRestricted)
            return (true, .startNextAutomaticFlow)

        case .accessRestricted:
            state = .stopped(generationID: generationID, reason: .accessRestricted)
            return (true, .startNextAutomaticFlow)

        case .continuousPosting:
            guard !continuousRetryUsed,
                  attempt < Self.maximumAttempts else {
                if isMultiThread {
                    state = .stopped(generationID: generationID,
                                     reason: .knownAlertAfterLimit)
                    awaitingSubmitResponseRetry = false
                    return (true, .handoffAfterContinuousLimit)
                }
                return (true, stop(.knownAlertAfterLimit))
            }
            continuousRetryUsed = true
            if isSameThreadRepeat || attempt == Self.regularAttemptLimit {
                continuousAPReconnectAttempts = 1
                state = .waitingForContinuousAPRetry(generationID: generationID,
                                                     attempt: attempt)
                return (true, .startContinuousAPReconnect)
            }
            state = .waitingForContinuousRetry(generationID: generationID,
                                                attempt: attempt)
            return (true, .none)

        case .cookieRetryRequired:
            guard !cookieRetryUsed,
                  !ipRetryIsTerminal,
                  !continuousRetryUsed,
                  attempt < Self.regularAttemptLimit else {
                return (true, stop(.knownAlertAfterLimit))
            }
            cookieRetryUsed = true
            state = .waitingForCookieRetry(generationID: generationID, attempt: attempt)
            return (true, .none)

        case .imagePostingRestricted:
            guard !ipRetryUsed,
                  !continuousRetryUsed,
                  attempt < Self.regularAttemptLimit else {
                return (true, stop(.knownAlertAfterLimit))
            }
            ipRetryUsed = true
            ipRetryIsTerminal = true
            state = .waitingForIPRetry(generationID: generationID, attempt: attempt)
            return (true, .startIPReconnect)
        }
    }

    mutating func stop(_ reason: AutomaticPostStopReason) -> AutomaticPostFlowEffect {
        guard let generationID else { return .none }
        awaitingSubmitResponseRetry = false
        isSceneSuspended = false
        state = .stopped(generationID: generationID, reason: reason)
        return .stopped(reason)
    }

    /// Marks the current multi-thread target as unavailable while preserving
    /// the session coordinator's ability to advance to another target. This
    /// is deliberately separate from `stop(_:)`: a missing/dead target is a
    /// per-thread condition, not a terminal batch failure.
    mutating func skipCurrentThread(reason: AutomaticPostStopReason) -> AutomaticPostFlowEffect {
        guard isMultiThread,
              isActive,
              let generationID else {
            return .none
        }
        awaitingSubmitResponseRetry = false
        isSceneSuspended = false
        state = .stopped(generationID: generationID, reason: reason)
        return .skipCurrentThread
    }

    /// Forces an active generation into a terminal state without producing a
    /// second effect. This is used by coordinator-level cancellation paths
    /// that already own the final UI/log result and must only invalidate late
    /// callbacks.
    mutating func forceTerminate(generationID: UInt64) {
        guard self.generationID == generationID, isActive else { return }
        awaitingSubmitResponseRetry = false
        isSceneSuspended = false
        state = .stopped(generationID: generationID, reason: .communicationFailure)
    }

    mutating func reset() {
        state = .idle
        generationID = nil
        pageToken = nil
        stalePageToken = nil
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        continuousAPReconnectAttempts = 0
        requiresHandwriting = false
        lastAttempt = 0
        currentSubmissionID = nil
        submitEventObserved = false
        submitResponseRetryUsed = false
        cookieRefreshAfterTimeoutUsed = false
        awaitingSubmitResponseRetry = false
        lastSubmitReadinessReason = .initial
        submitResponseRetryOrigin = nil
        isSceneSuspended = false
        isSameThreadRepeat = false
        isMultiThread = false
        apCompleted = false
        reloadCompleted = false
        cookieObserved = false
        compactReady = false
        handwritingReady = false
        preparationReason = .initial
    }

    private mutating func preparationEffectIfReady() -> AutomaticPostFlowEffect {
        guard case .preparing = state,
              apCompleted,
              reloadCompleted,
              cookieObserved,
              compactReady,
              handwritingReady else {
            return .none
        }
        state = .waitingForSubmitReadiness(generationID: generationID ?? 0,
                                           attempt: 1,
                                           reason: preparationReason)
        lastAttempt = 1
        lastSubmitReadinessReason = preparationReason
        return .startSubmitReadiness(attempt: 1, reason: preparationReason)
    }

    private mutating func beginSubmitReadiness(attempt: Int,
                                               reason: AutomaticPostReadinessReason)
        -> AutomaticPostFlowEffect {
        guard attempt <= Self.maximumAttempts,
              let generationID else {
            return stop(.retryLimit)
        }
        state = .waitingForSubmitReadiness(generationID: generationID,
                                           attempt: attempt,
                                           reason: reason)
        lastAttempt = attempt
        lastSubmitReadinessReason = reason
        return .startSubmitReadiness(attempt: attempt, reason: reason)
    }

    private mutating func beginSubmit(attempt: Int) -> AutomaticPostFlowEffect {
        guard attempt <= Self.maximumAttempts,
              let generationID else {
            return stop(.retryLimit)
        }
        state = .submitting(generationID: generationID, attempt: attempt)
        lastAttempt = attempt
        awaitingSubmitResponseRetry = false
        let nextSubmissionID = (currentSubmissionID ?? 0) &+ 1
        currentSubmissionID = nextSubmissionID == 0 ? 1 : nextSubmissionID
        submitEventObserved = false
        return .submit(attempt: attempt)
    }

    private mutating func acceptPageToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        if let pageToken {
            return pageToken == token
        }
        if stalePageToken == token {
            return false
        }
        pageToken = token
        return true
    }
}

private extension AutomaticPostFlowEvent {
    var generationID: UInt64? {
        switch self {
        case .reset:
            return nil
        case let .markAPCompleted(id),
             let .markReloadCompleted(id),
             let .markCookieObserved(id),
             let .submitReadinessObserved(id, _, _, _),
             let .submitReadinessTimedOut(id),
             let .initialSubmitDelayElapsed(id),
             let .cookieAlertDismissed(id),
             let .continuousAlertDismissed(id),
             let .submitObserved(id, _),
             let .submitResponseTimedOut(id, _),
             let .ipSubmitDelayElapsed(id),
             let .postCompleted(id),
             let .fail(id, _):
            return id
        case let .markCompactReady(id, _, _, _),
             let .markHandwritingReady(id, _, _),
             let .ipReconnectCompleted(id, _),
             let .continuousAPReconnectUnchanged(id),
             let .continuousAPReconnectCompleted(id, _):
            return id
        }
    }
}
