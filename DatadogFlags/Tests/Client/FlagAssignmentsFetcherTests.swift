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

    func testBuildsRequestAndDecodesResponse() throws {
        featureScope.contextMock = .mockWith(site: .us3)
        let capturedRequest = ThreadSafeBox<URLRequest?>(nil)
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "assignments decoded")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest.value = request
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                return {}
            },
            assignmentRequestRetryCount: 0
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(
            capturedRequest.value?.url?.absoluteString,
            "https://preview.ff-cdn.us3.datadoghq.com/precompute-assignments"
        )
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        XCTAssertNotNil(capturedRequest.value?.value(forHTTPHeaderField: "dd-client-token"))
        XCTAssertNotNil(capturedRequest.value?.httpBody)
        let flagAssignments = try XCTUnwrap(capturedResult.value?.get())
        XCTAssertEqual(flagAssignments, .mockAny())
    }

    func testCustomAssignmentRequestFetchReceivesSDKOwnedRequest() throws {
        featureScope.contextMock = .mockWith(
            site: .eu1,
            clientToken: "client-token",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "application-id")]
        )
        let capturedRequest = ThreadSafeBox<URLRequest?>(nil)
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "assignments decoded")
        let customFetch = Flags.AssignmentRequestFetch { request, completion in
            capturedRequest.value = request
            completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(
            capturedRequest.value?.url?.absoluteString,
            "https://preview.ff-cdn.datadoghq.eu/precompute-assignments"
        )
        XCTAssertEqual(capturedRequest.value?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "dd-client-token"), "client-token")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "dd-application-id"), "application-id")
        XCTAssertEqual(capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        XCTAssertNotNil(capturedRequest.value?.httpBody)
        let flagAssignments = try XCTUnwrap(capturedResult.value?.get())
        XCTAssertEqual(flagAssignments, .mockAny())
    }

    func testCustomAssignmentRequestFetchCannotBypassResponseStatusValidation() {
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "status validated")
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 401)))
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        guard
            case .failure(.networkError(let error)) = capturedResult.value,
            (error as? URLError)?.code == .badServerResponse
        else {
            return XCTFail("Expected HTTP status validation after the custom transport")
        }
        XCTAssertTrue(
            featureScope.telemetryMock.messages.firstError()?.message.contains(
                "Failed to fetch flag assignments from the server (status: 401)"
            ) == true
        )
    }

    func testSuccessfulResponseWithInvalidBodyIsNotRetried() {
        let fetchCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "invalid body rejected")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            fetch: { _, completion in
                fetchCount.mutate { $0 += 1 }
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200, data: Data())))
                return {}
            },
            assignmentRequestRetryCount: 3
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        guard case .failure(.invalidResponse) = capturedResult.value else {
            return XCTFail("Expected an invalid response error")
        }
        XCTAssertEqual(fetchCount.value, 1)
    }

    func testMapsTransportErrorToNetworkError() {
        let expectedError = URLError(.notConnectedToInternet)
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "transport error mapped")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                completion(.failure(expectedError))
                return {}
            },
            assignmentRequestRetryCount: 0
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        guard
            case .failure(.networkError(let error)) = capturedResult.value,
            (error as? URLError)?.code == expectedError.code
        else {
            return XCTFail("Expected the transport error to be mapped to a network error")
        }
        XCTAssertTrue(
            featureScope.telemetryMock.messages.firstError()?.message.hasPrefix(
                "Failed to fetch flag assignments from the server"
            ) == true
        )
    }

    func testDefaultPolicyMakesOneRequestWithoutRetry() {
        let expectedError = URLError(.networkConnectionLost)
        let fetchCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<[String: FlagAssignment], FlagsError>?>(nil)
        let completion = expectation(description: "request failed")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                fetchCount.mutate { $0 += 1 }
                completion(.failure(expectedError))
                return {}
            }
        )

        fetcher.flagAssignments(for: .mockAny()) {
            capturedResult.value = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(fetchCount.value, 1)
        guard
            case .failure(.networkError(let error)) = capturedResult.value,
            (error as? URLError)?.code == expectedError.code
        else {
            return XCTFail("Expected the initial request failure without a retry")
        }
    }

    func testSerializesCompletionDeliveryForConcurrentRequests() {
        let transportCompletions = ThreadSafeBox<[Flags.AssignmentRequestFetch.Completion]>([])
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            transportCompletions.mutate { $0.append(completion) }
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
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

        transportCompletions.value[0](.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 1), .success)
        transportCompletions.value[1](.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        XCTAssertEqual(
            secondEntered.wait(timeout: .now() + 0.1),
            .timedOut,
            "the second callback must not overlap the first callback"
        )
        releaseFirst.signal()
        XCTAssertEqual(secondEntered.wait(timeout: .now() + 1), .success)
    }

    func testCustomTransportCompletionIsDeliveredAtMostOnce() {
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
            completion(.failure(URLError(.networkConnectionLost)))
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
        )
        let completionCount = ThreadSafeBox(0)
        let firstCompletion = expectation(description: "first completion")
        let duplicateCompletion = expectation(description: "duplicate completion")
        duplicateCompletion.isInverted = true

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

        wait(for: [firstCompletion], timeout: 1)
        wait(for: [duplicateCompletion], timeout: 0.1)
        XCTAssertEqual(completionCount.value, 1)
    }

    func testUsesCustomEndpoint() {
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        let capturedRequest = ThreadSafeBox<URLRequest?>(nil)
        let completion = expectation(description: "request completed")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { request, fetchCompletion in
                capturedRequest.value = request
                fetchCompletion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                return {}
            },
            assignmentRequestRetryCount: 0
        )

        fetcher.flagAssignments(for: .mockAny()) { _ in completion.fulfill() }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(capturedRequest.value?.url, customEndpoint)
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

    // PROBE: after the handle is cancelled, does the fetcher still deliver a result?
    func testCancelledRequestDeliversNothing() {
        let transportCompletion = ThreadSafeBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                transportCompletion.value = completion
                return {}
            },
            assignmentRequestRetryCount: 0
        )
        let cancelledResults = ThreadSafeBox(0)

        let handle = fetcher.flagAssignments(for: .mockAny()) { _ in
            cancelledResults.mutate { $0 += 1 }
        }
        let cancelledTransport = transportCompletion.value
        XCTAssertNotNil(cancelledTransport, "the request must have reached the transport")
        handle.cancel()
        cancelledTransport?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))

        // Results arrive on one serial queue, so a later request that does deliver proves the
        // cancelled one already had its turn.
        let delivered = expectation(description: "an uncancelled request delivers")
        fetcher.flagAssignments(for: .mockAny()) { _ in delivered.fulfill() }
        transportCompletion.value?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        waitForExpectations(timeout: 5)

        XCTAssertEqual(
            cancelledResults.value,
            0,
            "a cancelled request must not deliver a result: the repository answers its caller instead"
        )
    }
}
