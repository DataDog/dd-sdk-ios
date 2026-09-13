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

    func testAssignmentAuthorizationExpirationNotifiesAndClearsToken() {
        let expiration = Date().addingTimeInterval(3_600)
        let store = AssignmentAuthorizationStore(
            initialAuthorization: .init(bearerToken: Self.compactJWT, expiresAt: expiration)
        )
        var notificationCount = 0
        store.setExpirationHandler {
            notificationCount += 1
        }

        store.expireIfNeeded(at: expiration.addingTimeInterval(1))

        XCTAssertEqual(notificationCount, 1)
        XCTAssertTrue(store.snapshot().isEnabled)
        XCTAssertNil(store.snapshot().authorization)
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

    func testFlagAssignmentsRejectsResponseWhenVerificationFails() {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: [:],
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: .init(
                    bearerToken: Self.compactJWT,
                    expiresAt: .distantFuture
                )
            ),
            fetch: { _, completion in
                completion(.success(self.fetched(.mockAnyFlagAssignmentsResponse())))
            },
            verify: { _, _, _ in
                throw SignedAssignmentVerificationError.invalidSignature
            },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let completed = expectation(description: "completed")

        fetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(.invalidResponse) = result {
                completed.fulfill()
            }
        }

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
        let requestBody = Data(#"{"data":{"attributes":{"subject":{"targeting_key":"user-1"}}}}"#.utf8)
        let responseBody = Data(#"{"data":{"id":"user-1"}}"#.utf8)
        var request = URLRequest(url: URL(string: "https://example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("client-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(Self.compactJWT)", forHTTPHeaderField: "Authorization")
        request.setValue("000102030405060708090a0b0c0d0e0f", forHTTPHeaderField: "x-dd-ffe-request-nonce")
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-dd-ffe-signature-version": "2",
                "x-dd-ffe-authorization-policy-version": "ap_test_v2",
                "x-dd-ffe-issued-at": "1789096800",
                "x-dd-ffe-expires-at": "1789097100",
                "x-dd-ffe-certificate-id": "a0d868097393828703e0f9864e355a79b744df556d151249ce947157f08a0ff7",
                "x-dd-ffe-signing-certificate": "MIIBszCCAVqgAwIBAgIBZTAKBggqhkjOPQQDAjAzMTEwLwYDVQQDDChEYXRhZG9nIEZGRSBFZGdlIEFzc2lnbm1lbnRzIFBPQyBSb290IEsxMB4XDTI2MDkxMTAzMTgzMFoXDTI2MTIxMDAzMTgzMFowMjEwMC4GA1UEAwwnRGF0YWRvZyBGRkUgRWRnZSBBc3NpZ25tZW50cyBQT0MgTGVhZiBBMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEOAdt79MNq0/K82oozH9BifTCyu5pogz9VnCf69v6m5rIERSTO27L2SizPPI3ptfMBDa+bT/0wMdPc6GQYG4QeaNgMF4wDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPjCuJhWtNy/Ne+/6ZCIB8cmhFuJMB8GA1UdIwQYMBaAFHGtfswbRCOOchC6yZHakhktSdq4MAoGCCqGSM49BAMCA0cAMEQCIFvqYcK+OAaBdMRuMkSpOVscR1SMdCPt5LNdkQEZyvNCAiBq2rtg8F27nZ2mHyoAL4OT5tCMBKvYytpnRZzwMBYJTQ==",
                "x-dd-ffe-signature": "MEUCIQC1Y+HApWCEfejMtZuWrq5Z7zXHoCkeheykCh0i4AmK6gIgXtiexYZXd2mC0r66E0lNOX41Cr4jcx8pm8yrrvbQ754="
            ]
        ))

        try SignedAssignmentVerifier.verify(
            request: request,
            fetched: FetchedFlagAssignments(data: responseBody, response: response),
            clientToken: "client-token",
            currentTime: 1_789_096_800
        )

        var tamperedBody = responseBody
        tamperedBody[0] ^= 1
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: FetchedFlagAssignments(data: tamperedBody, response: response),
                clientToken: "client-token",
                currentTime: 1_789_096_800
            )
        )
    }

    func testLiveStagingSignedAssignmentAndRejectsTampering() throws {
        guard let clientToken = ProcessInfo.processInfo.environment["FFE_STAGING_CLIENT_TOKEN"],
              let accessJWT = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENT_JWT"] else {
            throw XCTSkip("FFE_STAGING_CLIENT_TOKEN and FFE_STAGING_ASSIGNMENT_JWT are required for the live proof.")
        }
        let requestBody = Data(
            #"{"data":{"type":"precompute-assignments-request","attributes":{"env":{"dd_env":"staging"},"subject":{"targeting_key":"signed-assignment-poc","targeting_attributes":{"user_id":"signed-assignment-poc","country":"US"}}}}}"#.utf8
        )
        var request = URLRequest(
            url: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments")!
        )
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(clientToken, forHTTPHeaderField: "dd-client-token")
        request.setValue("Bearer \(accessJWT)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "x-dd-ffe-signature-version")
        request.setValue(try SignedAssignmentVerifier.makeNonce(), forHTTPHeaderField: "x-dd-ffe-request-nonce")

        let completed = expectation(description: "live signed assignment response")
        var result: Result<FetchedFlagAssignments, Error>?
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: request) { data, response, error in
            defer { completed.fulfill() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data, let response = response as? HTTPURLResponse else {
                result = .failure(URLError(.badServerResponse))
                return
            }
            result = .success(FetchedFlagAssignments(data: data, response: response))
        }
        task.resume()

        waitForExpectations(timeout: 10)
        let fetched = try XCTUnwrap(result).get()
        XCTAssertEqual(fetched.response.statusCode, 200)
        try SignedAssignmentVerifier.verify(
            request: request,
            fetched: fetched,
            clientToken: clientToken
        )

        var tamperedBody = fetched.data
        tamperedBody[tamperedBody.startIndex] ^= 1
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: FetchedFlagAssignments(data: tamperedBody, response: fetched.response),
                clientToken: clientToken
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

    private static let compactJWT = "eyJhbGciOiJFUzI1NiIsImtpZCI6ImN1c3RvbWVyLTIwMjYtMDkiLCJ0eXAiOiJkYXRhZG9nLWZmZS1hY2Nlc3Mrand0In0.eyJzdWIiOiJ1c2VyLTEifQ.signature"
}
