/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// User provided log attributes
public struct LogEventAttributes {
    public var attributes: [String: Encodable]

    /// User provided log attributes
    ///
    /// - Parameters:
    ///   - attributes: Ths Logs attributes
    public init(attributes: [String: Encodable]) {
        self.attributes = attributes
    }
}

extension LogEventAttributes: Codable {
    public func encode(to encoder: Encoder) throws {
        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try attributes.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.attributes = dictionary
    }
}
