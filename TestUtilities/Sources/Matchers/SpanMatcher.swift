/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Implemented by types allowed to represent span attribute `.*` value in JSON.
protocol AllowedSpanAttributeValue {}
/// Implemented by types allowed to represent span `metrics.*` value in JSON.
protocol AllowedSpanMetricValue {}
/// Implemented by types allowed to represent span `meta.*` value in JSON.
protocol AllowedSpanMetaValue {}

// All JSON-convertible values are allowed for `span.*`.
extension String: AllowedSpanAttributeValue {}
extension UInt64: AllowedSpanAttributeValue {}
extension Int: AllowedSpanAttributeValue {}

// Only numeric values are allowed for `span.metrics.*`.
extension Int: AllowedSpanMetricValue {}
extension Double: AllowedSpanMetricValue {}

// Only string values are allowed for `span.meta.*`.
extension String: AllowedSpanMetaValue {}

/// Provides set of assertions for single `SpanEvent` JSON object and collection of `[SpanEvent]`.
/// Note: this file is individually referenced by integration tests target, so no dependency on other source files should be introduced.
public class SpanMatcher {
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
    public class func fromNewlineSeparatedJSONObjectsData(_ data: Data) throws -> [SpanMatcher] {
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

    public func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        try self.envelope.assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    // MARK: - Attributes matching

    public func traceID() throws -> TraceID? {
        let idLoStr: String = try attribute(forKeyPath: "trace_id")
        let idLo = UInt64(idLoStr, radix: 16) ?? UInt64(0)

        let idHiStr: String = try meta.tid()
        let idHi = UInt64(idHiStr, radix: 16) ?? UInt64(0)

        return .init(idHi: idHi, idLo: idLo)
    }

    public func spanID() throws -> SpanID? {
        let spanId: String = try attribute(forKeyPath: "span_id")
        return .init(spanId, representation: .hexadecimal)
    }

    public func parentSpanID() throws -> SpanID? {
        let spanId: String = try attribute(forKeyPath: "parent_id")
        return .init(spanId, representation: .hexadecimal)
    }

    public func operationName()    throws -> String { try attribute(forKeyPath: "name") }
    public  func serviceName()      throws -> String { try attribute(forKeyPath: "service") }
    public func resource()         throws -> String { try attribute(forKeyPath: "resource") }
    public func type()             throws -> String { try attribute(forKeyPath: "type") }
    public func startTime()        throws -> UInt64 { try attribute(forKeyPath: "start") }
    public func duration()         throws -> UInt64 { try attribute(forKeyPath: "duration") }
    public func isError()          throws -> Int { try attribute(forKeyPath: "error") }
    public func environment()      throws -> String { try envelope.value(forKeyPath: "env") }

    // MARK: - Metrics matching

    public var metrics: Metrics { Metrics(matcher: self) }

    public struct Metrics {
        fileprivate let matcher: SpanMatcher

        public func isRootSpan()       throws -> Int { try matcher.metric(forKeyPath: "metrics._top_level") }
        public func samplingPriority() throws -> Int { try matcher.metric(forKeyPath: "metrics._sampling_priority_v1") }
        public func samplingRate() throws -> Double { try matcher.metric(forKeyPath: "metrics._dd.agent_psr") }
    }

    // MARK: - Meta matching

    public var meta: Meta { Meta(matcher: self) }

    public struct Meta {
        fileprivate let matcher: SpanMatcher

        public func tid()                  throws -> String { try matcher.meta(forKeyPath: "meta._dd.p.tid") }
        public func source()               throws -> String { try matcher.meta(forKeyPath: "meta._dd.source") }
        public func applicationVersion()   throws -> String { try matcher.meta(forKeyPath: "meta.version") }
        public func tracerVersion()        throws -> String { try matcher.meta(forKeyPath: "meta.tracer.version") }

        public func userID()               throws -> String { try matcher.meta(forKeyPath: "meta.usr.id") }
        public func userName()             throws -> String { try matcher.meta(forKeyPath: "meta.usr.name") }
        public func userEmail()            throws -> String { try matcher.meta(forKeyPath: "meta.usr.email") }

        public func networkReachability()            throws -> String { try matcher.meta(forKeyPath: "meta.network.client.reachability") }
        public func networkAvailableInterfaces()     throws -> String { try matcher.meta(forKeyPath: "meta.network.client.available_interfaces") }
        public func networkConnectionSupportsIPv4()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.supports_ipv4") }
        public func networkConnectionSupportsIPv6()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.supports_ipv6") }
        public func networkConnectionIsExpensive()   throws -> String { try matcher.meta(forKeyPath: "meta.network.client.is_expensive") }
        public func networkConnectionIsConstrained() throws -> String { try matcher.meta(forKeyPath: "meta.network.client.is_constrained") }

        public func mobileNetworkCarrierName()            throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.name") }
        public func mobileNetworkCarrierISOCountryCode()  throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.iso_country") }
        public func mobileNetworkCarrierRadioTechnology() throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.technology") }
        public func mobileNetworkCarrierAllowsVoIP()      throws -> String { try matcher.meta(forKeyPath: "meta.network.client.sim_carrier.allows_voip") }

        public func custom(keyPath: String) throws -> String { try matcher.meta(forKeyPath: keyPath) }
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

    private func metric<T: AllowedSpanMetricValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(keyPath.hasPrefix("metrics."))
        return try span.value(forKeyPath: keyPath)
    }

    private func meta<T: AllowedSpanMetaValue & Equatable>(forKeyPath keyPath: String) throws -> T {
        precondition(keyPath.hasPrefix("meta."))
        return try span.value(forKeyPath: keyPath)
    }
}
