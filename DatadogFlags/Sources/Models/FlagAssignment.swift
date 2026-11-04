/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@_spi(Internal)
public struct FlagAssignment: Equatable {
    public enum Variation: Equatable {
        case boolean(Bool)
        case string(String)
        case integer(Int)
        case double(Double)
        case object(AnyValue)
        case unknown(String)
    }
    public var allocationKey: String
    public var variationKey: String
    public var variation: Variation
    public var reason: String
    public var doLog: Bool
    public var serialID: Int?
    internal var numericConversion: FlagNumericConversion?

    func variation<T: FlagValue>(as type: T.Type) -> T? {
        if let numericConversion {
            if T.self == Int.self { return numericConversion.integer as? T }
            if T.self == Double.self { return numericConversion.double as? T }
        }
        switch self.variation {
        case .boolean(let value):
            return value as? T
        case .string(let value):
            return value as? T
        case .integer(let value):
            if T.self == Double.self {
                return Double(exactly: value) as? T
            }
            return value as? T
        case .double(let value):
            if T.self == Int.self {
                return Int(exactly: value) as? T
            }
            return value.isFinite ? value as? T : nil
        case .object(let value):
            return value as? T
        case .unknown:
            return nil
        }
    }

    public init(allocationKey: String, variationKey: String, variation: Variation, reason: String, doLog: Bool, serialID: Int? = nil) {
        self.allocationKey = allocationKey
        self.variationKey = variationKey
        self.variation = variation
        self.reason = reason
        self.doLog = doLog
        self.serialID = serialID
    }
}

extension FlagAssignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case allocationKey
        case variationKey
        case variationType
        case variationValue
        case reason
        case doLog
        case serialID = "serialId"
        case numericLiteral = "_numericLiteral"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.allocationKey = try container.decode(String.self, forKey: .allocationKey)
        self.variationKey = try container.decode(String.self, forKey: .variationKey)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.doLog = try container.decode(Bool.self, forKey: .doLog)
        // A malformed serial id decodes as absent so it cannot fail the whole response.
        self.serialID = try? container.decodeIfPresent(Int.self, forKey: .serialID)

        let variationType = try container.decode(String.self, forKey: .variationType)

        switch variationType {
        case "boolean":
            self.variation = try .boolean(container.decode(Bool.self, forKey: .variationValue))
        case "string":
            self.variation = try .string(container.decode(String.self, forKey: .variationValue))
        case "number", "integer", "float":
            // Preserve integer precision before considering a floating-point value.
            // Numeric wire labels do not constrain getter conversions.
            let cachedLiteral = FlagsNumericJSON.isCache(decoder)
                ? try container.decodeIfPresent(String.self, forKey: .numericLiteral) : nil
            let rawLiteral = FlagsNumericJSON.literal(in: decoder, key: "variationValue")
            // A string on the wire remains invalid, even if it contains digits.
            if let literal = cachedLiteral ?? rawLiteral,
               (try? container.decode(String.self, forKey: .variationValue)) == nil {
                let conversion = FlagNumericConversion(literal)
                if let integer = conversion.integer {
                    self.variation = .integer(integer)
                    if conversion.double != Double(exactly: integer) { self.numericConversion = conversion }
                } else {
                    let approximate = conversion.double ?? 0
                    self.variation = .double(approximate)
                    if conversion.double == nil || Int(exactly: approximate) != nil {
                        self.numericConversion = conversion
                    }
                }
            } else if let number = try? container.decode(Int.self, forKey: .variationValue) {
                self.variation = .integer(number)
            } else {
                self.variation = try .double(container.decode(Double.self, forKey: .variationValue))
            }
        case "object":
            self.variation = try .object(container.decode(AnyValue.self, forKey: .variationValue))
        default:
            self.variation = .unknown(variationType)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(allocationKey, forKey: .allocationKey)
        try container.encode(variationKey, forKey: .variationKey)
        try container.encode(reason, forKey: .reason)
        try container.encode(doLog, forKey: .doLog)
        try container.encodeIfPresent(serialID, forKey: .serialID)
        try container.encodeIfPresent(numericConversion?.literal, forKey: .numericLiteral)

        switch variation {
        case .boolean(let value):
            try container.encode("boolean", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .string(let value):
            try container.encode("string", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .double(let value):
            try container.encode("float", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .integer(let value):
            try container.encode("integer", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .object(let value):
            try container.encode("object", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .unknown(let typeName):
            // Should never happen as unknown variations are filtered out
            try container.encode(typeName, forKey: .variationType)
            try container.encodeNil(forKey: .variationValue)
        }
    }
}

/// Retains numeric tokens before Foundation can round them during decoding.
internal enum FlagsNumericJSON {
    private static let tokensKey = CodingUserInfoKey(rawValue: "flags.numericTokens")
    private static let cacheKey = CodingUserInfoKey(rawValue: "flags.numericCache")

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, cached: Bool = false) throws -> T {
        guard let tokensKey, let cacheKey else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid numeric decoder configuration"))
        }
        let bytes = Array(data)
        var quoted: [UInt8] = []
        quoted.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 {
                // Copy JSON strings verbatim, including escaped quotes and backslashes.
                quoted.append(byte)
                index += 1
                while index < bytes.count {
                    let next = bytes[index]
                    quoted.append(next)
                    index += 1
                    if next == 92, index < bytes.count {
                        quoted.append(bytes[index])
                        index += 1
                    } else if next == 34 {
                        break
                    }
                }
            } else if byte == 45 || (48...57).contains(byte) {
                quoted.append(34)
                repeat {
                    quoted.append(bytes[index])
                    index += 1
                } while index < bytes.count && (bytes[index] == 45 || bytes[index] == 43 || bytes[index] == 46 || bytes[index] == 69 || bytes[index] == 101 || (48...57).contains(bytes[index]))
                quoted.append(34)
            } else {
                quoted.append(byte)
                index += 1
            }
        }
        let decoder = JSONDecoder()
        decoder.userInfo[tokensKey] = try JSONDecoder().decode(FlagNumericTokenTree.self, from: Data(quoted))
        decoder.userInfo[cacheKey] = cached
        return try decoder.decode(type, from: data)
    }

    static func literal(in decoder: Decoder, key: String) -> String? {
        guard let tokensKey else { return nil }
        var value = decoder.userInfo[tokensKey] as? FlagNumericTokenTree
        for component in decoder.codingPath {
            switch value {
            case .object(let object): value = object[component.stringValue]
            case .array(let array):
                guard let index = component.intValue, array.indices.contains(index) else { return nil }
                value = array[index]
            default: return nil
            }
        }
        guard case .object(let object) = value, case .string(let literal) = object[key] else { return nil }
        return literal
    }

    static func isCache(_ decoder: Decoder) -> Bool {
        guard let cacheKey else { return false }
        return decoder.userInfo[cacheKey] as? Bool == true
    }
}

internal struct FlagNumericConversion: Equatable {
    let literal: String
    let integer: Int?
    let double: Double?

    init(_ literal: String) {
        self.literal = literal
        guard literal.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
            integer = nil
            double = nil
            return
        }
        let negative = literal.hasPrefix("-")
        let unsigned = negative ? String(literal.dropFirst()) : literal
        let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let significand = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = significand.joined().drop(while: { $0 == "0" })
        let fractionCount = significand.count == 2 ? significand[1].count : 0
        // Saturation avoids overflow/allocation for adversarial exponents.
        let exponent = parts.count == 2 ? Int(parts[1]) ?? (parts[1].hasPrefix("-") ? Int.min : Int.max) : 0
        let subtraction = exponent.subtractingReportingOverflow(fractionCount)
        var scale = subtraction.overflow ? Int.min : subtraction.partialValue
        if digits.isEmpty {
            integer = 0
            double = 0
            return
        }
        while digits.last == "0", scale < Int.max {
            digits = digits.dropLast()
            scale += 1
        }
        let whole = scale >= 0
        let sign = negative ? "-" : ""
        let wholeText: String? = whole && scale <= 309 && digits.count <= 309 - scale
            ? sign + digits + String(repeating: "0", count: scale) : nil
        integer = wholeText.flatMap(Int.init)
        guard let value = Double(literal), value.isFinite, value != 0 else {
            double = nil
            return
        }
        if whole {
            // %.0f renders the exact integer represented by a finite binary Double.
            double = wholeText == String(format: "%.0f", value) ? value : nil
        } else {
            double = value
        }
    }
}

private indirect enum FlagNumericTokenTree: Decodable {
    case string(String)
    case object([String: FlagNumericTokenTree])
    case array([FlagNumericTokenTree])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: FlagNumericTokenTree].self) {
            self = .object(object)
        } else if let array = try? container.decode([FlagNumericTokenTree].self) {
            self = .array(array)
        } else {
            self = .other
        }
    }
}
