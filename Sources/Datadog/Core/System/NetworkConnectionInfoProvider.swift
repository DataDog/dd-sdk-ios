/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Network

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
                reachability: NetworkConnectionInfo.Reachability(path.status),
                availableInterfaces: path.availableInterfaces.map { .init($0.type) },
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
            reachability: NetworkConnectionInfo.Reachability(flags),
            availableInterfaces: NetworkConnectionInfo.Interface(flags).map { [$0] },
            supportsIPv4: nil,
            supportsIPv6: nil,
            isExpensive: nil,
            isConstrained: nil
        )
    }
}
