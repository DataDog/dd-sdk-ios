/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class FlagAssignmentsFetcherTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testFutureOptOutRequiresTypedModeAndExactCutoffAcknowledgement() throws {
        let cases: [(String, Bool)] = [
            (#"{}"#, false),
            (#"{"experimentation_opt_out": true}"#, false),
            (#"{"experimentation_opt_out_mode": true, "dd_experimentation_opt_out_at": "2026-10-21T12:00:00.123456789Z"}"#, false),
            (#"{"experimentation_opt_out_mode": "future_experiments_only", "dd_experimentation_opt_out_at": 123}"#, false),
            (#"{"experimentation_opt_out_mode": "future_experiments_only", "dd_experimentation_opt_out_at": "2026-10-21T12:00:00.123456788Z"}"#, false),
            (#"{"experimentation_opt_out_mode": "future_experiments_only", "dd_experimentation_opt_out_at": "2026-10-21T14:00:00.123456789+02:00"}"#, true)
        ]
        for (options, expected) in cases {
            let bytes = Data("{\"data\":{\"attributes\":{\"flags\":{},\"evaluation_options\":\(options)}}}".utf8)
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                featureScope: featureScope,
                fetch: { _, complete in complete(.success(bytes)) }
            )
            var succeeded = false
            fetcher.flagAssignments(
                for: .mockAny(),
                experimentationOptOut: .futureExperimentsOnly(cutoff: "2026-10-21T12:00:00.123456789Z")
            ) {
                if case .success = $0 { succeeded = true }
            }
            XCTAssertEqual(succeeded, expected, options)
        }
    }

    func testOptedOutRequestRequiresBooleanAcknowledgement() {
        for acknowledgement in [
            "", #", "evaluation_options": {"experimentation_opt_out": false}"#,
            #", "evaluation_options": {"experimentation_opt_out": "true"}"#,
            #", "evaluation_options": {"experimentation_opt_out": null}"#,
            #", "evaluation_options": {"experimentation_opt_out": true}"#,
            #", "evaluation_options": {"experimentation_opt_out_mode": true, "experimentation_opt_out": true}"#,
            #", "evaluation_options": {"experimentation_opt_out_mode": "future_experiments_only", "experimentation_opt_out": true}"#
        ] {
            for optedOut in [false, true] {
                let bytes = Data(#"{"data":{"attributes":{"flags":{}"#.utf8)
                    + Data(acknowledgement.utf8) + Data("}}}".utf8)
                let fetcher = FlagAssignmentsFetcher(
                    customEndpoint: nil,
                    customHeaders: nil,
                    featureScope: featureScope,
                    fetch: { _, complete in complete(.success(bytes)) }
                )
                var succeeded = false
                fetcher.flagAssignments(for: .mockAny(), experimentationOptOut: optedOut ? .immediate : nil) {
                    if case .success = $0 { succeeded = true }
                }
                XCTAssertEqual(succeeded, !optedOut || (acknowledgement.hasSuffix("true}") && !acknowledgement.contains("experimentation_opt_out_mode")))
            }
        }
    }

    func testFlagAssignments() throws {
        // Given
        featureScope.contextMock = .mockWith(site: .us3)
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(.mockAnyFlagAssignmentsResponse()))
            }
        )
        let completed = expectation(description: "completed")
        var capturedResult: Result<FlagAssignmentsResponse, FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://preview.ff-cdn.us3.datadoghq.com/precompute-assignments"
        )
        let flagAssignments = try XCTUnwrap(capturedResult?.get())
        XCTAssertEqual(flagAssignments.flags, .mockAny())
    }

    func testFlagAssignmentsNetworkError() {
        // Given
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.failure(URLError(.notConnectedToInternet)))
            }
        )
        let completedWithNetworkError = expectation(description: "completedWithNetworkError")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(.networkError(let error)) = result,
               let urlError = error as? URLError,
               urlError.code == .notConnectedToInternet {
                completedWithNetworkError.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 0)
    }

    func testFlagAssignmentsInvalidResponse() {
        // Given
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success(Data()))
            }
        )
        let completedWithInvalidResponseError = expectation(description: "completedWithInvalidResponseError")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(.invalidResponse) = result {
                completedWithInvalidResponseError.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 0)
    }

    func testFlagAssignmentsCustomEndpoint() {
        // Given
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(.mockAnyFlagAssignmentsResponse()))
            }
        )

        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(capturedRequest?.url, customEndpoint)
        XCTAssertEqual(capturedRequest?.allHTTPHeaderFields?["X-Custom-Header"], "custom-value")
    }

    func testFlagsEndpointForAllSites() {
        let flagsEndpoints: [(DatadogSite, String)] = [
            (.us1, "https://preview.ff-cdn.datadoghq.com"),
            (.us3, "https://preview.ff-cdn.us3.datadoghq.com"),
            (.us5, "https://preview.ff-cdn.us5.datadoghq.com"),
            (.eu1, "https://preview.ff-cdn.datadoghq.eu"),
            (.ap1, "https://preview.ff-cdn.ap1.datadoghq.com"),
            (.ap2, "https://preview.ff-cdn.ap2.datadoghq.com"),
            (.uk1, "https://preview.ff-cdn.uk1.datadoghq.com"),
        ]

        for (site, expectedEndpoint) in flagsEndpoints {
            XCTAssertEqual(site.flagsEndpoint().absoluteString, expectedEndpoint)
        }
    }
}
