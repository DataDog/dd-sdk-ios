/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogFlags

final class RulesConfigurationDecoderTests: XCTestCase {
    /// The rules response from the browser SDK fixture `rules-v1-wire.json`, so both SDKs decode the same bytes.
    private let browserFixture = Data(base64Encoded: "CgQIABAAEgRwcm9kGm0KCXRlc3QtZmxhZxJgCAAQBBoECAAoASIsCgphbGxvY2F0aW9uEAAaDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByABKAEiJgoIZmFsbGJhY2saDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByACIgYSBAoCCAMiAgoAKgJvbioDb2ZmKgJVUyoHY291bnRyeTIEXlVTJDoJCgExCgEyCgEzSgYqBAgAEAJQAA==")!
    /// `DatadogFlags/Protos/fixtures/all-fields.txtpb`, encoded by `protoc`. It uses every message, oneof case and enum.
    private let allFieldsFixture = Data(base64Encoded: "CggIgPfE1QYQexIHc3RhZ2luZxraAQoOYWxsLXZhcmlhdGlvbnMSxwEIAhAFGgIQARoNCAEY/////////+//ARoLCAIhAAAAAAAAwL8aBAgDKAEaBAgEMAAihAEKCHRhcmdldGVkEAAaAgoAGgsSCQoEc2FsdBiQTiJYCgUIABCIJwoDEJBOEAQY/f//////////ASABKh4KBHRlYW0SBmdyb3d0aCoDcnVtKglleHBvc3VyZXMqEQoGd2VpZ2h0GQAAAAAAAOA/KggKBGJldGEgASgBMgkIgMri0AYQ5wciDgoIZmFsbGJhY2siAiADGhwKDXVua25vd24tZW51bXMSCxAqIgcKAWEiAiBNIgIKACIKEggKAggCCgIQACoCb24qA29mZioHY291bnRyeSoCVVMqBHBsYW4qD8O8bsOvY8O2ZMOpLeaXlzINXnVzZXItWzAtOV0rJDoSCgExCgEyCgEzEgRiZXRhEgExQhB7ImVuYWJsZWQiOnRydWV9SgYKBAoCAQJKBRIDCgEDSg8aDQgBEAQZAAAAAAAABEBKBCICGAFKCCoGCAESAgMFShIyEBIEc2FsdBoDAQIDGgH/IAFKBjoECAEQAUoGQgQIARADSgpKCAgBEAIYBCABSg1SCxIBcxgBIAQqAqq7SghaBhICAAEYAVABWgIICGIkNmY5NjE5ZmYtOGI4Ni1kMDExLWI0MmQtMDBjMDRmYzk2NGZm")!

    func testDecodesBrowserFixture() throws {
        let configuration = try RulesConfigurationDecoder.decode(browserFixture)
        XCTAssertEqual(configuration.environmentName, "prod")
        XCTAssertEqual(configuration.strings, ["on", "off", "US", "country"])
        XCTAssertEqual(configuration.regexes, ["^US$"])
        let flag = try XCTUnwrap(configuration.flags["test-flag"])
        XCTAssertEqual(flag.variationType, .boolean)
        XCTAssertEqual(flag.allocations.map(\.key), ["allocation", "fallback"])
        XCTAssertEqual(flag.allocations.map(\.logExposureEvent), [true, false])
        XCTAssertEqual(flag.allocations.flatMap(\.splits).map(\.serialID), [7, 7])
        XCTAssertEqual(flag.allocations.flatMap(\.splits).map(\.reason), [.targetingMatch, .split])
    }

    func testDecodesTopLevelFieldsAndAttributeReferences() throws {
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

        let attributes = configuration.attributes.map(\.kind)
        guard attributes.count == 2, case .targetingKey = attributes[0], case .attributePath(let path) = attributes[1] else {
            return XCTFail("Unexpected attributes: \(attributes)")
        }
        XCTAssertEqual(path.segments.map(\.kind), [.objectKeyStringIndex(2), .arrayIndex(0)])
    }

    func testDecodesEveryConditionKind() throws {
        let conditions = try RulesConfigurationDecoder.decode(allFieldsFixture).conditions.map(\.kind)
        guard conditions.count == 11, case .all(let all) = conditions[0], case .any(let any) = conditions[1],
              case .numeric(let numeric) = conditions[2], case .regex(let regex) = conditions[3], case .stringMembership(let membership) = conditions[4],
              case .sha256Membership(let sha256Membership) = conditions[5], case .attributePresence(let presence) = conditions[6], case .version(let version) = conditions[7],
              case .stringComparison(let comparison) = conditions[8], case .sha256StringComparison(let sha256Comparison) = conditions[9],
              case .flagEvaluationStringMembership(let dependency) = conditions[10] else {
            return XCTFail("Unexpected conditions: \(conditions)")
        }
        XCTAssertEqual(all.conditionIndexes, [1, 2])
        XCTAssertEqual(any.conditionIndexes, [3])
        XCTAssertEqual(numeric.comparator, .greaterThanOrEqual)
        XCTAssertEqual(numeric.comparand, 2.5)
        XCTAssertEqual(regex.regexIndex, 0)
        XCTAssertEqual(membership.stringIndexes, [3, 5])
        XCTAssertEqual(sha256Membership.salt, Data("salt".utf8))
        XCTAssertEqual(sha256Membership.sha256, [Data([0x01, 0x02, 0x03]), Data([0xFF])])
        XCTAssertTrue(presence.expectNull)
        XCTAssertEqual(version.comparator, .lessThan)
        XCTAssertEqual(version.versionIndex, 0)
        XCTAssertEqual(comparison.comparator, .endsWith)
        XCTAssertEqual(comparison.stringIndex, 4)
        XCTAssertEqual(sha256Comparison.salt, Data("s".utf8))
        XCTAssertEqual(sha256Comparison.comparator, .startsWith)
        XCTAssertEqual(sha256Comparison.length, 4)
        XCTAssertEqual(sha256Comparison.sha256, Data([0xAA, 0xBB]))
        XCTAssertEqual(dependency.flagKeyStringIndex, 0)
        XCTAssertEqual(dependency.variantKeyStringIndexes, [0, 1])
        // The fields that several kinds share, in condition order.
        let attributeIndexes = [numeric.attributeIndex, regex.attributeIndex, membership.attributeIndex, sha256Membership.attributeIndex, presence.attributeIndex, version.attributeIndex, comparison.attributeIndex, sha256Comparison.attributeIndex]
        XCTAssertEqual(attributeIndexes, [1, 0, 1, 0, 1, 1, 1, 0])
        let negates = [regex.negate, membership.negate, sha256Membership.negate, comparison.negate, sha256Comparison.negate, dependency.negate]
        XCTAssertEqual(negates, [true, false, true, true, false, true])
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
        let allocations = try XCTUnwrap(RulesConfigurationDecoder.decode(allFieldsFixture).flags["all-variations"]).allocations
        XCTAssertEqual(allocations.map(\.key), ["targeted", "fallback"])
        XCTAssertEqual(allocations.map(\.targetingConditionIndex), [0, nil])
        XCTAssertEqual(allocations.map(\.logExposureEvent), [true, false])
        XCTAssertEqual(allocations.map(\.randomizationActivatedAt?.seconds), [1_780_000_000, nil])
        XCTAssertEqual(allocations.map(\.randomizationActivatedAt?.nanos), [999, nil])
        let partitionKey = allocations.first?.partitionKey.map(\.kind) ?? []
        guard partitionKey.count == 2, case .time = partitionKey[0], case .shardMD5(let shard) = partitionKey[1] else {
            return XCTFail("Unexpected partition key: \(partitionKey)")
        }
        XCTAssertEqual(shard.salt, "salt")
        XCTAssertEqual(shard.attributeIndex, 0)
        XCTAssertEqual(shard.totalShards, 10_000)
        let splits = allocations.flatMap(\.splits)
        XCTAssertEqual(splits.map(\.variationIndex), [4, 0])
        XCTAssertEqual(splits.map(\.serialID), [-3, nil])
        XCTAssertEqual(splits.map(\.reason), [.targetingMatch, .static])
        let split = try XCTUnwrap(splits.first)
        XCTAssertEqual(split.ranges.map(\.from), [0, nil])
        XCTAssertEqual(split.ranges.map(\.to), [5_000, 10_000])
        XCTAssertEqual(split.features.map(\.key), ["team", "weight", "beta"])
        XCTAssertEqual(split.features.map(\.value), [.stringValue("growth"), .numberValue(0.5), .boolValue(true)])
        XCTAssertEqual(split.features.map(\.destinations), [["rum", "exposures"], [], []])
    }

    func testKeepsUnknownEnumValues() throws {
        let flag = try XCTUnwrap(RulesConfigurationDecoder.decode(allFieldsFixture).flags["unknown-enums"])
        XCTAssertEqual(flag.variationType, UFCVariationType(rawValue: 42))
        XCTAssertEqual(flag.allocations.flatMap(\.splits).map(\.reason), [UFCReason(rawValue: 77)])
    }

    func testSkipsUnknownFieldsOfEveryWireType() throws {
        // Fields 1000 to 1003, unknown to the schema: a varint, a fixed64, 3 length-delimited bytes and a fixed32.
        let unknownFields: [UInt8] = [0xC0, 0x3E, 0x01, 0xC9, 0x3E, 1, 2, 3, 4, 5, 6, 7, 8, 0xD2, 0x3E, 0x03, 1, 2, 3, 0xDD, 0x3E, 1, 2, 3, 4]
        let configuration = try RulesConfigurationDecoder.decode(browserFixture + unknownFields)
        XCTAssertEqual(configuration.environmentName, "prod")
        XCTAssertEqual(Array(configuration.flags.keys), ["test-flag"])
        XCTAssertEqual(configuration.strings, ["on", "off", "US", "country"])
    }

    func testDecodesEmptyDataAndRejectsTruncatedData() throws {
        let empty = try RulesConfigurationDecoder.decode(Data())
        XCTAssertTrue(empty.flags.isEmpty)
        XCTAssertNil(empty.createdAt)
        // Field 1 declares 5 bytes, but only 1 byte follows.
        XCTAssertThrowsError(try RulesConfigurationDecoder.decode(Data([0x0A, 0x05, 0x01]))) { error in
            XCTAssertEqual(error as? RulesConfigurationDecodingError, .invalidData)
        }
    }

    func testCorruptedDataNeverCrashes() {
        // Deterministic random corruption: each result must be a configuration or an error, never a crash or a hang.
        var state: UInt64 = 42
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33)
        }
        var rejected = 0
        for round in 0..<3_000 {
            var bytes = [UInt8](round.isMultiple(of: 2) ? allFieldsFixture : browserFixture)
            for _ in 0...(next() % 3) {
                bytes[next() % bytes.count] = UInt8(truncatingIfNeeded: next())
            }
            if next() % 5 == 0 {
                bytes.removeLast(1 + next() % 10)
            }
            rejected += (try? RulesConfigurationDecoder.decode(Data(bytes))) == nil ? 1 : 0
        }
        XCTAssertGreaterThan(rejected, 0)
    }
}
