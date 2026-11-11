/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogFlags

final class PortableFlagsConfigurationTests: XCTestCase {
    func testRoundTripPreservesValuesContextAndMetadata() throws {
        let object: AnyValue = .dictionary(["nested": .array([.null, .bool(true)])])
        let values: [(String, AnyValue, FlagAssignment.Variation)] = [
            ("boolean", .bool(false), .boolean(false)), ("string", .string(""), .string("")),
            ("integer", .int(0), .integer(0)), ("float", .double(0.5), .double(0.5)),
            ("object", object, .object(object)),
        ]
        let context: [String: Any] = ["targetingKey": "subject", "plan": "pro", "nested": ["items": [1, 2]]]
        for (type, value, expected) in values {
            let jsonValue = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
            let input = try wire(
                flags: ["flag": flag(type: type, value: jsonValue)],
                entry: ["context": context, "fetchedAt": 1_700_000_000_123.5, "etag": "revision"],
                attributes: ["observeFullEvaluationData": true, "evaluation_options": ["experimentation_opt_out": true]]
            )
            let parsed = PortableFlagsConfiguration.fromString(input)
            let precomputed = try XCTUnwrap(parsed.precomputed)
            let encoded = try parsed.toString()
            let output = PortableFlagsConfiguration.fromString(encoded)
            let inputEntry = try XCTUnwrap(json(input)["precomputed"] as? [String: Any])
            let outputEnvelope = try json(encoded)
            let outputEntry = try XCTUnwrap(outputEnvelope["precomputed"] as? [String: Any])

            XCTAssertNil(parsed.failure)
            XCTAssertEqual(Set(outputEnvelope.keys), ["version", "precomputed"])
            XCTAssertEqual(outputEnvelope["version"] as? Int, 1)
            XCTAssertEqual(Set(outputEntry.keys), ["response", "context", "fetchedAt", "etag"])
            XCTAssertEqual(outputEntry["response"] as? String, inputEntry["response"] as? String)
            XCTAssertEqual(precomputed.context?["targetingKey"], .string("subject"))
            XCTAssertEqual(precomputed.fetchedAt, 1_700_000_000_123.5)
            XCTAssertEqual(precomputed.etag, "revision")
            XCTAssertEqual(precomputed.assignments.flags["flag"]?.serialID, 42)
            XCTAssertEqual(precomputed.assignments.flags["flag"]?.variation, expected)
            XCTAssertEqual(precomputed.assignments.flags["flag"]?.reason, "TARGETING_MATCH")
            XCTAssertEqual(precomputed.assignments.flags["flag"]?.doLog, true)
            XCTAssertEqual(precomputed.assignments.experimentationOptOut, true)
            XCTAssertEqual(output.precomputed?.assignments, precomputed.assignments)
            XCTAssertEqual(output.precomputed?.context, precomputed.context)
            XCTAssertEqual(output.precomputed?.response, precomputed.response)
            XCTAssertEqual(output.precomputed?.fetchedAt, precomputed.fetchedAt)
            XCTAssertEqual(output.precomputed?.etag, precomputed.etag)
            let response = try XCTUnwrap(json(precomputed.response)["data"] as? [String: Any])
            let attributes = try XCTUnwrap(response["attributes"] as? [String: Any])
            XCTAssertEqual(attributes["observeFullEvaluationData"] as? Bool, true)
        }
    }

    func testAcceptsBrowserVariationAliases() throws {
        let values: [(String, Any)] = [
            ("BOOLEAN", true), ("STRING", "text"), ("NUMBER", 1.5), ("NUMERIC", 2),
            ("INTEGER", 1.5), ("JSON", ["a": 1]), ("OBJECT", NSNull()),
        ]
        for (type, value) in values {
            let parsed = PortableFlagsConfiguration.fromString(try wire(flags: ["flag": flag(type: type, value: value)]))
            XCTAssertNotNil(parsed.precomputed?.assignments.flags["flag"], type)
            XCTAssertTrue(try XCTUnwrap(parsed.precomputed).assignments.failedFlags.isEmpty, type)
        }
    }

    func testNativeNumericTypesMatchNetworkParser() throws {
        for (type, value) in [
            ("integer", "0"), ("integer", "2"), ("integer", "-2"),
            ("float", "2"), ("float", "2.0"), ("float", "2.5"),
            ("number", "2"), ("number", "2.5"),
        ] {
            let response = """
            {"data":{"attributes":{"createdAt":0,"flags":{"flag":{
              "allocationKey":"allocation","variationKey":"variant","variationType":"\(type)",
              "variationValue":\(value),"reason":"TARGETING_MATCH","doLog":true
            }}}}}
            """
            let network = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: Data(response.utf8))
            let expected = try XCTUnwrap(network.flags["flag"])
            let parsed = PortableFlagsConfiguration.fromString(try wire(entry: ["response": response]))
            let restored = PortableFlagsConfiguration.fromString(try parsed.toString())

            for configuration in [parsed, restored] {
                let assignment = try XCTUnwrap(configuration.precomputed?.assignments.flags["flag"])
                XCTAssertEqual(assignment, expected, "\(type)=\(value)")
                XCTAssertEqual(assignment.variation(as: Int.self), expected.variation(as: Int.self), "\(type)=\(value)")
                XCTAssertEqual(assignment.variation(as: Double.self), expected.variation(as: Double.self), "\(type)=\(value)")
            }
        }
    }

    func testFractionalNativeIntegerDoesNotDiscardValidSibling() throws {
        let parsed = PortableFlagsConfiguration.fromString(try wire(flags: [
            "good": flag(), "bad": flag(type: "integer", value: 2.5),
        ]))
        let precomputed = try XCTUnwrap(parsed.precomputed)
        XCTAssertNil(parsed.failure)
        XCTAssertEqual(Array(precomputed.assignments.flags.keys), ["good"])
        XCTAssertEqual(precomputed.assignments.failedFlags, ["bad": "Invalid precomputed flag configuration"])
    }

    func testAbsentAndEmptyContextRemainDistinct() throws {
        let absent = PortableFlagsConfiguration.fromString(try wire())
        let empty = PortableFlagsConfiguration.fromString(try wire(entry: ["context": [:]]))
        XCTAssertNil(absent.precomputed?.context)
        XCTAssertEqual(empty.precomputed?.context, [:])
        XCTAssertNil(PortableFlagsConfiguration.fromString(try absent.toString()).precomputed?.context)
        XCTAssertEqual(PortableFlagsConfiguration.fromString(try empty.toString()).precomputed?.context, [:])
    }

    func testMalformedFlagDoesNotDiscardSiblingsOrDisappearOnRoundTrip() throws {
        let invalidFlags: [Any] = [NSNull(), [:], flag(type: "new-type", value: true), flag(type: "boolean", value: "true")]
        for invalidFlag in invalidFlags {
            let parsed = PortableFlagsConfiguration.fromString(try wire(flags: ["good": flag(), "bad": invalidFlag]))
            let assignments = try XCTUnwrap(parsed.precomputed).assignments
            XCTAssertEqual(Array(assignments.flags.keys), ["good"])
            XCTAssertEqual(assignments.failedFlags, ["bad": "Invalid precomputed flag configuration"])
            XCTAssertEqual(PortableFlagsConfiguration.fromString(try parsed.toString()).precomputed?.assignments, assignments)
        }
    }

    func testRejectsInvalidEnvelopeWithoutThrowing() {
        for input in ["not JSON", "null", "[]", "{}", "{\"version\":999}", "{\"version\":\"1\"}"] {
            let parsed = PortableFlagsConfiguration.fromString(input)
            XCTAssertEqual(parsed.failure, .invalidEnvelope, input)
            XCTAssertNil(parsed.precomputed)
        }
    }

    func testAcceptsBothEnvelopeVersionsAndEmptyConfigurations() {
        for version in [1, 2] {
            let parsed = PortableFlagsConfiguration.fromString("{\"version\":\(version)}")
            XCTAssertNil(parsed.failure)
            XCTAssertNil(parsed.precomputed)
        }
    }

    func testInvalidPrecomputedEntryIsDistinctFromInvalidEnvelope() throws {
        let entries: [[String: Any]] = [
            ["context": NSNull()], ["context": []], ["context": ["targetingKey": 1]],
            ["fetchedAt": "123"], ["fetchedAt": NSNull()], ["etag": 1], ["etag": NSNull()],
            ["response": "not JSON"], ["response": [:]],
        ]
        for entry in entries {
            let parsed = PortableFlagsConfiguration.fromString(try wire(entry: entry))
            XCTAssertEqual(parsed.failure, .invalidPrecomputed)
            XCTAssertNil(parsed.precomputed)
            XCTAssertEqual(try json(parsed.toString())["version"] as? Int, 1)
        }
        XCTAssertEqual(PortableFlagsConfiguration.fromString("{\"version\":1,\"precomputed\":null}").failure, .invalidPrecomputed)
    }

    func testRejectsMalformedResponseStructure() throws {
        for response in ["null", "[]", "{}", "{\"data\":{\"attributes\":{\"flags\":{}}}}"] {
            XCTAssertEqual(PortableFlagsConfiguration.fromString(try wire(entry: ["response": response])).failure, .invalidPrecomputed)
        }
        for createdAt in [NSNull(), true, [:]] as [Any] {
            XCTAssertEqual(PortableFlagsConfiguration.fromString(try wire(attributes: ["createdAt": createdAt])).failure, .invalidPrecomputed)
        }
    }

    func testUnrepresentableNumberRejectsEntirePrecomputedEntry() throws {
        // Foundation rejects numeric overflow before individual flags can be isolated.
        let response = """
        {"data":{"attributes":{"createdAt":0,"flags":{
          "good":\(try string(flag())),
          "bad":{"allocationKey":"allocation","variationKey":"variant","variationType":"number",
                 "variationValue":1e400,"reason":"TARGETING_MATCH","doLog":true}
        }}}}
        """
        let parsed = PortableFlagsConfiguration.fromString(try wire(entry: ["response": response]))
        XCTAssertEqual(parsed.failure, .invalidPrecomputed)
        XCTAssertNil(parsed.precomputed)
        XCTAssertEqual(try parsed.toString(), "{\"version\":1}")
    }

    func testPrecomputedOnlyCodecIgnoresRulesSibling() throws {
        var input = try json(wire())
        input["rules"] = ["response": "invalid protobuf"]
        let parsed = PortableFlagsConfiguration.fromString(try string(input))
        XCTAssertNil(parsed.failure)
        XCTAssertNotNil(parsed.precomputed)
        XCTAssertNil(try json(parsed.toString())["rules"])
    }

    func testEncodedKeysRoundTripAsVersionTwo() throws {
        let parsed = PortableFlagsConfiguration.fromString(try wire(flags: [digest: flag()], attributes: encoding))
        let precomputed = try XCTUnwrap(parsed.precomputed)
        XCTAssertEqual(precomputed.assignments.obfuscation?.lookupKey(for: "flag"), digest)
        XCTAssertEqual(try json(parsed.toString())["version"] as? Int, 2)
        XCTAssertEqual(PortableFlagsConfiguration.fromString(try parsed.toString()).precomputed?.assignments, precomputed.assignments)
    }

    func testRejectsInvalidEncodingMetadataWithValidDigestKeys() throws {
        let invalidMetadata: [[String: Any]] = [
            ["obfuscated": true], ["obfuscated": "true"], ["obfuscation": [:]],
            ["obfuscated": true, "obfuscation": ["scheme": "unknown", "salt": salt]],
            ["obfuscated": true, "obfuscation": ["scheme": "flag-key-sha256-v1", "salt": "bad"]],
        ]
        for metadata in invalidMetadata {
            let parsed = PortableFlagsConfiguration.fromString(try wire(flags: [digest: flag()], attributes: metadata))
            XCTAssertEqual(parsed.failure, .invalidPrecomputed)
        }
    }

    func testRejectsPlaintextKeyOfMalformedFlagInEncodedResponse() throws {
        XCTAssertEqual(PortableFlagsConfiguration.fromString(try wire(flags: ["plaintext": [:]], attributes: encoding)).failure, .invalidPrecomputed)
    }

    private let digest = "9817872c144b018abd77e3915bd77e2c27f4f534dccff8ffaca27361e3a5e1ee"
    private let salt = "000102030405060708090a0b0c0d0e0f"
    private var encoding: [String: Any] {
        ["obfuscated": true, "obfuscation": ["scheme": "flag-key-sha256-v1", "salt": salt]]
    }

    private func flag(type: String = "boolean", value: Any = true) -> [String: Any] {
        [
            "allocationKey": "allocation", "variationKey": "variant", "variationType": type,
            "variationValue": value, "reason": "TARGETING_MATCH", "doLog": true, "serialId": 42,
        ]
    }

    private func wire(flags: [String: Any]? = nil, entry: [String: Any] = [:], attributes: [String: Any] = [:]) throws -> String {
        let attributes = ["createdAt": "2026-01-01T00:00:00Z", "flags": flags ?? ["flag": flag()]]
            .merging(attributes) { _, replacement in replacement }
        let precomputed = ["response": try string(["data": ["attributes": attributes]])] as [String: Any]
        return try string(["version": 1, "precomputed": precomputed.merging(entry) { _, replacement in replacement }])
    }

    private func string(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }

    private func json(_ string: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }
}
