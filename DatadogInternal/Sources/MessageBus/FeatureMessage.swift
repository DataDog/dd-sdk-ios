/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The set of messages that can be transimtted on the Features message bus.
public enum FeatureMessage {
    /// A custom message with generic encodable attributes.
    ///
    /// A baggage can be used to transmit loosely-typed data structure using `Codable`.
    /// The encoding/decoding processes will have an impact on performances, opt for a baggage
    /// only if the data-structure is small.
    ///
    /// For large data type, use the `.value` case with shared type definition.
    case baggage(
        key: String,
        baggage: FeatureBaggage
    )

    /// A web-view message.
    ///
    /// Represent a Browser SDK event sent through the JS bridge.
    case webview(WebViewMessage)

    /// A core context message.
    ///
    /// The core will send updated context throught the bus. Do not send new context values
    /// from a Feature or Integration.
    case context(DatadogContext)

    /// A telemtry message.
    ///
    /// The core can send telemtry data coming from all Features.
    case telemetry(TelemetryMessage)
}

extension FeatureMessage {
    /// Creates a `.baggage` message with the given key and `Encodable` value.
    ///
    /// A baggage can be used to transmit loosely-typed data structure using `Codable`.
    /// The encoding/decoding processes will have an impact on performances, opt for a baggage
    /// only if the data-structure is small.
    /// 
    /// - Parameters:
    ///   - key: The baggage key.
    ///   - baggage: The baggage value.
    /// - Returns: a `.baggage` case.
    public static func baggage<Value>(key: String, value: Value) -> FeatureMessage where Value: Encodable {
        .baggage(key: key, baggage: .init(value))
    }

    /// Returns the baggage if the key matches the message.
    ///
    /// - Parameters:
    ///   - key: The requested baggage key.
    ///   - type: The expected type of the baggage value.
    /// - Returns: The decoded baggage value, or nil if the key doesn't match.
    /// - Throws: A `DecodingError` if decoding fails.
    public func baggage<Value>(forKey key: String, type: Value.Type = Value.self) throws -> Value? where Value: Decodable {
        guard case let .baggage(messageKey, baggage) = self, messageKey == key else {
            return nil
        }

        return try baggage.decode(type: type)
    }
}
