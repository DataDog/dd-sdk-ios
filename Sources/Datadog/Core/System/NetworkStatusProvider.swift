import Network

/// Describes  network reachability condition.
internal struct NetworkStatus {
    enum Reachability {
        /// The network is reachable.
        case yes
        /// The network is not reachable.
        case no // swiftlint:disable:this identifier_name
        /// The network might be reachable after trying.
        case maybe
    }

    let reachability: Reachability
}

/// Shared provider to get current `NetworkStatus`.
internal protocol NetworkStatusProviderType {
    var current: NetworkStatus { get }
}

internal class NetworkStatusProvider: NetworkStatusProviderType {
    private let queue = DispatchQueue.global(qos: .utility)
    private let monitor = NWPathMonitor()

    init() {
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var current: NetworkStatus {
        switch monitor.currentPath.status {
        case .satisfied:
            return NetworkStatus(reachability: .yes)
        case .requiresConnection:
            return NetworkStatus(reachability: .maybe)
        case .unsatisfied:
            return NetworkStatus(reachability: .no)
        @unknown default:
            return NetworkStatus(reachability: .maybe)
        }
    }
}
