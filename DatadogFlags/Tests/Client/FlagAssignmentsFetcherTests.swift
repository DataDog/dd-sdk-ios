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
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

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
        XCTAssertEqual(flagAssignments, .mockAny())
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

    func testNetworkFailuresDoNotReportSDKDefects() {
        let errors: [NSError] = [
            NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ENOMEM),
                userInfo: [NSLocalizedDescriptionKey: "Cannot allocate memory"]
            ),
            URLError(.notConnectedToInternet) as NSError,
            URLError(.timedOut) as NSError,
            URLError(.cancelled) as NSError,
            URLError(.badServerResponse) as NSError,
        ]
        let logger = CoreLoggerMock()
        let dd = DD.mockWith(logger: logger)
        defer { dd.reset() }

        for expectedError in errors {
            // Given
            logger.reset()
            let scope = FeatureScopeMock()
            var fetchCount = 0
            var results: [Result<[String: FlagAssignment], FlagsError>] = []
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                featureScope: scope,
                fetch: { _, completion in
                    fetchCount += 1
                    completion(.failure(expectedError))
                }
            )

            // When
            fetcher.flagAssignments(for: .mockAny()) { results.append($0) }

            // Then
            XCTAssertEqual(fetchCount, 1)
            XCTAssertEqual(results.count, 1)
            guard case .failure(.networkError(let error)) = results.first else {
                return XCTFail("Expected the original network failure")
            }
            XCTAssertEqual(error as NSError, expectedError)
            XCTAssertNil(scope.telemetryMock.messages.firstError())
            XCTAssertTrue(logger.errorLogs.isEmpty)
            XCTAssertEqual(logger.warnMessages, ["Failed to fetch flag assignments from the server."])
        }
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
        XCTAssertNotNil(featureScope.telemetryMock.messages.firstError())
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
