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

    func testCanonicalResponses() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "precomputed", withExtension: nil))
        let cases = root.appendingPathComponent("cases")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: cases, includingPropertiesForKeys: nil))
        let files = enumerator.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty, "The canonical corpus must not be empty")
        let source = try object(Data(contentsOf: root.appendingPathComponent("SOURCE.json")))
        var executed = 0
        var excluded = 0
        for file in files {
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
                    let responseData = try Data(contentsOf: root.appendingPathComponent("responses/cases").appendingPathComponent(String(file.path.dropFirst(cases.path.count + 1))))
                    if fixture["expectedResponseError"] != nil {
                        XCTAssertEqual(fixture["expectedResponseError"] as? String, "INVALID_RESPONSE")
                        try runRejected(fixture, responseData: responseData)
                        return
                    }
                    let response = try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: responseData)
                    let context = try decoder.decode(FlagsEvaluationContext.self, from: data(fixture["context"]!))
                    let initial = FlagsData(flags: response.flags, context: context, date: Date(), obfuscation: response.obfuscation)
                    let restored = try FlagsNumericJSON.decode(FlagsData.self, from: JSONEncoder().encode(initial), cached: true)
                    for (label, state) in [("network-decoded", initial), ("serialized-state", restored)] {
                        try XCTContext.runActivity(named: label) { _ in try run(fixture, state: state) }
                    }
                }
            } catch {
                XCTFail("Canonical fixture \(file.lastPathComponent): \(error)")
            }
        }
        XCTAssertGreaterThan(executed, 0, "All canonical fixtures were excluded (\(excluded))")
        print("Canonical precompute: \(executed) fixtures executed, \(excluded) excluded")
    }

    private struct FixtureMetadata: Codable {
        let context: AnyValue
        let evaluations: AnyValue
        let expectations: AnyValue
        let expectedResponseError: String?
        let _include: AnyValue?
        let _skip: AnyValue?
    }

    private func runRejected(_ fixture: [String: Any], responseData: Data) throws {
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let date = DateProviderMock()
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil, customHeaders: nil, featureScope: scope,
            fetch: { _, complete in complete(.success(responseData)) }
        )
        let repository = FlagsRepository(
            clientName: UUID().uuidString, flagAssignmentsFetcher: fetcher,
            dateProvider: date, featureScope: scope, initializationTimeout: nil
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
            let count = matcher["_count"] as! Int
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
        return (actual as? NSObject)?.isEqual(expected) == true
    }

    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) }
    private func object(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
}
