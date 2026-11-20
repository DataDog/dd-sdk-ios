/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import CryptoKit
import Foundation

internal typealias ClientRules = Datadog_Ffe_Flagging_Ufc_V1_FlagsConfiguration

internal enum PrototypeError: Error {
    case invalidRequest, invalidConfiguration, unsupportedWorkload, notInitialized
    case targetingKeyMissing, invalidContext
}

internal struct ProtobufRequest {
    let flagKey: String
    let defaultValue: Bool
    let context: RulesValue

    init(_ request: [String: Any]) throws {
        guard let flagKey = request["flagKey"] as? String,
              request["type"] as? String == "boolean",
              let fallback = request["defaultValue"] as? NSNumber,
              CFGetTypeID(fallback) == CFBooleanGetTypeID(),
              let context = request["context"] as? [String: Any] else {
            throw PrototypeError.invalidRequest
        }
        self.flagKey = flagKey
        self.defaultValue = fallback.boolValue
        self.context = try Self.value(context)
    }

    private static func value(_ object: Any) throws -> RulesValue {
        switch object {
        case is NSNull: return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            guard number.doubleValue.isFinite else { throw PrototypeError.invalidContext }
            return .number(number.doubleValue)
        case let text as String: return .string(text)
        case let array as [Any]: return .array(try array.map(value))
        case let dictionary as [String: Any]: return .object(try dictionary.mapValues(value))
        default: throw PrototypeError.invalidContext
        }
    }
}

/// Client-protobuf benchmark subset, not a production or fully conformant evaluator.
internal struct ProtobufRulesEvaluator {
    let configuration: ClientRules

    func evaluate(_ request: ProtobufRequest, timestamp: Double) -> [String: Any] {
        var metadata: [String: Any] = [
            "__dd_eval_timestamp_ms": timestamp,
            "__dd_observe_full_evaluation_data": configuration.observeFullEvaluationData,
        ]
        func fallback(_ reason: String, error: String? = nil) -> [String: Any] {
            var result: [String: Any] = ["value": request.defaultValue, "reason": reason, "flagMetadata": metadata]
            if let error = error { result["errorCode"] = error }
            return result
        }
        guard let flag = configuration.flags[request.flagKey] else {
            return fallback("ERROR", error: "FLAG_NOT_FOUND")
        }
        do {
            guard flag.minimumFeatureLevel == 0, flag.variationType == .boolean else {
                throw PrototypeError.unsupportedWorkload
            }
            var conditionResults: [UInt32: Bool] = [:]
            for allocation in flag.allocations {
                if allocation.hasTargetingConditionIndex,
                   try !matches(allocation.targetingConditionIndex, context: request.context, cache: &conditionResults) {
                    continue
                }
                let coordinates = try allocation.partitionKey.map { partition -> UInt64 in
                    switch partition.kind {
                    case .time:
                        guard timestamp >= 0, timestamp <= 9_007_199_254_740_991 else {
                            throw PrototypeError.invalidConfiguration
                        }
                        return UInt64(timestamp)
                    case .shardMd5(let shard):
                        guard shard.totalShards > 0, shard.totalShards <= 9_007_199_254_740_991 else {
                            throw PrototypeError.invalidConfiguration
                        }
                        let attribute = try at(configuration.attributes, shard.attributeIndex)
                        guard let value = try attributeValue(shard.attributeIndex, context: request.context) else {
                            if case .targetingKey = attribute.kind { throw PrototypeError.targetingKeyMissing }
                            throw PrototypeError.invalidContext
                        }
                        guard let string = value.stringValue else { throw PrototypeError.invalidContext }
                        // The protobuf salt already includes its separator. MD5 is the assignment protocol.
                        let digest = Insecure.MD5.hash(data: Data((shard.salt + string).utf8))
                        let prefix = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        return UInt64(prefix) % shard.totalShards
                    default: throw PrototypeError.unsupportedWorkload
                    }
                }
                for split in allocation.splits {
                    guard split.ranges.count == coordinates.count else { throw PrototypeError.invalidConfiguration }
                    let matchesRange = zip(coordinates, split.ranges).allSatisfy { coordinate, range in
                        (!range.hasFrom || coordinate >= range.from) && (!range.hasTo || coordinate < range.to)
                    }
                    guard matchesRange else { continue }
                    let variation = try at(flag.variations, split.variationIndex)
                    guard case .booleanValue(let value) = variation.value else { throw PrototypeError.invalidConfiguration }
                    metadata["__dd_allocation_key"] = allocation.key
                    metadata["allocationKey"] = allocation.key
                    metadata["__dd_do_log"] = allocation.logExposureEvent
                    metadata["doLog"] = allocation.logExposureEvent
                    metadata["variationType"] = "boolean"
                    if split.hasSerialID { metadata["__dd_split_serial_id"] = Int(split.serialID) }
                    let reason: String
                    switch split.reason {
                    case .targetingMatch: reason = "TARGETING_MATCH"
                    case .split: reason = "SPLIT"
                    case .static: reason = "STATIC"
                    case .default: reason = "DEFAULT"
                    default: reason = "UNKNOWN"
                    }
                    return [
                        "value": value, "reason": reason,
                        "variant": try at(configuration.strings, variation.keyStringIndex),
                        "flagMetadata": metadata,
                    ]
                }
            }
            return fallback("DEFAULT")
        } catch PrototypeError.targetingKeyMissing {
            return fallback("ERROR", error: "TARGETING_KEY_MISSING")
        } catch PrototypeError.invalidContext {
            return fallback("ERROR", error: "INVALID_CONTEXT")
        } catch {
            var result = fallback("ERROR", error: "PARSE_ERROR")
            result["errorMessage"] = "Invalid or unsupported client-protobuf benchmark workload"
            return result
        }
    }

    private func matches(_ index: UInt32, context: RulesValue, cache: inout [UInt32: Bool]) throws -> Bool {
        if let cached = cache[index] {
            return cached
        }
        let condition = try at(configuration.conditions, index)
        let result: Bool
        switch condition.kind {
        case .all(let operands):
            result = try operands.conditionIndexes.allSatisfy { child in
                guard child < index else { throw PrototypeError.invalidConfiguration }
                return try matches(child, context: context, cache: &cache)
            }
        case .any(let operands):
            result = try operands.conditionIndexes.contains { child in
                guard child < index else { throw PrototypeError.invalidConfiguration }
                return try matches(child, context: context, cache: &cache)
            }
        case .stringMembership(let membership):
            if let value = try attributeValue(membership.attributeIndex, context: context)?.stringValue {
                let included = try membership.stringIndexes.contains { stringIndex in
                    try at(configuration.strings, stringIndex).utf8.elementsEqual(value.utf8)
                }
                result = membership.negate ? !included : included
            } else {
                result = false
            }
        case .numeric(let numeric):
            if let value = try attributeValue(numeric.attributeIndex, context: context)?.numberValue {
                switch numeric.comparator {
                case .lessThan: result = value < numeric.comparand
                case .lessThanOrEqual: result = value <= numeric.comparand
                case .greaterThan: result = value > numeric.comparand
                case .greaterThanOrEqual: result = value >= numeric.comparand
                default: throw PrototypeError.unsupportedWorkload
                }
            } else {
                result = false
            }
        case .attributePresence(let presence):
            let value = try attributeValue(presence.attributeIndex, context: context)
            result = presence.expectNull ? value == nil : value != nil
        default: throw PrototypeError.unsupportedWorkload
        }
        cache[index] = result
        return result
    }

    private func attributeValue(_ index: UInt32, context: RulesValue) throws -> RulesValue? {
        let reference = try at(configuration.attributes, index)
        let result: RulesValue?
        switch reference.kind {
        case .targetingKey:
            guard case .object(let attributes) = context else { throw PrototypeError.invalidContext }
            result = attributes["targetingKey"]
        case .attributePath(let path):
            guard let first = path.segments.first, case .objectKeyStringIndex = first.kind else {
                throw PrototypeError.invalidConfiguration
            }
            var value: RulesValue? = context
            for segment in path.segments {
                switch segment.kind {
                case .objectKeyStringIndex(let key):
                    guard case .object(let object) = value else {
                        return nil
                    }
                    value = object[try at(configuration.strings, key)]
                case .arrayIndex(let offset):
                    guard case .array(let array) = value, Int(offset) < array.count else {
                        return nil
                    }
                    value = array[Int(offset)]
                default: throw PrototypeError.invalidConfiguration
                }
            }
            result = value
        default: throw PrototypeError.unsupportedWorkload
        }
        return result == .null ? nil : result
    }

    private func at<T>(_ items: [T], _ index: UInt32) throws -> T {
        guard Int(index) < items.count else { throw PrototypeError.invalidConfiguration }
        return items[Int(index)]
    }
}
