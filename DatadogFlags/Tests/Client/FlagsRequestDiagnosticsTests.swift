/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagsRequestDiagnosticsTests: XCTestCase {
    func testUUIDv7GeneratorPreservesTimestampVersionVariantAndRandomness() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ids = (0..<100).map { _ in FlagsRequestDiagnostics.UUIDv7Generator.generate(now: now) }
        XCTAssertEqual(Set(ids).count, 100)
        for id in ids {
            var bytes = id.uuid
            withUnsafeBytes(of: &bytes) { buffer in
                XCTAssertEqual(buffer.prefix(6).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }, 1_700_000_000_000)
                XCTAssertEqual(buffer[6] >> 4, 7)
                XCTAssertEqual(buffer[8] >> 6, 2)
            }
        }
    }

    func testMinimalSchemaStableInstanceAndLogicalSequence() throws {
        let owner = FlagsRequestDiagnostics(now: Date(timeIntervalSince1970: 1_700_000_000))
        let first = try decode(owner.accept())
        let second = try decode(owner.accept())
        XCTAssertEqual(Set(first.keys), ["sdk", "fetch"])
        XCTAssertEqual(Set(try XCTUnwrap(first["sdk"].dictionary).keys), ["instance_id"])
        XCTAssertEqual(Set(try XCTUnwrap(first["fetch"].dictionary).keys), ["sequence", "trigger"])
        XCTAssertEqual(first["sdk"], second["sdk"])
        XCTAssertEqual(first["fetch"].dictionary?["sequence"], .int(1))
        XCTAssertEqual(second["fetch"].dictionary?["sequence"], .int(2))
        XCTAssertEqual(first["fetch"].dictionary?["trigger"], .string("initialization"))
        XCTAssertEqual(second["fetch"].dictionary?["trigger"], .string("context_change"))
        XCTAssertNil(first["fetch"].dictionary?["attempt"])
        XCTAssertNil(second["fetch"].dictionary?["attempt"])
        guard case .string(let id) = first["sdk"].dictionary?["instance_id"] else {
            return XCTFail("Missing instance ID")
        }
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        var bytes = uuid.uuid
        withUnsafeBytes(of: &bytes) { buffer in
            let timestamp = buffer.prefix(6).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            XCTAssertEqual(timestamp, 1_700_000_000_000)
            XCTAssertEqual(buffer[6] >> 4, 7)
            XCTAssertEqual(buffer[8] >> 6, 2)
        }
        XCTAssertNotEqual(first["sdk"], try decode(FlagsRequestDiagnostics().accept())["sdk"])
    }

    func testConcurrentAcceptanceAllocatesUniqueLogicalFetches() throws {
        let owner = FlagsRequestDiagnostics()
        let lock = NSLock()
        var values: [Data] = []
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if let value = owner.accept() {
                lock.lock()
                values.append(value)
                lock.unlock()
            }
        }
        let snapshots = try values.map { try decode($0) }
        XCTAssertEqual(snapshots.count, 100)
        XCTAssertTrue(snapshots.allSatisfy { $0["fetch"].dictionary?["attempt"] == nil })
        XCTAssertEqual(Set(snapshots.compactMap { $0["fetch"].dictionary?["sequence"] }), Set((1...100).map(AnyValue.int)))
        XCTAssertEqual(snapshots.filter { $0["fetch"].dictionary?["trigger"] == .string("initialization") }.count, 1)
    }

    func testStructuredBodyPreservesAssignmentsAndOmitsInvalidDiagnostics() throws {
        let owner = FlagsRequestDiagnostics()
        let envelope = try XCTUnwrap(owner.accept())
        let context = DatadogContext.mockAny()
        let evaluationContext = FlagsEvaluationContext(targetingKey: "private-user", attributes: ["large": .int(Int.max)])
        func request(_ diagnostics: Data?) throws -> URLRequest {
            try URLRequest.flagAssignmentsRequest(
                url: URL(string: "https://example.com/flags")!,
                evaluationContext: evaluationContext,
                context: context,
                customHeaders: nil,
                diagnostics: diagnostics
            )
        }
        let original = try request(nil)
        let withDiagnostics = try request(envelope)
        XCTAssertEqual(try decode(withDiagnostics.httpBody)["data"], try decode(original.httpBody)["data"])
        XCTAssertEqual(try decode(withDiagnostics.httpBody)["diagnostics"], .dictionary(try decode(envelope)))
        XCTAssertEqual(withDiagnostics.allHTTPHeaderFields, original.allHTTPHeaderFields)
        XCTAssertEqual(try decode(request(envelope).httpBody), try decode(withDiagnostics.httpBody))
        let invalid = Data("invalid".utf8)
        let root = try decode(request(invalid).httpBody)
        XCTAssertNil(root["diagnostics"])
        XCTAssertEqual(root["data"], try decode(original.httpBody)["data"])
    }

    func testRepositoryKeepsIdentityAcrossResetAndDoesNotPersistDiagnostics() throws {
        let scope = FeatureScopeMock()
        let context = FlagsEvaluationContext.mockAny()
        var requests: [URLRequest] = []
        let fetcher = FlagAssignmentsFetcher(customEndpoint: nil, customHeaders: nil, featureScope: scope) { request, completion in
            requests.append(request)
            completion(.success(.mockAnyFlagAssignmentsResponse()))
        }
        let repository = FlagsRepository(clientName: "client", flagAssignmentsFetcher: fetcher, dateProvider: DateProviderMock(), featureScope: scope, initializationTimeout: nil)
        scope.dataStore.flush()
        let initialized = expectation(description: "Initial context completes")
        repository.setEvaluationContext(context) { _ in initialized.fulfill() }
        wait(for: [initialized], timeout: 5)
        repository.flush()
        scope.dataStore.flush()
        let stored = try XCTUnwrap(scope.dataStoreMock.storage["client"]?.data())
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("diagnostics"))
        repository.reset()
        let refreshed = expectation(description: "Context after reset completes")
        repository.setEvaluationContext(context) { _ in refreshed.fulfill() }
        wait(for: [refreshed], timeout: 5)
        let first = try XCTUnwrap(decode(requests[0].httpBody)["diagnostics"].dictionary)
        let second = try XCTUnwrap(decode(requests[1].httpBody)["diagnostics"].dictionary)
        XCTAssertEqual(first["sdk"], second["sdk"])
        XCTAssertEqual(second["fetch"].dictionary?["sequence"], .int(2))
        let source = try decode(requests[0].httpBody)["data"].dictionary?["attributes"].dictionary?["source"].dictionary
        XCTAssertNotNil(source?["sdk_name"])
    }

    func testTransportFailureDoesNotRetryAndOmitsAttempt() throws {
        let scope = FeatureScopeMock()
        let owner = FlagsRequestDiagnostics()
        var requests: [URLRequest] = []
        let fetcher = FlagAssignmentsFetcher(customEndpoint: nil, customHeaders: nil, featureScope: scope) { request, completion in
            requests.append(request)
            completion(.failure(URLError(.timedOut)))
        }
        for _ in 0..<2 {
            let finished = expectation(description: "Transport failure completes")
            fetcher.flagAssignments(for: .mockAny(), diagnostics: owner.accept()) { result in
                if case .success = result { XCTFail("Expected transport failure") }
                finished.fulfill()
            }
            wait(for: [finished], timeout: 5)
        }
        XCTAssertEqual(requests.count, 2)
        for (index, request) in requests.enumerated() {
            let fetch = try decode(request.httpBody)["diagnostics"].dictionary?["fetch"].dictionary
            XCTAssertNil(fetch?["attempt"])
            XCTAssertEqual(fetch?["sequence"], .int(index + 1))
        }
    }

    private func decode(_ data: Data?) throws -> [String: AnyValue] {
        try JSONDecoder().decode([String: AnyValue].self, from: XCTUnwrap(data))
    }
}

private extension Optional where Wrapped == AnyValue {
    var dictionary: [String: AnyValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }
}
