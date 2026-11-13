/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Network
import Security
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class FlagAssignmentsFetcherTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func test302HTTPSRedirectsAreFollowedOnlyWithoutAnAssignmentToken() throws {
        try assertHTTPSRedirectBehavior(statusCode: 302)
    }

    func test303HTTPSRedirectsAreFollowedOnlyWithoutAnAssignmentToken() throws {
        try assertHTTPSRedirectBehavior(statusCode: 303)
    }

    func test307HTTPSRedirectsAreFollowedOnlyWithoutAnAssignmentToken() throws {
        try assertHTTPSRedirectBehavior(statusCode: 307)
    }

    private func assertHTTPSRedirectBehavior(statusCode: Int) throws {
        let identity = try AssignmentRedirectTLSIdentity.shared.get()
        for destinationHost in ["localhost", "127.0.0.1"] {
            let destination = try AssignmentRedirectHTTPSOrigin(identity: identity.identity, body: .mockAnyFlagAssignmentsResponse())
            defer { destination.stop() }
            let source = try AssignmentRedirectHTTPSOrigin(
                identity: identity.identity,
                statusCode: statusCode,
                location: destination.url(host: destinationHost)
            )
            defer { source.stop() }
            let session = makeRedirectTestSession(certificate: identity.certificate)
            defer { session.invalidateAndCancel() }
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: source.url(host: "localhost"),
                customHeaders: nil,
                flagSelection: nil,
                featureScope: featureScope,
                fetch: session.fetch
            )

            // Reuse the same session and fetcher to cover token removal and later replacement.
            let tokens: [String?] = [nil, "dummy-token-A", nil, "dummy-token-B"]
            for (index, token) in tokens.enumerated() {
                let destinationRequestsBefore = destination.requests.count
                let completed = expectation(description: "HTTPS \(statusCode), destination \(destinationHost), request \(index)")
                var capturedResult: Result<FlagAssignmentsResponse, FlagsError>?
                var attributes: [String: AnyValue] = [:]
                attributes[AssignmentAuthorization.contextAttribute] = token.map { .string($0) }

                fetcher.flagAssignments(for: .init(targetingKey: "subject", attributes: attributes)) { result in
                    capturedResult = result
                    completed.fulfill()
                }

                wait(for: [completed], timeout: 10)
                let result = try XCTUnwrap(capturedResult)
                let sourceRequest = try XCTUnwrap(source.requests.last)
                XCTAssertEqual(source.requests.count, index + 1)
                XCTAssertEqual(sourceRequest.method, "POST")
                XCTAssertEqual(sourceRequest.headers["dd-assignment-token"], token)
                XCTAssertFalse(String(decoding: sourceRequest.body, as: UTF8.self).contains("dd_assignment_token"))
                XCTAssertFalse(String(decoding: sourceRequest.body, as: UTF8.self).contains("dummy-token"))

                if token != nil {
                    assertRedirectDownloadFailure(result)
                    XCTAssertEqual(destination.requests.count, destinationRequestsBefore, "A protected redirect must send no destination request")
                } else {
                    XCTAssertEqual(try result.get().flags, FlagAssignmentsResponse.mockAny().flags)
                    XCTAssertEqual(destination.requests.count, destinationRequestsBefore + 1)
                    let redirectedRequest = try XCTUnwrap(destination.requests.last)
                    XCTAssertEqual(redirectedRequest.method, statusCode == 307 ? "POST" : "GET")
                    XCTAssertNil(redirectedRequest.headers["dd-assignment-token"])
                    if statusCode == 307 {
                        XCTAssertEqual(redirectedRequest.body, sourceRequest.body)
                    }
                }
            }
        }
    }

    func testRefusedHTTPSRedirectsUseSameSubjectFallbackAndIsolateOtherSubjects() throws {
        let identity = try AssignmentRedirectTLSIdentity.shared.get()
        for statusCode in [302, 303, 307] {
            let destination = try AssignmentRedirectHTTPSOrigin(identity: identity.identity, body: .mockAnyFlagAssignmentsResponse())
            defer { destination.stop() }
            let source = try AssignmentRedirectHTTPSOrigin(identity: identity.identity, body: .mockAnyFlagAssignmentsResponse())
            defer { source.stop() }
            let session = makeRedirectTestSession(certificate: identity.certificate)
            defer { session.invalidateAndCancel() }
            let scope = FeatureScopeMock()
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: source.url(host: "localhost"),
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                fetch: session.fetch
            )
            let repository = FlagsRepository(
                clientName: "https-redirect",
                flagAssignmentsFetcher: fetcher,
                dateProvider: DateProviderMock(),
                featureScope: scope,
                flagSelection: nil,
                initializationTimeout: nil
            )
            scope.dataStore.flush()
            defer { repository.flush() }
            let installed = expectation(description: "initial assignments")
            var initialResult: Result<Void, FlagsError>?
            repository.setEvaluationContext(.init(targetingKey: "subject-a")) { result in
                initialResult = result
                installed.fulfill()
            }
            wait(for: [installed], timeout: 10)
            try XCTUnwrap(initialResult).get()
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertNotNil(repository.flagAssignment(for: .mockAny()))

            source.setResponse(statusCode: statusCode, location: destination.url(host: "127.0.0.1"))
            for subject in ["subject-a", "subject-b"] {
                let completed = expectation(description: "refused \(statusCode) redirect for \(subject)")
                var capturedResult: Result<Void, FlagsError>?
                repository.setEvaluationContext(.init(
                    targetingKey: subject,
                    attributes: [AssignmentAuthorization.contextAttribute: .string("dummy-token-A")]
                )) { result in
                    capturedResult = result
                    completed.fulfill()
                }
                wait(for: [completed], timeout: 10)
                assertRedirectDownloadFailure(try XCTUnwrap(capturedResult))
                if subject == "subject-a" {
                    XCTAssertEqual(repository.state.currentState, .stale)
                    XCTAssertNotNil(repository.flagAssignment(for: .mockAny()))
                    XCTAssertEqual(repository.context?.targetingKey, "subject-a")
                } else {
                    XCTAssertEqual(repository.state.currentState, .error)
                    XCTAssertNil(repository.flagAssignment(for: .mockAny()))
                    XCTAssertEqual(repository.evaluationSnapshot(for: .mockAny()).error, .general)
                }
                XCTAssertTrue(destination.requests.isEmpty)
            }
            XCTAssertEqual(source.requests.count, 3)
        }
    }

    private func makeRedirectTestSession(certificate: SecCertificate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        // Only the fixture certificate is trusted, without changing system or simulator trust.
        return URLSession(
            configuration: configuration,
            delegate: AssignmentRedirectTrustDelegate(certificate: certificate),
            delegateQueue: nil
        )
    }

    private func assertRedirectDownloadFailure<T>(
        _ result: Result<T, FlagsError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.networkError(let error)) = result, let urlError = error as? URLError else {
            return XCTFail("Expected the existing network-failure classification", file: file, line: line)
        }
        XCTAssertEqual(urlError.code, .badServerResponse, file: file, line: line)
        XCTAssertTrue((urlError as NSError).userInfo.isEmpty, file: file, line: line)
    }

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

    func testExactAuthorizationRejectionReturnsTypedSafeError() throws {
        let logger = CoreLoggerMock()
        let dd = DD.mockWith(logger: logger)
        defer { dd.reset() }
        let response = try XCTUnwrap(
            HTTPURLResponse(url: .mockAny(), statusCode: 401, httpVersion: nil, headerFields: nil)
        )
        let body = Data(#"{"errors":[{"status":"401","code":"ASSIGNMENT_AUTHORIZATION_FAILED","detail":"secret"}]}"#.utf8)
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["dd-assignment-token": "custom-secret"],
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success((body, response)))
            }
        )
        let completed = expectation(description: "authorization rejected")

        fetcher.flagAssignments(
            for: .init(targetingKey: "subject"),
            experimentationOptOut: nil,
            diagnostics: nil,
            assignmentToken: "opaque-token"
        ) { result in
            guard case .failure(.assignmentAuthorizationFailed) = result else {
                return XCTFail("Expected assignmentAuthorizationFailed, got \(result)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: AssignmentAuthorization.header), "opaque-token")
        XCTAssertEqual(logger.warnMessages, ["Assignment download failed: ASSIGNMENT_AUTHORIZATION_FAILED"])
        XCTAssertTrue(logger.recordedLogs.allSatisfy { $0.error == nil })
        XCTAssertFalse(logger.recordedLogs.description.contains("opaque-token"))
        XCTAssertFalse(logger.recordedLogs.description.contains("secret"))
    }

    func testAuthorizationRejectionRequiresExactStatusAndJSONAPIErrorCode() throws {
        let cases: [(status: Int, body: String)] = [
            (400, #"{"errors":[{"code":"ASSIGNMENT_AUTHORIZATION_FAILED"}]}"#),
            (403, #"{"errors":[{"code":"ASSIGNMENT_AUTHORIZATION_FAILED"}]}"#),
            (500, #"{"errors":[{"code":"ASSIGNMENT_AUTHORIZATION_FAILED"}]}"#),
            (401, #"{"errors":[{"code":"assignment_authorization_failed"}]}"#),
            (401, #"{"errors":[null,42,"ASSIGNMENT_AUTHORIZATION_FAILED",{}, {"code":true}]}"#),
            (401, #"{"errors":[{"code":"OTHER_ERROR"}]}"#),
            (401, #"{"errors":[]}"#),
            (401, #"{"errors":null}"#),
            (401, "null"),
            (401, "[]"),
            (401, #"{"code":"ASSIGNMENT_AUTHORIZATION_FAILED"}"#),
            (401, #"{"errors":"ASSIGNMENT_AUTHORIZATION_FAILED"}"#),
            (401, "not-json")
        ]

        for testCase in cases {
            let response = try XCTUnwrap(
                HTTPURLResponse(url: .mockAny(), statusCode: testCase.status, httpVersion: nil, headerFields: nil)
            )
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: featureScope,
                fetch: { _, completion in
                    completion(.success((Data(testCase.body.utf8), response)))
                }
            )
            let completed = expectation(description: "ordinary HTTP failure \(testCase)")
            fetcher.flagAssignments(for: .mockAny()) { result in
                guard case .failure(.networkError(let error)) = result,
                      (error as? URLError)?.code == .badServerResponse else {
                    return XCTFail("Expected ordinary bad-server-response, got \(result)")
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
        }
    }

    func testAuthorizationRejectionIsRecognizedAmongUnrelatedOrMalformedErrorsWithoutAToken() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(url: .mockAny(), statusCode: 401, httpVersion: nil, headerFields: nil)
        )
        let body = Data(#"{"errors":[null,42,"untyped",{}, {"code":false},{"code":"OTHER_ERROR"},{"code":"ASSIGNMENT_AUTHORIZATION_FAILED"}]}"#.utf8)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                XCTAssertNil(request.value(forHTTPHeaderField: AssignmentAuthorization.header))
                completion(.success((body, response)))
            }
        )
        let completed = expectation(description: "mixed typed rejection")
        fetcher.flagAssignments(for: .init(targetingKey: "subject")) { result in
            guard case .failure(.assignmentAuthorizationFailed) = result else {
                XCTFail("Expected typed authorization rejection")
                completed.fulfill()
                return
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testTokenBearingResponseDiagnosticsNeverReflectCredentials() throws {
        let secret = "too_many_values"
        let bodies: [(String, Bool)] = [
            ("invalid-json-\(secret)", false),
            (#"{"data":{"attributes":{"flags":{"too_many_values":{"allocationKey":"allocation","variationKey":"variant","variationType":"secret-too_many_values","variationValue":true,"reason":"TARGETING_MATCH","doLog":true}}}}}"#, true)
        ]
        for (body, succeeds) in bodies {
            let logger = CoreLoggerMock()
            let dd = DD.mockWith(logger: logger)
            defer { dd.reset() }
            let scope = FeatureScopeMock()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: .mockAny(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["DD-Flag-Selection-Ignored": secret]
            ))
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
                featureScope: scope,
                fetch: { _, completion in completion(.success((Data(body.utf8), response))) }
            )
            let completed = expectation(description: "redacted response")
            fetcher.flagAssignments(
                for: .init(targetingKey: "subject"),
                experimentationOptOut: nil,
                assignmentToken: secret
            ) { result in
                switch result {
                case .success(let response):
                    XCTAssertTrue(succeeds)
                    XCTAssertTrue(response.flags.isEmpty)
                    XCTAssertEqual(response.failedFlags.count, 1)
                case .failure(let error):
                    XCTAssertFalse(succeeds)
                    XCTAssertFalse(String(describing: error).contains(secret))
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
            XCTAssertFalse(logger.recordedLogs.description.contains(secret))
            XCTAssertFalse(String(describing: scope.telemetryMock.messages).contains(secret))
        }
    }

    func testTokenBearingTransportErrorsRetainOnlyPlatformErrorCodes() {
        let errors: [Error] = [
            URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "opaque-token"]),
            URLError(.cancelled, userInfo: [NSUnderlyingErrorKey: NSError(domain: "opaque-token", code: 1)]),
            NSError(domain: "opaque-token", code: 1, userInfo: [NSLocalizedDescriptionKey: "opaque-token"])
        ]
        for error in errors {
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: featureScope,
                fetch: { _, completion in completion(.failure(error)) }
            )
            let completed = expectation(description: "sanitized transport failure")
            fetcher.flagAssignments(
                for: .init(targetingKey: "subject"),
                experimentationOptOut: nil,
                assignmentToken: "opaque-token"
            ) { result in
                guard case .failure(.networkError(let sanitized)) = result else {
                    XCTFail("Expected a network failure")
                    completed.fulfill()
                    return
                }
                XCTAssertEqual((sanitized as? URLError)?.code, (error as? URLError)?.code ?? .unknown)
                XCTAssertFalse(String(describing: sanitized).contains("opaque-token"))
                XCTAssertFalse((sanitized as NSError).userInfo.description.contains("opaque-token"))
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
        }
    }

    func testTokenBearingTransportFailureDoesNotExposeOriginalErrorAndPreservesTimeoutClassification() {
        let secret = "opaque-token"
        let logger = CoreLoggerMock()
        let dd = DD.mockWith(logger: logger)
        defer { dd.reset() }
        let original = URLError(
            .timedOut,
            userInfo: [NSLocalizedDescriptionKey: "request failed with \(secret)"]
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { _, completion in completion(.failure(original)) }
        )
        let completed = expectation(description: "safe timeout")

        fetcher.flagAssignments(
            for: .mockAny(),
            experimentationOptOut: nil,
            diagnostics: nil,
            assignmentToken: secret
        ) { result in
            guard case .failure(.networkError(let error)) = result,
                  let urlError = error as? URLError else {
                return XCTFail("Expected network error, got \(result)")
            }
            XCTAssertEqual(urlError.code, .timedOut)
            XCTAssertFalse((error as NSError).userInfo.description.contains(secret))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertTrue(logger.recordedLogs.allSatisfy { $0.error == nil })
        XCTAssertFalse(logger.recordedLogs.description.contains(secret))
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

/// Two instances provide actual TLS connections on distinct, dynamically allocated loopback ports.
/// No URLProtocol interception or global certificate-trust changes are involved.
private final class AssignmentRedirectHTTPSOrigin {
    struct Request {
        let method: String
        let headers: [String: String]
        let body: Data
    }

    private let queue = DispatchQueue(label: "com.datadoghq.flags-tests-https-origin")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var receivedRequests: [Request] = []
    private var response: Data

    var requests: [Request] {
        queue.sync { receivedRequests }
    }

    init(identity: SecIdentity, statusCode: Int = 200, location: URL? = nil, body: Data = Data()) throws {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, try XCTUnwrap(sec_identity_create(identity)))
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        response = Self.httpResponse(statusCode: statusCode, location: location, body: body)

        let ready = XCTestExpectation(description: "loopback HTTPS listener ready")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.fulfill()
            case .failed(let error):
                XCTFail("HTTPS test listener failed: \(error)")
                ready.fulfill()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(on: connection, buffered: Data())
        }
        listener.start(queue: queue)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, case .ready = listener.state else {
            listener.cancel()
            throw InternalError(description: "HTTPS test listener did not become ready")
        }
        queue.sync { listener.stateUpdateHandler = nil }
    }

    func url(host: String) -> URL {
        URL(string: "https://\(host):\(listener.port!.rawValue)/precompute-assignments")!
    }

    func setResponse(statusCode: Int, location: URL? = nil, body: Data = Data()) {
        queue.sync {
            response = Self.httpResponse(statusCode: statusCode, location: location, body: body)
        }
    }

    func stop() {
        queue.sync {
            listener.newConnectionHandler = nil
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            let buffered = buffered + (data ?? Data())
            if let request = Self.parseRequest(buffered) {
                self.receivedRequests.append(request)
                connection.send(
                    content: self.response,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffered: buffered)
            }
        }
    }

    private static func parseRequest(_ bytes: Data) -> Request? {
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let method = lines.first?.components(separatedBy: " ").first else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = bytes[boundary.upperBound...]
        guard body.count >= length else {
            return nil
        }
        return Request(method: method, headers: headers, body: Data(body.prefix(length)))
    }

    private static func httpResponse(statusCode: Int, location: URL?, body: Data) -> Data {
        var head = "HTTP/1.1 \(statusCode) Test\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if let location {
            head += "Location: \(location.absoluteString)\r\n"
        }
        return Data((head + "\r\n").utf8) + body
    }
}

/// Trust only this test's certificate and loopback hosts; retain real URLSession TLS and redirect handling.
private final class AssignmentRedirectTrustDelegate: NSObject, URLSessionDelegate {
    private let certificateData: Data

    init(certificate: SecCertificate) {
        certificateData = SecCertificateCopyData(certificate) as Data
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["localhost", "127.0.0.1"].contains(challenge.protectionSpace.host),
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              SecCertificateCopyData(certificate) as Data == certificateData else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private struct AssignmentRedirectTLSIdentity {
    let identity: SecIdentity
    let certificate: SecCertificate

    static let shared = Result { try make() }

    private static func make() throws -> AssignmentRedirectTLSIdentity {
        // Self-signed, non-production fixture identity for localhost and 127.0.0.1 only.
        let base64 = """
        MIIJgQIBAzCCCUcGCSqGSIb3DQEHAaCCCTgEggk0MIIJMDCCA+cGCSqGSIb3DQEHBqCCA9gwggPUAgEAMIIDzQYJKoZIhvcNAQcB
        MBwGCiqGSIb3DQEMAQMwDgQIsGyIvphSYwYCAggAgIIDoEsQLSx1tOx1rQBLPWVxWDv4HVlRzlnVD2fjNioEQ91RuV40J5wScARD
        K4QdyxdoAs8odq8quSzmHOpgr6AzBL9iZInB1d02SG+5Tkd8RP3qSh9AKoLgmNJI23TrKA024MbjwPbffULxsPIsOknrnXvnZIiN
        HbWDixmCc0qv+xCkA3VBdPzQmaGL38DOA8kzVX/Frqg5yd/ji06cVGtfSZzPKX3WeIjnXhI2oWNfPTUJSPL8lzwcM34PFK01SQ1w
        IxcfhWKPAxCz/8jLCgSbOYE9GDsCJek5bx+aoiqGXak47F29dTAhED0gVkBprAh09Kgf55ASZLj0RQ7UtkxGQ6LLCdJl/37fgtBX
        zM1aiB+AZtU3wAyu93FpVpKdZIiUQyv0q6DS64bpbqvCYL3vTGFIquUzD3LWBJ4QhhT0B4RflxJULDF+hWhPGhzF7I9eokwzfZuY
        brgsgFEl3p8jShyDn94J+3bdQAZ6uVTu5n1VYa3Z8jCmwJofiNwjK7y4Z8RsIgGexgGJG0JG8d/54NW1cOMI4uHPDs1GEA1TQuB3
        VorCgdePsXYheaPgR0GmEYxgtWraixzkGXCOTig+z3/ZnqrMp3ERnMX+xjvYaBlYmkDsY7i7sL5/x1nbXdwVzNRPTFGsjq151kls
        LLA7PieE2DO8Q3oY2I7s2IqUEIXDZLO+c5E/Y5Ke78eLXAfCSqb/sBjO9VXIstHvhznk9Lu55fc/DyPJq7APPaq26u245Mypvr3S
        0ofFyk5H3sgngWmMHCK8mQxnVPfHZn3ItD61dxuEYl2L3jGsOASHHOmiNA8eKIotwEmGVNq87bu2TmxPpC3RyskISkzNju5yrHF+
        IpYR4zEPCsWPzmLYVyWkjD4N7qtz9YALn1O2e/k+EO+jybY03JKohI0k1c3whek2/KV73OvG0KSVHuNpxx02FgW/HEF1MkL2t2cr
        4BZFRbeb6at1RenXEu+ehqbslL0a3QLiPVYjAjmghAP6AY9IvRyq64OunP3DlAId/2RDi7oQtCclJV4JnXHLa5w7PKGq78crBiKT
        BdSiYe+P6NH+CWtylAYzsIKAdVgB+WtWvw3kqD4SJxF9uICiwjK+HsmNPqA1hX45uhgkLWMSwW2mY0Ri8dE7pBhL/GJtqq52aX1u
        eMjn9RilW27sde/HUluLRpS4W0LPww0sL+B5GfLVBnsASX+yX7gY549fUbDRqOoEJdwcmyH9GkYQJ0SKWKowggVBBgkqhkiG9w0B
        BwGgggUyBIIFLjCCBSowggUmBgsqhkiG9w0BDAoBAqCCBO4wggTqMBwGCiqGSIb3DQEMAQMwDgQIoVk227/XQVECAggABIIEyKsD
        4+lDsaDwIpaXX4nCwuMNpcimQQxK8bkT16BnlCSLoSHqOb8MDFU/a5EjZyvRctRFwzrfAKIT9719+PBN0s/CFLZICExtyikUd4uN
        HPdZz5GHHFpZglObpUXynSWkNGoYDRlF/gVwDXT+MbYtI3hucFas4h6SJ4R+KEbCpp6ARndByb0O/yyazxxKaY0YVkdgLUb1mExm
        TUAsGG6hIyyiPWlAEPWzSARmr05Fd2e6vg2QTDcnEJ1Ow4Qm779wiDkJgCuPlJU6j4O8ya3QePXRlYQF5yNFE1Ll8cvth+GE+h1C
        bniCzFvyBC26ouaStri68dL3MMroi4evnjEia3fyuUl/estZS8vGxJ10XQ76n6XhHeJTcW/mrupSYop3XKvJ4fhu0UF/KPOj51Vs
        nn4BRXMgOxWSTaFCuvk1lOU7xwohbzI39c4txPMAy5fK7PZomvKqjBT19eboq6FP5GvOU/WI1osEmRJpDqXbTC1S48qeAw+3+0XB
        am9wJ+BPs4W1JLLue6Dgalsl70X206cZ5N2bTw3mHsJuzzQLNHnUJyAN+3Es5500y5HI9bR1b5eNqH9sG8jfTNIVi/IVL4pHUZCf
        ph2wfq7D3rnscsxl606PpcfowD0TBaWlK32oZtdiWiW6HuTdxPROr3S6ZlVZ/yInxfoi/FKdIKFL+gDFVbU6fhCczTniIWDeEZmX
        tWtQ5jjsIgHNWuZ7utCuYCqLRsOvKRtlOHSm5ZiwVccZs/OG3Gb8yI4wQ9N40Js4qEvF3orCllXZnNb6FFoUcatcvniFtPx3pSmB
        3YKH2tUFlnQNrWSJiNr5Bg/spkCb2jnKgdIhC0AZ2Z+NMNk87LLL6buSQMnZbcblCa6TUKNvvHQwP8m/VDoisr3whxSkfBf3hAq0
        tMzBkTwULJ1K9Qs08ldjfisKmTpP6PLYSeh5JpWZPrRjBukjvWCBWTD2T/L0q/yzmW+VyqlRsmuN3nJa22PfGsK2OeKdpV3fibFA
        OK6fe2B8gwNwDqYuyRq6wbhm9AE57+Ha6TVdCx0VGHgAx/ko8XG/YT3FpDECKoI35rjQs7p9iyWkemSzl8JA7cijMPr7fWqxpfWJ
        VMlCTtrEMorzTFzmTijx/dB4kaPXfexPOwrxldzI0tzca0/Tozyb/HcLQ74zqifsqhEe6aIPw+S6bpLNIGCQqMmqU61I2TJB3XiU
        Uic/RggHCMSD/Emq2ON3VegLB+CZzZfryg4DIKoYrvo1lEA66rALbOR6WfWAZUvegZJVwXmhS3IOVmpZWB5unn0JZNL39W/Ma0qA
        orxiqyf32ucnUWSRZkSKHtR2GbjO7Nx7Mi8P7VD0/HVAwp2Iy+/9B2FGBcIFNLFaYQp4UtaQIh2pG9n5ISVRbBOcsQTF3y1Nbhal
        SzCnJ9zSNAAaNcNmBC7x4pNZNf9l+2UeLf2pJK9DgKKbZ63fhhXGL3dcfFjVpKwxWHJsV4B6PMFY7WuQP9LLUofX09cMYd8HNjSA
        sPU+oRMdvqv32y6XlKavuN9eqIGDHyJAUf2esAF1ucWxblv7XCsg0P3dw6fPD7kh6xMvNdJ7KXI0r9g/UemtDYfKbTOovjop2B4E
        7orlCUMto32GGHdesOsNag/e8ioH0TElMCMGCSqGSIb3DQEJFTEWBBTpI4Iu/q5Jj5xKCgUNpNZZleg2WzAxMCEwCQYFKw4DAhoF
        AAQUsUSqu71YicL4kXa67/vAYmhTOZ8ECJOh6w2smUQ1AgIIAA==
        """
        let bytes = try XCTUnwrap(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
        var options: [String: Any] = [kSecImportExportPassphrase as String: "redirect-test"]
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            options[kSecImportToMemoryOnly as String] = true
        }
        var items: CFArray?
        let importStatus = SecPKCS12Import(bytes as CFData, options as CFDictionary, &items)
        guard importStatus == errSecSuccess else {
            throw InternalError(description: "HTTPS test identity import failed: \(importStatus)")
        }
        let imported = try XCTUnwrap(items as? [[String: Any]])
        let identity = try XCTUnwrap(imported.first?[kSecImportItemIdentity as String]) as! SecIdentity
        var certificate: SecCertificate?
        let copyStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard copyStatus == errSecSuccess else {
            throw InternalError(description: "HTTPS test certificate lookup failed: \(copyStatus)")
        }
        return AssignmentRedirectTLSIdentity(identity: identity, certificate: try XCTUnwrap(certificate))
    }
}
