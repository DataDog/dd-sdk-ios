/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class CanonicalPrecomputedTests: XCTestCase {
    private let decoder = JSONDecoder()
    private var executedEvaluations = 0

    func testCanonicalResponses() throws {
        // Fixtures are git-ignored and fetched by `make feature-flags-fixtures-pull`, like SR snapshots.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DatadogFlags
            .appendingPathComponent("Fixtures/precomputed")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("SOURCE.json").path) else {
            return XCTFail("Shared fixtures are missing. Run `make feature-flags-fixtures-pull`.")
        }
        let cases = root.appendingPathComponent("cases")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: cases.path))
        let files = enumerator.allObjects.compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertFalse(files.isEmpty, "The canonical corpus must not be empty")
        let source = try object(Data(contentsOf: root.appendingPathComponent("SOURCE.json")))
        var executed = 0
        var excluded = 0
        for relativePath in files {
            let file = cases.appendingPathComponent(relativePath)
            do {
                // Decode only expectations here; raw response bytes may exceed Double range.
                let metadata = try decoder.decode(FixtureMetadata.self, from: Data(contentsOf: file))
                let fixture = try object(JSONEncoder().encode(metadata))
                guard applies(fixture) else { excluded += 1; continue }
                guard (fixture["context"] as? [String: Any])?["targetingKey"] is String else {
                    XCTFail("\(file.lastPathComponent): iOS requires a string targetingKey; null-context fixtures must exclude ios upstream")
                    continue
                }
                executed += 1
                try XCTContext.runActivity(named: "\(source["commit"]!) / \(file.lastPathComponent)") { _ in
                    let responseData = try Data(contentsOf: root.appendingPathComponent("responses/cases").appendingPathComponent(relativePath))
                    if fixture["expectedResponseError"] != nil {
                        XCTAssertEqual(fixture["expectedResponseError"] as? String, "INVALID_RESPONSE")
                        try runRejected(fixture, responseData: responseData)
                        if case .failure(.invalidResponse) = try signedResponse(responseData) {} else {
                            XCTFail("A valid signature must not admit an invalid canonical response")
                        }
                        return
                    }
                    let context = try decoder.decode(FlagsEvaluationContext.self, from: data(fixture["context"]!))
                    let response = try fetchAccepted(responseData, context: context)
                    let initial = FlagsData(
                        flags: response.flags,
                        context: context,
                        date: Date(),
                        obfuscation: response.obfuscation,
                        observeFullEvaluationData: response.observeFullEvaluationData,
                        keySpellings: response.keySpellings
                    )
                    let restored = try restoreThroughDataStore(initial)
                    let verified = try signedResponse(responseData).get()
                    XCTAssertNotNil(verified.verification)
                    let signed = FlagsData(
                        flags: verified.flags,
                        context: context,
                        date: Date(),
                        obfuscation: verified.obfuscation,
                        observeFullEvaluationData: verified.observeFullEvaluationData,
                        keySpellings: verified.keySpellings
                    )
                    let states = [("network-decoded", initial), ("serialized-state", restored), ("required-verified", signed)]
                    for (label, state) in states {
                        try XCTContext.runActivity(named: label) { _ in try run(fixture, state: state) }
                    }
                }
            } catch {
                XCTFail("Canonical fixture \(file.lastPathComponent): \(error)")
            }
        }
        XCTAssertGreaterThan(executed, 0, "All canonical fixtures were excluded (\(excluded))")
        print("Canonical precompute \(source["commit"] as? String ?? "unknown"): \(executed) fixtures executed, \(excluded) excluded, \(executedEvaluations) evaluations executed across all states")
    }

    func testRunnerMatchesBooleansOnlyWithBooleans() throws {
        let events = try object(Data(#"{"runtime_default_used":1,"flag":{"enabled":true}}"#.utf8))
        XCTAssertFalse(matches(events["runtime_default_used"], true))
        XCTAssertFalse(matches(events, ["flag": ["enabled": 1]]))
        XCTAssertTrue(matches(events, ["runtime_default_used": 1, "flag": ["enabled": true]]))
    }

    func testRunnerReportsMatchersWithoutAPositiveIntegerCount() throws {
        let event = try object(Data(#"{"flag":"f"}"#.utf8))
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(#"[0,-1,true,"1",1.5,null]"#.utf8)) as? [Any])
        for count in counts {
            XCTExpectFailure("`_count` \(count) is not a positive integer")
            assertEvents([event], matchers: [["flag": "f", "_count": count]], exact: false)
        }
        XCTExpectFailure("A missing `_count` is not a positive integer")
        assertEvents([event], matchers: [["flag": "f"]], exact: false)
    }

    private struct FixtureMetadata: Codable {
        let context: AnyValue
        let evaluations: AnyValue
        let expectations: AnyValue
        let expectedResponseError: String?
        let _include: AnyValue?
        let _skip: AnyValue?
    }

    /// Decodes accepted fixture bytes through the production fetcher.
    private func fetchAccepted(_ responseData: Data, context: FlagsEvaluationContext) throws -> FlagAssignmentsResponse {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
            fetch: { _, complete in complete(.success((responseData, .mockAny()))) }
        )
        let fetched = expectation(description: "Accepted canonical response")
        var result: Result<FlagAssignmentsResponse, FlagsError>?
        fetcher.flagAssignments(for: context) { value in
            result = value
            fetched.fulfill()
        }
        wait(for: [fetched], timeout: 2)
        return try XCTUnwrap(result).get()
    }

    /// Verifies the same fixture bytes through the required signing path.
    private func signedResponse(_ body: Data) throws -> Result<FlagAssignmentsResponse, FlagsError> {
        let now = SigningChainFixture.now
        let anchor = try SigningChainFixture.root("root-a")
        let fixture = try SigningChainFixture.credential("two-intermediates")
        let completed = expectation(description: "Verify canonical response bytes")
        var result: Result<FlagAssignmentsResponse, FlagsError>?
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(context: .mockWith(source: "ios")),
            responseSigning: .init(mode: .required, trustedRootCertificates: [anchor]),
            dateProvider: DateProviderMock(now: Date(timeIntervalSince1970: now)),
            signingFetch: { request, completion in
                do {
                    let fields = try fixture.signedHeaders(request: request, body: body, now: now)
                    let url = try XCTUnwrap(request.url)
                    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: fields))
                    completion(.success((body, response)))
                } catch { completion(.failure(error)) }
            },
            fetch: { _, _ in XCTFail("Required verification must not retry unsigned") }
        )
        fetcher.flagAssignments(for: .init(targetingKey: "canonical")) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        return try XCTUnwrap(result)
    }

    /// Persists and restores through the production store, including its version selection and version check.
    private func restoreThroughDataStore(_ flagsData: FlagsData) throws -> FlagsData {
        let scope = FeatureScopeMock()
        scope.flagsDataStore.setFlagsData(flagsData, forClientNamed: "canonical")
        let read = expectation(description: "Canonical cache restored")
        var restored: FlagsData?
        scope.flagsDataStore.flagsData(forClientNamed: "canonical") { value in
            restored = value
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        return try XCTUnwrap(restored, "FlagsDataStore rejected the cache it wrote")
    }

    private func runRejected(_ fixture: [String: Any], responseData: Data) throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let date = DateProviderMock()
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: scope,
            fetch: { _, complete in complete(.success((responseData, .mockAny()))) }
        )
        let repository = FlagsRepository(
            clientName: UUID().uuidString,
            flagAssignmentsFetcher: fetcher,
            dateProvider: date,
            featureScope: scope,
            flagSelection: nil,
            initializationTimeout: nil
        )
        let aggregator = EvaluationAggregator(dateProvider: date, featureScope: scope, flushInterval: 100)
        let client = FlagsClient(
            repository: repository,
            exposureLogger: ExposureLogger(dateProvider: date, featureScope: scope),
            evaluationLogger: EvaluationLogger(aggregator: aggregator),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )
        let completed = expectation(description: "Rejected canonical response")
        let context = try decoder.decode(FlagsEvaluationContext.self, from: data(fixture["context"]!))
        client.setEvaluationContext(context) { result in
            if case .failure(.invalidResponse) = result {} else { XCTFail("Expected invalidResponse, got \(result)") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        repository.flush()
        aggregator.sendEvaluations()
        XCTAssertEqual(repository.state.currentState, .error)
        XCTAssertTrue(try scope.eventsWritten(ofType: ExposureEvent.self).isEmpty)
        XCTAssertTrue(try scope.eventsWritten(ofType: FlagEvaluationEvent.self).isEmpty)
    }

    private func run(_ fixture: [String: Any], state: FlagsData) throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let date = DateProviderMock()
        let aggregator = EvaluationAggregator(dateProvider: date, featureScope: scope, flushInterval: 100)
        let client = FlagsClient(
            repository: FlagsRepositoryMock(flagsData: state),
            exposureLogger: ExposureLogger(dateProvider: date, featureScope: scope),
            evaluationLogger: EvaluationLogger(aggregator: aggregator),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )
        let evaluations = try XCTUnwrap(fixture["evaluations"] as? [[String: Any]])
        for evaluation in evaluations where applies(evaluation) {
            switch evaluation["variationType"] as? String {
            case "boolean": try check(evaluation, client: client, type: Bool.self)
            case "string": try check(evaluation, client: client, type: String.self)
            case "integer": try check(evaluation, client: client, type: Int.self)
            case "float": try check(evaluation, client: client, type: Double.self)
            case "object": try check(evaluation, client: client, type: AnyValue.self)
            default: XCTFail("Unsupported canonical getter"); return
            }
        }
        aggregator.sendEvaluations()
        let expected = try XCTUnwrap(fixture["expectations"] as? [String: Any])
        let exposures = try scope.eventsWritten(ofType: ExposureEvent.self).map { try object(JSONEncoder().encode($0)) }
        let events = try scope.eventsWritten(ofType: FlagEvaluationEvent.self).map { try object(JSONEncoder().encode($0)) }
        assertEvents(exposures, matchers: expected["exposures"] as? [[String: Any]] ?? [], exact: expected["noUnmatchedEvents"] as? Bool == true)
        assertEvents(events, matchers: expected["evaluationEvents"] as? [[String: Any]] ?? [], exact: expected["noUnmatchedEvents"] as? Bool == true)
    }

    private func check<T: FlagValue & Decodable & Equatable>(_ evaluation: [String: Any], client: FlagsClient, type: T.Type) throws {
        let key = try XCTUnwrap(evaluation["flag"] as? String)
        let fallback = try decoder.decode(T.self, from: data(evaluation["defaultValue"]!))
        let expected = try XCTUnwrap(evaluation["expectedResult"] as? [String: Any])
        let details = client.getDetails(key: key, defaultValue: fallback)
        executedEvaluations += 1
        XCTAssertEqual(details.value, try decoder.decode(T.self, from: data(expected["value"]!)), key)
        if expected.keys.contains("reason") {
            XCTAssertEqual(details.error == nil ? details.reason : "ERROR", expected["reason"] as? String, key)
        }
        if expected.keys.contains("variantKey") { XCTAssertEqual(details.variant, expected["variantKey"] as? String, key) }
        if expected.keys.contains("errorCode") { XCTAssertEqual(errorCode(details.error), expected["errorCode"] as? String, key) }
    }

    private func errorCode(_ error: FlagEvaluationError?) -> String? {
        switch error {
        case .none: return nil
        case .providerNotReady: return "PROVIDER_NOT_READY"
        case .flagNotFound: return "FLAG_NOT_FOUND"
        case .typeMismatch: return "TYPE_MISMATCH"
        case .invalidContext: return "INVALID_CONTEXT"
        }
    }

    private func applies(_ value: [String: Any]) -> Bool {
        func contains(_ field: String) -> Bool { (value[field] as? [[String: Any]] ?? []).contains { $0["platform"] as? String == "ios" } }
        return !contains("_skip") && (value["_include"] == nil || contains("_include"))
    }

    private func assertEvents(_ events: [[String: Any]], matchers: [[String: Any]], exact: Bool) {
        var remaining = events
        for matcher in matchers where applies(matcher) {
            let fields = matcher.filter { !$0.key.hasPrefix("_") }
            guard let count = matcher["_count"] as? Int, count > 0, !isBoolean(matcher["_count"]) else {
                XCTFail("Matcher without a positive integer _count: \(matcher)")
                continue
            }
            for _ in 0..<count {
                guard let index = remaining.firstIndex(where: { matches($0, fields) }) else {
                    XCTFail("Missing event for \(matcher); remaining: \(remaining)"); return
                }
                remaining.remove(at: index)
            }
        }
        if exact { XCTAssertTrue(remaining.isEmpty, "Unmatched events: \(remaining)") }
    }

    private func matches(_ actual: Any?, _ expected: Any) -> Bool {
        if expected is NSNull {
            return actual == nil || actual is NSNull
        }
        if let expected = expected as? [String: Any] {
            guard let actual = actual as? [String: Any] else {
                return false
            }
            return expected.allSatisfy { matches(actual[$0.key], $0.value) }
        }
        // NSNumber equality treats `true` as `1`, so Booleans must match Booleans.
        if isBoolean(expected) != isBoolean(actual) {
            return false
        }
        return (actual as? NSObject)?.isEqual(expected) == true
    }

    private func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) }
    private func object(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
}

#if canImport(DatadogSDKTesting)
// This suite reads fetched fixture JSON at run time. Run it even when Swift coverage is unchanged.
extension CanonicalPrecomputedTests: FinalTaggedType {
    static var finalTypeTags: FinalTypeTags<CanonicalPrecomputedTests> {
        withTagger { $0.set(type: .tiaSkippable, to: false) }
    }
}
#endif
