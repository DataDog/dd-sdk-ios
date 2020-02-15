import Network

/// Network reachability details.
internal struct NetworkConnectionInfo {
    /// Tells if network is reachable.
    enum Reachability: String, Encodable {
        /// The network is reachable.
        case yes
        /// The network might be reachable after trying.
        case maybe
        /// The network is not reachable.
        case no // swiftlint:disable:this identifier_name
    }

    /// Network connection interfaces.
    enum Interface: String, Encodable {
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
    private let monitor: NWCurrentPathMonitor

    init(monitor: NWCurrentPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var current: NetworkConnectionInfo {
        let currentPath = monitor.currentPathInfo()
        let availableInterfaces: [NetworkConnectionInfo.Interface] = {
            currentPath.availableInterfaceTypes.map { interfaceType in
                switch interfaceType {
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
            switch currentPath.status {
            case .satisfied: return .yes
            case .requiresConnection: return .maybe
            case .unsatisfied: return .no
            @unknown default: return .maybe
            }
        }()

        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: currentPath.supportsIPv4,
            supportsIPv6: currentPath.supportsIPv6,
            isExpensive: currentPath.isExpensive,
            isConstrained: currentPath.isConstrained
        )
    }
}

// MARK: - Utilities

/// Utility protocol to inject `NWPathMonitor` to `NetworkConnectionInfoProvider`.
internal protocol NWCurrentPathMonitor {
    func start(queue: DispatchQueue)
    func cancel()
    func currentPathInfo() -> NWCurrentPathInfo
}

/// Utility type to aggregate current path info provided by `NWPathMonitor`,
internal struct NWCurrentPathInfo {
    let availableInterfaceTypes: [NWInterface.InterfaceType]
    let status: NWPath.Status
    let supportsIPv4: Bool
    let supportsIPv6: Bool
    let isExpensive: Bool
    let isConstrained: Bool?
}

/// Apple's `NWPathMonitor` conformance to utility `NWCurrentPathMonitor`.
extension NWPathMonitor: NWCurrentPathMonitor {
    func currentPathInfo() -> NWCurrentPathInfo {
        let isCurrentPathConstrained: Bool? = {
            if #available(iOS 13.0, macOS 10.15, *) {
                return currentPath.isConstrained
            } else {
                return nil
            }
        }()

        return NWCurrentPathInfo(
            availableInterfaceTypes: currentPath.availableInterfaces.map { $0.type },
            status: currentPath.status,
            supportsIPv4: currentPath.supportsIPv4,
            supportsIPv6: currentPath.supportsIPv6,
            isExpensive: currentPath.isExpensive,
            isConstrained: isCurrentPathConstrained
        )
    }
}
