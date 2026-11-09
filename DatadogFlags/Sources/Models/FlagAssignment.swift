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
    /// Consent captured with this assignment, including when bridged or restored from disk.
    public var observeFullEvaluationData: Bool = false

    /// 2^53 - 1. Above this magnitude, a whole `Double` can be the rounded form of a different number.
    private static let maxSafeInteger: Double = 9_007_199_254_740_991

    /// Returns the variation as `T`. Numeric variations convert between `Int` and `Double` only
    /// when the conversion is exact, whatever their served numeric type.
    func variation<T: FlagValue>(as type: T.Type) -> T? {
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
            return value as? T
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

internal extension CodingUserInfoKey {
    /// Set on the decoder that reads the flags cache.
    static let decodesStoredVariations = CodingUserInfoKey(
        rawValue: "com.datadoghq.flags.decodes-stored-variations"
    )
}

private extension Decoder {
    /// Whether this decoder reads variations that the flags cache wrote.
    var decodesStoredVariations: Bool {
        guard let key = CodingUserInfoKey.decodesStoredVariations else {
            return false
        }
        return userInfo[key] as? Bool ?? false
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
            if variationType == "float", decoder.decodesStoredVariations {
                // The flags cache writes a `.double` as "float". Restore it as `.double`, so a restore does not
                // change its reads.
                self.variation = try .double(container.decode(Double.self, forKey: .variationValue))
            } else if let number = try? container.decode(Int.self, forKey: .variationValue) {
                // The served numeric type does not limit reads. Try `Int` before `Double` to keep integer
                // literals exact. Known issue: `JSONDecoder` can decode a number with a fractional part as `Int`,
                // for example `9007199254740993.5` as `9007199254740993`. This decode path cannot detect the lost
                // fraction, because `JSONDecoder` does not expose the number text.
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
