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
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            assignmentRequestFetch: .init { request, completion in
                capturedRequest.value = request
                completion(.success(mockAssignmentFetchResponse()))
                return {}
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
            capturedRequest.value?.url?.absoluteString,
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
            assignmentRequestFetch: .init { _, completion in
                completion(.failure(URLError(.notConnectedToInternet)))
                return {}
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
        XCTAssertTrue(
            featureScope.telemetryMock.messages.firstError()?.message.hasPrefix(
                "Failed to fetch flag assignments from the server"
            ) == true
        )
    }

    func testFlagAssignmentsInvalidResponse() {
        // Given
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            assignmentRequestFetch: .init { _, completion in
                completion(.success(mockAssignmentFetchResponse(data: Data())))
                return {}
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
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            assignmentRequestFetch: .init { request, completion in
                capturedRequest.value = request
                completion(.success(mockAssignmentFetchResponse()))
                return {}
            }
        )

        let completed = expectation(description: "completed")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(capturedRequest.value?.url, customEndpoint)
        XCTAssertEqual(capturedRequest.value?.allHTTPHeaderFields?["X-Custom-Header"], "custom-value")
    }

    func testFlagAssignmentsRejectsUnsuccessfulHTTPResponse() {
        // Given
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            assignmentRequestFetch: .init { _, completion in
                completion(.success(mockAssignmentFetchResponse(statusCode: 503)))
                return {}
            }
        )
        let completedWithNetworkError = expectation(description: "completedWithNetworkError")

        // When
        fetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(.networkError(let error)) = result,
               let urlError = error as? URLError,
               urlError.code == .badServerResponse {
                completedWithNetworkError.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertTrue(
            featureScope.telemetryMock.messages.firstError()?.message.contains(
                "Failed to fetch flag assignments from the server (status: 503)"
            ) == true
        )
    }

    func testCustomAssignmentRequestFetchReceivesSDKOwnedRequest() throws {
        // Given
        featureScope.contextMock = .mockWith(
            site: .eu1,
            clientToken: "client-token",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "application-id")]
        )
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            assignmentRequestFetch: .init { request, completion in
                capturedRequest.value = request
                completion(.success(mockAssignmentFetchResponse()))
                return {}
            }
        )
        let completed = expectation(description: "completed")
        let capturedResult = LockedBox<Result<[String: FlagAssignment], FlagsError>?>(nil)

        // When
        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completed.fulfill()
        }

        // Then
        wait(for: [completed], timeout: 1)
        XCTAssertEqual(
            capturedRequest.value?.url?.absoluteString,
            "https://preview.ff-cdn.datadoghq.eu/precompute-assignments"
        )
        XCTAssertEqual(capturedRequest.value?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "dd-client-token"), "client-token")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "dd-application-id"), "application-id")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        XCTAssertNotNil(capturedRequest.value?.httpBody)
        XCTAssertEqual(try XCTUnwrap(capturedResult.value).get(), .mockAny())
    }

    func testSerializesCompletionDeliveryForConcurrentRequests() {
        let transportCompletions = LockedBox<[Flags.AssignmentRequestFetch.Completion]>([])
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            assignmentRequestFetch: .init { _, completion in
                transportCompletions.mutate { $0.append(completion) }
                return {}
            }
        )
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)

        fetcher.flagAssignments(for: .mockAny()) { _ in
            firstEntered.signal()
            _ = releaseFirst.wait(timeout: .now() + 2)
        }
        fetcher.flagAssignments(for: .mockAny()) { _ in
            secondEntered.signal()
        }
        XCTAssertEqual(transportCompletions.value.count, 2)

        transportCompletions.value[0](.success(mockAssignmentFetchResponse()))
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 1), .success)
        transportCompletions.value[1](.success(mockAssignmentFetchResponse()))
        XCTAssertEqual(
            secondEntered.wait(timeout: .now() + 0.1),
            .timedOut,
            "the second callback must not overlap the first callback"
        )
        releaseFirst.signal()
        XCTAssertEqual(secondEntered.wait(timeout: .now() + 1), .success)
    }

    func testFlagAssignmentsAcceptsOnlyFirstTransportCompletion() {
        // Given
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            assignmentRequestFetch: .init { _, completion in
                completion(.success(mockAssignmentFetchResponse()))
                completion(.failure(URLError(.timedOut)))
                return {}
            }
        )
        let completionCount = LockedBox(0)
        let firstCompletion = expectation(description: "first completion")
        let duplicateCompletion = expectation(description: "duplicate completion")
        duplicateCompletion.isInverted = true

        // When
        fetcher.flagAssignments(for: .mockAny()) { _ in
            let count = completionCount.mutate { value -> Int in
                value += 1
                return value
            }
            if count == 1 {
                firstCompletion.fulfill()
            } else {
                duplicateCompletion.fulfill()
            }
        }

        // Then
        wait(for: [firstCompletion], timeout: 1)
        wait(for: [duplicateCompletion], timeout: 0.1)
        XCTAssertEqual(completionCount.value, 1)
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

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }

    @discardableResult
    func mutate<Result>(_ operation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&storedValue)
    }
}

private func mockAssignmentFetchResponse(
    statusCode: Int = 200,
    data: Data = .mockAnyFlagAssignmentsResponse()
) -> Flags.AssignmentRequestFetch.Response {
    .init(
        data: data,
        httpResponse: HTTPURLResponse(
            url: .mockAny(),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    )
}
