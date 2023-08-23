/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Network connection details.
public struct NetworkConnectionInfo: Codable, Equatable, PassthroughAnyCodable {
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

    public init(
        reachability: Reachability,
        availableInterfaces: [Interface]?,
        supportsIPv4: Bool?,
        supportsIPv6: Bool?,
        isExpensive: Bool?,
        isConstrained: Bool?
    ) {
        self.reachability = reachability
        self.availableInterfaces = availableInterfaces
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

extension NetworkConnectionInfo {
    /// Returns an unknown network info with `.maybe` reachability.
    static var unknown: NetworkConnectionInfo {
        .init(
            reachability: .maybe,
            availableInterfaces: nil,
            supportsIPv4: nil,
            supportsIPv6: nil,
            isExpensive: nil,
            isConstrained: nil
        )
    }
}
