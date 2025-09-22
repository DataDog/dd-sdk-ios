/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class FlagsEvaluationContext: Codable {
    public let targetingKey: String
    public let attributes: [String: String]
    public init(targetingKey: String, attributes: [String: String] = [:]) {
        self.targetingKey = targetingKey
        self.attributes = attributes
    }
}

public enum FlagsError: Error {
    case networkError(Error)
    case invalidResponse
    case clientNotInitialized
    case invalidConfiguration
    case unsupportedSite(String)
}

// TODO: FFL-1016 Include everything to fully hydrate a client (evaluationContext, clientConfiguration, anything else?)
internal struct FlagsMetadata: Codable {
    let fetchedAt: Double // Timestamp in milliseconds (JavaScript-style)
    let context: FlagsEvaluationContext?
}

/// A Codable wrapper for flags dictionary to enable JSON serialization in DataStore
internal struct CodableFlags: Codable {
    let flags: [String: CodableAny]

    init(flags: [String: Any]) {
        self.flags = flags.compactMapValues { CodableAny($0) }
    }

    func toDictionary() -> [String: Any] {
        return flags.compactMapValues { $0.value }
    }
}

/// A type-erased Codable wrapper to handle Any values in flags
internal struct CodableAny: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let dictValue = try? container.decode([String: CodableAny].self) {
            value = dictValue.compactMapValues { $0.value }
        } else if let arrayValue = try? container.decode([CodableAny].self) {
            value = arrayValue.map { $0.value }
        } else {
            throw DecodingError.typeMismatch(CodableAny.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let dictValue as [String: Any]:
            let codableDict = dictValue.compactMapValues { CodableAny($0) }
            try container.encode(codableDict)
        case let arrayValue as [Any]:
            let codableArray = arrayValue.map { CodableAny($0) }
            try container.encode(codableArray)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
