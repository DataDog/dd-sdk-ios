/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Network

/// Network connection details.
internal struct NetworkConnectionInfo {
    /// Tells if network is reachable.
    enum Reachability: String, Encodable, CaseIterable {
        /// The network is reachable.
        case yes
        /// The network might be reachable after trying.
        case maybe
        /// The network is not reachable.
        case no
    }

    /// Network connection interfaces.
    enum Interface: String, Encodable, CaseIterable {
        case wifi
        case wiredEthernet
        case cellular
        case loopback
        case other
    }

    let reachability: Reachability
    let availableInterfaces: [Interface]?
    let supportsIPv4: Bool?
    let supportsIPv6: Bool?
    let isExpensive: Bool?
    let isConstrained: Bool?
}

/// Provides the current `NetworkConnectionInfo`.
internal protocol NetworkConnectionInfoProviderType {
    /// Current `NetworkConnectionInfo`. It might return `nil` for the first attempt(s),
    /// shortly after provider's initialization, until underlying monitor does not warm up.
    var current: NetworkConnectionInfo? { get }
}

internal class NetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    /// The `NetworkConnectionInfoProviderType` for current iOS version.
    private let wrappedProvider: NetworkConnectionInfoProviderType

    init() {
        if #available(iOS 12, *) {
            self.wrappedProvider = NWPathNetworkConnectionInfoProvider()
        } else {
            self.wrappedProvider = iOS11NetworkConnectionInfoProvider()
        }
    }

    var current: NetworkConnectionInfo? { wrappedProvider.current }
}

// MARK: - iOS 12+

/// Thread-safe wrapper for `NWPathMonitor`.
///
/// The `NWPathMonitor` provides two models of getting the `NWPath` info:
/// * pulling the value with `monitor.currentPath`,
/// * pushing the value with `monitor.pathUpdateHandler = { path in ... }`.
///
/// We found the pulling model to not be thread-safe: accessing `currentPath` properties lead to occasional crashes.
/// The `ThreadSafeNWPathMonitor` listens to path updates and synchonizes the values on `.current` property.
/// This adds the necessary thread-safety and keeps the convenience of pulling.
@available(iOS 12, *)
internal class NWPathNetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    /// Queue synchronizing the reads and updates to `NWPath`.
    private let queue = DispatchQueue(
        label: "com.datadoghq.thread-safe-nw-path-monitor",
        target: .global(qos: .utility)
    )
    private let monitor: NWPathMonitor

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.unsafeCurrentNetworkConnectionInfo = NetworkConnectionInfo(
                reachability: NetworkConnectionInfo.Reachability(from: path.status),
                availableInterfaces: Array(fromInterfaceTypes: path.availableInterfaces.map { $0.type }),
                supportsIPv4: path.supportsIPv4,
                supportsIPv6: path.supportsIPv6,
                isExpensive: path.isExpensive,
                isConstrained: {
                    if #available(iOS 13.0, *) {
                        return path.isConstrained
                    } else {
                        return nil
                    }
                }()
            )
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Unsynchronized `NetworkConnectionInfo`. Use `self.current` setter & getter.
    private var unsafeCurrentNetworkConnectionInfo: NetworkConnectionInfo?
    var current: NetworkConnectionInfo? {
        get { queue.sync { unsafeCurrentNetworkConnectionInfo } }
        set { queue.async { self.unsafeCurrentNetworkConnectionInfo = newValue } }
    }
}

// MARK: - iOS 11

import SystemConfiguration

internal class iOS11NetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    private let reachability: SCNetworkReachability = {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)

        return SCNetworkReachabilityCreateWithAddress(nil, &zero)! // swiftlint:disable:this force_unwrapping
    }()

    var current: NetworkConnectionInfo? {
        var retrieval = SCNetworkReachabilityFlags()
        let flags = (SCNetworkReachabilityGetFlags(reachability, &retrieval)) ? retrieval : nil
        return NetworkConnectionInfo(
            reachability: NetworkConnectionInfo.Reachability(from: flags),
            availableInterfaces: Array(fromReachabilityFlags: flags),
            supportsIPv4: nil,
            supportsIPv6: nil,
            isExpensive: nil,
            isConstrained: nil
        )
    }
}

// MARK: Conversion helpers

extension NetworkConnectionInfo.Reachability {
    @available(iOS 12, *)
    init(from status: NWPath.Status) {
        switch status {
        case .satisfied: self = .yes
        case .requiresConnection: self = .maybe
        case .unsatisfied: self = .no
        @unknown default: self = .maybe
        }
    }

    init(from flags: SCNetworkReachabilityFlags?) {
        switch flags?.contains(.reachable) {
        case .none: self = .maybe
        case .some(true): self = .yes
        case .some(false): self = .no
        }
    }
}

extension Array where Element == NetworkConnectionInfo.Interface {
    @available(iOS 12, *)
    init(fromInterfaceTypes interfaceTypes: [NWInterface.InterfaceType]) {
        self = interfaceTypes.map { interface in
            switch interface {
            case .wifi: return .wifi
            case .wiredEthernet: return .wiredEthernet
            case .cellular: return .cellular
            case .loopback: return .loopback
            case .other: return .other
            @unknown default: return .other
            }
        }
    }

    @available(iOS 2.0, macCatalyst 13.0, *)
    init?(fromReachabilityFlags flags: SCNetworkReachabilityFlags?) {
        if let flags = flags,
            flags.contains(.isWWAN) {
            self = [.cellular]
        } else {
            return nil
        }
    }
}
