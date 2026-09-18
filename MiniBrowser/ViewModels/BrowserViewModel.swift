import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    private static let standardSubmitDelayNanoseconds: UInt64 = 2_000_000_000
    static let sameThreadRepeatMinimumDelayNanoseconds: UInt64 = 250_000_000
    static let sameThreadRepeatSubmitDelayNanoseconds: UInt64 = 0
    static let multiThreadSuccessWaitNanoseconds: UInt64 = 1_000_000_000
    static let continuousAPRetryDelayNanoseconds: UInt64 = 1_000_000_000
    private static let continuousAPMinimumIntervalNanoseconds: UInt64 = 3_100_000_000
    private static let automaticSubmitResponseTimeoutNanoseconds: UInt64 = 15_000_000_000
    /// Futapo's isolation feed is polled only while the automatic session is
    /// foreground-active. The first check runs immediately; subsequent checks
    /// use this bounded interval and conditional HTTP validators.
    static let isolationMonitorIntervalNanoseconds: UInt64 = 10_000_000_000

    private enum Keys {
        static let lastURL = "lastURL"
        static let userAgentIndex = "userAgentIndex"
        static let userAgentID = "userAgentID"
        static let userAgentCatalogVersion = "userAgentCatalogVersion"
    }

    @Published var urlText = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var isUAChanging = false
    @Published private(set) var isCookieRefreshing = false
    @Published private(set) var isAPRunning = false
    @Published private(set) var isIdentityRefreshInProgress = false
    @Published private(set) var toasts: [ToastMessage] = []
    @Published private(set) var sitePostStatus: SitePostStatus? = nil
    @Published private(set) var automaticPostStatus: AutomaticPostStatus? = nil
    @Published private(set) var sameThreadRepeatEnabled = false
    @Published private(set) var multiThreadEnabled = false
    @Published private(set) var multiThreadSessionActive = false
    /// Safety stop is enabled for a fresh process but deliberately not
    /// persisted. Turning it off only affects the current process/session.
    @Published private(set) var isolationStopEnabled = true

    let bookmarkStore: BookmarkStore

    weak var webView: WKWebView?
    private let defaults: UserDefaults
    private let logStore: DebugLogStore
    private let ipService: IPAddressService
    private let userAgentRestrictionStore: UserAgentRestrictionStore
    private let isolationThreadMonitor: IsolationThreadMonitor
    private var selectedUAIndex: Int
    private var automaticTriedUAIDs: Set<Int> = []
    /// A session-only shuffled order. It is created once when an automatic
    /// flow starts and is never persisted or rebuilt during a handoff.
    private var automaticUserAgentOrder: [Int] = []
    private var automaticUserAgentOrderCursor = 0
    private var automaticPostDraft: AutomaticPostDraft?
    private var automaticPostRepeatSession: AutomaticPostRepeatSession?
    private var automaticPostRepeatSessionID: UInt64 = 0
    private var automaticPostRepeatDelayTask: Task<Void, Never>?
    private var automaticContinuousAPRetryDelayTask: Task<Void, Never>?
    private var multiThreadSession: MultiThreadPostSession?
    private var multiThreadSessionID: UInt64 = 0
    private var multiThreadTransitionTask: Task<Void, Never>?
    private var pendingMultiThreadNavigation: (sessionID: UInt64, target: CatalogPostTarget)?
    /// Monotonically identifies each WebView navigation. A destination
    /// availability probe must not be allowed to settle a later reload or
    /// redirect that happens to reuse the same thread URL.
    private var multiThreadNavigationSequence: UInt64 = 0
    private struct PendingMultiThreadAvailabilityProbe: Equatable {
        let sessionID: UInt64
        let targetID: String
        let pageURL: URL
        let navigationSequence: UInt64
    }
    private var pendingMultiThreadAvailabilityProbe: PendingMultiThreadAvailabilityProbe?
    /// A dropped target can report that it has no usable thread/form before
    /// `didFinish` creates the next page generation. Keep that bridge result
    /// tied to the pending destination until navigation is committed.
    private struct PendingMultiThreadUnavailable: Equatable {
        let sessionID: UInt64
        let targetID: String
        let pageToken: String
        let pageURL: URL
        let reason: String
    }
    private var pendingMultiThreadUnavailable: PendingMultiThreadUnavailable?
    private weak var automaticCatalogProvider: AutomaticCatalogProvider?
    private var pendingCookieRefresh: PendingCookieRefresh?
    private var pendingAP: PendingAP?
    private var lastRelatedCookieCountByHost: [String: Int] = [:]
    private var automaticPostMachine = AutomaticPostFlowMachine()
    private var automaticPostGeneration: UInt64 = 0
    /// Submission identities are monotonic for the lifetime of the WebView
    /// model. They must not restart at one when a new page generation begins,
    /// otherwise a delayed marker from an older generation can be accepted by
    /// a newer request on the same document.
    private var automaticSubmissionSequence: UInt64 = 0
    private var pendingUAChangeGeneration: UInt64?
    private var automaticReloadGeneration: UInt64?
    private var automaticPostPreparationTimer: Task<Void, Never>?
    private var automaticSubmitReadinessTask: Task<Void, Never>?
    private var automaticSubmitResponseTimer: Task<Void, Never>?
    private var automaticPostStatusTask: Task<Void, Never>?
    private var latestCompactReady: (pageURL: URL?, pageToken: String, hasComment: Bool, canSubmit: Bool)?
    /// Bridge readiness can arrive before WKNavigationDelegate.didFinish for
    /// a newly selected catalog target. Keep it associated with the frame URL
    /// until the matching generation owns the page; never replay it globally.
    private var pendingHandwritingReady: (pageURL: URL?, pageToken: String, ready: Bool)?
    /// A canvas restoration started before a multi-thread destination finished
    /// loading has no generation ID to embed in its asynchronous callback. Keep
    /// the request identity long enough to bind that one callback to the new
    /// generation after navigation completes.
    private struct PendingHandwritingRestore: Equatable {
        let pageURL: URL
        let pageToken: String
    }
    private var pendingHandwritingRestore: PendingHandwritingRestore?
    /// A multi-thread destination with a captured comment must not accept an
    /// empty/different early compactReady signal while its draft restoration
    /// script is still running.
    private var automaticDraftRestorePendingGeneration: UInt64?
    private var automaticSubmitReadinessStableSince: Date?
    private var automaticSubmitReadinessDeadline: Date?
    private var automaticSubmitReadinessLastReason: String?
    private var automaticSubmitReadinessFalseLogged = false
    private var automaticSubmitReadinessReason: AutomaticPostReadinessReason?
    private var automaticContinuousAPCompletedUptimeNanoseconds: UInt64?
    private var handwritingImageAvailable = false
    private var automaticCookieRelatedCount: Int?
    private var automaticCookieCountDelta: Int?
    private var automaticAPResult = "NOT_REQUESTED"
    private var automaticEventSequence: UInt64 = 0
    private var automaticGenerationStartedAt: [UInt64: Date] = [:]
    private var automaticFinishedGenerations: Set<UInt64> = []
    private var automaticPostAccepted = false
    private var automaticOwnResponseConfirmed = false
    private var automaticAcceptedPageToken: String?
    private var automaticPostVerificationTask: Task<Void, Never>?
    private var appSceneIsActive = false
    private enum IsolationMonitorMode: Equatable, Sendable {
        case sameThread
        case multiThread
    }
    private struct IsolationMonitorContext: Equatable, Sendable {
        let sessionID: UInt64
        let mode: IsolationMonitorMode
        let targetThreadIDs: Set<String>
    }
    private var isolationMonitorContext: IsolationMonitorContext?
    private var isolationMonitorTask: Task<Void, Never>?
    private var isolationMonitorFailureLogged = false

    private struct AutomaticPostDraft {
        let hasComment: Bool
        let comment: String?
        let hasImage: Bool
    }

    private struct AutomaticPostRepeatSession {
        let sessionID: UInt64
        var cycle: Int
        let pageURL: URL
        var pageToken: String?
        let comment: String?
        let hasImage: Bool
        var stopRequested: Bool
    }

    private struct PendingMultiThreadBootstrap {
        let snapshot: CatalogPostSnapshot
        let pageURL: URL
        let imageAvailable: Bool
    }

    private struct AutomaticLogContext {
        let generationID: UInt64
        let sequence: UInt64
        let elapsedMilliseconds: Int
    }

    private struct MultiThreadLogContext {
        let sessionID: UInt64
        let targetIndex: Int
        let threadID: String?
    }

    private struct PendingCookieRefresh {
        let host: String
        let beforeCount: Int
        let deletedCount: Int
        let deletionConfirmed: Bool
        let identityRefresh: Bool
        let automaticGenerationID: UInt64?
    }

    private enum APPurpose {
        case manual
        case identityRefresh(generationID: UInt64)
        case automaticIPRetry(generationID: UInt64)
        case automaticContinuousRetry(generationID: UInt64)
    }

    private struct PendingAP {
        let beforeIPv4: String?
        let reloadAfterCompletion: Bool
        let purpose: APPurpose
    }

    init(defaults: UserDefaults = .standard,
         ipService: IPAddressService = IPAddressService(),
         isolationThreadMonitor: IsolationThreadMonitor = IsolationThreadMonitor()) {
        self.defaults = defaults
        self.logStore = DebugLogStore(defaults: defaults)
        self.bookmarkStore = BookmarkStore(defaults: defaults)
        self.ipService = ipService
        self.userAgentRestrictionStore = UserAgentRestrictionStore(defaults: defaults)
        self.isolationThreadMonitor = isolationThreadMonitor
        let catalogNeedsMigration = defaults.integer(forKey: Keys.userAgentCatalogVersion) !=
            BrowserUserAgent.catalogVersion
        let savedID = defaults.object(forKey: Keys.userAgentID) as? Int
        let savedIDIndex = savedID.flatMap { savedID in
            BrowserUserAgent.all.firstIndex(where: { $0.id == savedID })
        }
        let savedIndexValue = defaults.object(forKey: Keys.userAgentIndex) as? Int
        if let savedIndex = savedIDIndex {
            self.selectedUAIndex = savedIndex
        } else {
            let savedIndex = defaults.integer(forKey: Keys.userAgentIndex)
            self.selectedUAIndex = BrowserUserAgent.all.indices.contains(savedIndex) ? savedIndex : 0
        }
        // Catalog updates are append-only. Preserve a valid saved ID and all
        // seven-day restriction entries, including legacy generated keys;
        // only repair the index/ID pair when the saved profile no longer
        // exists.
        if catalogNeedsMigration || savedIDIndex == nil ||
            savedIndexValue != selectedUAIndex ||
            savedID != BrowserUserAgent.all[selectedUAIndex].id {
            defaults.set(selectedUAIndex, forKey: Keys.userAgentIndex)
            defaults.set(BrowserUserAgent.all[selectedUAIndex].id, forKey: Keys.userAgentID)
        }
        defaults.set(BrowserUserAgent.catalogVersion, forKey: Keys.userAgentCatalogVersion)
        // Reading the restriction set also removes expired entries, without
        // changing valid IDs during an additive catalog migration.
        _ = userAgentRestrictionStore.restrictedIDs()
        logStore.append(action: "User Agent Catalog Ready", fields: [
            ("CATALOG_COUNT", String(BrowserUserAgent.all.count)),
            ("RESULT", "READY")
        ])
    }

    var currentUserAgent: BrowserUserAgent {
        BrowserUserAgent.all[selectedUAIndex]
    }

    /// The fixed catalog value used for every request in the current process.
    var effectiveUserAgent: String {
        currentUserAgent.value
    }

    var userAgentButtonTitle: String {
        let available = availableUserAgentIndices()
        let position = available.firstIndex(of: selectedUAIndex).map { $0 + 1 } ?? 0
        return "UA \(position)/\(available.count)"
    }

    private var effectiveUserAgentLogLabel: String {
        let available = availableUserAgentIndices()
        let position = available.firstIndex(of: selectedUAIndex).map { $0 + 1 } ?? 0
        return "\(position)/\(available.count) \(currentUserAgent.name)"
    }

    private func availableUserAgentIndices() -> [Int] {
        let restricted = userAgentRestrictionStore.restrictedIDs()
        return BrowserUserAgent.all.indices.filter {
            !restricted.contains(BrowserUserAgent.all[$0].id)
        }
    }

    func attachAutomaticCatalogProvider(_ provider: AutomaticCatalogProvider) {
        automaticCatalogProvider = provider
    }

    func attach(webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView
        webView.customUserAgent = effectiveUserAgent

        if let saved = defaults.string(forKey: Keys.lastURL),
           let url = URLNormalizer.normalize(saved) {
            urlText = url.absoluteString
            webView.load(URLRequest(url: url))
        }
    }

    func openURLFromField() {
        guard !multiThreadSessionActive else { return }
        guard let url = URLNormalizer.normalize(urlText) else {
            showToast("URLを確認してください", kind: .failure)
            return
        }
        urlText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func openThreadListThread(_ url: URL) {
        guard !multiThreadSessionActive else { return }
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "img.2chan.net",
              url.path.range(of: #"^/[^/]+/res/\d+\.htm$"#,
                             options: .regularExpression) != nil else {
            showToast("スレURLを確認してください", kind: .failure)
            return
        }
        urlText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        guard !multiThreadSessionActive else { return }
        webView?.goBack()
    }

    func goForward() {
        guard !multiThreadSessionActive else { return }
        webView?.goForward()
    }

    func reload() {
        guard !multiThreadSessionActive else { return }
        webView?.reload()
    }

    func cycleUserAgent() {
        guard !multiThreadSessionActive else { return }
        guard !isIdentityRefreshInProgress,
              !isUAChanging,
              !isCookieRefreshing,
              !isAPRunning,
              !isLoading,
              let webView,
              let pageURL = webView.url,
              pageURL.host != nil else {
            showToast("UA更新を開始できません", kind: .warning)
            return
        }
        cancelAutomaticRepeatSession()
        isUAChanging = true
        automaticPostGeneration &+= 1
        let generationID = automaticPostGeneration
        pendingUAChangeGeneration = generationID
        let oldPageToken = latestCompactReady?.pageToken
        let imageAvailable = handwritingImageAvailable

        let multiBootstrap: PendingMultiThreadBootstrap?
        if multiThreadEnabled,
           let provider = automaticCatalogProvider {
            let snapshot = provider.currentPostSnapshot(limit: 60)
            multiBootstrap = snapshot.targets.isEmpty
                ? nil
                : PendingMultiThreadBootstrap(snapshot: snapshot,
                                               pageURL: pageURL,
                                               imageAvailable: imageAvailable)
        } else {
            multiBootstrap = nil
        }

        // Read the current draft before changing the UA. This is deliberately
        // read-only: it never submits or mutates the page.
        webView.evaluateJavaScript(CompactPageModeService.currentPostStateScript) {
            [weak self] result, error in
            guard let self,
                  self.pendingUAChangeGeneration == generationID else { return }
            let state = Self.postState(from: result)
            let hasComment = state?.hasComment ?? false
            let comment = state?.comment
            let canSubmit = state?.canSubmit ?? false
            let isTarget = Self.isTargetThreadURL(pageURL)
            let hasContent = hasComment || imageAvailable
            let shouldStartMulti = self.multiThreadEnabled &&
                multiBootstrap != nil && isTarget && canSubmit && hasContent
            if shouldStartMulti,
               let multiBootstrap {
                self.beginMultiThreadSession(
                    snapshot: multiBootstrap.snapshot,
                    comment: comment,
                    hasImage: imageAvailable,
                    currentPageURL: pageURL
                )
                if self.multiThreadSession?.currentTarget?.threadURL.path != pageURL.path {
                    return
                }
            }
            let shouldStartAutomatic = isTarget && canSubmit && hasContent &&
                (shouldStartMulti || !multiThreadEnabled)
            self.startUserAgentChange(
                pageURL: pageURL,
                generationID: generationID,
                oldPageToken: oldPageToken,
                hasComment: hasComment,
                comment: comment,
                hasImage: imageAvailable,
                automatic: shouldStartAutomatic,
                readError: error != nil,
                targetUAIndex: nil,
                excludedUAIDs: [],
                newAutomaticSession: true,
                multiThread: shouldStartMulti,
                sameThreadRepeat: shouldStartAutomatic &&
                    sameThreadRepeatEnabled &&
                    !shouldStartMulti
            )
        }
    }

    func toggleMultiThread() {
        if multiThreadEnabled {
            multiThreadEnabled = false
            guard var session = multiThreadSession else { return }
            session.stopRequested = true
            multiThreadSession = session
            // A click already dispatched to the site is allowed to finish,
            // but OFF must revoke every unsent readiness/retry/transition
            // effect. Otherwise a delayed bridge callback could authorize a
            // new click after the user has disabled the mode.
            switch automaticPostMachine.state {
            case .submitting:
                break
            case .succeeded:
                if let generationID = automaticPostMachine.generationID {
                    finishMultiThreadSession(generationID: generationID,
                                             result: "STOPPED_MULTI_THREAD_DISABLED")
                }
            case .idle:
                finishMultiThreadSession(generationID: nil,
                                         result: "STOPPED_MULTI_THREAD_DISABLED")
            case .stopped:
                finishMultiThreadSession(
                    generationID: automaticPostMachine.generationID,
                    result: "STOPPED_MULTI_THREAD_DISABLED"
                )
            case .preparing, .waitingForSubmitReadiness, .waitingToSubmit,
                 .waitingForCookieRetry, .waitingForCookieRefresh,
                 .waitingForIPRetry,
                 .waitingForContinuousRetry, .waitingForContinuousAPRetry:
                let effect = automaticPostMachine.stop(.repeatDisabled)
                if let generationID = automaticPostMachine.generationID {
                    handleAutomaticPostEffect(effect, generationID: generationID)
                } else {
                    finishMultiThreadSession(generationID: nil,
                                             result: "STOPPED_MULTI_THREAD_DISABLED")
                }
            }
            return
        }

        // The two modes are mutually exclusive. The UI disables this button
        // while same-thread repeat is active, but keeping the invariant here
        // also protects programmatic callers and future entry points.
        if sameThreadRepeatEnabled {
            sameThreadRepeatEnabled = false
            cancelAutomaticRepeatSession()
        }
        multiThreadEnabled = true
    }

    private func beginMultiThreadSession(snapshot: CatalogPostSnapshot,
                                         comment: String?,
                                         hasImage: Bool,
                                         currentPageURL: URL) {
        guard !snapshot.targets.isEmpty else { return }
        multiThreadSessionID &+= 1
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = nil
        let session = MultiThreadPostSession(
            sessionID: multiThreadSessionID,
            snapshot: snapshot,
            comment: comment,
            hasImage: hasImage
        )
        multiThreadSession = session
        multiThreadSessionActive = true
        pendingMultiThreadUnavailable = nil
        updateIsolationMonitoring()
        updateIdleTimerState()
        automaticPostDraft = AutomaticPostDraft(
            hasComment: comment?.isEmpty == false,
            comment: comment,
            hasImage: hasImage
        )

        guard let target = session.currentTarget else {
            finishMultiThreadSession(generationID: automaticPostMachine.generationID,
                                     result: "STOPPED_NO_CONTENT")
            return
        }
        let samePage = target.threadURL.path == currentPageURL.path &&
            target.threadURL.host?.lowercased() == currentPageURL.host?.lowercased()
        guard !samePage else { return }
        pendingMultiThreadNavigation = (session.sessionID, target)
        pendingMultiThreadUnavailable = nil
        setMultiThreadStatusWithoutGeneration(.navigatingToNextThread)
        guard webView?.load(URLRequest(url: target.threadURL)) != nil else {
            pendingMultiThreadNavigation = nil
            skipPendingMultiThreadTargetWithoutGeneration(
                sessionID: session.sessionID,
                target: target,
                reason: "NAVIGATION_LOAD_FAILED"
            )
            return
        }
    }

    private func nextEligibleUserAgentIndex(after index: Int,
                                            excluding excludedUAIDs: Set<Int>) -> Int? {
        let restrictedUAIDs = userAgentRestrictionStore.restrictedIDs()
        guard !BrowserUserAgent.all.isEmpty else { return nil }
        for offset in 1...BrowserUserAgent.all.count {
            let candidateIndex = (index + offset) % BrowserUserAgent.all.count
            let candidateID = BrowserUserAgent.all[candidateIndex].id
            guard !excludedUAIDs.contains(candidateID),
                  !restrictedUAIDs.contains(candidateID) else {
                continue
            }
            return candidateIndex
        }
        return nil
    }

    private func nextAutomaticUserAgentIndex(excluding excludedUAIDs: Set<Int>) -> Int? {
        let restrictedUAIDs = userAgentRestrictionStore.restrictedIDs()
        while automaticUserAgentOrderCursor < automaticUserAgentOrder.count {
            let candidateIndex = automaticUserAgentOrder[automaticUserAgentOrderCursor]
            automaticUserAgentOrderCursor += 1
            let candidateID = BrowserUserAgent.all[candidateIndex].id
            guard !excludedUAIDs.contains(candidateID),
                  !restrictedUAIDs.contains(candidateID) else {
                continue
            }
            return candidateIndex
        }
        return nil
    }

    private func prepareAutomaticUserAgentOrder() {
        automaticUserAgentOrder = AutomaticUserAgentRotation.makeOrder(
            catalog: BrowserUserAgent.all,
            restrictedIDs: userAgentRestrictionStore.restrictedIDs()
        )
        automaticUserAgentOrderCursor = 0
    }

    private func nextAutomaticSubmissionSeed() -> UInt64 {
        automaticSubmissionSequence &+= 1
        if automaticSubmissionSequence == 0 {
            automaticSubmissionSequence = 1
        }
        return automaticSubmissionSequence
    }

    private func startNextAutomaticFlow(previousGenerationID: UInt64) {
        guard automaticPostMachine.generationID == previousGenerationID,
              let draft = automaticPostDraft ?? multiThreadSession.map({
                  AutomaticPostDraft(hasComment: $0.comment?.isEmpty == false,
                                     comment: $0.comment,
                                     hasImage: $0.hasImage)
              }),
              let webView,
              let pageURL = webView.url,
              Self.isTargetThreadURL(pageURL) else {
            setAutomaticPostStatus(.stopped, generationID: previousGenerationID)
            if multiThreadSession != nil {
                finishMultiThreadSession(generationID: previousGenerationID,
                                         result: "STOPPED_NO_AVAILABLE_UA")
            } else {
                finishAutomaticPost(generationID: previousGenerationID,
                                    result: "STOPPED_NO_AVAILABLE_UA")
            }
            return
        }
        if automaticUserAgentOrder.isEmpty {
            prepareAutomaticUserAgentOrder()
        }
        guard let nextIndex = nextAutomaticUserAgentIndex(
            excluding: automaticTriedUAIDs
        ) else {
            appendAutomaticEvent(
                generationID: previousGenerationID,
                phase: "FLOW",
                event: "NO_AVAILABLE_UA",
                result: "STOPPED"
            )
            setAutomaticPostStatus(.stopped, generationID: previousGenerationID)
            if multiThreadSession != nil {
                finishMultiThreadSession(generationID: previousGenerationID,
                                         result: "STOPPED_NO_AVAILABLE_UA")
            } else {
                finishAutomaticPost(generationID: previousGenerationID,
                                    result: "STOPPED_NO_AVAILABLE_UA")
            }
            return
        }

        setAutomaticPostStatus(.switchingAfterAccessRestriction,
                               generationID: previousGenerationID)
        let oldPageToken = automaticPostMachine.pageToken ?? latestCompactReady?.pageToken
        let continueSameThreadRepeat = sameThreadRepeatEnabled &&
            automaticPostRepeatSession != nil &&
            !automaticPostMachine.isMultiThread
        automaticPostGeneration &+= 1
        let nextGenerationID = automaticPostGeneration
        startUserAgentChange(
            pageURL: pageURL,
            generationID: nextGenerationID,
            oldPageToken: oldPageToken,
            hasComment: draft.hasComment,
            comment: draft.comment,
            hasImage: draft.hasImage,
            automatic: true,
            readError: false,
            targetUAIndex: nextIndex,
            excludedUAIDs: automaticTriedUAIDs,
            newAutomaticSession: false,
            multiThread: automaticPostMachine.isMultiThread,
            sameThreadRepeat: continueSameThreadRepeat
        )
    }

    /// Rebuilds only the Cookie/page preparation after the single response
    /// retry has also timed out following a Cookie alert. No UA or AP change
    /// is performed here; a new generation invalidates late callbacks from
    /// the failed submission while the in-memory draft and session remain.
    private func startAutomaticCookieRefreshAfterTimeout(
        previousGenerationID: UInt64
    ) {
        guard automaticPostMachine.generationID == previousGenerationID,
              automaticPostMachine.isActive,
              !isCookieRefreshing,
              pendingCookieRefresh == nil,
              pendingAP == nil,
              let webView,
              let pageURL = webView.url,
              Self.isTargetThreadURL(pageURL),
              let draft = automaticPostDraft ?? multiThreadSession.map({
                  AutomaticPostDraft(
                      hasComment: $0.comment?.isEmpty == false,
                      comment: $0.comment,
                      hasImage: $0.hasImage
                  )
              }) else {
            let effect = automaticPostMachine.stop(.communicationFailure)
            handleAutomaticPostEffect(effect, generationID: previousGenerationID)
            return
        }

        let wasMultiThread = automaticPostMachine.isMultiThread
        let wasSameThreadRepeat = automaticPostMachine.isSameThreadRepeat
        let oldPageToken = automaticPostMachine.pageToken

        automaticFinishedGenerations.insert(previousGenerationID)
        automaticPostMachine.forceTerminate(generationID: previousGenerationID)
        automaticPostPreparationTimer?.cancel()
        automaticPostPreparationTimer = nil
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        cancelAutomaticSubmitResponseTimer()
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        cancelAutomaticContinuousAPRetryDelay()
        automaticPostStatusTask?.cancel()
        automaticPostStatusTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        automaticCookieRelatedCount = nil
        automaticCookieCountDelta = nil
        automaticAPResult = "NOT_REQUESTED"
        latestCompactReady = nil
        pendingHandwritingReady = nil
        pendingHandwritingRestore = nil
        pendingMultiThreadAvailabilityProbe = nil
        pendingMultiThreadUnavailable = nil
        pendingUAChangeGeneration = nil
        automaticReloadGeneration = nil
        isUAChanging = false
        isIdentityRefreshInProgress = false

        automaticPostGeneration &+= 1
        let generationID = automaticPostGeneration
        automaticPostMachine.reset()
        let beginEffect = automaticPostMachine.begin(
            generationID: generationID,
            oldPageToken: oldPageToken,
            hasComment: draft.hasComment,
            hasImage: draft.hasImage,
            multiThread: wasMultiThread,
            sameThreadRepeat: wasSameThreadRepeat,
            cookieRefreshAfterTimeoutUsed: true,
            submissionIDSeed: nextAutomaticSubmissionSeed()
        )
        automaticPostDraft = draft
        if wasMultiThread, var session = multiThreadSession {
            session.currentGenerationID = generationID
            session.currentTargetID = session.currentTarget?.id
            multiThreadSession = session
        }
        beginAutomaticGenerationLogging(generationID: generationID)
        automaticDraftRestorePendingGeneration = draft.comment?.isEmpty == false
            ? generationID
            : nil
        automaticReloadGeneration = generationID
        setAutomaticPostStatus(.checkingCookie, generationID: generationID)
        startAutomaticPostPreparationTimeout(generationID: generationID)

        if case let .stopped(reason) = beginEffect {
            handleAutomaticPostEffect(.stopped(reason), generationID: generationID)
            return
        }
        let apEffect = automaticPostMachine.handle(
            .markAPCompleted(generationID: generationID)
        )
        handleAutomaticPostEffect(apEffect, generationID: generationID)

        appendAutomaticEvent(
            generationID: generationID,
            phase: "COOKIE",
            event: "TIMEOUT_COOKIE_REFRESH_STARTED",
            result: "STARTED",
            fields: [
                ("SOURCE_GENERATION_ID", String(previousGenerationID)),
                ("AP_PURPOSE", "NOT_REQUESTED")
            ]
        )
        isCookieRefreshing = true
        Task { [weak self] in
            await self?.deleteRelatedCookiesForRefresh(
                identityRefresh: false,
                automaticGenerationID: generationID,
                reloadWhenNoCookie: true
            )
        }
        updateIdleTimerState()
    }

    func toggleSameThreadRepeat() {
        guard !multiThreadSessionActive else { return }
        if !sameThreadRepeatEnabled {
            multiThreadEnabled = false
        }
        sameThreadRepeatEnabled.toggle()
        guard var session = automaticPostRepeatSession else { return }
        session.stopRequested = !sameThreadRepeatEnabled
        automaticPostRepeatSession = session

        guard !sameThreadRepeatEnabled,
              case .succeeded = automaticPostMachine.state,
              let generationID = automaticPostMachine.generationID else {
            return
        }
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        setAutomaticPostStatus(.completed, generationID: generationID)
        finishAutomaticPost(generationID: generationID,
                            result: "STOPPED_REPEAT_DISABLED")
    }

    /// Toggles the session-only safety stop driven by Futapo's isolation
    /// feed. It remains available while an automatic session is running so a
    /// user can explicitly opt out or opt back in without changing the post
    /// state machine. Re-enabling performs an immediate foreground check.
    func toggleIsolationStop() {
        isolationStopEnabled.toggle()
        if isolationStopEnabled {
            updateIsolationMonitoring(forceCheck: true)
        } else {
            stopIsolationMonitoring(clearContext: false)
        }
    }

    func refreshCookies() {
        guard !isCookieRefreshing,
              !isIdentityRefreshInProgress,
              !isLoading,
              webView?.url?.host != nil else {
            showToast("Cookie確認失敗", kind: .warning)
            return
        }

        isCookieRefreshing = true
        Task { [weak self] in
            await self?.deleteRelatedCookiesForRefresh(identityRefresh: false,
                                                       automaticGenerationID: nil)
        }
    }

    private func startUserAgentChange(pageURL: URL?,
                                      generationID: UInt64,
                                      oldPageToken: String?,
                                      hasComment: Bool,
                                      comment: String?,
                                      hasImage: Bool,
                                      automatic: Bool,
                                      readError: Bool,
                                      targetUAIndex: Int?,
                                      excludedUAIDs: Set<Int>,
                                      newAutomaticSession: Bool,
                                      multiThread: Bool = false,
                                      sameThreadRepeat: Bool = false) {
        guard let webView else {
            isUAChanging = false
            if multiThreadSession != nil {
                finishMultiThreadSession(generationID: nil,
                                         result: "STOPPED_WEBVIEW_UNAVAILABLE")
            }
            return
        }
        isUAChanging = true
        pendingUAChangeGeneration = nil

        if newAutomaticSession {
            automaticTriedUAIDs.removeAll()
            prepareAutomaticUserAgentOrder()
            // The UA that was already active when the user pressed the
            // automatic button is not a new session candidate. This keeps a
            // handoff from immediately returning to the same profile.
            automaticTriedUAIDs.insert(currentUserAgent.id)
        }
        let nextIndex: Int?
        if let targetUAIndex {
            nextIndex = targetUAIndex
        } else if automatic {
            if automaticUserAgentOrder.isEmpty {
                prepareAutomaticUserAgentOrder()
            }
            nextIndex = nextAutomaticUserAgentIndex(excluding: automaticTriedUAIDs)
        } else {
            nextIndex = nextEligibleUserAgentIndex(
                after: selectedUAIndex,
                excluding: excludedUAIDs
            )
        }
        guard let nextIndex else {
            isUAChanging = false
            if multiThreadSession != nil {
                appendAutomaticEvent(
                    generationID: automaticPostMachine.generationID ?? automaticPostGeneration,
                    phase: "FLOW",
                    event: "NO_AVAILABLE_UA",
                    result: "STOPPED"
                )
                finishMultiThreadSession(
                    generationID: automaticPostMachine.generationID,
                    result: "STOPPED_NO_AVAILABLE_UA"
                )
            } else {
                showToast("利用可能なUAがありません", kind: .warning)
            }
            return
        }
        selectedUAIndex = nextIndex
        defaults.set(selectedUAIndex, forKey: Keys.userAgentIndex)
        defaults.set(currentUserAgent.id, forKey: Keys.userAgentID)
        if automatic,
           multiThread,
           !newAutomaticSession,
           var session = multiThreadSession {
            // A restriction handoff or the scheduled two-target UA rotation
            // starts a fresh UA batch. The in-memory draft/session itself is
            // retained, but accepted-post counting begins at zero again.
            session.resetUserAgentPostCount()
            multiThreadSession = session
        }
        if automatic {
            automaticTriedUAIDs.insert(currentUserAgent.id)
            if let session = multiThreadSession, multiThread {
                automaticPostDraft = AutomaticPostDraft(
                    hasComment: session.comment?.isEmpty == false,
                    comment: session.comment,
                    hasImage: session.hasImage
                )
            } else {
                automaticPostDraft = AutomaticPostDraft(hasComment: hasComment,
                                                         comment: comment,
                                                         hasImage: hasImage)
            }
            if newAutomaticSession,
               sameThreadRepeatEnabled,
               !multiThread,
               let pageURL,
               Self.isTargetThreadURL(pageURL) {
                automaticPostRepeatSessionID &+= 1
                automaticPostRepeatSession = AutomaticPostRepeatSession(
                    sessionID: automaticPostRepeatSessionID,
                    cycle: 1,
                    pageURL: pageURL,
                    pageToken: nil,
                    comment: comment?.isEmpty == false ? comment : nil,
                    hasImage: hasImage,
                    stopRequested: false
                )
            }
        } else {
            automaticTriedUAIDs.removeAll()
            automaticPostDraft = nil
            cancelAutomaticRepeatSession()
        }
        webView.customUserAgent = effectiveUserAgent
        isIdentityRefreshInProgress = true

        automaticPostPreparationTimer?.cancel()
        automaticSubmitReadinessTask?.cancel()
        cancelAutomaticSubmitResponseTimer()
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        cancelAutomaticContinuousAPRetryDelay()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        automaticPostStatusTask?.cancel()
        automaticPostStatusTask = nil
        latestCompactReady = nil
        pendingHandwritingReady = nil
        pendingHandwritingRestore = nil
        pendingMultiThreadAvailabilityProbe = nil
        pendingMultiThreadUnavailable = nil
        automaticDraftRestorePendingGeneration = nil
        automaticCookieRelatedCount = nil
        automaticCookieCountDelta = nil
        automaticAPResult = automatic ? "PENDING" : "NOT_REQUESTED"

        automaticPostMachine.reset()
        if automatic && !readError {
            let submissionIDSeed = nextAutomaticSubmissionSeed()
            _ = automaticPostMachine.begin(generationID: generationID,
                                            oldPageToken: oldPageToken,
                                            hasComment: multiThread
                                                ? (multiThreadSession?.comment?.isEmpty == false)
                                                : hasComment,
                                            hasImage: multiThread
                                                ? (multiThreadSession?.hasImage ?? hasImage)
                                                : hasImage,
                                            multiThread: multiThread,
                                            sameThreadRepeat: sameThreadRepeat,
                                            submissionIDSeed: submissionIDSeed)
            if var session = multiThreadSession, multiThread {
                session.currentGenerationID = generationID
                session.currentTargetID = session.currentTarget?.id
                multiThreadSession = session
            }
            beginAutomaticGenerationLogging(generationID: generationID)
            setAutomaticPostStatus(.preparingUA, generationID: generationID)
            startAutomaticPostPreparationTimeout(generationID: generationID)
        }
        updateIsolationMonitoring()
        updateIdleTimerState()

        showToast("UA変更後にCookie更新とAP再接続を開始します", kind: .success)
        var userAgentFields = [
            ("URL", LogSanitizer.url(pageURL)),
            ("UA", effectiveUserAgentLogLabel),
            ("FLOW_MODE", automatic && !readError ? "AUTOMATIC" : "MANUAL"),
            ("AUTO_CANDIDATE", automatic ? "YES" : "NO"),
            ("READ_STATE", readError ? "FAILED" : "OK"),
            ("HAS_COMMENT", hasComment ? "YES" : "NO"),
            ("HAS_IMAGE", hasImage ? "YES" : "NO"),
            ("TARGET_PAGE", Self.isTargetThreadURL(pageURL) ? "YES" : "NO"),
            ("RESULT", "CHANGED")
        ]
        if automatic && !readError,
           let context = automaticLogContext(generationID: generationID) {
            userAgentFields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "FLOW",
                event: "UA_CHANGED",
                result: "CHANGED"
            ), at: 0)
        }
        logStore.append(action: "User Agent Change", fields: userAgentFields)

        Task { [weak self] in
            await self?.deleteRelatedCookiesForRefresh(
                identityRefresh: true,
                automaticGenerationID: automatic && !readError ? generationID : nil
            )
        }
    }

    func startCellularReconnect() {
        startCellularReconnect(reloadAfterCompletion: false, purpose: .manual)
    }

    private func startCellularReconnect(reloadAfterCompletion: Bool,
                                        purpose: APPurpose) {
        guard !isAPRunning else { return }
        isAPRunning = true

        Task { [weak self] in
            guard let self else { return }
            let before = try? await ipService.fetchIPv4(userAgent: effectiveUserAgent)
            self.pendingAP = PendingAP(beforeIPv4: before,
                                       reloadAfterCompletion: reloadAfterCompletion,
                                       purpose: purpose)

            guard let shortcutURL = Self.cellularReconnectURL(),
                  await Self.openExternalURL(shortcutURL) else {
                self.finishAPFailure(status: "SHORTCUT_OPEN_FAILED",
                                     before: before,
                                     reloadAfterCompletion: reloadAfterCompletion,
                                     purpose: purpose)
                return
            }
        }
    }

    func openBookmark(_ item: BookmarkItem) {
        guard !multiThreadSessionActive else { return }
        switch item.kind {
        case .url:
            guard let url = URLNormalizer.normalize(item.content) else {
                showToast("URLを確認してください", kind: .failure)
                return
            }
            urlText = url.absoluteString
            webView?.load(URLRequest(url: url))
        case .bookmarklet:
            executeBookmarklet(item.content)
        }
    }

    func validateBookmarklet(_ source: String) {
        let script = Self.bookmarkletScript(from: source)
        guard let literal = Self.javaScriptStringLiteral(script) else {
            showToast("Bookmarklet構文を確認してください", kind: .warning)
            return
        }
        webView?.evaluateJavaScript("new Function(\(literal)); true;") { [weak self] _, error in
            if error != nil {
                self?.showToast("Bookmarklet構文を確認してください", kind: .warning)
            }
        }
    }

    func copyDebugLog() {
        let text = logStore.plainText(limit: 50)
        guard !text.isEmpty else {
            showToast("ログなし", kind: .warning)
            return
        }
        UIPasteboard.general.string = text
        showToast("ログをコピーしました", kind: .success)
    }

    func contentBlockerFailed(error: Error) {
        logStore.append(action: "Content Blocker Setup", fields: [
            ("ERROR_DOMAIN", (error as NSError).domain),
            ("ERROR_CODE", String((error as NSError).code)),
            ("DETAIL", error.localizedDescription),
            ("RESULT", "FAILED")
        ])
        showToast("広告ブロック初期化失敗", kind: .warning)
    }

    func navigationStarted() {
        multiThreadNavigationSequence &+= 1
        if multiThreadSession != nil,
           pendingMultiThreadNavigation == nil,
           let generationID = automaticPostMachine.generationID {
            let expectedIdentityReload = automaticPostMachine.isActive &&
                automaticReloadGeneration == generationID
            if !expectedIdentityReload {
                finishMultiThreadSession(generationID: generationID,
                                         result: "STOPPED_PAGE_NAVIGATION")
            }
        }
        if automaticPostMachine.isActive,
           let generationID = automaticPostMachine.generationID,
           automaticReloadGeneration != generationID {
            stopAutomaticPost(.preparationFailed, generationID: generationID)
        }
        if automaticPostRepeatSession != nil,
           automaticReloadGeneration == nil,
           case .succeeded = automaticPostMachine.state,
           let generationID = automaticPostMachine.generationID {
            setAutomaticPostStatus(.stopped, generationID: generationID)
            finishAutomaticPost(generationID: generationID,
                                result: "STOPPED_PAGE_NAVIGATION")
        }
        automaticReloadGeneration = nil
        if pendingMultiThreadNavigation == nil {
            pendingMultiThreadUnavailable = nil
            pendingMultiThreadAvailabilityProbe = nil
        }
        isLoading = true
        sitePostStatus = nil
        latestCompactReady = nil
        pendingHandwritingReady = nil
        pendingHandwritingRestore = nil
        refreshNavigationState()
    }

    /// Keeps the foreground device awake only while an automatic posting
    /// operation still has work to do. Background scenes always release the
    /// idle timer so this does not attempt to turn an iOS app into a
    /// background execution service.
    func setAppSceneActive(_ isActive: Bool) {
        appSceneIsActive = isActive
        if isActive {
            updateIsolationMonitoring(forceCheck: true)
        } else {
            // iOS may suspend a background scene; keeping a sleeping polling
            // task alive would not provide reliable monitoring and would hold
            // unnecessary state. The session context itself is retained so a
            // foreground resume can perform an immediate fresh check.
            stopIsolationMonitoring(clearContext: false)
        }
        updateIdleTimerState()
    }

    private func currentIsolationMonitorContext() -> IsolationMonitorContext? {
        if let session = multiThreadSession {
            let threadIDs = IsolationThreadURLParser.threadIDs(
                inPostBody: session.comment ?? ""
            )
            guard !threadIDs.isEmpty else { return nil }
            return IsolationMonitorContext(
                sessionID: session.sessionID,
                mode: .multiThread,
                targetThreadIDs: threadIDs
            )
        }
        if let session = automaticPostRepeatSession,
           let threadID = IsolationThreadURLParser.threadID(from: session.pageURL) {
            return IsolationMonitorContext(
                sessionID: session.sessionID,
                mode: .sameThread,
                targetThreadIDs: [threadID]
            )
        }
        return nil
    }

    private func updateIsolationMonitoring(forceCheck: Bool = false) {
        let context = currentIsolationMonitorContext()
        guard isolationStopEnabled,
              appSceneIsActive,
              let context,
              !context.targetThreadIDs.isEmpty else {
            isolationMonitorTask?.cancel()
            isolationMonitorTask = nil
            if context == nil {
                isolationMonitorContext = nil
                isolationMonitorFailureLogged = false
            }
            return
        }

        let contextChanged = isolationMonitorContext != context
        guard contextChanged || forceCheck || isolationMonitorTask == nil else {
            return
        }

        isolationMonitorTask?.cancel()
        isolationMonitorContext = context
        isolationMonitorFailureLogged = false
        let monitor = isolationThreadMonitor
        isolationMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.checkIsolationOnce(context: context, monitor: monitor)
                guard !Task.isCancelled else { return }
                do {
                    try await Task.sleep(
                        nanoseconds: Self.isolationMonitorIntervalNanoseconds
                    )
                } catch {
                    return
                }
                guard self.isolationStopEnabled,
                      self.appSceneIsActive,
                      self.isolationMonitorContext == context,
                      self.currentIsolationMonitorContext() == context else {
                    return
                }
            }
        }
    }

    private func stopIsolationMonitoring(clearContext: Bool) {
        isolationMonitorTask?.cancel()
        isolationMonitorTask = nil
        if clearContext {
            isolationMonitorContext = nil
            isolationMonitorFailureLogged = false
        }
    }

    private func checkIsolationOnce(context: IsolationMonitorContext,
                                    monitor: IsolationThreadMonitor) async {
        guard isolationStopEnabled,
              appSceneIsActive,
              isolationMonitorContext == context,
              currentIsolationMonitorContext() == context else {
            return
        }
        do {
            let isolatedIDs = try await monitor.fetchIsolatedThreadIDs(
                userAgent: effectiveUserAgent
            )
            guard isolationStopEnabled,
                  appSceneIsActive,
                  isolationMonitorContext == context,
                  currentIsolationMonitorContext() == context else {
                return
            }
            guard let matchedID = context.targetThreadIDs
                .intersection(isolatedIDs)
                .sorted()
                .first else {
                isolationMonitorFailureLogged = false
                return
            }
            handleIsolationDetected(context: context, threadID: matchedID)
        } catch is CancellationError {
            return
        } catch {
            guard !isolationMonitorFailureLogged else { return }
            isolationMonitorFailureLogged = true
            guard let generationID = automaticPostMachine.generationID,
                  automaticPostMachine.isActive else { return }
            let nsError = error as NSError
            appendAutomaticEvent(
                generationID: generationID,
                phase: "ISOLATION",
                event: "MONITOR_FAILED",
                result: "RETRYING",
                fields: [
                    ("ERROR_DOMAIN", nsError.domain),
                    ("ERROR_CODE", String(nsError.code))
                ]
            )
        }
    }

    private func handleIsolationDetected(context: IsolationMonitorContext,
                                         threadID: String) {
        guard isolationStopEnabled,
              isolationMonitorContext == context,
              currentIsolationMonitorContext() == context else {
            return
        }
        let mode = context.mode == .multiThread ? "MULTI_THREAD" : "SAME_THREAD"
        if let generationID = automaticPostMachine.generationID {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "ISOLATION",
                event: "ISOLATED_THREAD_DETECTED",
                result: "STOPPED",
                fields: [
                    ("THREAD_ID", threadID),
                    ("MODE", mode)
                ]
            )
        }
        stopIsolationMonitoring(clearContext: true)
        let result = "STOPPED_ISOLATED_THREAD"

        if multiThreadSession != nil {
            if let generationID = automaticPostMachine.generationID,
               automaticPostMachine.isActive {
                stopAutomaticPost(.isolatedThread, generationID: generationID)
            } else {
                finishMultiThreadSession(
                    generationID: automaticPostMachine.generationID,
                    result: result
                )
            }
            return
        }

        guard automaticPostRepeatSession != nil else { return }
        if let generationID = automaticPostMachine.generationID,
           automaticPostMachine.isActive {
            stopAutomaticPost(.isolatedThread, generationID: generationID)
        } else if let generationID = automaticPostMachine.generationID {
            setAutomaticPostStatus(.stopped, generationID: generationID)
            finishAutomaticPost(generationID: generationID, result: result)
        } else {
            cancelAutomaticRepeatSession()
            setAutomaticPostStatusWithoutGeneration(.stopped)
        }
    }

    func updateSitePostStatus(_ rawStatus: String?) {
        sitePostStatus = rawStatus.flatMap(SitePostStatus.init(rawValue:))
    }

    func setHandwritingImageAvailable(_ available: Bool) {
        handwritingImageAvailable = available
    }

    func shouldIgnoreAutomaticPageToken(_ pageToken: String) -> Bool {
        automaticPostMachine.isStalePageToken(pageToken)
    }

    func handwritingPreparationGenerationID(pageToken: String,
                                            pageURL: URL? = nil) -> UInt64? {
        guard !automaticPostMachine.isStalePageToken(pageToken) else {
            return nil
        }
        if automaticPostMachine.isActive {
            return automaticPostMachine.generationID
        }

        // During a multi-thread transition the destination document can create
        // its canvas before didFinish starts the destination generation. The
        // restoration script must still run, but its callback is intentionally
        // unbound until the destination generation owns the matching page.
        guard let pageURL,
              let pendingNavigation = pendingMultiThreadNavigation,
              let session = multiThreadSession,
              session.sessionID == pendingNavigation.sessionID,
              Self.sameTargetThreadURL(pageURL, pendingNavigation.target.threadURL) else {
            return nil
        }
        pendingHandwritingRestore = PendingHandwritingRestore(
            pageURL: pageURL,
            pageToken: pageToken
        )
        return nil
    }

    /// Handles the compact-page bridge's early indication that the current
    /// catalog target has no usable thread/form (the usual shape of a dropped
    /// or expired thread). Only a running multi-thread session may consume
    /// this signal; manual and single-thread flows keep their existing stop
    /// and alert behavior.
    func handleThreadUnavailable(pageToken: String,
                                 pageURL: URL? = nil,
                                 reason: String) {
        guard reason == "THREAD_NOT_POSTABLE",
              multiThreadEnabled,
              let session = multiThreadSession,
              let target = session.currentTarget,
              let callbackURL = pageURL ?? webView?.url,
              Self.sameTargetThreadURL(callbackURL, target.threadURL) else {
            recordAutomaticBridgeIgnored(type: "threadUnavailable",
                                         reason: "TARGET_MISMATCH")
            return
        }

        if automaticPostMachine.isActive,
           automaticPostMachine.isMultiThread,
           let generationID = automaticPostMachine.generationID {
            let tokenAccepted = automaticPostMachine.pageToken == pageToken ||
                (automaticPostMachine.pageToken == nil &&
                 !automaticPostMachine.isStalePageToken(pageToken))
            guard tokenAccepted else {
                recordAutomaticBridgeIgnored(type: "threadUnavailable",
                                             reason: "STALE_OR_MISMATCH")
                return
            }
            skipActiveMultiThreadTarget(generationID: generationID,
                                        reason: "THREAD_UNAVAILABLE")
            return
        }

        // Before didFinish, the destination has no generation yet. Hold the
        // result until the matching navigation finishes so the old page's
        // callbacks cannot advance the new target out of order.
        if let pending = pendingMultiThreadNavigation,
           pending.sessionID == session.sessionID,
           pending.target.id == target.id {
            pendingMultiThreadUnavailable = PendingMultiThreadUnavailable(
                sessionID: session.sessionID,
                targetID: target.id,
                pageToken: pageToken,
                pageURL: callbackURL,
                reason: "THREAD_UNAVAILABLE"
            )
            appendAutomaticEvent(
                generationID: automaticPostMachine.generationID ?? automaticPostGeneration,
                phase: "BRIDGE",
                event: "THREAD_UNAVAILABLE",
                result: "PENDING",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("REASON", "THREAD_NOT_POSTABLE")
                ]
            )
            return
        }

        // A late signal after the previous generation has become terminal is
        // still safe to consume when it identifies the current target. This
        // path is intentionally limited to multi-thread sessions.
        skipPendingMultiThreadTargetWithoutGeneration(
            sessionID: session.sessionID,
            target: target,
            reason: "THREAD_UNAVAILABLE"
        )
    }

    func handleCompactReady(pageToken: String,
                            hasComment: Bool,
                            canSubmit: Bool,
                            comment: String? = nil,
                            pageURL: URL? = nil) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else {
            let candidateURL = pageURL ?? webView?.url
            guard Self.isTargetThreadURL(candidateURL) else { return }
            latestCompactReady = (candidateURL, pageToken, hasComment, canSubmit)
            return
        }
        if let pageURL,
           let currentURL = webView?.url,
           !Self.sameTargetThreadURL(pageURL, currentURL) {
            recordAutomaticBridgeIgnored(type: "compactReady",
                                         reason: "PAGE_URL_MISMATCH")
            return
        }
        let compactTokenAccepted = automaticPostMachine.pageToken == pageToken ||
            (automaticPostMachine.pageToken == nil &&
             !automaticPostMachine.isStalePageToken(pageToken))
        guard compactTokenAccepted else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "COMPACT_READY",
                result: "IGNORED",
                fields: [("PAGE_TOKEN_STATE", "STALE_OR_MISMATCH")]
            )
            return
        }
        if automaticPostMachine.isMultiThread, !canSubmit {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "THREAD_UNAVAILABLE",
                result: "SKIP_REQUESTED",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("REASON", "SUBMIT_FORM_UNAVAILABLE")
                ]
            )
            skipActiveMultiThreadTarget(generationID: generationID,
                                        reason: "THREAD_UNAVAILABLE")
            return
        }
        if automaticDraftRestorePendingGeneration == generationID,
           let expectedComment = automaticPostDraft?.comment,
           !expectedComment.isEmpty {
            guard let comment else {
                recordAutomaticBridgeInvalidPayload(type: "compactReady",
                                                    reason: "COMMENT_MISSING")
                return
            }
            guard comment == expectedComment else {
                latestCompactReady = (pageURL ?? webView?.url,
                                      pageToken,
                                      hasComment,
                                      canSubmit)
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "PREPARATION",
                    event: "DRAFT_CONTENT_PENDING",
                    result: "WAITING",
                    fields: [("REASON", "RESTORE_IN_PROGRESS")]
                )
                return
            }
            automaticDraftRestorePendingGeneration = nil
        }
        if automaticPostMachine.isMultiThread,
           let expectedComment = multiThreadSession?.comment,
           !expectedComment.isEmpty {
            guard let comment else {
                recordAutomaticBridgeInvalidPayload(type: "compactReady",
                                                    reason: "COMMENT_MISSING")
                return
            }
            guard comment == expectedComment else {
                if automaticDraftRestorePendingGeneration == generationID {
                    latestCompactReady = (pageURL ?? webView?.url,
                                          pageToken,
                                          hasComment,
                                          canSubmit)
                    appendAutomaticEvent(
                        generationID: generationID,
                        phase: "PREPARATION",
                        event: "DRAFT_CONTENT_PENDING",
                        result: "WAITING",
                        fields: [("REASON", "RESTORE_IN_PROGRESS")]
                    )
                    return
                }
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "PREPARATION",
                    event: "DRAFT_CONTENT_MISMATCH",
                    result: "STOPPED",
                    fields: [("REASON", "DESTINATION_COMMENT_MISMATCH")]
                )
                stopAutomaticPost(.preparationFailed, generationID: generationID)
                return
            }
            automaticDraftRestorePendingGeneration = nil
        }
        let effect = automaticPostMachine.handle(.markCompactReady(
            generationID: generationID,
            pageToken: pageToken,
            hasComment: hasComment,
            canSubmit: canSubmit
        ))
        appendAutomaticEvent(
            generationID: generationID,
            phase: "PREPARATION",
            event: "COMPACT_READY",
            result: "ACCEPTED",
            fields: [
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("HAS_COMMENT", hasComment ? "YES" : "NO"),
                ("CAN_SUBMIT", canSubmit ? "YES" : "NO")
            ]
        )
        latestCompactReady = (pageURL ?? webView?.url,
                              pageToken,
                              hasComment,
                              canSubmit)
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    func handleSubmitReadiness(pageToken: String,
                               ready: Bool,
                               reason: String) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID,
              case let .waitingForSubmitReadiness(_, attempt, _) = automaticPostMachine.state else {
            return
        }
        let handwritingTokenAccepted = automaticPostMachine.pageToken == pageToken ||
            (automaticPostMachine.pageToken == nil &&
             !automaticPostMachine.isStalePageToken(pageToken))
        guard handwritingTokenAccepted else {
            recordAutomaticBridgeIgnored(type: "submitReadiness",
                                          reason: "STALE_OR_MISMATCH")
            return
        }

        let safeReason = Self.safeSubmitReadinessReason(reason)
        if safeReason != automaticSubmitReadinessLastReason {
            automaticSubmitReadinessLastReason = safeReason
            appendAutomaticEvent(
                generationID: generationID,
                phase: "READINESS",
                event: ready ? "READY_SIGNAL" : "WAITING",
                result: ready ? "READY" : "NOT_READY",
                fields: [
                    ("ATTEMPT", String(attempt)),
                    ("REASON", safeReason),
                    ("PAGE_TOKEN_STATE", "MATCH")
                ]
            )
        }

        let now = Date()
        if ready {
            if automaticSubmitReadinessStableSince == nil {
                automaticSubmitReadinessStableSince = now
            }
        } else {
            automaticSubmitReadinessStableSince = nil
        }
        let stableMilliseconds = automaticSubmitReadinessStableSince.map {
            max(0, Int((now.timeIntervalSince($0) * 1_000).rounded()))
        } ?? 0
        let effect = automaticPostMachine.handle(.submitReadinessObserved(
            generationID: generationID,
            pageToken: pageToken,
            ready: ready,
            stableForMilliseconds: stableMilliseconds
        ))
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    func handleSubmitObserved(pageToken: String,
                              submissionID: UInt64) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else {
            return
        }
        guard automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "submitObserved",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        let wasAwaitingResponseRetry = automaticPostMachine.awaitingSubmitResponseRetry
        let canObserveSubmission: Bool
        switch automaticPostMachine.state {
        case .submitting:
            canObserveSubmission = true
        case .waitingForSubmitReadiness(_, _, .submitResponseRetry),
             .waitingToSubmit:
            canObserveSubmission = wasAwaitingResponseRetry
        default:
            canObserveSubmission = false
        }
        guard canObserveSubmission,
              let attempt = automaticPostMachine.currentAttempt else {
            recordAutomaticBridgeIgnored(type: "submitObserved",
                                          reason: "STATE_NOT_SUBMITTING")
            return
        }
        guard automaticPostMachine.currentSubmissionID == submissionID else {
            recordAutomaticBridgeIgnored(type: "submitObserved",
                                          reason: "STALE_SUBMISSION_ID")
            return
        }
        guard !automaticPostMachine.submitEventObserved else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "SUBMIT_EVENT_DUPLICATE",
                result: "IGNORED",
                fields: [
                    ("ATTEMPT", String(attempt)),
                    ("PAGE_TOKEN_STATE", "MATCH")
                ]
            )
            return
        }
        if wasAwaitingResponseRetry {
            // A delayed form event (or a manual fallback click) arrived while
            // the one allowed automatic retry was being prepared. Treat it as
            // the active submission and wait for its completion instead of
            // issuing another click.
            automaticSubmitReadinessTask?.cancel()
            automaticSubmitReadinessTask = nil
            automaticSubmitReadinessDeadline = nil
            automaticSubmitReadinessStableSince = nil
            automaticSubmitReadinessLastReason = nil
            automaticSubmitReadinessFalseLogged = false
            automaticSubmitReadinessReason = nil
            automaticPostPreparationTimer?.cancel()
            automaticPostPreparationTimer = nil
        }
        _ = automaticPostMachine.handle(.submitObserved(
            generationID: generationID,
            submissionID: submissionID
        ))
        appendAutomaticEvent(
            generationID: generationID,
            phase: "SUBMIT",
            event: "SUBMIT_EVENT_OBSERVED",
            result: "OBSERVED",
            fields: [
                ("ATTEMPT", String(attempt)),
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("SOURCE", wasAwaitingResponseRetry ? "LATE_FORM_SUBMIT" : "FORM_SUBMIT")
            ]
        )
        if wasAwaitingResponseRetry {
            startAutomaticSubmitResponseTimeout(
                generationID: generationID,
                attempt: attempt,
                submissionID: submissionID,
                pageToken: pageToken
            )
        }
    }

    func handleHandwritingReady(pageToken: String,
                                ready: Bool,
                                generationID incomingGenerationID: UInt64? = nil,
                                pageURL: URL? = nil) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else {
            let candidateURL = pageURL ?? webView?.url
            guard Self.isTargetThreadURL(candidateURL) else { return }
            pendingHandwritingReady = (candidateURL, pageToken, ready)
            return
        }
        if let pageURL,
           let currentURL = webView?.url,
           !Self.sameTargetThreadURL(pageURL, currentURL) {
            recordAutomaticBridgeIgnored(type: "handwritingReady",
                                         reason: "PAGE_URL_MISMATCH")
            return
        }
        let callbackURL = pageURL ?? webView?.url
        let isPendingMultiThreadRestore = incomingGenerationID == nil &&
            automaticPostMachine.isMultiThread &&
            matchesPendingHandwritingRestore(pageToken: pageToken,
                                             pageURL: callbackURL)
        let handwritingTokenAccepted = automaticPostMachine.pageToken == pageToken ||
            (automaticPostMachine.pageToken == nil &&
             !automaticPostMachine.isStalePageToken(pageToken))
        guard handwritingTokenAccepted else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "HANDWRITING_READY",
                result: "IGNORED",
                fields: [("PAGE_TOKEN_STATE", "STALE_OR_MISMATCH")]
            )
            return
        }
        guard incomingGenerationID == generationID || isPendingMultiThreadRestore else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "HANDWRITING_READY",
                result: "IGNORED",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("GENERATION_ID_STATE", "STALE_OR_MISMATCH")
                ]
            )
            return
        }
        if isPendingMultiThreadRestore {
            pendingHandwritingRestore = nil
        } else if let callbackURL,
                  pendingHandwritingRestore?.pageToken == pageToken,
                  Self.sameTargetThreadURL(pendingHandwritingRestore?.pageURL,
                                           callbackURL) {
            // An exactly tagged callback supersedes any pre-finish unbound
            // request for the same page, preventing a late duplicate from
            // authorizing a second readiness transition.
            pendingHandwritingRestore = nil
        }
        let effect = automaticPostMachine.handle(.markHandwritingReady(
            generationID: generationID,
            pageToken: pageToken,
            ready: ready
        ))
        guard automaticPostMachine.pageToken == pageToken else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "HANDWRITING_READY",
                result: "IGNORED",
                fields: [("PAGE_TOKEN_STATE", "STALE_OR_MISMATCH")]
            )
            return
        }
        var handwritingFields = [("PAGE_TOKEN_STATE", "MATCH")]
        if isPendingMultiThreadRestore {
            handwritingFields.append(("GENERATION_ID_STATE", "BOUND_FROM_PENDING_RESTORE"))
        }
        if !ready {
            handwritingFields.append(("FAILURE_REASON", "PAYLOAD_NOT_READY"))
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "PREPARATION",
            event: "HANDWRITING_READY",
            result: ready ? "ACCEPTED" : "FAILED",
            fields: handwritingFields
        )
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    func handlePostStatus(_ rawStatus: String?,
                          pageToken: String?,
                          submissionID: UInt64? = nil) {
        if automaticPostMachine.isActive {
            guard let pageToken else {
                recordAutomaticBridgeIgnored(type: "postStatus",
                                              reason: "MISSING_PAGE_TOKEN")
                return
            }
            guard let submissionID else {
                recordAutomaticBridgeInvalidPayload(type: "postStatus",
                                                    reason: "SUBMISSION_ID_MISSING")
                return
            }
            guard automaticPostMachine.pageToken == pageToken else {
                recordAutomaticBridgeIgnored(type: "postStatus",
                                              reason: "STALE_OR_MISMATCH")
                return
            }
            if automaticPostMachine.currentSubmissionID != submissionID {
                recordAutomaticBridgeIgnored(type: "postStatus",
                                              reason: "STALE_SUBMISSION_ID")
                return
            }
        } else if submissionID != nil {
            // A late automatic marker must not overwrite the ordinary manual
            // status slot after its generation has already finished.
            if let generationID = automaticPostMachine.generationID {
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "BRIDGE",
                    event: "POST_STATUS_IGNORED",
                    result: "IGNORED",
                    fields: [("REASON", "FLOW_NOT_ACTIVE")]
                )
            }
            return
        }
        updateSitePostStatus(rawStatus)
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID,
              let pageToken,
              automaticPostMachine.pageToken == pageToken else {
            if let generationID = automaticPostMachine.generationID,
               let statusName = Self.safePostStatusName(rawStatus),
               !automaticPostMachine.isActive {
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "BRIDGE",
                    event: "POST_STATUS_IGNORED",
                    result: "IGNORED",
                    fields: [
                        ("REASON", "FLOW_NOT_ACTIVE"),
                        ("STATUS", statusName)
                    ]
                )
            }
            return
        }
        let statusName: String
        if rawStatus == SitePostStatus.sending.rawValue {
            statusName = "SENDING"
        } else if rawStatus == SitePostStatus.completed.rawValue {
            statusName = "COMPLETED"
        } else {
            statusName = "OTHER"
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "POST_STATUS",
            result: "RECEIVED",
            fields: [
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("STATUS", statusName)
            ]
        )
        if rawStatus == SitePostStatus.sending.rawValue {
            setAutomaticPostStatus(.sending, generationID: generationID)
        } else if rawStatus == SitePostStatus.completed.rawValue {
            cancelAutomaticSubmitResponseTimer()
            recordAutomaticPostAccepted(generationID: generationID,
                                         pageToken: pageToken,
                                         source: "POST_STATUS")
            let effect = automaticPostMachine.handle(.postCompleted(generationID: generationID))
            handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    func handlePostCompleted(pageToken: String?,
                             submissionID: UInt64? = nil) {
        guard let generationID = automaticPostMachine.generationID else { return }
        guard automaticPostMachine.isActive else {
            let tokenState: String
            if let pageToken {
                tokenState = automaticPostMachine.pageToken == pageToken
                    ? "MATCH" : "STALE_OR_MISMATCH"
            } else {
                tokenState = "MISSING"
            }
            appendAutomaticEvent(
                generationID: generationID,
                phase: "BRIDGE",
                event: "POST_COMPLETED_IGNORED",
                result: "IGNORED",
                fields: [
                    ("REASON", "FLOW_NOT_ACTIVE"),
                    ("PAGE_TOKEN_STATE", tokenState)
                ]
            )
            return
        }
        guard let pageToken else {
            recordAutomaticBridgeIgnored(type: "postCompleted",
                                          reason: "MISSING_PAGE_TOKEN")
            return
        }
        guard let submissionID else {
            recordAutomaticBridgeInvalidPayload(type: "postCompleted",
                                                reason: "SUBMISSION_ID_MISSING")
            return
        }
        guard automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "postCompleted",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        if automaticPostMachine.currentSubmissionID != submissionID {
            recordAutomaticBridgeIgnored(type: "postCompleted",
                                          reason: "STALE_SUBMISSION_ID")
            return
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "POST_COMPLETED",
            result: "RECEIVED",
            fields: [("PAGE_TOKEN_STATE", "MATCH")]
        )
        cancelAutomaticSubmitResponseTimer()
        recordAutomaticPostAccepted(generationID: generationID,
                                    pageToken: pageToken,
                                    source: "POST_COMPLETED")
        let effect = automaticPostMachine.handle(.postCompleted(generationID: generationID))
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    func handleOwnPostVisible(pageToken: String?,
                              matchedCount: Int,
                              pendingCount: Int,
                              responseCount: Int,
                              newResponseCount: Int,
                              matchMethod: String?) {
        let canAcceptVisibleResponse: Bool
        switch automaticPostMachine.state {
        case .submitting:
            canAcceptVisibleResponse = true
        case .succeeded:
            // Multi-thread and same-thread repeat generations intentionally
            // skip the 12-second visibility watchdog. DOM visibility remains
            // diagnostic after the site's completion marker, regardless of
            // timer ownership.
            canAcceptVisibleResponse = automaticPostAccepted
        case .idle, .preparing, .waitingForSubmitReadiness, .waitingToSubmit,
             .waitingForCookieRetry, .waitingForCookieRefresh, .waitingForIPRetry,
             .waitingForContinuousRetry,
             .waitingForContinuousAPRetry, .stopped:
            canAcceptVisibleResponse = false
        }
        guard canAcceptVisibleResponse,
              let generationID = automaticPostMachine.generationID,
              let pageToken else {
            return
        }
        guard automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "ownPostVisible",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        automaticOwnResponseConfirmed = true
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        appendAutomaticEvent(
            generationID: generationID,
            phase: "VERIFICATION",
            event: "OWN_RESPONSE_CONFIRMED",
            result: "DOM_MATCHED",
            fields: [
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("MATCHED_COUNT", String(max(0, matchedCount))),
                ("PENDING_POST_COUNT", String(max(0, pendingCount))),
                ("THREAD_RESPONSE_COUNT", String(max(0, responseCount))),
                ("NEW_RESPONSE_COUNT", String(max(0, newResponseCount))),
                ("MATCH_METHOD", Self.safeMatchMethod(matchMethod)),
                ("FINAL_RESULT", "ACCEPTED_VISIBLE")
            ]
        )
        if automaticPostAccepted,
           case .succeeded = automaticPostMachine.state {
            if multiThreadSession != nil {
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "VERIFICATION",
                    event: "OWN_RESPONSE_CONFIRMED",
                    result: "DIAGNOSTIC_ONLY",
                    fields: [("PAGE_TOKEN_STATE", "MATCH")]
                )
                return
            }
            // The site completion marker has already scheduled the next
            // same-thread cycle. Visibility is diagnostic only in this mode;
            // finalizing here would clear the repeat session and cancel its
            // delay task before the next generation can start.
            if let session = automaticPostRepeatSession,
               sameThreadRepeatEnabled,
               !session.stopRequested {
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "VERIFICATION",
                    event: "OWN_RESPONSE_CONFIRMED",
                    result: "DIAGNOSTIC_ONLY",
                    fields: [
                        ("PAGE_TOKEN_STATE", "MATCH"),
                        ("REPEAT_SESSION_ACTIVE", "YES")
                    ]
                )
                return
            }
            setAutomaticPostStatus(.completed, generationID: generationID)
            finishAutomaticPost(generationID: generationID, result: "SUCCEEDED")
        }
    }

    func handleOwnPostObservation(pageToken: String?,
                                  pendingCount: Int,
                                  responseCount: Int,
                                  newResponseCount: Int,
                                  matchedCount: Int,
                                  matchMethod: String?) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID,
              let pageToken else {
            return
        }
        guard automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "ownPostObservation",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "VERIFICATION",
            event: "DOM_OBSERVATION",
            result: "PENDING",
            fields: [
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("PENDING_POST_COUNT", String(max(0, pendingCount))),
                ("THREAD_RESPONSE_COUNT", String(max(0, responseCount))),
                ("NEW_RESPONSE_COUNT", String(max(0, newResponseCount))),
                ("MATCHED_COUNT", String(max(0, matchedCount))),
                ("MATCH_METHOD", Self.safeMatchMethod(matchMethod))
            ]
        )
    }

    func navigationCommitted(url: URL?) {
        updateCurrentURL(url)
        refreshNavigationState()
    }

    func navigationFinished(url: URL?) {
        isLoading = false
        if !isIdentityRefreshInProgress {
            isUAChanging = false
        }
        updateCurrentURL(url)
        refreshNavigationState()
        runAutomaticBookmarklets(for: url)

        if let pending = pendingMultiThreadNavigation,
           let session = multiThreadSession,
           pending.sessionID == session.sessionID {
            guard let loadedURL = url,
                  ThreadListViewModel.threadID(from: loadedURL) == pending.target.id else {
                appendAutomaticEvent(
                    generationID: session.currentGenerationID ?? automaticPostGeneration,
                    phase: "NAVIGATION",
                    event: "NEXT_THREAD_NAVIGATION_FAILED",
                    result: "STOPPED",
                    fields: [("REASON", "TARGET_MISMATCH"),
                             ("DISPOSITION", "SKIP_CURRENT_THREAD")]
                )
                pendingMultiThreadNavigation = nil
                pendingMultiThreadAvailabilityProbe = nil
                skipPendingMultiThreadTargetWithoutGeneration(
                    sessionID: session.sessionID,
                    target: pending.target,
                    reason: "NAVIGATION_TARGET_MISMATCH"
                )
                return
            }
            let pendingUnavailable = pendingMultiThreadUnavailable
            if let pendingUnavailable,
               pendingUnavailable.sessionID == session.sessionID,
               pendingUnavailable.targetID == pending.target.id,
               Self.sameTargetThreadURL(pendingUnavailable.pageURL, loadedURL) {
                // The dropped-thread bridge arrived before didFinish, so no
                // generation should be started for this target. Move on with
                // the existing session draft and UA accounting intact.
                pendingMultiThreadNavigation = nil
                pendingMultiThreadAvailabilityProbe = nil
                pendingMultiThreadUnavailable = nil
                skipPendingMultiThreadTargetWithoutGeneration(
                    sessionID: session.sessionID,
                    target: pending.target,
                    reason: pendingUnavailable.reason
                )
                return
            }
            let probe = PendingMultiThreadAvailabilityProbe(
                sessionID: session.sessionID,
                targetID: pending.target.id,
                pageURL: loadedURL,
                navigationSequence: multiThreadNavigationSequence
            )
            if pendingMultiThreadAvailabilityProbe == probe {
                return
            }
            pendingMultiThreadAvailabilityProbe = probe
            guard let webView else {
                pendingMultiThreadAvailabilityProbe = nil
                continueMultiThreadDestinationAfterNavigation(
                    session: session,
                    target: pending.target,
                    loadedURL: loadedURL
                )
                return
            }
            webView.evaluateJavaScript(CompactPageModeService.threadAvailabilityScript) {
                [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.pendingMultiThreadAvailabilityProbe == probe,
                          self.multiThreadNavigationSequence == probe.navigationSequence,
                          let currentPending = self.pendingMultiThreadNavigation,
                          currentPending.sessionID == probe.sessionID,
                          currentPending.target.id == probe.targetID,
                          let currentSession = self.multiThreadSession,
                          currentSession.sessionID == probe.sessionID,
                          currentSession.currentTarget?.id == probe.targetID else {
                        return
                    }
                    self.pendingMultiThreadAvailabilityProbe = nil

                    let pendingUnavailable = self.pendingMultiThreadUnavailable
                    if let pendingUnavailable,
                       pendingUnavailable.sessionID == currentSession.sessionID,
                       pendingUnavailable.targetID == currentPending.target.id,
                       Self.sameTargetThreadURL(pendingUnavailable.pageURL,
                                                probe.pageURL) {
                        self.pendingMultiThreadNavigation = nil
                        self.pendingMultiThreadUnavailable = nil
                        self.skipPendingMultiThreadTargetWithoutGeneration(
                            sessionID: currentSession.sessionID,
                            target: currentPending.target,
                            reason: pendingUnavailable.reason
                        )
                        return
                    }

                    if error == nil,
                       let availability = Self.threadAvailability(from: result),
                       (!availability.hasThread || !availability.hasForm) {
                        self.pendingMultiThreadNavigation = nil
                        self.pendingMultiThreadUnavailable = nil
                        self.appendAutomaticEvent(
                            generationID: currentSession.currentGenerationID ??
                                self.automaticPostGeneration,
                            phase: "NAVIGATION",
                            event: "THREAD_UNAVAILABLE",
                            result: "PROBE_SKIP_REQUESTED",
                            fields: [
                                ("PAGE_TOKEN_STATE", "UNBOUND"),
                                ("REASON", "THREAD_NOT_POSTABLE")
                            ]
                        )
                        self.skipPendingMultiThreadTargetWithoutGeneration(
                            sessionID: currentSession.sessionID,
                            target: currentPending.target,
                            reason: "THREAD_NOT_POSTABLE_PROBE"
                        )
                        return
                    }

                    if error != nil {
                        self.appendAutomaticEvent(
                            generationID: currentSession.currentGenerationID ??
                                self.automaticPostGeneration,
                            phase: "NAVIGATION",
                            event: "THREAD_AVAILABILITY_PROBE",
                            result: "UNAVAILABLE",
                            fields: [("REASON", "EVALUATION_ERROR")]
                        )
                    }
                    self.continueMultiThreadDestinationAfterNavigation(
                        session: currentSession,
                        target: currentPending.target,
                        loadedURL: probe.pageURL
                    )
                }
            }
            return
        }
        if let pending = pendingCookieRefresh,
           let generationID = pending.automaticGenerationID,
           automaticPostMachine.isActive,
           automaticPostMachine.generationID == generationID,
           Self.isTargetThreadURL(url) {
            let effect = automaticPostMachine.handle(.markReloadCompleted(generationID: generationID))
            handleAutomaticPostEffect(effect, generationID: generationID)
        }
        if pendingCookieRefresh != nil {
            Task { [weak self] in
                await self?.completeCookieRefreshAfterReload()
            }
        }
    }

    /// Settles a successfully loaded multi-thread destination after its
    /// structural availability has been checked. Keeping the pending
    /// navigation alive until this point prevents a dropped page from being
    /// mistaken for a normal page generation during the transition.
    private func continueMultiThreadDestinationAfterNavigation(
        session: MultiThreadPostSession,
        target: CatalogPostTarget,
        loadedURL: URL
    ) {
        guard multiThreadSession?.sessionID == session.sessionID,
              multiThreadSession?.currentTarget?.id == target.id,
              let pending = pendingMultiThreadNavigation,
              pending.sessionID == session.sessionID,
              pending.target.id == target.id else {
            return
        }
        pendingMultiThreadNavigation = nil
        pendingMultiThreadAvailabilityProbe = nil
        pendingMultiThreadUnavailable = nil

        if session.currentGenerationID == nil {
            // The first catalog target was different from the page that
            // supplied the draft. Perform the initial UA refresh only after
            // that target has actually loaded.
            automaticPostGeneration &+= 1
            let generationID = automaticPostGeneration
            startUserAgentChange(
                pageURL: loadedURL,
                generationID: generationID,
                oldPageToken: nil,
                hasComment: session.comment?.isEmpty == false,
                comment: session.comment,
                hasImage: session.hasImage,
                automatic: true,
                readError: false,
                targetUAIndex: nil,
                excludedUAIDs: automaticTriedUAIDs,
                newAutomaticSession: false,
                multiThread: true
            )
        } else if let previousGenerationID = session.currentGenerationID,
                  session.shouldRotateUserAgent {
            // A multi-thread session keeps one UA for two accepted target
            // posts. The next target is loaded first, then the normal UA
            // refresh generation is started on that destination page.
            appendAutomaticEvent(
                generationID: previousGenerationID,
                phase: "FLOW",
                event: "UA_ROTATION_AFTER_TWO_THREADS",
                result: "NEXT_UA_REQUESTED",
                fields: [
                    ("POSTS_SINCE_UA_CHANGE",
                     String(session.postsSinceUserAgentChange))
                ]
            )
            automaticPostGeneration &+= 1
            let generationID = automaticPostGeneration
            setAutomaticPostStatus(
                .switchingAfterThreadBatch,
                generationID: previousGenerationID
            )
            startUserAgentChange(
                pageURL: loadedURL,
                generationID: generationID,
                oldPageToken: automaticPostMachine.pageToken,
                hasComment: session.comment?.isEmpty == false,
                comment: session.comment,
                hasImage: session.hasImage,
                automatic: true,
                readError: false,
                targetUAIndex: nil,
                excludedUAIDs: automaticTriedUAIDs,
                newAutomaticSession: false,
                multiThread: true
            )
        } else {
            startMultiThreadGenerationAfterNavigation(url: loadedURL,
                                                      session: session)
        }
    }

    private func startMultiThreadGenerationAfterNavigation(url: URL,
                                                           session: MultiThreadPostSession) {
        guard multiThreadSession?.sessionID == session.sessionID,
              let target = session.currentTarget else {
            return
        }
        guard ThreadListViewModel.threadID(from: url) == target.id else {
            appendAutomaticEvent(
                generationID: session.currentGenerationID ?? automaticPostGeneration,
                phase: "NAVIGATION",
                event: "NEXT_THREAD_NAVIGATION_FAILED",
                result: "SKIP_CURRENT_THREAD",
                fields: [
                    ("REASON", "TARGET_MISMATCH"),
                    ("DISPOSITION", "SKIP_CURRENT_THREAD")
                ]
            )
            pendingMultiThreadAvailabilityProbe = nil
            skipPendingMultiThreadTargetWithoutGeneration(
                sessionID: session.sessionID,
                target: target,
                reason: "NAVIGATION_TARGET_MISMATCH"
            )
            return
        }

        automaticPostPreparationTimer?.cancel()
        automaticSubmitReadinessTask?.cancel()
        cancelAutomaticSubmitResponseTimer()
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        cancelAutomaticContinuousAPRetryDelay()
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        let preFinishCompactReady = latestCompactReady
        let preFinishHandwritingReady = pendingHandwritingReady
        latestCompactReady = nil
        pendingHandwritingReady = nil
        automaticDraftRestorePendingGeneration = nil
        automaticCookieRelatedCount = nil
        automaticCookieCountDelta = nil
        automaticAPResult = "NOT_REQUESTED"
        automaticPostGeneration &+= 1
        let generationID = automaticPostGeneration
        let oldPageToken = automaticPostMachine.pageToken
        automaticPostMachine.reset()
        let beginEffect = automaticPostMachine.beginMultiThreadNavigation(
            generationID: generationID,
            oldPageToken: oldPageToken,
            hasComment: session.comment?.isEmpty == false,
            hasImage: session.hasImage,
            submissionIDSeed: nextAutomaticSubmissionSeed()
        )
        automaticPostDraft = AutomaticPostDraft(
            hasComment: session.comment?.isEmpty == false,
            comment: session.comment,
            hasImage: session.hasImage
        )
        var updatedSession = session
        updatedSession.currentGenerationID = generationID
        updatedSession.currentTargetID = target.id
        multiThreadSession = updatedSession
        beginAutomaticGenerationLogging(generationID: generationID)
        setAutomaticPostStatus(.checkingCookie, generationID: generationID)
        startAutomaticPostPreparationTimeout(generationID: generationID)
        let reloadEffect = automaticPostMachine.handle(
            .markReloadCompleted(generationID: generationID)
        )
        handleAutomaticPostEffect(beginEffect, generationID: generationID)
        handleAutomaticPostEffect(reloadEffect, generationID: generationID)

        // A document-end bridge message may have arrived before didFinish.
        // Reuse only signals tied to this exact target URL and page token;
        // never promote a previous target's readiness to the new generation.
        let destinationURL = url
        if let comment = session.comment, !comment.isEmpty {
            automaticDraftRestorePendingGeneration = generationID
            restoreMultiThreadDraft(comment: comment,
                                    generationID: generationID,
                                    pageURL: destinationURL)
        } else if let compact = preFinishCompactReady,
                  Self.sameTargetThreadURL(compact.pageURL, destinationURL),
                  compact.pageToken != oldPageToken,
                  compact.canSubmit {
            handleCompactReady(pageToken: compact.pageToken,
                               hasComment: compact.hasComment,
                               canSubmit: compact.canSubmit,
                               pageURL: compact.pageURL)
        }
        if let handwriting = preFinishHandwritingReady,
           Self.sameTargetThreadURL(handwriting.pageURL, destinationURL),
           handwriting.pageToken != oldPageToken {
            pendingHandwritingRestore = nil
            handleHandwritingReady(pageToken: handwriting.pageToken,
                                   ready: handwriting.ready,
                                   generationID: generationID,
                                   pageURL: handwriting.pageURL)
        }
    }

    private func restoreMultiThreadDraft(comment: String,
                                         generationID: UInt64,
                                         pageURL: URL) {
        guard automaticPostMachine.generationID == generationID,
              multiThreadSession?.currentGenerationID == generationID,
              let webView,
              let script = CompactPageModeService.restoreAutomaticDraftScript(
                  comment: comment
              ) else {
            stopAutomaticPost(.preparationFailed, generationID: generationID)
            return
        }
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.automaticPostMachine.generationID == generationID,
                      self.multiThreadSession?.currentGenerationID == generationID,
                      self.automaticPostMachine.isActive,
                      Self.sameTargetThreadURL(self.webView?.url, pageURL) else {
                    return
                }
                guard error == nil, Self.javascriptBoolean(result) == true else {
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "PREPARATION",
                        event: "DRAFT_RESTORE_FAILED",
                        result: "STOPPED",
                        fields: [("REASON", error == nil ? "SCRIPT_RETURNED_FALSE" : "EVALUATION_ERROR")]
                    )
                    self.stopAutomaticPost(.preparationFailed, generationID: generationID)
                    return
                }
                self.automaticDraftRestorePendingGeneration = nil
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "PREPARATION",
                    event: "DRAFT_RESTORE_VERIFIED",
                    result: "READY"
                )
            }
        }
    }

    /// Restores the in-memory comment after the bounded timeout recovery's
    /// Cookie reload. This is intentionally separate from UA handoff and
    /// multi-thread navigation restoration so those existing paths keep their
    /// original callback ownership.
    private func restoreAutomaticDraftAfterCookieRefresh(comment: String,
                                                         generationID: UInt64,
                                                         pageURL: URL) {
        guard automaticPostMachine.generationID == generationID,
              automaticPostMachine.isActive,
              let webView,
              let script = CompactPageModeService.restoreAutomaticDraftScript(
                  comment: comment
              ) else {
            stopAutomaticPost(.preparationFailed, generationID: generationID)
            return
        }
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.automaticPostMachine.generationID == generationID,
                      self.automaticPostMachine.isActive,
                      Self.sameTargetThreadURL(self.webView?.url, pageURL) else {
                    return
                }
                guard error == nil, Self.javascriptBoolean(result) == true else {
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "PREPARATION",
                        event: "DRAFT_RESTORE_FAILED",
                        result: "STOPPED",
                        fields: [
                            ("PATH", "TIMEOUT_COOKIE_REFRESH"),
                            ("REASON", error == nil
                                ? "SCRIPT_RETURNED_FALSE" : "EVALUATION_ERROR")
                        ]
                    )
                    self.stopAutomaticPost(.preparationFailed,
                                            generationID: generationID)
                    return
                }
                self.automaticDraftRestorePendingGeneration = nil
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "PREPARATION",
                    event: "DRAFT_RESTORE_VERIFIED",
                    result: "READY",
                    fields: [("PATH", "TIMEOUT_COOKIE_REFRESH")]
                )

                // If compactReady arrived while the restore script was still
                // running, replay only that same-page signal with the known
                // restored comment instead of waiting for another bridge tick.
                guard case .preparing = self.automaticPostMachine.state,
                      let compact = self.latestCompactReady,
                      Self.sameTargetThreadURL(compact.pageURL, pageURL),
                      compact.canSubmit else { return }
                self.handleCompactReady(
                    pageToken: compact.pageToken,
                    hasComment: compact.hasComment || !comment.isEmpty,
                    canSubmit: compact.canSubmit,
                    comment: comment,
                    pageURL: compact.pageURL ?? pageURL
                )
            }
        }
    }

    func navigationFailed(url: URL?, error: Error) {
        isLoading = false
        if !isIdentityRefreshInProgress {
            isUAChanging = false
        }
        updateCurrentURL(url)
        refreshNavigationState()
        showToast("読み込み失敗", kind: .failure)
        logStore.append(action: "Web Load Failure", fields: [
            ("URL", LogSanitizer.url(url)),
            ("UA", effectiveUserAgentLogLabel),
            ("ERROR_DOMAIN", (error as NSError).domain),
            ("ERROR_CODE", String((error as NSError).code)),
            ("DETAIL", error.localizedDescription),
            ("RESULT", "FAILED")
        ])
        failPendingCookieRefresh(result: "RELOAD_FAILED")
        if let pending = pendingMultiThreadNavigation,
           let session = multiThreadSession,
           pending.sessionID == session.sessionID {
            pendingMultiThreadNavigation = nil
            pendingMultiThreadAvailabilityProbe = nil
            skipPendingMultiThreadTargetWithoutGeneration(
                sessionID: session.sessionID,
                target: pending.target,
                reason: "NAVIGATION_FAILED"
            )
            return
        }
        if multiThreadSession != nil {
            finishMultiThreadSession(
                generationID: multiThreadSession?.currentGenerationID ??
                    automaticPostMachine.generationID,
                result: "STOPPED_NAVIGATION_FAILED"
            )
            return
        }
        stopAutomaticPost(.preparationFailed, generationID: automaticPostMachine.generationID)
    }

    func navigationTimedOut(url: URL?) {
        isLoading = false
        if !isIdentityRefreshInProgress {
            isUAChanging = false
        }
        updateCurrentURL(url)
        refreshNavigationState()
        showToast("読み込みタイムアウト", kind: .failure)
        logStore.append(action: "Web Load Timeout", fields: [
            ("URL", LogSanitizer.url(url)),
            ("UA", effectiveUserAgentLogLabel),
            ("TIMEOUT_SECONDS", "30"),
            ("RESULT", "TIMEOUT")
        ])
        failPendingCookieRefresh(result: "RELOAD_TIMEOUT")
        if let pending = pendingMultiThreadNavigation,
           let session = multiThreadSession,
           pending.sessionID == session.sessionID {
            pendingMultiThreadNavigation = nil
            pendingMultiThreadAvailabilityProbe = nil
            skipPendingMultiThreadTargetWithoutGeneration(
                sessionID: session.sessionID,
                target: pending.target,
                reason: "NAVIGATION_TIMEOUT"
            )
            return
        }
        if multiThreadSession != nil {
            finishMultiThreadSession(
                generationID: multiThreadSession?.currentGenerationID ??
                    automaticPostMachine.generationID,
                result: "STOPPED_NAVIGATION_TIMEOUT"
            )
            return
        }
        stopAutomaticPost(.preparationTimeout, generationID: automaticPostMachine.generationID)
    }

    func handleCallbackURL(_ url: URL) {
        guard url.scheme?.lowercased() == "minibrowser",
              url.host?.lowercased() == "return",
              isAPRunning,
              let context = pendingAP else { return }

        let status = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "status" })?.value ?? "success"
        guard status == "success" else {
            finishAPFailure(status: "CALLBACK_\(status.uppercased())",
                            before: context.beforeIPv4,
                            reloadAfterCompletion: context.reloadAfterCompletion,
                            purpose: context.purpose)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let after = await self.fetchIPv4AfterRecovery()
            self.completeAP(before: context.beforeIPv4,
                            after: after,
                            reloadAfterCompletion: context.reloadAfterCompletion,
                            purpose: context.purpose)
        }
    }

    func showToast(_ text: String, kind: ToastKind, duration: TimeInterval = 3.5) {
        let toast = ToastMessage(text: text, kind: kind)
        toasts.append(toast)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self?.toasts.removeAll { $0.id == toast.id }
        }
    }

    func handleTargetPageAlert(_ category: TargetPageAlertCategory,
                               host: String,
                               message: String) -> TargetPageAlertDisposition {
        let alertGenerationID = automaticPostMachine.isActive
            ? automaticPostMachine.generationID
            : nil
        let alertUA = effectiveUserAgentLogLabel
        let alertURL = currentURL
        let alertContext = alertGenerationID.flatMap {
            automaticLogContext(generationID: $0)
        }

        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else {
            Task { [weak self] in
                await self?.recordTargetPageAlert(
                    category,
                    host: host,
                    message: message,
                    automaticGenerationID: nil,
                    logContext: nil,
                    disposition: "SHOWN",
                    userAgent: alertUA,
                    url: alertURL
                )
            }
            return .showNormally
        }

        cancelAutomaticSubmitResponseTimer()

        if category == .accessRestricted {
            userAgentRestrictionStore.restrict(currentUserAgent.id)
        }

        let alert: AutomaticPostAlert
        switch category {
        case .cookieRetryRequired:
            alert = .cookieRetryRequired
        case .imagePostingRestricted:
            alert = .imagePostingRestricted
        case .accessRestricted:
            alert = .accessRestricted
        case .continuousPosting:
            alert = .continuousPosting
        case .imageContinuousPosting:
            alert = .imageContinuousPosting
        case .threadPostingUnavailable:
            alert = .threadPostingUnavailable
        case .imageCountRestricted:
            alert = .imageCountRestricted
        }
        let result = automaticPostMachine.handleAlert(alert, generationID: generationID)
        handleAutomaticPostEffect(result.effect, generationID: generationID)
        let alertDisposition = result.autoDismiss ? "AUTO_DISMISSED" : "SHOWN"
        Task { [weak self] in
            await self?.recordTargetPageAlert(
                category,
                host: host,
                message: message,
                automaticGenerationID: alertGenerationID,
                logContext: alertContext,
                disposition: alertDisposition,
                userAgent: alertUA,
                url: alertURL
            )
        }
        if result.autoDismiss {
            switch alert {
            case .cookieRetryRequired:
                guard automaticPostMachine.isActive,
                      automaticPostMachine.generationID == generationID else {
                    return .autoDismiss
                }
                setAutomaticPostStatus(.cookieRetry, generationID: generationID)
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self,
                          self.automaticPostMachine.generationID == generationID else { return }
                    let effect = self.automaticPostMachine.handle(
                        .cookieAlertDismissed(generationID: generationID)
                    )
                    self.handleAutomaticPostEffect(effect, generationID: generationID)
                }
            case .imagePostingRestricted:
                guard automaticPostMachine.isActive,
                      automaticPostMachine.generationID == generationID else {
                    return .autoDismiss
                }
                setAutomaticPostStatus(.reconnectingAfterIPLimit, generationID: generationID)
            case .continuousPosting:
                guard automaticPostMachine.isActive,
                      automaticPostMachine.generationID == generationID else {
                    return .autoDismiss
                }
                if case .waitingForContinuousRetry = automaticPostMachine.state {
                    setAutomaticPostStatus(.sending, generationID: generationID)
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        guard let self,
                              self.automaticPostMachine.generationID == generationID else { return }
                        let effect = self.automaticPostMachine.handle(
                            .continuousAlertDismissed(generationID: generationID)
                        )
                        self.handleAutomaticPostEffect(effect, generationID: generationID)
                    }
                }
            case .accessRestricted:
                // The state machine has already invalidated the current
                // generation and started the next eligible-UA handoff.
                break
            case .threadPostingUnavailable:
                break
            case .imageCountRestricted:
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "FLOW",
                    event: "IMAGE_COUNT_UA_HANDOFF",
                    result: "NEXT_UA_REQUESTED"
                )
            case .imageContinuousPosting:
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "FLOW",
                    event: "IMAGE_CONTINUOUS_UA_HANDOFF",
                    result: "NEXT_UA_REQUESTED"
                )
            }
            return .autoDismiss
        }
        return .showNormally
    }

    func handleUnknownJavaScriptAlert(message: String,
                                      host: String?,
                                      url: URL?) {
        let isTargetPageAlert = host?.lowercased() == "img.2chan.net"
        let capturedMessage = isTargetPageAlert
            ? LogSanitizer.alertMessage(message)
            : "[NOT_CAPTURED_NON_TARGET_HOST]"
        if let generationID = automaticPostMachine.generationID,
           automaticPostMachine.isActive {
            cancelAutomaticSubmitResponseTimer()
            appendAutomaticEvent(
                generationID: generationID,
                phase: "ALERT",
                event: "UNKNOWN_ALERT",
                result: "STOPPED",
                fields: [
                    ("URL", LogSanitizer.url(url)),
                    ("DOMAIN", host?.lowercased() ?? "(none)"),
                    ("UA", effectiveUserAgentLogLabel),
                    ("ALERT_MESSAGE", capturedMessage),
                    ("DISPOSITION", "SHOWN")
                ]
            )
        } else {
            logStore.append(action: "Site Post Alert", fields: [
                ("URL", LogSanitizer.url(url)),
                ("DOMAIN", host?.lowercased() ?? "(none)"),
                ("UA", effectiveUserAgentLogLabel),
                ("ALERT_CATEGORY", "UNKNOWN_ALERT"),
                ("ALERT_MESSAGE", capturedMessage),
                ("FLOW_MODE", "MANUAL"),
                ("DISPOSITION", "SHOWN"),
                ("RESULT", "OBSERVED")
            ])
        }
        stopAutomaticPost(.unknownAlert, generationID: automaticPostMachine.generationID)
    }

    // Keep the original test/debug entry point available for manual alert
    // observation while the automatic path supplies generation metadata.
    func recordTargetPageAlert(_ category: TargetPageAlertCategory,
                               host: String) async {
        await recordTargetPageAlert(category,
                                    host: host,
                                    message: category.rawValue,
                                    automaticGenerationID: nil,
                                    logContext: nil,
                                    disposition: "SHOWN",
                                    userAgent: effectiveUserAgentLogLabel,
                                    url: currentURL)
    }

    func recordTargetPageAlert(_ category: TargetPageAlertCategory,
                               host: String,
                               automaticGenerationID: UInt64?,
                               userAgent: String,
                               url: URL?) async {
        await recordTargetPageAlert(category,
                                    host: host,
                                    message: category.rawValue,
                                    automaticGenerationID: automaticGenerationID,
                                    logContext: automaticGenerationID.flatMap {
                                        automaticLogContext(generationID: $0)
                                    },
                                    disposition: automaticGenerationID == nil ? "SHOWN" : "OBSERVED",
                                    userAgent: userAgent,
                                    url: url)
    }

    private func recordTargetPageAlert(_ category: TargetPageAlertCategory,
                                       host: String,
                                       message: String,
                                       automaticGenerationID: UInt64?,
                                       logContext: AutomaticLogContext?,
                                       disposition: String,
                                       userAgent: String,
                                       url: URL?) async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let normalizedHost = host.lowercased()
        let cookies = await store.miniBrowserAllCookies()
        let relatedCount = cookies.filter {
            CookieDomainMatcher.isRelated(cookieDomain: $0.domain, toHost: normalizedHost)
        }.count
        let previousCount = lastRelatedCookieCountByHost[normalizedHost]
        lastRelatedCookieCountByHost[normalizedHost] = relatedCount
        if let automaticGenerationID,
           automaticPostMachine.isActive,
           automaticPostMachine.generationID == automaticGenerationID {
            automaticCookieRelatedCount = relatedCount
            automaticCookieCountDelta = previousCount.map { relatedCount - $0 }
        }

        // Capture only the TargetPage alert text for diagnosis. Cookie names,
        // values, form contents, and image data remain out of the log.
        var fields = [
            ("URL", LogSanitizer.url(url)),
            ("DOMAIN", normalizedHost),
            ("UA", userAgent),
            ("ALERT_CATEGORY", category.rawValue),
            ("ALERT_MESSAGE", LogSanitizer.alertMessage(message)),
            ("RELATED_COOKIE_COUNT", String(relatedCount)),
            ("COOKIE_COUNT_DELTA", previousCount.map { String(relatedCount - $0) } ?? "NO_BASELINE"),
            ("COOKIE_SAMPLE_PHASE", "ALERT"),
            ("POST_COOKIE", "UNVERIFIED"),
            ("FLOW_MODE", automaticGenerationID == nil ? "MANUAL" : "AUTOMATIC"),
            ("DISPOSITION", disposition),
            ("RESULT", "OBSERVED")
        ]
        if let logContext {
            fields.insert(contentsOf: automaticLogMetadata(
                logContext,
                phase: "ALERT",
                event: category.rawValue,
                result: "OBSERVED"
            ), at: 0)
        }
        logStore.append(action: "Site Post Alert", fields: fields)
    }

    private func deleteRelatedCookiesForRefresh(identityRefresh: Bool,
                                                automaticGenerationID: UInt64?,
                                                reloadWhenNoCookie: Bool = false) async {
        guard let webView,
              let host = webView.url?.host?.lowercased() else {
            if identityRefresh {
                finishIdentityRefresh()
            }
            if let automaticGenerationID {
                stopAutomaticPost(.preparationFailed, generationID: automaticGenerationID)
            }
            isCookieRefreshing = false
            showToast("Cookie確認失敗", kind: .warning)
            return
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let before = await store.miniBrowserAllCookies()
        let targets = before.filter {
            CookieDomainMatcher.isRelated(cookieDomain: $0.domain, toHost: host)
        }

        if targets.isEmpty, !identityRefresh {
            logCookieRefresh(host: host, before: 0, deleted: 0, after: 0, result: "NO_COOKIE")
            if let automaticGenerationID, reloadWhenNoCookie {
                appendAutomaticEvent(
                    generationID: automaticGenerationID,
                    phase: "COOKIE",
                    event: "TIMEOUT_COOKIE_REFRESH_FAILED",
                    result: "STOPPED",
                    fields: [("REASON", "NO_COOKIE")]
                )
                stopAutomaticPost(.preparationFailed,
                                  generationID: automaticGenerationID)
            }
            showToast("Cookieなし", kind: .warning)
            isCookieRefreshing = false
            return
        }

        for cookie in targets {
            await store.miniBrowserDelete(cookie)
        }

        let afterDeletion = await store.miniBrowserAllCookies()
        if let automaticGenerationID,
           automaticPostMachine.generationID != automaticGenerationID ||
           automaticFinishedGenerations.contains(automaticGenerationID) {
            isCookieRefreshing = false
            return
        }
        let remaining = afterDeletion.filter {
            CookieDomainMatcher.isRelated(cookieDomain: $0.domain, toHost: host)
        }
        pendingCookieRefresh = PendingCookieRefresh(
            host: host,
            beforeCount: targets.count,
            deletedCount: max(0, targets.count - remaining.count),
            deletionConfirmed: remaining.isEmpty,
            identityRefresh: identityRefresh,
            automaticGenerationID: automaticGenerationID
        )
        if let automaticGenerationID {
            setAutomaticPostStatus(.checkingCookie, generationID: automaticGenerationID)
        }

        if identityRefresh {
            let purpose: APPurpose = automaticGenerationID.map {
                .identityRefresh(generationID: $0)
            } ?? .manual
            startCellularReconnect(reloadAfterCompletion: true, purpose: purpose)
        } else if webView.reload() == nil {
            failPendingCookieRefresh(result: "RELOAD_NOT_STARTED")
        }
    }

    private func updateCurrentURL(_ url: URL?) {
        guard let url, url.scheme != "about" else { return }
        currentURL = url
        urlText = url.absoluteString
        defaults.set(url.absoluteString, forKey: Keys.lastURL)
    }

    private func refreshNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }

    private func executeBookmarklet(_ source: String,
                                    failureMessage: String = "ブックマークレット実行失敗") {
        guard let webView else {
            showToast(failureMessage, kind: .failure)
            return
        }
        let script = Self.bookmarkletScript(from: source)
        // Bookmarklets often leave a DOM node or function as their completion
        // value. Force a bridgeable Boolean result without changing their
        // side effects; genuine JavaScript exceptions still reach the handler.
        let executableScript = "\(script)\n; true;"
        webView.evaluateJavaScript(executableScript) { [weak self] _, error in
            guard let self, let error else { return }
            self.showToast(failureMessage, kind: .failure)
            self.logStore.append(action: "Bookmarklet Execution", fields: [
                ("URL", LogSanitizer.url(self.currentURL)),
                ("UA", self.effectiveUserAgentLogLabel),
                ("ERROR_DOMAIN", (error as NSError).domain),
                ("ERROR_CODE", String((error as NSError).code)),
                ("DETAIL", error.localizedDescription),
                ("RESULT", "FAILED")
            ])
        }
    }

    private func runAutomaticBookmarklets(for url: URL?) {
        guard let host = url?.host else { return }
        let matches = bookmarkStore.items.filter {
            $0.kind == .bookmarklet &&
                BookmarkAutoRunMatcher.matches(host: host, configuredDomain: $0.autoRunDomain)
        }
        for item in matches {
            executeBookmarklet(item.content,
                               failureMessage: "自動ブックマークレット実行失敗")
        }
    }

    private static func bookmarkletScript(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if trimmed.lowercased().hasPrefix("javascript:") {
            body = String(trimmed.dropFirst("javascript:".count))
        } else {
            body = source
        }
        return body.removingPercentEncoding ?? body
    }

    private static func javaScriptStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func completeCookieRefreshAfterReload() async {
        guard let pending = pendingCookieRefresh else {
            return
        }
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else {
            pendingCookieRefresh = nil
            isCookieRefreshing = false
            if pending.identityRefresh { finishIdentityRefresh() }
            if let generationID = pending.automaticGenerationID {
                stopAutomaticPost(.preparationFailed, generationID: generationID)
            }
            return
        }
        let allAfterReload = await store.miniBrowserAllCookies()
        let after = allAfterReload.filter {
            CookieDomainMatcher.isRelated(cookieDomain: $0.domain, toHost: pending.host)
        }
        if let generationID = pending.automaticGenerationID,
           automaticPostMachine.generationID != generationID ||
           automaticFinishedGenerations.contains(generationID) {
            if pendingCookieRefresh?.automaticGenerationID == generationID {
                pendingCookieRefresh = nil
            }
            isCookieRefreshing = false
            return
        }
        let reloadObserved = pending.deletionConfirmed && !after.isEmpty &&
            (pending.beforeCount > 0 || pending.identityRefresh)
        logCookieRefresh(host: pending.host,
                         before: pending.beforeCount,
                         deleted: pending.deletedCount,
                         after: after.count,
                         result: reloadObserved ? "RELOADED_POST_COOKIE_UNVERIFIED" : "FAILED",
                         automaticGenerationID: pending.automaticGenerationID,
                         phase: "AFTER_RELOAD")
        if pending.automaticGenerationID != nil {
            let previousCount = lastRelatedCookieCountByHost[pending.host]
            automaticCookieRelatedCount = after.count
            automaticCookieCountDelta = previousCount.map { after.count - $0 }
        }
        lastRelatedCookieCountByHost[pending.host] = after.count
        showToast(reloadObserved ? "Cookie再読込完了（投稿用は未確認）" : "Cookie再取得失敗",
                  kind: reloadObserved ? .warning : .failure)
        pendingCookieRefresh = nil
        isCookieRefreshing = false
        if pending.identityRefresh {
            finishIdentityRefresh()
        }
        if let generationID = pending.automaticGenerationID {
            guard reloadObserved else {
                stopAutomaticPost(.preparationFailed, generationID: generationID)
                return
            }
            if automaticDraftRestorePendingGeneration == generationID {
                if let comment = automaticPostDraft?.comment,
                   !comment.isEmpty,
                   let pageURL = webView?.url {
                    restoreAutomaticDraftAfterCookieRefresh(
                        comment: comment,
                        generationID: generationID,
                        pageURL: pageURL
                    )
                } else {
                    automaticDraftRestorePendingGeneration = nil
                }
            }
            let effect = automaticPostMachine.handle(.markCookieObserved(generationID: generationID))
            handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    private func failPendingCookieRefresh(result: String) {
        guard let pending = pendingCookieRefresh else { return }
        logCookieRefresh(host: pending.host,
                         before: pending.beforeCount,
                         deleted: pending.deletedCount,
                         after: 0,
                         result: result,
                         automaticGenerationID: pending.automaticGenerationID,
                         phase: "FAILED")
        showToast("Cookie再取得失敗", kind: .failure)
        pendingCookieRefresh = nil
        isCookieRefreshing = false
        if pending.identityRefresh {
            finishIdentityRefresh()
        }
        if let generationID = pending.automaticGenerationID {
            stopAutomaticPost(.preparationFailed, generationID: generationID)
        }
    }

    private func logCookieRefresh(host: String,
                                  before: Int,
                                  deleted: Int,
                                  after: Int,
                                  result: String,
                                  automaticGenerationID: UInt64? = nil,
                                  phase: String = "REFRESH") {
        var fields = [
            ("URL", LogSanitizer.url(currentURL)),
            ("DOMAIN", host),
            ("UA", effectiveUserAgentLogLabel),
            ("COOKIE_BEFORE", String(before)),
            ("COOKIE_DELETED", String(deleted)),
            ("COOKIE_AFTER_RELOAD", String(after)),
            ("COOKIE_SAMPLE_PHASE", phase),
            ("FLOW_MODE", automaticGenerationID == nil ? "MANUAL" : "AUTOMATIC"),
            ("POST_COOKIE", "UNVERIFIED"),
            ("RESULT", result)
        ]
        if let automaticGenerationID,
           let context = automaticLogContext(generationID: automaticGenerationID) {
            fields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "COOKIE",
                event: "REFRESH_\(phase)",
                result: result
            ), at: 0)
        }
        logStore.append(action: "Cookie Refresh", fields: fields)
    }

    private static func cellularReconnectURL() -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: "セルラー再接続"),
            URLQueryItem(name: "x-success", value: "minibrowser://return?status=success"),
            URLQueryItem(name: "x-cancel", value: "minibrowser://return?status=cancel"),
            URLQueryItem(name: "x-error", value: "minibrowser://return?status=error")
        ]
        return components.url
    }

    private static func openExternalURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    private func fetchIPv4AfterRecovery() async -> String? {
        let delays: [UInt64] = [1_500_000_000, 2_000_000_000, 3_000_000_000, 4_000_000_000]
        for delay in delays {
            try? await Task.sleep(nanoseconds: delay)
            if let value = try? await ipService.fetchIPv4(userAgent: effectiveUserAgent) {
                return value
            }
        }
        return nil
    }

    private func completeAP(before: String?,
                            after: String?,
                            reloadAfterCompletion: Bool,
                            purpose: APPurpose) {
        if let generationID = Self.appPurposeGenerationID(purpose),
           (automaticPostMachine.generationID != generationID ||
            automaticFinishedGenerations.contains(generationID)) {
            if Self.appPurposeGenerationID(pendingAP?.purpose ?? .manual) == generationID {
                pendingAP = nil
                isAPRunning = false
            }
            return
        }
        let result: String
        if let before, let after {
            if before == after {
                result = "IP_UNCHANGED"
                showToast("IP変更なし", kind: .warning)
            } else {
                result = "IP_CHANGED"
                showToast("IP変更済み \(before) → \(after)", kind: .success, duration: 5)
            }
        } else {
            result = "IP_CHECK_FAILED"
            showToast("IP確認失敗", kind: .warning)
        }

        let automaticGenerationID: UInt64?
        let apPurpose: String
        switch purpose {
        case .manual:
            automaticGenerationID = nil
            apPurpose = "MANUAL"
        case let .identityRefresh(generationID):
            automaticGenerationID = generationID
            apPurpose = "UA_REFRESH"
        case let .automaticIPRetry(generationID):
            automaticGenerationID = generationID
            apPurpose = "AUTOMATIC_IP_RETRY"
        case let .automaticContinuousRetry(generationID):
            automaticGenerationID = generationID
            apPurpose = "AUTOMATIC_CONTINUOUS_RETRY"
        }
        var apFields = [
            ("IP_BEFORE", before ?? "UNAVAILABLE"),
            ("IP_AFTER", after ?? "UNAVAILABLE"),
            ("AP_PURPOSE", apPurpose),
            ("RESULT", result)
        ]
        if let automaticGenerationID,
           let context = automaticLogContext(generationID: automaticGenerationID) {
            apFields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "AP",
                event: "RECONNECT_COMPLETED",
                result: result
            ), at: 0)
        }
        logStore.append(action: "Cellular Reconnect", fields: apFields)
        pendingAP = nil
        isAPRunning = false

        switch purpose {
        case let .identityRefresh(generationID):
            guard automaticPostMachine.generationID == generationID else { break }
            automaticAPResult = after == nil ? "FAILED" : "COMPLETED"
            guard after != nil else {
                stopAutomaticPost(.preparationFailed, generationID: generationID)
                return
            }
            let effect = automaticPostMachine.handle(.markAPCompleted(generationID: generationID))
            handleAutomaticPostEffect(effect, generationID: generationID)
        case let .automaticIPRetry(generationID):
            guard automaticPostMachine.generationID == generationID else { break }
            automaticAPResult = after == nil ? "FAILED" : "RECONNECTED"
            guard after != nil else {
                stopAutomaticPost(.communicationFailure, generationID: generationID)
                return
            }
            let effect = automaticPostMachine.handle(
                .ipReconnectCompleted(generationID: generationID, success: true)
            )
            handleAutomaticPostEffect(effect, generationID: generationID)
        case let .automaticContinuousRetry(generationID):
            guard automaticPostMachine.generationID == generationID else { break }
            guard before != nil, after != nil else {
                automaticAPResult = "FAILED"
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "AP",
                    event: "CONTINUOUS_AP_RETRY_FAILED",
                    result: "STOPPED",
                    fields: [("RESULT", result)]
                )
                stopAutomaticPost(.communicationFailure, generationID: generationID)
                return
            }
            let ipChanged = before != after
            automaticAPResult = ipChanged ? "RECONNECTED" : "FAILED"
            guard ipChanged else {
                guard case .waitingForContinuousAPRetry = automaticPostMachine.state else {
                    return
                }
                let effect = automaticPostMachine.handle(
                    .continuousAPReconnectUnchanged(generationID: generationID)
                )
                if case .scheduleContinuousAPReconnectRetry = effect {
                    appendAutomaticEvent(
                        generationID: generationID,
                        phase: "AP",
                        event: "CONTINUOUS_AP_RETRY_UNCHANGED",
                        result: "RETRY_SCHEDULED",
                        fields: [
                            ("AP_ATTEMPT",
                             String(automaticPostMachine.continuousAPReconnectAttempts - 1)),
                            ("DELAY_MS",
                             String(Self.continuousAPRetryDelayNanoseconds / 1_000_000))
                        ]
                    )
                } else {
                    appendAutomaticEvent(
                        generationID: generationID,
                        phase: "AP",
                        event: "CONTINUOUS_AP_RETRY_FAILED",
                        result: "STOPPED",
                        fields: [
                            ("RESULT", result),
                            ("AP_ATTEMPT",
                             String(automaticPostMachine.continuousAPReconnectAttempts))
                        ]
                    )
                }
                handleAutomaticPostEffect(effect, generationID: generationID)
                return
            }
            appendAutomaticEvent(
                generationID: generationID,
                phase: "AP",
                event: "CONTINUOUS_AP_RETRY_SUCCEEDED",
                result: "IP_CHANGED"
            )
            automaticContinuousAPCompletedUptimeNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            let effect = automaticPostMachine.handle(
                .continuousAPReconnectCompleted(generationID: generationID, success: true)
            )
            handleAutomaticPostEffect(effect, generationID: generationID)
        case .manual:
            break
        }

        if reloadAfterCompletion {
            if case let .identityRefresh(generationID) = purpose,
               automaticPostMachine.generationID == generationID {
                automaticReloadGeneration = generationID
            }
            guard webView?.reload() != nil else {
                automaticReloadGeneration = nil
                failPendingCookieRefresh(result: "RELOAD_NOT_STARTED")
                return
            }
            return
        }
    }

    private func finishAPFailure(status: String,
                                 before: String?,
                                 reloadAfterCompletion: Bool,
                                 purpose: APPurpose) {
        if let generationID = Self.appPurposeGenerationID(purpose),
           (automaticPostMachine.generationID != generationID ||
            automaticFinishedGenerations.contains(generationID)) {
            if Self.appPurposeGenerationID(pendingAP?.purpose ?? .manual) == generationID {
                pendingAP = nil
                isAPRunning = false
            }
            return
        }
        showToast("IP確認失敗", kind: .warning)
        let automaticGenerationID: UInt64?
        let apPurpose: String
        switch purpose {
        case .manual:
            automaticGenerationID = nil
            apPurpose = "MANUAL"
        case let .identityRefresh(generationID):
            automaticGenerationID = generationID
            apPurpose = "UA_REFRESH"
        case let .automaticIPRetry(generationID):
            automaticGenerationID = generationID
            apPurpose = "AUTOMATIC_IP_RETRY"
        case let .automaticContinuousRetry(generationID):
            automaticGenerationID = generationID
            apPurpose = "AUTOMATIC_CONTINUOUS_RETRY"
        }
        var apFields = [
            ("IP_BEFORE", before ?? "UNAVAILABLE"),
            ("IP_AFTER", "UNAVAILABLE"),
            ("CALLBACK_STATUS", status),
            ("AP_PURPOSE", apPurpose),
            ("RESULT", "FAILED")
        ]
        if let automaticGenerationID,
           let context = automaticLogContext(generationID: automaticGenerationID) {
            apFields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "AP",
                event: "RECONNECT_FAILED",
                result: "FAILED"
            ), at: 0)
        }
        logStore.append(action: "Cellular Reconnect", fields: apFields)
        pendingAP = nil
        isAPRunning = false
        switch purpose {
        case .manual:
            break
        case let .identityRefresh(generationID):
            if automaticPostMachine.generationID == generationID {
                automaticAPResult = "FAILED"
            }
        case let .automaticIPRetry(generationID):
            if automaticPostMachine.generationID == generationID {
                automaticAPResult = "FAILED"
            }
        case let .automaticContinuousRetry(generationID):
            if automaticPostMachine.generationID == generationID {
                automaticAPResult = "FAILED"
            }
        }
        if reloadAfterCompletion {
            failPendingCookieRefresh(result: "AP_\(status)")
        }
        if case let .identityRefresh(generationID) = purpose {
            stopAutomaticPost(.preparationFailed, generationID: generationID)
        } else {
            switch purpose {
            case let .automaticIPRetry(generationID),
                 let .automaticContinuousRetry(generationID):
                stopAutomaticPost(.communicationFailure, generationID: generationID)
            case .manual, .identityRefresh:
                break
            }
        }
    }

    private func setMultiThreadStatusWithoutGeneration(_ status: AutomaticPostStatus) {
        guard multiThreadSessionActive else { return }
        automaticPostStatusTask?.cancel()
        automaticPostStatusTask = nil
        automaticPostStatus = status
    }

    private func scheduleNextMultiThread(generationID: UInt64,
                                         afterSkippedThread: Bool = false) {
        let canContinueAfterSkip: Bool
        if afterSkippedThread,
           case let .stopped(_, reason) = automaticPostMachine.state,
           reason == .threadPostingUnavailable ||
           reason == .threadUnavailable ||
           reason == .knownAlertAfterLimit {
            canContinueAfterSkip = true
        } else {
            canContinueAfterSkip = false
        }
        guard automaticPostMachine.generationID == generationID,
              (automaticPostMachine.state == .succeeded(generationID: generationID) ||
               canContinueAfterSkip),
              var session = multiThreadSession,
              session.currentGenerationID == generationID else {
            return
        }
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        if !afterSkippedThread {
            session.recordAcceptedPost()
        }
        session.markCurrentProcessed()

        guard !session.stopRequested else {
            multiThreadSession = session
            finishMultiThreadSession(generationID: generationID,
                                     result: "STOPPED_MULTI_THREAD_DISABLED")
            return
        }

        let nextResult = nextMultiThreadPostableTarget(session: &session)
        multiThreadSession = session
        if !nextResult.replyLimitSkippedIDs.isEmpty {
            logReplyLimitSkips(nextResult.replyLimitSkippedIDs,
                               generationID: generationID)
        }
        if let next = nextResult.target {
            multiThreadSession = session
            scheduleMultiThreadNavigation(sessionID: session.sessionID,
                                          generationID: generationID,
                                          target: next,
                                          skipped: false)
            return
        }

        guard !session.catalogRefreshUsed else {
            setAutomaticPostStatus(.completed, generationID: generationID)
            finishMultiThreadSession(generationID: generationID, result: "SUCCEEDED")
            return
        }

        session.catalogRefreshUsed = true
        multiThreadSession = session
        setAutomaticPostStatus(.refreshingCatalog, generationID: generationID)
        appendAutomaticEvent(
            generationID: generationID,
            phase: "CATALOG",
            event: "CATALOG_REFRESH_STARTED",
            result: "STARTED",
            fields: [
                ("SESSION_ID", String(session.sessionID)),
                ("SNAPSHOT_COUNT", String(session.snapshot.targets.count))
            ]
        )
        let sessionID = session.sessionID
        let processed = session.processedThreadIDs
        guard let provider = automaticCatalogProvider else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "CATALOG",
                event: "CATALOG_REFRESH_FAILED",
                result: "STOPPED",
                fields: [("REASON", "PROVIDER_MISSING")]
            )
            finishMultiThreadSession(generationID: generationID,
                                     result: "STOPPED_CATALOG_REFRESH_FAILED")
            return
        }
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = Task { @MainActor [weak self] in
            do {
                let refreshed = try await provider.refreshPostSnapshot(
                    excludingIDs: processed,
                    limit: 60
                )
                guard let self,
                      self.multiThreadSession?.sessionID == sessionID,
                      self.multiThreadSession?.currentGenerationID == generationID,
                      self.multiThreadEnabled else { return }
                var current = self.multiThreadSession!
                let beforeCount = current.snapshot.targets.count
                current.appendUnprocessedTargets(from: refreshed)
                self.multiThreadSession = current
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "CATALOG",
                    event: "CATALOG_REFRESH_COMPLETED",
                    result: "SUCCESS",
                    fields: [
                        ("SESSION_ID", String(sessionID)),
                        ("SNAPSHOT_COUNT", String(beforeCount)),
                        ("NEW_TARGET_COUNT", String(max(0, current.snapshot.targets.count - beforeCount)))
                    ]
                )
                self.multiThreadTransitionTask = nil
                let nextResult = self.nextMultiThreadPostableTarget(session: &current)
                self.multiThreadSession = current
                if !nextResult.replyLimitSkippedIDs.isEmpty {
                    self.logReplyLimitSkips(nextResult.replyLimitSkippedIDs,
                                            generationID: generationID)
                }
                if let next = nextResult.target {
                    self.multiThreadSession = current
                    self.scheduleMultiThreadNavigation(
                        sessionID: sessionID,
                        generationID: generationID,
                        target: next,
                        skipped: false
                    )
                } else {
                    self.setAutomaticPostStatus(.completed, generationID: generationID)
                    self.finishMultiThreadSession(generationID: generationID,
                                                  result: "SUCCEEDED")
                }
            } catch is CancellationError {
                // Cancellation is normally owned by OFF/newer-generation
                // cleanup. If the current session is still the owner, the
                // provider cancelled independently (for example because the
                // scene/network became unavailable) and must be settled.
                guard let self,
                      self.multiThreadSession?.sessionID == sessionID,
                      self.multiThreadSession?.currentGenerationID == generationID,
                      self.multiThreadEnabled else { return }
                self.multiThreadTransitionTask = nil
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "CATALOG",
                    event: "CATALOG_REFRESH_FAILED",
                    result: "STOPPED",
                    fields: [("REASON", "CANCELLED_CURRENT_SESSION")]
                )
                self.finishMultiThreadSession(
                    generationID: generationID,
                    result: "STOPPED_CATALOG_REFRESH_FAILED"
                )
            } catch {
                guard let self,
                      self.multiThreadSession?.sessionID == sessionID,
                      self.multiThreadSession?.currentGenerationID == generationID else { return }
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "CATALOG",
                    event: "CATALOG_REFRESH_FAILED",
                    result: "STOPPED",
                    fields: [("REASON", "REQUEST_FAILED")]
                )
                self.finishMultiThreadSession(
                    generationID: generationID,
                    result: "STOPPED_CATALOG_REFRESH_FAILED"
                )
            }
        }
    }

    /// Advances over stale snapshot entries that reached the 1,000-reply
    /// limit after the catalog was captured. Such entries are the only
    /// non-alert condition that removes a target from a running session.
    private func nextMultiThreadPostableTarget(
        session: inout MultiThreadPostSession
    ) -> (target: CatalogPostTarget?, replyLimitSkippedIDs: [String]) {
        var skippedIDs: [String] = []
        while let target = session.advanceToNextUnprocessed() {
            guard !target.isReplyLimitReached else {
                session.markCurrentProcessed()
                automaticCatalogProvider?.excludeThread(id: target.id)
                skippedIDs.append(target.id)
                continue
            }
            return (target, skippedIDs)
        }
        return (nil, skippedIDs)
    }

    private func logReplyLimitSkips(_ skippedIDs: [String],
                                   generationID: UInt64) {
        guard !skippedIDs.isEmpty else { return }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "FLOW",
            event: "THREAD_SKIPPED",
            result: "CONTINUE",
            fields: [
                ("REASON", "REPLY_LIMIT"),
                ("SKIPPED_COUNT", String(skippedIDs.count)),
                ("SKIPPED_THREAD_IDS", skippedIDs.joined(separator: ","))
            ]
        )
    }

    private func skipActiveMultiThreadTarget(generationID: UInt64,
                                             reason: String) {
        guard automaticPostMachine.generationID == generationID,
              automaticPostMachine.isMultiThread,
              automaticPostMachine.isActive,
              multiThreadSession?.currentGenerationID == generationID else {
            return
        }
        let effect = automaticPostMachine.skipCurrentThread(
            reason: .threadUnavailable
        )
        guard effect == .skipCurrentThread else { return }
        invalidateAutomaticGenerationForThreadSkip(generationID: generationID)
        appendAutomaticEvent(
            generationID: generationID,
            phase: "FLOW",
            event: "THREAD_SKIP_REQUESTED",
            result: "CONTINUE",
            fields: [("REASON", reason)]
        )
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    private func invalidateAutomaticGenerationForThreadSkip(
        generationID: UInt64,
        markFinished: Bool = true
    ) {
        if markFinished {
            automaticFinishedGenerations.insert(generationID)
        }
        automaticPostPreparationTimer?.cancel()
        automaticPostPreparationTimer = nil
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        cancelAutomaticSubmitResponseTimer()
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        cancelAutomaticContinuousAPRetryDelay()
        automaticReloadGeneration = nil
        if pendingCookieRefresh?.automaticGenerationID == generationID {
            pendingCookieRefresh = nil
            isCookieRefreshing = false
        }
        if let pendingAP,
           Self.appPurposeGenerationID(pendingAP.purpose) == generationID {
            self.pendingAP = nil
            isAPRunning = false
        }
        isIdentityRefreshInProgress = false
        isUAChanging = false
    }

    /// Advances a multi-thread session when the destination failed before a
    /// page generation could be created (for example, an HTTP/navigation
    /// failure or the early no-form bridge from a dropped thread).
    private func skipPendingMultiThreadTargetWithoutGeneration(
        sessionID: UInt64,
        target: CatalogPostTarget,
        reason: String
    ) {
        guard multiThreadEnabled,
              var session = multiThreadSession,
              session.sessionID == sessionID,
              session.currentTarget?.id == target.id else { return }

        pendingMultiThreadNavigation = nil
        pendingMultiThreadAvailabilityProbe = nil
        pendingMultiThreadUnavailable = nil
        session.markCurrentProcessed()
        automaticCatalogProvider?.excludeThread(id: target.id)
        multiThreadSession = session
        appendAutomaticEvent(
            generationID: session.currentGenerationID ?? automaticPostGeneration,
            phase: "FLOW",
            event: "THREAD_SKIPPED",
            result: "CONTINUE",
            fields: [
                ("REASON", reason),
                ("GENERATION_ID_STATE", "UNBOUND")
            ]
        )

        guard !session.stopRequested else {
            finishMultiThreadSession(generationID: session.currentGenerationID,
                                     result: "STOPPED_MULTI_THREAD_DISABLED")
            return
        }

        let nextResult = nextMultiThreadPostableTarget(session: &session)
        multiThreadSession = session
        if let generationID = session.currentGenerationID {
            logReplyLimitSkips(nextResult.replyLimitSkippedIDs,
                               generationID: generationID)
        }
        if let next = nextResult.target {
            scheduleMultiThreadNavigationWithoutGeneration(
                sessionID: session.sessionID,
                target: next,
                skipped: true
            )
            return
        }

        guard !session.catalogRefreshUsed else {
            finishMultiThreadSession(generationID: session.currentGenerationID,
                                     result: "SUCCEEDED")
            return
        }
        refreshMultiThreadCatalogWithoutGeneration(sessionID: session.sessionID)
    }

    private func scheduleMultiThreadNavigationWithoutGeneration(
        sessionID: UInt64,
        target: CatalogPostTarget,
        skipped: Bool
    ) {
        guard multiThreadSession?.sessionID == sessionID,
              multiThreadEnabled,
              let webView else { return }
        let delayNanoseconds: UInt64 = skipped ? 0 : Self.multiThreadSuccessWaitNanoseconds
        setMultiThreadStatusWithoutGeneration(.waitingForNextThread)
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.multiThreadEnabled,
                  self.multiThreadSession?.sessionID == sessionID,
                  self.multiThreadSession?.currentTarget?.id == target.id else {
                return
            }
            self.setMultiThreadStatusWithoutGeneration(.navigatingToNextThread)
            self.pendingMultiThreadAvailabilityProbe = nil
            self.pendingMultiThreadNavigation = (sessionID, target)
            self.pendingMultiThreadUnavailable = nil
            self.appendAutomaticEvent(
                generationID: self.multiThreadSession?.currentGenerationID ??
                    self.automaticPostGeneration,
                phase: "NAVIGATION",
                event: "NEXT_THREAD_NAVIGATION_STARTED",
                result: "STARTED",
                fields: [("GENERATION_ID_STATE", "UNBOUND")]
            )
            guard webView.load(URLRequest(url: target.threadURL)) != nil else {
                self.pendingMultiThreadNavigation = nil
                self.skipPendingMultiThreadTargetWithoutGeneration(
                    sessionID: sessionID,
                    target: target,
                    reason: "NAVIGATION_LOAD_FAILED"
                )
                return
            }
            self.multiThreadTransitionTask = nil
        }
    }

    private func refreshMultiThreadCatalogWithoutGeneration(sessionID: UInt64) {
        guard var session = multiThreadSession,
              session.sessionID == sessionID,
              !session.catalogRefreshUsed,
              let provider = automaticCatalogProvider else {
            finishMultiThreadSession(generationID: multiThreadSession?.currentGenerationID,
                                     result: "SUCCEEDED")
            return
        }
        session.catalogRefreshUsed = true
        multiThreadSession = session
        setMultiThreadStatusWithoutGeneration(.refreshingCatalog)
        let processed = session.processedThreadIDs
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = Task { @MainActor [weak self] in
            do {
                let refreshed = try await provider.refreshPostSnapshot(
                    excludingIDs: processed,
                    limit: 60
                )
                guard let self,
                      self.multiThreadEnabled,
                      var current = self.multiThreadSession,
                      current.sessionID == sessionID else { return }
                current.appendUnprocessedTargets(from: refreshed)
                self.multiThreadSession = current
                self.multiThreadTransitionTask = nil
                let nextResult = self.nextMultiThreadPostableTarget(session: &current)
                self.multiThreadSession = current
                if let next = nextResult.target {
                    self.scheduleMultiThreadNavigationWithoutGeneration(
                        sessionID: sessionID,
                        target: next,
                        skipped: true
                    )
                } else {
                    self.finishMultiThreadSession(
                        generationID: current.currentGenerationID,
                        result: "SUCCEEDED"
                    )
                }
            } catch {
                guard let self,
                      self.multiThreadSession?.sessionID == sessionID else { return }
                self.multiThreadTransitionTask = nil
                self.finishMultiThreadSession(
                    generationID: self.multiThreadSession?.currentGenerationID,
                    result: "STOPPED_CATALOG_REFRESH_FAILED"
                )
            }
        }
    }

    private func scheduleMultiThreadNavigation(sessionID: UInt64,
                                               generationID: UInt64,
                                               target: CatalogPostTarget,
                                               skipped: Bool) {
        guard multiThreadSession?.sessionID == sessionID,
              multiThreadEnabled,
              let webView else { return }
        let delayNanoseconds: UInt64 = skipped ? 0 : Self.multiThreadSuccessWaitNanoseconds
        setAutomaticPostStatus(.waitingForNextThread, generationID: generationID)
        appendAutomaticEvent(
            generationID: generationID,
            phase: "FLOW",
            event: skipped ? "THREAD_SKIPPED" : "NEXT_THREAD_SCHEDULED",
            result: "SCHEDULED",
            fields: [
                ("TARGET_INDEX", String(multiThreadSession?.currentIndex ?? 0)),
                ("DELAY_MS", String(delayNanoseconds / 1_000_000))
            ]
        )
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.multiThreadEnabled,
                  self.multiThreadSession?.sessionID == sessionID,
                  self.multiThreadSession?.currentGenerationID == generationID else { return }
            guard let currentTarget = self.multiThreadSession?.currentTarget,
                  currentTarget.id == target.id else { return }
            self.setAutomaticPostStatus(.navigatingToNextThread,
                                        generationID: generationID)
            self.pendingMultiThreadAvailabilityProbe = nil
            self.pendingMultiThreadNavigation = (sessionID, target)
            self.pendingMultiThreadUnavailable = nil
            self.appendAutomaticEvent(
                generationID: generationID,
                phase: "NAVIGATION",
                event: "NEXT_THREAD_NAVIGATION_STARTED",
                result: "STARTED",
                fields: [("TARGET_INDEX", String(self.multiThreadSession?.currentIndex ?? 0))]
            )
            guard webView.load(URLRequest(url: target.threadURL)) != nil else {
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "NAVIGATION",
                    event: "NEXT_THREAD_NAVIGATION_FAILED",
                    result: "STOPPED"
                )
                self.pendingMultiThreadNavigation = nil
                self.skipPendingMultiThreadTargetWithoutGeneration(
                    sessionID: sessionID,
                    target: target,
                    reason: "NAVIGATION_LOAD_FAILED"
                )
                return
            }
            self.multiThreadTransitionTask = nil
        }
    }

    private func skipCurrentMultiThreadThread(
        generationID: UInt64,
        reason: String = "THREAD_POSTING_UNAVAILABLE",
        excludeFromCatalog: Bool = true
    ) {
        guard var session = multiThreadSession,
              session.currentGenerationID == generationID else { return }
        session.markCurrentProcessed()
        if excludeFromCatalog,
           let targetID = session.currentTarget?.id {
            automaticCatalogProvider?.excludeThread(id: targetID)
        }
        multiThreadSession = session
        appendAutomaticEvent(
            generationID: generationID,
            phase: "FLOW",
            event: "THREAD_SKIPPED",
            result: "CONTINUE",
            fields: [("REASON", reason)]
        )
        guard !session.stopRequested else {
            multiThreadSession = session
            scheduleNextMultiThread(generationID: generationID,
                                    afterSkippedThread: true)
            return
        }
        let nextResult = nextMultiThreadPostableTarget(session: &session)
        multiThreadSession = session
        logReplyLimitSkips(nextResult.replyLimitSkippedIDs,
                           generationID: generationID)
        guard let next = nextResult.target else {
            scheduleNextMultiThread(generationID: generationID,
                                    afterSkippedThread: true)
            return
        }
        scheduleMultiThreadNavigation(sessionID: session.sessionID,
                                      generationID: generationID,
                                      target: next,
                                      skipped: true)
    }

    private func finishMultiThreadSession(generationID: UInt64?, result: String) {
        let activeGenerationID = generationID ?? automaticPostMachine.generationID
        let hadSession = multiThreadSession != nil
        let finalLogContext = multiThreadSession.map {
            MultiThreadLogContext(
                sessionID: $0.sessionID,
                targetIndex: $0.currentIndex + 1,
                threadID: $0.currentTargetID
            )
        }
        if let activeGenerationID {
            automaticPostMachine.forceTerminate(generationID: activeGenerationID)
        }
        multiThreadTransitionTask?.cancel()
        multiThreadTransitionTask = nil
        cancelAutomaticContinuousAPRetryDelay()
        pendingMultiThreadNavigation = nil
        pendingMultiThreadAvailabilityProbe = nil
        pendingMultiThreadUnavailable = nil
        pendingHandwritingRestore = nil
        stopIsolationMonitoring(clearContext: true)
        multiThreadSession = nil
        multiThreadSessionActive = false
        multiThreadEnabled = false
        guard let activeGenerationID,
              automaticPostMachine.generationID == activeGenerationID else {
            clearAutomaticPostDraft()
            if hadSession {
                setAutomaticPostStatusWithoutGeneration(
                    result.hasPrefix("STOPPED") ? .stopped : .completed
                )
            }
            updateIdleTimerState()
            return
        }
        if result.hasPrefix("STOPPED") {
            setAutomaticPostStatus(.stopped, generationID: activeGenerationID)
        } else {
            setAutomaticPostStatus(.completed, generationID: activeGenerationID)
        }
        finishAutomaticPost(generationID: activeGenerationID,
                            result: result,
                            multiThreadContext: finalLogContext)
    }

    private func handleAutomaticPostEffect(_ effect: AutomaticPostFlowEffect,
                                           generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID else {
            updateIdleTimerState()
            return
        }
        if multiThreadSession?.stopRequested == true,
           automaticPostMachine.isActive {
            let stopEffect = automaticPostMachine.stop(.repeatDisabled)
            handleAutomaticPostEffect(stopEffect, generationID: generationID)
            return
        }
        defer { updateIdleTimerState() }
        switch effect {
        case .none:
            break
        case let .startSubmitReadiness(attempt, reason):
            if reason == .initial || reason == .sameThreadRepeat {
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "PREPARATION",
                    event: reason == .sameThreadRepeat
                        ? "REPEAT_PREPARATION_READY"
                        : "PREPARATION_READY",
                    result: "READY",
                    fields: [
                        ("AP_RESULT", automaticAPResult),
                        ("COOKIE_RELATED_COUNT", automaticCookieRelatedCount.map { String($0) } ?? "UNAVAILABLE"),
                        ("COOKIE_COUNT_DELTA", automaticCookieCountDelta.map { String($0) } ?? "UNAVAILABLE")
                    ]
                )
            }
            setAutomaticPostStatus(
                reason == .sameThreadRepeat
                    ? .waitingForRepeat
                    : reason == .submitResponseRetry ? .sending : .checkingCookie,
                generationID: generationID
            )
            startAutomaticSubmitReadiness(generationID: generationID,
                                          attempt: attempt,
                                          reason: reason)
        case .scheduleSubmitDelay:
            scheduleSubmitDelay(generationID: generationID)
        case let .submit(attempt):
            submitAutomatically(attempt: attempt, generationID: generationID)
        case .startIPReconnect:
            appendAutomaticEvent(
                generationID: generationID,
                phase: "AP",
                event: "RECONNECT_REQUESTED",
                result: "STARTED",
                fields: [("AP_PURPOSE", "AUTOMATIC_IP_RETRY")]
            )
            setAutomaticPostStatus(.reconnectingAfterIPLimit, generationID: generationID)
            startCellularReconnect(
                reloadAfterCompletion: false,
                purpose: .automaticIPRetry(generationID: generationID)
            )
        case .startContinuousAPReconnect:
            cancelAutomaticContinuousAPRetryDelay()
            appendAutomaticEvent(
                generationID: generationID,
                phase: "AP",
                event: "CONTINUOUS_AP_RETRY",
                result: "STARTED",
                fields: [
                    ("AP_ATTEMPT", String(automaticPostMachine.continuousAPReconnectAttempts)),
                    ("AP_PURPOSE", "AUTOMATIC_CONTINUOUS_RETRY")
                ]
            )
            setAutomaticPostStatus(.reconnectingAfterContinuousLimit,
                                   generationID: generationID)
            startCellularReconnect(
                reloadAfterCompletion: false,
                purpose: .automaticContinuousRetry(generationID: generationID)
            )
        case .scheduleContinuousAPReconnectRetry:
            scheduleContinuousAPReconnectRetry(generationID: generationID)
        case .startCookieRefreshAfterTimeout:
            appendAutomaticEvent(
                generationID: generationID,
                phase: "COOKIE",
                event: "TIMEOUT_COOKIE_REFRESH_REQUESTED",
                result: "STARTED",
                fields: [("REASON", "SUBMIT_RESPONSE_RETRY_TIMEOUT")]
            )
            setAutomaticPostStatus(.checkingCookie, generationID: generationID)
            startAutomaticCookieRefreshAfterTimeout(previousGenerationID: generationID)
        case .startNextAutomaticFlow:
            appendAutomaticEvent(
                generationID: generationID,
                phase: "FLOW",
                event: "ACCESS_RESTRICTED_HANDOFF",
                result: "NEXT_UA_REQUESTED"
            )
            setAutomaticPostStatus(.switchingAfterAccessRestriction,
                                   generationID: generationID)
            startNextAutomaticFlow(previousGenerationID: generationID)
        case .handoffAfterContinuousLimit:
            guard var session = multiThreadSession,
                  session.currentGenerationID == generationID else {
                let stopEffect = automaticPostMachine.stop(.knownAlertAfterLimit)
                handleAutomaticPostEffect(stopEffect, generationID: generationID)
                return
            }
            if !session.continuousRestrictionHandoffUsed {
                session.continuousRestrictionHandoffUsed = true
                multiThreadSession = session
                appendAutomaticEvent(
                    generationID: generationID,
                    phase: "FLOW",
                    event: "CONTINUOUS_UA_HANDOFF",
                    result: "NEXT_UA_REQUESTED",
                    fields: [
                        ("TARGET_INDEX", String(session.currentIndex)),
                        ("REASON", "CONTINUOUS_POSTING_AFTER_LIMIT")
                    ]
                )
                setAutomaticPostStatus(.switchingAfterContinuousLimit,
                                       generationID: generationID)
                startNextAutomaticFlow(previousGenerationID: generationID)
            } else {
                // The same target has already received its one bounded UA
                // handoff. Do not terminate the whole batch for a repeated
                // short restriction; settle this target and continue with
                // the remaining snapshot entries under the current session.
                // The generation is already terminal, so no late callback can
                // advance it. Keep it out of the finished tombstone set when
                // the session may still need to finalize through this same
                // generation after the target is skipped.
                invalidateAutomaticGenerationForThreadSkip(
                    generationID: generationID,
                    markFinished: false
                )
                setAutomaticPostStatus(.waitingForNextThread,
                                       generationID: generationID)
                skipCurrentMultiThreadThread(
                    generationID: generationID,
                    reason: "CONTINUOUS_POSTING_AFTER_UA_HANDOFF",
                    excludeFromCatalog: false
                )
            }
        case .skipCurrentThread:
            guard multiThreadSession != nil else {
                let stopEffect = automaticPostMachine.stop(.threadPostingUnavailable)
                handleAutomaticPostEffect(stopEffect, generationID: generationID)
                return
            }
            setAutomaticPostStatus(.waitingForNextThread, generationID: generationID)
            let skipReason: String
            if case let .stopped(_, reason) = automaticPostMachine.state {
                switch reason {
                case .threadUnavailable:
                    skipReason = "THREAD_UNAVAILABLE"
                case .threadPostingUnavailable:
                    skipReason = "THREAD_POSTING_UNAVAILABLE"
                default:
                    skipReason = "THREAD_UNAVAILABLE"
                }
            } else {
                skipReason = "THREAD_UNAVAILABLE"
            }
            skipCurrentMultiThreadThread(generationID: generationID,
                                         reason: skipReason)
        case .succeeded:
            if multiThreadSession != nil {
                if let targetID = multiThreadSession?.currentTarget?.id {
                    automaticCatalogProvider?.markThreadRead(id: targetID)
                }
                automaticPostVerificationTask?.cancel()
                automaticPostVerificationTask = nil
                scheduleNextMultiThread(generationID: generationID)
                return
            }
            if let session = automaticPostRepeatSession {
                if let targetID = ThreadListViewModel.threadID(from: session.pageURL) {
                    automaticCatalogProvider?.markThreadRead(id: targetID)
                }
                guard sameThreadRepeatEnabled, !session.stopRequested else {
                    clearAutomaticPostDraft()
                    setAutomaticPostStatus(.completed, generationID: generationID)
                    finishAutomaticPost(generationID: generationID, result: "SUCCEEDED")
                    return
                }
                automaticPostVerificationTask?.cancel()
                automaticPostVerificationTask = nil
                scheduleAutomaticPostRepeat(generationID: generationID)
                return
            }
            clearAutomaticPostDraft()
            if automaticPostAccepted && !automaticOwnResponseConfirmed {
                setAutomaticPostStatus(.acceptedPendingVerification,
                                       generationID: generationID)
                if automaticPostVerificationTask == nil {
                    scheduleAutomaticPostVerificationTimeout(generationID: generationID)
                }
            } else {
                setAutomaticPostStatus(.completed, generationID: generationID)
                finishAutomaticPost(generationID: generationID, result: "SUCCEEDED")
            }
        case let .stopped(reason):
            setAutomaticPostStatus(.stopped, generationID: generationID)
            automaticPostVerificationTask?.cancel()
            automaticPostVerificationTask = nil
            if multiThreadSession != nil {
                finishMultiThreadSession(generationID: generationID,
                                         result: Self.automaticStopResult(for: reason))
            } else {
                finishAutomaticPost(generationID: generationID,
                                    result: Self.automaticStopResult(for: reason))
            }
        }
    }

    private func startAutomaticSubmitReadiness(generationID: UInt64,
                                               attempt: Int,
                                               reason: AutomaticPostReadinessReason) {
        guard automaticPostMachine.generationID == generationID,
              case .waitingForSubmitReadiness = automaticPostMachine.state,
              automaticPostMachine.currentAttempt == attempt else {
            return
        }
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = reason
        appendAutomaticEvent(
            generationID: generationID,
            phase: "READINESS",
            event: "READINESS_STARTED",
            result: "STARTED",
            fields: [
                ("ATTEMPT", String(attempt)),
                ("REASON", reason.rawValue)
            ]
        )

        automaticSubmitReadinessDeadline = Date().addingTimeInterval(10)
        automaticSubmitReadinessTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  case .waitingForSubmitReadiness = self.automaticPostMachine.state,
                  self.automaticPostMachine.currentAttempt == attempt else {
                return
            }
            self.requestAutomaticSubmitReadiness(generationID: generationID,
                                                 attempt: attempt,
                                                 reason: reason)
        }
    }

    private func requestAutomaticSubmitReadiness(generationID: UInt64,
                                                 attempt: Int,
                                                 reason: AutomaticPostReadinessReason) {
        guard automaticPostMachine.generationID == generationID,
              case .waitingForSubmitReadiness = automaticPostMachine.state,
              automaticPostMachine.currentAttempt == attempt else {
            return
        }
        guard let deadline = automaticSubmitReadinessDeadline,
              Date() < deadline else {
            handleAutomaticSubmitReadinessTimeout(generationID: generationID,
                                                  attempt: attempt,
                                                  reason: reason)
            return
        }
        guard let webView else {
            stopAutomaticPost(.communicationFailure, generationID: generationID)
            return
        }
        webView.evaluateJavaScript(CompactPageModeService.submitReadinessScript) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.automaticPostMachine.generationID == generationID,
                      case .waitingForSubmitReadiness = self.automaticPostMachine.state,
                      self.automaticPostMachine.currentAttempt == attempt else {
                    return
                }
                if let error,
                   self.automaticSubmitReadinessLastReason != "EVALUATION_FAILED" {
                    self.automaticSubmitReadinessLastReason = "EVALUATION_FAILED"
                    let nsError = error as NSError
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "READINESS",
                        event: "EVALUATION_FAILED",
                        result: "RETRYING",
                        fields: [
                            ("ATTEMPT", String(attempt)),
                            ("REASON", reason.rawValue),
                            ("ERROR_DOMAIN", nsError.domain),
                            ("ERROR_CODE", String(nsError.code))
                        ]
                    )
                }
                let javascriptResult = Self.javascriptBoolean(result)
                if error == nil,
                   javascriptResult == false,
                   !self.automaticSubmitReadinessFalseLogged {
                    self.automaticSubmitReadinessFalseLogged = true
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "READINESS",
                        event: "EVALUATION_FALSE",
                        result: "RETRYING",
                        fields: [
                            ("ATTEMPT", String(attempt)),
                            ("REASON", self.automaticSubmitReadinessLastReason ?? reason.rawValue),
                            ("STAGE", "SUBMIT_READINESS")
                        ]
                    )
                } else if error == nil,
                          javascriptResult == nil,
                          !self.automaticSubmitReadinessFalseLogged {
                    self.automaticSubmitReadinessFalseLogged = true
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "READINESS",
                        event: "EVALUATION_RESULT_INVALID",
                        result: "RETRYING",
                        fields: [
                            ("ATTEMPT", String(attempt)),
                            ("REASON", reason.rawValue),
                            ("STAGE", "SUBMIT_READINESS")
                        ]
                    )
                }
                guard let deadline = self.automaticSubmitReadinessDeadline,
                      Date() < deadline else {
                    self.handleAutomaticSubmitReadinessTimeout(
                        generationID: generationID,
                        attempt: attempt,
                        reason: reason
                    )
                    return
                }
                self.automaticSubmitReadinessTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self,
                          !Task.isCancelled,
                          self.automaticPostMachine.generationID == generationID,
                          case .waitingForSubmitReadiness = self.automaticPostMachine.state,
                          self.automaticPostMachine.currentAttempt == attempt else {
                        return
                    }
                    self.requestAutomaticSubmitReadiness(generationID: generationID,
                                                         attempt: attempt,
                                                         reason: reason)
                }
            }
        }
    }

    private func handleAutomaticSubmitReadinessTimeout(generationID: UInt64,
                                                       attempt: Int,
                                                       reason: AutomaticPostReadinessReason) {
        guard automaticPostMachine.generationID == generationID,
              case .waitingForSubmitReadiness = automaticPostMachine.state else {
            return
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "READINESS",
            event: "READINESS_TIMEOUT",
            result: "STOPPED",
            fields: [
                ("ATTEMPT", String(attempt)),
                ("REASON", reason.rawValue)
            ]
        )
        let effect = automaticPostMachine.handle(
            .submitReadinessTimedOut(generationID: generationID)
        )
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    private func scheduleAutomaticPostRepeat(generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID,
              case .succeeded = automaticPostMachine.state,
              sameThreadRepeatEnabled,
              var session = automaticPostRepeatSession,
              !session.stopRequested,
              let pageURL = webView?.url,
              Self.isTargetThreadURL(pageURL),
              let pageToken = automaticPostMachine.pageToken else {
            return
        }
        guard pageURL.path == session.pageURL.path,
              pageURL.host?.lowercased() == session.pageURL.host?.lowercased() else {
            setAutomaticPostStatus(.stopped, generationID: generationID)
            finishAutomaticPost(generationID: generationID,
                                result: "STOPPED_PAGE_NAVIGATION")
            return
        }

        session.cycle += 1
        session.pageToken = pageToken
        automaticPostRepeatSession = session
        setAutomaticPostStatus(.waitingForRepeat, generationID: generationID)
        appendAutomaticEvent(
            generationID: generationID,
            phase: "REPEAT",
            event: "REPEAT_SCHEDULED",
            result: "SCHEDULED",
            fields: [
                ("DELAY_MS", String(Self.sameThreadRepeatMinimumDelayNanoseconds / 1_000_000))
            ]
        )

        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.sameThreadRepeatMinimumDelayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.sameThreadRepeatEnabled,
                  self.automaticPostMachine.generationID == generationID,
                  case .succeeded = self.automaticPostMachine.state else {
                return
            }
            self.automaticPostRepeatDelayTask = nil
            self.beginAutomaticPostRepeat(previousGenerationID: generationID)
        }
    }

    private func beginAutomaticPostRepeat(previousGenerationID: UInt64) {
        guard automaticPostMachine.generationID == previousGenerationID,
              case .succeeded = automaticPostMachine.state,
              sameThreadRepeatEnabled,
              let session = automaticPostRepeatSession,
              !session.stopRequested,
              let webView,
              let pageURL = webView.url,
              Self.isTargetThreadURL(pageURL),
              pageURL.path == session.pageURL.path,
              pageURL.host?.lowercased() == session.pageURL.host?.lowercased(),
              let pageToken = session.pageToken,
              automaticPostMachine.pageToken == pageToken else {
            if automaticPostMachine.generationID == previousGenerationID {
                setAutomaticPostStatus(.stopped, generationID: previousGenerationID)
                finishAutomaticPost(generationID: previousGenerationID,
                                    result: "STOPPED_PAGE_NAVIGATION")
            }
            return
        }

        automaticPostGeneration &+= 1
        let generationID = automaticPostGeneration
        automaticPostMachine.reset()
        let beginEffect = automaticPostMachine.beginSameThreadRepeat(
            generationID: generationID,
            pageToken: pageToken,
            hasComment: session.comment?.isEmpty == false,
            hasImage: session.hasImage,
            submissionIDSeed: nextAutomaticSubmissionSeed()
        )
        automaticPostDraft = AutomaticPostDraft(
            hasComment: session.comment?.isEmpty == false,
            comment: session.comment,
            hasImage: session.hasImage
        )
        beginAutomaticGenerationLogging(generationID: generationID)
        latestCompactReady = nil
        automaticCookieRelatedCount = nil
        automaticCookieCountDelta = nil
        automaticAPResult = "NOT_REQUESTED"
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        cancelAutomaticContinuousAPRetryDelay()
        setAutomaticPostStatus(.waitingForRepeat, generationID: generationID)
        startAutomaticPostPreparationTimeout(generationID: generationID)
        updateIdleTimerState()

        if case let .stopped(reason) = beginEffect {
            handleAutomaticPostEffect(.stopped(reason), generationID: generationID)
            return
        }
        guard let restoreScript = CompactPageModeService.restoreAutomaticDraftScript(
            comment: session.comment ?? ""
        ) else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "REPEAT",
                event: "REPEAT_PREPARATION_FAILED",
                result: "STOPPED",
                fields: [
                    ("PATH", "COMMENT_RESTORE"),
                    ("FAILURE_REASON", "SCRIPT_UNAVAILABLE")
                ]
            )
            stopAutomaticPost(.communicationFailure, generationID: generationID)
            return
        }
        webView.evaluateJavaScript(restoreScript) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.automaticPostMachine.generationID == generationID,
                      case .preparing = self.automaticPostMachine.state else { return }
                let didRestore = Self.javascriptBoolean(result) ?? false
                guard error == nil, didRestore else {
                    var fields = [
                        ("PATH", "COMMENT_RESTORE"),
                        ("JS_RESULT", didRestore ? "TRUE" : "FALSE")
                    ]
                    if let error {
                        let nsError = error as NSError
                        fields.append(("ERROR_DOMAIN", nsError.domain))
                        fields.append(("ERROR_CODE", String(nsError.code)))
                    } else {
                        fields.append(("FAILURE_REASON", "JS_RETURNED_FALSE"))
                    }
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "REPEAT",
                        event: "REPEAT_PREPARATION_FAILED",
                        result: "STOPPED",
                        fields: fields
                    )
                    self.stopAutomaticPost(.preparationFailed, generationID: generationID)
                    return
                }
                guard session.hasImage else { return }
                self.prepareRepeatImage(generationID: generationID,
                                       webView: webView)
            }
        }
    }

    private func prepareRepeatImage(generationID: UInt64, webView: WKWebView) {
        guard automaticPostMachine.generationID == generationID,
              case .preparing = automaticPostMachine.state else { return }
        webView.evaluateJavaScript(CanvasImageSessionService.canvasVisibilityScript) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.automaticPostMachine.generationID == generationID,
                      case .preparing = self.automaticPostMachine.state else { return }
                guard error == nil else {
                    var fields = [("PATH", "CANVAS_VISIBILITY")]
                    if let error {
                        let nsError = error as NSError
                        fields.append(("ERROR_DOMAIN", nsError.domain))
                        fields.append(("ERROR_CODE", String(nsError.code)))
                    }
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "REPEAT",
                        event: "REPEAT_IMAGE_PREPARATION_FAILED",
                        result: "STOPPED",
                        fields: fields
                    )
                    self.stopAutomaticPost(.communicationFailure, generationID: generationID)
                    return
                }
                let state = result as? [String: Any]
                let exists = (state?["exists"] as? Bool) ?? false
                let visible = (state?["visible"] as? Bool) ?? false
                if state?["exists"] as? Bool == nil ||
                    state?["visible"] as? Bool == nil {
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "REPEAT",
                        event: "REPEAT_IMAGE_PREPARATION_RESULT_INVALID",
                        result: "RETRYING",
                        fields: [
                            ("PATH", "CANVAS_VISIBILITY"),
                            ("JS_RESULT", "INVALID")
                        ]
                    )
                }
                if visible {
                    self.runRepeatCanvasUpdate(generationID: generationID,
                                               webView: webView)
                } else {
                    webView.evaluateJavaScript(
                        CanvasImageSessionService.openExistingCanvasScript
                    ) { [weak self] result, error in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.automaticPostMachine.generationID == generationID,
                                  case .preparing = self.automaticPostMachine.state else { return }
                            if let error {
                                var fields = [(
                                    "PATH", "CANVAS_OPEN"
                                )]
                                let nsError = error as NSError
                                fields.append(("ERROR_DOMAIN", nsError.domain))
                                fields.append(("ERROR_CODE", String(nsError.code)))
                                self.appendAutomaticEvent(
                                    generationID: generationID,
                                    phase: "REPEAT",
                                    event: "REPEAT_IMAGE_PREPARATION_FAILED",
                                    result: "STOPPED",
                                    fields: fields
                                )
                                self.stopAutomaticPost(.communicationFailure,
                                                        generationID: generationID)
                            } else if Self.javascriptBoolean(result) == false {
                                self.appendAutomaticEvent(
                                    generationID: generationID,
                                    phase: "REPEAT",
                                    event: "REPEAT_IMAGE_PREPARATION_FAILED",
                                    result: "STOPPED",
                                    fields: [
                                        ("PATH", "CANVAS_OPEN"),
                                        ("JS_RESULT", "FALSE"),
                                        ("FAILURE_REASON", "JS_RETURNED_FALSE")
                                    ]
                                )
                                self.stopAutomaticPost(.preparationFailed,
                                                        generationID: generationID)
                            } else if exists {
                                self.waitForRepeatCanvasVisibility(
                                    generationID: generationID,
                                    webView: webView,
                                    attempt: 0
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func waitForRepeatCanvasVisibility(generationID: UInt64,
                                               webView: WKWebView,
                                               attempt: Int) {
        guard automaticPostMachine.generationID == generationID,
              case .preparing = automaticPostMachine.state else { return }
        guard attempt < 50 else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "REPEAT",
                event: "REPEAT_IMAGE_CANVAS_VISIBILITY_TIMEOUT",
                result: "WAITING_FOR_PREPARATION_TIMEOUT",
                fields: [
                    ("PATH", "CANVAS_VISIBILITY"),
                    ("ATTEMPTS", "50")
                ]
            )
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  case .preparing = self.automaticPostMachine.state else { return }
            webView.evaluateJavaScript(CanvasImageSessionService.canvasVisibilityScript) {
                [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.automaticPostMachine.generationID == generationID,
                          case .preparing = self.automaticPostMachine.state else { return }
                    guard error == nil else {
                        var fields = [("PATH", "CANVAS_VISIBILITY")]
                        if let error {
                            let nsError = error as NSError
                            fields.append(("ERROR_DOMAIN", nsError.domain))
                            fields.append(("ERROR_CODE", String(nsError.code)))
                        }
                        self.appendAutomaticEvent(
                            generationID: generationID,
                            phase: "REPEAT",
                            event: "REPEAT_IMAGE_PREPARATION_FAILED",
                            result: "STOPPED",
                            fields: fields
                        )
                        self.stopAutomaticPost(.communicationFailure,
                                                generationID: generationID)
                        return
                    }
                    let state = result as? [String: Any]
                    if state?["visible"] as? Bool == nil {
                        self.appendAutomaticEvent(
                            generationID: generationID,
                            phase: "REPEAT",
                            event: "REPEAT_IMAGE_PREPARATION_RESULT_INVALID",
                            result: "RETRYING",
                            fields: [
                                ("PATH", "CANVAS_VISIBILITY"),
                                ("JS_RESULT", "INVALID")
                            ]
                        )
                    }
                    if (state?["visible"] as? Bool) == true {
                        self.runRepeatCanvasUpdate(generationID: generationID,
                                                   webView: webView)
                    } else {
                        self.waitForRepeatCanvasVisibility(
                            generationID: generationID,
                            webView: webView,
                            attempt: attempt + 1
                        )
                    }
                }
            }
        }
    }

    private func runRepeatCanvasUpdate(generationID: UInt64, webView: WKWebView) {
        guard automaticPostMachine.generationID == generationID,
              case .preparing = automaticPostMachine.state else { return }
        webView.evaluateJavaScript(
            CompactPageModeService.repeatCanvasUpdateScript(generationID: generationID)
        ) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.automaticPostMachine.generationID == generationID,
                      case .preparing = self.automaticPostMachine.state else { return }
                let didStart = Self.javascriptBoolean(result)
                if let error {
                    var fields = [
                        ("PATH", "CANVAS_UPDATE"),
                        ("JS_RESULT", didStart == true ? "TRUE" : "INVALID")
                    ]
                    let nsError = error as NSError
                    fields.append(("ERROR_DOMAIN", nsError.domain))
                    fields.append(("ERROR_CODE", String(nsError.code)))
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "REPEAT",
                        event: "REPEAT_IMAGE_PREPARATION_FAILED",
                        result: "STOPPED",
                        fields: fields
                    )
                    self.stopAutomaticPost(.communicationFailure,
                                            generationID: generationID)
                } else if didStart == false {
                    self.appendAutomaticEvent(
                        generationID: generationID,
                        phase: "REPEAT",
                        event: "REPEAT_IMAGE_PREPARATION_FAILED",
                        result: "STOPPED",
                        fields: [
                            ("PATH", "CANVAS_UPDATE"),
                            ("JS_RESULT", "FALSE"),
                            ("FAILURE_REASON", "JS_RETURNED_FALSE")
                        ]
                    )
                    self.stopAutomaticPost(.preparationFailed,
                                            generationID: generationID)
                }
            }
        }
    }

    private func scheduleContinuousAPReconnectRetry(generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID,
              case .waitingForContinuousAPRetry = automaticPostMachine.state,
              automaticPostMachine.continuousAPReconnectAttempts > 1 else {
            return
        }
        let attempt = automaticPostMachine.continuousAPReconnectAttempts
        appendAutomaticEvent(
            generationID: generationID,
            phase: "AP",
            event: "CONTINUOUS_AP_RETRY_SCHEDULED",
            result: "SCHEDULED",
            fields: [
                ("AP_ATTEMPT", String(attempt)),
                ("DELAY_MS", String(Self.continuousAPRetryDelayNanoseconds / 1_000_000)),
                ("AP_PURPOSE", "AUTOMATIC_CONTINUOUS_RETRY")
            ]
        )
        setAutomaticPostStatus(.reconnectingAfterContinuousLimit,
                               generationID: generationID)
        cancelAutomaticContinuousAPRetryDelay()
        automaticContinuousAPRetryDelayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.continuousAPRetryDelayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  self.automaticPostMachine.isActive,
                  case .waitingForContinuousAPRetry = self.automaticPostMachine.state,
                  !self.isAPRunning,
                  self.pendingAP == nil,
                  !self.automaticFinishedGenerations.contains(generationID) else {
                return
            }
            self.automaticContinuousAPRetryDelayTask = nil
            self.handleAutomaticPostEffect(.startContinuousAPReconnect,
                                            generationID: generationID)
        }
    }

    private func scheduleSubmitDelay(generationID: UInt64) {
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessStableSince = nil
        automaticPostPreparationTimer?.cancel()
        let readinessReason = automaticSubmitReadinessReason
        let delayNanoseconds = submitDelayNanoseconds(for: readinessReason)
        if let readinessReason,
           readinessReason == .continuousAPRetry ||
           readinessReason == .sameThreadRepeat ||
           readinessReason == .submitResponseRetry {
            var fields = [
                ("DELAY_MS", String(delayNanoseconds / 1_000_000)),
                ("REASON", readinessReason.rawValue)
            ]
            if readinessReason == .continuousAPRetry {
                fields.append((
                    "MIN_INTERVAL_MS",
                    String(Self.continuousAPMinimumIntervalNanoseconds / 1_000_000)
                ))
            }
            appendAutomaticEvent(
                generationID: generationID,
                phase: "READINESS",
                event: "SUBMIT_DELAY_SCHEDULED",
                result: "SCHEDULED",
                fields: fields
            )
        }
        automaticSubmitReadinessReason = nil
        automaticPostPreparationTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  case .waitingToSubmit = self.automaticPostMachine.state else {
                return
            }
            let effect = self.automaticPostMachine.handle(
                .initialSubmitDelayElapsed(generationID: generationID)
            )
            self.handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    private func submitDelayNanoseconds(for reason: AutomaticPostReadinessReason?) -> UInt64 {
        if reason == .sameThreadRepeat {
            return Self.sameThreadRepeatSubmitDelayNanoseconds
        }
        guard reason == .continuousAPRetry,
              let completedAt = automaticContinuousAPCompletedUptimeNanoseconds else {
            return Self.standardSubmitDelayNanoseconds
        }
        // Readiness is polled in parallel; this deadline is the only intentional
        // delay for the fourth attempt, so AP completion to click stays just over
        // three seconds when the page is already ready.
        let target = completedAt &+ Self.continuousAPMinimumIntervalNanoseconds
        let now = DispatchTime.now().uptimeNanoseconds
        return target > now ? target - now : 0
    }

    private func submitAutomatically(attempt: Int, generationID: UInt64) {
        if multiThreadSession?.stopRequested == true {
            stopAutomaticPost(.repeatDisabled, generationID: generationID)
            return
        }
        guard automaticPostMachine.generationID == generationID,
              let webView,
              let pageToken = automaticPostMachine.pageToken,
              let submissionID = automaticPostMachine.currentSubmissionID else {
            stopAutomaticPost(.communicationFailure, generationID: generationID)
            return
        }
        let isFinalIPAttempt = attempt == AutomaticPostFlowMachine.regularAttemptLimit &&
            automaticPostMachine.ipRetryIsTerminal
        let isContinuousAPAttempt = attempt == AutomaticPostFlowMachine.maximumAttempts &&
            automaticPostMachine.continuousRetryUsed
        let submitStatus: AutomaticPostStatus
        if isContinuousAPAttempt {
            submitStatus = .finalSendAfterContinuousLimit
        } else if isFinalIPAttempt {
            submitStatus = .finalSendAfterIPChange
        } else {
            submitStatus = .sending
        }
        setAutomaticPostStatus(submitStatus,
                                generationID: generationID)
        let branch: String
        if isContinuousAPAttempt {
            branch = "CONTINUOUS_AP_RETRY"
        } else if automaticPostMachine.continuousRetryUsed {
            branch = "CONTINUOUS_RETRY"
        } else if isFinalIPAttempt || automaticPostMachine.ipRetryIsTerminal {
            branch = "IP_RETRY"
        } else if attempt == 1 {
            branch = "INITIAL"
        } else {
            branch = "COOKIE_RETRY"
        }
        var submitFields = [
            ("ATTEMPT", String(attempt)),
            ("BRANCH", branch),
            ("COOKIE_RELATED_COUNT", automaticCookieRelatedCount.map { String($0) } ?? "UNAVAILABLE"),
            ("COOKIE_COUNT_DELTA", automaticCookieCountDelta.map { String($0) } ?? "UNAVAILABLE"),
            ("AP_RESULT", automaticAPResult),
            ("RESULT", "SUBMIT_STARTED")
        ]
        if let context = automaticLogContext(generationID: generationID) {
            submitFields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "SUBMIT",
                event: "CLICK_STARTED",
                result: "STARTED"
            ), at: 0)
        }
        logStore.append(action: "Automatic Post", fields: submitFields)
        startAutomaticSubmitResponseTimeout(generationID: generationID,
                                            attempt: attempt,
                                            submissionID: submissionID,
                                            pageToken: pageToken)
        webView.evaluateJavaScript(CompactPageModeService.autoSubmitScript(
            for: submissionID
        )) {
            [weak self] result, error in
            guard let self else { return }
            guard self.automaticPostMachine.generationID == generationID,
                  self.automaticPostMachine.currentAttempt == attempt,
                  self.automaticPostMachine.pageToken == pageToken,
                  self.automaticPostMachine.currentSubmissionID == submissionID else {
                if let currentGenerationID = self.automaticPostMachine.generationID {
                    self.appendAutomaticEvent(
                        generationID: currentGenerationID,
                        phase: "SUBMIT",
                        event: "CLICK_CALLBACK_IGNORED",
                        result: "IGNORED",
                        fields: [("REASON", "STALE_GENERATION_ATTEMPT_OR_SUBMISSION")]
                    )
                }
                return
            }
            guard case .submitting = self.automaticPostMachine.state else {
                self.appendAutomaticEvent(
                    generationID: generationID,
                    phase: "SUBMIT",
                    event: "CLICK_CALLBACK_IGNORED",
                    result: "IGNORED",
                    fields: [("REASON", "SUBMIT_STATE_CHANGED")]
                )
                return
            }
            let didClick = Self.javascriptBoolean(result) ?? false
            var callbackFields = [
                ("ATTEMPT", String(attempt)),
                ("JS_RESULT", didClick && error == nil ? "CLICKED" : "FAILED")
            ]
            if let error {
                let nsError = error as NSError
                callbackFields.append(("ERROR_DOMAIN", nsError.domain))
                callbackFields.append(("ERROR_CODE", String(nsError.code)))
                callbackFields.append(("FAILURE_REASON", "EVALUATION_ERROR"))
            } else if !didClick {
                callbackFields.append(("FAILURE_REASON", "JS_RETURNED_FALSE"))
            }
            self.appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "CLICK_CALLBACK",
                result: didClick && error == nil ? "ACCEPTED" : "FAILED",
                fields: callbackFields
            )
            guard error == nil, didClick else {
                self.cancelAutomaticSubmitResponseTimer()
                let effect = self.automaticPostMachine.handle(
                    .fail(generationID: generationID, reason: .communicationFailure)
                )
                self.handleAutomaticPostEffect(effect, generationID: generationID)
                return
            }
        }
    }

    private func startAutomaticSubmitResponseTimeout(generationID: UInt64,
                                                     attempt: Int,
                                                     submissionID: UInt64,
                                                     pageToken: String) {
        automaticSubmitResponseTimer?.cancel()
        automaticSubmitResponseTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: Self.automaticSubmitResponseTimeoutNanoseconds
            )
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  self.automaticPostMachine.pageToken == pageToken,
                  self.automaticPostMachine.currentSubmissionID == submissionID,
                  case let .submitting(_, currentAttempt) = self.automaticPostMachine.state,
                  currentAttempt == attempt else {
                return
            }

            let submissionEvidence: String
            if self.automaticPostMachine.submitEventObserved {
                submissionEvidence = "FORM_SUBMIT"
            } else if self.automaticOwnResponseConfirmed {
                submissionEvidence = "DOM_MATCHED"
            } else {
                submissionEvidence = "NONE"
            }
            let effect = self.automaticPostMachine.handle(
                .submitResponseTimedOut(
                    generationID: generationID,
                    submissionID: submissionID
                )
            )
            let willRetry: Bool
            switch effect {
            case .startSubmitReadiness, .startCookieRefreshAfterTimeout:
                willRetry = true
            default:
                willRetry = false
            }
            let timeoutBranch: String
            if case .startCookieRefreshAfterTimeout = effect {
                timeoutBranch = "COOKIE_REACQUIRE"
            } else {
                timeoutBranch = self.automaticSubmitBranch(attempt: attempt)
            }
            self.appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "SUBMIT_RESPONSE_TIMEOUT",
                result: willRetry ? "RETRYING" : "STOPPED",
                fields: [
                    ("ATTEMPT", String(attempt)),
                    ("BRANCH", timeoutBranch),
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("EVIDENCE", submissionEvidence),
                    ("TIMEOUT_MS", String(
                        Self.automaticSubmitResponseTimeoutNanoseconds / 1_000_000
                    ))
                ]
            )
            self.automaticSubmitResponseTimer = nil
            self.handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    private func cancelAutomaticSubmitResponseTimer() {
        automaticSubmitResponseTimer?.cancel()
        automaticSubmitResponseTimer = nil
    }

    private func automaticSubmitBranch(attempt: Int) -> String {
        let isFinalIPAttempt = attempt == AutomaticPostFlowMachine.regularAttemptLimit &&
            automaticPostMachine.ipRetryIsTerminal
        let isContinuousAPAttempt = attempt == AutomaticPostFlowMachine.maximumAttempts &&
            automaticPostMachine.continuousRetryUsed
        if isContinuousAPAttempt {
            return "CONTINUOUS_AP_RETRY"
        }
        if automaticPostMachine.continuousRetryUsed {
            return "CONTINUOUS_RETRY"
        }
        if isFinalIPAttempt || automaticPostMachine.ipRetryIsTerminal {
            return "IP_RETRY"
        }
        return attempt == 1 ? "INITIAL" : "COOKIE_RETRY"
    }

    private func startAutomaticPostPreparationTimeout(generationID: UInt64) {
        automaticPostPreparationTimer?.cancel()
        automaticPostPreparationTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  case .preparing = self.automaticPostMachine.state else { return }
            self.appendAutomaticEvent(
                generationID: generationID,
                phase: "PREPARATION",
                event: "PREPARATION_TIMEOUT",
                result: "STOPPED",
                fields: self.automaticPostMachine.preparationDiagnosticFields
            )
            if self.automaticPostMachine.isMultiThread {
                self.skipActiveMultiThreadTarget(
                    generationID: generationID,
                    reason: "PREPARATION_TIMEOUT"
                )
                return
            }
            let effect = self.automaticPostMachine.handle(
                .fail(generationID: generationID, reason: .preparationTimeout)
            )
            self.handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    private func stopAutomaticPost(_ reason: AutomaticPostStopReason,
                                   generationID: UInt64?) {
        guard let generationID,
              automaticPostMachine.generationID == generationID,
              automaticPostMachine.isActive else { return }
        let effect = automaticPostMachine.handle(
            .fail(generationID: generationID, reason: reason)
        )
        handleAutomaticPostEffect(effect, generationID: generationID)
    }

    private func finishAutomaticPost(generationID: UInt64,
                                     result: String,
                                     multiThreadContext: MultiThreadLogContext? = nil) {
        guard automaticPostMachine.generationID == generationID else { return }
        guard !automaticFinishedGenerations.contains(generationID) else { return }
        automaticFinishedGenerations.insert(generationID)
        automaticPostMachine.forceTerminate(generationID: generationID)
        defer { updateIdleTimerState() }
        automaticPostPreparationTimer?.cancel()
        automaticPostPreparationTimer = nil
        cancelAutomaticSubmitResponseTimer()
        cancelAutomaticContinuousAPRetryDelay()
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        latestCompactReady = nil
        pendingHandwritingReady = nil
        pendingHandwritingRestore = nil
        pendingMultiThreadAvailabilityProbe = nil
        automaticDraftRestorePendingGeneration = nil
        if automaticPostRepeatSession != nil,
           result.hasPrefix("STOPPED") || !sameThreadRepeatEnabled {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "REPEAT",
                event: "REPEAT_STOPPED",
                result: "STOPPED",
                fields: [
                    ("STOP_REASON", result)
                ]
            )
        }
        var finalFields = [
            ("ATTEMPT", String(automaticPostMachine.lastAttempt)),
            ("BRANCH", "FINAL"),
            ("COOKIE_RELATED_COUNT", automaticCookieRelatedCount.map { String($0) } ?? "UNAVAILABLE"),
            ("COOKIE_COUNT_DELTA", automaticCookieCountDelta.map { String($0) } ?? "UNAVAILABLE"),
            ("AP_RESULT", automaticAPResult),
            ("POST_ACCEPTANCE", automaticPostAccepted ? "CONFIRMED" : "UNOBSERVED"),
            ("POST_VISIBILITY", automaticOwnResponseConfirmed ? "CONFIRMED" : "NOT_OBSERVED"),
            ("RESULT", result)
        ]
        if let context = automaticLogContext(generationID: generationID) {
            var metadata = automaticLogMetadata(
                context,
                phase: "FINAL",
                event: "FLOW_FINISHED",
                result: result
            )
            if let multiThreadContext {
                metadata.append(("SESSION_ID", String(multiThreadContext.sessionID)))
                metadata.append(("TARGET_INDEX", String(multiThreadContext.targetIndex)))
                if let threadID = multiThreadContext.threadID {
                    metadata.append(("THREAD_ID", threadID))
                }
            }
            finalFields.insert(contentsOf: metadata, at: 0)
        }
        logStore.append(action: "Automatic Post", fields: finalFields)
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        stopIsolationMonitoring(clearContext: true)
        if pendingUAChangeGeneration == generationID {
            pendingUAChangeGeneration = nil
            isUAChanging = false
        }
        if automaticReloadGeneration == generationID {
            automaticReloadGeneration = nil
        }
        if pendingCookieRefresh?.automaticGenerationID == generationID {
            pendingCookieRefresh = nil
            isCookieRefreshing = false
        }
        if let pendingAP,
           Self.appPurposeGenerationID(pendingAP.purpose) == generationID {
            self.pendingAP = nil
            isAPRunning = false
        }
        automaticPostStatusTask?.cancel()
        automaticPostStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID else { return }
            self.automaticPostStatus = nil
            self.automaticPostStatusTask = nil
        }
        clearAutomaticPostDraft()
    }

    private func clearAutomaticPostDraft() {
        automaticPostDraft = nil
        automaticTriedUAIDs.removeAll()
        automaticUserAgentOrder.removeAll()
        automaticUserAgentOrderCursor = 0
        cancelAutomaticRepeatSession()
    }

    private func cancelAutomaticRepeatSession() {
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        automaticPostRepeatSession = nil
        if multiThreadSession == nil {
            stopIsolationMonitoring(clearContext: true)
        }
        cancelAutomaticContinuousAPRetryDelay()
        updateIdleTimerState()
    }

    private func cancelAutomaticContinuousAPRetryDelay() {
        automaticContinuousAPRetryDelayTask?.cancel()
        automaticContinuousAPRetryDelayTask = nil
        updateIdleTimerState()
    }

    private func updateIdleTimerState() {
        let shouldDisable = IdleTimerPolicy.shouldDisableIdleTimer(
            appIsActive: appSceneIsActive,
            automaticFlowIsActive: automaticPostMachine.isActive,
            repeatSessionIsActive: automaticPostRepeatSession != nil ||
                multiThreadSessionActive,
            responseVerificationIsActive: automaticPostVerificationTask != nil
        )
        guard UIApplication.shared.isIdleTimerDisabled != shouldDisable else {
            return
        }
        UIApplication.shared.isIdleTimerDisabled = shouldDisable
    }

    private func setAutomaticPostStatus(_ status: AutomaticPostStatus,
                                        generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID else { return }
        automaticPostStatusTask?.cancel()
        automaticPostStatus = status
    }

    /// Terminal UI for a multi-thread bootstrap that failed before a page
    /// generation was created. There is no generation guard to use here, so
    /// the task is owned solely by the status slot and is cancelled whenever a
    /// later generation starts.
    private func setAutomaticPostStatusWithoutGeneration(_ status: AutomaticPostStatus) {
        automaticPostStatusTask?.cancel()
        automaticPostStatus = status
        automaticPostStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.automaticPostStatus = nil
            self.automaticPostStatusTask = nil
        }
    }

    private func beginAutomaticGenerationLogging(generationID: UInt64) {
        automaticGenerationStartedAt[generationID] = Date()
        automaticFinishedGenerations.remove(generationID)
        // Keep the exactly-once tombstone set bounded while retaining enough
        // recent generations to reject delayed WebKit callbacks.
        if automaticFinishedGenerations.count > 64,
           let oldestFinishedGenerationID = automaticFinishedGenerations.min() {
            automaticFinishedGenerations.remove(oldestFinishedGenerationID)
        }
        if automaticGenerationStartedAt.count > 16,
           let oldestGenerationID = automaticGenerationStartedAt.keys.min() {
            automaticGenerationStartedAt.removeValue(forKey: oldestGenerationID)
        }
        automaticPostAccepted = false
        automaticOwnResponseConfirmed = false
        automaticAcceptedPageToken = nil
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
    }

    private func automaticLogContext(generationID: UInt64) -> AutomaticLogContext? {
        guard let startedAt = automaticGenerationStartedAt[generationID] else {
            return nil
        }
        automaticEventSequence &+= 1
        let elapsed = max(0, Int((Date().timeIntervalSince(startedAt) * 1_000).rounded()))
        return AutomaticLogContext(generationID: generationID,
                                   sequence: automaticEventSequence,
                                   elapsedMilliseconds: elapsed)
    }

    private func automaticLogMetadata(_ context: AutomaticLogContext,
                                      phase: String,
                                      event: String,
                                      result: String? = nil) -> [(String, String)] {
        var fields = [
            ("GENERATION_ID", String(context.generationID)),
            ("EVENT_SEQ", String(context.sequence)),
            ("ELAPSED_MS", String(context.elapsedMilliseconds)),
            ("PHASE", phase),
            ("EVENT", event)
        ]
        if let result {
            fields.append(("EVENT_RESULT", result))
        }
        if let session = automaticPostRepeatSession,
           automaticPostMachine.generationID == context.generationID {
            fields.append(("SESSION_ID", String(session.sessionID)))
            fields.append(("CYCLE", String(session.cycle)))
        } else if let session = multiThreadSession,
                  automaticPostMachine.generationID == context.generationID {
            fields.append(("SESSION_ID", String(session.sessionID)))
            fields.append(("TARGET_INDEX", String(session.currentIndex + 1)))
            fields.append(("POSTS_SINCE_UA_CHANGE",
                           String(session.postsSinceUserAgentChange)))
            if let targetID = session.currentTargetID {
                fields.append(("THREAD_ID", targetID))
            }
        }
        return fields
    }

    private func appendAutomaticEvent(generationID: UInt64,
                                      phase: String,
                                      event: String,
                                      result: String? = nil,
                                      fields: [(String, String)] = []) {
        guard let context = automaticLogContext(generationID: generationID) else {
            return
        }
        var allFields = automaticLogMetadata(context,
                                              phase: phase,
                                              event: event,
                                              result: result)
        allFields.append(contentsOf: fields)
        logStore.append(action: "Automatic Post Event", fields: allFields)
    }

    func recordAutomaticBridgeIgnored(type: String, reason: String) {
        guard let generationID = automaticPostMachine.generationID else { return }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "\(Self.safeBridgeEventName(type))_IGNORED",
            result: "IGNORED",
            fields: [("PAGE_TOKEN_STATE", reason)]
        )
    }

    func recordAutomaticBridgeInvalidPayload(type: String, reason: String) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else { return }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "BRIDGE_PAYLOAD_INVALID",
            result: "IGNORED",
            fields: [
                ("BRIDGE_TYPE", Self.safeBridgeEventName(type)),
                ("REASON", Self.safeBridgePayloadReason(reason))
            ]
        )
    }

    func recordAutomaticUnknownBridgeMessage() {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else { return }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "UNKNOWN_BRIDGE_MESSAGE",
            result: "IGNORED",
            fields: [("REASON", "UNSUPPORTED_TYPE")]
        )
    }

    private func recordAutomaticPostAccepted(generationID: UInt64,
                                             pageToken: String,
                                             source: String) {
        guard automaticPostMachine.generationID == generationID,
              automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "postCompleted",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        guard automaticPostMachine.canAcceptPostCompletion else {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "POST_ACCEPTED_IGNORED",
                result: "IGNORED",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("REASON", "STATE_NOT_SUBMITTING"),
                    ("SOURCE", Self.safePostAcceptanceSource(source))
                ]
            )
            return
        }
        if automaticPostMachine.awaitingSubmitResponseRetry {
            // A delayed completion marker won the race with the one allowed
            // response retry. Cancel the readiness/submit-delay work before
            // transitioning to success so it cannot dispatch a second click.
            automaticSubmitReadinessTask?.cancel()
            automaticSubmitReadinessTask = nil
            automaticSubmitReadinessDeadline = nil
            automaticSubmitReadinessStableSince = nil
            automaticSubmitReadinessLastReason = nil
            automaticSubmitReadinessFalseLogged = false
            automaticSubmitReadinessReason = nil
            automaticPostPreparationTimer?.cancel()
            automaticPostPreparationTimer = nil
            appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "LATE_COMPLETION_ACCEPTED",
                result: "RETRY_SUPPRESSED",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("SOURCE", Self.safePostAcceptanceSource(source))
                ]
            )
        }
        cancelAutomaticSubmitResponseTimer()
        if automaticPostAccepted {
            appendAutomaticEvent(
                generationID: generationID,
                phase: "SUBMIT",
                event: "POST_ACCEPTED_DUPLICATE",
                result: "IGNORED",
                fields: [
                    ("PAGE_TOKEN_STATE", "MATCH"),
                    ("SOURCE", Self.safePostAcceptanceSource(source))
                ]
            )
            return
        }
        automaticPostAccepted = true
        automaticAcceptedPageToken = pageToken
        appendAutomaticEvent(
            generationID: generationID,
            phase: "SUBMIT",
            event: "POST_ACCEPTED",
            result: "MARKER_COMPLETED",
            fields: [
                ("PAGE_TOKEN_STATE", "MATCH"),
                ("SOURCE", Self.safePostAcceptanceSource(source)),
                ("POST_VISIBILITY", automaticOwnResponseConfirmed ? "CONFIRMED" : "PENDING")
            ]
        )
        if automaticOwnResponseConfirmed {
            automaticPostVerificationTask = nil
        } else {
            scheduleAutomaticPostVerificationTimeout(generationID: generationID)
        }
    }

    private func scheduleAutomaticPostVerificationTimeout(generationID: UInt64) {
        guard multiThreadSession == nil else { return }
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID,
                  self.automaticPostAccepted,
                  !self.automaticOwnResponseConfirmed else { return }
            self.appendAutomaticEvent(
                generationID: generationID,
                phase: "VERIFICATION",
                event: "OWN_RESPONSE_TIMEOUT",
                result: "NOT_CONFIRMED",
                fields: [
                    ("PAGE_TOKEN_STATE", self.automaticAcceptedPageToken == nil ?
                        "MISSING" : "ACCEPTED_PAGE"),
                    ("FINAL_RESULT", "ACCEPTED_UNCONFIRMED")
                ]
            )
            self.automaticPostVerificationTask = nil
            self.setAutomaticPostStatus(.completedUnconfirmed,
                                        generationID: generationID)
            self.finishAutomaticPost(generationID: generationID,
                                     result: "SUCCEEDED_UNCONFIRMED")
        }
    }

    private static func safeBridgeEventName(_ type: String) -> String {
        switch type {
        case "selectedImage": return "SELECTED_IMAGE"
        case "pageReady": return "PAGE_READY"
        case "canvasReady": return "CANVAS_READY"
        case "compactReady": return "COMPACT_READY"
        case "handwritingReady": return "HANDWRITING_READY"
        case "postStatus": return "POST_STATUS"
        case "postCompleted": return "POST_COMPLETED"
        case "submitReadiness": return "SUBMIT_READINESS"
        case "submitObserved": return "SUBMIT_OBSERVED"
        case "ownPostVisible": return "OWN_POST_VISIBLE"
        case "ownPostObservation": return "OWN_POST_OBSERVATION"
        case "threadUnavailable": return "THREAD_UNAVAILABLE"
        default: return "OTHER_BRIDGE_EVENT"
        }
    }

    private static func safeBridgePayloadReason(_ reason: String) -> String {
        switch reason {
        case "DATA_URL_MISSING": return "DATA_URL_MISSING"
        case "DATA_URL_REJECTED": return "DATA_URL_REJECTED"
        case "READY_MISSING": return "READY_MISSING"
        case "PAGE_TOKEN_MISSING": return "PAGE_TOKEN_MISSING"
        case "REASON_MISSING": return "REASON_MISSING"
        case "HAS_COMMENT_MISSING": return "HAS_COMMENT_MISSING"
        case "CAN_SUBMIT_MISSING": return "CAN_SUBMIT_MISSING"
        case "COUNTS_MISSING": return "COUNTS_MISSING"
        case "RESTORE_SCRIPT_UNAVAILABLE": return "RESTORE_SCRIPT_UNAVAILABLE"
        case "SUBMISSION_ID_MISSING": return "SUBMISSION_ID_MISSING"
        case "PAGE_URL_MISMATCH": return "PAGE_URL_MISMATCH"
        case "REASON_INVALID": return "REASON_INVALID"
        default: return "OTHER"
        }
    }

    private static func safeSubmitReadinessReason(_ reason: String) -> String {
        switch reason {
        case "READY": return "READY"
        case "DOCUMENT_LOADING": return "DOCUMENT_LOADING"
        case "FORM_MISSING": return "FORM_MISSING"
        case "COMMENT_FIELD_MISSING": return "COMMENT_FIELD_MISSING"
        case "SUBMIT_BUTTON_MISSING": return "SUBMIT_BUTTON_MISSING"
        case "SUBMIT_BUTTON_DISABLED": return "SUBMIT_BUTTON_DISABLED"
        case "POST_IN_FLIGHT": return "POST_IN_FLIGHT"
        case "OUTSIDE_TARGET_PAGE": return "OUTSIDE_TARGET_PAGE"
        case "SUBMIT_RESPONSE_RETRY": return "SUBMIT_RESPONSE_RETRY"
        default: return "OTHER"
        }
    }

    private static func safePostAcceptanceSource(_ source: String) -> String {
        switch source {
        case "POST_STATUS": return "POST_STATUS"
        case "POST_COMPLETED": return "POST_COMPLETED"
        default: return "OTHER"
        }
    }

    private static func automaticStopResult(for reason: AutomaticPostStopReason) -> String {
        if reason == .submitResponseTimeout {
            return "STOPPED_SUBMIT_RESPONSE_TIMEOUT"
        }
        if reason == .threadUnavailable {
            return "STOPPED_THREAD_UNAVAILABLE"
        }
        if reason == .isolatedThread {
            return "STOPPED_ISOLATED_THREAD"
        }
        return "STOPPED_\(String(describing: reason).uppercased())"
    }

    private static func safePostStatusName(_ rawStatus: String?) -> String? {
        switch rawStatus {
        case "…": return "SENDING"
        case "完了": return "COMPLETED"
        default: return nil
        }
    }

    private static func safeMatchMethod(_ method: String?) -> String {
        switch method {
        case "COMMENT_NORMALIZED": return "COMMENT_NORMALIZED"
        case "COMMENT_COMPACT": return "COMMENT_COMPACT"
        case "IMAGE_ATTACHMENT": return "IMAGE_ATTACHMENT"
        case "DEFAULT_IMAGE_COMMENT": return "DEFAULT_IMAGE_COMMENT"
        default: return "NONE"
        }
    }

    private static func javascriptBoolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private static func postState(from result: Any?) -> (hasComment: Bool,
                                                          comment: String?,
                                                          canSubmit: Bool)? {
        guard let dictionary = result as? [String: Any] else { return nil }
        guard let eligible = dictionary["eligible"] as? Bool, eligible else { return nil }
        return (dictionary["hasComment"] as? Bool ?? false,
                dictionary["comment"] as? String,
                dictionary["canSubmit"] as? Bool ?? false)
    }

    static func threadAvailability(from result: Any?) ->
        (hasThread: Bool, hasForm: Bool)? {
        guard let dictionary = result as? [String: Any],
              let eligible = dictionary["eligible"] as? Bool,
              eligible,
              let hasThread = dictionary["hasThread"] as? Bool,
              let hasForm = dictionary["hasForm"] as? Bool else {
            return nil
        }
        return (hasThread, hasForm)
    }

    private static func isTargetThreadURL(_ url: URL?) -> Bool {
        CanvasImageSessionService.isTargetPageThreadURL(url)
    }

    private static func sameTargetThreadURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              isTargetThreadURL(lhs),
              isTargetThreadURL(rhs) else { return false }
        return lhs.host?.lowercased() == rhs.host?.lowercased() &&
            lhs.path == rhs.path
    }

    private func matchesPendingHandwritingRestore(pageToken: String,
                                                  pageURL: URL?) -> Bool {
        guard let pendingHandwritingRestore,
              pendingHandwritingRestore.pageToken == pageToken,
              Self.sameTargetThreadURL(pendingHandwritingRestore.pageURL, pageURL),
              let session = multiThreadSession,
              let currentTarget = session.currentTarget,
              Self.sameTargetThreadURL(currentTarget.threadURL, pageURL) else {
            return false
        }
        return true
    }

    private static func appPurposeGenerationID(_ purpose: APPurpose) -> UInt64? {
        switch purpose {
        case .manual:
            return nil
        case let .identityRefresh(generationID),
             let .automaticIPRetry(generationID),
             let .automaticContinuousRetry(generationID):
            return generationID
        }
    }

    private func finishIdentityRefresh() {
        isIdentityRefreshInProgress = false
        isUAChanging = false
    }
}

private extension WKHTTPCookieStore {
    func miniBrowserAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }

    func miniBrowserDelete(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            delete(cookie) { continuation.resume() }
        }
    }
}
