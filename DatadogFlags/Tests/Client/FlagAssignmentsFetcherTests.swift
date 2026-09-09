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
                completion(.success(self.fetched(.mockAnyFlagAssignmentsResponse())))
            },
            verify: { _, _, _ in },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
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
            },
            verify: { _, _, _ in },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
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
                completion(.success(self.fetched(Data())))
            },
            verify: { _, _, _ in },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
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
                completion(.success(self.fetched(.mockAnyFlagAssignmentsResponse())))
            },
            verify: { _, _, _ in },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
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

    func testSignedAssignmentVerifierAcceptsOriginAndRejectsTampering() throws {
        let requestBody = Data(
            """
            {"data":{"type":"precompute-assignments-request","attributes":{"env":{"dd_env":"test-env"},"source":{"sdk_name":"poc-curl","sdk_version":"1.0"},"subject":{"targeting_key":"user123","targeting_attributes":{"country":"US"}}}}}
            """.utf8
        )
        let responseBody = Data(
            """
            {"data":{"id":"user123","type":"precomputed-assignments","attributes":{"obfuscated":false,"createdAt":"2026-09-09T03:49:09.973203Z","format":"PRECOMPUTED","environment":{"name":"test-env"},"flags":{"country-message":{"variationType":"string","variationValue":"hello-us","doLog":false,"allocationKey":"country-allocation","variationKey":"us","reason":"TARGETING_MATCH","serialId":11,"extraLogging":{}}}}}}
            """.utf8
        )
        var request = URLRequest(url: URL(string: "http://127.0.0.1:17676/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("poc-client-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("000102030405060708090a0b0c0d0e0f", forHTTPHeaderField: "x-dd-ffe-request-nonce")
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-dd-ffe-signature-version": "1",
                "x-dd-ffe-issued-at": "1788925749",
                "x-dd-ffe-expires-at": "1788926049",
                "x-dd-ffe-certificate-id": "d0745e67df306ef25a7a1b8d2f4e3dddace676bfc87da42f8604188fc71e5ec8",
                "x-dd-ffe-signing-certificate": "MIIBlzCCAT2gAwIBAgIBAjAKBggqhkjOPQQDAjAyMTAwLgYDVQQDEydEYXRhZG9nIEZGRSBTaWduZWQgQXNzaWdubWVudHMgUE9DIFJvb3QwHhcNMjYwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAyMTAwLgYDVQQDEydEYXRhZG9nIEZGRSBTaWduZWQgQXNzaWdubWVudHMgUE9DIExlYWYwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQToOIWEw3kjXu2+fWY5Qzes0xvt/vWLq4m6L7utZOGoBcsqWvIhPdwv9ms2kd4skGRmMAbTa2QhGOVNkJN6HQYo0QwQjAOBgNVHQ8BAf8EBAMCB4AwDwYDVR0lBAgwBgYEVR0lADAfBgNVHSMEGDAWgBSGiz2ZJtQjcGZo/yO2jn3V/OFX4jAKBggqhkjOPQQDAgNIADBFAiBTCS85cf9drSucl7rlqQqBY5ni3H4gs6ThLDc7dDBB9gIhAJL/8Sy2/VdqQCEP0np+nHY/UYAVZqreYhEse+PbtRnb",
                "x-dd-ffe-signature": "MEUCIDL8Yuot2McXdFHtyEHmPCl+pXRKp8c7lgseHAGylIkyAiEA9yGxQoaJpM3ID79qrQ5urfL5sdR96tkm5IMpQ1LthmA="
            ]
        ))

        try SignedAssignmentVerifier.verify(
            request: request,
            fetched: FetchedFlagAssignments(data: responseBody, response: response),
            clientToken: "poc-client-token",
            currentTime: 1_788_925_749
        )

        var tamperedBody = responseBody
        tamperedBody[0] ^= 1
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: FetchedFlagAssignments(data: tamperedBody, response: response),
                clientToken: "poc-client-token",
                currentTime: 1_788_925_749
            )
        )
    }

    private func fetched(_ data: Data) -> FetchedFlagAssignments {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        return FetchedFlagAssignments(data: data, response: response)
    }
}
