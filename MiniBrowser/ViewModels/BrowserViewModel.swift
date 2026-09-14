import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    private static let standardSubmitDelayNanoseconds: UInt64 = 2_000_000_000
    static let sameThreadRepeatMinimumDelayNanoseconds: UInt64 = 250_000_000
    static let sameThreadRepeatSubmitDelayNanoseconds: UInt64 = 0
    private static let continuousAPMinimumIntervalNanoseconds: UInt64 = 3_100_000_000

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

    let bookmarkStore: BookmarkStore

    weak var webView: WKWebView?
    private let defaults: UserDefaults
    private let logStore: DebugLogStore
    private let ipService: IPAddressService
    private let userAgentRestrictionStore: UserAgentRestrictionStore
    private var selectedUAIndex: Int
    private var runtimeUserAgent: RuntimeUserAgent?
    private var automaticTriedUAIDs: Set<Int> = []
    private var automaticPostDraft: AutomaticPostDraft?
    private var automaticPostRepeatSession: AutomaticPostRepeatSession?
    private var automaticPostRepeatSessionID: UInt64 = 0
    private var automaticPostRepeatDelayTask: Task<Void, Never>?
    private var pendingCookieRefresh: PendingCookieRefresh?
    private var pendingAP: PendingAP?
    private var lastRelatedCookieCountByHost: [String: Int] = [:]
    private var automaticPostMachine = AutomaticPostFlowMachine()
    private var automaticPostGeneration: UInt64 = 0
    private var pendingUAChangeGeneration: UInt64?
    private var automaticReloadGeneration: UInt64?
    private var automaticPostPreparationTimer: Task<Void, Never>?
    private var automaticSubmitReadinessTask: Task<Void, Never>?
    private var automaticPostStatusTask: Task<Void, Never>?
    private var latestCompactReady: (pageToken: String, hasComment: Bool, canSubmit: Bool)?
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
    private var automaticPostAccepted = false
    private var automaticOwnResponseConfirmed = false
    private var automaticAcceptedPageToken: String?
    private var automaticPostVerificationTask: Task<Void, Never>?

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

    private struct AutomaticLogContext {
        let generationID: UInt64
        let sequence: UInt64
        let elapsedMilliseconds: Int
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
         userAgentGenerator: RuntimeUserAgentGenerator = RuntimeUserAgentGenerator()) {
        self.defaults = defaults
        self.logStore = DebugLogStore(defaults: defaults)
        self.bookmarkStore = BookmarkStore(defaults: defaults)
        self.ipService = ipService
        self.userAgentRestrictionStore = UserAgentRestrictionStore(defaults: defaults)
        self.runtimeUserAgent = nil
        let catalogNeedsReset = defaults.integer(forKey: Keys.userAgentCatalogVersion) !=
            BrowserUserAgent.catalogVersion
        if catalogNeedsReset {
            self.selectedUAIndex = 0
        } else if let savedID = defaults.object(forKey: Keys.userAgentID) as? Int,
                  let savedIndex = BrowserUserAgent.all.firstIndex(where: { $0.id == savedID }) {
            self.selectedUAIndex = savedIndex
        } else {
            let savedIndex = defaults.integer(forKey: Keys.userAgentIndex)
            self.selectedUAIndex = BrowserUserAgent.all.indices.contains(savedIndex) ? savedIndex : 0
        }
        if catalogNeedsReset {
            defaults.set(0, forKey: Keys.userAgentIndex)
            defaults.set(BrowserUserAgent.all[0].id, forKey: Keys.userAgentID)
            userAgentRestrictionStore.clearAll()
        }
        defaults.set(BrowserUserAgent.catalogVersion, forKey: Keys.userAgentCatalogVersion)

        let generatedUserAgent = userAgentGenerator.generate { value in
            let key = userAgentRestrictionStore.generatedRestrictionKey(for: value)
            return userAgentRestrictionStore.isRestricted(key)
        }
        let launchSelectionSource: String
        if let generatedUserAgent {
            runtimeUserAgent = generatedUserAgent
            launchSelectionSource = "GENERATED"
        } else {
            let restrictedIDs = userAgentRestrictionStore.restrictedIDs()
            if let fallbackIndex = BrowserUserAgent.all.indices.first(where: {
                !restrictedIDs.contains(BrowserUserAgent.all[$0].id)
            }) {
                selectedUAIndex = fallbackIndex
                defaults.set(selectedUAIndex, forKey: Keys.userAgentIndex)
                defaults.set(BrowserUserAgent.all[fallbackIndex].id,
                             forKey: Keys.userAgentID)
                launchSelectionSource = "FIXED_FALLBACK"
            } else {
                launchSelectionSource = "FIXED_CURRENT"
            }
            runtimeUserAgent = nil
        }
        logStore.append(action: "User Agent Launch Selection", fields: [
            ("SOURCE", launchSelectionSource),
            ("RESULT", "READY")
        ])
    }

    var currentUserAgent: BrowserUserAgent {
        BrowserUserAgent.all[selectedUAIndex]
    }

    /// The UA used for all requests in the current process. A generated value
    /// is selected once during model initialization and is not regenerated on
    /// scene activation or WebView recreation.
    var effectiveUserAgent: String {
        runtimeUserAgent?.value ?? currentUserAgent.value
    }

    var userAgentButtonTitle: String {
        if runtimeUserAgent != nil {
            return "UA 自動"
        }
        return "UA \(selectedUAIndex + 1)/\(BrowserUserAgent.all.count)"
    }

    private var effectiveUserAgentLogLabel: String {
        runtimeUserAgent == nil
            ? "\(selectedUAIndex + 1)/\(BrowserUserAgent.all.count) \(currentUserAgent.name)"
            : "GENERATED"
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
        guard let url = URLNormalizer.normalize(urlText) else {
            showToast("URLを確認してください", kind: .failure)
            return
        }
        urlText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func openThreadListThread(_ url: URL) {
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
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func cycleUserAgent() {
        guard !isIdentityRefreshInProgress,
              !isUAChanging,
              !isCookieRefreshing,
              !isAPRunning,
              !isLoading,
              let webView,
              webView.url?.host != nil else {
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
        let pageURL = webView.url

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
            let shouldStartAutomatic = isTarget && canSubmit && (hasComment || imageAvailable)
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
                newAutomaticSession: true
            )
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

    private func startNextAutomaticFlow(previousGenerationID: UInt64) {
        guard automaticPostMachine.generationID == previousGenerationID,
              let draft = automaticPostDraft,
              let webView,
              let pageURL = webView.url,
              Self.isTargetThreadURL(pageURL),
              let nextIndex = nextEligibleUserAgentIndex(
                after: selectedUAIndex,
                excluding: automaticTriedUAIDs
              ) else {
            setAutomaticPostStatus(.stopped, generationID: previousGenerationID)
            finishAutomaticPost(generationID: previousGenerationID,
                                result: "STOPPED_NO_AVAILABLE_UA")
            return
        }

        setAutomaticPostStatus(.switchingAfterAccessRestriction,
                               generationID: previousGenerationID)
        let oldPageToken = automaticPostMachine.pageToken ?? latestCompactReady?.pageToken
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
            newAutomaticSession: false
        )
    }

    func toggleSameThreadRepeat() {
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
                                      newAutomaticSession: Bool) {
        guard let webView else {
            isUAChanging = false
            return
        }
        isUAChanging = true
        pendingUAChangeGeneration = nil

        if newAutomaticSession {
            automaticTriedUAIDs.removeAll()
        }
        guard let nextIndex = targetUAIndex ?? nextEligibleUserAgentIndex(
            after: selectedUAIndex,
            excluding: excludedUAIDs
        ) else {
            isUAChanging = false
            automaticTriedUAIDs.removeAll()
            showToast("利用可能なUAがありません", kind: .warning)
            return
        }
        selectedUAIndex = nextIndex
        runtimeUserAgent = nil
        defaults.set(selectedUAIndex, forKey: Keys.userAgentIndex)
        defaults.set(currentUserAgent.id, forKey: Keys.userAgentID)
        if automatic {
            automaticTriedUAIDs.insert(currentUserAgent.id)
            automaticPostDraft = AutomaticPostDraft(hasComment: hasComment,
                                                     comment: comment,
                                                     hasImage: hasImage)
            if newAutomaticSession,
               sameThreadRepeatEnabled,
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
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
        automaticPostStatusTask?.cancel()
        latestCompactReady = nil
        automaticCookieRelatedCount = nil
        automaticCookieCountDelta = nil
        automaticAPResult = automatic ? "PENDING" : "NOT_REQUESTED"

        automaticPostMachine.reset()
        if automatic && !readError {
            _ = automaticPostMachine.begin(generationID: generationID,
                                           oldPageToken: oldPageToken,
                                           hasComment: hasComment,
                                           hasImage: hasImage)
            beginAutomaticGenerationLogging(generationID: generationID)
            setAutomaticPostStatus(.preparingUA, generationID: generationID)
            startAutomaticPostPreparationTimeout(generationID: generationID)
        }

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
        isLoading = true
        sitePostStatus = nil
        latestCompactReady = nil
        refreshNavigationState()
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

    func handwritingPreparationGenerationID(pageToken: String) -> UInt64? {
        guard automaticPostMachine.isActive,
              !automaticPostMachine.isStalePageToken(pageToken) else {
            return nil
        }
        return automaticPostMachine.generationID
    }

    func handleCompactReady(pageToken: String,
                            hasComment: Bool,
                            canSubmit: Bool) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else {
            latestCompactReady = (pageToken, hasComment, canSubmit)
            return
        }
        let effect = automaticPostMachine.handle(.markCompactReady(
            generationID: generationID,
            pageToken: pageToken,
            hasComment: hasComment,
            canSubmit: canSubmit
        ))
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
        latestCompactReady = (pageToken, hasComment, canSubmit)
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

    func handleHandwritingReady(pageToken: String,
                                ready: Bool,
                                generationID incomingGenerationID: UInt64? = nil) {
        guard automaticPostMachine.isActive,
              let generationID = automaticPostMachine.generationID else { return }
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
        guard incomingGenerationID == generationID else {
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

    func handlePostStatus(_ rawStatus: String?, pageToken: String?) {
        if automaticPostMachine.isActive {
            guard let pageToken else {
                recordAutomaticBridgeIgnored(type: "postStatus",
                                              reason: "MISSING_PAGE_TOKEN")
                return
            }
            guard automaticPostMachine.pageToken == pageToken else {
                recordAutomaticBridgeIgnored(type: "postStatus",
                                              reason: "STALE_OR_MISMATCH")
                return
            }
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
            recordAutomaticPostAccepted(generationID: generationID,
                                         pageToken: pageToken,
                                         source: "POST_STATUS")
            let effect = automaticPostMachine.handle(.postCompleted(generationID: generationID))
            handleAutomaticPostEffect(effect, generationID: generationID)
        }
    }

    func handlePostCompleted(pageToken: String?) {
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
        guard automaticPostMachine.pageToken == pageToken else {
            recordAutomaticBridgeIgnored(type: "postCompleted",
                                          reason: "STALE_OR_MISMATCH")
            return
        }
        appendAutomaticEvent(
            generationID: generationID,
            phase: "BRIDGE",
            event: "POST_COMPLETED",
            result: "RECEIVED",
            fields: [("PAGE_TOKEN_STATE", "MATCH")]
        )
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
            canAcceptVisibleResponse = automaticPostAccepted &&
                automaticPostVerificationTask != nil
        case .idle, .preparing, .waitingForSubmitReadiness, .waitingToSubmit,
             .waitingForCookieRetry, .waitingForIPRetry, .waitingForContinuousRetry,
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
        if category == .accessRestricted,
           let runtimeUserAgent {
            let key = userAgentRestrictionStore.generatedRestrictionKey(
                for: runtimeUserAgent.value
            )
            userAgentRestrictionStore.restrict(key)
        }
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

        if category == .accessRestricted {
            if runtimeUserAgent == nil {
                userAgentRestrictionStore.restrict(currentUserAgent.id)
            }
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
        case .threadPostingUnavailable:
            alert = .threadPostingUnavailable
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
                                                automaticGenerationID: UInt64?) async {
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
            showToast("Cookieなし", kind: .warning)
            isCookieRefreshing = false
            return
        }

        for cookie in targets {
            await store.miniBrowserDelete(cookie)
        }

        let afterDeletion = await store.miniBrowserAllCookies()
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
            automaticAPResult = after == nil ? "FAILED" : "RECONNECTED"
            guard after != nil else {
                stopAutomaticPost(.communicationFailure, generationID: generationID)
                return
            }
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

    private func handleAutomaticPostEffect(_ effect: AutomaticPostFlowEffect,
                                           generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID else { return }
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
                reason == .sameThreadRepeat ? .waitingForRepeat : .checkingCookie,
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
            appendAutomaticEvent(
                generationID: generationID,
                phase: "AP",
                event: "CONTINUOUS_RETRY_RECONNECT_REQUESTED",
                result: "STARTED",
                fields: [("AP_PURPOSE", "AUTOMATIC_CONTINUOUS_RETRY")]
            )
            setAutomaticPostStatus(.reconnectingAfterContinuousLimit,
                                   generationID: generationID)
            startCellularReconnect(
                reloadAfterCompletion: false,
                purpose: .automaticContinuousRetry(generationID: generationID)
            )
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
        case .succeeded:
            if let session = automaticPostRepeatSession,
               sameThreadRepeatEnabled,
               !session.stopRequested {
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
            finishAutomaticPost(generationID: generationID,
                                result: "STOPPED_\(String(describing: reason).uppercased())")
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
            hasImage: session.hasImage
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
        setAutomaticPostStatus(.waitingForRepeat, generationID: generationID)
        startAutomaticPostPreparationTimeout(generationID: generationID)

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

    private func scheduleSubmitDelay(generationID: UInt64) {
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessStableSince = nil
        automaticPostPreparationTimer?.cancel()
        let readinessReason = automaticSubmitReadinessReason
        let delayNanoseconds = submitDelayNanoseconds(for: readinessReason)
        if let readinessReason,
           readinessReason == .continuousAPRetry || readinessReason == .sameThreadRepeat {
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
        guard automaticPostMachine.generationID == generationID,
              let webView else {
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
        webView.evaluateJavaScript(CompactPageModeService.autoSubmitScript) {
            [weak self] result, error in
            guard let self else { return }
            guard self.automaticPostMachine.generationID == generationID,
                  self.automaticPostMachine.currentAttempt == attempt else {
                if let currentGenerationID = self.automaticPostMachine.generationID {
                    self.appendAutomaticEvent(
                        generationID: currentGenerationID,
                        phase: "SUBMIT",
                        event: "CLICK_CALLBACK_IGNORED",
                        result: "IGNORED",
                        fields: [("REASON", "STALE_GENERATION_OR_ATTEMPT")]
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
                let effect = self.automaticPostMachine.handle(
                    .fail(generationID: generationID, reason: .communicationFailure)
                )
                self.handleAutomaticPostEffect(effect, generationID: generationID)
                return
            }
        }
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

    private func finishAutomaticPost(generationID: UInt64, result: String) {
        guard automaticPostMachine.generationID == generationID else { return }
        automaticPostPreparationTimer?.cancel()
        automaticSubmitReadinessTask?.cancel()
        automaticSubmitReadinessTask = nil
        automaticSubmitReadinessStableSince = nil
        automaticSubmitReadinessDeadline = nil
        automaticSubmitReadinessLastReason = nil
        automaticSubmitReadinessFalseLogged = false
        automaticSubmitReadinessReason = nil
        automaticContinuousAPCompletedUptimeNanoseconds = nil
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
            finalFields.insert(contentsOf: automaticLogMetadata(
                context,
                phase: "FINAL",
                event: "FLOW_FINISHED",
                result: result
            ), at: 0)
        }
        logStore.append(action: "Automatic Post", fields: finalFields)
        automaticPostVerificationTask?.cancel()
        automaticPostVerificationTask = nil
        automaticPostStatusTask?.cancel()
        automaticPostStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.automaticPostMachine.generationID == generationID else { return }
            self.automaticPostStatus = nil
        }
        clearAutomaticPostDraft()
    }

    private func clearAutomaticPostDraft() {
        automaticPostDraft = nil
        automaticTriedUAIDs.removeAll()
        cancelAutomaticRepeatSession()
    }

    private func cancelAutomaticRepeatSession() {
        automaticPostRepeatDelayTask?.cancel()
        automaticPostRepeatDelayTask = nil
        automaticPostRepeatSession = nil
    }

    private func setAutomaticPostStatus(_ status: AutomaticPostStatus,
                                        generationID: UInt64) {
        guard automaticPostMachine.generationID == generationID else { return }
        automaticPostStatusTask?.cancel()
        automaticPostStatus = status
    }

    private func beginAutomaticGenerationLogging(generationID: UInt64) {
        automaticGenerationStartedAt[generationID] = Date()
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
        guard case .submitting = automaticPostMachine.state else {
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
        case "ownPostVisible": return "OWN_POST_VISIBLE"
        case "ownPostObservation": return "OWN_POST_OBSERVATION"
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

    private static func isTargetThreadURL(_ url: URL?) -> Bool {
        CanvasImageSessionService.isTargetPageThreadURL(url)
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
