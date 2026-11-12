/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import XCTest
@testable import RulesEvaluationPrototype

internal final class RulesEvaluatorTests: XCTestCase {
    func testSharedConformanceFixtures() throws {
        let evaluator = try FixtureSupport.evaluator()
        let cases = try FixtureSupport.cases()
        XCTAssertGreaterThan(cases.count, 100)
        for (index, test) in cases.enumerated() {
            let result = test.evaluate(with: evaluator)
            let message = "case \(index), flag \(test.flag), targetingKey \(test.targetingKey ?? "nil")"
            XCTAssertEqual(result.value, test.result.value, message)
            XCTAssertEqual(result.reason, test.result.reason, message)
            XCTAssertEqual(result.errorCode, test.result.errorCode, message)
        }
    }

    func testContextAToBToAReusesConfiguration() throws {
        let evaluator = try FixtureSupport.evaluator()
        let contextA = RulesContext(targetingKey: "same-user", attributes: ["country": .string("US")])
        let contextB = RulesContext(targetingKey: "same-user", attributes: ["country": .string("Germany")])
        func evaluate(_ context: RulesContext) -> RulesEvaluation {
            evaluator.evaluate(flagKey: "kill-switch", type: .boolean, defaultValue: .boolean(false), context: context, at: FixtureSupport.date)
        }
        let first = evaluate(contextA)
        XCTAssertEqual(first.value, .boolean(true))
        XCTAssertEqual(evaluate(contextB).value, .boolean(false))
        XCTAssertEqual(evaluate(contextA), first)
    }

    func testAssignmentMetadataAndEvaluationTimeAreReturnedWithoutTracking() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(splits: [split(serialID: 4_184_331)], doLog: true)]
        }
        let result = evaluate(evaluator)
        XCTAssertEqual(result.variant, "on")
        XCTAssertEqual(result.allocationKey, "allocation")
        XCTAssertEqual(result.splitSerialID, 4_184_331)
        XCTAssertTrue(result.doLog)
        XCTAssertTrue(result.observeFullEvaluationData)
        XCTAssertEqual(result.evaluatedAt, FixtureSupport.date)
    }

    func testUnsupportedOperatorIsExplicitAndValidSiblingStillEvaluates() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(conditions: [condition("MATCHES", value: "^US$")])]
        }
        let result = evaluate(evaluator)
        XCTAssertEqual(result.value, .boolean(false))
        XCTAssertEqual(result.reason, .error)
        XCTAssertEqual(result.errorCode, .parseError)
        XCTAssertEqual(result.preparationError, .unsupportedOperator("MATCHES"))
        XCTAssertEqual(evaluate(evaluator, key: "sibling").value, .boolean(true))
    }

    func testMalformedJSONAndUnsupportedEnvelopeAreRejected() {
        XCTAssertThrowsError(try RulesConfiguration.parse(Data("{".utf8)))
        XCTAssertThrowsError(try RulesConfiguration.parse(Data(#"{"format":"CLIENT","flags":{}}"#.utf8))) {
            XCTAssertEqual($0 as? RulesPreparationError, .unsupportedFormat)
        }
    }

    func testMissingAndEmptyTargetingKeysAreDifferentForSplits() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(splits: [split(shards: [shard(start: 0, end: 10_000)])])]
        }
        XCTAssertEqual(evaluate(evaluator).errorCode, .targetingKeyMissing)
        let empty = evaluate(evaluator, context: RulesContext(targetingKey: ""))
        XCTAssertEqual(empty.value, .boolean(true))
        XCTAssertEqual(empty.reason, .split)
        XCTAssertNil(empty.errorCode)
    }

    func testTargetingKeyAliasDoesNotReplaceAnExplicitIDAttribute() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(conditions: [condition("ONE_OF", value: ["alice"], attribute: "id")])]
        }
        XCTAssertEqual(evaluate(evaluator, context: RulesContext(targetingKey: "alice")).value, .boolean(true))
        XCTAssertEqual(evaluate(evaluator, context: RulesContext(targetingKey: "alice", attributes: ["id": .string("bob")])).value, .boolean(false))
        XCTAssertEqual(evaluate(evaluator, context: RulesContext(targetingKey: "alice", attributes: ["id": .null])).value, .boolean(false))
    }

    func testNullAndMissingDoNotMatchNegatedMembership() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(conditions: [condition("NOT_ONE_OF", value: ["US"])])]
        }
        for attributes: [String: RulesValue] in [[:], ["country": .null], ["country": .array([])], ["country": .object([:])]] {
            XCTAssertEqual(evaluate(evaluator, context: RulesContext(attributes: attributes)).reason, .defaultValue)
        }
        XCTAssertEqual(evaluate(evaluator, context: RulesContext(attributes: ["country": .string("UK")])).value, .boolean(true))
    }

    func testNumericComparisonDoesNotCoerceBooleanOrWhitespace() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(conditions: [condition("GTE", value: 50, attribute: "age")])]
        }
        for value: RulesValue in [.boolean(true), .string(" 50"), .string("50\n"), .string("0x40"), .string("NaN"), .string("Infinity"), .array([])] {
            XCTAssertEqual(evaluate(evaluator, context: RulesContext(attributes: ["age": value])).value, .boolean(false))
        }
        for value: RulesValue in [.number(50), .string("50"), .string("+5e1")] {
            XCTAssertEqual(evaluate(evaluator, context: RulesContext(attributes: ["age": value])).value, .boolean(true))
        }
    }

    func testTimeWindowIsStartInclusiveAndEndExclusive() throws {
        let evaluator = try makeEvaluator { flag in
            var scheduled = allocation()
            scheduled["startAt"] = "2026-01-01T00:00:00.000Z"
            scheduled["endAt"] = "2026-01-02T00:00:00.000Z"
            flag["allocations"] = [scheduled]
        }
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        XCTAssertEqual(evaluate(evaluator, at: start.addingTimeInterval(-0.001)).value, .boolean(false))
        XCTAssertEqual(evaluate(evaluator, at: start).value, .boolean(true))
        XCTAssertEqual(evaluate(evaluator, at: start.addingTimeInterval(86_400)).value, .boolean(false))
    }

    func testSplitRangeIsStartInclusiveAndEndExclusive() throws {
        let bucket = RulesEvaluator.shard(salt: "salt", targetingKey: "alice", totalShards: 10_000)
        let including = try makeEvaluator { flag in
            flag["allocations"] = [allocation(splits: [split(shards: [shard(start: bucket, end: bucket + 1)])])]
        }
        let excluding = try makeEvaluator { flag in
            flag["allocations"] = [allocation(splits: [split(shards: [shard(start: 0, end: bucket)])])]
        }
        let context = RulesContext(targetingKey: "alice")
        XCTAssertEqual(evaluate(including, context: context).value, .boolean(true))
        XCTAssertEqual(evaluate(excluding, context: context).value, .boolean(false))
    }

    func testAllShardsMustMatchAndLaterAllocationsCanMatch() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [
                allocation(splits: [split(shards: [shard(start: 0, end: 10_000), shard(start: 0, end: 0)])]),
                allocation(splits: [split()], doLog: true),
            ]
        }
        let result = evaluate(evaluator, context: RulesContext(targetingKey: "alice"))
        XCTAssertEqual(result.reason, .staticValue)
        XCTAssertTrue(result.doLog)
    }

    func testZeroShardCountIsRejectedWithoutModuloCrash() throws {
        let evaluator = try makeEvaluator { flag in
            flag["allocations"] = [allocation(splits: [split(shards: [["salt": "salt", "totalShards": 0, "ranges": []]])])]
        }
        XCTAssertEqual(evaluate(evaluator).errorCode, .parseError)
    }

    func testInvalidDateDoesNotPoisonSiblingFlag() throws {
        let evaluator = try makeEvaluator { flag in
            var scheduled = allocation()
            scheduled["startAt"] = "not-a-date"
            flag["allocations"] = [scheduled]
        }
        XCTAssertEqual(evaluate(evaluator).errorCode, .parseError)
        XCTAssertEqual(evaluate(evaluator, key: "sibling").value, .boolean(true))
    }

    func testTypeMismatchDoesNotProduceExposureMetadata() throws {
        let evaluator = try makeEvaluator()
        let result = evaluator.evaluate(flagKey: "test", type: .string, defaultValue: .string("fallback"), context: RulesContext(), at: FixtureSupport.date)
        XCTAssertEqual(result.errorCode, .typeMismatch)
        XCTAssertEqual(result.value, .string("fallback"))
        XCTAssertNil(result.variant)
        XCTAssertNil(result.allocationKey)
        XCTAssertFalse(result.doLog)
    }

    private func evaluate(_ evaluator: RulesEvaluator, key: String = "test", context: RulesContext = RulesContext(), at date: Date = FixtureSupport.date) -> RulesEvaluation {
        evaluator.evaluate(flagKey: key, type: .boolean, defaultValue: .boolean(false), context: context, at: date)
    }

    private func makeEvaluator(_ update: (inout [String: Any]) -> Void = { _ in }) throws -> RulesEvaluator {
        let base: [String: Any] = [
            "key": "test", "enabled": true, "variationType": "BOOLEAN",
            "variations": ["on": ["key": "on", "value": true]],
            "allocations": [allocation()],
        ]
        var flag = base
        update(&flag)
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "SERVER", "observeFullEvaluationData": true,
            "flags": ["test": flag, "sibling": base],
        ])
        return RulesEvaluator(configuration: try RulesConfiguration.parse(data))
    }

    private func allocation(conditions: [[String: Any]] = [], splits: [[String: Any]]? = nil, doLog: Bool = false) -> [String: Any] {
        ["key": "allocation", "rules": conditions.isEmpty ? [] : [["conditions": conditions]], "splits": splits ?? [split()], "doLog": doLog]
    }

    private func split(shards: [[String: Any]] = [], serialID: UInt64 = 0) -> [String: Any] {
        ["variationKey": "on", "shards": shards, "serialId": serialID]
    }

    private func shard(start: Int, end: Int) -> [String: Any] {
        ["salt": "salt", "totalShards": 10_000, "ranges": [["start": start, "end": end]]]
    }

    private func condition(_ operation: String, value: Any, attribute: String = "country") -> [String: Any] {
        ["operator": operation, "attribute": attribute, "value": value]
    }
}
