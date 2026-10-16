/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation

internal enum RulesValue: Codable, Equatable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([RulesValue])
    case object([String: RulesValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RulesValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RulesValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .boolean(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var type: RulesValueType? {
        switch self {
        case .null: return nil
        case .boolean: return .boolean
        case .number: return .number
        case .string: return .string
        case .array, .object: return .object
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .boolean(let value): return value ? "true" : "false"
        case .number(let value) where value.isFinite:
            if value == 0 {
                return "0"
            }
            let text = String(value)
            // Match common JSON scalar coercions. Exotic floating-point formatting is not a conformance claim.
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        default: return nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value) where value.isFinite: return value
        case .string(let value):
            let pattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
            guard value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex,
                  let number = Double(value), number.isFinite else {
                return nil
            }
            return number
        default: return nil
        }
    }
}

internal enum RulesValueType {
    case boolean, number, string, object
}

internal struct RulesContext {
    let targetingKey: String?
    let attributes: [String: RulesValue]

    init(targetingKey: String? = nil, attributes: [String: RulesValue] = [:]) {
        self.targetingKey = targetingKey
        self.attributes = attributes
    }

    func value(for attribute: String) -> RulesValue? {
        if let value = attributes[attribute] {
            return value
        }
        return attribute == "id" ? targetingKey.map(RulesValue.string) : nil
    }
}
