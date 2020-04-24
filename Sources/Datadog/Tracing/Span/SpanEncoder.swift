/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Encodable` representation of span.
internal struct Span: Encodable {
    let traceID: TracingUUID
    let spanID: TracingUUID
    let parentID: TracingUUID?
    let operationName: String
    let serviceName: String
    let resource: String
    let startTime: Date
    let duration: TimeInterval
    let isError: Bool

    // MARK: - Meta

    let tracerVersion: String
    let applicationVersion: String
    let networkConnectionInfo: NetworkConnectionInfo?
    let mobileCarrierInfo: CarrierInfo?
    let userInfo: UserInfo

    func encode(to encoder: Encoder) throws {
        try SpanEncoder().encode(self, to: encoder)
    }
}

/// Encodes `Span` to given encoder.
internal struct SpanEncoder {
    /// Coding keys for permanent `Log` attributes.
    enum StaticCodingKeys: String, CodingKey {
        case traceID = "trace_id"
        case spanID = "span_id"
        case parentID = "parent_id"
        case operationName = "name"
        case serviceName = "service"
        case resource
        case type
        case startTime = "start"
        case duration
        case isError = "error"

        // MARK: - Metrics

        case isRootSpan = "metrics._top_level"

        // MARK: - Meta

        case source = "meta._dd.source"

        // MARK: - Application info

        case applicationVersion = "meta.application.version"

        // MARK: - Tracer info

        case tracerVersion = "meta.tracer.version"

        // MARK: - User info

        case userId = "meta.usr.id"
        case userName = "meta.usr.name"
        case userEmail = "meta.usr.email"

        // MARK: - Network connection info

        case networkReachability = "meta.network.client.reachability"
        case networkAvailableInterfaces = "meta.network.client.available_interfaces"
        case networkConnectionSupportsIPv4 = "meta.network.client.supports_ipv4"
        case networkConnectionSupportsIPv6 = "meta.network.client.supports_ipv6"
        case networkConnectionIsExpensive = "meta.network.client.is_expensive"
        case networkConnectionIsConstrained = "meta.network.client.is_constrained"

        // MARK: - Mobile carrier info

        case mobileNetworkCarrierName = "meta.network.client.sim_carrier.name"
        case mobileNetworkCarrierISOCountryCode = "meta.network.client.sim_carrier.iso_country"
        case mobileNetworkCarrierRadioTechnology = "meta.network.client.sim_carrier.technology"
        case mobileNetworkCarrierAllowsVoIP = "meta.network.client.sim_carrier.allows_voip"
    }

    func encode(_ span: Span, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(span.traceID.toHexadecimalString, forKey: .traceID)
        try container.encode(span.spanID.toHexadecimalString, forKey: .spanID)

        let parentSpanID = span.parentID ?? TracingUUID(rawValue: 0) // 0 is a reserved ID for a root span (ref: DDTracer.java#L600)
        try container.encode(parentSpanID.toHexadecimalString, forKey: .parentID)

        try container.encode(span.operationName, forKey: .operationName)
        try container.encode(span.serviceName, forKey: .serviceName)
        try container.encode(span.resource, forKey: .resource)
        try container.encode("custom", forKey: .type)

        try container.encode(span.startTime.timeIntervalSince1970.toNanoseconds, forKey: .startTime)
        try container.encode(span.duration.toNanoseconds, forKey: .duration)

        let isError = span.isError ? 1 : 0
        try container.encode(isError, forKey: .isError)

        // Encode `metrics.*`
        if span.parentID == nil {
            try container.encode(1, forKey: .isRootSpan)
        }

        // TODO: RUMM-402 Encode custom metrics from `DDSpan` (coding key: `metrics.*`)

        // Encode `meta.*`
        try container.encode("mobile", forKey: .source)
        try container.encode(span.tracerVersion, forKey: .tracerVersion)
        try container.encode(span.applicationVersion, forKey: .applicationVersion)

        // TODO: RUMM-299 Consider sharing `userInfo` encoding between `SpanEncoder` and `LogEncoder` when tests are ready
        try span.userInfo.id.ifNotNil { try container.encode($0, forKey: .userId) }
        try span.userInfo.name.ifNotNil { try container.encode($0, forKey: .userName) }
        try span.userInfo.email.ifNotNil { try container.encode($0, forKey: .userEmail) }

        // TODO: RUMM-299 Consider sharing `networkConnectionInfo` encoding between `SpanEncoder` and `LogEncoder` when tests are ready
        if let networkConnectionInfo = span.networkConnectionInfo {
            try container.encode(networkConnectionInfo.reachability, forKey: .networkReachability)
            try container.encode(networkConnectionInfo.availableInterfaces, forKey: .networkAvailableInterfaces)
            try container.encode(networkConnectionInfo.supportsIPv4, forKey: .networkConnectionSupportsIPv4)
            try container.encode(networkConnectionInfo.supportsIPv6, forKey: .networkConnectionSupportsIPv6)
            try container.encode(networkConnectionInfo.isExpensive, forKey: .networkConnectionIsExpensive)
            try networkConnectionInfo.isConstrained.ifNotNil {
                try container.encode($0, forKey: .networkConnectionIsConstrained)
            }
        }

        // TODO: RUMM-299 Consider sharing `mobileCarrierInfo` encoding between `SpanEncoder` and `LogEncoder` when tests are ready
        if let carrierInfo = span.mobileCarrierInfo {
            try carrierInfo.carrierName.ifNotNil {
                try container.encode($0, forKey: .mobileNetworkCarrierName)
            }
            try carrierInfo.carrierISOCountryCode.ifNotNil {
                try container.encode($0, forKey: .mobileNetworkCarrierISOCountryCode)
            }
            try container.encode(carrierInfo.radioAccessTechnology, forKey: .mobileNetworkCarrierRadioTechnology)
            try container.encode(carrierInfo.carrierAllowsVOIP, forKey: .mobileNetworkCarrierAllowsVoIP)
        }

        // TODO: RUMM-403 Encode custom meta (including `span.tags`) from `DDSpan` (coding key: `meta.*`)
    }
}
