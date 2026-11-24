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
    @_spi(Internal)
    public var observeFullEvaluationData: Bool = false
    /// Features of the selected split. The public initializer starts with an empty list.
    internal var features: [SplitFeature] = []

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

    /// Rebuilds a bridged assignment. Features are normalized like a decoded response: the first valid
    /// entry for each key wins, and entries with an empty key, a non-finite number or no destination are skipped.
    public init(
        allocationKey: String,
        variationKey: String,
        variation: Variation,
        reason: String,
        doLog: Bool,
        serialID: Int?,
        observeFullEvaluationData: Bool,
        snapshotFeatures: [FlagSnapshotFeature]
    ) {
        self.init(
            allocationKey: allocationKey,
            variationKey: variationKey,
            variation: variation,
            reason: reason,
            doLog: doLog,
            serialID: serialID
        )
        self.observeFullEvaluationData = observeFullEvaluationData
        self.features = SplitFeature.firstValidPerKey(
            snapshotFeatures.lazy.map { SplitFeature.validated(key: $0.key, value: $0.value.anyValue, destinations: $0.destinations) }
        )
    }

    /// Every feature of the selected split, all destinations included, for bridges that rebuild the assignment.
    public var snapshotFeatures: [FlagSnapshotFeature] {
        features.compactMap(FlagSnapshotFeature.init(splitFeature:))
    }
}

/// The value of a split feature in a bridged assignment.
@_spi(Internal)
public enum FlagSnapshotFeatureValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var anyValue: AnyValue {
        switch self {
        case .string(let value): return .string(value)
        case .number(let value): return .double(value)
        case .bool(let value): return .bool(value)
        }
    }
}

/// A split feature of a bridged assignment.
@_spi(Internal)
public struct FlagSnapshotFeature: Equatable {
    public let key: String
    public let value: FlagSnapshotFeatureValue
    /// Wire names, unknown ones included. Only `HOOK`, `EXPOSURE` and `EVALUATION` route the feature.
    public let destinations: [String]

    public init(key: String, value: FlagSnapshotFeatureValue, destinations: [String]) {
        self.key = key
        self.value = value
        self.destinations = destinations
    }

    init?(splitFeature: SplitFeature) {
        switch splitFeature.value {
        case .string(let value): self.value = .string(value)
        case .double(let value): self.value = .number(value)
        case .bool(let value): self.value = .bool(value)
        default: return nil
        }
        self.key = splitFeature.key
        self.destinations = splitFeature.destinations
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
        case features
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
        self.features = (try? container.decodeIfPresent(LenientSplitFeatures.self, forKey: .features))?.features ?? []

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
        if !features.isEmpty {
            try container.encode(features, forKey: .features)
        }

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

/// A feature of the split that produced an assignment.
internal struct SplitFeature: Equatable {
    enum Destination: String {
        case hook = "HOOK"
        case exposure = "EXPOSURE"
        case evaluation = "EVALUATION"
    }

    /// The public metadata prefix. Customers read `HOOK` features under it.
    static let hookMetadataPrefix = "__dd_feature."

    let key: String
    /// `.string`, `.double` or `.bool`.
    let value: AnyValue
    /// Wire names, unknown ones included. Routing uses the known names.
    let destinations: [String]

    func routes(to destination: Destination) -> Bool {
        destinations.contains(destination.rawValue)
    }

    /// Returns nil for an empty key, a value other than a string, a finite number or a Boolean, or no non-empty destination.
    static func validated(key: String, value: AnyValue, destinations: [String]) -> SplitFeature? {
        switch value {
        case .string, .bool: break
        case .double(let number) where number.isFinite: break
        default: return nil
        }
        let destinations = destinations.filter { !$0.isEmpty }
        guard !key.isEmpty, !destinations.isEmpty else {
            return nil
        }
        return SplitFeature(key: key, value: value, destinations: destinations)
    }

    /// Keeps the first valid feature for each key. An invalid entry does not claim its key.
    static func firstValidPerKey<S: Sequence>(_ candidates: S) -> [SplitFeature] where S.Element == SplitFeature? {
        var features: [SplitFeature] = []
        var keys: Set<String> = []
        for case let feature? in candidates where keys.insert(feature.key).inserted {
            features.append(feature)
        }
        return features
    }
}

extension SplitFeature: Encodable {
    private enum CodingKeys: String, CodingKey {
        case key
        case value
        case destinations
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
        try container.encode(destinations, forKey: .destinations)
    }
}

extension Array where Element == SplitFeature {
    /// Feature values for one destination, keyed by feature key.
    func values(for destination: SplitFeature.Destination) -> [String: AnyValue] {
        var values: [String: AnyValue] = [:]
        for feature in self where feature.routes(to: destination) {
            values[feature.key] = feature.value
        }
        return values
    }

    func hookMetadata() -> [String: AnyValue] {
        var metadata: [String: AnyValue] = [:]
        for feature in self where feature.routes(to: .hook) {
            metadata[SplitFeature.hookMetadataPrefix + feature.key] = feature.value
        }
        return metadata
    }
}

/// Decodes `features` leniently and returns an empty list for a malformed field. It skips invalid
/// entries and keeps the first valid entry for each key.
internal struct LenientSplitFeatures: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key
        case value
        case destinations
    }

    /// Consumes any JSON value, so a skipped element still advances an unkeyed container.
    private struct Skip: Decodable {}

    private struct Entry: Decodable {
        let feature: SplitFeature?

        init(from decoder: any Decoder) {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self),
                  let key = try? container.decode(String.self, forKey: .key),
                  let value = Self.value(in: container),
                  let destinations = Self.destinations(in: container) else {
                feature = nil
                return
            }
            feature = SplitFeature.validated(key: key, value: value, destinations: destinations)
        }

        private static func value(in container: KeyedDecodingContainer<CodingKeys>) -> AnyValue? {
            if let value = try? container.decode(Bool.self, forKey: .value) {
                return .bool(value)
            }
            if let value = try? container.decode(Double.self, forKey: .value) {
                return .double(value)
            }
            if let value = try? container.decode(String.self, forKey: .value) {
                return .string(value)
            }
            return nil
        }

        private static func destinations(in container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
            guard var list = try? container.nestedUnkeyedContainer(forKey: .destinations) else {
                return nil
            }
            var names: [String] = []
            while !list.isAtEnd {
                if let name = try? list.decode(String.self) {
                    names.append(name)
                } else if !LenientSplitFeatures.skip(&list) {
                    break
                }
            }
            return names
        }
    }

    let features: [SplitFeature]

    init(from decoder: any Decoder) {
        guard var list = try? decoder.unkeyedContainer() else {
            features = []
            return
        }
        var candidates: [SplitFeature?] = []
        while !list.isAtEnd {
            guard let entry = try? list.decode(Entry.self) else {
                break
            }
            candidates.append(entry.feature)
        }
        self.features = SplitFeature.firstValidPerKey(candidates)
    }

    /// An unkeyed container advances on a successful decode, so this consumes a skipped element explicitly.
    fileprivate static func skip(_ list: inout UnkeyedDecodingContainer) -> Bool {
        if (try? list.decodeNil()) == true {
            return true
        }
        return (try? list.decode(Skip.self)) != nil
    }
}
