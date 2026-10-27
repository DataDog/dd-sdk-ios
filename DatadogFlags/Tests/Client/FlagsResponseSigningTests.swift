/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import CryptoKit
import TestUtilities
import DatadogInternal

@_spi(Internal) @testable import DatadogFlags

final class FlagsResponseSigningTests: XCTestCase {
    private struct Corpus: Decodable {
        let anchor: String
        let cases: [Vector]
        enum CodingKeys: String, CodingKey {
            case anchor = "anchor_der_base64"
            case cases
            case supplementalAnchor = "anchor"
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            anchor =
                try container.decodeIfPresent(String.self, forKey: .anchor)
                ?? container.decode(String.self, forKey: .supplementalAnchor)
            cases = try container.decode([Vector].self, forKey: .cases)
        }
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
        struct Credential: Decodable { let private_key_pkcs8_der_base64: String }
        let id: String
        let request: Request
        let response: Response
        let now: TimeInterval
        let expected_accept: Bool
        let transcript_base64: String?
        let credential: Credential?
    }

    private func corpus(
        name: String = "ResponseSigningCorpus",
        hash: String = "cc444ec8a2890430fa8dd8aee6cbde5a92d388ee55938596aac67891cfc099b6"
    ) throws -> Corpus {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        let raw = try Data(contentsOf: url)
        XCTAssertEqual(
            SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(),
            hash
        )
        return try JSONDecoder().decode(Corpus.self, from: raw)
    }

    private func headers(_ pairs: [[String]]) -> [String: String] {
        pairs.reduce(into: [:]) { result, pair in
            let name = pair[0].lowercased()
            result[name] = result[name].map { $0 + ", " + pair[1] } ?? pair[1]
        }
    }

    func testFrozenIndependentCorpusAndExactTranscripts() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.cases.count, 43)
        XCTAssertEqual(corpus.cases.filter(\.expected_accept).count, 6)
        try assertCorpus(corpus)
    }

    func testCanonicalKeyUsageSupplement() throws {
        let corpus = try corpus(
            name: "ResponseSigningKeyUsage",
            hash: "e6e2bc29ab28b490a1e17bb7c46a9342cf9496d9962c04aa5ca0e3ce6b08d347"
        )
        XCTAssertEqual(corpus.cases.count, 2)
        XCTAssertEqual(corpus.cases.filter(\.expected_accept).count, 1)
        try assertCorpus(corpus)
    }

    private func assertCorpus(_ corpus: Corpus) throws {
        let anchor = try XCTUnwrap(Data(base64Encoded: corpus.anchor))
        let verifier = FlagsResponseVerifier(configuration: .init(mode: .required, trustedRootCertificates: [anchor]))
        var executed = 0
        for vector in corpus.cases {
            try XCTContext.runActivity(named: vector.id) { _ in
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
                if vector.expected_accept {
                    let proof = try verifier.verify(
                        request: request,
                        response: response,
                        body: body,
                        now: Date(timeIntervalSince1970: vector.now)
                    )
                    XCTAssertEqual(proof.verifiedAt, vector.now)
                    let prefix = FlagsResponseVerifier.prefix
                    let transcript = try FlagsResponseVerifier.transcript(
                        request: request,
                        status: response.statusCode,
                        body: body,
                        issuedAt: UInt64(try XCTUnwrap(responseHeaders[prefix + "issued-at"]))!,
                        expiresAt: UInt64(try XCTUnwrap(responseHeaders[prefix + "expires-at"]))!,
                        leaf: Data(base64Encoded: try XCTUnwrap(responseHeaders[prefix + "signing-certificate"]))!,
                        intermediate: Data(
                            base64Encoded: try XCTUnwrap(responseHeaders[prefix + "signing-intermediate"])
                        )!
                    )
                    XCTAssertEqual(transcript.base64EncodedString(), vector.transcript_base64)
                } else {
                    XCTAssertThrowsError(
                        try verifier.verify(
                            request: request,
                            response: response,
                            body: body,
                            now: Date(timeIntervalSince1970: vector.now)
                        ),
                        vector.id
                    )
                }
                executed += 1
            }
        }
        XCTAssertEqual(executed, corpus.cases.count)
    }

    func testRequiredNeedsAnExplicitAnchorAndObserveDoesNotInventOne() throws {
        let vector = try XCTUnwrap(corpus().cases.first)
        var request = URLRequest(url: URL(string: vector.request.url)!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("test", forHTTPHeaderField: "dd-client-token")
        XCTAssertThrowsError(try FlagsResponseVerifier(configuration: .init(mode: .required)).prepare(request))
        let observing = FlagsResponseVerifier(configuration: .init(mode: .observe))
        let prepared = try observing.prepare(request)
        XCTAssertEqual(prepared.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version"), "3")
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
        let corpus = try corpus()
        let vector = try XCTUnwrap(corpus.cases.first)
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: vector.now))
        let anchor = try XCTUnwrap(Data(base64Encoded: corpus.anchor))
        let responseBody = Data.mockAnyFlagAssignmentsResponse()
        let key = try P256.Signing.PrivateKey(
            derRepresentation:
                XCTUnwrap(Data(base64Encoded: XCTUnwrap(vector.credential).private_key_pkcs8_der_base64))
        )
        let scope = FeatureScopeMock()
        let done = expectation(description: "verified before fetch completion")
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: URL(string: "https://flags.example.test/assign?dd_env=prod&x=a%2Fb"),
            customHeaders: ["dd-client-token": "effective-override"],
            featureScope: scope,
            responseSigning: .init(mode: .required, trustedRootCertificates: [anchor]),
            dateProvider: clock,
            signingFetch: { request, completion in
                do {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "dd-client-token"), "effective-override")
                    var headers = self.headers(vector.response.headers)
                    let prefix = FlagsResponseVerifier.prefix
                    let transcript = try FlagsResponseVerifier.transcript(
                        request: request,
                        status: 200,
                        body: responseBody,
                        issuedAt: UInt64(vector.now),
                        expiresAt: UInt64(vector.now + 300),
                        leaf: Data(base64Encoded: headers[prefix + "signing-certificate"]!)!,
                        intermediate: Data(base64Encoded: headers[prefix + "signing-intermediate"]!)!
                    )
                    headers[prefix + "signature"] = try key.signature(for: transcript).derRepresentation
                        .base64EncodedString()
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: headers
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
    }

    func testFetcherModesAndRedirectFailures() throws {
        for mode in [Flags.ResponseSigningMode.off, .observe, .required] {
            for redirected in [false, true] {
                let corpus = try corpus()
                let done = expectation(description: "mode completion")
                var signedCalls = 0
                var ordinaryCalls = 0
                let fetcher = FlagAssignmentsFetcher(
                    customEndpoint: nil,
                    customHeaders: nil,
                    featureScope: FeatureScopeMock(),
                    responseSigning: .init(mode: mode, trustedRootCertificates: [Data(base64Encoded: corpus.anchor)!]),
                    signingFetch: { request, completion in
                        signedCalls += 1
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
                        XCTAssertNil(
                            request.value(forHTTPHeaderField: FlagsResponseVerifier.prefix + "signature-version")
                        )
                        completion(.success(.mockAnyFlagAssignmentsResponse()))
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
                guard case .failure = result else { return XCTFail("invalid proof admitted") }
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
        let corpus = try corpus()
        let vector = try XCTUnwrap(corpus.cases.first)
        let anchor = try XCTUnwrap(Data(base64Encoded: corpus.anchor))
        let key = try P256.Signing.PrivateKey(
            derRepresentation: XCTUnwrap(Data(base64Encoded: XCTUnwrap(vector.credential).private_key_pkcs8_der_base64))
        )
        let body = try JSONEncoder().encode(FlagAssignmentsResponse(flags: ["flag": .mockAnyBoolean()]))
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let clock = DateProviderMock(now: Date(timeIntervalSince1970: vector.now))
            let first = expectation(description: "first verified response")
            let started = expectation(description: "second response waiting")
            let stopped = expectation(description: "late completion rejected")
            var calls = 0
            var pending: (() -> Void)?
            let fetcher = FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                featureScope: FeatureScopeMock(),
                responseSigning: .init(mode: mode, trustedRootCertificates: [anchor]),
                dateProvider: clock,
                signingFetch: { request, completion in
                    do {
                        calls += 1
                        var headers = self.headers(vector.response.headers)
                        let prefix = FlagsResponseVerifier.prefix
                        let transcript = try FlagsResponseVerifier.transcript(
                            request: request,
                            status: 200,
                            body: body,
                            issuedAt: UInt64(vector.now),
                            expiresAt: UInt64(vector.now + 300),
                            leaf: Data(base64Encoded: headers[prefix + "signing-certificate"]!)!,
                            intermediate: Data(base64Encoded: headers[prefix + "signing-intermediate"]!)!
                        )
                        headers[prefix + "signature"] = try key.signature(for: transcript).derRepresentation
                            .base64EncodedString()
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
            featureScope: FeatureScopeMock(),
            fetch: { _, completion in completion(.success(.mockAnyFlagAssignmentsResponse())) }
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

    func testCoreScopeMessagesUpdateNamespaceBeforeNextRequest() {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
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
            initializationTimeout: nil
        )
        defer { repository.flush() }
        XCTAssertNil(repository.flagAssignment(for: "legacy"))
        repository.setEvaluationContext(context) { _ in }
        fetcher.completeVerified(index: 0, expiry: 200)
        repository.flush()
        let key = FlagsResponseVerifier.cacheKey(clientName: "signed", scope: "scope-a")
        XCTAssertNotNil(store.value(forKey: key))
        XCTAssertEqual(store.value(forKey: "signed")?.data(), legacy)
        let same = FlagsRepository(
            clientName: "signed",
            flagAssignmentsFetcher: fetcher,
            dateProvider: clock,
            featureScope: FeatureScopeMock(dataStore: store),
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
}

private final class SigningLifecycleFetcher: FlagAssignmentsFetching {
    let responseSigningMode: Flags.ResponseSigningMode
    let scope = UUID()
    var responseSigningCacheScope: String? = "scope-a"
    var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
    init(mode: Flags.ResponseSigningMode) { responseSigningMode = mode }
    func isVerified(_ proof: FlagsResponseVerification?, at now: Date) -> Bool {
        proof?.cacheScope == responseSigningCacheScope && proof?.isValid(at: now, scope: scope) == true
    }
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
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
    var reads = 0
    var writes = 0
    var removals = 0
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        reads += 1
        callback(.noValue)
    }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) { writes += 1 }
    func removeValue(forKey key: String) { removals += 1 }
    func clearAllData() {}
    func flush() {}
}
