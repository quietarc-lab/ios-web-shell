import Foundation

enum AutomaticPostAlert: Equatable {
    case cookieRetryRequired
    case imagePostingRestricted
    case accessRestricted
    case continuousPosting
    case threadPostingUnavailable
}

enum TargetPageAlertDisposition: Equatable {
    case showNormally
    case autoDismiss
}

enum AutomaticPostStopReason: Equatable {
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
}

enum AutomaticPostReadinessReason: String, Equatable {
    case initial = "INITIAL"
    case cookieRetry = "COOKIE_RETRY"
    case ipRetry = "IP_RETRY"
    case continuousRetry = "CONTINUOUS_RETRY"
    case continuousAPRetry = "CONTINUOUS_AP_RETRY"
    case sameThreadRepeat = "SAME_THREAD_REPEAT"
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
    case startNextAutomaticFlow
    case succeeded
    case stopped(AutomaticPostStopReason)
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
    case continuousAPReconnectCompleted(generationID: UInt64, success: Bool)
    case ipSubmitDelayElapsed(generationID: UInt64)
    case postCompleted(generationID: UInt64)
    case fail(generationID: UInt64, reason: AutomaticPostStopReason)
    case reset
}

struct AutomaticPostFlowMachine {
    static let regularAttemptLimit = 3
    static let maximumAttempts = 4
    static let readinessStableMilliseconds = 500

    private(set) var state: AutomaticPostFlowState = .idle
    private(set) var generationID: UInt64?
    private(set) var pageToken: String?
    private(set) var cookieRetryUsed = false
    private(set) var ipRetryUsed = false
    private(set) var ipRetryIsTerminal = false
    private(set) var continuousRetryUsed = false
    private(set) var requiresHandwriting = false
    private(set) var lastAttempt = 0

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
             .submitting, .waitingForCookieRetry, .waitingForIPRetry,
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
             let .waitingForIPRetry(_, attempt),
             let .waitingForContinuousRetry(_, attempt),
             let .waitingForContinuousAPRetry(_, attempt):
            return attempt
        case .idle, .preparing, .succeeded, .stopped:
            return nil
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
                        hasImage: Bool) -> AutomaticPostFlowEffect {
        guard hasComment || hasImage else {
            state = .stopped(generationID: generationID, reason: .noContent)
            self.generationID = generationID
            return .stopped(.noContent)
        }

        self.generationID = generationID
        stalePageToken = oldPageToken
        pageToken = nil
        requiresHandwriting = hasImage
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        lastAttempt = 0
        apCompleted = false
        reloadCompleted = false
        cookieObserved = false
        compactReady = false
        handwritingReady = !hasImage
        state = .preparing(generationID: generationID)
        preparationReason = .initial
        return .none
    }

    mutating func beginSameThreadRepeat(generationID: UInt64,
                                        pageToken: String,
                                        hasComment: Bool,
                                        hasImage: Bool) -> AutomaticPostFlowEffect {
        guard !pageToken.isEmpty,
              hasComment || hasImage else {
            state = .stopped(generationID: generationID, reason: .noContent)
            self.generationID = generationID
            return .stopped(.noContent)
        }

        self.generationID = generationID
        stalePageToken = nil
        self.pageToken = pageToken
        requiresHandwriting = hasImage
        cookieRetryUsed = false
        ipRetryUsed = false
        ipRetryIsTerminal = false
        continuousRetryUsed = false
        lastAttempt = 0
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

    mutating func handle(_ event: AutomaticPostFlowEvent) -> AutomaticPostFlowEffect {
        if case .reset = event {
            reset()
            return .none
        }

        guard let eventGenerationID = event.generationID,
              eventGenerationID == generationID else {
            return .none
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

        case .postCompleted:
            guard case .submitting = state else { return .none }
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
            return (false, stop(.unknownAlert))

        case .accessRestricted:
            state = .stopped(generationID: generationID, reason: .accessRestricted)
            return (true, .startNextAutomaticFlow)

        case .continuousPosting:
            guard !continuousRetryUsed,
                  attempt < Self.maximumAttempts else {
                return (true, stop(.knownAlertAfterLimit))
            }
            continuousRetryUsed = true
            if attempt == Self.regularAttemptLimit {
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
        state = .stopped(generationID: generationID, reason: reason)
        return .stopped(reason)
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
        requiresHandwriting = false
        lastAttempt = 0
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
        return .startSubmitReadiness(attempt: attempt, reason: reason)
    }

    private mutating func beginSubmit(attempt: Int) -> AutomaticPostFlowEffect {
        guard attempt <= Self.maximumAttempts,
              let generationID else {
            return stop(.retryLimit)
        }
        state = .submitting(generationID: generationID, attempt: attempt)
        lastAttempt = attempt
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
             let .ipSubmitDelayElapsed(id),
             let .postCompleted(id),
             let .fail(id, _):
            return id
        case let .markCompactReady(id, _, _, _),
             let .markHandwritingReady(id, _, _),
             let .ipReconnectCompleted(id, _),
             let .continuousAPReconnectCompleted(id, _):
            return id
        }
    }
}
