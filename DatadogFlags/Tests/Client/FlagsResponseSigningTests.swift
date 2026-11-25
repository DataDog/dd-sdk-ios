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

final class FlagsResponseSigningTests: XCTestCase {
    func testObserveCacheRemainsBoundedAcrossContextsAndTrustScopes() throws {
        let store = SigningDataStoreSpy()
        let fetcher = SigningLifecycleFetcher(mode: .observe)
        func repository() -> FlagsRepository {
            FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: 100)),
                featureScope: FeatureScopeMock(dataStore: store),
                flagSelection: nil,
                initializationTimeout: nil
            )
        }
        let active = repository()
        for index in 0..<3 {
            fetcher.responseSigningCacheScope = "scope-\(index)"
            active.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject-\(index)")) { _ in }
            fetcher.completeVerified(index: index, expiry: 200)
            active.flush()
        }
        XCTAssertEqual(store.keys.count, 1)
        let restored = repository()
        XCTAssertNotNil(restored.flagAssignment(for: "flag"))
        restored.flush()
        fetcher.responseSigningCacheScope = "scope-0"
        let otherScope = repository()
        XCTAssertNil(otherScope.flagAssignment(for: "flag"))
        otherScope.flush()
        fetcher.responseSigningCacheScope = nil
        active.reset()
        active.flush()
        XCTAssertTrue(store.keys.isEmpty)
    }

    func testRequiredKeepsLatestContextWhenSignedCompletionsAreReordered() {
        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: 100)),
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil,
            experimentationOptOutMode: .immediate
        )
        defer { repository.flush() }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "a")) { _ in }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "b")) { _ in }
        fetcher.completeVerified(index: 1, expiry: 200)
        fetcher.completeVerified(index: 0, expiry: 200)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.context?.targetingKey, "b")
    }

    func testBundledStagingTrustIsBoundToExactHTTPSOrigin() throws {
        let configuration = Flags.ResponseSigningConfiguration(mode: .required)
        let accepted = [
            "https://preview.ff-cdn.datad0g.com/precompute-assignments",
            "https://PREVIEW.FF-CDN.DATAD0G.COM:443/precompute-assignments?dd_env=production"
        ]
        for endpoint in accepted {
            let roots = configuration.roots(for: URL(string: endpoint))
            XCTAssertEqual(roots.count, 1)
            XCTAssertEqual(
                SHA256.hash(data: try XCTUnwrap(roots.first)).map { String(format: "%02x", $0) }.joined(),
                "0e469f3cecc9cd51fd64373879636540512d56e99eecd70361c78b98c47ea934"
            )
            var request = URLRequest(url: try XCTUnwrap(URL(string: endpoint)))
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("test", forHTTPHeaderField: "dd-client-token")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            XCTAssertNoThrow(try FlagsResponseVerifier(configuration: configuration).prepare(request))
        }
        let rejected = [
            "https://preview.ff-cdn.datadoghq.com/precompute-assignments?dd_env=staging",
            "https://preview.ff-cdn.us3.datadoghq.com/precompute-assignments",
            "https://preview.ff-cdn.datad0g.com.attacker.test/precompute-assignments",
            "https://attacker-preview.ff-cdn.datad0g.com/precompute-assignments",
            "https://preview.ff-cdn.datad0g.com:444/precompute-assignments",
            "http://preview.ff-cdn.datad0g.com/precompute-assignments",
            "https://user@preview.ff-cdn.datad0g.com/precompute-assignments"
        ]
        for endpoint in rejected {
            XCTAssertTrue(configuration.roots(for: URL(string: endpoint)).isEmpty, endpoint)
            var request = URLRequest(url: try XCTUnwrap(URL(string: endpoint)))
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("test", forHTTPHeaderField: "dd-client-token")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            XCTAssertThrowsError(try FlagsResponseVerifier(configuration: configuration).prepare(request), endpoint)
        }
    }

    func testExplicitRootsReplaceBundledStagingTrust() throws {
        let root = try SigningChainFixture.root("root-a")
        let configuration = Flags.ResponseSigningConfiguration(mode: .required, trustedRootCertificates: [root])
        XCTAssertEqual(
            configuration.roots(for: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments")),
            [root]
        )
        XCTAssertEqual(Flags.ResponseSigningConfiguration().mode, .off)
    }

    // MARK: - Contract: opt-in, staging gate, pinned anchor and rotation

    private func capturedRequest(
        responseSigning: Flags.ResponseSigningConfiguration?,
        endpoint: URL? = nil
    ) throws -> (request: URLRequest, response: FlagAssignmentsResponse) {
        var captured: URLRequest?
        let fetch: (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void = { request, complete in
            captured = request
            complete(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
        }
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let fetcher: FlagAssignmentsFetcher
        if let responseSigning {
            fetcher = FlagAssignmentsFetcher(
                customEndpoint: endpoint,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                responseSigning: responseSigning,
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { _, _ in XCTFail("An opted-out client must not use the signing transport") },
                fetch: fetch
            )
        } else {
            fetcher = FlagAssignmentsFetcher(
                customEndpoint: endpoint,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                fetch: fetch
            )
        }
        let completed = expectation(description: "Fetched")
        var result: Result<FlagAssignmentsResponse, FlagsError>?
        fetcher.flagAssignments(for: .init(targetingKey: "subject")) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        return (try XCTUnwrap(captured), try XCTUnwrap(result).get())
    }

    /// The body encodes a dictionary, so compare decoded JSON instead of key order.
    private func jsonBody(_ request: URLRequest) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? NSDictionary)
    }

    func testOptedOutClientSendsTodaysRequestAndHandlesResponsesAsToday() throws {
        let today = try capturedRequest(responseSigning: nil)
        for configuration in [Flags.ResponseSigningConfiguration(), .init(mode: .off)] {
            let optedOut = try capturedRequest(responseSigning: configuration)
            XCTAssertEqual(optedOut.request.url, today.request.url)
            XCTAssertEqual(optedOut.request.httpMethod, today.request.httpMethod)
            XCTAssertEqual(try jsonBody(optedOut.request), try jsonBody(today.request))
            XCTAssertEqual(optedOut.request.allHTTPHeaderFields, today.request.allHTTPHeaderFields)
            XCTAssertEqual(optedOut.response.flags, today.response.flags)
            XCTAssertNil(optedOut.response.verification)
            XCTAssertNil(optedOut.response.responseSigningCacheScope)
        }
        let headers = today.request.allHTTPHeaderFields ?? [:]
        XCTAssertNil(today.request.value(forHTTPHeaderField: "X-stream"))
        XCTAssertFalse(headers.keys.contains { $0.lowercased().hasPrefix(FlagsResponseVerifier.prefix) })
        XCTAssertFalse(
            (today.request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
                .contains(FlagsResponseVerifier.capability)
        )

        // The default feature configuration installs no signing component.
        let feature = FlagsFeature(configuration: .init(), featureScope: FeatureScopeMock(), core: FeatureRegistrationCoreMock())
        XCTAssertEqual(feature.flagAssignmentsFetcher.responseSigningMode, .off)
        XCTAssertTrue(feature.messageReceiver is NOPFeatureMessageReceiver)
    }

    private let nonStagingEndpoints: [URL?] = [
        nil,
        URL(string: "https://preview.ff-cdn.datadoghq.com/precompute-assignments"),
        URL(string: "https://preview.ff-cdn.datadoghq.eu/precompute-assignments"),
        URL(string: "https://proxy.example.test/precompute-assignments"),
        URL(string: "https://attacker-preview.ff-cdn.datad0g.com/precompute-assignments"),
        URL(string: "http://preview.ff-cdn.datad0g.com/precompute-assignments")
    ]

    func testObserveOutsideStagingIsANoOpThatWarns() throws {
        for endpoint in nonStagingEndpoints {
            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }
            let configuration = Flags.ResponseSigningConfiguration(mode: .observe)
            XCTAssertEqual(configuration.effective(customFlagsEndpoint: endpoint).mode, .off, "\(String(describing: endpoint))")
            XCTAssertEqual(dd.logger.warnLogs.count, 1)
            XCTAssertTrue(dd.logger.errorLogs.isEmpty)
            let warning = try XCTUnwrap(dd.logger.warnLog?.message)
            XCTAssertTrue(warning.contains("supported only on the Datadog staging endpoint"))
            XCTAssertTrue(warning.contains("Production support comes in a later release"))
            XCTAssertTrue(warning.contains("flags are not verified"))
            let feature = FlagsFeature(
                configuration: .init(customFlagsEndpoint: endpoint, experimentalResponseSigning: configuration),
                featureScope: FeatureScopeMock(),
                core: FeatureRegistrationCoreMock()
            )
            XCTAssertEqual(feature.flagAssignmentsFetcher.responseSigningMode, .off)
            XCTAssertTrue(feature.messageReceiver is NOPFeatureMessageReceiver)
            // The gated configuration sends exactly the opted-out request.
            let gated = try capturedRequest(responseSigning: configuration.effective(customFlagsEndpoint: endpoint), endpoint: endpoint)
            let today = try capturedRequest(responseSigning: nil, endpoint: endpoint)
            XCTAssertEqual(gated.request.allHTTPHeaderFields, today.request.allHTTPHeaderFields)
            XCTAssertEqual(try jsonBody(gated.request), try jsonBody(today.request))
        }
        // An opted-out configuration logs nothing.
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        XCTAssertEqual(Flags.ResponseSigningConfiguration().effective(customFlagsEndpoint: nil).mode, .off)
        XCTAssertTrue(dd.logger.warnLogs.isEmpty)
        XCTAssertTrue(dd.logger.errorLogs.isEmpty)
    }

    func testRequiredOutsideStagingFailsClosedWithoutARequest() throws {
        for endpoint in nonStagingEndpoints {
            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }
            let configuration = Flags.ResponseSigningConfiguration(mode: .required)
            let feature = FlagsFeature(
                configuration: .init(customFlagsEndpoint: endpoint, experimentalResponseSigning: configuration),
                featureScope: FeatureScopeMock(),
                core: FeatureRegistrationCoreMock()
            )
            // One error at enable, with the staging-only guidance.
            XCTAssertEqual(dd.logger.errorLogs.count, 1, "\(String(describing: endpoint))")
            XCTAssertTrue(dd.logger.warnLogs.isEmpty)
            let message = try XCTUnwrap(dd.logger.errorLog?.message)
            XCTAssertTrue(message.contains("supported only on the Datadog staging endpoint"))
            XCTAssertTrue(message.contains("Production support comes in a later release"))
            XCTAssertTrue(message.contains("Remove `required`, or use `observe`"))
            XCTAssertEqual(feature.flagAssignmentsFetcher.responseSigningMode, .required)

            let effective = configuration.effective(customFlagsEndpoint: endpoint)
            XCTAssertEqual(effective.mode, .required)
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: endpoint,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
                responseSigning: effective,
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { _, _ in XCTFail("Required signing outside staging must not send a request") },
                fetch: { _, _ in XCTFail("Required signing outside staging must not send a request") }
            )
            // Every fetch returns the same error.
            for _ in 0..<2 {
                let done = expectation(description: "fetch")
                fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                    defer { done.fulfill() }
                    guard case .failure(.responseSigningFailed(reason: "unsupported-site")) = result else {
                        return XCTFail("Expected unsupported-site, got \(result)")
                    }
                }
                wait(for: [done], timeout: 1)
            }
            // The repository moves to its error state and serves no flags.
            let repository = FlagsRepository(
                clientName: "required-outside-staging",
                flagAssignmentsFetcher: fetcher,
                dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: 100)),
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil
            )
            let contextSet = expectation(description: "context")
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { result in
                defer { contextSet.fulfill() }
                guard case .failure(.responseSigningFailed(reason: "unsupported-site")) = result else {
                    return XCTFail("Expected unsupported-site, got \(result)")
                }
            }
            wait(for: [contextSet], timeout: 1)
            XCTAssertEqual(repository.state.currentState, .error)
            XCTAssertNil(repository.flagAssignments())
            repository.flush()
        }
    }

    func testSignedRequestMapsAssignmentAuthorizationRejection() throws {
        let staging = try XCTUnwrap(URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"))
        let body = Data(#"{"errors":[{"status":"401","code":"ASSIGNMENT_AUTHORIZATION_FAILED"}]}"#.utf8)
        for mode in [Flags.ResponseSigningMode.required, .observe] {
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: staging,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
                responseSigning: .init(mode: mode),
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, complete in
                    complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: [:])!)))
                },
                fetch: { _, _ in XCTFail("Signing must use the signing transport") }
            )
            let done = expectation(description: "\(mode)")
            fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                defer { done.fulfill() }
                guard case .failure(.assignmentAuthorizationFailed) = result else {
                    return XCTFail("\(mode): \(result)")
                }
            }
            wait(for: [done], timeout: 1)
        }
    }

    func testNoModeSendsXStream() throws {
        let staging = try XCTUnwrap(URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"))
        for mode in [Flags.ResponseSigningMode.off, .observe, .required] {
            var sent: [URLRequest] = []
            let reply: (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void = { request, complete in
                sent.append(request)
                complete(.success((.mockAnyFlagAssignmentsResponse(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)))
            }
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: staging,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
                responseSigning: .init(mode: mode),
                floorStore: InMemorySigningFloorStore(),
                signingFetch: reply,
                fetch: reply
            )
            let done = expectation(description: "fetch \(mode)")
            fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { _ in done.fulfill() }
            wait(for: [done], timeout: 1)
            XCTAssertEqual(sent.count, 1)
            for request in sent {
                XCTAssertFalse((request.allHTTPHeaderFields ?? [:]).keys.contains { $0.lowercased() == "x-stream" }, "\(mode)")
            }
        }
    }

    func testOptInOnStagingSendsTheSigningRequest() throws {
        let staging = try XCTUnwrap(URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"))
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }
            let configuration = Flags.ResponseSigningConfiguration(mode: mode)
            XCTAssertEqual(configuration.effective(customFlagsEndpoint: staging).mode, mode)
            XCTAssertTrue(dd.logger.warnLogs.isEmpty)
            let feature = FlagsFeature(
                configuration: .init(customFlagsEndpoint: staging, experimentalResponseSigning: configuration),
                featureScope: FeatureScopeMock(),
                core: FeatureRegistrationCoreMock()
            )
            XCTAssertEqual(feature.flagAssignmentsFetcher.responseSigningMode, mode)
            XCTAssertTrue(feature.messageReceiver is FlagsSigningScopeReceiver)
        }
        var request = URLRequest(url: staging)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .required))
        let first = try verifier.prepare(request)
        let second = try verifier.prepare(request)
        XCTAssertNil(first.value(forHTTPHeaderField: "X-stream"))
        XCTAssertEqual(first.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities"), "response-signing-v1")
        XCTAssertEqual(first.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version"), "1")
        // The SDK lists each bound header that it set, in ascending byte order.
        XCTAssertEqual(
            first.value(forHTTPHeaderField: FlagsResponseVerifier.signedHeadersName),
            "content-type,x-dd-feature-flags-capabilities"
        )
        request.setValue("rum-app", forHTTPHeaderField: "dd-application-id")
        // `x-use-cache` is a staging header, not a bound header, so the SDK does not list it.
        request.setValue("true", forHTTPHeaderField: "x-use-cache")
        XCTAssertEqual(
            try verifier.prepare(request).value(forHTTPHeaderField: FlagsResponseVerifier.signedHeadersName),
            "content-type,dd-application-id,x-dd-feature-flags-capabilities"
        )
        // `content-type` is a required name, so a request without it is not signed.
        request.setValue(nil, forHTTPHeaderField: "content-type")
        XCTAssertThrowsError(try verifier.prepare(request)) {
            XCTAssertEqual($0 as? FlagsSigningError, .unsupportedRequest)
        }
        let nonce = try XCTUnwrap(first.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "request-nonce"))
        XCTAssertNotNil(nonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
        XCTAssertNotEqual(nonce, second.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "request-nonce"))
        XCTAssertNil(first.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signing-intermediate"))
    }

    func testStagingRootIsTheOnlyBuiltInAnchorAndAnchorsTheStagingIntermediate() throws {
        let staging = URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments")
        let builtIn = Flags.ResponseSigningConfiguration(mode: .required).roots(for: staging)
        XCTAssertEqual(builtIn, [Flags.ResponseSigningConfiguration.stagingRoot])
        let root = try FlagsSigningCertificate(der: Flags.ResponseSigningConfiguration.stagingRoot, role: .anchor)
        XCTAssertEqual(root.pathLength, 2)
        XCTAssertEqual(
            root.subjectKeyID.map { $0.map { String(format: "%02x", $0) }.joined() },
            "aa5e91e52cdb130d175eed1010a501c0ef45d60d"
        )
        // The us1 staging DC intermediate, index 1 in the served chain, chains to the built-in root.
        let intermediate = try FlagsSigningCertificate(der: SigningChainFixture.root("staging-us1-dc-intermediate"), role: .intermediate)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(intermediate.pathLength), 1)
        XCTAssertNoThrow(try FlagsResponseVerifier.verifyChild(intermediate, parent: root))
        // A test root never anchors the staging intermediate.
        let other = try FlagsSigningCertificate(der: SigningChainFixture.root("root-a"), role: .anchor)
        XCTAssertThrowsError(try FlagsResponseVerifier.verifyChild(intermediate, parent: other))
    }

    func testRotatedLeavesAndIntermediatesUnderOneRootAllVerifyWithoutPinning() throws {
        // Previous, current and next leaves rotate on the server. One verifier must accept every valid leaf under
        // the pinned root, in any order, without remembering an earlier leaf or intermediate.
        let anchor = try SigningChainFixture.root("root-a")
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .required, trustedRootCertificates: [anchor]))
        let body = Data.mockAnyFlagAssignmentsResponse()
        let now = Date(timeIntervalSince1970: SigningChainFixture.now)
        let sequence = ["two-intermediates", "rotated-lower-intermediate", "one-intermediate", "two-intermediates", "rotated-lower-intermediate"]
        var leaves = Set<Data>()
        var lowerIntermediates = Set<Data>()
        for name in sequence {
            var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            let prepared = try verifier.prepare(request)
            let fixture = try SigningChainFixture.credential(name)
            leaves.insert(fixture.leaf)
            lowerIntermediates.insert(try XCTUnwrap(fixture.intermediates.first))
            let response = try response(prepared, fixture.signedHeaders(request: prepared, body: body))
            XCTAssertNoThrow(try verifier.verify(request: prepared, response: response, body: body, now: now), name)
        }
        XCTAssertEqual(leaves.count, 3)
        XCTAssertGreaterThanOrEqual(lowerIntermediates.count, 2)
    }

    /// At cutover the staging edge can serve unsigned 200 responses until the rotator republishes the credential.
    /// `observe` accepts the unverified response and reports `missingProof`. `required` fails closed and never retries unsigned.
    func testUnsignedStagingResponseAtCutoverByMode() throws {
        let staging = try XCTUnwrap(URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"))
        let body = Data.mockAnyFlagAssignmentsResponse()
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
            var signedRequests = 0
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: staging,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                responseSigning: .init(mode: mode),
                dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now)),
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, complete in
                    signedRequests += 1
                    XCTAssertTrue(
                        (request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
                            .split(separator: ",").contains("response-signing-v1")
                    )
                    XCTAssertNil(request.value(forHTTPHeaderField: "X-stream"))
                    // An ordinary 200 with no proof headers.
                    let response = HTTPURLResponse(url: staging, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
                    complete(.success((body, response)))
                },
                fetch: { _, _ in XCTFail("Signing never retries with an unsigned request") }
            )
            let completed = expectation(description: "Unsigned cutover response")
            var result: Result<FlagAssignmentsResponse, FlagsError>?
            fetcher.flagAssignments(for: .init(targetingKey: "subject")) {
                result = $0
                completed.fulfill()
            }
            wait(for: [completed], timeout: 2)
            XCTAssertEqual(signedRequests, 1)
            let reports = scope.telemetryMock.messages.compactMap { message -> String? in
                guard case let .debug(id, text, _) = message, text == "flags.response_signing" else {
                    return nil
                }
                return id
            }
            XCTAssertEqual(reports, ["flags.response_signing:\(mode):unverified:missing-proof"], "\(mode)")
            switch (mode, try XCTUnwrap(result)) {
            case (.observe, .success(let response)):
                XCTAssertFalse(response.flags.isEmpty)
                XCTAssertNil(response.verification, "An unsigned response is never verified")
            case (.required, .failure(.responseSigningFailed(reason: "missing-proof"))):
                break
            default:
                XCTFail("Unexpected \(mode) outcome: \(String(describing: result))")
            }
        }
    }

    private struct Corpus: Decodable {
        let anchor_der_base64: String
        let cases: [Vector]
    }
    private struct Vector: Decodable {
        struct Request: Decodable {
            let url: String
            let method: String
            let headers: [[String]]
            let body_base64: String
        }
        struct Response: Decodable {
            let status: Int
            let headers: [[String]]
            let body_base64: String
        }
        let id: String
        let request: Request
        let response: Response
        let now: TimeInterval
        let expected_accept: Bool
        let transcript_base64: String?
        /// Optional per-case root. It replaces the file anchor for this case only.
        let anchor_der_base64: String?
        /// The shared reason code of a rejected case. All SDKs report the same code.
        let sdk_reason: String?
        /// The values of the signed response list of an accepted case, in list order. `nil` is an absent header.
        let verified_response_headers: [String: String?]?
    }

    private func corpus(name: String, hash: String) throws -> Corpus {
        let url = try SharedSigningFixtures.url("response-signing-v1", name, "json")
        let raw = try Data(contentsOf: url)
        XCTAssertEqual(SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(), hash, name)
        return try JSONDecoder().decode(Corpus.self, from: raw)
    }

    private func headers(_ pairs: [[String]]) -> [String: String] {
        pairs.reduce(into: [:]) { result, pair in
            let name = pair[0].lowercased()
            result[name] = result[name].map { $0 + ", " + pair[1] } ?? pair[1]
        }
    }

    /// Runs every verifier case of every suite in the pinned ffe-system-test-data manifest.
    /// Clients skip `signing_cases`, because they hold no signing keys.
    func testCentralManifestSuitesAndExactTranscripts() throws {
        struct Manifest: Decodable {
            struct Suite: Decodable {
                let sha256: String
                let response_cases: Int
                let accepted: Int
            }
            let schema_version: Int
            let files: [String: Suite]
        }
        let url = try SharedSigningFixtures.url("response-signing-v1", "manifest", "json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        XCTAssertEqual(manifest.schema_version, 1)
        XCTAssertFalse(manifest.files.isEmpty)
        var executed = 0
        for name in manifest.files.keys.sorted() {
            let suite = try XCTUnwrap(manifest.files[name])
            let corpus = try corpus(name: String(name.dropLast(5)), hash: suite.sha256)
            XCTAssertEqual(corpus.cases.count, suite.response_cases, name)
            XCTAssertEqual(corpus.cases.filter(\.expected_accept).count, suite.accepted, name)
            executed += try assertCorpus(corpus, suite: name)
        }
        XCTAssertEqual(executed, manifest.files.values.map(\.response_cases).reduce(0, +))
    }

    /// F16: a leaf that spans exactly 432300 s verifies, and a leaf that spans 432301 s is an invalid certificate.
    func testLeafLifetimeBoundaryVectors() throws {
        let url = try SharedSigningFixtures.url("response-signing-v1", "corpus", "json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(FlagsResponseVerifier.maximumLeafLifetime, 432_300)
        for (id, accept) in [("valid-leaf-lifetime-at-limit", true), ("leaf-lifetime-over-limit", false)] {
            let vector = try XCTUnwrap(corpus.cases.first { $0.id == id }, id)
            XCTAssertEqual(vector.expected_accept, accept, id)
            XCTAssertEqual(try assertCorpus(Corpus(anchor_der_base64: corpus.anchor_der_base64, cases: [vector]), suite: id), 1)
        }
    }

    /// The empty query binds as `?`, and a high-S ECDSA signature is accepted (no low-S rule).
    func testSharedEmptyQueryAndHighSSignatureVectorsAreAccepted() throws {
        let url = try SharedSigningFixtures.url("response-signing-v1", "corpus", "json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        for id in ["valid-empty-query", "valid-high-s-signature"] {
            let vector = try XCTUnwrap(corpus.cases.first { $0.id == id }, id)
            XCTAssertTrue(vector.expected_accept, id)
            if id == "valid-empty-query" {
                XCTAssertTrue(vector.request.url.hasSuffix("?"), id)
            }
            XCTAssertEqual(try assertCorpus(Corpus(anchor_der_base64: corpus.anchor_der_base64, cases: [vector]), suite: id), 1)
        }
    }

    private func assertCorpus(_ corpus: Corpus, suite: String) throws -> Int {
        var executed = 0
        for vector in corpus.cases {
            let name = "\(suite)/\(vector.id)"
            try XCTContext.runActivity(named: name) { _ in
                let anchor = try XCTUnwrap(Data(base64Encoded: vector.anchor_der_base64 ?? corpus.anchor_der_base64))
                let verifier = FlagsResponseVerifier(
                    configuration: .init(mode: .required, trustedRootCertificates: [anchor])
                )
                var request = URLRequest(url: try XCTUnwrap(URL(string: vector.request.url)))
                request.httpMethod = vector.request.method
                request.httpBody = try XCTUnwrap(Data(base64Encoded: vector.request.body_base64))
                for (name, value) in headers(vector.request.headers) {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                let responseHeaders = headers(vector.response.headers)
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: vector.response.status,
                        httpVersion: "HTTP/1.1",
                        headerFields: responseHeaders
                    )
                )
                let body = try XCTUnwrap(Data(base64Encoded: vector.response.body_base64))
                let now = Date(timeIntervalSince1970: vector.now)
                if vector.expected_accept {
                    let proof = try verifier.verify(request: request, response: response, body: body, now: now)
                    XCTAssertEqual(proof.verifiedAt, vector.now, name)
                    XCTAssertEqual(proof.verifiedResponseHeaders, try XCTUnwrap(vector.verified_response_headers, name), name)
                    let prefix = FlagsResponseVerifier.prefix
                    let listed = try XCTUnwrap(responseHeaders[prefix + "signed-response-headers"], name)
                        .split(separator: ",").map { ($0.description, responseHeaders[$0.description]) }
                    let chain = try XCTUnwrap(responseHeaders[prefix + "signing-chain"], name)
                        .split(separator: ",").map { try XCTUnwrap(Data(base64Encoded: String($0))) }
                    let transcript = try FlagsResponseVerifier.transcript(
                        request: request,
                        status: response.statusCode,
                        body: body,
                        issuedAt: try XCTUnwrap(UInt64(XCTUnwrap(responseHeaders[prefix + "issued-at"]))),
                        expiresAt: try XCTUnwrap(UInt64(XCTUnwrap(responseHeaders[prefix + "expires-at"]))),
                        leaf: try XCTUnwrap(Data(base64Encoded: XCTUnwrap(responseHeaders[prefix + "signing-certificate"]))),
                        intermediates: chain,
                        responseHeaders: listed
                    )
                    XCTAssertEqual(transcript.base64EncodedString(), vector.transcript_base64, name)
                } else {
                    // `rejection_reason` is a fixture code. `sdk_reason` is the shared SDK reason code.
                    let expected = try XCTUnwrap(vector.sdk_reason, "\(name) has no sdk_reason")
                    XCTAssertThrowsError(try verifier.verify(request: request, response: response, body: body, now: now), name) {
                        XCTAssertEqual(($0 as? FlagsSigningError)?.rawValue, expected, name)
                    }
                }
                executed += 1
            }
        }
        XCTAssertEqual(executed, corpus.cases.count, suite)
        return executed
    }

    /// X.690 11.2.2: a DER named bit list removes trailing zero bits. A leaf keyUsage with an extra zero octet
    /// (`03 03 07 80 00`) is not the canonical `03 02 07 80`, so the leaf is rejected.
    /// This replaces the removed single-intermediate `ResponseSigningKeyUsage.json` supplement.
    func testLeafKeyUsageMustBeCanonicalNamedBitList() throws {
        let leaf = try SigningChainFixture.credential("two-intermediates").leaf
        XCTAssertNoThrow(try FlagsSigningCertificate(der: leaf, role: .leaf))
        func tlv(_ tag: UInt8, _ content: Data) -> Data {
            var length = Data()
            var count = content.count
            if count < 128 {
                length.append(UInt8(count))
            } else {
                var bytes: [UInt8] = []
                while count > 0 { bytes.insert(UInt8(count & 255), at: 0); count >>= 8 }
                length.append(128 | UInt8(bytes.count))
                length.append(contentsOf: bytes)
            }
            return Data([tag]) + length + content
        }
        func rebuild(_ node: FlagsSigningDER, _ transform: (FlagsSigningDER) -> Data?) -> Data {
            if let replaced = transform(node) {
                return replaced
            }
            guard !node.children.isEmpty else {
                return node.raw
            }
            return tlv(node.tag, node.children.map { rebuild($0, transform) }.reduce(Data(), +))
        }
        let keyUsage = Data([6, 3, 85, 29, 15])
        let mutated = rebuild(try FlagsSigningDER.parse(leaf)) { node in
            guard node.tag == 48, node.children.first?.raw == keyUsage, let value = node.children.last else {
                return nil
            }
            XCTAssertEqual(value.content, Data([3, 2, 7, 128]))
            let items = node.children.dropLast().map(\.raw) + [tlv(4, Data([3, 3, 7, 128, 0]))]
            return tlv(48, items.reduce(Data(), +))
        }
        XCTAssertNotEqual(mutated, leaf)
        XCTAssertThrowsError(try FlagsSigningCertificate(der: mutated, role: .leaf))
        // The rebuild itself is exact: an identity transform returns the original bytes.
        XCTAssertEqual(rebuild(try FlagsSigningDER.parse(leaf)) { _ in nil }, leaf)
    }

    func testRequiredNeedsAnExplicitAnchorAndObserveDoesNotInventOne() throws {
        var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("test", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        XCTAssertThrowsError(try FlagsResponseVerifier(configuration: .init(mode: .required)).prepare(request))
        let observing = FlagsResponseVerifier(configuration: .init(mode: .observe))
        let prepared = try observing.prepare(request)
        XCTAssertEqual(prepared.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version"), "1")
        XCTAssertNotEqual(
            try observing.prepare(request).value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "request-nonce"),
            prepared.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "request-nonce")
        )
    }

    func testProofCannotBeRestoredFromOrdinaryPersistence() throws {
        var data = FlagsData(flags: ["flag": .mockAnyBoolean()], context: .mockAny(), date: Date())
        data.verification = .init(scope: UUID(), verifiedAt: 1, expiresAt: 300)
        let encoded = try JSONEncoder().encode(data)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("verification"))
        XCTAssertNil(try JSONDecoder().decode(FlagsData.self, from: encoded).verification)
    }

    func testActualFetcherUsesEffectiveRequestAndNativeCryptoBeforeAdmission() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
        let anchor = try SigningChainFixture.root("root-a")
        let responseBody = Data.mockAnyFlagAssignmentsResponse()
        let scope = FeatureScopeMock()
        var validProof = true
        let done = expectation(description: "verified before fetch completion")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://flags.example.test/assign?dd_env=prod&x=a%2Fb"),
            customHeaders: ["dd-client-token": "effective-override"],
            flagSelection: nil,
            featureScope: scope,
            responseSigning: .init(mode: .required, trustedRootCertificates: [anchor]),
            dateProvider: clock,
            floorStore: InMemorySigningFloorStore(),
            signingFetch: { request, completion in
                do {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "dd-client-token"), "effective-override")
                    let headers = try fixture.signedHeaders(request: request, body: responseBody)
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: validProof ? headers : [:]
                    )!
                    completion(.success((responseBody, response)))
                } catch { completion(.failure(error)) }
            },
            fetch: { _, _ in XCTFail("required must never retry unsigned") }
        )
        fetcher.flagAssignments(for: .mockAny()) { result in
            switch result {
            case .success(let response): XCTAssertTrue(fetcher.isVerified(response.verification, at: clock.now))
            case .failure(let error): XCTFail("\(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        validProof = false
        for _ in 0..<2 {
            let rejected = expectation(description: "unsigned response rejected")
            fetcher.flagAssignments(for: .mockAny()) { result in
                if case .success = result { XCTFail("Required must reject missing proof") }
                rejected.fulfill()
            }
            wait(for: [rejected], timeout: 2)
        }
        let reports = scope.telemetryMock.messages.compactMap { message -> String? in
            guard case let .debug(id, text, _) = message, text == "flags.response_signing" else {
                return nil
            }
            return id
        }
        // required reports failures only. Both failures have the same id, so RUM keeps one for each session.
        XCTAssertEqual(reports, Array(repeating: "flags.response_signing:required:unverified:missing-proof", count: 2))
    }

    func testFetcherModesAndRedirectFailures() throws {
        for mode in [Flags.ResponseSigningMode.off, .observe, .required] {
            for redirected in [false, true] {
                let anchor = try SigningChainFixture.root("root-a")
                let done = expectation(description: "mode completion")
                var signedCalls = 0
                var ordinaryCalls = 0
                let fetcher = FlagAssignmentsFetcher(
                    customEndpoint: nil,
                    customHeaders: nil,
                    flagSelection: nil,
                    featureScope: FeatureScopeMock(),
                    responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                    floorStore: InMemorySigningFloorStore(),
                    signingFetch: { request, completion in
                        signedCalls += 1
                        XCTAssertNil(request.value(forHTTPHeaderField: "X-stream"))
                        let url = redirected ? URL(string: "https://unexpected.example.test/")! : request.url!
                        completion(
                            .success(
                                (
                                    .mockAnyFlagAssignmentsResponse(),
                                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
                                )
                            )
                        )
                    },
                    fetch: { request, completion in
                        ordinaryCalls += 1
                        XCTAssertNil(request.value(forHTTPHeaderField: "X-stream"))
                        XCTAssertNil(
                            request.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version")
                        )
                        completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
                    }
                )
                fetcher.flagAssignments(for: .mockAny()) { result in
                    switch result {
                    case .success(let response):
                        XCTAssertTrue(mode == .off || (mode == .observe && !redirected))
                        XCTAssertNil(response.verification)
                    case .failure:
                        XCTAssertTrue(mode == .required || (mode == .observe && redirected))
                    }
                    done.fulfill()
                }
                wait(for: [done], timeout: 2)
                XCTAssertEqual(ordinaryCalls, mode == .off ? 1 : 0)
                XCTAssertEqual(signedCalls, mode == .off ? 0 : 1)
            }
        }
    }

    func testRequiredMemoryExpiresAndCannotCrossContextOrRestart() {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        let context = FlagsEvaluationContext(targetingKey: "one")
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        clock.now = Date(timeIntervalSince1970: 200)
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertNil(repository.flagAssignments())
        clock.now = Date(timeIntervalSince1970: 150)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "two")) { _ in }
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        fetcher.completions[1](.failure(.invalidResponse))
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        let restarted = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { restarted.flush() }
        XCTAssertNil(restarted.flagAssignment(for: "flag"))
    }

    func testRequiredSkipsDiskAndRejectsUnverifiedForeignOrExpiredProofs() {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let store = SigningDataStoreSpy()
        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        XCTAssertEqual(store.reads, 0)
        let context = FlagsEvaluationContext(targetingKey: "same")
        let proofs: [FlagsResponseVerification?] = [
            nil,
            .init(scope: UUID(), verifiedAt: 90, expiresAt: 200),
            .init(scope: fetcher.scope, verifiedAt: 90, expiresAt: 100)
        ]
        for (index, proof) in proofs.enumerated() {
            repository.setEvaluationContext(context) { result in
                guard case .failure = result else {
                    return XCTFail("invalid proof admitted")
                }
            }
            var response = FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()])
            response.verification = proof
            response.verification?.cacheScope = fetcher.responseSigningCacheScope
            response.responseSigningCacheScope = fetcher.responseSigningCacheScope
            fetcher.completions[index](.success(response))
            XCTAssertNil(repository.flagAssignment(for: "flag"))
        }
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 3, expiry: 200)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        repository.flush()
        XCTAssertEqual(store.writes, 0)
        repository.reset()
        repository.flush()
        XCTAssertEqual(store.removals, 0)
    }

    func testRequiredRejectionPersistsNothingAndRestartLoadsNoUnverifiedFlags() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let anchor = try SigningChainFixture.root("root-a")
        let body = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()]))
        let tampered = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean(), "extra": .mockAnyBoolean()]))
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
        let store = SigningDataStoreSpy()
        let context = FlagsEvaluationContext(targetingKey: "same")

        // An earlier unsigned client left flags on disk under the same client name.
        let unsigned = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()])))
            },
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
            flagSelection: nil,
            initializationTimeout: nil
        )
        unsigned.setEvaluationContext(context) { _ in }
        unsigned.flush()
        XCTAssertEqual(store.writes, 1)
        let seededKeys = store.keys
        let seededReads = store.reads

        func requiredRepository() -> FlagsRepository {
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(dataStore: store),
                responseSigning: .init(mode: .required, trustedRootCertificates: [anchor]),
                dateProvider: clock,
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, completion in
                    do {
                        // The proof signs `body`, but the edge returns other bytes.
                        let headers = try fixture.signedHeaders(request: request, body: body)
                        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
                        completion(.success((tampered, response)))
                    } catch { completion(.failure(error)) }
                },
                fetch: { _, _ in XCTFail("must not retry unsigned") }
            )
            return FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(dataStore: store),
                flagSelection: nil,
                initializationTimeout: nil
            )
        }

        let repository = requiredRepository()
        let rejected = expectation(description: "required rejects the response")
        repository.setEvaluationContext(context) { result in
            guard case .failure(.responseSigningFailed) = result else {
                return XCTFail("required admitted an invalid response: \(result)")
            }
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 2)
        repository.flush()
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertNil(repository.flagAssignments())
        XCTAssertEqual(store.writes, 1, "required wrote flag data after a rejection")
        XCTAssertEqual(store.keys, seededKeys)

        let restarted = requiredRepository()
        defer { restarted.flush() }
        XCTAssertNil(restarted.flagAssignment(for: "flag"))
        XCTAssertNil(restarted.flagAssignments())
        XCTAssertEqual(store.reads - store.signingFloorReads, seededReads, "required read the unverified disk cache")
    }

    func testRequiredResetAndNewContextRejectLateVerifiedCallbacks() {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        repository.setEvaluationContext(.init(targetingKey: "old")) { _ in }
        repository.setEvaluationContext(.init(targetingKey: "new")) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        repository.reset()
        fetcher.completeVerified(index: 1, expiry: 200)
        XCTAssertNil(repository.flagAssignment(for: "flag"))
    }

    func testFeatureLifetimeReleaseInvalidatesRetainedCachePendingCallbackAndFutureRequests() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let anchor = try SigningChainFixture.root("root-a")
        let body = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()]))
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
            let first = expectation(description: "first verified response")
            let started = expectation(description: "second response waiting")
            let stopped = expectation(description: "late completion rejected")
            var calls = 0
            var pending: (() -> Void)?
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(),
                responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                dateProvider: clock,
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, completion in
                    do {
                        calls += 1
                        let headers = try fixture.signedHeaders(request: request, body: body)
                        let response = HTTPURLResponse(
                            url: request.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: headers
                        )!
                        if calls == 1 {
                            completion(.success((body, response)))
                        } else {
                            pending = { completion(.success((body, response))) }
                            started.fulfill()
                        }
                    } catch { completion(.failure(error)) }
                },
                fetch: { _, _ in XCTFail("must not retry unsigned") }
            )
            var lifetime: FlagsSigningLifetime? = FlagsSigningLifetime(fetcher: fetcher)
            let repository = FlagsRepository(
                clientName: "retained",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil
            )
            defer { repository.flush() }
            let context = FlagsEvaluationContext(targetingKey: "same")
            repository.setEvaluationContext(context) { result in
                if case .failure(let error) = result { XCTFail("\(error)") }
                first.fulfill()
            }
            wait(for: [first], timeout: 2)
            XCTAssertNotNil(repository.flagAssignment(for: "flag"))
            repository.setEvaluationContext(context) { result in
                guard case .failure(.clientNotInitialized) = result else {
                    XCTFail("stopped feature admitted a pending response")
                    stopped.fulfill()
                    return
                }
                stopped.fulfill()
            }
            wait(for: [started], timeout: 2)
            XCTAssertNotNil(lifetime)
            lifetime = nil
            XCTAssertNil(fetcher.responseSigningCacheScope)
            XCTAssertNil(repository.flagAssignment(for: "flag"))
            XCTAssertNil(repository.flagAssignments())
            XCTAssertNil(fetcher.updateResponseSigningCacheScope(.mockWith(clientToken: "late", env: "late")))
            try XCTUnwrap(pending)()
            wait(for: [stopped], timeout: 2)
            XCTAssertNil(repository.flagAssignment(for: "flag"))
            let future = expectation(description: "future call fails locally")
            repository.setEvaluationContext(context) { result in
                guard case .failure(.clientNotInitialized) = result else {
                    XCTFail("stopped feature started a new request")
                    future.fulfill()
                    return
                }
                future.fulfill()
            }
            wait(for: [future], timeout: 2)
            XCTAssertEqual(calls, 2)
        }
    }

    func testLifetimeInvalidationDoesNotChangeOffTransport() {
        let done = expectation(description: "ordinary transport")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            fetch: { _, completion in completion(.success((.mockAnyFlagAssignmentsResponse(), .mockAny()))) }
        )
        fetcher.invalidateResponseSigningLifetime()
        fetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testSigningScopeSeparatesEveryIdentityAndConfigurationInput() {
        var request = URLRequest(url: URL(string: "https://example.test/assign?dd_env=prod")!)
        request.setValue("token-a", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .observe, trustedRootCertificates: [Data([1])]))
        func scope(_ value: URLRequest, environment: String = "prod") -> String {
            verifier.cacheScope(request: value, environment: environment, customHeaderNames: ["x-custom"])
        }
        let original = scope(request)
        XCTAssertNotEqual(original, scope(request, environment: "staging"))
        for (header, value) in [
            ("dd-client-token", "token-b"), ("authorization", "Bearer test"), ("x-custom", "new")
        ] {
            var changed = request
            changed.setValue(value, forHTTPHeaderField: header)
            XCTAssertNotEqual(original, scope(changed), header)
        }
        // RUM can start, stop or change during a session, so the application ID is not in the scope.
        var withApplicationID = request
        withApplicationID.setValue("app-b", forHTTPHeaderField: "dd-application-id")
        XCTAssertEqual(original, scope(withApplicationID))
        var changed = request
        changed.url = URL(string: "https://other.example.test/assign?dd_env=prod")!
        XCTAssertNotEqual(original, scope(changed))
        for config in [
            Flags.ResponseSigningConfiguration(mode: .required, trustedRootCertificates: [Data([1])]),
            .init(mode: .observe, trustedRootCertificates: [Data([2])])
        ] {
            XCTAssertNotEqual(
                original,
                FlagsResponseVerifier(configuration: config).cacheScope(
                    request: request,
                    environment: "prod",
                    customHeaderNames: ["x-custom"]
                )
            )
        }
    }

    func testSigningCacheScopeIncludesFlagSelection() {
        let context = DatadogContext.mockWith(clientToken: "token", env: "staging")
        func scope(_ selection: CanonicalFlagSelection?) -> String? {
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: selection,
                featureScope: FeatureScopeMock(),
                responseSigning: .init(mode: .observe),
                floorStore: InMemorySigningFloorStore(),
                fetch: { _, _ in XCTFail("no network expected") }
            )
            return fetcher.updateResponseSigningCacheScope(context)
        }
        let unselected = scope(nil)
        let selected = scope(CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []))
        XCTAssertNotNil(unselected)
        XCTAssertNotNil(selected)
        XCTAssertNotEqual(unselected, selected)
        XCTAssertNotEqual(selected, scope(CanonicalFlagSelection(tags: ["web"], keyPatterns: [])))
    }

    func testCoreScopeMessagesUpdateNamespaceBeforeNextRequest() {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            responseSigning: .init(mode: .observe),
            floorStore: InMemorySigningFloorStore(),
            fetch: { _, _ in XCTFail("no network expected") }
        )
        let receiver = FlagsSigningScopeReceiver(fetcher: fetcher)
        let core = PassthroughCoreMock()
        let initial = DatadogContext.mockWith(
            clientToken: "token",
            env: "prod",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "app-a")]
        )
        XCTAssertTrue(receiver.receive(message: .context(initial), from: core))
        let original = fetcher.responseSigningCacheScope
        XCTAssertNotNil(original)
        let changed = DatadogContext.mockWith(
            clientToken: "token",
            env: "staging",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "app-a")]
        )
        XCTAssertTrue(receiver.receive(message: .context(changed), from: core))
        XCTAssertNotEqual(original, fetcher.responseSigningCacheScope)
    }

    // MARK: - The signing scope does not include RUM

    func testRUMStartStopAndApplicationIDChangeDoNotChangeTheSigningScope() {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            responseSigning: .init(mode: .required),
            floorStore: InMemorySigningFloorStore(),
            fetch: { _, _ in XCTFail("no network expected") }
        )
        let receiver = FlagsSigningScopeReceiver(fetcher: fetcher)
        let core = PassthroughCoreMock()
        func context(_ rum: RUMCoreContext?) -> DatadogContext {
            .mockWith(clientToken: "token", env: "staging", additionalContext: rum.map { [$0] } ?? [])
        }
        // Flags starts without RUM.
        XCTAssertTrue(receiver.receive(message: .context(context(nil)), from: core))
        let original = fetcher.responseSigningCacheScope
        XCTAssertNotNil(original)
        let changes: [(String, RUMCoreContext?)] = [
            ("RUM starts after init", .mockWith(applicationID: "app-a", sessionID: UUID())),
            ("the RUM session changes", .mockWith(applicationID: "app-a", sessionID: UUID())),
            ("the RUM application ID changes", .mockWith(applicationID: "app-b", sessionID: UUID())),
            ("RUM stops", nil),
        ]
        for (name, rum) in changes {
            XCTAssertTrue(receiver.receive(message: .context(context(rum)), from: core))
            XCTAssertEqual(fetcher.responseSigningCacheScope, original, name)
        }
    }

    func testRUMApplicationIDChangeDuringAFetchKeepsTheVerifiedResponse() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
        let anchor = try SigningChainFixture.root("root-a")
        let body = Data.mockAnyFlagAssignmentsResponse()
        let appA = DatadogContext.mockWith(
            clientToken: "token",
            env: "staging",
            source: "ios",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "app-a")]
        )
        let appB = DatadogContext.mockWith(
            clientToken: "token",
            env: "staging",
            source: "ios",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "app-b")]
        )
        var fetcher: FlagAssignmentsFetcher?
        fetcher = FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://flags.example.test/precompute-assignments"),
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(context: appA),
            responseSigning: .init(mode: .required, trustedRootCertificates: [anchor]),
            dateProvider: clock,
            floorStore: InMemorySigningFloorStore(),
            signingFetch: { request, complete in
                // The transcript still binds the application ID of this request.
                XCTAssertEqual(request.value(forHTTPHeaderField: "dd-application-id"), "app-a")
                // The RUM application ID changes while the request is in flight.
                fetcher?.updateResponseSigningCacheScope(appB)
                do {
                    let headers = try fixture.signedHeaders(request: request, body: body)
                    complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                } catch {
                    complete(.failure(error))
                }
            },
            fetch: { _, _ in XCTFail("Signing must use the signing transport") }
        )
        let done = expectation(description: "fetch")
        fetcher?.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
            defer { done.fulfill() }
            guard case .success(let response) = result else {
                return XCTFail("\(result)")
            }
            XCTAssertEqual(response.responseSigningCacheScope, fetcher?.responseSigningCacheScope)
            XCTAssertEqual(fetcher?.isVerified(response.verification, at: clock.now), true)
        }
        wait(for: [done], timeout: 2)
    }

    // MARK: - Signing errors and user logs

    func testSigningFailureReturnsTheReasonCodeAndLogsItOnce() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
        let anchor = try SigningChainFixture.root("root-a")
        let body = Data.mockAnyFlagAssignmentsResponse()
        for mode in [Flags.ResponseSigningMode.required, .observe] {
            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: URL(string: "https://flags.example.test/precompute-assignments"),
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
                responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                dateProvider: clock,
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, complete in
                    do {
                        // Signed for a different body: the signature does not match.
                        let headers = try fixture.signedHeaders(request: request, body: Data("{}".utf8))
                        complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                    } catch {
                        complete(.failure(error))
                    }
                },
                fetch: { _, _ in XCTFail("Signing must use the signing transport") }
            )
            for _ in 0..<2 {
                let done = expectation(description: "\(mode)")
                fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                    defer { done.fulfill() }
                    switch (mode, result) {
                    case (.required, .failure(.responseSigningFailed(let reason))): XCTAssertEqual(reason, "invalid-signature")
                    case (.observe, .success(let response)): XCTAssertNil(response.verification)
                    default: XCTFail("\(mode): \(result)")
                    }
                }
                wait(for: [done], timeout: 2)
            }
            let expected = "Flag response signing failed (invalid-signature): the signature does not match the request and response. The response changed in transit."
            let logs = mode == .required ? dd.logger.errorMessages : dd.logger.warnMessages
            XCTAssertEqual(logs.filter { $0.hasPrefix("Flag response signing failed") }, [mode == .required ? expected : expected + " Flags are not verified."], "\(mode)")
        }
    }

    func testEveryReasonCodeIsKebabCaseWithALogMessage() {
        let codes: [FlagsSigningError] = [
            .unsupportedRequest, .unavailableCrypto, .missingAnchor, .missingProof, .invalidProof, .responseTooLarge,
            .invalidCertificate, .invalidSignature, .expiredProof, .unsupportedSite, .revokedCertificate
        ]
        XCTAssertEqual(codes.map(\.rawValue), [
            "unsupported-request", "unavailable-crypto", "missing-anchor", "missing-proof", "invalid-proof",
            "response-too-large", "invalid-certificate", "invalid-signature", "expired-proof", "unsupported-site",
            "revoked-certificate"
        ])
        for code in codes {
            XCTAssertTrue(code.logMessage.hasPrefix("Flag response signing failed (\(code.rawValue)): "), code.rawValue)
            XCTAssertTrue(code.logMessage.hasSuffix("."), code.rawValue)
        }
        XCTAssertEqual(
            FlagsSigningError.missingProof.logMessage,
            "Flag response signing failed (missing-proof): the response has no signature headers. A proxy, CDN or custom endpoint removed the signature headers, or the organization is not enrolled."
        )
    }

    func testObservePersistenceHasFreshScopedNamespaceAndNeverReadsLegacy() throws {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let store = DataStoreMock()
        let context = FlagsEvaluationContext(targetingKey: "same")
        let legacy = try JSONEncoder().encode(
            FlagsData(flags: ["legacy": .mockAnyBoolean()], context: context, date: clock.now)
        )
        store.setValue(legacy, forKey: "signed", version: dataStoreDefaultKeyVersion)
        let fetcher = SigningLifecycleFetcher(mode: .observe)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        XCTAssertNil(repository.flagAssignment(for: "legacy"))
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        repository.flush()
        let key = FlagsResponseVerifier.cacheKey(clientName: "signed")
        XCTAssertNotNil(store.value(forKey: key))
        XCTAssertEqual(store.value(forKey: "signed")?.data(), legacy)
        let same = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { same.flush() }
        XCTAssertNotNil(same.flagAssignment(for: "flag"))
        fetcher.responseSigningCacheScope = "scope-b"
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        let changed = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { changed.flush() }
        XCTAssertNil(changed.flagAssignment(for: "flag"))
        changed.reset()
        XCTAssertEqual(store.value(forKey: "signed")?.data(), legacy)
    }

    func testSigningScopeChangeRejectsLateSuccessAndFallback() {
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
            let fetcher = SigningLifecycleFetcher(mode: mode)
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil
            )
            defer { repository.flush() }
            let context = FlagsEvaluationContext(targetingKey: "same")
            repository.setEvaluationContext(context) { _ in }
            fetcher.completeVerified(index: 0, expiry: 200)
            repository.setEvaluationContext(context) { _ in }
            var late = FlagAssignmentsResponse(flags: ["late": .mockAnyBoolean()])
            late.responseSigningCacheScope = "scope-a"
            late.verification = .init(scope: fetcher.scope, verifiedAt: 100, expiresAt: 200, cacheScope: "scope-a")
            fetcher.responseSigningCacheScope = "scope-b"
            XCTAssertNil(repository.flagAssignment(for: "flag"))
            fetcher.completions[1](.success(late))
            XCTAssertNil(repository.flagAssignment(for: "late"))
            XCTAssertNil(repository.flagAssignment(for: "flag"))
        }
    }

    func testObservePreservesVerifiedFallbackAfterUnverifiedRefresh() {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let fetcher = SigningLifecycleFetcher(mode: .observe)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        let context = FlagsEvaluationContext(targetingKey: "same")
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        repository.setEvaluationContext(context) { _ in }
        var unverified = FlagAssignmentsResponse(flags: [:])
        unverified.responseSigningCacheScope = fetcher.responseSigningCacheScope
        fetcher.completions[1](.success(unverified))
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        repository.setEvaluationContext(context) { _ in }
        fetcher.completions[2](.failure(.invalidResponse))
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
    }

    // MARK: - Certificate chain

    private func signedRequest(_ url: String = "https://flags.example.test/precompute-assignments?dd_env=prod")
        throws -> (FlagsResponseVerifier, URLRequest) {
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [try SigningChainFixture.root("root-a")])
        )
        var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"subject":"one"}"#.utf8)
        request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return (verifier, try verifier.prepare(request))
    }

    private func response(_ request: URLRequest, _ headers: [String: String]) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
        )
    }

    func testChainTestCACredentialTable() throws {
        let body = Data.mockAnyFlagAssignmentsResponse()
        let expected: [(credential: String, roots: [String], accept: Bool)] = [
            ("two-intermediates", ["root-a"], true),
            ("two-intermediates", ["root-b"], false),
            ("backup-root", ["root-b"], true),
            ("backup-root", ["root-a"], false),
            ("backup-root", ["root-a", "root-b"], true),
            ("rotated-lower-intermediate", ["root-a"], true),
            ("other-product", ["root-a"], false),
            ("missing-upper-intermediate", ["root-a"], false),
            ("one-intermediate", ["root-a"], true),
            ("codesigning-leaf", ["root-a"], false),
            ("unrelated-root", ["root-a", "root-b"], false)
        ]
        for row in expected {
            let roots = try row.roots.map { try SigningChainFixture.root($0) }
            let verifier = FlagsResponseVerifier(configuration: .init(mode: .required, trustedRootCertificates: roots))
            var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            let prepared = try verifier.prepare(request)
            let fixture = try SigningChainFixture.credential(row.credential)
            let response = try response(prepared, fixture.signedHeaders(request: prepared, body: body))
            let name = "\(row.credential) pinned \(row.roots)"
            let now = Date(timeIntervalSince1970: SigningChainFixture.now)
            if row.accept {
                let proof = try verifier.verify(request: prepared, response: response, body: body, now: now)
                XCTAssertEqual(proof.verifiedAt, SigningChainFixture.now, name)
                XCTAssertEqual(proof.expiresAt, SigningChainFixture.now + 300, name)
            } else {
                XCTAssertThrowsError(
                    try verifier.verify(request: prepared, response: response, body: body, now: now),
                    name
                ) { error in
                    XCTAssertEqual(error as? FlagsSigningError, .invalidCertificate, name)
                }
            }
        }
    }

    func testChainLeavesExpireWithTheirValidity() throws {
        let (verifier, request) = try signedRequest()
        let body = Data.mockAnyFlagAssignmentsResponse()
        let fixture = try SigningChainFixture.credential("two-intermediates")
        // Leaves are valid for 72 hours from issuance; the proof must fit inside the leaf.
        let late = 1_795_234_700.0
        let response = try response(request, fixture.signedHeaders(request: request, body: body, now: late))
        XCTAssertThrowsError(
            try verifier.verify(request: request, response: response, body: body, now: Date(timeIntervalSince1970: late))
        )
    }

    func testChainTranscriptDomainAndTail() throws {
        let (_, request) = try signedRequest()
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let body = Data("{}".utf8)
        let transcript = try FlagsResponseVerifier.transcript(
            request: request,
            status: 200,
            body: body,
            issuedAt: 10,
            expiresAt: 20,
            leaf: fixture.leaf,
            intermediates: fixture.intermediates,
            responseHeaders: SigningChainFixture.responseHeaders
        )
        XCTAssertTrue(transcript.starts(with: Data("datadog.feature-flags.precomputed-assignments.v1\0".utf8)))
        var tail = Data(SHA256.hash(data: body))
        tail.append(Data(SHA256.hash(data: fixture.leaf)))
        tail.append(UInt8(fixture.intermediates.count))
        for intermediate in fixture.intermediates { tail.append(Data(SHA256.hash(data: intermediate))) }
        // The signed response list follows the chain: `u8(count)`, then `lp(name) u8(presence) lp(value)` each.
        tail.append(2)
        for (name, value) in [("content-type", "application/json"), ("dd-flag-selection-ignored", "")] {
            tail.append(contentsOf: [0, 0, 0, UInt8(name.utf8.count)] + Array(name.utf8))
            tail.append(value.isEmpty ? 0 : 1)
            tail.append(contentsOf: [0, 0, 0, UInt8(value.utf8.count)] + Array(value.utf8))
        }
        XCTAssertEqual(fixture.intermediates.count, 2)
        XCTAssertEqual(transcript.suffix(tail.count), tail)
        // Header order is bound: reversing the chain changes the transcript.
        XCTAssertNotEqual(
            transcript,
            try FlagsResponseVerifier.transcript(
                request: request,
                status: 200,
                body: body,
                issuedAt: 10,
                expiresAt: 20,
                leaf: fixture.leaf,
                intermediates: fixture.intermediates.reversed(),
                responseHeaders: SigningChainFixture.responseHeaders
            )
        )
        for count in [0, 4] {
            XCTAssertThrowsError(
                try FlagsResponseVerifier.transcript(
                    request: request,
                    status: 200,
                    body: body,
                    issuedAt: 10,
                    expiresAt: 20,
                    leaf: fixture.leaf,
                    intermediates: Array(repeating: fixture.leaf, count: count),
                    responseHeaders: SigningChainFixture.responseHeaders
                )
            )
        }
    }

    func testChainRejectsMalformedProofHeaders() throws {
        let (verifier, request) = try signedRequest()
        let body = Data.mockAnyFlagAssignmentsResponse()
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let prefix = FlagsResponseVerifier.prefix
        let valid = try fixture.signedHeaders(request: request, body: body)
        let now = Date(timeIntervalSince1970: SigningChainFixture.now)
        XCTAssertNoThrow(try verifier.verify(request: request, response: response(request, valid), body: body, now: now))
        let chain = fixture.intermediates.map { $0.base64EncodedString() }
        let variants: [String: [String: String?]] = [
            "missing chain": [prefix + "signing-chain": nil],
            "v1 intermediate header only": [
                prefix + "signing-chain": nil, prefix + "signing-intermediate": chain[0]
            ],
            "version 2": [prefix + "signature-version": "2"],
            "version 3": [prefix + "signature-version": "3"],
            "space after comma": [prefix + "signing-chain": chain.joined(separator: ", ")],
            "empty entry": [prefix + "signing-chain": chain.joined(separator: ",,")],
            "trailing comma": [prefix + "signing-chain": chain.joined(separator: ",") + ","],
            "reordered chain": [prefix + "signing-chain": chain.reversed().joined(separator: ",")],
            "four entries": [prefix + "signing-chain": (chain + chain).joined(separator: ",")],
            "leaf as chain": [prefix + "signing-chain": fixture.leaf.base64EncodedString()],
            "truncated chain": [prefix + "signing-chain": chain[0]]
        ]
        for (name, changes) in variants {
            var headers = valid
            for (key, value) in changes { headers[key] = value }
            XCTAssertThrowsError(
                try verifier.verify(request: request, response: response(request, headers), body: body, now: now),
                name
            )
        }
    }

    func testChainProfileDecodesBasicConstraintsAndExtendedKeyUsage() throws {
        typealias Certificate = FlagsSigningCertificate
        XCTAssertTrue(try Certificate.basicConstraints(Data([48, 0])) == (false, nil))
        XCTAssertTrue(try Certificate.basicConstraints(Data([48, 3, 1, 1, 255])) == (true, nil))
        XCTAssertTrue(try Certificate.basicConstraints(Data([48, 6, 1, 1, 255, 2, 1, 0])) == (true, 0))
        XCTAssertTrue(try Certificate.basicConstraints(Data([48, 6, 1, 1, 255, 2, 1, 3])) == (true, 3))
        XCTAssertTrue(try Certificate.basicConstraints(Data([48, 7, 1, 1, 255, 2, 2, 1, 0])) == (true, 256))
        for invalid in [
            Data([48, 3, 1, 1, 0]), // cA FALSE must be omitted in DER
            Data([48, 6, 1, 1, 255, 2, 1, 255]), // negative pathLen
            Data([48, 3, 2, 1, 0]), // pathLen without cA
            Data([48, 9, 1, 1, 255, 2, 1, 0, 2, 1, 0]), // extra element
            Data([49, 0])
        ] {
            XCTAssertThrowsError(try Certificate.basicConstraints(invalid), "\(Array(invalid))")
        }
        let ffe = Data([6, 10, 43, 6, 1, 4, 1, 134, 141, 31, 1, 1])
        let any = Data([6, 4, 85, 29, 37, 0])
        let codeSigning = Data([6, 8, 43, 6, 1, 5, 5, 7, 3, 3])
        func sequence(_ items: Data...) -> Data {
            let content = items.reduce(Data(), +)
            return Data([48, UInt8(content.count)]) + content
        }
        XCTAssertEqual(try Certificate.extendedKeyUsages(sequence(codeSigning, ffe)), [
            Data(codeSigning.dropFirst(2)), Certificate.assignmentSigningUsage
        ])
        XCTAssertEqual(try Certificate.extendedKeyUsages(sequence(any)), [Certificate.anyExtendedKeyUsage])
        XCTAssertThrowsError(try Certificate.extendedKeyUsages(sequence()))
        XCTAssertThrowsError(try Certificate.extendedKeyUsages(sequence(Data([2, 1, 1]))))
        XCTAssertEqual(Data([6, 10]) + Certificate.assignmentSigningUsage, ffe)
        XCTAssertEqual(Data([6, 4]) + Certificate.anyExtendedKeyUsage, any)
    }

    func testChainRootExtendedKeyUsageAndPathLength() throws {
        let body = Data.mockAnyFlagAssignmentsResponse()
        let fixture = try SigningChainFixture.credential("root-eku-chain")
        let now = Date(timeIntervalSince1970: SigningChainFixture.now)
        // Each root has the same key and subject; only the named extension differs.
        let expected: [(root: String, accept: Bool)] = [
            ("root-eku-none", true),
            ("root-eku-ffe", true),
            ("root-eku-any", true),
            ("root-eku-codesigning-ffe", true),
            ("root-eku-codesigning", false),
            ("root-pathlen-0", false)
        ]
        for row in expected {
            let root = try SigningChainFixture.root(row.root)
            let verifier = FlagsResponseVerifier(configuration: .init(mode: .required, trustedRootCertificates: [root]))
            var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            let prepared = try verifier.prepare(request)
            let response = try response(prepared, fixture.signedHeaders(request: prepared, body: body))
            if row.accept {
                XCTAssertNoThrow(try verifier.verify(request: prepared, response: response, body: body, now: now), row.root)
            } else {
                XCTAssertThrowsError(
                    try verifier.verify(request: prepared, response: response, body: body, now: now),
                    row.root
                ) { error in
                    XCTAssertEqual(error as? FlagsSigningError, .invalidCertificate, row.root)
                }
            }
        }
        XCTAssertThrowsError(
            try FlagsSigningCertificate(der: SigningChainFixture.root("root-eku-codesigning"), role: .anchor)
        )
        XCTAssertEqual(
            try FlagsSigningCertificate(der: SigningChainFixture.root("root-pathlen-0"), role: .anchor).pathLength,
            0
        )
    }

    func testChainTranscriptAuthorityOmitsDefaultHTTPSPort() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let body = Data("{}".utf8)
        // An independent encoder for the transcript prefix: domain, then length-prefixed request components.
        func prefix(_ authority: String) -> Data {
            var data = Data("datadog.feature-flags.precomputed-assignments.v1\0".utf8)
            for value in ["POST", "https", authority, "/precompute-assignments", "?a=b"] {
                withUnsafeBytes(of: UInt32(value.utf8.count).bigEndian) { data.append(contentsOf: $0) }
                data.append(Data(value.utf8))
            }
            return data
        }
        for (url, authority) in [
            ("https://Flags.Example.Test:443/precompute-assignments?a=b", "flags.example.test"),
            ("https://flags.example.test/precompute-assignments?a=b", "flags.example.test"),
            ("https://flags.example.test:8443/precompute-assignments?a=b", "flags.example.test:8443"),
            ("https://flags.example.test:80/precompute-assignments?a=b", "flags.example.test:80"),
            ("https://[::1]:443/precompute-assignments?a=b", "[::1]")
        ] {
            let (_, request) = try signedRequest(url)
            let transcript = try FlagsResponseVerifier.transcript(
                request: request,
                status: 200,
                body: body,
                issuedAt: 10,
                expiresAt: 20,
                leaf: fixture.leaf,
                intermediates: fixture.intermediates,
                responseHeaders: SigningChainFixture.responseHeaders
            )
            XCTAssertTrue(transcript.starts(with: prefix(authority)), url)
        }
        for url in ["http://flags.example.test/precompute-assignments", "http://localhost:7676/precompute-assignments"] {
            XCTAssertThrowsError(try signedRequest(url), url) { error in
                XCTAssertEqual(error as? FlagsSigningError, .unsupportedRequest, url)
            }
        }
    }
}

extension FlagsResponseSigningTests {
    // MARK: - Proof expiry (`expireVerifiedFlags`)

    func testExpireVerifiedFlagsDefaultsToFalse() {
        XCTAssertFalse(Flags.ResponseSigningConfiguration(mode: .required).expireVerifiedFlags)
        XCTAssertTrue(Flags.ResponseSigningConfiguration(mode: .required, expireVerifiedFlags: true).expireVerifiedFlags)
        let proof = FlagsResponseVerification(scope: UUID(), verifiedAt: 100, expiresAt: 200)
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 200), scope: proof.scope))
        XCTAssertTrue(proof.isValid(at: Date(timeIntervalSince1970: 200), scope: proof.scope, allowExpired: true))
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 200), scope: UUID(), allowExpired: true))
    }

    func testRequiredProofExpiryIsStaleByDefaultAndErrorWhenStrict() {
        for strict in [false, true] {
            let fetcher = SigningLifecycleFetcher(mode: .required)
            fetcher.trustExpired = !strict
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
            let store = SigningDataStoreSpy()
            var scheduled: [(delay: TimeInterval, work: () -> Void)] = []
            func makeRepository() -> FlagsRepository {
                FlagsRepository(
                    clientName: "signed",
                    flagAssignmentsFetcher: fetcher,
                    dateProvider: clock,
                    featureScope: FeatureScopeMock(dataStore: store),
                    flagSelection: nil,
                    initializationTimeout: nil,
                    scheduleExpiry: { scheduled.append(($0, $1)) }
                )
            }
            let repository = makeRepository()
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
            fetcher.completeVerified(index: 0, expiry: 200)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertNotNil(repository.flagAssignment(for: "flag"))
            XCTAssertEqual(scheduled.map(\.delay), [100])

            // The expiry timer fires at `expires-at`.
            clock.now = Date(timeIntervalSince1970: 200)
            scheduled[0].work()
            if strict {
                XCTAssertEqual(repository.state.currentState, .error)
                XCTAssertNil(repository.flagAssignment(for: "flag"))
            } else {
                XCTAssertEqual(repository.state.currentState, .stale)
                XCTAssertNotNil(repository.flagAssignment(for: "flag"), "The last verified flags stay in use")
            }

            // A new verified response returns the state to ready.
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
            fetcher.completeVerified(index: 1, expiry: 500)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertNotNil(repository.flagAssignment(for: "flag"))
            XCTAssertEqual(scheduled.map(\.delay), [100, 300])
            repository.flush()

            // Required mode persists no flag data, so a restart starts with defaults.
            XCTAssertTrue(store.keys.isEmpty)
            let restarted = makeRepository()
            XCTAssertNil(restarted.flagAssignment(for: "flag"))
            restarted.flush()
        }
    }

    func testRequiredProofExpiryFromStaleIsErrorOnlyWhenStrict() {
        final class StateSpy: FlagsStateListener {
            var states: [FlagsClientState] = []
            func flagsStateDidChange(_ newState: FlagsClientState) { states.append(newState) }
        }
        for strict in [false, true] {
            for viaTimer in [true, false] {
                let fetcher = SigningLifecycleFetcher(mode: .required)
                fetcher.trustExpired = !strict
                let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
                var scheduled: [() -> Void] = []
                let repository = FlagsRepository(
                    clientName: "signed",
                    flagAssignmentsFetcher: fetcher,
                    dateProvider: clock,
                    featureScope: FeatureScopeMock(),
                    flagSelection: nil,
                    initializationTimeout: nil,
                    scheduleExpiry: { scheduled.append($1) }
                )
                let spy = StateSpy()
                repository.state.addListener(spy)
                repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
                fetcher.completeVerified(index: 0, expiry: 200)
                // A failed refresh before expiry serves the verified flags as stale.
                repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
                fetcher.completions[1](.failure(.networkError(URLError(.notConnectedToInternet))))
                XCTAssertEqual(repository.state.currentState, .stale)
                XCTAssertNotNil(repository.flagAssignment(for: "flag"))

                clock.now = Date(timeIntervalSince1970: 200)
                if viaTimer {
                    scheduled.forEach { $0() }
                }
                XCTAssertEqual(repository.flagAssignment(for: "flag") != nil, !strict, "strict=\(strict) timer=\(viaTimer)")
                XCTAssertEqual(repository.state.currentState, strict ? .error : .stale, "strict=\(strict) timer=\(viaTimer)")
                // The listener gets the error event once, and no event when the state stays stale.
                XCTAssertEqual(spy.states.last, strict ? .error : .stale)
                XCTAssertEqual(spy.states.filter { $0 == .error }.count, strict ? 1 : 0)
                repository.flush()
            }
        }
    }

    func testRequiredProofExpiryIsAppliedOnReadWithoutTheTimer() {
        for strict in [false, true] {
            let fetcher = SigningLifecycleFetcher(mode: .required)
            fetcher.trustExpired = !strict
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { _, _ in }
            )
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
            fetcher.completeVerified(index: 0, expiry: 200)
            clock.now = Date(timeIntervalSince1970: 250)
            XCTAssertEqual(repository.flagAssignment(for: "flag") != nil, !strict)
            XCTAssertEqual(repository.state.currentState, strict ? .error : .stale)
            repository.flush()
        }
    }

    // MARK: - Minimum not-before revocation (DRAFT wire)

    private func signedFixtureResponse(
        _ verifier: FlagsResponseVerifier,
        _ name: String,
        minimumNotBefore: UInt64? = nil,
        now: TimeInterval = SigningChainFixture.now,
        changeHeader: ((inout [String: String]) -> Void)? = nil
    ) throws -> (URLRequest, HTTPURLResponse, Data) {
        var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let prepared = try verifier.prepare(request)
        let body = Data.mockAnyFlagAssignmentsResponse()
        var headers = try SigningChainFixture.credential(name)
            .signedHeaders(request: prepared, body: body, now: now, minimumNotBefore: minimumNotBefore)
        changeHeader?(&headers)
        return (prepared, try response(prepared, headers), body)
    }

    private func verify(
        _ verifier: FlagsResponseVerifier,
        _ signed: (URLRequest, HTTPURLResponse, Data),
        at now: TimeInterval = SigningChainFixture.now
    ) throws -> FlagsResponseVerification {
        try verifier.verify(request: signed.0, response: signed.1, body: signed.2, now: Date(timeIntervalSince1970: now))
    }

    private func requiredVerifier(store: any FlagsSigningFloorStore) throws -> FlagsResponseVerifier {
        FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [try SigningChainFixture.root("root-a")]),
            floorStore: store
        )
    }

    private func anchorKey() throws -> String {
        SHA256.hash(data: try SigningChainFixture.root("root-a")).map { String(format: "%02x", $0) }.joined()
    }

    private func floorKey() throws -> String { FlagsResponseVerifier.leafFloorKey(try anchorKey()) }

    private func highWaterMarkKey() throws -> String { FlagsResponseVerifier.highWaterMarkKey(try anchorKey()) }

    /// `two-intermediates` has an older leaf than `rotated-lower-intermediate`. Both chains share the upper intermediate,
    /// and every intermediate is older than both leaves.
    func testLeafFloorRevokesAnOlderLeafAndSurvivesARestart() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let oldLeaf = try SigningChainFixture.credential("two-intermediates")
        let newLeaf = try SigningChainFixture.credential("rotated-lower-intermediate")
        XCTAssertEqual(oldLeaf.intermediates.last, newLeaf.intermediates.last, "The chains share the upper intermediate")
        let floor = try newLeaf.leafNotBefore()
        XCTAssertGreaterThan(floor, try oldLeaf.leafNotBefore())

        // Without a stored floor, both leaves verify.
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates")))
        let proof = try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate", minimumNotBefore: floor))
        XCTAssertFalse(proof.ignoredMinimumNotBefore)
        XCTAssertEqual(store.values[try floorKey()], floor)
        // The old leaf is now revoked. The new leaf still verifies.
        XCTAssertThrowsError(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates"))) {
            XCTAssertEqual($0 as? FlagsSigningError, .revokedCertificate)
        }
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate")))

        // A restart creates a new verifier with the same persisted store.
        let restarted = try requiredVerifier(store: store)
        XCTAssertThrowsError(try verify(restarted, signedFixtureResponse(restarted, "two-intermediates"))) {
            XCTAssertEqual($0 as? FlagsSigningError, .revokedCertificate)
        }
    }

    /// The old rule ignored a floor that was later than any certificate in the chain, so it could not pass
    /// the oldest intermediate. The leaf-only floor never compares with intermediates.
    func testNewLeafWithOlderIntermediatesIsAccepted() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let newLeaf = try SigningChainFixture.credential("rotated-lower-intermediate")
        let floor = try newLeaf.leafNotBefore()
        let intermediates = try newLeaf.intermediates.map { try FlagsSigningCertificate(der: $0, role: .intermediate) }
        XCTAssertTrue(intermediates.allSatisfy { $0.notBefore < Double(floor) }, "Every intermediate is older than the floor")
        let proof = try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate", minimumNotBefore: floor))
        XCTAssertFalse(proof.ignoredMinimumNotBefore)
        XCTAssertEqual(store.values[try floorKey()], floor)
        for _ in 0..<2 {
            XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate")))
        }
    }

    func testMinimumNotBeforeDataStoreKeepsTheHighestValueAcrossARestart() throws {
        let dataStore = DataStoreMock()
        let first = DataStoreSigningFloorStore(dataStore: dataStore)
        for wait in [true, false] {
            XCTAssertNil(DataStoreSigningFloorStore(dataStore: dataStore).value(forKey: "anchor", waitForRead: wait))
        }
        first.store(20, forKey: "anchor")
        first.store(10, forKey: "anchor")
        XCTAssertEqual(first.value(forKey: "anchor", waitForRead: true), 20)
        XCTAssertNil(first.value(forKey: "other", waitForRead: true))
        // A restart reads the persisted value from the feature data store.
        let restarted = DataStoreSigningFloorStore(dataStore: dataStore)
        XCTAssertEqual(restarted.value(forKey: "anchor", waitForRead: true), 20)
        restarted.store(15, forKey: "anchor")
        XCTAssertEqual(DataStoreSigningFloorStore(dataStore: dataStore).value(forKey: "anchor", waitForRead: false), 20)
        restarted.store(30, forKey: "anchor")
        XCTAssertEqual(DataStoreSigningFloorStore(dataStore: dataStore).value(forKey: "anchor", waitForRead: true), 30)
    }

    // MARK: - Clock floor (build floor, high-water mark, monotonic expiry)

    func testBuildFloorIsNotLaterThanNowAndAppliesToThePublicConfiguration() {
        XCTAssertLessThanOrEqual(Double(FlagsResponseVerifier.buildFloor), Date().timeIntervalSince1970)
        XCTAssertEqual(Flags.ResponseSigningConfiguration(mode: .required).buildFloor, FlagsResponseVerifier.buildFloor)
    }

    func testBuildFloorRejectsALeafThatExpiredBeforeTheRelease() throws {
        let floor = FlagsResponseVerifier.buildFloor
        let deviceNow = Double(floor) - 86_400
        let fixture = try SigningChainFixture.credential("two-intermediates")
        XCTAssertLessThan(try FlagsSigningCertificate(der: fixture.leaf, role: .leaf).notAfter, Double(floor))
        XCTAssertLessThan(SigningChainFixture.now, deviceNow)
        let anchor = try SigningChainFixture.root("root-a")
        let withFloor = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor], buildFloor: floor)
        )
        // The leaf is valid at the fixture clock. With the floor, the device clock cannot go back to that time.
        let signed = try signedFixtureResponse(withFloor, "two-intermediates")
        XCTAssertThrowsError(try verify(withFloor, signed, at: deviceNow)) {
            XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
        }
        XCTAssertThrowsError(try verify(withFloor, signed)) {
            XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
        }
        XCTAssertNoThrow(try verify(try requiredVerifier(store: MinimumNotBeforeStoreMock()), signed))
    }

    func testHighWaterMarkRejectsAnOlderProofAfterAClockRollbackAndARestart() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let earlier = SigningChainFixture.now
        let later = earlier + 3_600
        let leaf = try FlagsSigningCertificate(der: SigningChainFixture.credential("two-intermediates").leaf, role: .leaf)
        XCTAssertLessThanOrEqual(leaf.notBefore, earlier)
        XCTAssertGreaterThan(leaf.notAfter, later + 300)
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates", now: later), at: later))
        XCTAssertEqual(store.values[try highWaterMarkKey()], UInt64(later))
        // The device clock goes back 1 h. A proof that is valid at that time is rejected.
        for current in [verifier, try requiredVerifier(store: store)] {
            XCTAssertThrowsError(
                try verify(current, signedFixtureResponse(current, "two-intermediates", now: earlier), at: earlier)
            ) {
                XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
            }
        }
    }

    func testHighWaterMarkMovesAtMostThirtySecondsPastTheDeviceClock() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let now = SigningChainFixture.now
        for attempt in 0..<3 {
            let proof = try verify(verifier, signedFixtureResponse(verifier, "two-intermediates", now: now + 30), at: now)
            XCTAssertEqual(store.values[try highWaterMarkKey()], UInt64(now + 30))
            XCTAssertEqual(proof.verifiedAt, now, "verifiedAt is the device clock")
            XCTAssertEqual(proof.monotonicBaseline, attempt == 0 ? now : now + 30)
            // The mark of a response applies from the next verification.
            XCTAssertEqual(proof.timeFloor, attempt == 0 ? 0 : now + 30)
        }
    }

    func testKeychainStoreMigratesTheCachesFileAndKeepsTheHighWaterMarkAcrossARestart() throws {
        let keychain = KeychainMock()
        let caches = DataStoreMock()
        DataStoreSigningFloorStore(dataStore: caches).store(42, forKey: try floorKey())
        let store = KeychainSigningFloorStore(legacy: DataStoreSigningFloorStore(dataStore: caches), keychain: keychain)
        XCTAssertEqual(store.value(forKey: try floorKey(), waitForRead: true), 42)
        XCTAssertEqual(keychain.items[try floorKey()], Data("42".utf8))
        XCTAssertNil(DataStoreSigningFloorStore(dataStore: caches).value(forKey: try floorKey(), waitForRead: true))

        let later = SigningChainFixture.now + 3_600
        let verifier = try requiredVerifier(store: store)
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates", now: later), at: later))
        XCTAssertEqual(keychain.items[try highWaterMarkKey()], Data(String(UInt64(later)).utf8))
        // A restart reads the Keychain only. The Caches file is gone.
        let restarted = try requiredVerifier(store: KeychainSigningFloorStore(legacy: nil, keychain: keychain))
        let earlier = SigningChainFixture.now
        XCTAssertThrowsError(
            try verify(restarted, signedFixtureResponse(restarted, "two-intermediates", now: earlier), at: earlier)
        ) {
            XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
        }
    }

    func testKeychainFailureKeepsTheValuesInMemoryAndAcceptsTheResponse() throws {
        let keychain = KeychainMock()
        keychain.fails = true
        let caches = DataStoreMock()
        DataStoreSigningFloorStore(dataStore: caches).store(42, forKey: try floorKey())
        let store = KeychainSigningFloorStore(legacy: DataStoreSigningFloorStore(dataStore: caches), keychain: keychain)
        XCTAssertEqual(store.value(forKey: try floorKey(), waitForRead: true), 42)
        // The Caches file stays until the Keychain holds its value.
        XCTAssertEqual(DataStoreSigningFloorStore(dataStore: caches).value(forKey: try floorKey(), waitForRead: true), 42)

        let verifier = try requiredVerifier(store: store)
        let later = SigningChainFixture.now + 3_600
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates", now: later), at: later))
        XCTAssertTrue(keychain.items.isEmpty)
        let earlier = SigningChainFixture.now
        XCTAssertThrowsError(
            try verify(verifier, signedFixtureResponse(verifier, "two-intermediates", now: earlier), at: earlier)
        ) {
            XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
        }
    }

    func testKeychainReadFailureIsRetriedAndThenAppliesTheStoredFloor() throws {
        let keychain = KeychainMock()
        keychain.items[try floorKey()] = Data("42".utf8)
        keychain.failingReads = 1
        let store = KeychainSigningFloorStore(legacy: nil, keychain: keychain)
        // Before the first unlock the read fails. It is not cached as "no value".
        XCTAssertNil(store.value(forKey: try floorKey(), waitForRead: true))
        XCTAssertEqual(store.value(forKey: try floorKey(), waitForRead: true), 42)
        // The value in memory stays a lower bound while reads fail.
        store.store(50, forKey: try highWaterMarkKey())
        keychain.failingReads = 1
        XCTAssertEqual(store.value(forKey: try highWaterMarkKey(), waitForRead: true), 50)
    }

    func testTwoKeychainStoresNeverLowerAValueThatTheOtherWrote() throws {
        let keychain = KeychainMock()
        let first = KeychainSigningFloorStore(legacy: nil, keychain: keychain)
        let second = KeychainSigningFloorStore(legacy: nil, keychain: keychain)
        let key = try highWaterMarkKey()
        XCTAssertNil(second.value(forKey: key, waitForRead: true))
        first.store(200, forKey: key)
        // `second` read no value before. Its lower write must not replace the value of `first`.
        second.store(100, forKey: key)
        XCTAssertEqual(keychain.items[key], Data("200".utf8))
        XCTAssertEqual(KeychainSigningFloorStore(legacy: nil, keychain: keychain).value(forKey: key, waitForRead: true), 200)
        second.store(300, forKey: key)
        XCTAssertEqual(keychain.items[key], Data("300".utf8))
    }

    func testMissingKeychainEntitlementKeepsTheEarlierFileStore() throws {
        let keychain = KeychainMock()
        keychain.fails = true
        keychain.failureStatus = errSecMissingEntitlement
        let caches = DataStoreMock()
        let store = KeychainSigningFloorStore(legacy: DataStoreSigningFloorStore(dataStore: caches), keychain: keychain)
        store.store(42, forKey: try highWaterMarkKey())
        // The value persists in the file store, and a restart reads it.
        let restarted = KeychainSigningFloorStore(legacy: DataStoreSigningFloorStore(dataStore: caches), keychain: keychain)
        XCTAssertEqual(restarted.value(forKey: try highWaterMarkKey(), waitForRead: true), 42)
    }

    func testSystemKeychainRoundTrip() throws {
        let keychain = SystemFlagsKeychain()
        let account = "test-round-trip"
        defer { keychain.delete(account: account) }
        do {
            try keychain.write(Data("1".utf8), account: account)
        } catch let failure as SystemFlagsKeychain.Failure where failure.status == errSecMissingEntitlement {
            throw XCTSkip("The test host has no Keychain entitlement.")
        }
        try keychain.write(Data("2".utf8), account: account)
        XCTAssertEqual(try keychain.read(account: account), Data("2".utf8))
        XCTAssertNil(try keychain.read(account: "test-absent-account"))
    }

    func testWallClockStepBackDoesNotExtendTheProof() throws {
        let scope = UUID()
        var proof = FlagsResponseVerification(scope: scope, verifiedAt: 1_000, expiresAt: 1_300)
        proof.monotonicBaseline = 1_000
        proof.verifiedUptime = 50
        XCTAssertTrue(proof.isValid(at: Date(timeIntervalSince1970: 1_270), scope: scope, uptime: 340))
        // 301 s passed on the monotonic clock. The wall clock stepped back 21 s, inside the 30 s allowance.
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 1_280), scope: scope, uptime: 351))
        XCTAssertTrue(proof.isValid(at: Date(timeIntervalSince1970: 1_280), scope: scope, allowExpired: true, uptime: 351))
        XCTAssertEqual(proof.effectiveTime(at: Date(timeIntervalSince1970: 1_280), uptime: 351), 1_301)
        // Without a monotonic start, the wall clock decides, as before.
        let wallOnly = FlagsResponseVerification(scope: scope, verifiedAt: 1_000, expiresAt: 1_300)
        XCTAssertTrue(wallOnly.isValid(at: Date(timeIntervalSince1970: 1_280), scope: scope, uptime: 351))
        // The verifier records the monotonic time of the verification.
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [try SigningChainFixture.root("root-a")]),
            uptime: { 77 }
        )
        let verified = try verify(verifier, signedFixtureResponse(verifier, "two-intermediates"))
        XCTAssertEqual(verified.verifiedUptime, 77)
        XCTAssertEqual(verified.monotonicBaseline, SigningChainFixture.now)
    }

    /// The monotonic term starts at the effective time of the verification, so it keeps the age of the proof.
    func testMonotonicExpiryKeepsTheAgeOfTheProofAtVerification() {
        let scope = UUID()
        // Issued at 1000, expires at 1300, verified at device time 1290.
        var proof = FlagsResponseVerification(scope: scope, verifiedAt: 1_290, expiresAt: 1_300)
        proof.monotonicBaseline = 1_290
        proof.verifiedUptime = 50
        // 20 monotonic seconds later, the clock steps back 20 s, inside the 30 s allowance. The proof expired at 1300.
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 1_290), scope: scope, uptime: 70))
        XCTAssertEqual(proof.effectiveTime(at: Date(timeIntervalSince1970: 1_290), uptime: 70), 1_310)
        // After the expiry was observed, a later step back does not make the proof readable again.
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 1_280), scope: scope, uptime: 90))
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 1_265), scope: scope, uptime: 100))
    }

    func testKeychainStoresOfTwoCoresShareTheirValues() throws {
        let keychain = KeychainMock()
        let shared = KeychainSigningFloorStore.SharedValues()
        let key = try floorKey()
        keychain.items[key] = Data("100".utf8)
        let first = KeychainSigningFloorStore(legacy: nil, keychain: keychain, shared: shared)
        let second = KeychainSigningFloorStore(legacy: nil, keychain: keychain, shared: shared)
        XCTAssertEqual(first.value(forKey: key, waitForRead: true), 100)
        XCTAssertEqual(second.value(forKey: key, waitForRead: true), 100)
        second.store(200, forKey: key)
        // `first` read 100 before. It now uses 200, and its lower write keeps 200.
        XCTAssertEqual(first.value(forKey: key, waitForRead: true), 200)
        first.store(150, forKey: key)
        XCTAssertEqual(keychain.items[key], Data("200".utf8))
        XCTAssertEqual(second.value(forKey: key, waitForRead: true), 200)
    }

    /// iOS only: a slow first read must not skip the floor in `required` mode.
    func testRequiredWaitsForASlowFloorReadAndNeverSkipsTheCheck() throws {
        let persisted = DataStoreMock()
        let floor = try SigningChainFixture.credential("rotated-lower-intermediate").leafNotBefore()
        DataStoreSigningFloorStore(dataStore: persisted).store(floor, forKey: try floorKey())
        let slow = SlowDataStore(wrapping: persisted, delay: 1)
        let anchor = try SigningChainFixture.root("root-a")

        let required = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            floorStore: DataStoreSigningFloorStore(dataStore: slow, readTimeout: 0.1)
        )
        XCTAssertThrowsError(try verify(required, signedFixtureResponse(required, "two-intermediates"))) {
            XCTAssertEqual($0 as? FlagsSigningError, .revokedCertificate)
        }

        // `observe` waits only for the short read timeout. The next verification uses the finished read.
        let observeStore = DataStoreSigningFloorStore(dataStore: slow, readTimeout: 0.1)
        let observe = FlagsResponseVerifier(
            configuration: .init(mode: .observe, trustedRootCertificates: [anchor]),
            floorStore: observeStore
        )
        XCTAssertNoThrow(try verify(observe, signedFixtureResponse(observe, "two-intermediates")))
        XCTAssertEqual(observeStore.value(forKey: try floorKey(), waitForRead: true), floor)
        XCTAssertThrowsError(try verify(observe, signedFixtureResponse(observe, "two-intermediates")))
    }

    func testMinimumNotBeforeLowerThanTheStoredValueIsIgnored() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let floor = try SigningChainFixture.credential("rotated-lower-intermediate").leafNotBefore()
        _ = try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate", minimumNotBefore: floor))
        _ = try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate", minimumNotBefore: floor - 1))
        XCTAssertEqual(store.values[try floorKey()], floor)
    }

    func testLeafFloorGreaterThanTheLeafIsIgnored() throws {
        let store = MinimumNotBeforeStoreMock()
        let verifier = try requiredVerifier(store: store)
        let chain = try SigningChainFixture.credential("one-intermediate")
        // A response never revokes its own leaf.
        let proof = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: try chain.leafNotBefore() + 1))
        XCTAssertTrue(proof.ignoredMinimumNotBefore)
        XCTAssertNil(store.values[try floorKey()])
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate")))
        // A value later than the intermediate but not later than the leaf is accepted: intermediates are not compared.
        let between = try chain.oldestNotBefore() + 1
        XCTAssertLessThanOrEqual(between, try chain.leafNotBefore())
        let accepted = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: between))
        XCTAssertFalse(accepted.ignoredMinimumNotBefore)
        XCTAssertEqual(store.values[try floorKey()], between)
    }

    func testChangedMinimumNotBeforeHeaderFailsTheSignature() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let store = MinimumNotBeforeStoreMock()
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            floorStore: store
        )
        let value = try SigningChainFixture.credential("one-intermediate").leafNotBefore()
        let name = FlagsResponseVerifier.prefix + "minimum-leaf-not-before"
        let changes: [(inout [String: String]) -> Void] = [
            { $0[name] = String(value - 1) }, // changed
            { $0[name] = nil }, // removed
        ]
        for change in changes {
            XCTAssertThrowsError(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value, changeHeader: change))) {
                XCTAssertEqual($0 as? FlagsSigningError, .invalidSignature)
            }
        }
        // Added to a response that was signed without it.
        XCTAssertThrowsError(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", changeHeader: { $0[name] = String(value) }))) {
            XCTAssertEqual($0 as? FlagsSigningError, .invalidSignature)
        }
        // A malformed value is rejected before the signature.
        for malformed in ["", "01", "-1", "1.5", "9007199254740992", "1,2"] {
            XCTAssertThrowsError(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value, changeHeader: { $0[name] = malformed })), malformed)
        }
        XCTAssertTrue(store.values.isEmpty)
    }

    func testRevokedChainFailsClosedInRequiredAndIsReportedInObserve() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let anchorKey = SHA256.hash(data: anchor).map { String(format: "%02x", $0) }.joined()
        let body = Data.mockAnyFlagAssignmentsResponse()
        // The floor is the newer leaf, so the older `two-intermediates` leaf is revoked.
        let value = try SigningChainFixture.credential("rotated-lower-intermediate").leafNotBefore()
        for mode in [Flags.ResponseSigningMode.required, .observe] {
            let store = MinimumNotBeforeStoreMock()
            store.values[FlagsResponseVerifier.leafFloorKey(anchorKey)] = value
            let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
            let telemetry = scope.telemetryMock
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now)),
                floorStore: store,
                signingFetch: { request, complete in
                    do {
                        let headers = try SigningChainFixture.credential("two-intermediates").signedHeaders(request: request, body: body)
                        complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                    } catch {
                        XCTFail("\(error)")
                    }
                },
                fetch: { _, _ in XCTFail("Signing must use the signing transport") }
            )
            let done = expectation(description: "\(mode)")
            fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                defer { done.fulfill() }
                switch (mode, result) {
                case (.required, .failure(.responseSigningFailed(reason: "revoked-certificate"))): break
                case (.observe, .success(let response)): XCTAssertNil(response.verification)
                default: XCTFail("\(mode): \(result)")
                }
            }
            wait(for: [done], timeout: 1)
            XCTAssertTrue(telemetry.messages.contains { message in
                guard case .debug(let id, _, _) = message else {
                    return false
                }
                return id == "flags.response_signing:\(mode):unverified:revoked-certificate"
            }, "\(mode)")
        }
    }
}

extension FlagsResponseSigningTests {
    // MARK: - Signing telemetry (`flags.response_signing`)

    private func signingEvents(_ scope: FeatureScopeMock) -> [(id: String, attributes: [String: String])] {
        scope.telemetryMock.messages.compactMap { message in
            guard case let .debug(id, text, attributes) = message, text == "flags.response_signing" else {
                return nil
            }
            let values = (attributes ?? [:]).mapValues { "\($0)" }
            return (id, values)
        }
    }

    /// A fetcher whose transport answers with `respond` for each signed request.
    private func telemetryFetcher(
        mode: Flags.ResponseSigningMode,
        scope: FeatureScopeMock,
        body: Data = Data.mockAnyFlagAssignmentsResponse(),
        respond: @escaping (URLRequest) throws -> [String: String]
    ) throws -> FlagAssignmentsFetcher {
        FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"),
            customHeaders: nil,
            flagSelection: nil,
            featureScope: scope,
            responseSigning: .init(mode: mode, trustedRootCertificates: [try SigningChainFixture.root("root-a")]),
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now)),
            floorStore: InMemorySigningFloorStore(),
            signingFetch: { request, complete in
                do {
                    let headers = try respond(request)
                    complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                } catch {
                    complete(.failure(error))
                }
            },
            fetch: { request, complete in
                complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)))
            }
        )
    }

    private func fetchOnce(_ fetcher: FlagAssignmentsFetcher) {
        let done = expectation(description: "fetch")
        fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { _ in done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    /// The SDK keeps no dedupe set: RUM telemetry deduplicates by id for each session, after its sampling.
    func testSigningTelemetryGivesIdenticalFailuresTheSameEventID() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios", sdkVersion: "1.2.3"))
        let fetcher = try telemetryFetcher(mode: .observe, scope: scope) { _ in [:] }
        fetchOnce(fetcher)
        fetchOnce(fetcher)
        let events = signingEvents(scope)
        XCTAssertEqual(events.map(\.id), Array(repeating: "flags.response_signing:observe:unverified:missing-proof", count: 2))
        // The event has only the fields of the shared table.
        XCTAssertEqual(
            events.first?.attributes,
            ["mode": "observe", "result": "unverified", "reason": "missing-proof", "sdk_version": "1.2.3", "site": "datad0g.com"]
        )
    }

    func testSigningTelemetrySendsOneEventForEachReasonAndVerifiedInObserve() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios", sdkVersion: "1.2.3"))
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let body = Data.mockAnyFlagAssignmentsResponse()
        var answers: [(URLRequest) throws -> [String: String]] = [
            { _ in [:] }, // missing-proof
            { try fixture.signedHeaders(request: $0, body: Data("{}".utf8)) }, // invalid-signature
            { try fixture.signedHeaders(request: $0, body: body) }, // verified
        ]
        let fetcher = try telemetryFetcher(mode: .observe, scope: scope, body: body) { request in try answers.removeFirst()(request) }
        for _ in 0..<3 {
            fetchOnce(fetcher)
        }
        let events = signingEvents(scope)
        XCTAssertEqual(events.map(\.id), [
            "flags.response_signing:observe:unverified:missing-proof",
            "flags.response_signing:observe:unverified:invalid-signature",
            "flags.response_signing:observe:verified:",
        ])
        XCTAssertEqual(events.last?.attributes, ["mode": "observe", "result": "verified", "sdk_version": "1.2.3", "site": "datad0g.com"])
    }

    func testSigningTelemetryInRequiredSendsFailuresOnly() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let body = Data.mockAnyFlagAssignmentsResponse()
        var fail = false
        let fetcher = try telemetryFetcher(mode: .required, scope: scope, body: body) { request in
            fail ? [:] : try fixture.signedHeaders(request: request, body: body)
        }
        fetchOnce(fetcher)
        XCTAssertTrue(signingEvents(scope).isEmpty, "A verified response in required mode sends nothing")
        fail = true
        fetchOnce(fetcher)
        XCTAssertEqual(signingEvents(scope).map(\.id), ["flags.response_signing:required:unverified:missing-proof"])
    }

    func testSigningTelemetryInOffSendsNothing() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let fetcher = try telemetryFetcher(mode: .off, scope: scope) { _ in [:] }
        fetchOnce(fetcher)
        XCTAssertTrue(signingEvents(scope).isEmpty)
    }

    func testSigningTelemetrySiteNeverCarriesAURL() {
        let cases: [(String?, String)] = [
            ("https://preview.ff-cdn.datad0g.com/precompute-assignments", "datad0g.com"),
            ("https://preview.ff-cdn.datadoghq.com/precompute-assignments", "datadoghq.com"),
            ("https://preview.ff-cdn.us3.datadoghq.com/x", "us3.datadoghq.com"),
            ("https://preview.ff-cdn.datadoghq.eu/x", "datadoghq.eu"),
            ("https://proxy.example.test/precompute-assignments", "custom"),
            ("https://preview.ff-cdn.example.test/x", "custom"),
            ("https://preview.ff-cdn.evildatadoghq.com/x", "custom"),
            ("https://preview.ff-cdn.evildatadoghq.eu/x", "custom"),
            ("https://preview.ff-cdn.evildatad0g.com/x", "custom"),
            ("https://preview.ff-cdn.datadoghq.com.example.test/x", "custom"),
            ("https://preview.ff-cdn.ap1.datadoghq.com/x", "ap1.datadoghq.com"),
            (nil, "custom"),
        ]
        for (url, site) in cases {
            XCTAssertEqual(FlagAssignmentsFetcher.signingSite(url.flatMap(URL.init(string:))), site, url ?? "nil")
        }
    }

    // MARK: - Required mode matches contexts by wire identity

    func testWireIdentityComparesTheBytesOfNestedValuesAndKeys() {
        let nfc = "caf\u{E9}", nfd = "cafe\u{301}"
        func context(value: AnyValue, key: String = "k", attribute: String = "a") -> FlagsEvaluationContext {
            FlagsEvaluationContext(targetingKey: key, attributes: [attribute: value])
        }
        let nested = AnyValue.dictionary(["list": .array([.string(nfc), .int(1)])])
        XCTAssertTrue(context(value: nested).hasSameWireIdentity(as: context(value: nested)))
        let decomposed = AnyValue.dictionary(["list": .array([.string(nfd), .int(1)])])
        XCTAssertEqual(context(value: nested), context(value: decomposed))
        XCTAssertFalse(context(value: nested).hasSameWireIdentity(as: context(value: decomposed)))
        XCTAssertFalse(context(value: .null, attribute: nfc).hasSameWireIdentity(as: context(value: .null, attribute: nfd)))
        XCTAssertFalse(context(value: .null, key: nfc).hasSameWireIdentity(as: context(value: .null, key: nfd)))
        XCTAssertFalse(context(value: .int(1)).hasSameWireIdentity(as: context(value: .int(2))))
        XCTAssertFalse(context(value: .null).hasSameWireIdentity(as: FlagsEvaluationContext(targetingKey: "k")))
    }

    /// Numbers match by the bytes that the request encoder writes, not by `AnyValue` equality.
    func testWireIdentityOfNumbersMatchesTheEncodedRequestBytes() throws {
        func context(_ value: AnyValue) -> FlagsEvaluationContext {
            FlagsEvaluationContext(targetingKey: "k", attributes: ["a": .array([value])])
        }
        // `.int(1)` and `.double(1)` encode as `1` but are not equal. `0.0` and `-0.0` are equal but encode differently.
        XCTAssertNotEqual(AnyValue.int(1), .double(1))
        XCTAssertTrue(context(.int(1)).hasSameWireIdentity(as: context(.double(1))))
        XCTAssertEqual(AnyValue.double(0), .double(-0.0))
        XCTAssertFalse(context(.double(0)).hasSameWireIdentity(as: context(.double(-0.0))))
        let values: [AnyValue] = [
            .int(0), .int(1), .int(-1), .int(10_000_000_000_000_000), .int(Int.max), .int(Int.min),
            .double(0), .double(-0.0), .double(1), .double(-1), .double(1.5), .double(0.1), .double(1e16),
            .double(9.223372036854776e18), .double(-9.223372036854776e18), .bool(true), .string("1"), .null
        ]
        let encoder = JSONEncoder.dd.default()
        for lhs in values {
            for rhs in values {
                let sameBytes = try encoder.encode(["a": [lhs]]) == encoder.encode(["a": [rhs]])
                XCTAssertEqual(context(lhs).hasSameWireIdentity(as: context(rhs)), sameBytes, "\(lhs) and \(rhs)")
            }
        }
    }

    func testRequiredDoesNotServeAContextWithADifferentWireIdentity() {
        let precomposed = FlagsEvaluationContext(targetingKey: "caf\u{E9}")
        let decomposed = FlagsEvaluationContext(targetingKey: "cafe\u{301}")
        XCTAssertEqual(precomposed, decomposed, "Swift strings compare by canonical equivalence")
        XCTAssertFalse(precomposed.hasSameWireIdentity(as: decomposed))
        XCTAssertTrue(precomposed.hasSameWireIdentity(as: FlagsEvaluationContext(targetingKey: "caf\u{E9}")))

        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: 100)),
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        repository.setEvaluationContext(precomposed) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        // While the decomposed context is pending, and after its request fails, the precomposed proof is not used.
        repository.setEvaluationContext(decomposed) { _ in }
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        fetcher.completions[1](.failure(.networkError(URLError(.notConnectedToInternet))))
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.state.currentState, .error)
    }

    /// Two requests overlap: a precomposed context, then a decomposed one. The older response is for another wire
    /// identity, so it must not publish `ready`, and the failure of the newer request must still apply.
    func testRequiredDoesNotAdmitAnOlderResponseForAnotherWireIdentity() {
        let precomposed = FlagsEvaluationContext(targetingKey: "caf\u{E9}")
        let decomposed = FlagsEvaluationContext(targetingKey: "cafe\u{301}")
        let fetcher = SigningLifecycleFetcher(mode: .required)
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: 100)),
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        repository.setEvaluationContext(precomposed) { _ in }
        repository.setEvaluationContext(decomposed) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        XCTAssertNotEqual(repository.state.currentState, .ready, "an older response for another wire identity published ready")
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        fetcher.completions[1](.failure(.networkError(URLError(.notConnectedToInternet))))
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.state.currentState, .error)
    }

    // MARK: - Verifier rules that no shared vector pins

    private func fixtureRequest(_ verifier: FlagsResponseVerifier) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return try verifier.prepare(request)
    }

    func testSignedResponseReportsOnlyTheVerifiedFlagSelectionIgnoredValue() throws {
        let listed: [(name: String, value: String?)] = [
            ("content-type", "application/json"), ("dd-flag-selection-ignored", "too_many_values")
        ]
        XCTAssertEqual(
            try selectionIgnoredErrors(mode: .required, signed: listed),
            ["`Flags.Configuration.flagSelection` was ignored by the server (too_many_values). Loaded the full flag configuration."]
        )
        // A listed header that is absent is verified as absent, and nothing is reported.
        XCTAssertEqual(try selectionIgnoredErrors(mode: .required, signed: SigningChainFixture.responseHeaders), [])
        // `observe` accepts a response that fails verification, but it never reads the raw header of a signed request.
        // A header that a proxy added after signing fails the signature.
        XCTAssertEqual(
            try selectionIgnoredErrors(
                mode: .observe,
                signed: SigningChainFixture.responseHeaders,
                added: ["dd-flag-selection-ignored": "too_many_values"]
            ),
            []
        )
        // A header that is present and not listed is not verified. With a selection, the list must name it.
        XCTAssertEqual(
            try selectionIgnoredErrors(
                mode: .observe,
                signed: [("content-type", "application/json")],
                added: ["dd-flag-selection-ignored": "too_many_values"]
            ),
            []
        )
    }

    /// A verified response header value never reaches the logs or the telemetry. They carry fixed values only.
    func testVerifiedResponseHeaderValuesNeverReachLogsOrTelemetry() throws {
        let secret = "secret-header-value-1234"
        let errors = try selectionIgnoredErrors(
            mode: .observe,
            signed: [("content-type", "application/json"), ("dd-flag-selection-ignored", secret)]
        ) { logger, scope in
            XCTAssertFalse(logger.recordedLogs.contains { $0.message.contains(secret) }, "A log carries a header value")
            XCTAssertFalse(
                scope.telemetryMock.messages.contains { String(describing: $0).contains(secret) },
                "Telemetry carries a header value"
            )
            XCTAssertTrue(logger.recordedLogs.contains { $0.message.contains("(unknown)") })
        }
        XCTAssertEqual(errors.count, 1)
    }

    /// The SDK request carries the selection at `data.attributes.flag_selection`. So in `required` mode a signed
    /// response list without `dd-flag-selection-ignored` is rejected, and the SDK does not hide an ignored selection.
    func testRequiredRejectsAResponseListWithoutSelectionIgnoredForTheSDKRequestEnvelope() throws {
        XCTAssertEqual(
            try selectionIgnoredErrors(
                mode: .required,
                signed: [("content-type", "application/json")],
                expectedFailureReason: "invalid-proof"
            ),
            [FlagsSigningError.invalidProof.logMessage]
        )
    }

    /// Fetches once with a flag selection through the signed path, and returns the error logs.
    private func selectionIgnoredErrors(
        mode: Flags.ResponseSigningMode,
        signed: [(name: String, value: String?)],
        added: [String: String] = [:],
        expectedFailureReason: String? = nil,
        inspect: ((CoreLoggerMock, FeatureScopeMock) -> Void)? = nil
    ) throws -> [String] {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let now = SigningChainFixture.now
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let body = Data.mockAnyFlagAssignmentsResponse()
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []),
            featureScope: scope,
            responseSigning: .init(mode: mode, trustedRootCertificates: [try SigningChainFixture.root("root-a")]),
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: now)),
            floorStore: InMemorySigningFloorStore(),
            signingFetch: { request, completion in
                do {
                    let fields = try fixture.signedHeaders(request: request, body: body, now: now, responseHeaders: signed)
                        .merging(added) { $1 }
                    let url = try XCTUnwrap(request.url)
                    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: fields))
                    completion(.success((body, response)))
                } catch { completion(.failure(error)) }
            },
            fetch: { _, _ in XCTFail("A signed fetch must not retry unsigned") }
        )
        let completed = expectation(description: "Fetch with a flag selection")
        var result: Result<FlagAssignmentsResponse, FlagsError>?
        fetcher.flagAssignments(for: .mockAny()) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        if let expectedFailureReason {
            guard case .failure(.responseSigningFailed(reason: expectedFailureReason)) = try XCTUnwrap(result) else {
                XCTFail("Expected responseSigningFailed(\(expectedFailureReason)), got \(String(describing: result))")
                return dd.logger.errorMessages
            }
        } else {
            XCTAssertEqual(try XCTUnwrap(result).get().flags, .mockAny())
        }
        inspect?(dd.logger, scope)
        return dd.logger.errorMessages
    }

    func testCertificateIDMustMatchTheLeaf() throws {
        let verifier = try requiredVerifier(store: MinimumNotBeforeStoreMock())
        let prepared = try fixtureRequest(verifier)
        let body = Data.mockAnyFlagAssignmentsResponse()
        var headers = try SigningChainFixture.credential("two-intermediates").signedHeaders(request: prepared, body: body)
        // The certificate id is not in the transcript, so only this check rejects another valid-looking id.
        headers[FlagsResponseVerifier.prefix + "certificate-id"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try verifier.verify(
            request: prepared, response: try response(prepared, headers), body: body, now: Date(timeIntervalSince1970: SigningChainFixture.now)
        )) { XCTAssertEqual($0 as? FlagsSigningError, .invalidProof) }
    }

    func testIssuedAtUpToThirtySecondsInTheFutureIsAccepted() throws {
        let verifier = try requiredVerifier(store: MinimumNotBeforeStoreMock())
        let prepared = try fixtureRequest(verifier)
        let body = Data.mockAnyFlagAssignmentsResponse()
        let issued = SigningChainFixture.now
        let headers = try SigningChainFixture.credential("two-intermediates").signedHeaders(request: prepared, body: body, now: issued)
        let signed = try response(prepared, headers)
        XCTAssertNoThrow(try verifier.verify(request: prepared, response: signed, body: body, now: Date(timeIntervalSince1970: issued - 30)))
        // A new verifier: the accepted response moved the high-water mark to `issued`.
        let fresh = try requiredVerifier(store: MinimumNotBeforeStoreMock())
        XCTAssertThrowsError(try fresh.verify(request: prepared, response: signed, body: body, now: Date(timeIntervalSince1970: issued - 31))) {
            XCTAssertEqual($0 as? FlagsSigningError, .expiredProof)
        }
    }

    func testOnlyHTTP200IsVerified() throws {
        let verifier = try requiredVerifier(store: MinimumNotBeforeStoreMock())
        let prepared = try fixtureRequest(verifier)
        let body = Data.mockAnyFlagAssignmentsResponse()
        // Signed for status 201, so only the status rule rejects it.
        let headers = try SigningChainFixture.credential("two-intermediates").signedHeaders(request: prepared, body: body, status: 201)
        let created = try XCTUnwrap(HTTPURLResponse(url: prepared.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: headers))
        XCTAssertThrowsError(try verifier.verify(request: prepared, response: created, body: body, now: Date(timeIntervalSince1970: SigningChainFixture.now))) {
            XCTAssertEqual($0 as? FlagsSigningError, .invalidProof)
        }
    }

    func testBodyLargerThanTheSignedLimitIsRejected() throws {
        let verifier = try requiredVerifier(store: MinimumNotBeforeStoreMock())
        let prepared = try fixtureRequest(verifier)
        let body = Data(repeating: 32, count: FlagsResponseVerifier.maximumResponseBytes + 1)
        let headers = try SigningChainFixture.credential("two-intermediates").signedHeaders(request: prepared, body: Data("{}".utf8))
        XCTAssertThrowsError(try verifier.verify(
            request: prepared, response: try response(prepared, headers), body: body, now: Date(timeIntervalSince1970: SigningChainFixture.now)
        )) { XCTAssertEqual($0 as? FlagsSigningError, .responseTooLarge) }
    }

    func testMoreThanFourRootsFailPrepareClosedInRequiredAndUnsignedInObserve() throws {
        let roots = try Array(repeating: SigningChainFixture.root("root-a"), count: 5)
        for mode in [Flags.ResponseSigningMode.required, .observe] {
            var sent: [URLRequest] = []
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: URL(string: "https://flags.example.test/precompute-assignments"),
                customHeaders: nil,
                flagSelection: nil,
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
                responseSigning: .init(mode: mode, trustedRootCertificates: roots),
                floorStore: InMemorySigningFloorStore(),
                signingFetch: { request, complete in
                    sent.append(request)
                    complete(.success((.mockAnyFlagAssignmentsResponse(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)))
                },
                fetch: { _, _ in XCTFail("Signing must use the signing transport") }
            )
            let done = expectation(description: "\(mode)")
            fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                defer { done.fulfill() }
                switch (mode, result) {
                case (.required, .failure(.responseSigningFailed(reason: "invalid-certificate"))): XCTAssertTrue(sent.isEmpty)
                case (.observe, .success(let response)):
                    XCTAssertNil(response.verification)
                    // observe sends the ordinary request, with no signing headers.
                    XCTAssertEqual(sent.count, 1)
                    XCTAssertNil(sent.first?.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "request-nonce"))
                default: XCTFail("\(mode): \(result)")
                }
            }
            wait(for: [done], timeout: 2)
        }
    }

    // MARK: - Verifier parity with the browser

    func testCertificateNotSignedByItsIssuerIsAnInvalidCertificate() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        var leafDER = fixture.leaf
        leafDER[leafDER.count - 1] ^= 0x01 // the last byte of the leaf signature
        let leaf = try FlagsSigningCertificate(der: leafDER, role: .leaf)
        let issuer = try FlagsSigningCertificate(der: XCTUnwrap(fixture.intermediates.first), role: .intermediate)
        XCTAssertThrowsError(try FlagsResponseVerifier.verifyChild(leaf, parent: issuer)) {
            XCTAssertEqual($0 as? FlagsSigningError, .invalidCertificate)
        }
    }

    func testMalformedTimeValuesAreRejectedAnywhereInTheDER() {
        func sequence(_ tag: UInt8, _ value: String) -> Data {
            let time = [tag, UInt8(value.utf8.count)] + Array(value.utf8)
            return Data([48, UInt8(time.count)] + time)
        }
        XCTAssertNoThrow(try FlagsSigningDER.parse(sequence(23, "261121000000Z")))
        XCTAssertNoThrow(try FlagsSigningDER.parse(sequence(24, "20261121000000Z")))
        for (tag, value) in [(UInt8(23), "26112100000Z"), (23, "2611210000a0Z"), (23, "261321000000Z"), (24, "20261121000000"), (24, "2026112100000+Z")] {
            XCTAssertThrowsError(try FlagsSigningDER.parse(sequence(tag, value)), value)
        }
    }

    /// The shared vectors pin only a non-critical PolicyMappings. NameConstraints, PolicyConstraints and
    /// InhibitAnyPolicy must also fail when they are not critical. The leaf parser rejects them before any
    /// signature check, so a swapped OID byte isolates the rule.
    func testNonCriticalConstraintExtensionsAreRejected() throws {
        let url = try SharedSigningFixtures.url("response-signing-v1", "extension-profile", "json")
        let profile = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(profile["cases"] as? [[String: Any]])
        let vector = try XCTUnwrap(cases.first { $0["id"] as? String == "noncritical-policy-mappings" })
        let response = try XCTUnwrap(vector["response"] as? [String: Any])
        let headers = try XCTUnwrap(response["headers"] as? [[String]])
        let encoded = try XCTUnwrap(headers.first { $0.first == FlagsResponseVerifier.prefix + "signing-certificate" }?.last)
        let leaf = try XCTUnwrap(Data(base64Encoded: encoded))
        let policyMappings = Data([6, 3, 85, 29, 33])
        let range = try XCTUnwrap(leaf.range(of: policyMappings))
        func swappingLastOIDByte(_ byte: UInt8) -> Data {
            var data = leaf
            data[range.upperBound - 1] = byte
            return data
        }
        // Control: certificatePolicies (2.5.29.32) is not a constraint, so the same non-critical slot parses.
        XCTAssertNoThrow(try FlagsSigningCertificate(der: swappingLastOIDByte(32), role: .leaf))
        // NameConstraints (2.5.29.30), PolicyMappings (.33), PolicyConstraints (.36), InhibitAnyPolicy (.54).
        for byte: UInt8 in [30, 33, 36, 54] {
            XCTAssertThrowsError(try FlagsSigningCertificate(der: swappingLastOIDByte(byte), role: .leaf), "2.5.29.\(byte)") {
                XCTAssertEqual($0 as? FlagsSigningError, .invalidCertificate, "2.5.29.\(byte)")
            }
        }
    }

    // MARK: - Scope update work and session lifetime

    func testScopeUpdateSkipsWorkWhenNoInputChanged() {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            responseSigning: .init(mode: .observe),
            floorStore: InMemorySigningFloorStore(),
            fetch: { _, _ in XCTFail("no network expected") }
        )
        let base = DatadogContext.mockWith(clientToken: "token", env: "staging", source: "ios")
        let first = fetcher.updateResponseSigningCacheScope(base)
        XCTAssertNotNil(first)
        var rum = base
        rum.set(additionalContext: RUMCoreContext.mockWith(applicationID: "app-a"))
        XCTAssertEqual(fetcher.updateResponseSigningCacheScope(rum), first)
        // A real input change still computes a new scope.
        XCTAssertNotEqual(fetcher.updateResponseSigningCacheScope(.mockWith(clientToken: "token", env: "prod", source: "ios")), first)
        XCTAssertEqual(fetcher.updateResponseSigningCacheScope(base), first)
    }

    func testFeatureLifetimeInvalidatesTheSigningSession() throws {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"),
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            responseSigning: .init(mode: .required)
        )
        XCTAssertNotNil(fetcher.responseSigningSession)
        var lifetime: FlagsSigningLifetime? = FlagsSigningLifetime(fetcher: fetcher)
        XCTAssertNotNil(lifetime)
        XCTAssertFalse(fetcher.hasInvalidatedSigningSession)
        lifetime = nil
        XCTAssertTrue(fetcher.hasInvalidatedSigningSession)
        XCTAssertNil(FlagAssignmentsFetcher(
            customEndpoint: nil, customHeaders: nil, flagSelection: nil, featureScope: FeatureScopeMock()
        ).responseSigningSession, "Signing off has no signing session")
    }
}

extension FlagsResponseSigningTests {
    // MARK: - Backward clock steps

    func testBackwardClockStepIsToleratedUpToThirtySecondsThenHandledAsExpiryAndRecovers() {
        for strict in [false, true] {
            let fetcher = SigningLifecycleFetcher(mode: .required)
            fetcher.trustExpired = !strict
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { _, _ in }
            )
            defer { repository.flush() }
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { _ in }
            fetcher.completeVerified(index: 0, expiry: 200) // verified at 100
            // A step of 30 s back keeps the proof fresh.
            clock.now = Date(timeIntervalSince1970: 70)
            XCTAssertNotNil(repository.flagAssignment(for: "flag"), "strict=\(strict)")
            XCTAssertEqual(repository.state.currentState, .ready, "strict=\(strict)")
            // A larger step is handled as expiry.
            clock.now = Date(timeIntervalSince1970: 69)
            XCTAssertEqual(repository.flagAssignment(for: "flag") != nil, !strict, "strict=\(strict)")
            XCTAssertEqual(repository.state.currentState, strict ? .error : .stale, "strict=\(strict)")
            // The clock returns into the proof window: the client gets back the state from before the step.
            clock.now = Date(timeIntervalSince1970: 150)
            XCTAssertNotNil(repository.flagAssignment(for: "flag"), "strict=\(strict)")
            XCTAssertEqual(repository.state.currentState, .ready, "strict=\(strict)")
        }
    }

    /// A state update between the clock step and the return wins: the client does not go back to `ready`.
    func testClockReturnDoesNotRestoreReadyAfterAFailedRefreshInBetween() {
        let fetcher = SigningLifecycleFetcher(mode: .required)
        fetcher.trustExpired = true
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
        let repository = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil,
            scheduleExpiry: { _, _ in }
        )
        defer { repository.flush() }
        let context = FlagsEvaluationContext(targetingKey: "subject")
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        clock.now = Date(timeIntervalSince1970: 69)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.state.currentState, .stale)
        repository.setEvaluationContext(context) { _ in }
        fetcher.completions[1](.failure(.networkError(URLError(.notConnectedToInternet))))
        XCTAssertEqual(repository.state.currentState, .stale)
        clock.now = Date(timeIntervalSince1970: 150)
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.state.currentState, .stale)
    }

    func testProofValidityToleratesThirtySecondsBeforeVerification() {
        let proof = FlagsResponseVerification(scope: UUID(), verifiedAt: 100, expiresAt: 200)
        XCTAssertTrue(proof.isValid(at: Date(timeIntervalSince1970: 70), scope: proof.scope))
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 69), scope: proof.scope))
        XCTAssertTrue(proof.isValid(at: Date(timeIntervalSince1970: 69), scope: proof.scope, allowExpired: true))
        XCTAssertFalse(proof.isValid(at: Date(timeIntervalSince1970: 69), scope: UUID(), allowExpired: true))
    }

    // MARK: - expireVerifiedFlags through the real fetcher

    private func realSigningFetcher(
        expireVerifiedFlags: Bool,
        clock: DateProviderMock,
        body: Data,
        fails: @escaping () -> Bool = { false }
    ) throws -> FlagAssignmentsFetcher {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        return FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://flags.example.test/precompute-assignments"),
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
            responseSigning: .init(
                mode: .required,
                trustedRootCertificates: [try SigningChainFixture.root("root-a")],
                expireVerifiedFlags: expireVerifiedFlags
            ),
            dateProvider: clock,
            floorStore: MinimumNotBeforeStoreMock(),
            signingFetch: { request, complete in
                if fails() {
                    return complete(.failure(URLError(.notConnectedToInternet)))
                }
                do {
                    let headers = try fixture.signedHeaders(request: request, body: body)
                    complete(.success((body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                } catch {
                    complete(.failure(error))
                }
            },
            fetch: { _, _ in XCTFail("Signing must use the signing transport") }
        )
    }

    func testRealFetcherAppliesExpireVerifiedFlagsAcrossExpiresAt() throws {
        for strict in [false, true] {
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
            let body = Data.mockAnyFlagAssignmentsResponse()
            let fetcher = try realSigningFetcher(expireVerifiedFlags: strict, clock: clock, body: body)
            let repository = FlagsRepository(
                clientName: "signed-\(strict)",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { _, _ in }
            )
            defer { repository.flush() }
            let done = expectation(description: "context \(strict)")
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { result in
                if case .failure(let error) = result { XCTFail("\(error)") }
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            let proof = try XCTUnwrap(repository.assignmentsSnapshot()?.verification)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertFalse(try XCTUnwrap(repository.flagAssignments()).isEmpty)

            // The fixture proof expires 300 s after it was issued.
            clock.now = Date(timeIntervalSince1970: SigningChainFixture.now + 300)
            XCTAssertFalse(fetcher.isVerified(proof, at: clock.now))
            XCTAssertEqual(fetcher.isTrusted(proof, at: clock.now), !strict, "strict=\(strict)")
            XCTAssertEqual(repository.flagAssignments().map { !$0.isEmpty } ?? false, !strict, "strict=\(strict)")
            XCTAssertEqual(repository.state.currentState, strict ? .error : .stale, "strict=\(strict)")
        }
    }

    /// `expireVerifiedFlags` applies to `required` only. In `observe`, an expired proof must not make older verified
    /// flags win the failure fallback over newer unverified flags.
    func testObserveFallbackDoesNotPreferAnExpiredVerifiedResponse() throws {
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
        let verifiedBody = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["old": .mockAnyBoolean()]))
        let unverifiedBody = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["new": .mockAnyBoolean()]))
        var calls = 0
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://flags.example.test/precompute-assignments"),
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
            responseSigning: .init(mode: .observe, trustedRootCertificates: [try SigningChainFixture.root("root-a")]),
            dateProvider: clock,
            floorStore: MinimumNotBeforeStoreMock(),
            signingFetch: { request, complete in
                calls += 1
                switch calls {
                case 1:
                    do {
                        let headers = try fixture.signedHeaders(request: request, body: verifiedBody)
                        complete(.success((verifiedBody, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)))
                    } catch { complete(.failure(error)) }
                case 2:
                    complete(.success((unverifiedBody, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)))
                default:
                    complete(.failure(URLError(.notConnectedToInternet)))
                }
            },
            fetch: { _, _ in XCTFail("Signing must use the signing transport") }
        )
        let repository = FlagsRepository(
            clientName: "observe-fallback",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(),
            flagSelection: nil,
            initializationTimeout: nil,
            scheduleExpiry: { _, _ in }
        )
        defer { repository.flush() }
        let context = FlagsEvaluationContext(targetingKey: "subject")
        for _ in 0..<3 {
            let done = expectation(description: "context update")
            repository.setEvaluationContext(context) { _ in done.fulfill() }
            wait(for: [done], timeout: 2)
            if calls == 2 {
                XCTAssertNotNil(repository.flagAssignment(for: "new"))
                // The fixture proof expires 300 s after it was issued.
                clock.now = Date(timeIntervalSince1970: SigningChainFixture.now + 300)
            }
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(repository.state.currentState, .stale)
        XCTAssertNotNil(repository.flagAssignment(for: "new"), "observe restored the expired verified flags")
        XCTAssertNil(repository.flagAssignment(for: "old"))
    }

    /// The fetcher verifies the proof, but the proof expires before the repository admits it. In the default setting,
    /// `isTrusted` still accepts it, so only the outer admission check can reject the response.
    /// A response that verified but crossed `expires-at` before admission is installed as `stale` and kept as the
    /// verified fallback. With `expireVerifiedFlags`, it is rejected with `expired-proof`.
    func testProofThatExpiredBeforeAdmissionIsStaleOrRejectedWhenStrict() throws {
        for strict in [false, true] {
            let fetcherClock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
            let repositoryClock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now + 400))
            let body = Data.mockAnyFlagAssignmentsResponse()
            var offline = false
            let fetcher = try realSigningFetcher(expireVerifiedFlags: strict, clock: fetcherClock, body: body) { offline }
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: repositoryClock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { _, _ in }
            )
            defer { repository.flush() }
            let context = FlagsEvaluationContext(targetingKey: "subject")
            let done = expectation(description: "context")
            repository.setEvaluationContext(context) { result in
                defer { done.fulfill() }
                switch (strict, result) {
                case (false, .success), (true, .failure(.responseSigningFailed(reason: "expired-proof"))): break
                default: XCTFail("strict \(strict): \(result)")
                }
            }
            wait(for: [done], timeout: 2)
            if strict {
                XCTAssertNil(repository.flagAssignments())
                XCTAssertEqual(repository.state.currentState, .error)
                continue
            }
            XCTAssertEqual(repository.state.currentState, .stale, "Not ready: the proof expired before admission")
            XCTAssertEqual(repository.flagAssignments(), .mockAny())
            // The response is the verified fallback: a failed refresh of the same context keeps serving it.
            offline = true
            let refreshed = expectation(description: "refresh")
            repository.setEvaluationContext(context) { _ in refreshed.fulfill() }
            wait(for: [refreshed], timeout: 2)
            XCTAssertEqual(repository.state.currentState, .stale)
            XCTAssertEqual(repository.flagAssignments(), .mockAny())
        }
    }

    /// The proof expires between admission and install. One clock read decides the install: strict policy fails with
    /// `expired-proof`, installs nothing, starts no proof timer and publishes no `ready` or `stale`. The default policy
    /// installs the response as `stale`.
    func testProofThatExpiresBetweenAdmissionAndInstallFollowsOneClockRead() throws {
        for strict in [false, true] {
            let fetcherClock = DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now))
            let repositoryClock = SteppingDateProvider(
                first: Date(timeIntervalSince1970: SigningChainFixture.now),
                then: Date(timeIntervalSince1970: SigningChainFixture.now + 400)
            )
            let body = Data.mockAnyFlagAssignmentsResponse()
            let fetcher = try realSigningFetcher(expireVerifiedFlags: strict, clock: fetcherClock, body: body) {
                // The next repository read is the admission check. Every later read is after `expires-at`.
                repositoryClock.step()
                return false
            }
            var timers = 0
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: repositoryClock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { _, _ in timers += 1 }
            )
            defer { repository.flush() }
            let listener = SigningStateRecorder()
            repository.state.addListener(listener)
            defer { repository.state.removeListener(listener) }
            let done = expectation(description: "context")
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "subject")) { result in
                defer { done.fulfill() }
                switch (strict, result) {
                case (false, .success), (true, .failure(.responseSigningFailed(reason: "expired-proof"))): break
                default: XCTFail("strict \(strict): \(result)")
                }
            }
            wait(for: [done], timeout: 2)
            if strict {
                XCTAssertNil(repository.flagAssignments())
                XCTAssertEqual(repository.state.currentState, .error)
                XCTAssertFalse(listener.states.contains(.ready) || listener.states.contains(.stale), "\(listener.states)")
                XCTAssertEqual(timers, 0, "No proof timer for a snapshot that was not installed")
            } else {
                XCTAssertEqual(repository.state.currentState, .stale)
                XCTAssertFalse(listener.states.contains(.ready), "\(listener.states)")
                XCTAssertEqual(repository.flagAssignments(), .mockAny())
            }
        }
    }

    // MARK: - Expiry while a refresh is reconciling

    func testProofExpiryAppliesWhileReconcilingAndKeepsThePendingRequest() {
        for strict in [false, true] {
            let fetcher = SigningLifecycleFetcher(mode: .required)
            fetcher.trustExpired = !strict
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: 100))
            var scheduled: [() -> Void] = []
            let repository = FlagsRepository(
                clientName: "signed",
                flagAssignmentsFetcher: fetcher,
                dateProvider: clock,
                featureScope: FeatureScopeMock(),
                flagSelection: nil,
                initializationTimeout: nil,
                scheduleExpiry: { scheduled.append($1) }
            )
            defer { repository.flush() }
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "a")) { _ in }
            fetcher.completeVerified(index: 0, expiry: 200)
            var completed: Result<Void, FlagsError>?
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "b")) { completed = $0 }
            XCTAssertEqual(repository.state.currentState, .reconciling, "strict=\(strict)")
            // The proof of `a` expires while the refresh for `b` is in flight.
            clock.now = Date(timeIntervalSince1970: 200)
            scheduled.forEach { $0() }
            XCTAssertEqual(repository.state.currentState, strict ? .error : .stale, "strict=\(strict)")
            XCTAssertNil(completed, "The pending request is kept")
            // A verified response for `b` restores `ready`.
            fetcher.completeVerified(index: 1, expiry: 500)
            XCTAssertEqual(repository.state.currentState, .ready, "strict=\(strict)")
            XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        }
    }
}

/// Test-CA-issued certificate-chain credentials and pinned roots from the shared `response-signing-chain` source.
internal struct SigningChainFixture {
    /// The shared `now` of the chain fixtures, from `chain/manifest.json` (1795089600, 2026-11-19T12:00:00Z).
    /// It is inside every fixture leaf's 72-hour validity.
    static let now: TimeInterval = {
        guard let url = try? url("manifest", "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let now = (json["now"] as? NSNumber)?.doubleValue
        else {
            XCTFail("The chain manifest has no `now`. Run `make feature-flags-fixtures-pull`.")
            return 0
        }
        return now
    }()

    let key: P256.Signing.PrivateKey
    let leaf: Data
    let intermediates: [Data]

    private struct Credential: Decodable {
        let private_key_pkcs8_der_base64: String
        let certificate_der_base64: String
        let intermediates_der_base64: [String]
    }

    private static func url(_ name: String, _ ext: String) throws -> URL {
        try SharedSigningFixtures.url("response-signing-chain", name, ext)
    }

    static func credential(_ name: String) throws -> SigningChainFixture {
        let credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: url(name, "json")))
        return SigningChainFixture(
            key: try P256.Signing.PrivateKey(
                derRepresentation: XCTUnwrap(Data(base64Encoded: credential.private_key_pkcs8_der_base64))
            ),
            leaf: try XCTUnwrap(Data(base64Encoded: credential.certificate_der_base64)),
            intermediates: try credential.intermediates_der_base64.map { try XCTUnwrap(Data(base64Encoded: $0)) }
        )
    }

    static func root(_ name: String) throws -> Data {
        let pem = try String(contentsOf: url(name, "pem"), encoding: .ascii)
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return try XCTUnwrap(Data(base64Encoded: body))
    }

    /// The default signed response list of the edge: `content-type,dd-flag-selection-ignored`.
    static let responseHeaders: [(name: String, value: String?)] = [
        ("content-type", "application/json"), ("dd-flag-selection-ignored", nil)
    ]

    /// Edge-equivalent v1 proof headers for `request` and `body`, signed with the fixture key.
    /// The result also has the listed response headers that are present.
    func signedHeaders(
        request: URLRequest,
        body: Data,
        now: TimeInterval = now,
        minimumNotBefore: UInt64? = nil,
        status: Int = 200,
        responseHeaders: [(name: String, value: String?)] = responseHeaders
    ) throws -> [String: String] {
        let prefix = FlagsResponseVerifier.prefix
        let transcript = try FlagsResponseVerifier.transcript(
            request: request,
            status: status,
            body: body,
            issuedAt: UInt64(now),
            expiresAt: UInt64(now + 300),
            leaf: leaf,
            intermediates: intermediates,
            responseHeaders: responseHeaders,
            minimumNotBefore: minimumNotBefore
        )
        var headers = [
            prefix + "signature-version": "1",
            prefix + "signing-certificate": leaf.base64EncodedString(),
            prefix + "signing-chain": intermediates.map { $0.base64EncodedString() }.joined(separator: ","),
            prefix + "certificate-id": SHA256.hash(data: leaf).map { String(format: "%02x", $0) }.joined(),
            prefix + "issued-at": String(UInt64(now)),
            prefix + "expires-at": String(UInt64(now + 300)),
            prefix + "signature": try key.signature(for: transcript).derRepresentation.base64EncodedString(),
            prefix + "signed-response-headers": responseHeaders.map(\.name).joined(separator: ",")
        ]
        for case let (name, value?) in responseHeaders {
            headers[name] = value
        }
        if let minimumNotBefore {
            headers[prefix + "minimum-leaf-not-before"] = String(minimumNotBefore)
        }
        return headers
    }

    /// The lowest `notBefore` of the leaf and the intermediates.
    func oldestNotBefore() throws -> UInt64 {
        let chain = try [FlagsSigningCertificate(der: leaf, role: .leaf)]
            + intermediates.map { try FlagsSigningCertificate(der: $0, role: .intermediate) }
        return UInt64(chain.map(\.notBefore).min() ?? 0)
    }

    func leafNotBefore() throws -> UInt64 {
        UInt64(try FlagsSigningCertificate(der: leaf, role: .leaf).notBefore)
    }
}

/// Answers reads after a delay on another queue, like a slow disk.
private final class SlowDataStore: DataStore {
    private let wrapped: DataStoreMock
    private let delay: TimeInterval

    init(wrapping wrapped: DataStoreMock, delay: TimeInterval) {
        self.wrapped = wrapped
        self.delay = delay
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        wrapped.setValue(value, forKey: key, version: version)
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [wrapped] in
            wrapped.value(forKey: key, callback: callback)
        }
    }

    func removeValue(forKey key: String) { wrapped.removeValue(forKey: key) }
    func clearAllData() { wrapped.clearAllData() }
    func flush() { wrapped.flush() }
}

/// Returns `first` until `step()`. After `step()`, it returns `first` once more, then `then`.
private final class SigningStateRecorder: FlagsStateListener {
    private let lock = NSLock()
    private var recorded: [FlagsClientState] = []
    var states: [FlagsClientState] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
    func flagsStateDidChange(_ newState: FlagsClientState) {
        lock.lock()
        recorded.append(newState)
        lock.unlock()
    }
}

private final class SteppingDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let first: Date
    private let then: Date
    private var remainingFirstReads: Int?

    init(first: Date, then: Date) {
        self.first = first
        self.then = then
    }

    func step() {
        lock.lock()
        remainingFirstReads = 1
        lock.unlock()
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        guard let remaining = remainingFirstReads else {
            return first
        }
        remainingFirstReads = max(0, remaining - 1)
        return remaining > 0 ? first : then
    }
}

private final class KeychainMock: FlagsKeychain {
    var items: [String: Data] = [:]
    var fails = false
    /// The number of next reads that fail, for example before the first unlock.
    var failingReads = 0
    var failureStatus = errSecNotAvailable
    func read(account: String) throws -> Data? {
        if fails || failingReads > 0 {
            failingReads = max(0, failingReads - 1)
            throw SystemFlagsKeychain.Failure(status: failureStatus)
        }
        return items[account]
    }
    func write(_ data: Data, account: String) throws {
        if fails {
            throw SystemFlagsKeychain.Failure(status: failureStatus)
        }
        items[account] = data
    }
}

private final class MinimumNotBeforeStoreMock: FlagsSigningFloorStore {
    var values: [String: UInt64] = [:]
    func value(forKey anchor: String, waitForRead: Bool) -> UInt64? { values[anchor] }
    func store(_ value: UInt64, forKey anchor: String) {
        values[anchor] = max(values[anchor] ?? 0, value)
    }
}

/// Shared signing fixtures are git-ignored and fetched by `make feature-flags-fixtures-pull`, like the precomputed corpus.
private enum SharedSigningFixtures {
    static func url(_ folder: String, _ name: String, _ ext: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Client
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DatadogFlags
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(folder)
            .appendingPathComponent(name + "." + ext)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Shared fixture \(folder)/\(name).\(ext) is missing. Run `make feature-flags-fixtures-pull`.")
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}

private final class SigningLifecycleFetcher: FlagAssignmentsFetching {
    let responseSigningMode: Flags.ResponseSigningMode
    let scope = UUID()
    var responseSigningCacheScope: String? = "scope-a"
    var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
    init(mode: Flags.ResponseSigningMode) { responseSigningMode = mode }
    var trustExpired = false
    func isVerified(_ proof: FlagsResponseVerification?, at now: Date) -> Bool {
        proof?.cacheScope == responseSigningCacheScope && proof?.isValid(at: now, scope: scope) == true
    }
    func isTrusted(_ proof: FlagsResponseVerification?, at now: Date) -> Bool {
        proof?.cacheScope == responseSigningCacheScope
            && proof?.isValid(at: now, scope: scope, allowExpired: trustExpired) == true
    }
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
        assignmentToken: String?,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        completions.append(completion)
    }
    func completeVerified(index: Int, expiry: TimeInterval) {
        var response = FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()])
        response.verification = .init(
            scope: scope,
            verifiedAt: 100,
            expiresAt: expiry,
            cacheScope: responseSigningCacheScope
        )
        response.responseSigningCacheScope = responseSigningCacheScope
        completions[index](.success(response))
    }
}

private final class SigningDataStoreSpy: DataStore {
    private let store = DataStoreMock()
    var keys = Set<String>()
    var reads = 0
    var writes = 0
    var removals = 0
    /// Reads of the earlier signing floor file, which the Keychain store migrates. They are not flag data.
    var signingFloorReads = 0
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        reads += 1
        let floorKinds = [FlagsResponseVerifier.leafFloorKey(""), FlagsResponseVerifier.highWaterMarkKey("")]
        if floorKinds.contains(where: { key.hasPrefix(DataStoreSigningFloorStore.keyPrefix + $0) }) {
            signingFloorReads += 1
        }
        store.value(forKey: key, callback: callback)
    }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        writes += 1
        keys.insert(key)
        store.setValue(value, forKey: key, version: version)
    }
    func removeValue(forKey key: String) {
        removals += 1
        keys.remove(key)
        store.removeValue(forKey: key)
    }
    func clearAllData() {}
    func flush() {}
}
