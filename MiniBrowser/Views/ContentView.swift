import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BrowserViewModel
    @StateObject private var listModel: ThreadListViewModel
    @StateObject private var stopAlertFeedback = StopAlertFeedbackController()
    @State private var showingBookmarks = false
    @Environment(\.scenePhase) private var scenePhase

    init(model: BrowserViewModel) {
        self.model = model
        _listModel = StateObject(wrappedValue: ThreadListViewModel())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar
                Divider()
                browserContent
                Divider()
                bottomBar
            }

            ToastStackView(toasts: model.toasts)
                .padding(.horizontal, 12)
                .padding(.bottom, 58)

            SitePostStatusView(status: model.sitePostStatus,
                               automaticStatus: model.automaticPostStatus)
                .padding(.bottom, 58)
                .zIndex(1)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            listModel.setUserAgent(model.effectiveUserAgent)
            model.attachAutomaticCatalogProvider(listModel)
            listModel.start()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            let isActive = phase == .active
            listModel.setSceneActive(isActive)
            model.setAppSceneActive(isActive)
        }
        .onDisappear {
            model.setAppSceneActive(false)
            stopAlertFeedback.stop()
        }
        .onChange(of: model.isIdentityRefreshInProgress) { _, isInProgress in
            listModel.setUserAgent(model.effectiveUserAgent)
            listModel.setNetworkActivityAllowed(!isInProgress)
        }
        .onChange(of: model.isolationStopNotice, initial: true) { _, notice in
            if notice == nil {
                stopAlertFeedback.stop()
            } else {
                stopAlertFeedback.startIfNeeded()
            }
        }
        .alert(item: $model.isolationStopNotice) { notice in
            let threadDetail = notice.threadID.map { "\nスレッド: \($0)" } ?? ""
            return Alert(
                title: Text(notice.kind.alertTitle),
                message: Text("\(notice.kind.alertMessage)\(threadDetail)"),
                dismissButton: .default(Text("OK")) {
                    model.acknowledgeIsolationStop()
                }
            )
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarkListView(store: model.bookmarkStore,
                             currentURL: model.currentURL,
                             onOpen: model.openBookmark,
                             onValidateBookmarklet: model.validateBookmarklet)
        }
    }

    private var browserContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                BrowserWebView(model: model,
                               onThreadPostingUnavailable: { url in
                                   listModel.excludeThread(url)
                               })
                    .frame(height: listModel.isExpanded
                        ? geometry.size.height * 0.65
                        : max(0, geometry.size.height - 29))
                Divider()
                if listModel.isExpanded {
                    ThreadListView(model: listModel,
                                      onOpenThread: model.openThreadListThread,
                                      sameThreadRepeatEnabled: model.sameThreadRepeatEnabled,
                                      onToggleSameThreadRepeat: model.toggleSameThreadRepeat,
                                      isolationStopEnabled: model.isolationStopEnabled,
                                      onToggleIsolationStop: model.toggleIsolationStop,
                                      multiThreadEnabled: model.multiThreadEnabled,
                                      multiThreadSessionActive: model.multiThreadSessionActive,
                                      onToggleMultiThread: model.toggleMultiThread)
                        .frame(height: max(0, geometry.size.height * 0.35 - 1))
                } else {
                    ThreadListCollapsedBar(model: listModel,
                                            interactionLocked: model.multiThreadSessionActive)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                showingBookmarks = true
            } label: {
                Image(systemName: "bookmark")
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ブックマーク")
            .disabled(model.multiThreadSessionActive)

            URLTextField(text: $model.urlText, onGo: model.openURLFromField)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                .layoutPriority(1)
                .disabled(model.multiThreadSessionActive)

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var bottomBar: some View {
        GeometryReader { geometry in
            let buttonWidth = geometry.size.width / 6
            HStack(spacing: 0) {
                toolbarButton("chevron.backward", label: "戻る", width: buttonWidth,
                              enabled: model.canGoBack && !model.multiThreadSessionActive,
                              action: model.goBack)
                toolbarButton("chevron.forward", label: "進む", width: buttonWidth,
                              enabled: model.canGoForward && !model.multiThreadSessionActive,
                              action: model.goForward)
                toolbarButton("arrow.clockwise", label: "更新", width: buttonWidth,
                              enabled: !model.multiThreadSessionActive,
                              action: model.reload)
                toolbarTextButton(model.userAgentButtonTitle,
                                  width: buttonWidth,
                                  enabled: !model.multiThreadSessionActive &&
                                      !model.isUAChanging && !model.isLoading &&
                                      !model.isIdentityRefreshInProgress,
                                  action: model.cycleUserAgent)
                toolbarTextButton("Cookie",
                                  width: buttonWidth,
                                  enabled: !model.multiThreadSessionActive &&
                                      !model.isCookieRefreshing && !model.isLoading,
                                  action: model.refreshCookies)
                toolbarTextButton("AP",
                                  width: buttonWidth,
                                  enabled: !model.multiThreadSessionActive &&
                                      !model.isAPRunning && !model.isIdentityRefreshInProgress,
                                  action: model.startCellularReconnect)
            }
        }
        .frame(height: 48)
        .background(.bar)
        .contextMenu {
            Button("ログをコピー", action: model.copyDebugLog)
        }
    }

    private func toolbarButton(_ systemName: String,
                               label: String,
                               width: CGFloat,
                               enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: width, height: 48)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func toolbarTextButton(_ title: String,
                                   width: CGFloat,
                                   enabled: Bool = true,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width, height: 48)
        }
            .disabled(!enabled)
    }
}
