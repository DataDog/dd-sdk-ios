/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation

internal enum RulesPreparationError: Error, Equatable {
    case invalidConfiguration
    case unsupportedFormat
    case unsupportedOperator(String)
}

internal struct RulesConfiguration: Decodable {
    let format: String
    let flags: [String: RulesFlagEntry]
    let observeFullEvaluationData: Bool?

    static func parse(_ data: Data) throws -> RulesConfiguration {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
                throw RulesPreparationError.invalidConfiguration
            }
            // The JS reference uses Date, whose precision is milliseconds.
            return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
        }
        let configuration = try decoder.decode(Self.self, from: data)
        guard configuration.format == "SERVER" else {
            throw RulesPreparationError.unsupportedFormat
        }
        return configuration
    }
}

internal enum RulesFlagEntry: Decodable {
    case valid(RulesFlag)
    case invalid(RulesPreparationError)

    init(from decoder: Decoder) throws {
        do {
            let flag = try RulesFlag(from: decoder)
            try flag.validate()
            self = .valid(flag)
        } catch let error as RulesPreparationError {
            self = .invalid(error)
        } catch {
            // Invalid or unsupported flags must not prevent valid sibling flags from loading.
            self = .invalid(.invalidConfiguration)
        }
    }
}

internal struct RulesFlag: Decodable {
    let key: String
    let enabled: Bool
    let variationType: RulesVariationType
    let variations: [String: RulesVariation]
    let allocations: [RulesAllocation]

    func validate() throws {
        guard variations.allSatisfy({ key, variation in
            key == variation.key && variationType.accepts(variation.value)
        }) else {
            throw RulesPreparationError.invalidConfiguration
        }
        for allocation in allocations {
            for split in allocation.splits {
                guard variations[split.variationKey] != nil else {
                    throw RulesPreparationError.invalidConfiguration
                }
                for shard in split.shards {
                    guard shard.totalShards > 0, shard.totalShards <= Int(UInt32.max),
                          shard.ranges.allSatisfy({ $0.start >= 0 && $0.end >= $0.start && $0.end <= shard.totalShards }) else {
                        throw RulesPreparationError.invalidConfiguration
                    }
                }
            }
        }
    }
}

internal enum RulesVariationType: String, Decodable {
    case boolean = "BOOLEAN"
    case integer = "INTEGER"
    case numeric = "NUMERIC"
    case string = "STRING"
    case json = "JSON"

    var valueType: RulesValueType {
        switch self {
        case .boolean: return .boolean
        case .integer, .numeric: return .number
        case .string: return .string
        case .json: return .object
        }
    }

    func accepts(_ value: RulesValue) -> Bool {
        guard value.type == valueType else {
            return false
        }
        if case .number(let number) = value {
            return number.isFinite && (self != .integer || (number.rounded() == number && abs(number) <= 9_007_199_254_740_991))
        }
        return true
    }
}

internal struct RulesVariation: Decodable {
    let key: String
    let value: RulesValue
}

internal struct RulesAllocation: Decodable {
    let key: String
    let rules: [RulesRule]?
    let startAt: Date?
    let endAt: Date?
    let splits: [RulesSplit]
    let doLog: Bool?

    func matches(_ context: RulesContext, at date: Date) -> Bool {
        if let startAt = startAt, date < startAt {
            return false
        }
        if let endAt = endAt, date >= endAt {
            return false
        }
        guard let rules = rules, !rules.isEmpty else {
            return true
        }
        return rules.contains { $0.conditions.allSatisfy { $0.matches(context) } }
    }
}

internal struct RulesSplit: Decodable {
    let variationKey: String
    let shards: [RulesShard]
    let serialId: UInt64?
}

internal struct RulesShard: Decodable {
    let salt: String
    let totalShards: Int
    let ranges: [RulesShardRange]
}

internal struct RulesShardRange: Decodable {
    let start: Int
    let end: Int
}

internal struct RulesRule: Decodable {
    let conditions: [RulesCondition]
}

internal struct RulesCondition: Decodable {
    enum Operation: String {
        case oneOf = "ONE_OF", notOneOf = "NOT_ONE_OF", isNull = "IS_NULL"
        case less = "LT", lessOrEqual = "LTE", greater = "GT", greaterOrEqual = "GTE"
    }

    private enum CodingKeys: String, CodingKey { case attribute, value, operation = "operator" }

    let attribute: String
    let operation: Operation
    let value: RulesValue

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attribute = try container.decode(String.self, forKey: .attribute)
        value = try container.decode(RulesValue.self, forKey: .value)
        let name = try container.decode(String.self, forKey: .operation)
        guard let operation = Operation(rawValue: name) else {
            throw RulesPreparationError.unsupportedOperator(name)
        }
        self.operation = operation
        switch (operation, value) {
        case (.oneOf, .array(let members)), (.notOneOf, .array(let members)):
            guard members.allSatisfy({ $0.type == .string }) else {
                throw RulesPreparationError.invalidConfiguration
            }
        case (.isNull, .boolean): break
        case (.less, .number(let number)), (.lessOrEqual, .number(let number)),
             (.greater, .number(let number)), (.greaterOrEqual, .number(let number)):
            guard number.isFinite else {
                throw RulesPreparationError.invalidConfiguration
            }
        default: throw RulesPreparationError.invalidConfiguration
        }
    }

    func matches(_ context: RulesContext) -> Bool {
        let attributeValue = context.value(for: attribute)
        if case (.isNull, .boolean(let expectedNull)) = (operation, value) {
            return (attributeValue == nil || attributeValue == .null) == expectedNull
        }
        guard let attributeValue = attributeValue, attributeValue != .null else {
            return false
        }
        switch (operation, value) {
        case (.oneOf, .array(let members)), (.notOneOf, .array(let members)):
            guard let text = attributeValue.stringValue else {
                return false
            }
            let contained = members.contains {
                guard case .string(let member) = $0 else {
                    return false
                }
                // Swift String equality normalizes Unicode; JS string equality does not.
                return member.utf8.elementsEqual(text.utf8)
            }
            return operation == .oneOf ? contained : !contained
        case (_, .number(let expected)):
            guard let actual = attributeValue.numberValue else {
                return false
            }
            switch operation {
            case .less: return actual < expected
            case .lessOrEqual: return actual <= expected
            case .greater: return actual > expected
            case .greaterOrEqual: return actual >= expected
            default: return false
            }
        default: return false
        }
    }
}
