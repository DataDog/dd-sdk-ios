/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `SpanEnvelope` allows encoding multiple spans sharing the same `traceID` to a single payload.
internal struct SpanEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spans = "spans"
        case environment = "env"
    }

    let spans: [Span]
    let environment: String

    /// The initializer to encode single `Span` within an envelope.
    init(span: Span, environment: String) {
        self.init(spans: [span], environment: environment)
    }

    /// This initializer is `private` now, as we don't yet
    /// support batching multiple spans sharing the same `traceID` within a single payload.
    private init(spans: [Span], environment: String) {
        self.spans = spans
        self.environment = environment
    }
}

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
    /// Coding keys for permanent `Span` attributes.
    enum StaticCodingKeys: String, CodingKey {
        // MARK: - Attributes

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
        case samplingPriority = "metrics._sampling_priority_v1"

        // MARK: - Meta

        case source = "meta._dd.source"
        case applicationVersion = "meta.application.version"
        case tracerVersion = "meta.tracer.version"

        case userId = "meta.usr.id"
        case userName = "meta.usr.name"
        case userEmail = "meta.usr.email"

        case networkReachability = "meta.network.client.reachability"
        case networkAvailableInterfaces = "meta.network.client.available_interfaces"
        case networkConnectionSupportsIPv4 = "meta.network.client.supports_ipv4"
        case networkConnectionSupportsIPv6 = "meta.network.client.supports_ipv6"
        case networkConnectionIsExpensive = "meta.network.client.is_expensive"
        case networkConnectionIsConstrained = "meta.network.client.is_constrained"

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

        try encodeMetrics(span, to: &container)
        try encodeMeta(span, to: &container)
    }

    /// Encodes `metrics.*` attributes
    private func encodeMetrics(_ span: Span, to container: inout KeyedEncodingContainer<StaticCodingKeys>) throws {
        // NOTE: RUMM-299 only numeric values are supported for `metrics.*` attributes
        if span.parentID == nil {
            try container.encode(1, forKey: .isRootSpan)
        }
        try container.encode(1, forKey: .samplingPriority)

        // TODO: RUMM-402 Encode custom metrics from `DDSpan` (coding key: `metrics.*`)
    }

    /// Encodes `meta.*` attributes
    private func encodeMeta(_ span: Span, to container: inout KeyedEncodingContainer<StaticCodingKeys>) throws {
        // NOTE: RUMM-299 only string values are supported for `meta.*` attributes
        try container.encode("mobile", forKey: .source)
        try container.encode(span.tracerVersion, forKey: .tracerVersion)
        try container.encode(span.applicationVersion, forKey: .applicationVersion)

        try span.userInfo.id.ifNotNil { try container.encode($0, forKey: .userId) }
        try span.userInfo.name.ifNotNil { try container.encode($0, forKey: .userName) }
        try span.userInfo.email.ifNotNil { try container.encode($0, forKey: .userEmail) }

        if let networkConnectionInfo = span.networkConnectionInfo {
            try container.encode(networkConnectionInfo.reachability, forKey: .networkReachability)
            if let availableInterfaces = networkConnectionInfo.availableInterfaces, availableInterfaces.count > 0 {
                // Because only string values are supported for `meta.*` attributes, available network interfaces
                // are represented as names concatenated using `+` symbol, i.e.: "wifi+cellular", "cellular"
                let availableInterfacesString = availableInterfaces.map { $0.rawValue }.joined(separator: "+")
                try container.encode(availableInterfacesString, forKey: .networkAvailableInterfaces)
            }
            if let supportsIPv4 = networkConnectionInfo.supportsIPv4 {
                try container.encode(supportsIPv4 ? "1" : "0", forKey: .networkConnectionSupportsIPv4)
            }
            if let supportsIPv6 = networkConnectionInfo.supportsIPv6 {
                try container.encode(supportsIPv6 ? "1" : "0", forKey: .networkConnectionSupportsIPv6)
            }
            if let isExpensive = networkConnectionInfo.isExpensive {
                try container.encode(isExpensive ? "1" : "0", forKey: .networkConnectionIsExpensive)
            }
            if let isConstrained = networkConnectionInfo.isConstrained {
                try container.encode(isConstrained ? "1" : "0", forKey: .networkConnectionIsConstrained)
            }
        }

        if let carrierInfo = span.mobileCarrierInfo {
            if let carrierName = carrierInfo.carrierName {
                try container.encode(carrierName, forKey: .mobileNetworkCarrierName)
            }
            if let carrierISOCountryCode = carrierInfo.carrierISOCountryCode {
                try container.encode(carrierISOCountryCode, forKey: .mobileNetworkCarrierISOCountryCode)
            }
            try container.encode(carrierInfo.radioAccessTechnology, forKey: .mobileNetworkCarrierRadioTechnology)
            try container.encode(carrierInfo.carrierAllowsVOIP ? "1" : "0", forKey: .mobileNetworkCarrierAllowsVoIP)
        }

        // TODO: RUMM-403 Encode custom meta from `DDSpan` (as String values!), including `span.tags` (coding key: `meta.*`)
    }
}
