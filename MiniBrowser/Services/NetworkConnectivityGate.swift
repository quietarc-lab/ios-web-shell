import Foundation
import Network

/// Small foreground-only gate for requests that must not be started while
/// iOS reports that no usable network path is available.  In particular, a
/// cellular path can be temporarily `requiresConnection` while Shortcuts is
/// bringing the radio back.  Starting an IP check in that window can make
/// iOS present its system-level "use Wi-Fi" alert before the request fails.
///
/// This gate never changes network settings and never treats a satisfied path
/// as proof that a remote host is reachable.  It only prevents an avoidable
/// request during the local path transition; the URLSession timeout and
/// caller-specific retry policy remain authoritative for remote failures.
@MainActor
final class NetworkConnectivityGate {
    enum PathState: Equatable, Sendable {
        case satisfied
        case requiresConnection
        case unsatisfied

        var rawValue: String {
            switch self {
            case .satisfied:
                return "SATISFIED"
            case .requiresConnection:
                return "REQUIRES_CONNECTION"
            case .unsatisfied:
                return "UNSATISFIED"
            }
        }
    }

    enum Interface: Equatable, Sendable {
        case wifi
        case cellular
        case wiredEthernet
        case other
        case unavailable

        var rawValue: String {
            switch self {
            case .wifi:
                return "WIFI"
            case .cellular:
                return "CELLULAR"
            case .wiredEthernet:
                return "WIRED_ETHERNET"
            case .other:
                return "OTHER"
            case .unavailable:
                return "UNAVAILABLE"
            }
        }
    }

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "local.sidestore.MiniBrowser.network-path")
    private(set) var pathState: PathState = .requiresConnection
    private(set) var interface: Interface = .unavailable

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.pathState(for: path.status)
            let interface = Self.interface(for: path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pathState = state
                self.interface = interface
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var isSatisfied: Bool {
        pathState == .satisfied
    }

    /// Waits briefly for a usable local path.  A false result means the
    /// caller should skip/defer its request rather than forcing a connection.
    func waitUntilSatisfied(timeoutNanoseconds: UInt64) async -> Bool {
        guard timeoutNanoseconds > 0 else { return isSatisfied }
        if isSatisfied { return true }

        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !Task.isCancelled {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            let remaining = deadline - now
            try? await Task.sleep(
                nanoseconds: min(remaining, 250_000_000)
            )
            if isSatisfied { return true }
        }
        return isSatisfied
    }

    nonisolated private static func pathState(for status: NWPath.Status) -> PathState {
        switch status {
        case .satisfied:
            return .satisfied
        case .requiresConnection:
            return .requiresConnection
        case .unsatisfied:
            return .unsatisfied
        @unknown default:
            return .unsatisfied
        }
    }

    nonisolated private static func interface(for path: NWPath) -> Interface {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        guard path.status == .satisfied else { return .unavailable }
        return .other
    }
}
