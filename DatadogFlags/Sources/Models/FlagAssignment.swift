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

    /// Whether a decoded number has a value that snapshots and bridge consumers can represent.
    internal var hasRepresentableValue: Bool {
        guard let numericConversion else {
            return true
        }
        return numericConversion.integer != nil || numericConversion.double != nil
    }

    /// Consent captured with this assignment, including when bridged or restored from disk.
    @_spi(Internal)
    public var observeFullEvaluationData: Bool = false

    /// 2^53 - 1. Above this magnitude, a whole `Double` can be the rounded form of a different number.
    private static let maxSafeInteger: Double = 9_007_199_254_740_991

    /// Returns the variation as `T`. Numeric getters use `numericConversion` when present. Otherwise they
    /// convert the stored variation with conservative rules.
    func variation<T: FlagValue>(as type: T.Type) -> T? {
        if let numericConversion {
            if T.self == Int.self {
                return numericConversion.integer as? T
            }
            if T.self == Double.self {
                return numericConversion.double as? T
            }
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
                // Above 2^53 - 1, a `.double` can be the rounded form of a different number, so it does not
                // convert. For example, `JSONDecoder` decodes `9007199254740993.0001` as `9007199254740994.0`.
                // Below the limit, exactness applies to the decoded value, not to the JSON text: `JSONDecoder`
                // rounds over-precise literals such as `999999999999999.99` to `1000000000000000`.
                return abs(value) <= Self.maxSafeInteger ? Int(exactly: value) as? T : nil
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
        case observeFullEvaluationData
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.allocationKey = try container.decode(String.self, forKey: .allocationKey)
        self.variationKey = try container.decode(String.self, forKey: .variationKey)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.doLog = try container.decode(Bool.self, forKey: .doLog)
        // A malformed serial id decodes as absent so it cannot fail the whole response.
        self.serialID = try? container.decodeIfPresent(Int.self, forKey: .serialID)
        self.observeFullEvaluationData = (try? container.decode(Bool.self, forKey: .observeFullEvaluationData)) == true

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
            if FlagsNumericJSON.isCache(decoder), variationType == "float", cachedLiteral == nil {
                // Restore a cached "float" without `_numericLiteral` as `.double`. Earlier and current SDK
                // versions both write this form. Integer reads stay conservative.
                self.variation = try .double(container.decode(Double.self, forKey: .variationValue))
            } else if let literal = cachedLiteral ?? rawLiteral,
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
                // Without `FlagsNumericJSON`, `JSONDecoder` can decode a fractional number as `Int`, for
                // example `9007199254740993.5`.
                self.variation = .integer(number)
            } else {
                do {
                    self.variation = try .double(container.decode(Double.self, forKey: .variationValue))
                } catch {
                    // A canonically equivalent key can hide this member's token, and `JSONDecoder` rejects a number
                    // such as `1e400`. `addingKeySpellings(from:)` decodes the member again from its own bytes.
                    // `JSONDecoder` reports that rejection with an internal error type, so only type errors rethrow.
                    guard FlagsNumericJSON.hasTokens(decoder), !FlagsNumericJSON.isTypeError(error) else {
                        throw error
                    }
                    self.variation = .unknown(variationType)
                }
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
        try container.encode(observeFullEvaluationData, forKey: .observeFullEvaluationData)

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

/// A decodable whose JSON holds flag assignments at a fixed path.
internal protocol FlagNumericTokenRoot: Decodable {
    /// JSON keys from the document root to the object that maps flag keys to assignments.
    /// Empty when the document is a single assignment.
    static var flagAssignmentsPath: [String] { get }
}

extension FlagAssignment: FlagNumericTokenRoot {
    static var flagAssignmentsPath: [String] { [] }
}

/// Retains numeric tokens before Foundation can round them during decoding.
internal enum FlagsNumericJSON {
    private static let tokensKey = CodingUserInfoKey(rawValue: "flags.numericTokens")
    private static let cacheKey = CodingUserInfoKey(rawValue: "flags.numericCache")
    /// Bytes that can continue a JSON number: digits, sign, decimal point, and exponent marker.
    private static let numberBytes = Set("0123456789+-.eE".utf8)

    static func decode<T: FlagNumericTokenRoot>(_ type: T.Type, from data: Data, cached: Bool = false) throws -> T {
        guard let tokensKey, let cacheKey else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid numeric decoder configuration"))
        }
        let decoder = JSONDecoder()
        decoder.userInfo[cacheKey] = cached
        // The cache stores `_numericLiteral` whenever a read differs from the decoded number, and writes every
        // other number as exact `JSONEncoder` output. Only network responses need their original tokens.
        if !cached {
            let data = utf8(data)
            var tokens = try numericTokens(in: data)
            for key in T.flagAssignmentsPath {
                guard case .object(let object) = tokens, let next = object[key] else {
                    tokens = .other
                    break
                }
                tokens = next
            }
            decoder.userInfo[tokensKey] = tokens
            return try decoder.decode(type, from: data)
        }
        return try decoder.decode(type, from: data)
    }

    /// Returns `data` as UTF-8 without a byte order mark. `JSONDecoder` also reads UTF-16 and UTF-32, but the
    /// numeric token scan and the key-spelling scan read UTF-8 bytes.
    static func utf8(_ data: Data) -> Data {
        let head = Array(data.prefix(4))
        if head.starts(with: [0xEF, 0xBB, 0xBF]) {
            return Data(data.dropFirst(3))
        }
        // Without a byte order mark, the zero bytes around the first ASCII character give the encoding.
        let zero = head.map { $0 == 0 }
        let encoding: String.Encoding
        if head.starts(with: [0x00, 0x00, 0xFE, 0xFF]) || zero.starts(with: [true, true, true]) {
            encoding = .utf32BigEndian
        } else if head.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || zero == [false, true, true, true] {
            encoding = .utf32LittleEndian
        } else if head.starts(with: [0xFE, 0xFF]) || zero.first == true {
            encoding = .utf16BigEndian
        } else if head.starts(with: [0xFF, 0xFE]) || zero.dropFirst().first == true {
            encoding = .utf16LittleEndian
        } else {
            return data
        }
        guard let text = String(data: data, encoding: encoding) else {
            return data
        }
        let scalars = text.unicodeScalars
        return Data(String(scalars.first == "\u{FEFF}" ? scalars.dropFirst() : scalars[...]).utf8)
    }

    /// Copies `data` with every number token quoted, and decodes the string leaves of the result.
    private static func numericTokens(in data: Data) throws -> FlagNumericTokenTree {
        let bytes = Array(data)
        var quoted: [UInt8] = []
        quoted.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                // Copy JSON strings verbatim, including escaped quotes and backslashes.
                quoted.append(byte)
                index += 1
                while index < bytes.count {
                    let next = bytes[index]
                    quoted.append(next)
                    index += 1
                    if next == UInt8(ascii: "\\"), index < bytes.count {
                        quoted.append(bytes[index])
                        index += 1
                    } else if next == UInt8(ascii: "\"") {
                        break
                    }
                }
            } else if byte == UInt8(ascii: "-") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                let numberStart = index
                quoted.append(UInt8(ascii: "\""))
                repeat {
                    quoted.append(bytes[index])
                    index += 1
                } while index < bytes.count && Self.numberBytes.contains(bytes[index])
                // Quoting would turn an invalid JSON number into a valid string, so reject it here.
                guard FlagNumericConversion.hasValidSyntax(String(decoding: bytes[numberStart..<index], as: UTF8.self)) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid numeric literal"))
                }
                quoted.append(UInt8(ascii: "\""))
            } else {
                quoted.append(byte)
                index += 1
            }
        }
        return try JSONDecoder().decode(FlagNumericTokenTree.self, from: Data(quoted))
    }

    static func literal(in decoder: Decoder, key: String) -> String? {
        guard let tokensKey, var tokens = decoder.userInfo[tokensKey] as? FlagNumericTokenTree else {
            return nil
        }
        // Older `JSONDecoder` implementations can drop nested container keys from `codingPath`. Only its last
        // component, the flag key, is reliable, so `decode` resolves the assignments object first.
        if let flagKey = decoder.codingPath.last?.stringValue {
            guard case .object(let assignments) = tokens, let assignment = assignments[flagKey] else {
                return nil
            }
            tokens = assignment
        }
        guard case .object(let object) = tokens, case .string(let literal) = object[key] else {
            return nil
        }
        return literal
    }

    /// True when `decode` scanned the original number tokens, that is, for a network response.
    static func hasTokens(_ decoder: Decoder) -> Bool {
        guard let tokensKey else {
            return false
        }
        return decoder.userInfo[tokensKey] is FlagNumericTokenTree
    }

    /// True for an error that a value of the wrong JSON type causes, for example a string for a number.
    static func isTypeError(_ error: Error) -> Bool {
        switch error as? DecodingError {
        case .typeMismatch, .valueNotFound, .keyNotFound: return true
        default: return false
        }
    }

    static func isCache(_ decoder: Decoder) -> Bool {
        guard let cacheKey else {
            return false
        }
        return decoder.userInfo[cacheKey] as? Bool == true
    }
}

internal struct FlagNumericConversion: Equatable {
    let literal: String
    let integer: Int?
    let double: Double?

    /// Matches the JSON number grammar.
    static func hasValidSyntax(_ literal: String) -> Bool {
        literal.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
    }

    init(_ literal: String) {
        self.literal = literal
        guard Self.hasValidSyntax(literal) else {
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

private enum FlagNumericTokenTree: Decodable {
    case string(String)
    case object([String: FlagNumericTokenTree])
    case array([FlagNumericTokenTree])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Check the common leaves first, so Booleans and nulls do not throw through every container attempt.
        if container.decodeNil() {
            self = .other
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if (try? container.decode(Bool.self)) != nil {
            self = .other
        } else if let object = try? container.decode([String: FlagNumericTokenTree].self) {
            self = .object(object)
        } else if let array = try? container.decode([FlagNumericTokenTree].self) {
            self = .array(array)
        } else {
            self = .other
        }
    }
}
