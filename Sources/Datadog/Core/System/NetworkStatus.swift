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
internal protocol NetworkStatusProvider {
    var current: NetworkStatus { get }
}

internal struct PlatformSpecificNetworkStatusProvider: NetworkStatusProvider {
    private let monitor = NWPathMonitor()

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
