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
        // Given
        featureScope.contextMock = .mockWith(site: .us3)
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(Self.fetchResponse(statusCode: 200)))
                return {}
            },
            assignmentRequestRetryCount: 0
        )
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://preview.ff-cdn.us3.datadoghq.com/precompute-assignments"
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        XCTAssertNotNil(capturedRequest?.value(forHTTPHeaderField: "dd-client-token"))
        XCTAssertNotNil(capturedRequest?.httpBody)
        let flagAssignments = try XCTUnwrap(capturedResult?.get())
        XCTAssertEqual(flagAssignments, .mockAny())
    }

    func testCustomAssignmentRequestFetchReceivesSDKOwnedRequest() throws {
        // Given
        featureScope.contextMock = .mockWith(
            site: .eu1,
            clientToken: "client-token",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "application-id")]
        )
        var capturedRequest: URLRequest?
        let customFetch = Flags.AssignmentRequestFetch { request, completion in
            capturedRequest = request
            completion(.success(Self.fetchResponse(statusCode: 200)))
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: ["X-Custom-Header": "custom-value"],
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
        )
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://preview.ff-cdn.datadoghq.eu/precompute-assignments"
        )
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "dd-client-token"), "client-token")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "dd-application-id"), "application-id")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        XCTAssertNotNil(capturedRequest?.httpBody)
        let flagAssignments = try XCTUnwrap(capturedResult?.get())
        XCTAssertEqual(flagAssignments, .mockAny())
    }

    func testCustomAssignmentRequestFetchCannotBypassResponseStatusValidation() {
        // Given
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(Self.fetchResponse(statusCode: 401)))
            return {}
        }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            assignmentRequestFetch: customFetch
        )
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        guard
            case .failure(.networkError(let error)) = capturedResult,
            (error as? URLError)?.code == .badServerResponse
        else {
            return XCTFail("Expected HTTP status validation after the custom transport")
        }
        XCTAssertEqual(
            featureScope.telemetryMock.messages.firstError()?.message,
            "Failed to fetch flag assignments from the server"
        )
    }

    func testSuccessfulResponseWithInvalidBodyIsNotRetried() {
        // Given
        var fetchCount = 0
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            fetch: { _, completion in
                fetchCount += 1
                completion(.success(Self.fetchResponse(statusCode: 200, data: Data())))
                return {}
            },
            assignmentRequestRetryCount: 3
        )
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        guard case .failure(.invalidResponse) = capturedResult else {
            return XCTFail("Expected an invalid response error")
        }
        XCTAssertEqual(fetchCount, 1)
    }

    func testMapsTransportErrorToNetworkError() {
        // Given
        let expectedError = URLError(.notConnectedToInternet)
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
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        guard
            case .failure(.networkError(let error)) = capturedResult,
            (error as? URLError)?.code == expectedError.code
        else {
            return XCTFail("Expected the transport error to be mapped to a network error")
        }
        XCTAssertEqual(
            featureScope.telemetryMock.messages.firstError()?.message,
            "Failed to fetch flag assignments from the server"
        )
    }

    func testDefaultPolicyMakesOneRequestWithoutRetry() {
        // Given
        let expectedError = URLError(.networkConnectionLost)
        var fetchCount = 0
        var scheduledRetryCount = 0
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                fetchCount += 1
                completion(.failure(expectedError))
                return {}
            },
            schedule: { _, _ in
                scheduledRetryCount += 1
                return {}
            }
        )
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        fetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        XCTAssertEqual(fetcher.assignmentRequestRetryCount, 0)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(scheduledRetryCount, 0)
        guard
            case .failure(.networkError(let error)) = capturedResult,
            (error as? URLError)?.code == expectedError.code
        else {
            return XCTFail("Expected the initial request failure without a retry")
        }
    }

    func testUsesCustomEndpoint() {
        // Given
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(Self.fetchResponse(statusCode: 200)))
                return {}
            },
            assignmentRequestRetryCount: 0
        )

        // When
        fetcher.flagAssignments(for: .mockAny()) { _ in }

        // Then
        XCTAssertEqual(capturedRequest?.url, customEndpoint)
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

    private static func fetchResponse(
        statusCode: Int,
        data: Data = .mockAnyFlagAssignmentsResponse()
    ) -> FlagAssignmentsFetchResponse {
        FlagAssignmentsFetchResponse(
            data: data,
            httpResponse: HTTPURLResponse(
                url: .mockAny(),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
