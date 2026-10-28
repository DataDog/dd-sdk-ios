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

    func testOptOutTimestampNormalizesProlepticGregorianDates() throws {
        let cases = [
            ("0000-01-01T00:00:00Z", "0000-01-01T00:00:00Z"),
            ("0000-02-29T00:00:00Z", "0000-02-29T00:00:00Z"),
            ("1582-10-10T00:00:00Z", "1582-10-10T00:00:00Z"),
            ("2000-03-01T00:15:00+01:00", "2000-02-29T23:15:00Z"),
            ("1900-03-01T00:15:00+01:00", "1900-02-28T23:15:00Z"),
            ("2026-01-01T00:00:00+23:59", "2025-12-31T00:01:00Z"),
            ("2025-12-31T23:59:00-23:59", "2026-01-01T23:58:00Z"),
            ("2026-10-19t08:00:00.1234567899-04:00", "2026-10-19T12:00:00.123456789Z"),
            ("2026-10-19T12:00:00.1200000000z", "2026-10-19T12:00:00.12Z"),
            ("9999-12-31T23:59:59.999999999Z", "9999-12-31T23:59:59.999999999Z")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(try ExperimentationOptOut.normalizedTimestamp(input), expected, input)
        }
    }

    func testOptOutTimestampRejectsInvalidGregorianDatesAndUTCOverflow() {
        for input in [
            "0000-01-01T00:00:00+00:01",
            "9999-12-31T23:59:59-00:01",
            "1500-02-29T00:00:00Z",
            "1900-02-29T00:00:00Z",
            "2026-04-31T00:00:00Z",
            "2026-01-01T00:00:60Z",
            "2026-01-01T00:00:00+24:00",
            "2026-01-01T00:00:00+00:60"
        ] {
            XCTAssertThrowsError(try ExperimentationOptOut.normalizedTimestamp(input), input)
        }
    }

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
            let completed = expectation(description: "acknowledgement")
            fetcher.flagAssignments(
                for: .mockAny(),
                experimentationOptOut: .futureExperimentsOnly(cutoff: "2026-10-21T12:00:00.123456789Z")
            ) {
                if case .success = $0 { succeeded = true }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 2)
            XCTAssertEqual(succeeded, expected, options)
        }
    }

    func testOptedOutRequestRequiresBooleanAcknowledgement() {
        let cases: [(String, Bool, Bool)] = [
            ("", true, false),
            (#", "evaluation_options": {"experimentation_opt_out": false}"#, true, false),
            (#", "evaluation_options": {"experimentation_opt_out": "true"}"#, true, false),
            (#", "evaluation_options": {"experimentation_opt_out": null}"#, true, false),
            (#", "evaluation_options": {"experimentation_opt_out": true}"#, false, true),
            (#", "evaluation_options": {"experimentation_opt_out_mode": true, "experimentation_opt_out": true}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": "future_experiments_only", "experimentation_opt_out": true}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": "unknown"}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": ""}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": null}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": true}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": 42}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": {}}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": []}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": "immediate"}"#, false, false),
            (#", "evaluation_options": {"experimentation_opt_out_mode": "future_experiments_only"}"#, false, false)
        ]
        for (acknowledgement, acceptsUnfiltered, acceptsImmediate) in cases {
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
                let completed = expectation(description: "acknowledgement")
                fetcher.flagAssignments(for: .mockAny(), experimentationOptOut: optedOut ? .immediate : nil) {
                    if case .success = $0 { succeeded = true }
                    completed.fulfill()
                }
                wait(for: [completed], timeout: 2)
                XCTAssertEqual(succeeded, optedOut ? acceptsImmediate : acceptsUnfiltered, acknowledgement)
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
        waitForExpectations(timeout: 1)
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
        waitForExpectations(timeout: 1)
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
        waitForExpectations(timeout: 1)
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
        waitForExpectations(timeout: 1)
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

    func testFlagAssignments_whenCompletionIsBlocked_doesNotBlockAnotherRequest() {
        let results: [Result<Data, Error>] = [
            .success(.mockAnyFlagAssignmentsResponse()),
            .success(Data()),
            .failure(URLError(.notConnectedToInternet))
        ]

        for result in results {
            // Given
            let contextQueue = DispatchQueue(label: "com.datadoghq.flags-tests-context")
            let contextQueueKey = DispatchSpecificKey<Void>()
            contextQueue.setSpecific(key: contextQueueKey, value: ())
            let featureScope = FeatureScopeMock()
            let queue = DispatchQueue(label: "com.datadoghq.flags-tests-assignment-fetch")
            let queueKey = DispatchSpecificKey<Void>()
            queue.setSpecific(key: queueKey, value: ())
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                featureScope: featureScope,
                assignmentFetchQueue: queue,
                fetch: { _, completion in
                    XCTAssertNil(DispatchQueue.getSpecific(key: contextQueueKey))
                    XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
                    completion(result)
                }
            )
            let firstCompletionStarted = expectation(description: "first completion started")
            let firstCompletionFinished = expectation(description: "first completion finished")
            let secondCompleted = expectation(description: "second request completed")
            let releaseCompletion = DispatchSemaphore(value: 0)
            defer {
                releaseCompletion.signal()
                wait(for: [firstCompletionFinished], timeout: 1)
            }

            // FeatureScopeMock supplies its context synchronously on the calling queue.
            contextQueue.async {
                fetcher.flagAssignments(for: .mockAny()) { _ in
                    XCTAssertNil(DispatchQueue.getSpecific(key: contextQueueKey))
                    XCTAssertNil(DispatchQueue.getSpecific(key: queueKey))
                    firstCompletionStarted.fulfill()
                    releaseCompletion.wait()
                    firstCompletionFinished.fulfill()
                }
            }
            wait(for: [firstCompletionStarted], timeout: 1)

            // When
            contextQueue.async {
                fetcher.flagAssignments(for: .mockAny()) { _ in
                    XCTAssertNil(DispatchQueue.getSpecific(key: contextQueueKey))
                    XCTAssertNil(DispatchQueue.getSpecific(key: queueKey))
                    secondCompleted.fulfill()
                }
            }

            // Then
            wait(for: [secondCompleted], timeout: 1)
        }
    }
}
