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
                "6e83e91905e966b37a4eaf30961143cba6027ead0affc207ae6edc012390171e"
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

    // The pinned shared suites use the single-intermediate v1 format: one `signing-intermediate` header,
    // a codeSigning leaf and the old transcript tail. The v1 chain format replaces that format.
    // The chain fixtures in `response-signing/chain` cover the v1 chain format until the pin is updated.
    func testCentralManifestSuitesAndExactTranscripts() throws {
        throw XCTSkip(
            "ffe-system-test-data response-signing/v1 is regenerated for the v1 certificate-chain format; "
            + "the fixture pin is updated in a follow-up commit"
        )
    }

    func testCanonicalKeyUsageSupplement() throws {
        throw XCTSkip(
            "ResponseSigningKeyUsage.json uses the single-intermediate v1 format; it is regenerated with the shared "
            + "ffe-system-test-data response-signing/v1 fixtures for the certificate-chain format in a follow-up commit"
        )
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
        let fixture = try SigningChainFixture.credential("lukas-valid")
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
                        XCTAssertEqual(request.value(forHTTPHeaderField: "X-stream"), "false")
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
        let fixture = try SigningChainFixture.credential("lukas-valid")
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

    func testChainVaultCredentialTable() throws {
        let body = Data.mockAnyFlagAssignmentsResponse()
        let expected: [(credential: String, roots: [String], accept: Bool)] = [
            ("lukas-valid", ["root-a"], true),
            ("lukas-valid", ["root-b"], false),
            ("lukas-backup-root", ["root-b"], true),
            ("lukas-backup-root", ["root-a"], false),
            ("lukas-backup-root", ["root-a", "root-b"], true),
            ("lukas-rotated", ["root-a"], true),
            ("other-product", ["root-a"], false),
            ("missing-dc-int", ["root-a"], false),
            ("single-int-ffe", ["root-a"], true),
            ("v1-codesigning", ["root-a"], false),
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
        let fixture = try SigningChainFixture.credential("lukas-valid")
        // Leaves are valid for 72 hours from issuance; the proof must fit inside the leaf.
        let late = 1_795_219_000.0
        let response = try response(request, fixture.signedHeaders(request: request, body: body, now: late))
        XCTAssertThrowsError(
            try verifier.verify(request: request, response: response, body: body, now: Date(timeIntervalSince1970: late))
        )
    }

    func testChainTranscriptDomainAndTail() throws {
        let (_, request) = try signedRequest()
        let fixture = try SigningChainFixture.credential("lukas-valid")
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
        let fixture = try SigningChainFixture.credential("lukas-valid")
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
        let fixture = try SigningChainFixture.credential("lukas-valid")
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

/// Real Vault-issued certificate-chain credentials and pinned roots in `response-signing/chain`.
internal struct SigningChainFixture {
    /// Within every fixture leaf's 72-hour validity (2026-11-18T00:00:36Z to 2026-11-21T00:01:04Z).
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
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "response-signing/chain"))
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
    func signedHeaders(request: URLRequest, body: Data, now: TimeInterval = now) throws -> [String: String] {
        let prefix = FlagsResponseVerifier.prefix
        let transcript = try FlagsResponseVerifier.transcript(
            request: request,
            status: 200,
            body: body,
            issuedAt: UInt64(now),
            expiresAt: UInt64(now + 300),
            leaf: leaf,
            intermediates: intermediates
        )
        return [
            prefix + "signature-version": "1",
            prefix + "signing-certificate": leaf.base64EncodedString(),
            prefix + "signing-chain": intermediates.map { $0.base64EncodedString() }.joined(separator: ","),
            prefix + "certificate-id": SHA256.hash(data: leaf).map { String(format: "%02x", $0) }.joined(),
            prefix + "issued-at": String(UInt64(now)),
            prefix + "expires-at": String(UInt64(now + 300)),
            prefix + "signature": try key.signature(for: transcript).derRepresentation.base64EncodedString()
        ]
    }
}

private final class BundleToken {}

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
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
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
