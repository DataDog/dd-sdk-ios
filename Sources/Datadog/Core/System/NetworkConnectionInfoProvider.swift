import Network

/// Network reachability details.
internal struct NetworkConnectionInfo {
    /// Tells if network is reachable.
    enum Reachability {
        /// The network is reachable.
        case yes
        /// The network might be reachable after trying.
        case maybe
        /// The network is not reachable.
        case no // swiftlint:disable:this identifier_name
    }

    /// Network connection interfaces.
    enum Interface {
        case wifi
        case wiredEthernet
        case cellular
        case loopback
        case other
    }

    let reachability: Reachability
    let availableInterfaces: [Interface]
    let supportsIPv4: Bool
    let supportsIPv6: Bool
    let isExpensive: Bool
    let isConstrained: Bool?
}

internal protocol NetworkConnectionInfoProviderType {
    var current: NetworkConnectionInfo { get }
}

internal class NetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    private let queue = DispatchQueue.global(qos: .utility)
    private let monitor = NWPathMonitor()

    init() {
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var current: NetworkConnectionInfo {
        let availableInterfaces: [NetworkConnectionInfo.Interface] = {
            monitor.currentPath.availableInterfaces.map { interface in
                switch interface.type {
                case .wifi: return .wifi
                case .wiredEthernet: return .wiredEthernet
                case .cellular: return .cellular
                case .loopback: return .loopback
                case .other: return .other
                @unknown default: return .other
                }
            }
        }()

        let reachability: NetworkConnectionInfo.Reachability = {
            switch monitor.currentPath.status {
            case .satisfied: return .yes
            case .requiresConnection: return .maybe
            case .unsatisfied: return .no
            @unknown default: return .maybe
            }
        }()

        let isConstrained: Bool? = {
            if #available(iOS 13.0, OSX 10.15, *) {
                return monitor.currentPath.isConstrained
            } else {
                return nil
            }
        }()

        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: monitor.currentPath.supportsIPv4,
            supportsIPv6: monitor.currentPath.supportsIPv6,
            isExpensive: monitor.currentPath.isExpensive,
            isConstrained: isConstrained
        )
    }
}
