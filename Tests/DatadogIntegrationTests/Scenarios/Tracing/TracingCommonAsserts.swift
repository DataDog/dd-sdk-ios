/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?batch_time=1589969230153`
            let pathRegex = #"^(.*)(/ui-tests-client-token\?batch_time=)([0-9]+)$"#
            XCTAssertTrue(
                request.path.matches(regex: pathRegex),
                """
                Request path doesn't match the expected regex.
                ✉️ path: \(request.path)
                🧪 expected regex:  \(pathRegex)
                """,
                file: file,
                line: line
            )
            let expectedHeader = "Content-Type: text/plain;charset=UTF-8"
            XCTAssertTrue(
                request.httpHeaders.contains(expectedHeader),
                """
                Request doesn't contain expected header.
                ✉️ request headers: \(request.httpHeaders.joined(separator: "\n"))
                🧪 expected header:  \(expectedHeader)
                """,
                file: file,
                line: line
            )
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
            XCTAssertEqual(try matcher.meta.tracerVersion().split(separator: ".").count, 3, file: file, line: line)
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

extension String {
    /// Tracing feature uses hexadecimal representation of trace and span IDs, while Logging uses decimals.
    /// This helper converts hexadecimal string to decimal string for comparison.
    var hexadecimalNumberToDecimal: String {
        return "\(UInt64(self, radix: 16)!)"
    }
}

extension SpanMatcher {
    class func from(requests: [HTTPServerMock.Request]) throws -> [SpanMatcher] {
        return try requests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }
    }
}
