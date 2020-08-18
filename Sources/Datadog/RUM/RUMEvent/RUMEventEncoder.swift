/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Encodable` representation of RUM event.
internal struct RUMEvent<DM: RUMDataModel>: Encodable {
    /// The actual RUM event model created by `RUMMonitor`
    let model: DM

    let networkConnectionInfo: NetworkConnectionInfo?
    let mobileCarrierInfo: CarrierInfo?

    /// Custom attributes set by the user
    let attributes: [String: Encodable]

    func encode(to encoder: Encoder) throws {
        try RUMEventEncoder().encode(self, to: encoder)
    }
}

/// Encodes `RUMEvent` to given encoder.
internal struct RUMEventEncoder {
    /// Coding keys for permanent `RUMEvent` attributes.
    enum StaticCodingKeys: String, CodingKey {
        // MARK: - Network connection info

        case networkReachability = "network.client.reachability"
        case networkAvailableInterfaces = "network.client.available_interfaces"
        case networkConnectionSupportsIPv4 = "network.client.supports_ipv4"
        case networkConnectionSupportsIPv6 = "network.client.supports_ipv6"
        case networkConnectionIsExpensive = "network.client.is_expensive"
        case networkConnectionIsConstrained = "network.client.is_constrained"

        // MARK: - Mobile carrier info

        case mobileNetworkCarrierName = "network.client.sim_carrier.name"
        case mobileNetworkCarrierISOCountryCode = "network.client.sim_carrier.iso_country"
        case mobileNetworkCarrierRadioTechnology = "network.client.sim_carrier.technology"
        case mobileNetworkCarrierAllowsVoIP = "network.client.sim_carrier.allows_voip"
    }

    /// Coding keys for dynamic `RUMEvent` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
}

    func encode<DM: RUMDataModel>(_ event: RUMEvent<DM>, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)

        // Encode network info
        try container.encodeIfPresent(event.networkConnectionInfo?.reachability, forKey: .networkReachability)
        try container.encodeIfPresent(event.networkConnectionInfo?.availableInterfaces, forKey: .networkAvailableInterfaces)
        try container.encodeIfPresent(event.networkConnectionInfo?.supportsIPv4, forKey: .networkConnectionSupportsIPv4)
        try container.encodeIfPresent(event.networkConnectionInfo?.supportsIPv6, forKey: .networkConnectionSupportsIPv6)
        try container.encodeIfPresent(event.networkConnectionInfo?.isExpensive, forKey: .networkConnectionIsExpensive)
        try container.encodeIfPresent(event.networkConnectionInfo?.isConstrained, forKey: .networkConnectionIsConstrained)

        // Encode mobile carrier info
        try container.encodeIfPresent(event.mobileCarrierInfo?.carrierName, forKey: .mobileNetworkCarrierName)
        try container.encodeIfPresent(event.mobileCarrierInfo?.carrierISOCountryCode, forKey: .mobileNetworkCarrierISOCountryCode)
        try container.encodeIfPresent(event.mobileCarrierInfo?.radioAccessTechnology, forKey: .mobileNetworkCarrierRadioTechnology)
        try container.encodeIfPresent(event.mobileCarrierInfo?.carrierAllowsVOIP, forKey: .mobileNetworkCarrierAllowsVoIP)

        // Encode attributes
        var attributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try event.attributes.forEach { attributeName, attributeValue in
            try attributesContainer.encode(EncodableValue(attributeValue), forKey: DynamicCodingKey(attributeName))
        }

        // Encode `RUMDataModel`
        try event.model.encode(to: encoder)
    }
}
