/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import CryptoKit
import SwiftProtobuf
import XCTest
@testable import RulesEvaluationPrototype

final class ProtobufBenchmarkTests: XCTestCase {
    func testSharedClientFixturesThroughBothDecoders() throws {
        let fixtures = try loadFixtures()
        let bridge = FlagsBenchmark()
        for fixture in fixtures {
            let base64 = try XCTUnwrap(fixture["protobufBase64"] as? String)
            let bytes = try XCTUnwrap(Data(base64Encoded: base64))
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), fixture["sha256"] as? String)
            _ = bridge.run(["op": "preload", "base64": base64])
            let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
            for install in [["op": "installBinary"], ["op": "installJson", "json": fixture["protoJson"] as! String]] {
                XCTAssertEqual(bridge.run(install)["flagCount"] as? Int, 10)
                for entry in cases {
                    let request = try XCTUnwrap(entry["request"] as? [String: Any])
                    let expected = try XCTUnwrap(entry["expected"] as? [String: Any])
                    XCTAssertEqual(try canonical(bridge.run(request)), try canonical(expected))
                }
            }
            let exported = bridge.run(["op": "binaryToJson"])
            let roundtrip = try ClientRules(jsonString: XCTUnwrap(exported["json"] as? String))
            XCTAssertEqual(roundtrip, try ClientRules(serializedBytes: bytes))
        }
    }

    func testContextChangesAndReplacementWithoutReloadingPerRead() throws {
        let fixtures = try loadFixtures()
        let bridge = FlagsBenchmark()
        _ = bridge.run(["op": "installJson", "json": fixtures[0]["protoJson"]!])
        let paid = request(flag: "flag-1", plan: "paid")
        let free = request(flag: "flag-1", plan: "free")
        XCTAssertEqual(bridge.run(paid)["value"] as? Bool, true)
        XCTAssertEqual(bridge.run(free)["value"] as? Bool, false)
        XCTAssertEqual(bridge.run(paid)["value"] as? Bool, true)
        _ = bridge.run(["op": "installJson", "json": fixtures[1]["protoJson"]!])
        XCTAssertEqual(bridge.run(paid)["value"] as? Bool, false)
        _ = bridge.run(["op": "installJson", "json": fixtures[0]["protoJson"]!])
        XCTAssertEqual(bridge.run(paid)["value"] as? Bool, true)
    }

    func testMalformedInstallPreservesPreviousSnapshot() throws {
        let bridge = FlagsBenchmark()
        XCTAssertNotNil(bridge.run(request())["benchmarkError"])
        _ = bridge.run(["op": "installJson", "json": try loadFixtures()[0]["protoJson"]!])
        XCTAssertNotNil(bridge.run(["op": "installJson", "json": "{"])["benchmarkError"])
        _ = bridge.run(["op": "preload", "base64": "AA=="])
        XCTAssertNotNil(bridge.run(["op": "installBinary"])["benchmarkError"])
        XCTAssertEqual(bridge.run(request())["value"] as? Bool, true)
        XCTAssertNotNil(bridge.run(["op": "preload", "base64": "not base64"])["benchmarkError"])
    }

    func testUnsupportedAndMalformedRulesAreExplicitErrors() throws {
        var config = try ClientRules(jsonString: loadFixtures()[0]["protoJson"] as! String)
        config.conditions[0].kind = .regex(.init())
        let engine = ProtobufRulesEvaluator(configuration: config)
        let result = engine.evaluate(try ProtobufRequest(request(flag: "flag-1")), timestamp: 123)
        XCTAssertEqual(result["errorCode"] as? String, "PARSE_ERROR")
        XCTAssertEqual(engine.evaluate(try ProtobufRequest(request()), timestamp: 123)["value"] as? Bool, true)

        config.conditions[0].kind = .all(.with { $0.conditionIndexes = [0] })
        XCTAssertEqual(ProtobufRulesEvaluator(configuration: config).evaluate(
            try ProtobufRequest(request(flag: "flag-1")), timestamp: 123
        )["errorCode"] as? String, "PARSE_ERROR")
        config.flags["flag-0"]!.minimumFeatureLevel = 1
        XCTAssertEqual(ProtobufRulesEvaluator(configuration: config).evaluate(
            try ProtobufRequest(request()), timestamp: 123
        )["errorCode"] as? String, "PARSE_ERROR")
    }

    func testMissingTargetingKeyAndZeroShardsCannotCrash() throws {
        var config = try ClientRules(jsonString: loadFixtures()[0]["protoJson"] as! String)
        let missing: [String: Any] = ["flagKey": "flag-3", "type": "boolean", "defaultValue": false, "context": [:]]
        XCTAssertEqual(ProtobufRulesEvaluator(configuration: config).evaluate(
            try ProtobufRequest(missing), timestamp: 123
        )["errorCode"] as? String, "TARGETING_KEY_MISSING")
        config.flags["flag-3"]!.allocations[0].partitionKey[0].shardMd5.totalShards = 0
        XCTAssertEqual(ProtobufRulesEvaluator(configuration: config).evaluate(
            try ProtobufRequest(request(flag: "flag-3")), timestamp: 123
        )["errorCode"] as? String, "PARSE_ERROR")
    }

    func testControlsConsumeResultsAndValidateCounts() throws {
        let fixture = try loadFixtures()[0]
        let cases = fixture["cases"] as! [[String: Any]]
        let requests = cases.map { $0["request"] as! [String: Any] }
        let expectedChecksum = cases.filter { ($0["expected"] as! [String: Any])["value"] as? Bool == true }.count
        let bridge = FlagsBenchmark()
        _ = bridge.run(["op": "preload", "base64": fixture["protobufBase64"]!])
        var input: [String: Any] = ["op": "controls", "requests": requests, "iterations": 64, "warmup": 1, "decodeIterations": 3]
        let output = bridge.run(input)
        XCTAssertNil(output["benchmarkError"])
        XCTAssertEqual(output["checksum"] as? Int, expectedChecksum)
        XCTAssertEqual(output["flagCount"] as? Int, 10)
        XCTAssertEqual((output["directEvaluation"] as? [String: Any])?["count"] as? Int, 64)
        XCTAssertEqual((output["decode"] as? [String: Any])?["count"] as? Int, 3)
        for value in [0, -1, 100_001, 1.5] {
            input["iterations"] = value
            XCTAssertNotNil(bridge.run(input)["benchmarkError"])
        }
        XCTAssertEqual(FlagsBenchmark.summarize([4, 1, 3, 2])["p50Us"] as? Double, 2_000)
    }

    private func request(flag: String = "flag-0", plan: String = "paid") -> [String: Any] {
        [
            "op": "evaluate", "flagKey": flag, "type": "boolean", "defaultValue": false,
            "context": ["targetingKey": "subject-0", "plan": plan, "age": 25],
        ]
    }

    private func loadFixtures() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "client-benchmark", withExtension: "json", subdirectory: "Fixtures"))
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return try XCTUnwrap(document["configurations"] as? [[String: Any]])
    }

    private func canonical(_ result: [String: Any]) throws -> Data {
        var result = result
        if var metadata = result["flagMetadata"] as? [String: Any] {
            metadata.removeValue(forKey: "__dd_eval_timestamp_ms")
            result["flagMetadata"] = metadata
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
}
