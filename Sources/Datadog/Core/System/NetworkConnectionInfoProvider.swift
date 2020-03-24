/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Network

/// Network reachability details.
internal struct NetworkConnectionInfo {
    /// Tells if network is reachable.
    enum Reachability: String, Encodable, CaseIterable {
        /// The network is reachable.
        case yes
        /// The network might be reachable after trying.
        case maybe
        /// The network is not reachable.
        case no // swiftlint:disable:this identifier_name
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

internal protocol NetworkConnectionInfoProviderType {
    var current: NetworkConnectionInfo { get }
}

internal class NetworkConnectionInfoProvider: NetworkConnectionInfoProviderType {
    private let queue: DispatchQueue?
    private let fetchBlock: () -> NetworkConnectionInfo
    private let cancelBlock: (() -> Void)?

    var current: NetworkConnectionInfo {
        return fetchBlock()
    }

    convenience init() {
        if #available(iOS 12, *) {
            self.init(NWPathMonitor())
        } else {
            self.init(iOS11PathMonitor())
        }
    }

    @available(iOS 12, *)
    init(_ provider: NWPathMonitor) {
        let queue = DispatchQueue(
            label: "com.datadoghq.network-connection-info",
            qos: .utility,
            attributes: [],
            target: DispatchQueue.global(qos: .utility)
        )
        self.queue = queue
        self.fetchBlock = {
            return provider.current
        }
        self.cancelBlock = { [weak provider] in
            provider?.cancel()
        }
        provider.start(queue: queue)
    }

    init(_ provider: iOS11PathMonitor) {
        self.queue = nil
        self.fetchBlock = {
            return provider.current
        }
        self.cancelBlock = nil
    }

    deinit {
        cancelBlock?()
    }
}
