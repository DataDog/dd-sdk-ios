/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagAssignment: Equatable {
    enum Variation: Equatable {
        case boolean(Bool)
        case string(String)
        case integer(Int)
        case double(Double)
        case object(AnyValue)
    }

    var allocationKey: String
    var variationKey: String
    var variation: Variation
    var doLog: Bool

    func variation<T: FlagValue>(as type: T.Type) -> T? {
        switch self.variation {
        case .boolean(let value):
            return value as? T
        case .string(let value):
            return value as? T
        case .integer(let value):
            return value as? T
        case .double(let value):
            return value as? T
        case .object(let value):
            return value as? T
        }
    }
}

extension FlagAssignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case allocationKey
        case variationKey
        case variationType
        case variationValue
        case doLog
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.allocationKey = try container.decode(String.self, forKey: .allocationKey)
        self.variationKey = try container.decode(String.self, forKey: .variationKey)
        self.doLog = try container.decode(Bool.self, forKey: .doLog)

        let variationType = try container.decode(String.self, forKey: .variationType)

        switch variationType {
        case "BOOLEAN":
            self.variation = try .boolean(container.decode(Bool.self, forKey: .variationValue))
        case "STRING":
            self.variation = try .string(container.decode(String.self, forKey: .variationValue))
        case "NUMBER":
            // Check integer first, then double
            if let number = try? container.decode(Int.self, forKey: .variationValue) {
                self.variation = .integer(number)
            } else {
                self.variation = try .double(container.decode(Double.self, forKey: .variationValue))
            }
        case "OBJECT", "JSON":
            self.variation = try .object(container.decode(AnyValue.self, forKey: .variationValue))
        default:
            let context = DecodingError.Context(
                codingPath: container.codingPath + [CodingKeys.variationType],
                debugDescription: "Unrecognized variation type \(variationType)"
            )
            throw DecodingError.typeMismatch(FlagAssignment.self, context)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(allocationKey, forKey: .allocationKey)
        try container.encode(variationKey, forKey: .variationKey)
        try container.encode(doLog, forKey: .doLog)

        switch variation {
        case .boolean(let value):
            try container.encode("BOOLEAN", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .string(let value):
            try container.encode("STRING", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .double(let value):
            try container.encode("NUMBER", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .integer(let value):
            try container.encode("NUMBER", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        case .object(let value):
            try container.encode("JSON", forKey: .variationType)
            try container.encode(value, forKey: .variationValue)
        }
    }
}
