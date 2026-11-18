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

    func testFetcherAppliesOptOutAdmission() throws {
        for accepted in [false, true] {
            let cutoff = accepted ? "2026-10-21T12:00:00Z" : "2026-10-22T12:00:00Z"
            let bytes = Data("""
                {"data":{"attributes":{"flags":{},"evaluation_options":{
                    "experimentation_opt_out_mode":"future_experiments_only",
                    "dd_experimentation_opt_out_at":"\(cutoff)"
                }}}}
                """.utf8)
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: featureScope,
                fetch: { _, complete in complete(.success((bytes, .mockAny()))) }
            )
            let completed = expectation(description: "admission \(accepted)")
            fetcher.flagAssignments(for: .mockAny(), experimentationOptOut: .futureExperimentsOnly(cutoff: try OptOutInstant(rfc3339: "2026-10-21T12:00:00Z"))) { result in
                switch result {
                case .success: XCTAssertTrue(accepted)
                case .failure(.invalidResponse): XCTAssertFalse(accepted)
                default: XCTFail("Unexpected result \(result)")
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
        }
    }

    func testFlagAssignments() throws {
        // Given
        featureScope.contextMock = .mockWith(site: .us3)
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
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
            flagSelection: nil,
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
            var results: [Result<FlagAssignmentsResponse, FlagsError>] = []
            let completed = expectation(description: "completed for \(expectedError)")
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                fetch: { _, completion in
                    fetchCount += 1
                    completion(.failure(expectedError))
                }
            )

            // When
            fetcher.flagAssignments(for: .mockAny()) { result in
                results.append(result)
                completed.fulfill()
            }

            // Then
            wait(for: [completed], timeout: 1)
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
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((Data(), .mockAny())))
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
        let defect = featureScope.telemetryMock.messages.firstError()?.message ?? ""
        XCTAssertTrue(defect.hasPrefix("Failed to decode FlagAssignmentsResponse from flag assignments response"), defect)
    }

    func testFlagAssignmentsCustomEndpoint() {
        // Given
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: ["X-Custom-Header": "custom-value"],
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
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

    func testFlagAssignmentsDefaultEndpointDoesNotSendCustomHeaders() {
        // Given
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value", "dd-client-token": "overridden"],
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
            }
        )

        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(capturedRequest?.url?.host, "preview.ff-cdn.datadoghq.com")
        XCTAssertNil(capturedRequest?.allHTTPHeaderFields?["X-Custom-Header"])
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "dd-client-token"), featureScope.contextMock.clientToken)
    }

    func testFlagAssignmentsSendsFlagSelection() throws {
        // Given
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: ["checkout.*"]),
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
            }
        )
        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        let flagSelection = try XCTUnwrap(attributes["flag_selection"] as? [String: [String]])
        XCTAssertEqual(flagSelection, ["tags": ["mobile"], "key_patterns": ["checkout.*"]])
    }

    func testFlagAssignmentsSendsFlagSelectionToCustomEndpoint() throws {
        // Given
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
            }
        )
        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(capturedRequest?.url, customEndpoint)
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        let flagSelection = try XCTUnwrap(attributes["flag_selection"] as? [String: [String]])
        XCTAssertEqual(flagSelection, ["tags": ["mobile"], "key_patterns": []])
    }

    func testFlagAssignmentsReportsIgnoredFlagSelection() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": "too_many_values"]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), response)))
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
        XCTAssertEqual(try XCTUnwrap(capturedResult?.get()).flags, .mockAny())
        XCTAssertEqual(
            dd.logger.errorMessages,
            ["`Flags.Configuration.flagSelection` was ignored by the server (too_many_values). Loaded the full flag configuration."]
        )
        let telemetry = featureScope.telemetryMock.messages
        XCTAssertEqual(telemetry.count, 1)
        let debug = try XCTUnwrap(telemetry.firstDebug())
        XCTAssertEqual(debug.message, "Flag selection ignored")
        XCTAssertEqual(debug.attributes?.count, 1)
        XCTAssertEqual(debug.attributes?["reason"] as? String, "too_many_values")
    }

    func testFlagAssignmentsWithIgnoredHeaderAndAnUndecodableBodyDoesNotReportIgnoredFlagSelection() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": "too_many_values"]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((Data("not json".utf8), response)))
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
        guard case .failure(.invalidResponse) = capturedResult else {
            return XCTFail("Expected .invalidResponse, got \(String(describing: capturedResult))")
        }
        XCTAssertEqual(dd.logger.errorMessages, [])
        XCTAssertNil(featureScope.telemetryMock.messages.firstDebug())
    }

    func testFlagAssignmentsReportsEachIgnoredReasonWithItsOwnTelemetryID() throws {
        // When
        let tooManyValues = try XCTUnwrap(reportIgnoredFlagSelection(headerValue: "too_many_values").telemetry.firstDebug())
        let tagLoadFailed = try XCTUnwrap(reportIgnoredFlagSelection(headerValue: "tag_load_failed").telemetry.firstDebug())

        // Then
        // Telemetry keeps one event per id in a session, so equal ids would drop the second reason.
        XCTAssertNotEqual(tooManyValues.id, tagLoadFailed.id)
    }

    func testFlagAssignmentsReportsKnownIgnoredReasons() throws {
        for reason in ["malformed_selection", "too_many_values", "invalid_key_pattern", "invalid_tag", "tag_load_failed"] {
            // When
            let reported = try reportIgnoredFlagSelection(headerValue: reason)

            // Then
            XCTAssertEqual(
                reported.errors,
                ["`Flags.Configuration.flagSelection` was ignored by the server (\(reason)). Loaded the full flag configuration."]
            )
            XCTAssertEqual(reported.telemetry.count, 1, reason)
            let debug = try XCTUnwrap(reported.telemetry.firstDebug())
            XCTAssertEqual(debug.message, "Flag selection ignored")
            XCTAssertEqual(debug.attributes?.count, 1)
            XCTAssertEqual(debug.attributes?["reason"] as? String, reason)
        }
    }

    func testFlagAssignmentsReportsOtherIgnoredValuesAsUnknown() throws {
        // A proxy behind `customFlagsEndpoint` controls this header, so its content must not reach logs or telemetry.
        let values = [
            "Some Future-Reason",
            "Too_Many_Values",
            "TOO_MANY_VALUES",
            " too_many_values",
            "too_many_values\u{0007}",
            "tag_load_failed\u{001B}[0m",
            "too_many_valu\u{00E9}s",
            "invalid_tag" + String(repeating: "x", count: 22),
            String(repeating: "a", count: 10_000),
            "token=secret",
        ]

        for value in values {
            // When
            let reported = try reportIgnoredFlagSelection(headerValue: value)

            // Then
            XCTAssertEqual(
                reported.errors,
                ["`Flags.Configuration.flagSelection` was ignored by the server (unknown). Loaded the full flag configuration."],
                value
            )
            XCTAssertEqual(reported.telemetry.count, 1, value)
            let debug = try XCTUnwrap(reported.telemetry.firstDebug())
            XCTAssertEqual(debug.attributes?.count, 1, value)
            XCTAssertEqual(debug.attributes?["reason"] as? String, "unknown", value)
        }
    }

    func testFlagAssignmentsReportsIgnoredFlagSelectionForEveryResponseWithALowercaseHeaderName() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["dd-flag-selection-ignored": "too_many_values"]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), response)))
            }
        )

        // When
        for _ in 0..<2 {
            let completed = expectation(description: "completed")
            fetcher.flagAssignments(for: .mockAny()) { _ in
                completed.fulfill()
            }
            waitForExpectations(timeout: 1)
        }

        // Then
        let expectedError = "`Flags.Configuration.flagSelection` was ignored by the server (too_many_values). Loaded the full flag configuration."
        XCTAssertEqual(dd.logger.errorMessages, [expectedError, expectedError])
        XCTAssertEqual(featureScope.telemetryMock.messages.count, 2)
    }

    func testFlagAssignmentsWithoutFlagSelectionIgnoresIgnoredHeader() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": "too_many_values"]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), response)))
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
        XCTAssertEqual(try XCTUnwrap(capturedResult?.get()).flags, .mockAny())
        XCTAssertTrue(dd.logger.errorMessages.isEmpty)
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
    }

    func testFlagAssignmentsWithEmptyIgnoredHeaderLogsNothing() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": ""]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), response)))
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
        XCTAssertEqual(try XCTUnwrap(capturedResult?.get()).flags, .mockAny())
        XCTAssertTrue(dd.logger.errorMessages.isEmpty)
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
    }

    func testFlagAssignmentsWithoutIgnoredHeaderLogsNothing() {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
            }
        )
        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertTrue(dd.logger.errorMessages.isEmpty)
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
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
        let results: [Result<(Data, HTTPURLResponse), Error>] = [
            .success((.mockAnyFlagAssignmentsResponse(), .mockAny())),
            .success((Data(), .mockAny())),
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
                flagSelection: nil,
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

    /// Fetches once with a selection and the given `DD-Flag-Selection-Ignored` value, and returns what the SDK reported.
    private func reportIgnoredFlagSelection(headerValue: String) throws -> (errors: [String], telemetry: [TelemetryMessage]) {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let scope = FeatureScopeMock()
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": headerValue]
            )
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: scope,
            fetch: { _, completion in
                completion(.success((.mockAnyFlagAssignmentsResponse(), response)))
            }
        )
        let completed = expectation(description: "completed")
        var capturedResult: Result<FlagAssignmentsResponse, FlagsError>?
        fetcher.flagAssignments(for: .mockAny()) { result in
            capturedResult = result
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        // The full configuration is still used.
        XCTAssertEqual(try XCTUnwrap(capturedResult?.get()).flags, .mockAny())
        return (dd.logger.errorMessages, scope.telemetryMock.messages)
    }
}
