/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Network

/// Network connection details.
public struct NetworkConnectionInfo: Equatable {
    /// Tells if network is reachable.
    public enum Reachability: String, Codable, CaseIterable {
        /// The network is reachable.
        case yes
        /// The network might be reachable after trying.
        case maybe
        /// The network is not reachable.
        case no
    }

    /// Network connection interfaces.
    public enum Interface: String, Codable, CaseIterable {
        case wifi
        case wiredEthernet
        case cellular
        case loopback
        case other
    }

    /// Network reachability status.
    public let reachability: Reachability
    /// Available network interfaces.
    public let availableInterfaces: [Interface]?
    /// A Boolean indicating whether the connection supports IPv4 traffic.
    public let supportsIPv4: Bool?
    /// A Boolean indicating whether the connection supports IPv6 traffic.
    public let supportsIPv6: Bool?
    /// A Boolean indicating if the connection uses an interface that is considered expensive, such as Cellular or a Personal Hotspot.
    public let isExpensive: Bool?
    /// A Boolean indicating if the connection uses an interface in Low Data Mode.
    public let isConstrained: Bool?
}

/// An observer for `NetworkConnectionInfo` value.
internal typealias NetworkConnectionInfoObserver = ValueObserver

/// Provides the current `NetworkConnectionInfo`.
internal protocol NetworkConnectionInfoProviderType {
    /// Current `NetworkConnectionInfo`. It might return `nil` for the first attempt(s),
    /// shortly after provider's initialization, until underlying monitor does not warm up.
    var current: NetworkConnectionInfo? { get }
    /// Subscribes for `NetworkConnectionInfo` updates.
    func subscribe<Observer: NetworkConnectionInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == NetworkConnectionInfo?
}

/// An interface for the iOS-version specific network info provider.
internal protocol WrappedNetworkConnectionInfoProvider {
    var current: NetworkConnectionInfo? { get }
}

internal class NetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    /// The `NetworkConnectionInfo` provider for the current iOS version.
    private let wrappedProvider: WrappedNetworkConnectionInfoProvider
    /// Publisher for notifying observers on `NetworkConnectionInfo` change.
    private let publisher: ValuePublisher<NetworkConnectionInfo?>

    convenience init() {
        if #available(iOS 12, tvOS 12, *) {
            self.init(wrappedProvider: NWPathNetworkConnectionInfoProvider())
        } else {
            self.init(wrappedProvider: iOS11NetworkConnectionInfoProvider())
        }
    }

    init(wrappedProvider: WrappedNetworkConnectionInfoProvider) {
        self.wrappedProvider = wrappedProvider
        self.publisher = ValuePublisher(initialValue: nil)
    }

    var current: NetworkConnectionInfo? {
        let nextValue = wrappedProvider.current
        // `NetworkConnectionInfo` subscribers are notified as a side-effect of retrieving the
        // current `NetworkConnectionInfo` value.
        publisher.publishAsync(nextValue)
        return nextValue
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: NetworkConnectionInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == NetworkConnectionInfo? {
        publisher.subscribe(subscriber)
    }
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
@available(iOS 12, tvOS 12, *)
internal class NWPathNetworkConnectionInfoProvider: WrappedNetworkConnectionInfoProvider {
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
                    if #available(iOS 13, tvOS 13, *) {
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

internal class iOS11NetworkConnectionInfoProvider: WrappedNetworkConnectionInfoProvider {
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

// MARK: - Conversion helpers

extension NetworkConnectionInfo.Reachability {
    @available(iOS 12, tvOS 12, *)
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
    @available(iOS 12, tvOS 12, *)
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
