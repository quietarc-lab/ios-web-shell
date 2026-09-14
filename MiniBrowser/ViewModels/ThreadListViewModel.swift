import Combine
import Foundation

@MainActor
final class ThreadListViewModel: ObservableObject, AutomaticCatalogProvider {
    private static let listItemLimit = 60
    static let excludedThreadRetention: TimeInterval = 6 * 60 * 60
    private enum Keys {
        static let sort = "ThreadListSort"
        static let expanded = "ThreadListExpanded"
        static let openCounts = "ThreadListOpenCounts"
        static let excludedThreadExpirations = "ThreadListExcludedThreadExpirations"
    }

    @Published private(set) var items: [ThreadListItem] = []
    @Published private(set) var selectedSort: ThreadListSort
    @Published private(set) var isExpanded: Bool
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var openCounts: [String: Int]
    @Published private(set) var excludedThreadIDs: Set<String>

    private let service: ThreadListService
    private let defaults: UserDefaults
    private var excludedThreadExpirations: [String: Date]
    private var isSceneActive = true
    private var isNetworkActivityAllowed = true
    private var userAgent = BrowserUserAgent.all[0].value
    private var hasStarted = false
    private var loadTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    // A slow/failed request must not permanently starve cells later in the
    // grid: the next automatic refresh starts after the last attempted cell.
    private var nextThumbnailRetryID: String?

    init(service: ThreadListService = ThreadListService(),
         defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        self.selectedSort = ThreadListSort(
            rawValue: defaults.string(forKey: Keys.sort) ?? ""
        ) ?? .momentum
        self.isExpanded = defaults.object(forKey: Keys.expanded) == nil
            ? true
            : defaults.bool(forKey: Keys.expanded)
        self.openCounts = defaults.dictionary(forKey: Keys.openCounts)?
            .compactMapValues { ($0 as? NSNumber)?.intValue } ?? [:]
        let now = Date()
        let stored = defaults.dictionary(forKey: Keys.excludedThreadExpirations) ?? [:]
        var validExpirations: [String: Date] = [:]
        for (id, value) in stored {
            let timestamp: TimeInterval?
            if let number = value as? NSNumber {
                timestamp = number.doubleValue
            } else if let date = value as? Date {
                timestamp = date.timeIntervalSince1970
            } else {
                timestamp = nil
            }
            guard let timestamp else { continue }
            let expiration = Date(timeIntervalSince1970: timestamp)
            if expiration > now {
                validExpirations[id] = expiration
            }
        }
        self.excludedThreadExpirations = validExpirations
        self.excludedThreadIDs = Set(validExpirations.keys)
        if validExpirations.count != stored.count {
            persistExcludedThreadExpirations()
        }
    }

    deinit {
        loadTask?.cancel()
        refreshLoopTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if isExpanded {
            refresh()
        }
        updateRefreshLoop()
    }

    func setSceneActive(_ active: Bool) {
        guard isSceneActive != active else { return }
        isSceneActive = active
        updateRefreshLoop()
    }

    func setNetworkActivityAllowed(_ allowed: Bool) {
        guard isNetworkActivityAllowed != allowed else { return }
        isNetworkActivityAllowed = allowed
        if !allowed {
            loadTask?.cancel()
            loadTask = nil
            isRefreshing = false
        } else if hasStarted, isExpanded {
            refresh()
        }
        updateRefreshLoop()
    }

    func setUserAgent(_ value: String) {
        userAgent = value
    }

    func currentPostSnapshot(limit: Int = 60) -> CatalogPostSnapshot {
        purgeExpiredThreadExclusions()
        let boundedLimit = min(Self.listItemLimit, max(0, limit))
        return CatalogPostSnapshot(
            sort: selectedSort,
            targets: items.filter { !excludedThreadIDs.contains($0.id) }
                .prefix(boundedLimit)
                .map {
                CatalogPostTarget(id: $0.id, threadURL: $0.threadURL)
            }
        )
    }

    /// Fetches one fresh snapshot for a running multi-thread session. This is
    /// deliberately separate from the normal refresh loop so the session can
    /// request exactly one deterministic end-of-catalog refresh.
    func refreshPostSnapshot(excludingIDs: Set<String>,
                             limit: Int = 60) async throws -> CatalogPostSnapshot {
        guard isSceneActive, isNetworkActivityAllowed else {
            throw CancellationError()
        }
        purgeExpiredThreadExclusions()
        loadTask?.cancel()
        loadTask = nil
        let sort = selectedSort
        let currentUA = userAgent
        let excluded = excludedThreadIDs.union(excludingIDs)
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        await service.updateUserAgent(currentUA)
        let loaded = try await service.fetchList(
            sort: sort,
            limit: min(Self.listItemLimit, max(0, limit)),
            excludingIDs: excluded
        )
        try Task.checkCancellation()
        guard selectedSort == sort else { throw CancellationError() }
        items = Self.mergingDisplayState(of: loaded, with: items)
        // Details are loaded by the normal refresh loop. Keeping this one-shot
        // operation lightweight prevents catalog metadata from delaying the
        // next target transition.
        return CatalogPostSnapshot(
            sort: sort,
            targets: loaded.map {
                CatalogPostTarget(id: $0.id, threadURL: $0.threadURL)
            }
        )
    }

    func toggleExpanded() {
        isExpanded.toggle()
        defaults.set(isExpanded, forKey: Keys.expanded)
        if isExpanded {
            refresh()
        } else {
            loadTask?.cancel()
            isRefreshing = false
        }
        updateRefreshLoop()
    }

    func selectSort(_ sort: ThreadListSort) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        defaults.set(sort.rawValue, forKey: Keys.sort)
        refresh()
    }

    func refresh() {
        guard isExpanded, isSceneActive, isNetworkActivityAllowed else { return }
        purgeExpiredThreadExclusions()
        loadTask?.cancel()
        let sort = selectedSort
        isRefreshing = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                await service.updateUserAgent(userAgent)
                let loaded = try await service.fetchList(
                    sort: sort,
                    limit: Self.listItemLimit,
                    excludingIDs: excludedThreadIDs
                )
                try Task.checkCancellation()
                guard selectedSort == sort, isNetworkActivityAllowed else { return }
                items = Self.mergingDisplayState(of: loaded, with: items)
                isRefreshing = false
                await loadThumbnails(for: loaded, sort: sort)
                await loadOpenerTexts(for: loaded, sort: sort)
            } catch is CancellationError {
                isRefreshing = false
            } catch {
                isRefreshing = false
                errorMessage = "更新失敗"
            }
        }
    }

    func recordOpen(_ item: ThreadListItem) {
        openCounts[item.id, default: 0] += 1
        if openCounts.count > 1_000 {
            let excess = openCounts.count - 1_000
            let oldestIDs = openCounts.keys.sorted {
                (Int($0) ?? 0) < (Int($1) ?? 0)
            }.prefix(excess)
            for id in oldestIDs {
                openCounts.removeValue(forKey: id)
            }
        }
        defaults.set(openCounts, forKey: Keys.openCounts)
    }

    func openCount(for item: ThreadListItem) -> Int {
        openCounts[item.id, default: 0]
    }

    func resetOpenHistory() {
        openCounts = [:]
        defaults.removeObject(forKey: Keys.openCounts)
    }

    func excludeThread(_ url: URL) {
        guard let id = Self.threadID(from: url) else { return }
        excludeThread(id: id)
    }

    func excludeThread(id: String) {
        guard !id.isEmpty else { return }
        purgeExpiredThreadExclusions()
        let expiration = Date().addingTimeInterval(Self.excludedThreadRetention)
        excludedThreadExpirations[id] = expiration
        excludedThreadIDs.insert(id)
        persistExcludedThreadExpirations()
        loadTask?.cancel()
        loadTask = nil
        isRefreshing = false
        nextThumbnailRetryID = nextThumbnailRetryID == id ? nil : nextThumbnailRetryID
        items.removeAll { $0.id == id }
    }

    nonisolated static func threadID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "img.2chan.net",
              let match = url.path.range(of: #"^/[^/]+/res/(\d+)\.htm$"#,
                                         options: .regularExpression) else {
            return nil
        }
        let path = String(url.path[match])
        return path.split(separator: "/").last?
            .split(separator: ".").first
            .map(String.init)
    }

    private func purgeExpiredThreadExclusions(now: Date = Date()) {
        let valid = excludedThreadExpirations.filter { $0.value > now }
        guard valid.count != excludedThreadExpirations.count else { return }
        excludedThreadExpirations = valid
        excludedThreadIDs = Set(valid.keys)
        persistExcludedThreadExpirations()
    }

    private func persistExcludedThreadExpirations() {
        let values = excludedThreadExpirations.mapValues { $0.timeIntervalSince1970 }
        if values.isEmpty {
            defaults.removeObject(forKey: Keys.excludedThreadExpirations)
        } else {
            defaults.set(values, forKey: Keys.excludedThreadExpirations)
        }
    }

    private func loadThumbnails(for loaded: [ThreadListItem],
                                sort: ThreadListSort) async {
        let unresolved = loaded.filter { item in
            items.first(where: { $0.id == item.id })?.thumbnailData == nil
        }
        let ordered = orderedForThumbnailRetry(unresolved)

        for (index, item) in ordered.enumerated() {
            guard !Task.isCancelled, selectedSort == sort else { return }
            advanceThumbnailRetry(after: index, in: ordered)
            do {
                let data = try await service.thumbnailData(for: item,
                                                           referer: sort.url)
                guard !Task.isCancelled, selectedSort == sort else { return }
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].thumbnailData = data
                    items[index].thumbnailLoadFailed = false
                }
            } catch is CancellationError {
                return
            } catch {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].thumbnailLoadFailed = true
                }
            }
            await Task.yield()
        }
    }

    private func orderedForThumbnailRetry(_ unresolved: [ThreadListItem]) -> [ThreadListItem] {
        guard let nextThumbnailRetryID,
              let index = unresolved.firstIndex(where: { $0.id == nextThumbnailRetryID }) else {
            return unresolved
        }
        return Array(unresolved[index...]) + Array(unresolved[..<index])
    }

    private func advanceThumbnailRetry(after index: Int,
                                       in ordered: [ThreadListItem]) {
        guard !ordered.isEmpty else {
            nextThumbnailRetryID = nil
            return
        }
        nextThumbnailRetryID = ordered[(index + 1) % ordered.count].id
    }

    nonisolated static func mergingDisplayState(of loaded: [ThreadListItem],
                                                 with previous: [ThreadListItem]) -> [ThreadListItem] {
        let previousByID = previous.reduce(into: [String: ThreadListItem]()) { result, item in
            result[item.id] = item
        }
        return loaded.map { item in
            guard let oldItem = previousByID[item.id] else { return item }

            var merged = item
            // Keep a successfully fetched image while a 60-second refresh is
            // obtaining the new list. A changed thumbnail URL deliberately
            // starts fresh so it can be fetched again.
            if oldItem.thumbnailURL == item.thumbnailURL {
                merged.thumbnailData = oldItem.thumbnailData
                merged.thumbnailLoadFailed = oldItem.thumbnailLoadFailed
            }
            merged.openerText = oldItem.openerText
            return merged
        }
    }

    private func loadOpenerTexts(for loaded: [ThreadListItem],
                                 sort: ThreadListSort) async {
        for item in loaded {
            guard !Task.isCancelled, selectedSort == sort else { return }
            let text: String
            do {
                text = try await service.openerText(for: item)
            } catch is CancellationError {
                return
            } catch {
                text = "本文取得失敗"
            }

            guard !Task.isCancelled, selectedSort == sort else { return }
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].openerText = text
            }
            await Task.yield()
        }
    }

    private func updateRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        guard hasStarted, isExpanded, isSceneActive, isNetworkActivityAllowed else { return }

        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self, self.isExpanded, self.isSceneActive,
                      self.isNetworkActivityAllowed else { return }
                self.refresh()
            }
        }
    }
}
