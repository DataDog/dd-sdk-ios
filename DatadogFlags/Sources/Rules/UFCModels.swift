/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// Decode-only Swift types for `DatadogFlags/Protos/ufc.proto`. Each `decode` maps the schema's field numbers.

internal struct UFCFlagsConfiguration: UFCMessage {
    var createdAt: UFCTimestamp?
    var environmentName = ""
    var flags: [String: UFCFlag] = [:]
    var attributes: [UFCAttributeReference] = []
    var strings: [String] = []
    var regexes: [String] = []
    var versions: [UFCVersion] = []
    var jsonStrings: [String] = []
    var conditions: [UFCCondition] = []
    var observeFullEvaluationData = false
    var evaluatorParams: UFCEvaluatorParams?
    var environmentID = ""

    init() {}
    /// Decodes the protobuf body of the client rules endpoint.
    init(serializedData data: Data) throws { self = try data.withUnsafeBytes { try Self($0) } }

    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: createdAt = try reader.message(field)
        case 2: environmentName = try reader.string(field)
        case 3:
            let entry: UFCFlagEntry = try reader.message(field)
            flags[entry.key] = entry.value
        case 4: attributes.append(try reader.message(field))
        case 5: strings.append(try reader.string(field))
        case 6: regexes.append(try reader.string(field))
        case 7: versions.append(try reader.message(field))
        case 8: jsonStrings.append(try reader.string(field))
        case 9: conditions.append(try reader.message(field))
        case 10: observeFullEvaluationData = try reader.bool(field)
        case 11: evaluatorParams = try reader.message(field)
        case 12: environmentID = try reader.string(field)
        default: try reader.skip(field)
        }
    }
}

/// One `map<string, Flag>` entry. A missing key is `""` and a missing value is an empty flag.
internal struct UFCFlagEntry: UFCMessage {
    var key = "", value = UFCFlag()
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: key = try reader.string(field)
        case 2: value = try reader.message(field)
        default: try reader.skip(field)
        }
    }
}

/// `google.protobuf.Timestamp`.
internal struct UFCTimestamp: UFCMessage {
    var seconds: Int64 = 0, nanos: Int32 = 0
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: seconds = try reader.int64(field)
        case 2: nanos = try reader.int32(field)
        default: try reader.skip(field)
        }
    }
}

/// `google.protobuf.Empty` and `TimePartitionKey`. They have no fields, but their bytes must be well-formed.
internal struct UFCEmpty: UFCMessage {
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws { try reader.skip(field) }
}

internal struct UFCEvaluatorParams: UFCMessage {
    var maxDependencyDepth: UInt64?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: maxDependencyDepth = try reader.uint64(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCVersion: UFCMessage {
    var components: [String] = [], prerelease: [String] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: components.append(try reader.string(field))
        case 2: prerelease.append(try reader.string(field))
        default: try reader.skip(field)
        }
    }
}

// MARK: - Flags

internal struct UFCFlag: UFCMessage {
    var minimumFeatureLevel: UInt32 = 0, variationType: UFCVariationType = .unspecified
    var variations: [UFCVariation] = [], allocations: [UFCAllocation] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: minimumFeatureLevel = try reader.uint32(field)
        case 2: variationType = try reader.enumeration(field)
        case 3: variations.append(try reader.message(field))
        case 4: allocations.append(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCVariation: UFCMessage {
    enum Value: Equatable {
        case stringValueIndex(UInt32), integerValue(Int64), numericValue(Double), booleanValue(Bool), jsonStringIndex(UInt32)
    }
    var keyStringIndex: UInt32 = 0, value: Value?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: keyStringIndex = try reader.uint32(field)
        case 2: value = .stringValueIndex(try reader.uint32(field))
        case 3: value = .integerValue(try reader.int64(field))
        case 4: value = .numericValue(try reader.double(field))
        case 5: value = .booleanValue(try reader.bool(field))
        case 6: value = .jsonStringIndex(try reader.uint32(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCAllocation: UFCMessage {
    var key = "", targetingConditionIndex: UInt32?, partitionKey: [UFCPartitionKey] = [], splits: [UFCSplit] = []
    var logExposureEvent = false, randomizationActivatedAt: UFCTimestamp?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: key = try reader.string(field)
        case 2: targetingConditionIndex = try reader.uint32(field)
        case 3: partitionKey.append(try reader.message(field))
        case 4: splits.append(try reader.message(field))
        case 5: logExposureEvent = try reader.bool(field)
        case 6: randomizationActivatedAt = try reader.message(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCPartitionKey: UFCMessage {
    enum Kind { case time, shardMD5(UFCMD5ShardPartitionKey) }
    var kind: Kind?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1:
            _ = try reader.message(field) as UFCEmpty
            kind = .time
        case 2: kind = .shardMD5(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCMD5ShardPartitionKey: UFCMessage {
    var salt = "", attributeIndex: UInt32 = 0, totalShards: UInt64 = 0
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: salt = try reader.string(field)
        case 2: attributeIndex = try reader.uint32(field)
        case 3: totalShards = try reader.uint64(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCSplit: UFCMessage {
    var ranges: [UFCPartitionRange] = [], variationIndex: UInt32 = 0, serialID: Int32?
    var reason: UFCReason = .unspecified, features: [UFCFeature] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: ranges.append(try reader.message(field))
        case 2: variationIndex = try reader.uint32(field)
        case 3: serialID = try reader.int32(field)
        case 4: reason = try reader.enumeration(field)
        case 5: features.append(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCPartitionRange: UFCMessage {
    var from: UInt64?, to: UInt64?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: from = try reader.uint64(field)
        case 2: to = try reader.uint64(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCFeature: UFCMessage {
    enum Value: Equatable { case stringValue(String), numberValue(Double), boolValue(Bool) }
    var key = "", value: Value?, destinations: [String] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: key = try reader.string(field)
        case 2: value = .stringValue(try reader.string(field))
        case 3: value = .numberValue(try reader.double(field))
        case 4: value = .boolValue(try reader.bool(field))
        case 5: destinations.append(try reader.string(field))
        default: try reader.skip(field)
        }
    }
}

// MARK: - Attributes

internal struct UFCAttributeReference: UFCMessage {
    enum Kind { case targetingKey, attributePath(UFCAttributePath) }
    var kind: Kind?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1:
            _ = try reader.message(field) as UFCEmpty
            kind = .targetingKey
        case 2: kind = .attributePath(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCAttributePath: UFCMessage {
    var segments: [UFCAttributePathSegment] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: segments.append(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCAttributePathSegment: UFCMessage {
    enum Kind: Equatable { case objectKeyStringIndex(UInt32), arrayIndex(UInt32) }
    var kind: Kind?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: kind = .objectKeyStringIndex(try reader.uint32(field))
        case 2: kind = .arrayIndex(try reader.uint32(field))
        default: try reader.skip(field)
        }
    }
}

// MARK: - Conditions

internal struct UFCCondition: UFCMessage {
    enum Kind {
        case all(UFCConditionOperands), any(UFCConditionOperands), numeric(UFCNumericCondition), regex(UFCRegexCondition)
        case stringMembership(UFCStringMembershipCondition), sha256Membership(UFCSHA256MembershipCondition)
        case attributePresence(UFCAttributePresenceCondition), version(UFCVersionCondition)
        case stringComparison(UFCStringComparisonCondition), sha256StringComparison(UFCSHA256StringComparisonCondition)
        case flagEvaluationStringMembership(UFCFlagEvaluationStringMembershipCondition)
    }
    var kind: Kind?
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: kind = .all(try reader.message(field))
        case 2: kind = .any(try reader.message(field))
        case 3: kind = .numeric(try reader.message(field))
        case 4: kind = .regex(try reader.message(field))
        case 5: kind = .stringMembership(try reader.message(field))
        case 6: kind = .sha256Membership(try reader.message(field))
        case 7: kind = .attributePresence(try reader.message(field))
        case 8: kind = .version(try reader.message(field))
        case 9: kind = .stringComparison(try reader.message(field))
        case 10: kind = .sha256StringComparison(try reader.message(field))
        case 11: kind = .flagEvaluationStringMembership(try reader.message(field))
        default: try reader.skip(field)
        }
    }
}

internal struct UFCConditionOperands: UFCMessage {
    var conditionIndexes: [UInt32] = []
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: try reader.appendUInt32(field, to: &conditionIndexes)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCFlagEvaluationStringMembershipCondition: UFCMessage {
    var flagKeyStringIndex: UInt32 = 0, variantKeyStringIndexes: [UInt32] = [], negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: flagKeyStringIndex = try reader.uint32(field)
        case 2: try reader.appendUInt32(field, to: &variantKeyStringIndexes)
        case 3: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCNumericCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, comparator: UFCNumericComparator = .unspecified, comparand: Double = 0
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: comparator = try reader.enumeration(field)
        case 3: comparand = try reader.double(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCRegexCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, regexIndex: UInt32 = 0, negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: regexIndex = try reader.uint32(field)
        case 3: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCStringMembershipCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, stringIndexes: [UInt32] = [], negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: try reader.appendUInt32(field, to: &stringIndexes)
        case 3: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCStringComparisonCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, comparator: UFCStringComparator = .unspecified, stringIndex: UInt32 = 0, negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: comparator = try reader.enumeration(field)
        case 3: stringIndex = try reader.uint32(field)
        case 4: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCSHA256StringComparisonCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, salt = Data(), comparator: UFCSHA256StringComparator = .unspecified
    var length: UInt32 = 0, sha256 = Data(), negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: salt = try reader.data(field)
        case 3: comparator = try reader.enumeration(field)
        case 4: length = try reader.uint32(field)
        case 5: sha256 = try reader.data(field)
        case 6: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCSHA256MembershipCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, salt = Data(), sha256: [Data] = [], negate = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: salt = try reader.data(field)
        case 3: sha256.append(try reader.data(field))
        case 4: negate = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCAttributePresenceCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, expectNull = false
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: expectNull = try reader.bool(field)
        default: try reader.skip(field)
        }
    }
}

internal struct UFCVersionCondition: UFCMessage {
    var attributeIndex: UInt32 = 0, comparator: UFCVersionComparator = .unspecified, versionIndex: UInt32 = 0
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws {
        switch field.number {
        case 1: attributeIndex = try reader.uint32(field)
        case 2: comparator = try reader.enumeration(field)
        case 3: versionIndex = try reader.uint32(field)
        default: try reader.skip(field)
        }
    }
}

// MARK: - Enums
// Protobuf enums are open, so each enum is a struct (with a memberwise `init(rawValue:)`): unknown values are kept.

internal struct UFCVariationType: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), string = Self(rawValue: 1), integer = Self(rawValue: 2), numeric = Self(rawValue: 3), boolean = Self(rawValue: 4), json = Self(rawValue: 5)
}

internal struct UFCNumericComparator: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), lessThan = Self(rawValue: 1), lessThanOrEqual = Self(rawValue: 2), greaterThan = Self(rawValue: 3), greaterThanOrEqual = Self(rawValue: 4)
}

internal struct UFCStringComparator: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), startsWith = Self(rawValue: 1), endsWith = Self(rawValue: 2), contains = Self(rawValue: 3)
}

internal struct UFCSHA256StringComparator: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), startsWith = Self(rawValue: 1), endsWith = Self(rawValue: 2)
}

internal struct UFCVersionComparator: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), equal = Self(rawValue: 1), notEqual = Self(rawValue: 2), lessThan = Self(rawValue: 3), lessThanOrEqual = Self(rawValue: 4), greaterThan = Self(rawValue: 5), greaterThanOrEqual = Self(rawValue: 6)
}

internal struct UFCReason: UFCEnum {
    let rawValue: Int32
    static let unspecified = Self(rawValue: 0), targetingMatch = Self(rawValue: 1), split = Self(rawValue: 2), `static` = Self(rawValue: 3), `default` = Self(rawValue: 4)
}
