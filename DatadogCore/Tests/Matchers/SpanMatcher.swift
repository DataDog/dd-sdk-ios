/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Implemented by types allowed to represent span attribute `.*` value in JSON.
protocol AllowedSpanAttributeValue {}
/// Implemented by types allowed to represent span attribute `_dd.*` value in JSON.
protocol AllowedSpanDdValue {}
/// Implemented by types allowed to represent span `metrics.*` value in JSON.
protocol AllowedSpanMetricValue {}
/// Implemented by types allowed to represent span `meta.*` value in JSON.
protocol AllowedSpanMetaValue {}

// All JSON-convertible values are allowed for `span.*`.
extension String: AllowedSpanAttributeValue {}
extension UInt64: AllowedSpanAttributeValue {}
extension Int: AllowedSpanAttributeValue {}

// Only numeric values are allowed for `span._dd.*`.
extension Double: AllowedSpanDdValue {}

// Only numeric values are allowed for `span.metrics.*`.
extension Int: AllowedSpanMetricValue {}

// Only string values are allowed for `span.meta.*`.
extension String: AllowedSpanMetaValue {}

/// Provides set of assertions for single `SpanEvent` JSON object and collection of `[SpanEvent]`.
/// Note: this file is individually referenced by integration tests target, so no dependency on other source files should be introduced.
internal class SpanMatcher {
    // MARK: - Initialization

    /// Returns "Span A" matcher for data representing string:
    ///
    ///     { "spans": [ { /* Span A json */ } ] }
    ///
    /// **NOTE:** If `spans` array contains more than one span JSON, only the first one will be described by the matcher.
    /// Current implementation of `SpanEnvelope` doesn't allow for more than one span in the array.
    ///
    /// **See Also**: `SpanEnvelope`
    ///
    class func fromJSONObjectData(_ data: Data) throws -> SpanMatcher {
        return try SpanMatcher(from: try data.toJSONObject())
    }

    /// Returns array containing Span A, Span B and Span C matchers for data representing string:
    ///
    ///     ```
    ///     { "spans": [ { /* Span A json */ } ] }
    ///     { "spans": [ { /* Span B json */ } ] }
    ///     { "spans": [ { /* Span C json */ } ] }
    ///     ```
    ///
    /// **See Also** `SpanMatcher.fromJSONObjectData(_:)`
    ///
    class func fromNewlineSeparatedJSONObjectsData(_ data: Data) throws -> [SpanMatcher] {
        let separator = "\n".data(using: .utf8)![0]
        let spansData = data.split(separator: separator).map { Data($0) }
        return try spansData.map { spanJSONData in try SpanMatcher.fromJSONObjectData(spanJSONData) }
    }

    /// Matcher for the whole `SpanEnvelope`.
    private let envelope: JSONDataMatcher
    /// Matcher for the first `Span` from envelope.
    private let span: JSONDataMatcher

    private init(from jsonObject: [String: Any]) throws {
        self.envelope = JSONDataMatcher(from: jsonObject)
        self.span = JSONDataMatcher(from: try self.envelope.value(forKeyPath: "spans.@firstObject"))
    }

    // MARK: - Full match

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        try self.envelope.assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    // MARK: - Attributes matching

    func traceID() throws -> TraceID? {
        let idLoStr: String = try attribute(forKeyPath: "trace_id")
        let idLo = UInt64(idLoStr, radix: 16) ?? UInt64(0)

        let idHiStr: String = try meta.tid()
        let idHi = UInt64(idHiStr, radix: 16) ?? UInt64(0)

        return .init(idHi: idHi, idLo: idLo)
    }

    func spanID() throws -> SpanID? {
        let spanId: String = try attribute(forKeyPath: "span_id")
        return .init(spanId, representation: .hexadecimal)
    }

    func parentSpanID() throws -> SpanID? {
        let spanId: String = try attribute(forKeyPath: "parent_id")
        return .init(spanId, representation: .hexadecimal)
    }

    func operationName()    throws -> String { try attribute(forKeyPath: "name") }
    func serviceName()      throws -> String { try attribute(forKeyPath: "service") }
    func resource()         throws -> String { try attribute(forKeyPath: "resource") }
    func type()             throws -> String { try attribute(forKeyPath: "type") }
    func startTime()        throws -> UInt64 { try attribute(forKeyPath: "start") }
    func duration()         throws -> UInt64 { try attribute(forKeyPath: "duration") }
    func isError()          throws -> Int { try attribute(forKeyPath: "error") }
    func environment()      throws -> String { try envelope.value(forKeyPath: "env") }

    // MARK: - _dd matching

    var dd: Dd { Dd(matcher: self) }

    struct Dd {
        fileprivate let matcher: SpanMatcher

        func samplingRate() throws -> Double { try matcher.dd(forKeyPath: "_dd.agent_psr") }
    }

    // MARK: - Metrics matching

    var metrics: Metrics { Metrics(matcher: self) }

    struct Metrics {
        fileprivate let matcher: SpanMatcher

        func isRootSpan()       throws -> Int { try matcher.metric(forKeyPath: "metrics._top_level") }
        func samplingPriority() throws -> Int { try matcher.metric(forKeyPath: "metrics._sampling_priority_v1") }
    }

    // MARK: - Meta matching

    var meta: Meta { Meta(matcher: self) }

    struct Meta {
        fileprivate let matcher: SpanMatcher

        func tid()                  throws -> String { try matcher.meta(forKeyPath: "meta._dd.p.tid") }
        func source()               throws -> String { try matcher.meta(forKeyPath: "meta._dd.source") }
        func applicationVersion()   throws -> String { try matcher.meta(forKeyPath: "meta.version") }
        func tracerVersion()        throws -> String { try matcher.meta(forKeyPath: "meta.tracer.version") }

        func userID()               throws -> String { try matcher.meta(forKeyPath: "meta.usr.id") }
        func userName()             throws -> String { try matcher.meta(forKeyPath: "meta.usr.name") }
        func userEmail()            throws -> String { try matcher.meta(forKeyPath: "meta.usr.email") }

        func networkReachability()            throws -> String { try matcher.meta(forKeyPath: "meta.network.client.reachability") }
        func networkAvailableInterfaces()     throws -> String { try matcher.meta(forKeyPath: "meta.network.client.available_interfaces") }
        func networkConnectionSupportsIPv4()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.supports_ipv4") }
        func networkConnectionSupportsIPv6()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.supports_ipv6") }
        func networkConnectionIsExpensive()   throws -> String { try matcher.meta(forKeyPath: "meta.network.client.is_expensive") }
        func networkConnectionIsConstrained() throws -> String { try matcher.meta(forKeyPath: "meta.network.client.is_constrained") }

        func mobileNetworkCarrierName()            throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.name") }
        func mobileNetworkCarrierISOCountryCode()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.iso_country") }
        func mobileNetworkCarrierRadioTechnology() throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.technology") }
        func mobileNetworkCarrierAllowsVoIP()      throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.allows_voip") }

        func custom(keyPath: String) throws -> String { try matcher.meta(forKeyPath: keyPath) }
    }

    /// Allowed values for `meta.network.client.available_interfaces` attribute.
    static let allowedNetworkAvailableInterfacesValues: Set<String> = ["wifi", "wiredEthernet", "cellular", "loopback", "other"]
    /// Allowed values for `meta.network.client.reachability` attribute.
    static let allowedNetworkReachabilityValues: Set<String> = ["yes", "no", "maybe"]

    // MARK: - Private

    private func attribute<T: AllowedSpanAttributeValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(!keyPath.hasPrefix("metrics."), "use specialized `metric(forKeyPath:)`")
        precondition(!keyPath.hasPrefix("meta."), "use specialized `meta(forKeyPath:)`")
        return try span.value(forKeyPath: keyPath)
    }

    private func dd<T: AllowedSpanDdValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(keyPath.hasPrefix("_dd."))
        return try span.value(forKeyPath: keyPath)
    }

    private func metric<T: AllowedSpanMetricValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(keyPath.hasPrefix("metrics."))
        return try span.value(forKeyPath: keyPath)
    }

    private func meta<T: AllowedSpanMetaValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(keyPath.hasPrefix("meta."))
        return try span.value(forKeyPath: keyPath)
    }
}
