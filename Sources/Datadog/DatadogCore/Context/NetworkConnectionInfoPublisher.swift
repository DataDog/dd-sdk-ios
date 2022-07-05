/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol NetworkConnectionInfoPublisher: ContextValuePublisher, ContextValueReader where Value == NetworkConnectionInfo? {
    func set(queue: DispatchQueue) -> Self
}

internal struct AnyNetworkConnectionInfoPublisher: NetworkConnectionInfoPublisher {
    private let publisher: AnyContextValuePublisher<NetworkConnectionInfo?>
    private let reader: AnyContextValueReader<NetworkConnectionInfo?>
    private let setQueue: (DispatchQueue) -> AnyNetworkConnectionInfoPublisher

    init<Publisher>(_ publisher: Publisher) where Publisher: NetworkConnectionInfoPublisher {
        self.publisher = publisher.eraseToAnyPublisher()
        self.reader = publisher.eraseToAnyReader()
        self.setQueue = { publisher.set(queue: $0).eraseToAnyPublisher() }
    }

    init() {
        if #available(iOS 12, tvOS 12, *) {
            self.init(NWPathMonitorPublisher())
        } else {
            self.init(SCNetworkReachabilityReader())
        }
    }

    func set(queue: DispatchQueue) -> Self {
        .init(setQueue(queue))
    }

    func read(_ receiver: ContextValueReceiver<NetworkConnectionInfo?>) {
        reader.read(receiver)
    }

    func publish(to receiver: @escaping ContextValueReceiver<NetworkConnectionInfo?>) {
        publisher.publish(to: receiver)
    }

    func cancel() {
        publisher.cancel()
    }
}

extension NetworkConnectionInfoPublisher {
    var initialValue: NetworkConnectionInfo? { nil }

    func eraseToAnyPublisher() -> AnyNetworkConnectionInfoPublisher {
        return AnyNetworkConnectionInfoPublisher(self)
    }
}

// MARK: - iOS 12+

import Network

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
private class NWPathMonitorPublisher: NetworkConnectionInfoPublisher {
    private let monitor: NWPathMonitor
    private var queue: DispatchQueue = .global(qos: .utility)

    init(monitor: NWPathMonitor = .init()) {
        self.monitor = monitor
    }

    func set(queue: DispatchQueue) -> Self {
        self.queue = queue
        return self
    }

    func read(_ receive: ContextValueReceiver<NetworkConnectionInfo?>) {
        // no-op
    }

    func publish(to receiver: @escaping ContextValueReceiver<NetworkConnectionInfo?>) {
        monitor.pathUpdateHandler = { path in
            let info = NetworkConnectionInfo(
                reachability: NetworkConnectionInfo.Reachability(from: path.status),
                availableInterfaces: path.availableInterfaces.map { .init($0.type) },
                supportsIPv4: path.supportsIPv4,
                supportsIPv6: path.supportsIPv6,
                isExpensive: path.isExpensive,
                isConstrained: {
                    guard #available(iOS 13, tvOS 13, *) else {
                        return nil
                    }
                    return path.isConstrained
                }()
            )

            receiver(info)
        }

        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

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
}

extension NetworkConnectionInfo.Interface {
    @available(iOS 12, tvOS 12, *)
    init(_ interface: NWInterface.InterfaceType) {
        switch interface {
        case .wifi: self = .wifi
        case .wiredEthernet: self = .wiredEthernet
        case .cellular: self = .cellular
        case .loopback: self = .loopback
        case .other: self = .other
        @unknown default: self = .other
        }
    }
}

// MARK: - iOS 11

import SystemConfiguration

private final class SCNetworkReachabilityReader: NetworkConnectionInfoPublisher {
    private let reachability: SCNetworkReachability

    init() {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)
        self.reachability = SCNetworkReachabilityCreateWithAddress(nil, &zero)! // swiftlint:disable:this force_unwrapping
    }

    func read(_ receive: ContextValueReceiver<NetworkConnectionInfo?>) {
        var retrieval = SCNetworkReachabilityFlags()
        let flags = (SCNetworkReachabilityGetFlags(reachability, &retrieval)) ? retrieval : nil
        let info = NetworkConnectionInfo(
            reachability: NetworkConnectionInfo.Reachability(from: flags),
            availableInterfaces: NetworkConnectionInfo.Interface(flags).map { [$0] },
            supportsIPv4: nil,
            supportsIPv6: nil,
            isExpensive: nil,
            isConstrained: nil
        )

        receive(info)
    }

    func set(queue: DispatchQueue) -> Self {
        // no-op
        return self
    }

    func publish(to receiver: @escaping ContextValueReceiver<NetworkConnectionInfo?>) {
        // no-op
    }

    func cancel() {
        // no-op
    }
}

extension NetworkConnectionInfo.Reachability {
    init(from flags: SCNetworkReachabilityFlags?) {
        switch flags?.contains(.reachable) {
        case .none: self = .maybe
        case .some(true): self = .yes
        case .some(false): self = .no
        }
    }
}

extension NetworkConnectionInfo.Interface {
    @available(iOS 2.0, macCatalyst 13.0, *)
    init?(_ flags: SCNetworkReachabilityFlags?) {
        guard let flags = flags, flags.contains(.isWWAN) else {
            return nil
        }
        self = .cellular
    }
}
