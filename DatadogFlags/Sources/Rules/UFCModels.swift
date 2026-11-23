/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// Decode-only Swift types for `DatadogFlags/Protos/ufc.proto`.
// Field numbers and types follow the schema. Unknown fields are skipped.

// MARK: - Root

internal struct UFCFlagsConfiguration {
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

    /// Decodes the protobuf body of the client rules endpoint.
    init(serializedData data: Data) throws {
        self = try data.withUnsafeBytes { try UFCFlagsConfiguration($0) }
    }

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: createdAt = try UFCTimestamp(reader.message(field))
                case 2: environmentName = try reader.string(field)
                case 3: try decodeFlagEntry(reader.message(field))
                case 4: attributes.append(try UFCAttributeReference(reader.message(field)))
                case 5: strings.append(try reader.string(field))
                case 6: regexes.append(try reader.string(field))
                case 7: versions.append(try UFCVersion(reader.message(field)))
                case 8: jsonStrings.append(try reader.string(field))
                case 9: conditions.append(try UFCCondition(reader.message(field)))
                case 10: observeFullEvaluationData = try reader.bool(field)
                case 11: evaluatorParams = try UFCEvaluatorParams(reader.message(field))
                case 12: environmentID = try reader.string(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }

    /// Decodes one `map<string, Flag>` entry: key is field 1, value is field 2.
    private mutating func decodeFlagEntry(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        var key = ""
        var flag = UFCFlag()
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: key = try reader.string(field)
                case 2: flag = try UFCFlag(reader.message(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
        flags[key] = flag
    }
}

internal struct UFCTimestamp {
    var seconds: Int64 = 0
    var nanos: Int32 = 0

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: seconds = try reader.int64(field)
                case 2: nanos = try reader.int32(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCEvaluatorParams {
    var maxDependencyDepth: UInt64?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: maxDependencyDepth = try reader.uint64(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCVersion {
    var components: [String] = []
    var prerelease: [String] = []

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: components.append(try reader.string(field))
                case 2: prerelease.append(try reader.string(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

// MARK: - Flags

internal struct UFCFlag {
    var minimumFeatureLevel: UInt32 = 0
    var variationType: UFCVariationType = .unspecified
    var variations: [UFCVariation] = []
    var allocations: [UFCAllocation] = []

    init() {}

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: minimumFeatureLevel = try reader.uint32(field)
                case 2: variationType = UFCVariationType(rawValue: try reader.enumValue(field))
                case 3: variations.append(try UFCVariation(reader.message(field)))
                case 4: allocations.append(try UFCAllocation(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCVariation {
    enum Value: Equatable {
        case stringValueIndex(UInt32)
        case integerValue(Int64)
        case numericValue(Double)
        case booleanValue(Bool)
        case jsonStringIndex(UInt32)
    }

    var keyStringIndex: UInt32 = 0
    var value: Value?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: keyStringIndex = try reader.uint32(field)
                case 2: value = .stringValueIndex(try reader.uint32(field))
                case 3: value = .integerValue(try reader.int64(field))
                case 4: value = .numericValue(try reader.double(field))
                case 5: value = .booleanValue(try reader.bool(field))
                case 6: value = .jsonStringIndex(try reader.uint32(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCAllocation {
    var key = ""
    var targetingConditionIndex: UInt32?
    var partitionKey: [UFCPartitionKey] = []
    var splits: [UFCSplit] = []
    var logExposureEvent = false
    var randomizationActivatedAt: UFCTimestamp?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: key = try reader.string(field)
                case 2: targetingConditionIndex = try reader.uint32(field)
                case 3: partitionKey.append(try UFCPartitionKey(reader.message(field)))
                case 4: splits.append(try UFCSplit(reader.message(field)))
                case 5: logExposureEvent = try reader.bool(field)
                case 6: randomizationActivatedAt = try UFCTimestamp(reader.message(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCPartitionKey {
    enum Kind {
        case time
        case shardMD5(UFCMD5ShardPartitionKey)
    }

    var kind: Kind?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1:
                    try UFCPartitionKey.validateEmptyMessage(reader.message(field))
                    kind = .time
                case 2: kind = .shardMD5(try UFCMD5ShardPartitionKey(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }

    /// `TimePartitionKey` has no fields. Its bytes must still be well-formed.
    static func validateEmptyMessage(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            try reader.skip(field)
        }
    }
}

internal struct UFCMD5ShardPartitionKey {
    var salt = ""
    var attributeIndex: UInt32 = 0
    var totalShards: UInt64 = 0

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: salt = try reader.string(field)
                case 2: attributeIndex = try reader.uint32(field)
                case 3: totalShards = try reader.uint64(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCSplit {
    var ranges: [UFCPartitionRange] = []
    var variationIndex: UInt32 = 0
    var serialID: Int32?
    var reason: UFCReason = .unspecified
    var features: [UFCFeature] = []

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: ranges.append(try UFCPartitionRange(reader.message(field)))
                case 2: variationIndex = try reader.uint32(field)
                case 3: serialID = try reader.int32(field)
                case 4: reason = UFCReason(rawValue: try reader.enumValue(field))
                case 5: features.append(try UFCFeature(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCPartitionRange {
    var from: UInt64?
    var to: UInt64?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: from = try reader.uint64(field)
                case 2: to = try reader.uint64(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCFeature {
    enum Value: Equatable {
        case stringValue(String)
        case numberValue(Double)
        case boolValue(Bool)
    }

    var key = ""
    var value: Value?
    var destinations: [String] = []

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: key = try reader.string(field)
                case 2: value = .stringValue(try reader.string(field))
                case 3: value = .numberValue(try reader.double(field))
                case 4: value = .boolValue(try reader.bool(field))
                case 5: destinations.append(try reader.string(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

// MARK: - Attributes

internal struct UFCAttributeReference {
    enum Kind {
        case targetingKey
        case attributePath(UFCAttributePath)
    }

    var kind: Kind?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1:
                    try UFCPartitionKey.validateEmptyMessage(reader.message(field))
                    kind = .targetingKey
                case 2: kind = .attributePath(try UFCAttributePath(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCAttributePath {
    var segments: [UFCAttributePathSegment] = []

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: segments.append(try UFCAttributePathSegment(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCAttributePathSegment {
    enum Kind: Equatable {
        case objectKeyStringIndex(UInt32)
        case arrayIndex(UInt32)
    }

    var kind: Kind?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: kind = .objectKeyStringIndex(try reader.uint32(field))
                case 2: kind = .arrayIndex(try reader.uint32(field))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

// MARK: - Conditions

internal struct UFCCondition {
    enum Kind {
        case all(UFCConditionOperands)
        case any(UFCConditionOperands)
        case numeric(UFCNumericCondition)
        case regex(UFCRegexCondition)
        case stringMembership(UFCStringMembershipCondition)
        case sha256Membership(UFCSHA256MembershipCondition)
        case attributePresence(UFCAttributePresenceCondition)
        case version(UFCVersionCondition)
        case stringComparison(UFCStringComparisonCondition)
        case sha256StringComparison(UFCSHA256StringComparisonCondition)
        case flagEvaluationStringMembership(UFCFlagEvaluationStringMembershipCondition)
    }

    var kind: Kind?

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: kind = .all(try UFCConditionOperands(reader.message(field)))
                case 2: kind = .any(try UFCConditionOperands(reader.message(field)))
                case 3: kind = .numeric(try UFCNumericCondition(reader.message(field)))
                case 4: kind = .regex(try UFCRegexCondition(reader.message(field)))
                case 5: kind = .stringMembership(try UFCStringMembershipCondition(reader.message(field)))
                case 6: kind = .sha256Membership(try UFCSHA256MembershipCondition(reader.message(field)))
                case 7: kind = .attributePresence(try UFCAttributePresenceCondition(reader.message(field)))
                case 8: kind = .version(try UFCVersionCondition(reader.message(field)))
                case 9: kind = .stringComparison(try UFCStringComparisonCondition(reader.message(field)))
                case 10: kind = .sha256StringComparison(try UFCSHA256StringComparisonCondition(reader.message(field)))
                case 11: kind = .flagEvaluationStringMembership(try UFCFlagEvaluationStringMembershipCondition(reader.message(field)))
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCConditionOperands {
    var conditionIndexes: [UInt32] = []

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: try reader.appendUInt32(field, to: &conditionIndexes)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCFlagEvaluationStringMembershipCondition {
    var flagKeyStringIndex: UInt32 = 0
    var variantKeyStringIndexes: [UInt32] = []
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: flagKeyStringIndex = try reader.uint32(field)
                case 2: try reader.appendUInt32(field, to: &variantKeyStringIndexes)
                case 3: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCNumericCondition {
    var attributeIndex: UInt32 = 0
    var comparator: UFCNumericComparator = .unspecified
    var comparand: Double = 0

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: comparator = UFCNumericComparator(rawValue: try reader.enumValue(field))
                case 3: comparand = try reader.double(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCRegexCondition {
    var attributeIndex: UInt32 = 0
    var regexIndex: UInt32 = 0
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: regexIndex = try reader.uint32(field)
                case 3: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCStringMembershipCondition {
    var attributeIndex: UInt32 = 0
    var stringIndexes: [UInt32] = []
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: try reader.appendUInt32(field, to: &stringIndexes)
                case 3: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCStringComparisonCondition {
    var attributeIndex: UInt32 = 0
    var comparator: UFCStringComparator = .unspecified
    var stringIndex: UInt32 = 0
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: comparator = UFCStringComparator(rawValue: try reader.enumValue(field))
                case 3: stringIndex = try reader.uint32(field)
                case 4: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCSHA256StringComparisonCondition {
    var attributeIndex: UInt32 = 0
    var salt = Data()
    var comparator: UFCSHA256StringComparator = .unspecified
    var length: UInt32 = 0
    var sha256 = Data()
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: salt = try reader.data(field)
                case 3: comparator = UFCSHA256StringComparator(rawValue: try reader.enumValue(field))
                case 4: length = try reader.uint32(field)
                case 5: sha256 = try reader.data(field)
                case 6: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCSHA256MembershipCondition {
    var attributeIndex: UInt32 = 0
    var salt = Data()
    var sha256: [Data] = []
    var negate = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: salt = try reader.data(field)
                case 3: sha256.append(try reader.data(field))
                case 4: negate = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCAttributePresenceCondition {
    var attributeIndex: UInt32 = 0
    var expectNull = false

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: expectNull = try reader.bool(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

internal struct UFCVersionCondition {
    var attributeIndex: UInt32 = 0
    var comparator: UFCVersionComparator = .unspecified
    var versionIndex: UInt32 = 0

    init(_ bytes: UnsafeRawBufferPointer) throws {
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                switch field.number {
                case 1: attributeIndex = try reader.uint32(field)
                case 2: comparator = UFCVersionComparator(rawValue: try reader.enumValue(field))
                case 3: versionIndex = try reader.uint32(field)
                default: try reader.skip(field)
                }
            } catch UFCDecodingError.wireTypeMismatch {
                // A known field with the wrong wire type is skipped like an unknown field, as other protobuf decoders do.
                try reader.skip(field)
            }
        }
    }
}

// MARK: - Enums

/// Protobuf enums are open: a value this schema does not know is kept as `unrecognized`.
internal enum UFCVariationType: Equatable {
    case unspecified, string, integer, numeric, boolean, json
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .string
        case 2: self = .integer
        case 3: self = .numeric
        case 4: self = .boolean
        case 5: self = .json
        default: self = .unrecognized(rawValue)
        }
    }
}

internal enum UFCNumericComparator: Equatable {
    case unspecified, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .lessThan
        case 2: self = .lessThanOrEqual
        case 3: self = .greaterThan
        case 4: self = .greaterThanOrEqual
        default: self = .unrecognized(rawValue)
        }
    }
}

internal enum UFCStringComparator: Equatable {
    case unspecified, startsWith, endsWith, contains
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .startsWith
        case 2: self = .endsWith
        case 3: self = .contains
        default: self = .unrecognized(rawValue)
        }
    }
}

internal enum UFCSHA256StringComparator: Equatable {
    case unspecified, startsWith, endsWith
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .startsWith
        case 2: self = .endsWith
        default: self = .unrecognized(rawValue)
        }
    }
}

internal enum UFCVersionComparator: Equatable {
    case unspecified, equal, notEqual, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .equal
        case 2: self = .notEqual
        case 3: self = .lessThan
        case 4: self = .lessThanOrEqual
        case 5: self = .greaterThan
        case 6: self = .greaterThanOrEqual
        default: self = .unrecognized(rawValue)
        }
    }
}

internal enum UFCReason: Equatable {
    case unspecified, targetingMatch, split, `static`, `default`
    case unrecognized(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .targetingMatch
        case 2: self = .split
        case 3: self = .static
        case 4: self = .default
        default: self = .unrecognized(rawValue)
        }
    }
}
