/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Encodable` representation of RUM event.
/// Mutable properties are subject of sanitization or data scrubbing.
internal struct RUMEvent<DM: RUMDataModel>: Encodable {
    /// The actual RUM event model created by `RUMMonitor`
    var model: DM

    /// Custom attributes set by the user
    var attributes: [String: Encodable]
    var userInfoAttributes: [String: Encodable]

    func encode(to encoder: Encoder) throws {
        let sanitizedEvent = RUMEventSanitizer().sanitize(event: self)
        try RUMEventEncoder().encode(sanitizedEvent, to: encoder)
    }
}

/// Encodes `RUMEvent` to given encoder.
internal struct RUMEventEncoder {
    /// Coding keys for dynamic `RUMEvent` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode<DM: RUMDataModel>(_ event: RUMEvent<DM>, to encoder: Encoder) throws {
        // Encode attributes
        var attributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try event.attributes.forEach { attributeName, attributeValue in
            // TODO: RUMM-1463 Remove this condition once new error format is managed through `RUMDataModels`
            if attributeName == DDError.threads || attributeName == DDError.binaryImages || attributeName == DDError.meta || attributeName == DDError.wasTruncated {
                try attributesContainer.encode(CodableValue(attributeValue), forKey: DynamicCodingKey(attributeName))
            } else {
                try attributesContainer.encode(CodableValue(attributeValue), forKey: DynamicCodingKey("context.\(attributeName)"))
            }
        }
        try event.userInfoAttributes.forEach { attributeName, attributeValue in
            try attributesContainer.encode(CodableValue(attributeValue), forKey: DynamicCodingKey("usr.\(attributeName)"))
        }

        // Encode `RUMDataModel`
        try event.model.encode(to: encoder)
    }
}
