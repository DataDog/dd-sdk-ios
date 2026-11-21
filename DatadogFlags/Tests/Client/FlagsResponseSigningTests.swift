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
                signingFetch: { _, _ in XCTFail("Required signing outside staging must not send a request") },
                fetch: { _, _ in XCTFail("Required signing outside staging must not send a request") }
            )
            // Every fetch returns the same error.
            for _ in 0..<2 {
                let done = expectation(description: "fetch")
                fetcher.flagAssignments(for: FlagsEvaluationContext(targetingKey: "subject")) { result in
                    defer { done.fulfill() }
                    guard case .failure(.invalidConfiguration) = result else {
                        return XCTFail("Expected invalidConfiguration, got \(result)")
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
                guard case .failure(.invalidConfiguration) = result else {
                    return XCTFail("Expected invalidConfiguration, got \(result)")
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
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .required))
        let first = try verifier.prepare(request)
        let second = try verifier.prepare(request)
        XCTAssertNil(first.value(forHTTPHeaderField: "X-stream"))
        XCTAssertEqual(first.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities"), "response-signing-v1")
        XCTAssertEqual(first.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version"), "1")
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
                guard case let .debug(id, text, _) = message, text == "Flags response signing" else {
                    return nil
                }
                return id
            }
            XCTAssertEqual(reports, ["flags-response-signing-missingProof"], "\(mode)")
            switch (mode, try XCTUnwrap(result)) {
            case (.observe, .success(let response)):
                XCTAssertFalse(response.flags.isEmpty)
                XCTAssertNil(response.verification, "An unsigned response is never verified")
            case (.required, .failure(.invalidResponse)):
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
                    let prefix = FlagsResponseVerifier.prefix
                    let chain = try XCTUnwrap(responseHeaders[prefix + "signing-chain"], name)
                        .split(separator: ",").map { try XCTUnwrap(Data(base64Encoded: String($0))) }
                    let transcript = try FlagsResponseVerifier.transcript(
                        request: request,
                        status: response.statusCode,
                        body: body,
                        issuedAt: try XCTUnwrap(UInt64(XCTUnwrap(responseHeaders[prefix + "issued-at"]))),
                        expiresAt: try XCTUnwrap(UInt64(XCTUnwrap(responseHeaders[prefix + "expires-at"]))),
                        leaf: try XCTUnwrap(Data(base64Encoded: XCTUnwrap(responseHeaders[prefix + "signing-certificate"]))),
                        intermediates: chain
                    )
                    XCTAssertEqual(transcript.base64EncodedString(), vector.transcript_base64, name)
                } else {
                    // `rejection_reason` is a stable fixture code, not a native error; assert only the rejection.
                    XCTAssertThrowsError(try verifier.verify(request: request, response: response, body: body, now: now), name)
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
            guard case let .debug(id, text, _) = message, text == "Flags response signing" else {
                return nil
            }
            return id
        }
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(Set(reports).count, 2, "Each bounded outcome must survive downstream ID deduplication")
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
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .observe, trustedRootCertificates: [Data([1])]))
        func scope(_ value: URLRequest, environment: String = "prod") -> String {
            verifier.cacheScope(request: value, environment: environment, customHeaderNames: ["x-custom"])
        }
        let original = scope(request)
        XCTAssertNotEqual(original, scope(request, environment: "staging"))
        for (header, value) in [
            ("dd-client-token", "token-b"), ("dd-application-id", "app-b"), ("authorization", "Bearer test"),
            ("x-custom", "new")
        ] {
            var changed = request
            changed.setValue(value, forHTTPHeaderField: header)
            XCTAssertNotEqual(original, scope(changed), header)
        }
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
            env: "prod",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "app-b")]
        )
        XCTAssertTrue(receiver.receive(message: .context(changed), from: core))
        XCTAssertNotEqual(original, fetcher.responseSigningCacheScope)
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
            intermediates: fixture.intermediates
        )
        XCTAssertTrue(transcript.starts(with: Data("datadog.feature-flags.precomputed-assignments.v1\0".utf8)))
        var tail = Data(SHA256.hash(data: body))
        tail.append(Data(SHA256.hash(data: fixture.leaf)))
        tail.append(UInt8(fixture.intermediates.count))
        for intermediate in fixture.intermediates { tail.append(Data(SHA256.hash(data: intermediate))) }
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
                intermediates: fixture.intermediates.reversed()
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
                    intermediates: Array(repeating: fixture.leaf, count: count)
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
                intermediates: fixture.intermediates
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
        changeHeader: ((inout [String: String]) -> Void)? = nil
    ) throws -> (URLRequest, HTTPURLResponse, Data) {
        var request = URLRequest(url: URL(string: "https://flags.example.test/precompute-assignments")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("fixture-token", forHTTPHeaderField: "dd-client-token")
        let prepared = try verifier.prepare(request)
        let body = Data.mockAnyFlagAssignmentsResponse()
        var headers = try SigningChainFixture.credential(name)
            .signedHeaders(request: prepared, body: body, minimumNotBefore: minimumNotBefore)
        changeHeader?(&headers)
        return (prepared, try response(prepared, headers), body)
    }

    private func verify(_ verifier: FlagsResponseVerifier, _ signed: (URLRequest, HTTPURLResponse, Data)) throws -> FlagsResponseVerification {
        try verifier.verify(
            request: signed.0,
            response: signed.1,
            body: signed.2,
            now: Date(timeIntervalSince1970: SigningChainFixture.now)
        )
    }

    func testMinimumNotBeforeRevokesAnOlderChainAndSurvivesARestart() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let anchorKey = SHA256.hash(data: anchor).map { String(format: "%02x", $0) }.joined()
        let store = MinimumNotBeforeStoreMock()
        let configuration = Flags.ResponseSigningConfiguration(mode: .required, trustedRootCertificates: [anchor])
        let verifier = FlagsResponseVerifier(configuration: configuration, minimumNotBeforeStore: store)
        let newChain = try SigningChainFixture.credential("one-intermediate")
        let oldChain = try SigningChainFixture.credential("two-intermediates")
        let value = try newChain.oldestNotBefore()
        XCTAssertGreaterThan(value, try oldChain.oldestNotBefore(), "The fixtures must have an older chain")

        // Without a stored value, both chains verify.
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates")))
        // The new chain carries the value, and the SDK stores it.
        let proof = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value))
        XCTAssertFalse(proof.ignoredMinimumNotBefore)
        XCTAssertEqual(store.values[anchorKey], value)
        // The old chain is now revoked. The new chain still verifies.
        XCTAssertThrowsError(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates"))) {
            XCTAssertEqual($0 as? FlagsSigningError, .revokedCertificate)
        }
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate")))

        // A restart creates a new verifier with the same persisted store.
        let restarted = FlagsResponseVerifier(configuration: configuration, minimumNotBeforeStore: store)
        XCTAssertThrowsError(try verify(restarted, signedFixtureResponse(restarted, "two-intermediates"))) {
            XCTAssertEqual($0 as? FlagsSigningError, .revokedCertificate)
        }
    }

    func testMinimumNotBeforeDataStoreKeepsTheHighestValueAcrossARestart() throws {
        let dataStore = DataStoreMock()
        let first = DataStoreMinimumNotBeforeStore(dataStore: dataStore)
        XCTAssertNil(first.value(forAnchor: "anchor"))
        first.store(20, forAnchor: "anchor")
        first.store(10, forAnchor: "anchor")
        XCTAssertEqual(first.value(forAnchor: "anchor"), 20)
        XCTAssertNil(first.value(forAnchor: "other"))
        // A restart reads the persisted value from the feature data store.
        let restarted = DataStoreMinimumNotBeforeStore(dataStore: dataStore)
        XCTAssertEqual(restarted.value(forAnchor: "anchor"), 20)
        restarted.store(15, forAnchor: "anchor")
        XCTAssertEqual(DataStoreMinimumNotBeforeStore(dataStore: dataStore).value(forAnchor: "anchor"), 20)
        restarted.store(30, forAnchor: "anchor")
        XCTAssertEqual(DataStoreMinimumNotBeforeStore(dataStore: dataStore).value(forAnchor: "anchor"), 30)
    }

    /// Intermediates are older than every leaf. A value between an old leaf and a new leaf would revoke
    /// the shared intermediates, so the SDK ignores it, and later responses on both chains still verify.
    func testMinimumNotBeforeBetweenTwoLeavesWithOlderIntermediatesIsIgnored() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let store = MinimumNotBeforeStoreMock()
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            minimumNotBeforeStore: store
        )
        let oldLeafChain = try SigningChainFixture.credential("two-intermediates")
        let newLeafChain = try SigningChainFixture.credential("rotated-lower-intermediate")
        XCTAssertEqual(oldLeafChain.intermediates.last, newLeafChain.intermediates.last, "The chains share the upper intermediate")
        let value = try newLeafChain.leafNotBefore()
        XCTAssertGreaterThan(value, try oldLeafChain.leafNotBefore())
        XCTAssertLessThanOrEqual(try newLeafChain.oldestNotBefore(), try oldLeafChain.leafNotBefore())
        let proof = try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate", minimumNotBefore: value))
        XCTAssertTrue(proof.ignoredMinimumNotBefore)
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "rotated-lower-intermediate")))
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "two-intermediates")))
    }

    func testMinimumNotBeforeLowerThanTheStoredValueIsIgnored() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let anchorKey = SHA256.hash(data: anchor).map { String(format: "%02x", $0) }.joined()
        let store = MinimumNotBeforeStoreMock()
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            minimumNotBeforeStore: store
        )
        let value = try SigningChainFixture.credential("one-intermediate").oldestNotBefore()
        _ = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value))
        _ = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value - 1))
        XCTAssertEqual(store.values[anchorKey], value)
    }

    func testMinimumNotBeforeGreaterThanAnyCertificateInTheChainIsIgnored() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let store = MinimumNotBeforeStoreMock()
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            minimumNotBeforeStore: store
        )
        let chain = try SigningChainFixture.credential("one-intermediate")
        // Greater than the leaf, and between the intermediate and the leaf: a response never revokes its own chain.
        for value in [try chain.leafNotBefore() + 1, try chain.oldestNotBefore() + 1] {
            let proof = try verify(verifier, signedFixtureResponse(verifier, "one-intermediate", minimumNotBefore: value))
            XCTAssertTrue(proof.ignoredMinimumNotBefore, "\(value)")
        }
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertNoThrow(try verify(verifier, signedFixtureResponse(verifier, "one-intermediate")))
    }

    func testChangedMinimumNotBeforeHeaderFailsTheSignature() throws {
        let anchor = try SigningChainFixture.root("root-a")
        let store = MinimumNotBeforeStoreMock()
        let verifier = FlagsResponseVerifier(
            configuration: .init(mode: .required, trustedRootCertificates: [anchor]),
            minimumNotBeforeStore: store
        )
        let value = try SigningChainFixture.credential("one-intermediate").oldestNotBefore()
        let name = FlagsResponseVerifier.prefix + "minimum-not-before"
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
        let value = try SigningChainFixture.credential("one-intermediate").oldestNotBefore()
        for mode in [Flags.ResponseSigningMode.required, .observe] {
            let store = MinimumNotBeforeStoreMock()
            store.values[anchorKey] = value
            let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
            let telemetry = scope.telemetryMock
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: SigningChainFixture.now)),
                minimumNotBeforeStore: store,
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
                case (.required, .failure(.invalidResponse)): break
                case (.observe, .success(let response)): XCTAssertNil(response.verification)
                default: XCTFail("\(mode): \(result)")
                }
            }
            wait(for: [done], timeout: 1)
            XCTAssertTrue(telemetry.messages.contains { message in
                guard case .debug(let id, _, _) = message else {
                    return false
                }
                return id == "flags-response-signing-revoked-certificate"
            }, "\(mode)")
        }
    }
}

/// Test-CA-issued certificate-chain credentials and pinned roots from the shared `response-signing-chain` source.
internal struct SigningChainFixture {
    /// Within every fixture leaf's 72-hour validity (2026-11-18T04:20:54Z to 2026-11-21T04:20:52Z).
    static let now: TimeInterval = 1_795_000_000

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

    /// Edge-equivalent v1 proof headers for `request` and `body`, signed with the fixture key.
    func signedHeaders(
        request: URLRequest,
        body: Data,
        now: TimeInterval = now,
        minimumNotBefore: UInt64? = nil
    ) throws -> [String: String] {
        let prefix = FlagsResponseVerifier.prefix
        let transcript = try FlagsResponseVerifier.transcript(
            request: request,
            status: 200,
            body: body,
            issuedAt: UInt64(now),
            expiresAt: UInt64(now + 300),
            leaf: leaf,
            intermediates: intermediates,
            minimumNotBefore: minimumNotBefore
        )
        var headers = [
            prefix + "signature-version": "1",
            prefix + "signing-certificate": leaf.base64EncodedString(),
            prefix + "signing-chain": intermediates.map { $0.base64EncodedString() }.joined(separator: ","),
            prefix + "certificate-id": SHA256.hash(data: leaf).map { String(format: "%02x", $0) }.joined(),
            prefix + "issued-at": String(UInt64(now)),
            prefix + "expires-at": String(UInt64(now + 300)),
            prefix + "signature": try key.signature(for: transcript).derRepresentation.base64EncodedString()
        ]
        if let minimumNotBefore {
            headers[prefix + "minimum-not-before"] = String(minimumNotBefore)
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

private final class MinimumNotBeforeStoreMock: FlagsMinimumNotBeforeStore {
    var values: [String: UInt64] = [:]
    func value(forAnchor anchor: String) -> UInt64? { values[anchor] }
    func store(_ value: UInt64, forAnchor anchor: String) {
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
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        reads += 1
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
