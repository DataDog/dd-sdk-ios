/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import HTTPServerMock

/// A set of common assertions for all Tracing tests.
protocol TracingCommonAsserts {
    func assertTracing(requests: [HTTPServerMock.Request], file: StaticString, line: UInt)

    /// Asserts that given Spans are started after and finished before given dates.
    func assertThat(
        spans: [SpanMatcher],
        startAfter startTimeInNanoseconds: UInt64,
        andFinishBefore endTimeInNanoseconds: UInt64,
        file: StaticString,
        line: UInt
    ) throws

    /// Asserts common metadata values for Spans (service name, environment, network info, carrier info, ...).
    func assertCommonMetadata(in spans: [SpanMatcher], file: StaticString, line: UInt) throws
}

extension TracingCommonAsserts {
    func assertTracing(
        requests: [HTTPServerMock.Request],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        requests.forEach { request in
            XCTAssertEqual(request.httpMethod, "POST")

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309?ddtags=retry_count:1`
            XCTAssertFalse(request.path.isEmpty)
            XCTAssertNotNil(request.queryItems)
            XCTAssertEqual(request.queryItems!.count, 1)

            let ddtags = request.queryItems?.ddtags()
            XCTAssertNotNil(ddtags)
            XCTAssertEqual(ddtags?.count, 1)
            XCTAssertEqual(ddtags!["retry_count"], "1")

            XCTAssertEqual(request.httpHeaders["Content-Type"], "text/plain;charset=UTF-8", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["User-Agent"]?.matches(regex: userAgentRegex), true, file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-API-KEY"], "ui-tests-client-token", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-EVP-ORIGIN"], "ios", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-EVP-ORIGIN-VERSION"]?.matches(regex: semverRegex), true, file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-REQUEST-ID"]?.matches(regex: ddRequestIDRegex), true, file: file, line: line)
        }
    }

    func assertThat(
        spans: [SpanMatcher],
        startAfter startTimeInNanoseconds: UInt64,
        andFinishBefore endTimeInNanoseconds: UInt64,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        try spans.forEach { matcher in
            XCTAssertGreaterThan(try matcher.startTime(), startTimeInNanoseconds, file: file, line: line)
            XCTAssertLessThan(try matcher.startTime(), endTimeInNanoseconds, file: file, line: line)
        }
    }

    func assertCommonMetadata(in spans: [SpanMatcher], file: StaticString = #file, line: UInt = #line) throws {
        try spans.forEach { matcher in
            XCTAssertEqual(try matcher.serviceName(), "ui-tests-service-name", file: file, line: line)
            XCTAssertEqual(try matcher.type(), "custom", file: file, line: line)
            XCTAssertEqual(try matcher.environment(), "integration", file: file, line: line)

            XCTAssertEqual(try matcher.meta.source(), "ios", file: file, line: line)
            XCTAssertTrue(try matcher.meta.tracerVersion().matches(regex: semverRegex), file: file, line: line)
            XCTAssertEqual(try matcher.meta.applicationVersion(), "1.0", file: file, line: line)

            XCTAssertTrue(
                SpanMatcher.allowedNetworkReachabilityValues.contains(try matcher.meta.networkReachability()),
                file: file,
                line: line
            )

            if #available(iOS 12.0, *) { // The `iOS11NetworkConnectionInfoProvider` doesn't provide those info
                try matcher.meta.networkAvailableInterfaces().split(separator: "+").forEach { interface in
                    XCTAssertTrue(
                        SpanMatcher.allowedNetworkAvailableInterfacesValues.contains(String(interface)),
                        file: file,
                        line: line
                    )
                }

                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv4()), file: file, line: line)
                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv6()), file: file, line: line)
                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsExpensive()), file: file, line: line)
            }

            if #available(iOS 13.0, *) {
                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsConstrained()), file: file, line: line)
            }

            #if targetEnvironment(simulator)
                // When running on iOS Simulator
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierName(), file: file, line: line)
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode(), file: file, line: line)
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology(), file: file, line: line)
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP(), file: file, line: line)
            #else
                // When running on physical device with SIM card registered
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierName(), file: file, line: line)
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode(), file: file, line: line)
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology(), file: file, line: line)
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP(), file: file, line: line)
            #endif
        }
    }
}

extension SpanMatcher {
    class func from(requests: [HTTPServerMock.Request]) throws -> [SpanMatcher] {
        return try requests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }
    }
}
