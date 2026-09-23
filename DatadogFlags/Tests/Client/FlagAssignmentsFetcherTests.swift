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
        waitForExpectations(timeout: 1)
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
            let featureScope = QueuedFeatureScope(contextQueue: contextQueue)
            let queue = DispatchQueue(label: "com.datadoghq.flags-tests-assignment-fetch")
            let queueKey = DispatchSpecificKey<Void>()
            queue.setSpecific(key: queueKey, value: ())
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                featureScope: featureScope,
                assignmentFetchQueue: queue,
                fetch: { _, completion in
                    XCTAssertFalse(featureScope.isOnContextQueue)
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

            fetcher.flagAssignments(for: .mockAny()) { _ in
                XCTAssertFalse(featureScope.isOnContextQueue)
                XCTAssertNil(DispatchQueue.getSpecific(key: queueKey))
                firstCompletionStarted.fulfill()
                releaseCompletion.wait()
                firstCompletionFinished.fulfill()
            }
            wait(for: [firstCompletionStarted], timeout: 1)

            // When
            fetcher.flagAssignments(for: .mockAny()) { _ in
                XCTAssertFalse(featureScope.isOnContextQueue)
                XCTAssertNil(DispatchQueue.getSpecific(key: queueKey))
                secondCompleted.fulfill()
            }

            // Then
            wait(for: [secondCompleted], timeout: 1)
        }
    }
}

private final class QueuedFeatureScope: FeatureScope, @unchecked Sendable {
    private let contextQueue: DispatchQueue
    private let contextQueueKey = DispatchSpecificKey<Void>()
    private let contextMock: DatadogContext

    var isOnContextQueue: Bool {
        DispatchQueue.getSpecific(key: contextQueueKey) != nil
    }

    init(contextQueue: DispatchQueue, context: DatadogContext = .mockAny()) {
        self.contextQueue = contextQueue
        self.contextMock = context
        self.contextQueue.setSpecific(key: contextQueueKey, value: ())
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {}

    func context(_ block: @escaping (DatadogContext) -> Void) {
        contextQueue.async {
            block(self.contextMock)
        }
    }

    var dataStore: DataStore { NOPDataStore() }

    var telemetry: Telemetry { NOPTelemetry() }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {}

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {}

    func set(anonymousId: String?) {}
}
