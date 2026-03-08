/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import Network

/// Produces `NetworkConnectionInfo` updates via `AsyncStream` backed by `NWPathMonitor`.
///
/// On iOS 17+ / tvOS 17+ the native `AsyncSequence` conformance of `NWPathMonitor` is
/// used directly. On earlier OS versions the stream is built from `pathUpdateHandler`.
internal struct NWPathMonitorSource: ContextValueSource {
    let initialValue: NetworkConnectionInfo?
    let values: AsyncStream<NetworkConnectionInfo?>

    init(monitor: NWPathMonitor = .init()) {
        self.initialValue = NetworkConnectionInfo(monitor.currentPath)

        if #available(iOS 17, tvOS 17, macOS 14, watchOS 10, *) {
            self.values = Self.nativeAsyncStream(monitor: monitor)
        } else {
            self.values = Self.callbackAsyncStream(monitor: monitor)
        }
    }

    @available(iOS 17, tvOS 17, macOS 14, watchOS 10, *)
    private static func nativeAsyncStream(monitor: NWPathMonitor) -> AsyncStream<NetworkConnectionInfo?> {
        AsyncStream { continuation in
            let task = Task {
                for await path in monitor {
                    continuation.yield(NetworkConnectionInfo(path))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                monitor.cancel()
            }

            monitor.start(queue: .global(qos: .utility))
        }
    }

    private static func callbackAsyncStream(monitor: NWPathMonitor) -> AsyncStream<NetworkConnectionInfo?> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(NetworkConnectionInfo(path))
            }

            let queue = DispatchQueue(
                label: "com.datadoghq.nw-path-monitor-source",
                target: .global(qos: .utility)
            )
            monitor.start(queue: queue)

            continuation.onTermination = { _ in
                monitor.cancel()
            }
        }
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
            isConstrained: path.isConstrained
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
