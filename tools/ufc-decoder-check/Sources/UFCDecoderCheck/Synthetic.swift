/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftProtobuf

typealias PBConfig = Datadog_Ffe_Flagging_Ufc_V1_FlagsConfiguration

/// Deterministic random numbers, so every run builds the same configurations.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func double() -> Double { Double(next() % 1_000_000) / 997.0 - 300 }
    mutating func bytes(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8(truncatingIfNeeded: next()) }) }
}

/// Builds a rules-based configuration that uses every message, field, oneof case and enum of the schema.
func makeConfiguration(flags flagCount: Int, seed: UInt64) -> PBConfig {
    typealias V1 = Datadog_Ffe_Flagging_Ufc_V1_FlagsConfiguration
    var rng = SplitMix64(state: seed)
    var config = V1()
    config.createdAt = .init(seconds: Int64(1_790_000_000 + rng.int(0...1_000_000)), nanos: Int32(rng.int(0...999_999_999)))
    config.environmentName = "prod-\(seed)"
    config.environmentID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!.uuidString
    config.observeFullEvaluationData = rng.bool()
    if rng.bool() {
        var params = Datadog_Ffe_Flagging_Ufc_V1_EvaluatorParams()
        params.maxDependencyDepth = UInt64(rng.int(0...10))
        config.evaluatorParams = params
    } else {
        config.evaluatorParams = Datadog_Ffe_Flagging_Ufc_V1_EvaluatorParams()
    }
    config.strings = (0..<max(200, flagCount * 2)).map { i in i % 17 == 0 ? "ünïcödé-\(i)-旗" : "string-value-\(i)" }
    config.regexes = (0..<50).map { "^user-\($0)-[a-z]+$" }
    config.jsonStrings = (0..<50).map { "{\"key\":\($0),\"nested\":{\"enabled\":true}}" }
    config.versions = (0..<50).map { i in
        var version = Datadog_Ffe_Flagging_Ufc_V1_Version()
        version.components = ["\(i % 5)", "\(i % 7)", "\(i)"]
        if i % 3 == 0 { version.prerelease = ["beta", "\(i)"] }
        return version
    }
    config.attributes = (0..<100).map { i in
        var reference = Datadog_Ffe_Flagging_Ufc_V1_AttributeReference()
        if i % 10 == 0 {
            reference.targetingKey = SwiftProtobuf.Google_Protobuf_Empty()
        } else {
            var path = Datadog_Ffe_Flagging_Ufc_V1_AttributePath()
            path.segments = (0..<rng.int(1...3)).map { s in
                var segment = Datadog_Ffe_Flagging_Ufc_V1_AttributePathSegment()
                if s % 2 == 0 { segment.objectKeyStringIndex = UInt32(rng.int(0...199)) } else { segment.arrayIndex = UInt32(rng.int(0...5)) }
                return segment
            }
            reference.attributePath = path
        }
        return reference
    }
    config.conditions = (0..<max(100, flagCount)).map { i in
        var condition = Datadog_Ffe_Flagging_Ufc_V1_Condition()
        let attribute = UInt32(rng.int(0...99))
        switch i % 11 {
        case 0:
            var operands = Datadog_Ffe_Flagging_Ufc_V1_ConditionOperands()
            operands.conditionIndexes = (0..<rng.int(1...4)).map { _ in UInt32(rng.int(0...99)) }
            condition.all = operands
        case 1:
            var operands = Datadog_Ffe_Flagging_Ufc_V1_ConditionOperands()
            operands.conditionIndexes = (0..<rng.int(1...4)).map { _ in UInt32(rng.int(0...99)) }
            condition.any = operands
        case 2:
            var numeric = Datadog_Ffe_Flagging_Ufc_V1_NumericCondition()
            numeric.attributeIndex = attribute
            numeric.comparator = Datadog_Ffe_Flagging_Ufc_V1_NumericComparator(rawValue: rng.int(0...4))!
            numeric.comparand = rng.double()
            condition.numeric = numeric
        case 3:
            var regex = Datadog_Ffe_Flagging_Ufc_V1_RegexCondition()
            regex.attributeIndex = attribute
            regex.regexIndex = UInt32(rng.int(0...49))
            regex.negate = rng.bool()
            condition.regex = regex
        case 4:
            var membership = Datadog_Ffe_Flagging_Ufc_V1_StringMembershipCondition()
            membership.attributeIndex = attribute
            membership.stringIndexes = (0..<rng.int(1...20)).map { _ in UInt32(rng.int(0...199)) }
            membership.negate = rng.bool()
            condition.stringMembership = membership
        case 5:
            var membership = Datadog_Ffe_Flagging_Ufc_V1_Sha256MembershipCondition()
            membership.attributeIndex = attribute
            membership.salt = rng.bytes(16)
            membership.sha256 = (0..<rng.int(1...5)).map { _ in rng.bytes(32) }
            membership.negate = rng.bool()
            condition.sha256Membership = membership
        case 6:
            var presence = Datadog_Ffe_Flagging_Ufc_V1_AttributePresenceCondition()
            presence.attributeIndex = attribute
            presence.expectNull = rng.bool()
            condition.attributePresence = presence
        case 7:
            var version = Datadog_Ffe_Flagging_Ufc_V1_VersionCondition()
            version.attributeIndex = attribute
            version.comparator = Datadog_Ffe_Flagging_Ufc_V1_VersionComparator(rawValue: rng.int(0...6))!
            version.versionIndex = UInt32(rng.int(0...49))
            condition.version = version
        case 8:
            var comparison = Datadog_Ffe_Flagging_Ufc_V1_StringComparisonCondition()
            comparison.attributeIndex = attribute
            comparison.comparator = Datadog_Ffe_Flagging_Ufc_V1_StringComparator(rawValue: rng.int(0...3))!
            comparison.stringIndex = UInt32(rng.int(0...199))
            comparison.negate = rng.bool()
            condition.stringComparison = comparison
        case 9:
            var comparison = Datadog_Ffe_Flagging_Ufc_V1_Sha256StringComparisonCondition()
            comparison.attributeIndex = attribute
            comparison.salt = rng.bytes(16)
            comparison.comparator = Datadog_Ffe_Flagging_Ufc_V1_Sha256StringComparator(rawValue: rng.int(0...2))!
            comparison.length = UInt32(rng.int(1...8))
            comparison.sha256 = rng.bytes(32)
            comparison.negate = rng.bool()
            condition.sha256StringComparison = comparison
        default:
            var dependency = Datadog_Ffe_Flagging_Ufc_V1_FlagEvaluationStringMembershipCondition()
            dependency.flagKeyStringIndex = UInt32(rng.int(0...199))
            dependency.variantKeyStringIndexes = (0..<rng.int(1...3)).map { _ in UInt32(rng.int(0...199)) }
            dependency.negate = rng.bool()
            condition.flagEvaluationStringMembership = dependency
        }
        return condition
    }
    for i in 0..<flagCount {
        var flag = Datadog_Ffe_Flagging_Ufc_V1_Flag()
        flag.minimumFeatureLevel = UInt32(rng.int(0...3))
        flag.variationType = Datadog_Ffe_Flagging_Ufc_V1_VariationType(rawValue: rng.int(1...5))!
        flag.variations = (0..<rng.int(2...4)).map { v in
            var variation = Datadog_Ffe_Flagging_Ufc_V1_Variation()
            variation.keyStringIndex = UInt32(rng.int(0...199))
            switch (i + v) % 5 {
            case 0: variation.stringValueIndex = UInt32(rng.int(0...199))
            case 1: variation.integerValue = Int64(rng.int(-1_000_000...1_000_000)) * (v % 2 == 0 ? 1 : -9_000_000)
            case 2: variation.numericValue = rng.double()
            case 3: variation.booleanValue = rng.bool()
            default: variation.jsonStringIndex = UInt32(rng.int(0...49))
            }
            return variation
        }
        flag.allocations = (0..<rng.int(1...4)).map { a in
            var allocation = Datadog_Ffe_Flagging_Ufc_V1_Allocation()
            allocation.key = "allocation-\(i)-\(a)"
            if rng.bool() { allocation.targetingConditionIndex = UInt32(rng.int(0...99)) }
            allocation.partitionKey = (0..<rng.int(0...2)).map { p in
                var key = Datadog_Ffe_Flagging_Ufc_V1_PartitionKey()
                if p == 0 && rng.bool() {
                    key.time = Datadog_Ffe_Flagging_Ufc_V1_TimePartitionKey()
                } else {
                    var shard = Datadog_Ffe_Flagging_Ufc_V1_Md5ShardPartitionKey()
                    shard.salt = "salt-\(i)-\(a)"
                    shard.attributeIndex = UInt32(rng.int(0...99))
                    shard.totalShards = UInt64(rng.int(1...10_000))
                    key.shardMd5 = shard
                }
                return key
            }
            allocation.splits = (0..<rng.int(1...3)).map { s in
                var split = Datadog_Ffe_Flagging_Ufc_V1_Split()
                split.ranges = (0..<rng.int(1...2)).map { _ in
                    var range = Datadog_Ffe_Flagging_Ufc_V1_PartitionRange()
                    if rng.bool() { range.from = UInt64(rng.int(0...5_000)) }
                    if rng.bool() { range.to = UInt64(rng.int(5_000...10_000)) }
                    return range
                }
                split.variationIndex = UInt32(rng.int(0...3))
                if rng.bool() { split.serialID = Int32(rng.int(-5...1_000)) }
                split.reason = Datadog_Ffe_Flagging_Ufc_V1_Reason(rawValue: rng.int(0...4))!
                split.features = (0..<rng.int(0...2)).map { f in
                    var feature = Datadog_Ffe_Flagging_Ufc_V1_Feature()
                    feature.key = "feature-\(s)-\(f)"
                    switch f % 3 {
                    case 0: feature.stringValue = "value-\(i)"
                    case 1: feature.numberValue = rng.double()
                    default: feature.boolValue = rng.bool()
                    }
                    feature.destinations = rng.bool() ? ["rum", "exposures"] : []
                    return feature
                }
                return split
            }
            allocation.logExposureEvent = rng.bool()
            if rng.bool() { allocation.randomizationActivatedAt = .init(seconds: Int64(1_780_000_000 + a), nanos: Int32(rng.int(0...999))) }
            return allocation
        }
        config.flags["flag-key-\(i)"] = flag
    }
    return config
}
