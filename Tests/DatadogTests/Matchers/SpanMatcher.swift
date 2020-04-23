/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides set of assertions for single `Span` JSON object or collection of `[Span]`.
/// Note: this file is individually referenced by integration tests project, so no dependency on other source files should be introduced.
internal class SpanMatcher: JSONDataMatcher {
    /// Span JSON keys.
    struct JSONKey {
        static let traceID = "trace_id"
        static let spanID = "span_id"
        static let parentID = "parent_id"
        static let operationName = "name"
        static let serviceName = "service"
        static let resource = "resource"
        static let type = "type"
        static let startTime = "start"
        static let duration = "duration"
        static let isError = "error"

        // MARK: - Metrics

        static let isRootSpan = "metrics._top_level"

        // MARK: - Meta

        static let source = "meta._dd.source"

        // MARK: - Application info

        static let applicationVersion = "meta.application.version"

        // MARK: - Tracer info

        static let tracerVersion = "meta.tracer.version"

        // MARK: - User info

        static let userId = "meta.usr.id"
        static let userName = "meta.usr.name"
        static let userEmail = "meta.usr.email"

        // MARK: - Network connection info

        static let networkReachability = "meta.network.client.reachability"
        static let networkAvailableInterfaces = "meta.network.client.available_interfaces"
        static let networkConnectionSupportsIPv4 = "meta.network.client.supports_ipv4"
        static let networkConnectionSupportsIPv6 = "meta.network.client.supports_ipv6"
        static let networkConnectionIsExpensive = "meta.network.client.is_expensive"
        static let networkConnectionIsConstrained = "meta.network.client.is_constrained"

        // MARK: - Mobile carrier info

        static let mobileNetworkCarrierName = "meta.network.client.sim_carrier.name"
        static let mobileNetworkCarrierISOCountryCode = "meta.network.client.sim_carrier.iso_country"
        static let mobileNetworkCarrierRadioTechnology = "meta.network.client.sim_carrier.technology"
        static let mobileNetworkCarrierAllowsVoIP = "meta.network.client.sim_carrier.allows_voip"
    }

    /// Allowed values for `network.client.available_interfaces` attribute.
    static let allowedNetworkAvailableInterfacesValues: Set<String> = ["wifi", "wiredEthernet", "cellular", "loopback", "other"]
    /// Allowed values for `network.client.reachability` attribute.
    static let allowedNetworkReachabilityValues: Set<String> = ["yes", "no", "maybe"]

    // MARK: - Initialization

    class func fromJSONObjectData(_ data: Data, file: StaticString = #file, line: UInt = #line) throws -> SpanMatcher {
        return try super.fromJSONObjectData(data, file: file, line: line)
    }

    class func fromArrayOfJSONObjectsData(_ data: Data, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        return try super.fromArrayOfJSONObjectsData(data, file: file, line: line)
    }

    // MARK: Partial matches

    func assertTraceID(equals traceIDString: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.traceID, equals: traceIDString, file: file, line: line)
    }

    func assertSpanID(equals spanIDString: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.spanID, equals: spanIDString, file: file, line: line)
    }

    func assertParentSpanID(equals parentSpanIDString: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.parentID, equals: parentSpanIDString, file: file, line: line)
    }

    func assertOperationName(equals operationName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.operationName, equals: operationName, file: file, line: line)
    }

    func assertServiceName(equals serviceName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.serviceName, equals: serviceName, file: file, line: line)
    }

    func assertResource(equals resource: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.resource, equals: resource, file: file, line: line)
    }

    func assertStartTime(equals timeIntervalSince1970InNanoseconds: UInt64, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.startTime, equals: timeIntervalSince1970InNanoseconds, file: file, line: line)
    }

    func assertDuration(equals timeIntervalInNanoseconds: UInt64, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.duration, equals: timeIntervalInNanoseconds, file: file, line: line)
    }

    func assertUserInfo(equals userInfo: (id: String?, name: String?, email: String?)?, file: StaticString = #file, line: UInt = #line) {
        if let id = userInfo?.id { // swiftlint:disable:this identifier_name
            assertValue(forKey: JSONKey.userId, equals: id, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userId, file: file, line: line)
        }
        if let name = userInfo?.name {
            assertValue(forKey: JSONKey.userName, equals: name, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userName, file: file, line: line)
        }
        if let email = userInfo?.email {
            assertValue(forKey: JSONKey.userEmail, equals: email, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userEmail, file: file, line: line)
        }
    }
}
