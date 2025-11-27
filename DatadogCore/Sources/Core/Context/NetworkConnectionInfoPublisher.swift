/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import Network

/// Thread-safe wrapper for `NWPathMonitor`.
///
/// The `NWPathMonitor` provides two models of getting the `NWPath` info:
/// * pulling the value with `monitor.currentPath`,
/// * pushing the value with `monitor.pathUpdateHandler = { path in ... }`.
///
/// We found the pulling model to not be thread-safe: accessing `currentPath` properties lead to occasional crashes.
/// The `ThreadSafeNWPathMonitor` listens to path updates and synchronizes the values on `.current` property.
/// This adds the necessary thread-safety and keeps the convenience of pulling.
internal struct NWPathMonitorPublisher: ContextValuePublisher {
    private static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.nw-path-monitor-publisher",
        target: .global(qos: .utility)
    )

    let initialValue: NetworkConnectionInfo?

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init(
        monitor: NWPathMonitor = .init(),
        queue: DispatchQueue = NWPathMonitorPublisher.defaultQueue
    ) {
        self.monitor = monitor
        self.queue = queue
        self.initialValue = NetworkConnectionInfo(monitor.currentPath)
    }

    func publish(to receiver: @escaping ContextValueReceiver<NetworkConnectionInfo?>) {
        monitor.pathUpdateHandler = {
            let info = NetworkConnectionInfo($0)
            receiver(info)
        }

        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

extension NetworkConnectionInfo {
    init(_ path: NWPath) {
        self.init(
            reachability: NetworkConnectionInfo.Reachability(path.status),
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
    }
}

extension NetworkConnectionInfo.Reachability {
    init(_ status: NWPath.Status) {
        switch status {
        case .satisfied: self = .yes
        case .requiresConnection: self = .maybe
        case .unsatisfied: self = .no
        @unknown default: self = .maybe
        }
    }
}

extension NetworkConnectionInfo.Interface {
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
