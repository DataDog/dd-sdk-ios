/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct GlobalRUMAttributes: Codable, PassthroughAnyCodable {
    public let attributes: [AttributeKey: AttributeValue]

    public init(attributes: [AttributeKey: AttributeValue]) {
        self.attributes = attributes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try attributes.forEach {
            try container.encode(AnyEncodable($1), forKey: DynamicCodingKey($0))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        attributes = try container.allKeys
            .reduce(into: [:]) { acc, next in acc[next.stringValue] = try container.decode(AnyCodable.self, forKey: next) }
    }
}
