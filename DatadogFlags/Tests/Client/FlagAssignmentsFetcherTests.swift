/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import CryptoKit
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
        XCTAssertEqual(store.snapshot().protection, .disabled)
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
            verify: { _, _, _, _, _ in Self.verificationMetadata },
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
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader))
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
            verify: { _, _, _, _, _ in Self.verificationMetadata },
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
            verify: { _, _, _, _, _ in Self.verificationMetadata },
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
                initialAuthorization: nil,
                protection: .signed
            ),
            fetch: { _, completion in
                completion(.success(self.fetched(.mockAnyFlagAssignmentsResponse())))
            },
            verify: { _, _, _, _, _ in
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

    func testSignedProtectionRejectsUnsignedProductionResponse() throws {
        let evaluationContext = FlagsEvaluationContext(targetingKey: "user-1")
        let responseData = try JSONEncoder().encode(
            FlagAssignmentsResponse(flags: [:], subject: evaluationContext.targetingKey)
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: nil,
                protection: .signed
            ),
            fetch: { request, completion in
                completion(.success(self.fetched(responseData, requestURL: request.url)))
            },
            verify: SignedAssignmentVerifier.verify,
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let completed = expectation(description: "completed")

        fetcher.flagAssignments(for: evaluationContext) { result in
            guard case .failure(.invalidResponse) = result else {
                return XCTFail("Expected signed mode to reject an unsigned response")
            }
            completed.fulfill()
        }

        waitForExpectations(timeout: 0)
    }

    func testSignedProtectionUsesProductionRequestAndDoesNotRequireAuthorization() throws {
        let evaluationContext = FlagsEvaluationContext(targetingKey: "user-1")
        let responseData = try JSONEncoder().encode(
            FlagAssignmentsResponse(flags: [:], subject: evaluationContext.targetingKey)
        )
        var capturedRequest: URLRequest?
        var capturedProtection: Flags.AssignmentProtection?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: nil,
                protection: .signed
            ),
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(self.fetched(responseData, requestURL: request.url)))
            },
            verify: { _, _, _, protection, _ in
                capturedProtection = protection
                return Self.verificationMetadata
            },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let completed = expectation(description: "completed")
        var result: Result<VerifiedFlagAssignments, FlagsError>?

        fetcher.verifiedFlagAssignments(for: evaluationContext) {
            result = $0
            completed.fulfill()
        }

        waitForExpectations(timeout: 0)
        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(capturedProtection, .signed)
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader),
            "2"
        )
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader),
            "000102030405060708090a0b0c0d0e0f"
        )
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try result?.get().signedPayload?.protection, .signed)
    }

    func testSignedAndAuthorizedProtectionBindsExactBearerToken() throws {
        let evaluationContext = FlagsEvaluationContext(targetingKey: "user-1")
        let authorization = Flags.AssignmentAuthorization(
            bearerToken: Self.compactJWT,
            expiresAt: .distantFuture
        )
        let responseData = try JSONEncoder().encode(
            FlagAssignmentsResponse(flags: [:], subject: evaluationContext.targetingKey)
        )
        var capturedRequest: URLRequest?
        let metadata = SignedAssignmentVerificationMetadata(
            certificateID: String(repeating: "a", count: 64),
            rulesRevision: "rules-1",
            issuedAt: 1_789_096_800,
            expiresAt: 1_789_097_100,
            authorizationPolicyVersion: "policy-1"
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: authorization,
                protection: .signedAndAuthorized
            ),
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(self.fetched(responseData, requestURL: request.url)))
            },
            verify: { _, _, _, protection, _ in
                XCTAssertEqual(protection, .signedAndAuthorized)
                return metadata
            },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let completed = expectation(description: "completed")
        var result: Result<VerifiedFlagAssignments, FlagsError>?

        fetcher.verifiedFlagAssignments(for: evaluationContext) {
            result = $0
            completed.fulfill()
        }

        waitForExpectations(timeout: 0)
        let signedPayload = try XCTUnwrap(result?.get().signedPayload)
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(Self.compactJWT)"
        )
        XCTAssertEqual(signedPayload.protection, .signedAndAuthorized)
        XCTAssertEqual(signedPayload.authorizationBinding?.policyVersion, "policy-1")
        XCTAssertEqual(
            signedPayload.authorizationBinding?.compactJWTSHA256,
            AssignmentAuthorizationStore.digest(of: Self.compactJWT)
        )
        let persistedJSON = String(
            data: try JSONEncoder().encode(signedPayload),
            encoding: .utf8
        )
        XCTAssertFalse(try XCTUnwrap(persistedJSON).contains(Self.compactJWT))
    }

    func testSignedAndAuthorizedProtectionFailsClosedWithoutAuthorization() {
        var didFetch = false
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: nil,
                protection: .signedAndAuthorized
            ),
            fetch: { _, _ in didFetch = true },
            verify: { _, _, _, _, _ in Self.verificationMetadata },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let completed = expectation(description: "completed")

        fetcher.flagAssignments(for: .mockAny()) { result in
            guard case .failure(.invalidConfiguration) = result else {
                return XCTFail("Expected missing authorization to fail closed")
            }
            completed.fulfill()
        }

        waitForExpectations(timeout: 0)
        XCTAssertFalse(didFetch)
    }

    func testProtectedRequestRejectsUnsafeEndpointBeforeAddingHeadersOrFetching() {
        let endpoints = [
            URL(string: "http://example.test/precompute-assignments")!,
            URL(string: "https://example.test/precompute-assignments?route=other")!,
            URL(string: "https://example.test/precompute-assignments#other")!,
            URL(string: "https://user@example.test/precompute-assignments")!,
            URL(string: "https://example.test/\(String(repeating: "a", count: 2_049))")!
        ]

        for endpoint in endpoints {
            assertProtectedRequestFailsBeforeNetwork(endpoint: endpoint)
        }
    }

    func testProtectedRequestRejectsOversizedBodyAndClientTokenBeforeNetwork() {
        assertProtectedRequestFailsBeforeNetwork(
            endpoint: URL(string: "https://example.test/precompute-assignments")!,
            evaluationContext: FlagsEvaluationContext(
                targetingKey: "user-1",
                attributes: ["oversized": .string(String(repeating: "a", count: 1_048_577))]
            )
        )
        assertProtectedRequestFailsBeforeNetwork(
            endpoint: URL(string: "https://example.test/precompute-assignments")!,
            datadogContext: .mockWith(
                site: .us1,
                clientToken: String(repeating: "a", count: 513),
                env: "production",
                sdkVersion: "wargame"
            )
        )
    }

    func testSignedAndAuthorizedRequestRejectsInvalidBearerShapeBeforeNetwork() {
        let invalidTokens = [
            "",
            "header.payload",
            "header..signature",
            "header.payload.signature with-space",
            "header.payload.signature=",
            "\(String(repeating: "a", count: 4_093)).b.c"
        ]
        for token in invalidTokens {
            assertProtectedRequestFailsBeforeNetwork(
                endpoint: URL(string: "https://example.test/precompute-assignments")!,
                protection: .signedAndAuthorized,
                authorization: Flags.AssignmentAuthorization(
                    bearerToken: token,
                    expiresAt: .distantFuture
                )
            )
        }
    }

    func testProtectedHTTPClientRejectsDeclaredOrReceivedBodiesAboveLimit() throws {
        let declared = try fetchWithProtectedHTTPClient(dataSize: 0, declaredSize: 9, maximumSize: 8)
        let streamed = try fetchWithProtectedHTTPClient(dataSize: 9, declaredSize: nil, maximumSize: 8)

        for result in [declared, streamed] {
            guard case .failure(let error as URLError) = result else {
                return XCTFail("Expected the protected transport to reject an oversized response")
            }
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        }
    }

    func testProtectedHTTPClientAcceptsBodyAtLimit() throws {
        let result = try fetchWithProtectedHTTPClient(dataSize: 8, declaredSize: 8, maximumSize: 8)
        XCTAssertEqual(try result.get().data, Data(repeating: 0x61, count: 8))
    }

    func testPersistedSignedAssignmentsAreReverifiedAndBoundToContextAndClientToken() throws {
        let datadogContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "client-token",
            env: "production",
            sdkVersion: "wargame"
        )
        featureScope.contextMock = datadogContext
        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "user-1",
            attributes: ["country": .string("US")]
        )
        let flags = ["wargame-fixture": FlagAssignment.mockAny()]
        let responseData = try JSONEncoder().encode(
            FlagAssignmentsResponse(flags: flags, subject: evaluationContext.targetingKey)
        )
        let metadata = SignedAssignmentVerificationMetadata(
            certificateID: String(repeating: "a", count: 64),
            rulesRevision: "rules-42",
            issuedAt: 1_789_096_800,
            expiresAt: 1_789_097_100,
            authorizationPolicyVersion: nil
        )
        var verificationCount = 0
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: nil,
                protection: .signed
            ),
            fetch: { request, completion in
                completion(.success(self.fetched(responseData, requestURL: request.url)))
            },
            verify: { _, _, _, protection, _ in
                XCTAssertEqual(protection, .signed)
                verificationCount += 1
                return metadata
            },
            makeNonce: { "000102030405060708090a0b0c0d0e0f" }
        )
        let fetched = expectation(description: "fetched")
        var result: Result<VerifiedFlagAssignments, FlagsError>?
        fetcher.verifiedFlagAssignments(for: evaluationContext) {
            result = $0
            fetched.fulfill()
        }
        waitForExpectations(timeout: 0)

        let verified = try XCTUnwrap(result).get()
        let flagsData = FlagsData(
            flags: verified.flags,
            context: evaluationContext,
            date: Date(timeIntervalSince1970: 1_789_096_800),
            signedPayload: try XCTUnwrap(verified.signedPayload)
        )
        XCTAssertEqual(flagsData.signedPayload?.rulesRevision, "rules-42")
        XCTAssertNil(flagsData.signedPayload?.requestHeaders["dd-client-token"])
        let persistedJSON = try XCTUnwrap(String(
            data: JSONEncoder().encode(flagsData),
            encoding: .utf8
        ))
        XCTAssertFalse(persistedJSON.contains("client-token"))

        func validate(_ data: FlagsData) -> Bool {
            let completed = expectation(description: "validated persisted assignments")
            var isValid = false
            fetcher.validatePersistedFlagAssignments(
                data,
                at: Date(timeIntervalSince1970: 1_789_096_800)
            ) {
                isValid = $0
                completed.fulfill()
            }
            waitForExpectations(timeout: 0)
            return isValid
        }

        XCTAssertTrue(validate(flagsData))

        var changedSubject = flagsData
        changedSubject.context = FlagsEvaluationContext(
            targetingKey: "user-2",
            attributes: evaluationContext.attributes
        )
        XCTAssertFalse(validate(changedSubject))

        var changedAttributes = flagsData
        changedAttributes.context = FlagsEvaluationContext(
            targetingKey: evaluationContext.targetingKey,
            attributes: ["country": .string("CA")]
        )
        XCTAssertFalse(validate(changedAttributes))

        var changedFlags = flagsData
        changedFlags.flags = [:]
        XCTAssertFalse(validate(changedFlags))

        featureScope.contextMock = .mockWith(
            site: .us1,
            clientToken: "another-client-token",
            env: "production",
            sdkVersion: "wargame"
        )
        XCTAssertFalse(validate(flagsData))
        XCTAssertEqual(verificationCount, 4)
    }

    func testPersistedArtifactRoundTripUsesRealTrustAndRejectsCriticalFieldMutations() throws {
        let verificationTime: Int64 = 1_789_096_800
        let datadogContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "client-token",
            env: "production",
            sdkVersion: "wargame"
        )
        featureScope.contextMock = datadogContext
        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "user-1",
            attributes: ["country": .string("US")]
        )
        let flags = [
            "wargame-fixture": FlagAssignment(
                allocationKey: "allocation-1",
                variationKey: "enabled",
                variation: .boolean(true),
                reason: "TARGETING_MATCH",
                doLog: false
            )
        ]
        let responseBody = try JSONEncoder().encode(
            FlagAssignmentsResponse(flags: flags, subject: evaluationContext.targetingKey)
        )
        let privateKey = try P256.Signing.PrivateKey(
            rawRepresentation: XCTUnwrap(Data(base64Encoded: Self.vectorPrivateKeyRaw))
        )
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: nil,
                protection: .signed
            ),
            fetch: { request, completion in
                do {
                    let input = try SignedAssignmentVerifier.signatureInput(
                        nonce: Data((0..<16).map(UInt8.init)),
                        request: request,
                        requestBody: request.httpBody ?? Data(),
                        compactJWT: nil,
                        clientToken: datadogContext.clientToken,
                        policyVersion: nil,
                        rulesRevision: "rules-production-test",
                        responseStatus: 200,
                        issuedAt: verificationTime,
                        expiresAt: verificationTime + 300,
                        responseBody: responseBody
                    )
                    let signature = try privateKey.signature(for: input).derRepresentation.base64EncodedString()
                    let response = HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            SignedAssignmentVerifier.signatureVersionHeader: "2",
                            SignedAssignmentVerifier.rulesRevisionHeader: "rules-production-test",
                            "x-datadog-feature-flags-issued-at": String(verificationTime),
                            "x-datadog-feature-flags-expires-at": String(verificationTime + 300),
                            "x-datadog-feature-flags-certificate-id": Self.vectorCertificateID,
                            "x-datadog-feature-flags-signing-certificate": Self.vectorCertificate,
                            "x-datadog-feature-flags-signature": signature
                        ]
                    )
                    completion(.success(FetchedFlagAssignments(
                        data: responseBody,
                        response: try XCTUnwrap(response)
                    )))
                } catch {
                    completion(.failure(error))
                }
            },
            verify: { request, fetched, clientToken, protection, _ in
                try SignedAssignmentVerifier.verify(
                    request: request,
                    fetched: fetched,
                    clientToken: clientToken,
                    protection: protection,
                    currentTime: verificationTime
                )
            },
            makeNonce: { Self.vectorNonce }
        )
        let completed = expectation(description: "production-shaped assignment fetched")
        var result: Result<VerifiedFlagAssignments, FlagsError>?
        fetcher.verifiedFlagAssignments(for: evaluationContext) {
            result = $0
            completed.fulfill()
        }
        waitForExpectations(timeout: 0)

        let verified = try XCTUnwrap(result).get()
        let flagsData = FlagsData(
            flags: verified.flags,
            context: evaluationContext,
            date: Date(timeIntervalSince1970: TimeInterval(verificationTime)),
            signedPayload: try XCTUnwrap(verified.signedPayload)
        )
        let persistedBytes = try JSONEncoder().encode(flagsData)
        let decoded = try JSONDecoder().decode(FlagsData.self, from: persistedBytes)

        func validate(_ data: FlagsData) -> Bool {
            let completed = expectation(description: "persisted artifact validated")
            var isValid = false
            fetcher.validatePersistedFlagAssignments(
                data,
                at: Date(timeIntervalSince1970: TimeInterval(verificationTime))
            ) {
                isValid = $0
                completed.fulfill()
            }
            waitForExpectations(timeout: 0)
            return isValid
        }

        XCTAssertTrue(validate(decoded))
        let payload = try XCTUnwrap(decoded.signedPayload)

        var changedFlags = decoded
        changedFlags.flags = [:]
        XCTAssertFalse(validate(changedFlags))

        var changedContext = decoded
        changedContext.context = FlagsEvaluationContext(
            targetingKey: "user-1",
            attributes: ["country": .string("CA")]
        )
        XCTAssertFalse(validate(changedContext))

        var changedRequestHeaders = payload.requestHeaders
        changedRequestHeaders[SignedAssignmentVerifier.requestNonceHeader] = String(repeating: "f", count: 32)
        var changedResponseHeaders = payload.responseHeaders
        changedResponseHeaders[SignedAssignmentVerifier.rulesRevisionHeader] = "rules-attacker"

        let payloadMutations = [
            payload.replacing(endpoint: URL(string: "https://other.test/precompute-assignments")),
            payload.replacing(environment: "other"),
            payload.replacing(subject: "user-2"),
            payload.replacing(clientTokenSHA256: String(repeating: "0", count: 64)),
            payload.replacing(requestBody: Data("tampered".utf8)),
            payload.replacing(requestHeaders: changedRequestHeaders),
            payload.replacing(responseBody: Data("tampered".utf8)),
            payload.replacing(responseHeaders: changedResponseHeaders),
            payload.replacing(certificateID: String(repeating: "0", count: 64)),
            payload.replacing(expiresAt: payload.expiresAt.addingTimeInterval(-1))
        ]
        for mutatedPayload in payloadMutations {
            var mutated = decoded
            mutated.signedPayload = mutatedPayload
            XCTAssertFalse(validate(mutated))
        }
    }

    func testFlagAssignmentsCustomEndpoint() {
        // Given
        let customEndpoint = URL(string: "https://custom-proxy.com/flags")!
        var capturedRequest: URLRequest?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: customEndpoint,
            customHeaders: [
                "X-Custom-Header": "custom-value",
                "Authorization": "Bearer customer-managed",
                SignedAssignmentVerifier.signatureVersionHeader: "customer-managed"
            ],
            featureScope: featureScope,
            fetch: { request, completion in
                capturedRequest = request
                completion(.success(self.fetched(.mockAnyFlagAssignmentsResponse())))
            },
            verify: { _, _, _, _, _ in Self.verificationMetadata },
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
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer customer-managed"
        )
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader),
            "customer-managed"
        )
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

    func testSignedOnlyVerifierMatchesEdgeGoldenVector() throws {
        let request = Self.vectorRequest(authorization: nil)
        let fetched = try Self.vectorResponse(
            requestURL: XCTUnwrap(request.url),
            policyVersion: nil,
            signature: Self.signedOnlySignature
        )
        let input = try Self.vectorSignatureInput(
            request: request,
            policyVersion: nil
        )

        XCTAssertEqual(input.count, 288)
        XCTAssertEqual(Self.sha256Hex(input), "b2dcfe21420f79ac6745a0e054d159d4f3197304bafb239e51c3a7aecf54f2e4")
        let metadata = try SignedAssignmentVerifier.verify(
            request: request,
            fetched: fetched,
            clientToken: "client-token",
            protection: .signed,
            currentTime: 1_789_096_800
        )
        XCTAssertNil(metadata.authorizationPolicyVersion)
        XCTAssertEqual(metadata.certificateID, Self.vectorCertificateID)
        XCTAssertEqual(metadata.rulesRevision, "")
        XCTAssertEqual(metadata.issuedAt, 1_789_096_800)
        XCTAssertEqual(metadata.expiresAt, 1_789_097_100)
    }

    func testSignedAndAuthorizedVerifierMatchesEdgeGoldenVectorAndRejectsTampering() throws {
        let request = Self.vectorRequest(authorization: Self.compactJWT)
        let fetched = try Self.vectorResponse(
            requestURL: XCTUnwrap(request.url),
            policyVersion: "ap_test_v2",
            signature: Self.signedAndAuthorizedSignature
        )
        let input = try Self.vectorSignatureInput(
            request: request,
            policyVersion: "ap_test_v2"
        )

        XCTAssertEqual(input.count, 334)
        XCTAssertEqual(Self.sha256Hex(input), "b0d8cd615160a59a69a0024fdca85213b9ca6d2a542f4490706cc3d67cde3148")
        let metadata = try SignedAssignmentVerifier.verify(
            request: request,
            fetched: fetched,
            clientToken: "client-token",
            protection: .signedAndAuthorized,
            currentTime: 1_789_096_800
        )
        XCTAssertEqual(metadata.authorizationPolicyVersion, "ap_test_v2")
        XCTAssertEqual(metadata.certificateID, Self.vectorCertificateID)
        XCTAssertEqual(metadata.rulesRevision, "")

        var tamperedBody = fetched.data
        tamperedBody[0] ^= 1
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: FetchedFlagAssignments(data: tamperedBody, response: fetched.response),
                clientToken: "client-token",
                protection: .signedAndAuthorized,
                currentTime: 1_789_096_800
            )
        )

        let changedRules = try Self.vectorResponse(
            requestURL: XCTUnwrap(request.url),
            policyVersion: "ap_test_v2",
            signature: Self.signedAndAuthorizedSignature,
            rulesRevision: "unverified-origin-revision"
        )
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: changedRules,
                clientToken: "client-token",
                protection: .signedAndAuthorized,
                currentTime: 1_789_096_800
            )
        )
    }

    func testVerifierRejectsMissingOrOversizedSignedHeadersBeforeTrustEvaluation() throws {
        let request = Self.vectorRequest(authorization: nil)
        let requestURL = try XCTUnwrap(request.url)
        let missingRules = try Self.vectorResponse(
            requestURL: requestURL,
            policyVersion: nil,
            signature: Self.signedOnlySignature,
            rulesRevision: nil
        )
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: missingRules,
                clientToken: "client-token",
                protection: .signed,
                currentTime: 1_789_096_800
            )
        )

        let oversizedCertificate = try Self.vectorResponse(
            requestURL: requestURL,
            policyVersion: nil,
            signature: Self.signedOnlySignature,
            certificate: String(repeating: "A", count: 8_193)
        )
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: oversizedCertificate,
                clientToken: "client-token",
                protection: .signed,
                currentTime: 1_789_096_800
            )
        )
    }

    func testLiveStagingSignedAssignmentAndRejectsTampering() throws {
        guard let clientToken = ProcessInfo.processInfo.environment["FFE_STAGING_CLIENT_TOKEN"] else {
            throw XCTSkip("FFE_STAGING_CLIENT_TOKEN is required for the live proof.")
        }
        let mode = ProcessInfo.processInfo.environment["FFE_STAGING_PROTECTION"] ?? "signed"
        let protection: Flags.AssignmentProtection
        let authorization: Flags.AssignmentAuthorization?
        switch mode {
        case "signed":
            protection = .signed
            authorization = nil
        case "signed-and-authorized":
            guard let accessJWT = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENT_JWT"] else {
                throw XCTSkip("FFE_STAGING_ASSIGNMENT_JWT is required for signed-and-authorized live proof.")
            }
            protection = .signedAndAuthorized
            authorization = .init(bearerToken: accessJWT, expiresAt: .distantFuture)
        default:
            throw XCTSkip("FFE_STAGING_PROTECTION must be signed or signed-and-authorized.")
        }
        let environment = ProcessInfo.processInfo.environment["FFE_STAGING_ENV"] ?? "staging"
        let endpoint = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENTS_ENDPOINT"]
            .flatMap(URL.init(string:))
            ?? URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments")
        featureScope.contextMock = .mockWith(
            site: .us1,
            clientToken: clientToken,
            env: environment,
            sdkVersion: "wargame"
        )
        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "signed-assignment-poc",
            attributes: [
                "user_id": .string("signed-assignment-poc"),
                "country": .string("US")
            ]
        )
        var capturedRequest: URLRequest?
        var capturedResponse: FetchedFlagAssignments?
        let session = URLSession(configuration: .ephemeral)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: endpoint,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: authorization,
                protection: protection
            ),
            fetch: { request, completion in
                capturedRequest = request
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard let data, let response = response as? HTTPURLResponse else {
                        completion(.failure(URLError(.badServerResponse)))
                        return
                    }
                    let fetched = FetchedFlagAssignments(data: data, response: response)
                    capturedResponse = fetched
                    completion(.success(fetched))
                }
                task.resume()
            },
            verify: SignedAssignmentVerifier.verify,
            makeNonce: SignedAssignmentVerifier.makeNonce
        )
        let completed = expectation(description: "live signed assignment response")
        var result: Result<VerifiedFlagAssignments, FlagsError>?
        fetcher.verifiedFlagAssignments(for: evaluationContext) {
            result = $0
            completed.fulfill()
        }

        waitForExpectations(timeout: 10)
        _ = try XCTUnwrap(result).get()
        let request = try XCTUnwrap(capturedRequest)
        let fetched = try XCTUnwrap(capturedResponse)
        XCTAssertEqual(fetched.response.statusCode, 200)

        var tamperedBody = fetched.data
        tamperedBody[tamperedBody.startIndex] ^= 1
        XCTAssertThrowsError(
            try SignedAssignmentVerifier.verify(
                request: request,
                fetched: FetchedFlagAssignments(data: tamperedBody, response: fetched.response),
                clientToken: clientToken,
                protection: protection,
                currentTime: Int64(Date().timeIntervalSince1970)
            )
        )
    }

    private func fetched(_ data: Data, requestURL: URL? = nil) -> FetchedFlagAssignments {
        let response = HTTPURLResponse(
            url: requestURL ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        return FetchedFlagAssignments(data: data, response: response)
    }

    private func assertProtectedRequestFailsBeforeNetwork(
        endpoint: URL,
        evaluationContext: FlagsEvaluationContext = .mockAny(),
        datadogContext: DatadogContext = .mockWith(
            site: .us1,
            clientToken: "client-token",
            env: "production",
            sdkVersion: "wargame"
        ),
        protection: Flags.AssignmentProtection = .signed,
        authorization: Flags.AssignmentAuthorization? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        featureScope.contextMock = datadogContext
        var didFetch = false
        var didMakeNonce = false
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: endpoint,
            customHeaders: nil,
            featureScope: featureScope,
            authorizationStore: AssignmentAuthorizationStore(
                initialAuthorization: authorization,
                protection: protection
            ),
            fetch: { _, completion in
                didFetch = true
                completion(.failure(URLError(.unknown)))
            },
            verify: { _, _, _, _, _ in Self.verificationMetadata },
            makeNonce: {
                didMakeNonce = true
                return "000102030405060708090a0b0c0d0e0f"
            }
        )
        let completed = expectation(description: "invalid protected request rejected")
        var result: Result<[String: FlagAssignment], FlagsError>?
        fetcher.flagAssignments(for: evaluationContext) {
            result = $0
            completed.fulfill()
        }

        waitForExpectations(timeout: 0)
        guard case .failure(.invalidConfiguration)? = result else {
            XCTFail("Expected invalid protected request configuration", file: file, line: line)
            return
        }
        XCTAssertFalse(didMakeNonce, file: file, line: line)
        XCTAssertFalse(didFetch, file: file, line: line)
    }

    private func fetchWithProtectedHTTPClient(
        dataSize: Int,
        declaredSize: Int?,
        maximumSize: Int
    ) throws -> Result<FetchedFlagAssignments, Error> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlagAssignmentsURLProtocolStub.self]
        let client = FlagAssignmentsHTTPClient(
            configuration: configuration,
            maximumResponseBytes: maximumSize
        )
        var request = URLRequest(url: URL(string: "https://example.test/precompute-assignments")!)
        request.setValue(String(dataSize), forHTTPHeaderField: "x-test-data-size")
        if let declaredSize {
            request.setValue(String(declaredSize), forHTTPHeaderField: "x-test-declared-size")
        }
        let completed = expectation(description: "protected transport completed")
        var result: Result<FetchedFlagAssignments, Error>?
        client.fetch(request) {
            result = $0
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        withExtendedLifetime(client) {}
        return try XCTUnwrap(result)
    }

    private static func vectorRequest(authorization: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = vectorRequestBody
        request.setValue("client-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "content-type")
        request.setValue("2", forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader)
        request.setValue(vectorNonce, forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader)
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func vectorResponse(
        requestURL: URL,
        policyVersion: String?,
        signature: String,
        rulesRevision: String? = "",
        certificate: String = vectorCertificate
    ) throws -> FetchedFlagAssignments {
        var headers = [
            "x-datadog-feature-flags-signature-version": "2",
            "x-datadog-feature-flags-issued-at": "1789096800",
            "x-datadog-feature-flags-expires-at": "1789097100",
            "x-datadog-feature-flags-certificate-id": vectorCertificateID,
            "x-datadog-feature-flags-signing-certificate": certificate,
            "x-datadog-feature-flags-signature": signature
        ]
        if let policyVersion {
            headers["x-datadog-feature-flags-authorization-policy-version"] = policyVersion
        }
        if let rulesRevision {
            headers["x-datadog-feature-flags-rules-revision"] = rulesRevision
        }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        ))
        return FetchedFlagAssignments(data: vectorResponseBody, response: response)
    }

    private static func vectorSignatureInput(
        request: URLRequest,
        policyVersion: String?
    ) throws -> Data {
        try SignedAssignmentVerifier.signatureInput(
            nonce: Data((0..<16).map(UInt8.init)),
            request: request,
            requestBody: vectorRequestBody,
            compactJWT: request.value(forHTTPHeaderField: "Authorization").map {
                String($0.dropFirst("Bearer ".count))
            },
            clientToken: "client-token",
            policyVersion: policyVersion,
            rulesRevision: "",
            responseStatus: 200,
            issuedAt: 1_789_096_800,
            expiresAt: 1_789_097_100,
            responseBody: vectorResponseBody
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let verificationMetadata = SignedAssignmentVerificationMetadata(
        certificateID: String(repeating: "a", count: 64),
        rulesRevision: "",
        issuedAt: 1_789_096_800,
        expiresAt: 1_789_097_100,
        authorizationPolicyVersion: nil
    )

    private static let vectorNonce = "000102030405060708090a0b0c0d0e0f"
    private static let vectorRequestBody = Data(#"{"data":{"attributes":{"subject":{"targeting_key":"user-1"}}}}"#.utf8)
    private static let vectorResponseBody = Data(#"{"data":{"id":"user-1"}}"#.utf8)
    private static let vectorCertificateID = "a0d868097393828703e0f9864e355a79b744df556d151249ce947157f08a0ff7"
    private static let vectorCertificate = "MIIBszCCAVqgAwIBAgIBZTAKBggqhkjOPQQDAjAzMTEwLwYDVQQDDChEYXRhZG9nIEZGRSBFZGdlIEFzc2lnbm1lbnRzIFBPQyBSb290IEsxMB4XDTI2MDkxMTAzMTgzMFoXDTI2MTIxMDAzMTgzMFowMjEwMC4GA1UEAwwnRGF0YWRvZyBGRkUgRWRnZSBBc3NpZ25tZW50cyBQT0MgTGVhZiBBMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEOAdt79MNq0/K82oozH9BifTCyu5pogz9VnCf69v6m5rIERSTO27L2SizPPI3ptfMBDa+bT/0wMdPc6GQYG4QeaNgMF4wDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPjCuJhWtNy/Ne+/6ZCIB8cmhFuJMB8GA1UdIwQYMBaAFHGtfswbRCOOchC6yZHakhktSdq4MAoGCCqGSM49BAMCA0cAMEQCIFvqYcK+OAaBdMRuMkSpOVscR1SMdCPt5LNdkQEZyvNCAiBq2rtg8F27nZ2mHyoAL4OT5tCMBKvYytpnRZzwMBYJTQ=="
    // Test-only scalar from the edge fixture. Runtime code never contains signing key material.
    private static let vectorPrivateKeyRaw = "6qcvKUwQlHOnjQSnt7U9S+AxMLXzd0ABH9TpRMFbNdM="
    private static let signedOnlySignature = "MEUCIBim8DaKFvPtvhHV5yjwyPWZgZVnpz6tkiAUzAOk3bTyAiEA3OsaJ3VjUP+o6iojyD5Fv7D4+9FDNUODiDDA3XUvze4="
    private static let signedAndAuthorizedSignature = "MEYCIQDAG5d1Edg2NhaMGfJiMTbjSmhYSsUS65ZbImV/3IeFwQIhAJjHs87OUC6Ni08YguV72YI8rAaT1ehn6da9gWLw7w+R"
    private static let compactJWT = "eyJhbGciOiJFUzI1NiIsImtpZCI6ImN1c3RvbWVyLTIwMjYtMDkiLCJ0eXAiOiJkYXRhZG9nLWZlYXR1cmUtZmxhZ3MtYWNjZXNzK2p3dCJ9.eyJzdWIiOiJ1c2VyLTEifQ.signature"
}

private final class FlagAssignmentsURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let dataSizeValue = request.value(forHTTPHeaderField: "x-test-data-size"),
              let dataSize = Int(dataSizeValue) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var headers: [String: String] = [:]
        if let declaredSize = request.value(forHTTPHeaderField: "x-test-declared-size") {
            headers["Content-Length"] = declaredSize
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if dataSize > 0 {
            client?.urlProtocol(self, didLoad: Data(repeating: 0x61, count: dataSize))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension PersistedSignedAssignmentPayload {
    func replacing(
        protection: Flags.AssignmentProtection? = nil,
        endpoint: URL? = nil,
        environment: String? = nil,
        subject: String? = nil,
        clientTokenSHA256: String? = nil,
        authorizationBinding: AssignmentAuthorizationBinding? = nil,
        requestBody: Data? = nil,
        requestHeaders: [String: String]? = nil,
        responseStatus: Int? = nil,
        responseBody: Data? = nil,
        responseHeaders: [String: String]? = nil,
        certificateID: String? = nil,
        rulesRevision: String? = nil,
        issuedAt: Date? = nil,
        expiresAt: Date? = nil
    ) -> PersistedSignedAssignmentPayload {
        PersistedSignedAssignmentPayload(
            protection: protection ?? self.protection,
            endpoint: endpoint ?? self.endpoint,
            environment: environment ?? self.environment,
            subject: subject ?? self.subject,
            clientTokenSHA256: clientTokenSHA256 ?? self.clientTokenSHA256,
            authorizationBinding: authorizationBinding ?? self.authorizationBinding,
            requestBody: requestBody ?? self.requestBody,
            requestHeaders: requestHeaders ?? self.requestHeaders,
            responseStatus: responseStatus ?? self.responseStatus,
            responseBody: responseBody ?? self.responseBody,
            responseHeaders: responseHeaders ?? self.responseHeaders,
            certificateID: certificateID ?? self.certificateID,
            rulesRevision: rulesRevision ?? self.rulesRevision,
            issuedAt: issuedAt ?? self.issuedAt,
            expiresAt: expiresAt ?? self.expiresAt
        )
    }
}
