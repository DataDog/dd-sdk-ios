/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `SpanEnvelope` allows encoding multiple spans sharing the same `traceID` to a single payload.
internal struct SpanEventsEnvelope: Encodable {
    enum CodingKeys: String, CodingKey {
        case spans = "spans"
        case environment = "env"
    }

    let spans: [SpanEvent]
    let environment: String

    /// The initializer to encode single `Span` within an envelope.
    init(span: SpanEvent, environment: String) {
        self.init(spans: [span], environment: environment)
    }

    /// This initializer is `private` now, as we don't yet
    /// support batching multiple spans sharing the same `traceID` within a single payload.
    private init(spans: [SpanEvent], environment: String) {
        self.spans = spans
        self.environment = environment
    }
}

/// Individual span event sent do Datadog.
public struct SpanEvent: Encodable {
    /// The id of the trace this span belongs to.
    internal let traceID: TraceID
    /// The unique id of this span.
    internal let spanID: SpanID
    /// The id this span's parent or `nil` if this is the root span.
    internal let parentID: SpanID?
    /// The operation name set for this span.
    public var operationName: String
    /// The service name configured for tracer.
    public let serviceName: String
    /// The resource name associated with this span.
    /// For automatically tracked spans, it is set to the request URL.
    /// For all other spands it fallbacks to `operationName`.
    public var resource: String
    /// The start time of this span.
    public let startTime: Date
    /// The span duration.
    public let duration: TimeInterval
    /// Indicates if there was an error information collected for this span.
    public let isError: Bool
    /// Name of the component sourcing the span, for iOS SDK it is set to `ios`.
    internal let source: String
    /// The origin for the Span, it is used to label the spans used created under testing
    internal let origin: String?
    /// The sampling rate for the span (between 0 and 1)
    internal let samplingRate: Float
    /// If the span is kept according to sampling rules
    internal let isKept: Bool

    // MARK: - Meta

    /// The SDK version.
    public let tracerVersion: String
    /// The client application version.
    public let applicationVersion: String
    /// The network connection information from the moment the span was completed.
    public let networkConnectionInfo: NetworkConnectionInfo?
    /// The mobile carrier information from the moment the span was completed.
    public let mobileCarrierInfo: CarrierInfo?
    /// Device information.
    public let device: Device
    /// Operating System information.
    public let os: OperatingSystem

    public struct UserInfo {
        /// User ID, if any.
        public let id: String?
        /// Name representing the user, if any.
        public let name: String?
        /// User email, if any.
        public let email: String?
        /// User custom attributes, if any.
        public var extraInfo: [String: String]
    }

    public struct AccountInfo {
        /// Account ID
        public let id: String
        /// Name representing the account, if any.
        public let name: String?
        /// Account custom attributes, if any.
        public var extraInfo: [String: String]
    }

    /// Custom user information configured globally for the SDK.
    public var userInfo: UserInfo

    /// Custom account information configured globally for the SDK.
    public var accountInfo: AccountInfo?

    /// Tags associated with the span.
    public var tags: [String: String]

    public func encode(to encoder: Encoder) throws {
        let sanitizedSpan = SpanSanitizer().sanitize(span: self)
        try SpanEventEncoder().encode(sanitizedSpan, to: encoder)
    }
}

/// Encodes `SpanEvent` to given encoder.
internal struct SpanEventEncoder {
    /// Coding keys for permanent `SpanEvent` attributes.
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
        case device = "meta.device" // Should be under `meta` to comply with the span schema
        case os = "meta.os" // Should be under `meta` to comply with the span schema

        // MARK: - Metrics

        case isRootSpan = "metrics._top_level"
        case samplingPriority = "metrics._sampling_priority_v1"
        case samplingRate = "metrics._dd.agent_psr"

        // MARK: - Meta

        case source = "meta._dd.source"
        case applicationVersion = "meta.version"
        case tracerVersion = "meta.tracer.version"

        case origin = "meta._dd.origin"

        case ptid = "meta._dd.p.tid"

        case userId = "meta.usr.id"
        case userName = "meta.usr.name"
        case userEmail = "meta.usr.email"

        case accountId = "meta.account.id"
        case accountName = "meta.account.name"

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

    /// Coding keys for dynamic `SpanEvent` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(_ span: SpanEvent, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(span.traceID.idLoHex, forKey: .traceID)
        try container.encode(String(span.spanID, representation: .hexadecimal), forKey: .spanID)

        let parentSpanID = span.parentID ?? SpanID.invalid // 0 is a reserved ID for a root span (ref: DDTracer.java#L600)
        try container.encode(String(parentSpanID, representation: .hexadecimal), forKey: .parentID)

        try container.encode(span.operationName, forKey: .operationName)
        try container.encode(span.serviceName, forKey: .serviceName)
        try container.encode(span.resource, forKey: .resource)
        try container.encode("custom", forKey: .type)

        try container.encode(span.startTime.timeIntervalSince1970.dd.toNanoseconds, forKey: .startTime)
        try container.encode(span.duration.dd.toNanoseconds, forKey: .duration)

        let isError = span.isError ? 1 : 0
        try container.encode(isError, forKey: .isError)

        try encodeDefaultMetrics(span, to: &container)
        try encodeDefaultMeta(span, to: &container)

        var customAttributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try encodeCustomMeta(span, to: &customAttributesContainer)
    }

    /// Encodes default `metrics.*` attributes
    private func encodeDefaultMetrics(_ span: SpanEvent, to container: inout KeyedEncodingContainer<StaticCodingKeys>) throws {
        // NOTE: RUMM-299 only numeric values are supported for `metrics.*` attributes
        if span.parentID == nil {
            try container.encode(1, forKey: .isRootSpan)
            try container.encode(span.samplingRate, forKey: .samplingRate)
            try container.encode((span.isKept ? 1 : 0), forKey: .samplingPriority)
        }
    }

    /// Encodes default `meta.*` attributes
    private func encodeDefaultMeta(_ span: SpanEvent, to container: inout KeyedEncodingContainer<StaticCodingKeys>) throws {
        // NOTE: RUM-9494 only basic types (boolean, string, number) are supported for `meta.*` attributes
        try container.encode(span.source, forKey: .source)
        try container.encode(span.tracerVersion, forKey: .tracerVersion)
        try container.encode(span.applicationVersion, forKey: .applicationVersion)

        try span.origin.dd.ifNotNil { try container.encode($0, forKey: .origin) }

        try container.encode(span.device, forKey: .device)
        try container.encode(span.os, forKey: .os)

        try span.userInfo.id.dd.ifNotNil { try container.encode($0, forKey: .userId) }
        try span.userInfo.name.dd.ifNotNil { try container.encode($0, forKey: .userName) }
        try span.userInfo.email.dd.ifNotNil { try container.encode($0, forKey: .userEmail) }

        if let accountInfo = span.accountInfo {
            try container.encode(accountInfo.id, forKey: .accountId)
            try accountInfo.name.dd.ifNotNil { try container.encode($0, forKey: .accountName) }
        }

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

        try container.encode(span.traceID.idHiHex, forKey: .ptid)
    }

    /// Encodes `meta.*` attributes coming from user
    private func encodeCustomMeta(_ span: SpanEvent, to container: inout KeyedEncodingContainer<DynamicCodingKey>) throws {
        // NOTE: RUM-9494 only basic types (boolean, string, number) are supported for `meta.*` attributes
        try span.userInfo.extraInfo.forEach {
            let metaKey = "meta.usr.\($0.key)"
            try container.encode($0.value, forKey: DynamicCodingKey(metaKey))
        }

        try span.accountInfo?.extraInfo.forEach {
            let metaKey = "meta.account.\($0.key)"
            try container.encode($0.value, forKey: DynamicCodingKey(metaKey))
        }
        try span.tags.forEach {
            let metaKey = "meta.\($0.key)"
            try container.encode($0.value, forKey: DynamicCodingKey(metaKey))
        }
    }
}
