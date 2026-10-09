/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@_spi(Internal)
@testable import DatadogFlags

final class FlagKeyObfuscationTests: XCTestCase {
    private let salt = "000102030405060708090a0b0c0d0e0f"
    private let digest = "9817872c144b018abd77e3915bd77e2c27f4f534dccff8ffaca27361e3a5e1ee"
    private let assignment = FlagAssignment(
        allocationKey: "allocation-123",
        variationKey: "variation-456",
        variation: .boolean(true),
        reason: "TARGETING_MATCH",
        doLog: true,
        serialID: 123
    )

    func testSharedHashVectors() throws {
        // The same fixed vectors run in the browser SDK and Rust edge encoder.
        let vectors = [
            ("new-route-planner", "a60479237ef2f69175bbe0bd581966d1583766941815dc1d414c883767795190"),
            ("Flag", "adca75d2141c51b0c0f084c1058edfb8e6e763f91aaf54ca06326d9847bd9586"),
            ("flag", "9817872c144b018abd77e3915bd77e2c27f4f534dccff8ffaca27361e3a5e1ee"),
            (" flag ", "b1a5f851cc82a3fdf03a461d72a2241584dcf455df1d384e02a937901b3bc80b"),
            ("café", "3bfa8c3c17c1b61035b98ecf14007cdf5cba5ce61a48e8cfb65f8106541892d3"),
            ("cafe\u{0301}", "1e8b7ec5e8028a1ec96b38dd37f6ccea041c0a90358904af40ac5810c23c8765"),
            ("🚲/旗", "94b611e0d3b26b52f6ad66013d1c72f8a92ea109390049759e75d3c8d3aa4dab"),
            ("a\0b", "bac134d201be5e7f28fc7019248f0809c2a013b137e866446ee71add2bc344c7"),
            ("", "072d985b427f536ad0a11b2d4c5e0f7e6f0ff6d23e779e082f75599ce3fe3eba"),
        ]
        for (key, expectedDigest) in vectors {
            let response = try decode(flags: [expectedDigest: assignment], metadata: metadata())
            let data = state(response)
            XCTAssertEqual(response.obfuscation?.lookupKey(for: key), expectedDigest)
            XCTAssertEqual(data.flagAssignment(for: key), assignment)
            XCTAssertNil(data.flagAssignment(for: expectedDigest), "Do not retry lookup as plaintext")
        }
    }

    func testPreservesEveryValueTypeAndEvaluationDetails() throws {
        try assertEquivalent(.boolean(true), defaultValue: false)
        try assertEquivalent(.string("visible-value"), defaultValue: "default")
        try assertEquivalent(.integer(42), defaultValue: -1)
        try assertEquivalent(.double(12.5), defaultValue: -1.0)
        try assertEquivalent(.object(.dictionary(["nested": .array([.string("visible"), .int(42)])])), defaultValue: AnyValue.dictionary([:]))
    }

    func testLookupCacheIsBoundedAndKeepsExactBytesAndSaltSeparate() throws {
        let response = try decode(flags: [digest: assignment], metadata: metadata())
        var cache = FlagsRepository.CachedFlagsData(data: state(response))
        var other = FlagsRepository.CachedFlagsData(data: state(try decode(flags: [:], metadata: metadata(salt: String(repeating: "f", count: 32)))))
        XCTAssertEqual(cache.flagAssignment(for: "flag"), assignment)
        XCTAssertEqual(cache.flagAssignment(for: "flag"), assignment)
        XCTAssertEqual(cache.lookupKeys.count, 1)
        _ = other.flagAssignment(for: "flag")
        XCTAssertNotEqual(other.lookupKeys[Data("flag".utf8)], digest)
        XCTAssertEqual(cache.flagAssignment(for: "flag"), assignment)
        _ = cache.flagAssignment(for: "café")
        _ = cache.flagAssignment(for: "cafe\u{0301}")
        XCTAssertNotEqual(cache.lookupKeys[Data("café".utf8)], cache.lookupKeys[Data("cafe\u{0301}".utf8)])
        XCTAssertEqual(cache.lookupKeys.count, 3)

        var copy = cache
        _ = copy.flagAssignment(for: "copy-only")
        XCTAssertEqual(cache.lookupKeys.count, 3, "Copies must not share mutable lookup hashes")
        XCTAssertEqual(copy.lookupKeys.count, 4)
        for index in 0..<FlagsRepository.CachedFlagsData.lookupCacheLimit {
            _ = cache.flagAssignment(for: "flag-\(index)")
            XCTAssertLessThanOrEqual(cache.lookupKeys.count, FlagsRepository.CachedFlagsData.lookupCacheLimit)
        }
        XCTAssertNil(cache.lookupKeys[Data("flag".utf8)])
        XCTAssertEqual(cache.flagAssignment(for: "flag"), assignment)
        let restored = try JSONDecoder().decode(FlagsData.self, from: JSONEncoder().encode(cache.data))
        XCTAssertEqual(restored, cache.data)
        XCTAssertTrue(FlagsRepository.CachedFlagsData(data: restored).lookupKeys.isEmpty, "Lookup hashes are not persisted")
    }

    func testRejectsInvalidWireMetadata() throws {
        let descriptor: [String: Any] = ["scheme": "flag-key-sha256-v1", "salt": salt]
        var invalidMetadata: [[String: Any]] = [
            ["obfuscated": true],
            ["obfuscated": "true", "obfuscation": descriptor],
            ["obfuscated": 1, "obfuscation": descriptor],
            ["obfuscated": NSNull()],
            ["obfuscated": false, "obfuscation": descriptor],
            ["obfuscation": descriptor],
            ["obfuscated": true, "obfuscation": NSNull()],
            ["obfuscated": true, "obfuscation": []],
            ["obfuscated": true, "obfuscation": ["scheme": "flag-key-sha256-v2", "salt": salt]],
        ]
        let invalidSalts: [Any] = [
            "", String(repeating: "0", count: 30), String(repeating: "0", count: 34),
            String(repeating: "G", count: 32), salt.uppercased(), salt + "\n",
            String(repeating: "a", count: 31) + "\n", 42,
        ]
        invalidMetadata += invalidSalts.map {
            ["obfuscated": true, "obfuscation": ["scheme": "flag-key-sha256-v1", "salt": $0]]
        }
        for metadata in invalidMetadata {
            XCTAssertThrowsError(try decode(flags: [digest: assignment], metadata: metadata))
        }
    }

    func testRejectsInvalidDiskDescriptors() throws {
        let cache = try JSONEncoder().encode(FlagsData(flags: [digest: assignment], context: .mockAny(), date: .mockAny()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: cache) as? [String: Any])
        let invalidDescriptors: [Any] = [
            [], [:], "invalid-descriptor",
            ["scheme": "flag-key-sha256-v2", "salt": salt],
            ["scheme": "flag-key-sha256-v1"],
            ["scheme": "flag-key-sha256-v1", "salt": NSNull()],
            ["scheme": "flag-key-sha256-v1", "salt": salt.uppercased()],
            ["scheme": "flag-key-sha256-v1", "salt": "00"],
        ]
        for descriptor in invalidDescriptors {
            json["obfuscation"] = descriptor
            XCTAssertThrowsError(try JSONDecoder().decode(FlagsData.self, from: JSONSerialization.data(withJSONObject: json)))
        }
    }

    func testDecodingErrorsCarryCodingPathsAndUseSanitizedTelemetry() throws {
        let cases: [([String: Any], [String: FlagAssignment], [String])] = [
            (metadata(salt: "private-invalid-salt"), [digest: assignment], ["data", "attributes", "obfuscation", "salt"]),
            (["obfuscated": true, "obfuscation": ["scheme": "private-unknown-scheme", "salt": salt]], [digest: assignment], ["data", "attributes", "obfuscation", "scheme"]),
            (["obfuscated": false, "obfuscation": ["scheme": "flag-key-sha256-v1", "salt": salt]], [digest: assignment], ["data", "attributes", "obfuscation"]),
            (metadata(), ["private-flag-name": assignment], ["data", "attributes", "flags"]),
        ]
        for (metadata, flags, path) in cases {
            XCTAssertThrowsError(try decode(flags: flags, metadata: metadata)) { error in
                guard case DecodingError.dataCorrupted(let context) = error else {
                    return XCTFail("Expected dataCorrupted, got \(error)")
                }
                XCTAssertEqual(context.codingPath.map(\.stringValue), path)
                let sanitized = TelemetrySanitizedError(sanitizing: error)
                XCTAssertEqual(sanitized.kind, "DecodingError.dataCorrupted")
                XCTAssertEqual(sanitized.message, "data was corrupted")
                XCTAssertEqual(sanitized.stack, "\(path.count) levels deep")
            }
        }
    }

    func testAcceptsNewKeysAndUnknownFieldsAndIsolatesUnknownVariantTypes() throws {
        let encoding = try XCTUnwrap(decode(flags: [:], metadata: metadata()).obfuscation)
        var unknown = assignment
        unknown.variation = .unknown("future-type")
        let response = try decode(
            flags: [digest: assignment, encoding.lookupKey(for: "new-flag"): assignment, encoding.lookupKey(for: "future"): unknown],
            metadata: metadata().merging(["future-field": ["enabled": true]]) { _, new in new }
        )
        XCTAssertEqual(state(response).flagAssignment(for: "flag"), assignment)
        XCTAssertEqual(state(response).flagAssignment(for: "new-flag"), assignment)
        XCTAssertNil(state(response).flagAssignment(for: "future"))
        XCTAssertNotNil(response.failedFlags[encoding.lookupKey(for: "future")])
    }

    func testOfflineRestoreUsesLatestSaltAndChangedValue() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        var networkData = Data()
        let repository = makeRepository(scope: scope, fetcher: makeFetcher(scope: scope) { networkData })
        for (salt, value) in [(salt, true), (String(repeating: "f", count: 32), false)] {
            let encoding = try XCTUnwrap(decode(flags: [:], metadata: metadata(salt: salt)).obfuscation)
            var changed = assignment
            changed.variation = .boolean(value)
            networkData = try payload(flags: [encoding.lookupKey(for: "flag"): changed], metadata: metadata(salt: salt))
            let completed = expectation(description: "refresh completes")
            repository.setEvaluationContext(.mockAny()) { _ in completed.fulfill() }
            waitForExpectations(timeout: 1)
            XCTAssertEqual(repository.flagAssignment(for: "flag"), changed)
        }
        let stored = try XCTUnwrap(scope.dataStoreMock.storage["client"]?.data(expectedVersion: 2))
        XCTAssertEqual(try JSONDecoder().decode(FlagsData.self, from: stored).obfuscation?.salt.bytes, Array(repeating: 255, count: 16))
        let restored = makeRepository(scope: scope, fetcher: FlagAssignmentsFetcherMock { _, completion in
            completion(.failure(.invalidResponse))
        })
        let completed = expectation(description: "offline refresh completes")
        restored.setEvaluationContext(.mockAny()) { _ in completed.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(restored.state.currentState, .stale)
        XCTAssertEqual(restored.flagAssignment(for: "flag")?.variation, .boolean(false))
    }

    func testConcurrentLookupsDuringSaltRotation() throws {
        // Given
        let keys = (0..<64).map { "flag-\($0)" }
        let responses = try [salt, String(repeating: "f", count: 32)].map { salt in
            let encoding = try XCTUnwrap(decode(flags: [:], metadata: metadata(salt: salt)).obfuscation)
            let flags = Dictionary(uniqueKeysWithValues: keys.map { (encoding.lookupKey(for: $0), assignment) })
            return try decode(flags: flags, metadata: metadata(salt: salt))
        }
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        scope.flagsDataStore.setFlagsData(state(responses[0]), forClientNamed: "client")
        var nextResponse = responses[0]
        let repository = makeRepository(scope: scope, fetcher: FlagAssignmentsFetcherMock { _, completion in
            completion(.success(nextResponse))
        })
        repository.setEvaluationContext(.mockAny()) { _ in }
        for key in keys.prefix(32) {
            XCTAssertEqual(repository.flagAssignment(for: key), assignment)
        }

        // When: one writer rotates the salt while readers use cached and uncached keys.
        DispatchQueue.concurrentPerform(iterations: 17) { worker in
            if worker == 0 {
                for index in 0..<32 {
                    nextResponse = responses[index % 2]
                    repository.setEvaluationContext(.mockAny()) { _ in }
                }
            } else {
                for _ in 0..<4 {
                    for key in keys {
                        XCTAssertEqual(repository.flagAssignment(for: key), assignment)
                    }
                }
            }
        }

        // Then
        for key in keys {
            XCTAssertEqual(repository.flagAssignment(for: key), assignment)
        }
    }

    func testLookupCacheFollowsPlaintextRefreshAndReset() throws {
        // Given
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        var response = try decode(flags: [digest: assignment], metadata: metadata())
        let repository = makeRepository(scope: scope, fetcher: FlagAssignmentsFetcherMock { _, completion in
            completion(.success(response))
        })
        repository.setEvaluationContext(.mockAny()) { _ in }
        XCTAssertEqual(repository.flagAssignment(for: "flag"), assignment)

        // When
        var changed = assignment
        changed.variation = .boolean(false)
        response = try decode(flags: ["flag": changed], metadata: [:])
        repository.setEvaluationContext(.mockAny()) { _ in }

        // Then
        XCTAssertEqual(repository.flagAssignment(for: "flag"), changed)
        repository.reset()
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertNil(scope.dataStoreMock.storage["client"])

        response = try decode(flags: [digest: assignment], metadata: metadata())
        repository.setEvaluationContext(.mockAny()) { _ in }
        XCTAssertEqual(repository.flagAssignment(for: "flag"), assignment)
    }

    func testRejectsMalformedEncodedKeysFromWire() throws {
        let invalidKeys = [
            "plaintext-key", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
            String(repeating: "A", count: 64), String(repeating: "a", count: 64) + "\n",
            String(repeating: "a", count: 63) + "\n",
        ]
        for key in invalidKeys {
            XCTAssertThrowsError(try decode(flags: [key: assignment], metadata: metadata()))
        }
    }

    func testLegacyWireAndCacheRemainReadable() throws {
        for metadata in [[:], ["obfuscated": false]] {
            let response = try decode(flags: ["flag": assignment], metadata: metadata)
            XCTAssertNil(response.obfuscation)
            let restored = try JSONDecoder().decode(FlagsData.self, from: JSONEncoder().encode(state(response)))
            XCTAssertEqual(restored.flagAssignment(for: "flag"), assignment)
        }
    }

    func testWireAndCacheRoundTripsKeepDescriptorWithAssignments() throws {
        let response = try decode(flags: [digest: assignment], metadata: metadata())
        XCTAssertEqual(try JSONDecoder().decode(FlagAssignmentsResponse.self, from: JSONEncoder().encode(response)), response)
        let data = state(response)
        let encoded = try JSONEncoder().encode(data)
        let diskJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(diskJSON["obfuscation"] as? [String: String], ["scheme": "flag-key-sha256-v1", "salt": salt])
        XCTAssertNil(diskJSON["obfuscated"], "The disk format needs only the optional descriptor")
        XCTAssertNil(diskJSON["lookupKeys"], "Lookup hashes remain in memory")
        let restored = try JSONDecoder().decode(FlagsData.self, from: encoded)
        XCTAssertEqual(restored, data)
        XCTAssertEqual(restored.flagAssignment(for: "flag"), assignment)
        XCTAssertEqual(Array(restored.flags.keys), [digest])
    }

    func testCacheVersionMustMatchAssignmentEncoding() throws {
        let scope = FeatureScopeMock()
        let encoded = state(try decode(flags: [digest: assignment], metadata: metadata()))
        let legacy = FlagsData(flags: ["flag": assignment], context: .mockAny(), date: .mockAny())
        for (data, version) in [(encoded, DataStoreKeyVersion(1)), (legacy, DataStoreKeyVersion(2))] {
            scope.dataStore.setValue(try JSONEncoder().encode(data), forKey: "client", version: version)
            let completed = expectation(description: "inconsistent cache rejected")
            scope.flagsDataStore.flagsData(forClientNamed: "client") {
                XCTAssertNil($0)
                completed.fulfill()
            }
            waitForExpectations(timeout: 1)
        }

        scope.flagsDataStore.setFlagsData(encoded, forClientNamed: "client")
        XCTAssertNil(scope.dataStoreMock.storage["client"]?.data())
        XCTAssertNotNil(scope.dataStoreMock.storage["client"]?.data(expectedVersion: 2))
        scope.flagsDataStore.setFlagsData(legacy, forClientNamed: "client")
        XCTAssertNotNil(scope.dataStoreMock.storage["client"]?.data())
        XCTAssertNil(scope.dataStoreMock.storage["client"]?.data(expectedVersion: 2))
    }

    func testRequestAdvertisesCapabilitiesWithoutChangingSourceVersion() throws {
        for source in ["ios", "flutter", "react-native", "future-bridge"] {
            let request = try URLRequest.flagAssignmentsRequest(
                url: URL(string: "https://example.com/precompute-assignments")!,
                evaluationContext: .mockAny(),
                context: .mockWith(source: source, sdkVersion: "99.1.2-telemetry"),
                customHeaders: nil
            )
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let data = try XCTUnwrap(body["data"] as? [String: Any])
            let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
            let identity = try XCTUnwrap(attributes["source"] as? [String: String])
            XCTAssertEqual(identity, ["sdk_name": "dd-sdk-ios", "sdk_version": "99.1.2-telemetry"])
            XCTAssertNil(attributes["supported_capabilities"])
            if source != "ios" {
                XCTAssertNil(request.value(forHTTPHeaderField: "X-DD-FEATURE-FLAGS-CAPABILITIES"))
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-DD-FEATURE-FLAGS-CAPABILITIES"), "assignment-encoding-flag-key-256-v1")
            }
        }
    }

    func testReactNativeRejectsEncodedNetworkAndDiskAssignments() throws {
        let response = try decode(flags: [digest: assignment], metadata: metadata())
        let scope = FeatureScopeMock(context: .mockWith(source: "react-native"))
        scope.flagsDataStore.setFlagsData(state(response), forClientNamed: "client")
        let data = try JSONEncoder().encode(response)
        let fetcher = makeFetcher(scope: scope) { data }
        let repository = makeRepository(scope: scope, fetcher: fetcher)
        scope.dataStore.flush()
        XCTAssertNil(repository.context)
        XCTAssertNil(repository.flagAssignment(for: "flag"))
        XCTAssertNil(repository.flagAssignments())
        let completed = expectation(description: "unsupported encoding fails")
        repository.setEvaluationContext(.mockAny()) { result in
            guard case .failure(.invalidResponse) = result else {
                return XCTFail("Expected invalid response")
            }
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(repository.state.currentState, .error)
        XCTAssertNil(repository.flagAssignment(for: "flag"))
    }

    func testMalformedRefreshKeepsOnlyMatchingCachedContext() throws {
        let response = try decode(flags: [digest: assignment], metadata: metadata())
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        scope.flagsDataStore.setFlagsData(state(response), forClientNamed: "client")
        let malformed = try payload(flags: [digest: assignment], metadata: ["obfuscated": true])
        let repository = makeRepository(scope: scope, fetcher: makeFetcher(scope: scope) { malformed })
        scope.dataStore.flush()
        XCTAssertEqual(repository.flagAssignment(for: "flag"), assignment)

        for context in [FlagsEvaluationContext.mockAny(), .init(targetingKey: "different", attributes: [:])] {
            let completed = expectation(description: "invalid response")
            repository.setEvaluationContext(context) { result in
                guard case .failure(.invalidResponse) = result else {
                    return XCTFail("Expected invalid response")
                }
                completed.fulfill()
            }
            waitForExpectations(timeout: 1)
            if context == .mockAny() {
                XCTAssertEqual(repository.state.currentState, .stale)
                XCTAssertEqual(repository.flagAssignment(for: "flag"), assignment)
            } else {
                XCTAssertEqual(repository.state.currentState, .error)
                XCTAssertNil(repository.flagAssignment(for: "flag"))
            }
        }
    }

    func testDelayedSourceDoesNotDelayDiskCompletionOrExposeEncodedCache() throws {
        let response = try decode(flags: [digest: assignment], metadata: metadata())
        for source in ["ios", "react-native", "future-bridge"] {
            let scope = DeferredFlagsContextScope()
            scope.flagsDataStore.setFlagsData(state(response), forClientNamed: "client")
            var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
                dateProvider: DateProviderMock(),
                featureScope: scope,
                initializationTimeout: nil
            )
            XCTAssertNil(repository.context)
            XCTAssertNil(repository.flagAssignment(for: "flag"))
            XCTAssertNil(repository.flagAssignments())
            repository.setEvaluationContext(.mockAny()) { _ in }
            XCTAssertNotNil(fetchCompletion, "Disk completion must not depend on the context callback")
            scope.completeContext(source: source)
            XCTAssertEqual(repository.flagAssignment(for: "flag"), source == "ios" ? assignment : nil)
            fetchCompletion?(.failure(.invalidResponse))
            XCTAssertEqual(repository.state.currentState, source == "ios" ? .stale : .error)
            XCTAssertEqual(repository.flagAssignment(for: "flag"), source == "ios" ? assignment : nil)
        }
    }

    func testMissingSourceCallbackDoesNotPreventRepositoryCompletion() {
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.clientNotInitialized))
            },
            dateProvider: DateProviderMock(),
            featureScope: NOPFeatureScope(),
            initializationTimeout: nil
        )
        let completed = expectation(description: "repository completes without core context")
        repository.setEvaluationContext(.mockAny()) { _ in completed.fulfill() }
        waitForExpectations(timeout: 0)
    }

    func testSaltRotationPreservesOriginalTelemetryAndExposureDeduplication() throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        var networkData = Data()
        let repository = makeRepository(scope: scope, fetcher: makeFetcher(scope: scope) { networkData })
        let evaluations = EvaluationLoggerMock()
        let rum = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: repository,
            exposureLogger: ExposureLogger(dateProvider: DateProviderMock(), featureScope: scope),
            evaluationLogger: evaluations,
            rumFlagEvaluationReporter: rum
        )
        for salt in [salt, String(repeating: "f", count: 32), salt] {
            let encoding = try XCTUnwrap(decode(flags: [:], metadata: metadata(salt: salt)).obfuscation)
            let key = encoding.lookupKey(for: "flag")
            networkData = try payload(flags: [key: assignment], metadata: metadata(salt: salt))
            let completed = expectation(description: "new assignments")
            client.setEvaluationContext(.mockAny()) { result in
                if case .failure = result {
                    XCTFail("Expected valid encoded assignments")
                }
                completed.fulfill()
            }
            waitForExpectations(timeout: 1)
            XCTAssertTrue(client.getBooleanValue(key: "flag", defaultValue: false))
            let stored = try XCTUnwrap(scope.dataStoreMock.storage["client"])
            XCTAssertNil(stored.data(), "Old SDKs must not read encoded assignments as plaintext")
            let persisted = try XCTUnwrap(stored.data(expectedVersion: 2))
            let restored = try JSONDecoder().decode(FlagsData.self, from: persisted)
            XCTAssertEqual(restored.obfuscation, encoding)
            XCTAssertEqual(Array(restored.flags.keys), [key])
            XCTAssertEqual(restored.flagAssignment(for: "flag"), assignment)
        }
        XCTAssertEqual(evaluations.logEvaluationCalls.map(\.flagKey), ["flag", "flag", "flag"])
        XCTAssertEqual(evaluations.logEvaluationCalls.map(\.assignment.serialID), [123, 123, 123])
        XCTAssertEqual(rum.sendFlagEvaluationCalls.map { $0.0 }, ["flag", "flag", "flag"])
        let exposures = scope.eventsWritten(ofType: ExposureEvent.self)
        XCTAssertEqual(exposures.count, 1)
        XCTAssertEqual(exposures.first?.flag.key, "flag")
        XCTAssertEqual(exposures.first?.serialID, 123)
    }

    func testLegacySnapshotDoesNotExposeEncodedKeys() throws {
        for encoded in [false, true] {
            let response = try decode(
                flags: [encoded ? digest : "flag": assignment],
                metadata: encoded ? metadata() : [:]
            )
            let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
            scope.flagsDataStore.setFlagsData(state(response), forClientNamed: "client")
            let repository = makeRepository(scope: scope, fetcher: FlagAssignmentsFetcherMock())
            scope.dataStore.flush()
            let client = FlagsClient(
                repository: repository,
                exposureLogger: ExposureLoggerMock(),
                evaluationLogger: EvaluationLoggerMock(),
                rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
            )

            XCTAssertTrue(client.getBooleanValue(key: "flag", defaultValue: false))
            if encoded {
                XCTAssertNil(repository.flagAssignments())
                XCTAssertNil(client.snapshot())
            } else {
                XCTAssertEqual(Array(try XCTUnwrap(client.snapshot()).assignments.keys), ["flag"])
            }
        }
    }

    private func assertEquivalent<T: FlagValue & Equatable>(_ variation: FlagAssignment.Variation, defaultValue: T) throws {
        var flag = assignment
        flag.variation = variation
        let plain = try decode(flags: ["flag": flag], metadata: [:])
        let encoded = try decode(flags: [digest: flag], metadata: metadata())
        let clients = [plain, encoded].map { response in
            FlagsClient(
                repository: FlagsRepositoryMock(flagsData: state(response)),
                exposureLogger: ExposureLoggerMock(),
                evaluationLogger: EvaluationLoggerMock(),
                rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
            )
        }
        for key in ["flag", "missing"] {
            XCTAssertEqual(clients[0].getDetails(key: key, defaultValue: defaultValue), clients[1].getDetails(key: key, defaultValue: defaultValue))
            XCTAssertEqual(clients[0].getDetails(key: key, defaultValue: false), clients[1].getDetails(key: key, defaultValue: false))
        }
    }

    private func metadata(salt: String? = nil) -> [String: Any] {
        ["obfuscated": true, "obfuscation": ["scheme": "flag-key-sha256-v1", "salt": salt ?? self.salt]]
    }

    private func payload(flags: [String: FlagAssignment], metadata: [String: Any]) throws -> Data {
        let flagsJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(flags))
        var attributes = metadata
        attributes["flags"] = flagsJSON
        return try JSONSerialization.data(withJSONObject: ["data": ["attributes": attributes]])
    }

    private func decode(flags: [String: FlagAssignment], metadata: [String: Any]) throws -> FlagAssignmentsResponse {
        try JSONDecoder().decode(FlagAssignmentsResponse.self, from: payload(flags: flags, metadata: metadata))
    }

    private func state(_ response: FlagAssignmentsResponse) -> FlagsData {
        FlagsData(flags: response.flags, context: .mockAny(), date: .mockAny(), obfuscation: response.obfuscation)
    }

    private func makeFetcher(scope: FeatureScopeMock, data: @escaping () -> Data) -> FlagAssignmentsFetcher {
        FlagAssignmentsFetcher(customEndpoint: nil, customHeaders: nil, featureScope: scope) { _, completion in
            completion(.success(data()))
        }
    }

    private func makeRepository(scope: FeatureScopeMock, fetcher: FlagAssignmentsFetching) -> FlagsRepository {
        FlagsRepository(clientName: "client", flagAssignmentsFetcher: fetcher, dateProvider: DateProviderMock(), featureScope: scope)
    }
}

private final class DeferredFlagsContextScope: FeatureScope, @unchecked Sendable {
    let dataStore: any DataStore = DataStoreMock()
    let telemetry: any Telemetry = NOPTelemetry()
    private var contextCallback: ((DatadogContext) -> Void)?

    func context(_ block: @escaping (DatadogContext) -> Void) { contextCallback = block }

    func completeContext(source: String) {
        contextCallback?(.mockWith(source: source))
        contextCallback = nil
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) { }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { fallback() }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { }
    func set(anonymousId: String?) { }
}
