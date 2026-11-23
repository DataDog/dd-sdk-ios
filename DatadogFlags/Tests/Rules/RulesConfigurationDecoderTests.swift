/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogFlags

final class RulesConfigurationDecoderTests: XCTestCase {
    /// The rules response from the browser SDK fixture `rules-v1-wire.json`, so both SDKs decode the same bytes.
    private let browserFixture = Data(
        base64Encoded: "CgQIABAAEgRwcm9kGm0KCXRlc3QtZmxhZxJgCAAQBBoECAAoASIsCgphbGxvY2F0aW9uEAAaDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByABKAEiJgoIZmFsbGJhY2saDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByACIgYSBAoCCAMiAgoAKgJvbioDb2ZmKgJVUyoHY291bnRyeTIEXlVTJDoJCgExCgEyCgEzSgYqBAgAEAJQAA=="
    )!

    /// `DatadogFlags/Protos/fixtures/all-fields.txtpb`, encoded by `protoc`. It uses every message, oneof case and enum.
    private let allFieldsFixture = Data(
        base64Encoded: "CggIgPfE1QYQexIHc3RhZ2luZxraAQoOYWxsLXZhcmlhdGlvbnMSxwEIAhAFGgIQARoNCAEY/////////+//ARoLCAIhAAAAAAAAwL8aBAgDKAEaBAgEMAAihAEKCHRhcmdldGVkEAAaAgoAGgsSCQoEc2FsdBiQTiJYCgUIABCIJwoDEJBOEAQY/f//////////ASABKh4KBHRlYW0SBmdyb3d0aCoDcnVtKglleHBvc3VyZXMqEQoGd2VpZ2h0GQAAAAAAAOA/KggKBGJldGEgASgBMgkIgMri0AYQ5wciDgoIZmFsbGJhY2siAiADGhwKDXVua25vd24tZW51bXMSCxAqIgcKAWEiAiBNIgIKACIKEggKAggCCgIQACoCb24qA29mZioHY291bnRyeSoCVVMqBHBsYW4qD8O8bsOvY8O2ZMOpLeaXlzINXnVzZXItWzAtOV0rJDoSCgExCgEyCgEzEgRiZXRhEgExQhB7ImVuYWJsZWQiOnRydWV9SgYKBAoCAQJKBRIDCgEDSg8aDQgBEAQZAAAAAAAABEBKBCICGAFKCCoGCAESAgMFShIyEBIEc2FsdBoDAQIDGgH/IAFKBjoECAEQAUoGQgQIARADSgpKCAgBEAIYBCABSg1SCxIBcxgBIAQqAqq7SghaBhICAAEYAVABWgIICGIkNmY5NjE5ZmYtOGI4Ni1kMDExLWI0MmQtMDBjMDRmYzk2NGZm"
    )!

    func testDecodesBrowserFixture() throws {
        let configuration = try RulesConfigurationDecoder.decode(browserFixture)

        XCTAssertEqual(configuration.environmentName, "prod")
        XCTAssertEqual(configuration.strings, ["on", "off", "US", "country"])
        XCTAssertEqual(configuration.regexes, ["^US$"])

        let flag = try XCTUnwrap(configuration.flags["test-flag"])
        XCTAssertEqual(flag.variationType, .boolean)
        XCTAssertEqual(flag.allocations.map(\.key), ["allocation", "fallback"])

        let allocation = flag.allocations[0]
        XCTAssertTrue(allocation.logExposureEvent)
        XCTAssertEqual(allocation.splits.first?.serialID, 7)
        XCTAssertEqual(allocation.splits.first?.reason, .targetingMatch)
        XCTAssertEqual(flag.allocations[1].splits.first?.reason, .split)
    }

    func testDecodesTopLevelFields() throws {
        let configuration = try RulesConfigurationDecoder.decode(allFieldsFixture)

        XCTAssertEqual(configuration.createdAt?.seconds, 1_790_000_000)
        XCTAssertEqual(configuration.createdAt?.nanos, 123)
        XCTAssertEqual(configuration.environmentName, "staging")
        XCTAssertEqual(configuration.environmentID, "6f9619ff-8b86-d011-b42d-00c04fc964ff")
        XCTAssertTrue(configuration.observeFullEvaluationData)
        XCTAssertEqual(configuration.evaluatorParams?.maxDependencyDepth, 8)
        XCTAssertEqual(configuration.strings, ["on", "off", "country", "US", "plan", "ünïcödé-旗"])
        XCTAssertEqual(configuration.regexes, ["^user-[0-9]+$"])
        XCTAssertEqual(configuration.jsonStrings, ["{\"enabled\":true}"])
        XCTAssertEqual(configuration.versions.map(\.components), [["1", "2", "3"]])
        XCTAssertEqual(configuration.versions.map(\.prerelease), [["beta", "1"]])
        XCTAssertEqual(Set(configuration.flags.keys), ["all-variations", "unknown-enums"])
    }

    func testDecodesAttributeReferences() throws {
        let attributes = try RulesConfigurationDecoder.decode(allFieldsFixture).attributes
        XCTAssertEqual(attributes.count, 2)

        guard case .targetingKey = attributes[0].kind else {
            return XCTFail("Expected the targeting key, got \(String(describing: attributes[0].kind))")
        }
        guard case .attributePath(let path) = attributes[1].kind else {
            return XCTFail("Expected an attribute path, got \(String(describing: attributes[1].kind))")
        }
        XCTAssertEqual(path.segments.map(\.kind), [.objectKeyStringIndex(2), .arrayIndex(0)])
    }

    func testDecodesEveryConditionKind() throws {
        let conditions = try RulesConfigurationDecoder.decode(allFieldsFixture).conditions
        XCTAssertEqual(conditions.count, 11)

        guard case .all(let all) = conditions[0].kind else {
            return XCTFail("Expected all")
        }
        XCTAssertEqual(all.conditionIndexes, [1, 2])
        guard case .any(let any) = conditions[1].kind else {
            return XCTFail("Expected any")
        }
        XCTAssertEqual(any.conditionIndexes, [3])
        guard case .numeric(let numeric) = conditions[2].kind else {
            return XCTFail("Expected numeric")
        }
        XCTAssertEqual(numeric.attributeIndex, 1)
        XCTAssertEqual(numeric.comparator, .greaterThanOrEqual)
        XCTAssertEqual(numeric.comparand, 2.5)
        guard case .regex(let regex) = conditions[3].kind else {
            return XCTFail("Expected regex")
        }
        XCTAssertEqual(regex.regexIndex, 0)
        XCTAssertTrue(regex.negate)
        guard case .stringMembership(let membership) = conditions[4].kind else {
            return XCTFail("Expected string membership")
        }
        XCTAssertEqual(membership.stringIndexes, [3, 5])
        XCTAssertFalse(membership.negate)
        guard case .sha256Membership(let sha256Membership) = conditions[5].kind else {
            return XCTFail("Expected SHA-256 membership")
        }
        XCTAssertEqual(sha256Membership.salt, Data("salt".utf8))
        XCTAssertEqual(sha256Membership.sha256, [Data([0x01, 0x02, 0x03]), Data([0xFF])])
        XCTAssertTrue(sha256Membership.negate)
        guard case .attributePresence(let presence) = conditions[6].kind else {
            return XCTFail("Expected attribute presence")
        }
        XCTAssertTrue(presence.expectNull)
        guard case .version(let version) = conditions[7].kind else {
            return XCTFail("Expected version")
        }
        XCTAssertEqual(version.comparator, .lessThan)
        XCTAssertEqual(version.versionIndex, 0)
        guard case .stringComparison(let comparison) = conditions[8].kind else {
            return XCTFail("Expected string comparison")
        }
        XCTAssertEqual(comparison.comparator, .endsWith)
        XCTAssertEqual(comparison.stringIndex, 4)
        XCTAssertTrue(comparison.negate)
        guard case .sha256StringComparison(let sha256Comparison) = conditions[9].kind else {
            return XCTFail("Expected SHA-256 comparison")
        }
        XCTAssertEqual(sha256Comparison.salt, Data("s".utf8))
        XCTAssertEqual(sha256Comparison.comparator, .startsWith)
        XCTAssertEqual(sha256Comparison.length, 4)
        XCTAssertEqual(sha256Comparison.sha256, Data([0xAA, 0xBB]))
        guard case .flagEvaluationStringMembership(let dependency) = conditions[10].kind else {
            return XCTFail("Expected flag evaluation membership")
        }
        XCTAssertEqual(dependency.flagKeyStringIndex, 0)
        XCTAssertEqual(dependency.variantKeyStringIndexes, [0, 1])
        XCTAssertTrue(dependency.negate)
    }

    func testDecodesEveryVariationValue() throws {
        let flag = try XCTUnwrap(RulesConfigurationDecoder.decode(allFieldsFixture).flags["all-variations"])

        XCTAssertEqual(flag.minimumFeatureLevel, 2)
        XCTAssertEqual(flag.variationType, .json)
        XCTAssertEqual(flag.variations.map(\.keyStringIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(
            flag.variations.map(\.value),
            [.stringValueIndex(1), .integerValue(-9_007_199_254_740_993), .numericValue(-0.125), .booleanValue(true), .jsonStringIndex(0)]
        )
    }

    func testDecodesAllocationsAndSplits() throws {
        let flag = try XCTUnwrap(RulesConfigurationDecoder.decode(allFieldsFixture).flags["all-variations"])
        XCTAssertEqual(flag.allocations.map(\.key), ["targeted", "fallback"])

        let allocation = flag.allocations[0]
        XCTAssertEqual(allocation.targetingConditionIndex, 0)
        XCTAssertTrue(allocation.logExposureEvent)
        XCTAssertEqual(allocation.randomizationActivatedAt?.seconds, 1_780_000_000)
        XCTAssertEqual(allocation.randomizationActivatedAt?.nanos, 999)
        XCTAssertEqual(allocation.partitionKey.count, 2)
        guard case .time = allocation.partitionKey[0].kind else {
            return XCTFail("Expected a time partition key")
        }
        guard case .shardMD5(let shard) = allocation.partitionKey[1].kind else {
            return XCTFail("Expected an MD5 shard partition key")
        }
        XCTAssertEqual(shard.salt, "salt")
        XCTAssertEqual(shard.attributeIndex, 0)
        XCTAssertEqual(shard.totalShards, 10_000)

        let split = try XCTUnwrap(allocation.splits.first)
        XCTAssertEqual(split.ranges.map(\.from), [0, nil])
        XCTAssertEqual(split.ranges.map(\.to), [5_000, 10_000])
        XCTAssertEqual(split.variationIndex, 4)
        XCTAssertEqual(split.serialID, -3)
        XCTAssertEqual(split.reason, .targetingMatch)
        XCTAssertEqual(split.features.map(\.key), ["team", "weight", "beta"])
        XCTAssertEqual(split.features.map(\.value), [.stringValue("growth"), .numberValue(0.5), .boolValue(true)])
        XCTAssertEqual(split.features[0].destinations, ["rum", "exposures"])

        let fallback = flag.allocations[1]
        XCTAssertNil(fallback.targetingConditionIndex)
        XCTAssertNil(fallback.randomizationActivatedAt)
        XCTAssertNil(fallback.splits.first?.serialID)
        XCTAssertEqual(fallback.splits.first?.reason, .static)
    }

    func testKeepsUnknownEnumValues() throws {
        let flag = try XCTUnwrap(RulesConfigurationDecoder.decode(allFieldsFixture).flags["unknown-enums"])

        XCTAssertEqual(flag.variationType, .unrecognized(42))
        XCTAssertEqual(flag.allocations.first?.splits.first?.reason, .unrecognized(77))
    }

    func testSkipsUnknownFieldsOfEveryWireType() throws {
        var bytes = [UInt8](browserFixture)
        bytes += [0xC0, 0x3E, 0x01] // field 1000, varint
        bytes += [0xC9, 0x3E] + [UInt8](repeating: 7, count: 8) // field 1001, fixed64
        bytes += [0xD2, 0x3E, 0x03, 0x01, 0x02, 0x03] // field 1002, 3 bytes
        bytes += [0xDD, 0x3E] + [UInt8](repeating: 9, count: 4) // field 1003, fixed32

        let configuration = try RulesConfigurationDecoder.decode(Data(bytes))

        XCTAssertEqual(configuration.environmentName, "prod")
        XCTAssertEqual(Array(configuration.flags.keys), ["test-flag"])
        XCTAssertEqual(configuration.strings, ["on", "off", "US", "country"])
    }

    func testDecodesEmptyDataAsEmptyConfiguration() throws {
        let configuration = try RulesConfigurationDecoder.decode(Data())

        XCTAssertTrue(configuration.flags.isEmpty)
    }

    func testThrowsForTruncatedData() {
        // Field 1 declares 5 bytes, but only 1 byte follows.
        let truncated = Data([0x0A, 0x05, 0x01])

        XCTAssertThrowsError(try RulesConfigurationDecoder.decode(truncated)) { error in
            XCTAssertEqual(error as? RulesConfigurationDecodingError, .invalidData)
        }
    }

    func testCorruptedDataNeverCrashes() {
        // Deterministic random corruption: each result must be a configuration or an error, never a crash or a hang.
        var state: UInt64 = 42
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let fixtures = [[UInt8](allFieldsFixture), [UInt8](browserFixture)]
        var decoded = 0
        var rejected = 0

        for round in 0..<3_000 {
            var bytes = fixtures[round % fixtures.count]
            for _ in 0..<(1 + Int(next() % 3)) {
                bytes[Int(next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: next())
            }
            if next() % 5 == 0 {
                bytes.removeLast(1 + Int(next() % 10))
            }
            if (try? RulesConfigurationDecoder.decode(Data(bytes))) != nil {
                decoded += 1
            } else {
                rejected += 1
            }
        }

        XCTAssertEqual(decoded + rejected, 3_000)
        XCTAssertGreaterThan(rejected, 0)
    }
}
