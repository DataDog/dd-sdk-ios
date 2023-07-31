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

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309`
            XCTAssertFalse(
                request.path.contains("?"),
                """
                Request path must contain no query parameters.
                ✉️ path: \(request.path)
                """,
                file: file,
                line: line
            )

            let expectedHeadersRegexes = [
                #"^Content-Type: text/plain;charset=UTF-8$"#,
                #"^User-Agent: .*/\d+[.\d]* CFNetwork \([a-zA-Z ]+; iOS/[0-9.]+\)$"#, // e.g. "User-Agent: Example/1.0 CFNetwork (iPhone; iOS/14.5)"
                #"^DD-API-KEY: ui-tests-client-token$"#,
                #"^DD-EVP-ORIGIN: ios$"#,
                #"^DD-EVP-ORIGIN-VERSION: \#(semverPattern)$"#, // e.g. "DD-EVP-ORIGIN-VERSION: 1.7.0-beta.2"
                #"^DD-REQUEST-ID: [0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"# // e.g. "DD-REQUEST-ID: 524A2616-D2AA-4FE5-BBD9-898D173BE658"
            ]
            expectedHeadersRegexes.forEach { expectedHeaderRegex in
                XCTAssertTrue(
                    request.httpHeaders.contains { $0.matches(regex: expectedHeaderRegex) },
                    """
                    Request doesn't contain header matching expected regex.
                    ✉️ request headers: \(request.httpHeaders.joined(separator: "\n"))
                    🧪 expected regex: '\(expectedHeaderRegex)'
                    """,
                    file: file,
                    line: line
                )
            }
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
