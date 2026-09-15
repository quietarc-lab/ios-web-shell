import Foundation
import SwiftUI
import UIKit
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var model: BrowserViewModel
    private let onThreadPostingUnavailable: (URL) -> Void

    init(model: BrowserViewModel,
         onThreadPostingUnavailable: @escaping (URL) -> Void = { _ in }) {
        self.model = model
        self.onThreadPostingUnavailable = onThreadPostingUnavailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model,
                    onThreadPostingUnavailable: onThreadPostingUnavailable)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        InputAutoZoomPreventionService.install(on: configuration.userContentController)
        CompactPageModeService.install(on: configuration.userContentController)
        CanvasImageSessionService.install(on: configuration.userContentController)
        configuration.userContentController.add(context.coordinator,
                                                name: CanvasImageSessionService.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(webView: webView)
        Task { @MainActor [weak webView] in
            guard let webView else { return }
            do {
                try await ContentBlockerService.install(on: configuration.userContentController)
            } catch {
                model.contentBlockerFailed(error: error)
            }
            model.attach(webView: webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: CanvasImageSessionService.messageHandlerName
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let model: BrowserViewModel
        private let onThreadPostingUnavailable: (URL) -> Void
        private var timeoutTimer: Timer?
        private weak var attachedWebView: WKWebView?
        private let handwritingImageStore = TargetPageHandwritingImageStore()
        private var currentPageToken: String?

        init(model: BrowserViewModel,
             onThreadPostingUnavailable: @escaping (URL) -> Void) {
            self.model = model
            self.onThreadPostingUnavailable = onThreadPostingUnavailable
        }

        deinit {
            timeoutTimer?.invalidate()
        }

        func attach(webView: WKWebView) {
            attachedWebView = webView
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == CanvasImageSessionService.messageHandlerName,
                  message.frameInfo.isMainFrame,
                  CanvasImageSessionService.isTargetPageThreadURL(
                    message.frameInfo.request.url ?? attachedWebView?.url
                  ),
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            let pageToken = body["pageToken"] as? String
            if let pageToken, model.shouldIgnoreAutomaticPageToken(pageToken) {
                model.recordAutomaticBridgeIgnored(type: type,
                                                    reason: "STALE_PAGE_TOKEN")
                return
            }
            if type != "selectedImage",
               let pageToken,
               let currentPageToken,
               pageToken != currentPageToken {
                model.recordAutomaticBridgeIgnored(type: type,
                                                    reason: "CURRENT_PAGE_TOKEN_MISMATCH")
                return
            }

            switch type {
            case "selectedImage":
                guard let dataURL = body["dataURL"] as? String else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "DATA_URL_MISSING"
                    )
                    return
                }
                guard handwritingImageStore.replace(withDataURL: dataURL) else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "DATA_URL_REJECTED"
                    )
                    return
                }
                model.setHandwritingImageAvailable(handwritingImageStore.hasImage)

            case "pageReady":
                if let pageToken {
                    currentPageToken = pageToken
                }
                guard handwritingImageStore.hasImage else { return }
                attachedWebView?.evaluateJavaScript(CanvasImageSessionService.openExistingCanvasScript)

            case "canvasReady":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                guard acceptPageToken(pageToken) else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "CURRENT_PAGE_TOKEN_MISMATCH")
                    return
                }
                let canvasPageURL = message.frameInfo.request.url ?? attachedWebView?.url
                let preparationGenerationID = model.handwritingPreparationGenerationID(
                    pageToken: pageToken,
                    pageURL: canvasPageURL
                )
                guard let script = handwritingImageStore.restorationScript(
                    generationID: preparationGenerationID
                ) else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "RESTORE_SCRIPT_UNAVAILABLE"
                    )
                    return
                }
                attachedWebView?.evaluateJavaScript(script) { [weak self] _, error in
                    guard let self, error != nil else { return }
                    self.model.handleHandwritingReady(
                        pageToken: pageToken,
                        ready: false,
                        generationID: preparationGenerationID,
                        pageURL: canvasPageURL ?? self.attachedWebView?.url
                    )
                }

            case "handwritingReady":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                guard acceptPageToken(pageToken) else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "CURRENT_PAGE_TOKEN_MISMATCH")
                    return
                }
                guard let ready = body["ready"] as? Bool else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "READY_MISSING"
                    )
                    return
                }
                model.handleHandwritingReady(
                    pageToken: pageToken,
                    ready: ready,
                    generationID: uint64Value(body["generationID"]),
                    pageURL: message.frameInfo.request.url ?? attachedWebView?.url
                )

            case "compactReady":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                guard acceptPageToken(pageToken) else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "CURRENT_PAGE_TOKEN_MISMATCH")
                    return
                }
                guard let hasComment = body["hasComment"] as? Bool else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "HAS_COMMENT_MISSING"
                    )
                    return
                }
                guard let canSubmit = body["canSubmit"] as? Bool else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "CAN_SUBMIT_MISSING"
                    )
                    return
                }
                let comment = body["comment"] as? String
                model.handleCompactReady(pageToken: pageToken,
                                         hasComment: hasComment,
                                         canSubmit: canSubmit,
                                         comment: comment,
                                         pageURL: message.frameInfo.request.url ?? attachedWebView?.url)

            case "threadUnavailable":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                guard acceptPageToken(pageToken) else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "CURRENT_PAGE_TOKEN_MISMATCH")
                    return
                }
                guard let reason = body["reason"] as? String,
                      reason == "THREAD_NOT_POSTABLE" else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "REASON_INVALID"
                    )
                    return
                }
                model.handleThreadUnavailable(
                    pageToken: pageToken,
                    pageURL: message.frameInfo.request.url ?? attachedWebView?.url,
                    reason: reason
                )

            case "submitReadiness":
                guard let pageToken else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "PAGE_TOKEN_MISSING"
                    )
                    return
                }
                guard let ready = body["ready"] as? Bool else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "READY_MISSING"
                    )
                    return
                }
                guard let reason = body["reason"] as? String else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "REASON_MISSING"
                    )
                    return
                }
                model.handleSubmitReadiness(pageToken: pageToken,
                                            ready: ready,
                                            reason: reason)

            case "submitObserved":
                guard let pageToken else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "PAGE_TOKEN_MISSING"
                    )
                    return
                }
                guard let submissionID = uint64Value(body["submissionID"]) else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "SUBMISSION_ID_MISSING"
                    )
                    return
                }
                model.handleSubmitObserved(pageToken: pageToken,
                                           submissionID: submissionID)

            case "postCompleted":
                model.handlePostCompleted(
                    pageToken: pageToken,
                    submissionID: uint64Value(body["submissionID"])
                )
                let canvasWasOpen = body["canvasWasOpen"] as? Bool ?? false
                guard canvasWasOpen || handwritingImageStore.hasImage else { return }
                attachedWebView?.evaluateJavaScript(CanvasImageSessionService.openExistingCanvasScript)

            case "postStatus":
                model.handlePostStatus(
                    body["status"] as? String,
                    pageToken: pageToken,
                    submissionID: uint64Value(body["submissionID"])
                )

            case "ownPostVisible":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                let matchedCount = integerValue(body["matchedCount"])
                let pendingCount = integerValue(body["pendingCount"])
                let responseCount = integerValue(body["responseCount"])
                let newResponseCount = integerValue(body["newResponseCount"])
                guard let matchedCount,
                      let pendingCount,
                      let responseCount,
                      let newResponseCount else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "COUNTS_MISSING"
                    )
                    return
                }
                model.handleOwnPostVisible(
                    pageToken: pageToken,
                    matchedCount: matchedCount,
                    pendingCount: pendingCount,
                    responseCount: responseCount,
                    newResponseCount: newResponseCount,
                    matchMethod: body["matchMethod"] as? String
                )

            case "ownPostObservation":
                guard let pageToken else {
                    model.recordAutomaticBridgeIgnored(type: type,
                                                        reason: "MISSING_PAGE_TOKEN")
                    return
                }
                let pendingCount = integerValue(body["pendingCount"])
                let responseCount = integerValue(body["responseCount"])
                let newResponseCount = integerValue(body["newResponseCount"])
                let matchedCount = integerValue(body["matchedCount"])
                guard let pendingCount,
                      let responseCount,
                      let newResponseCount,
                      let matchedCount else {
                    model.recordAutomaticBridgeInvalidPayload(
                        type: type,
                        reason: "COUNTS_MISSING"
                    )
                    return
                }
                model.handleOwnPostObservation(
                    pageToken: pageToken,
                    pendingCount: pendingCount,
                    responseCount: responseCount,
                    newResponseCount: newResponseCount,
                    matchedCount: matchedCount,
                    matchMethod: body["matchMethod"] as? String
                )

            default:
                model.recordAutomaticUnknownBridgeMessage()
                return
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            if ["http", "https", "about"].contains(scheme) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            startTimeout(for: webView)
            currentPageToken = nil
            model.navigationStarted()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.navigationCommitted(url: webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cancelTimeout()
            model.navigationFinished(url: webView.url)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            handleFailure(webView: webView, error: error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleFailure(webView: webView, error: error)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    webView.load(navigationAction.request)
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            var didComplete = false
            let completeOnce = {
                guard !didComplete else { return }
                didComplete = true
                completionHandler()
            }
            let host = frame.request.url?.host ?? webView.url?.host
            if let category = TargetPageAlertClassifier.category(host: host, message: message),
               let host {
                if category == .threadPostingUnavailable,
                   let url = [frame.request.url, webView.url]
                    .compactMap({ $0 })
                    .first(where: { ThreadListViewModel.threadID(from: $0) != nil }) {
                    onThreadPostingUnavailable(url)
                }
                if model.handleTargetPageAlert(category,
                                                host: host,
                                                message: message) == .autoDismiss {
                    completeOnce()
                    return
                }
            } else {
                let alertURL = frame.request.url ?? webView.url
                model.handleUnknownJavaScriptAlert(message: message,
                                                   host: host,
                                                   url: alertURL)
            }
            let alert = UIAlertController(title: dialogTitle(for: frame, webView: webView),
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completeOnce()
            })
            present(alert, from: webView, orCompleteWith: completeOnce)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            var didComplete = false
            let completeOnce: (Bool) -> Void = { value in
                guard !didComplete else { return }
                didComplete = true
                completionHandler(value)
            }
            let alert = UIAlertController(title: dialogTitle(for: frame, webView: webView),
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in
                completeOnce(false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completeOnce(true)
            })
            present(alert, from: webView) {
                completeOnce(false)
            }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            var didComplete = false
            let completeOnce: (String?) -> Void = { value in
                guard !didComplete else { return }
                didComplete = true
                completionHandler(value)
            }
            let alert = UIAlertController(title: dialogTitle(for: frame, webView: webView),
                                          message: prompt,
                                          preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in
                completeOnce(nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                completeOnce(alert?.textFields?.first?.text)
            })
            present(alert, from: webView) {
                completeOnce(nil)
            }
        }

        private func dialogTitle(for frame: WKFrameInfo, webView: WKWebView) -> String {
            let host = frame.request.url?.host ?? webView.url?.host ?? "Webサイト"
            return "\(host) のメッセージ"
        }

        private func present(_ alert: UIAlertController,
                             from webView: WKWebView,
                             orCompleteWith fallback: @escaping () -> Void) {
            guard let presenter = Self.topViewController(from: webView.window?.rootViewController) else {
                fallback()
                return
            }
            presenter.present(alert, animated: true)
        }

        private static func topViewController(from root: UIViewController?) -> UIViewController? {
            if let presented = root?.presentedViewController,
               !presented.isBeingDismissed {
                return topViewController(from: presented)
            }
            if let navigation = root as? UINavigationController {
                return topViewController(from: navigation.visibleViewController)
            }
            if let tabs = root as? UITabBarController {
                return topViewController(from: tabs.selectedViewController)
            }
            return root
        }

        private func startTimeout(for webView: WKWebView) {
            cancelTimeout()
            let timer = Timer(timeInterval: 30, repeats: false) { [weak self, weak webView] _ in
                guard let self, let webView, webView.isLoading else { return }
                webView.stopLoading()
                self.model.navigationTimedOut(url: webView.url)
            }
            timeoutTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func cancelTimeout() {
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }

        private func acceptPageToken(_ token: String?) -> Bool {
            guard let token, !token.isEmpty else { return false }
            if let currentPageToken {
                return currentPageToken == token
            }
            currentPageToken = token
            return true
        }

        private func integerValue(_ value: Any?) -> Int? {
            if let value = value as? Int {
                return value
            }
            if let value = value as? NSNumber {
                return value.intValue
            }
            return nil
        }

        private func uint64Value(_ value: Any?) -> UInt64? {
            if let value = value as? UInt64 {
                return value
            }
            if let value = value as? NSNumber, value.int64Value >= 0 {
                return UInt64(value.int64Value)
            }
            if let value = value as? String {
                return UInt64(value)
            }
            return nil
        }

        private func handleFailure(webView: WKWebView, error: Error) {
            cancelTimeout()
            if (error as NSError).code == NSURLErrorCancelled { return }
            model.navigationFailed(url: webView.url, error: error)
        }
    }
}
