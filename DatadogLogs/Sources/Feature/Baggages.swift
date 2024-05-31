/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Error message sent from Logs on the message-bus.
internal struct ErrorMessage: Encodable {
    static let key = "error"
    /// The time of the log
    let time: Date
    /// The Log error message
    let message: String
    /// The Log error type
    let type: String?
    /// The Log error stack
    let stack: String?
    /// The Log error stack
    let source: String = "logger"
    /// The Log attributes
    let attributes: AnyEncodable
    /// Binary images if need to decode the stack trace
    let binaryImages: [BinaryImage]?
}

internal struct GlobalLogAttributes: Codable {
    static let key = "global-log-attributes"

    let attributes: [AttributeKey: AttributeValue]

    init(attributes: [AttributeKey: AttributeValue]) {
        self.attributes = attributes
    }

    func encode(to encoder: Encoder) throws {
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try attributes.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.attributes = try dynamicContainer.allKeys
            .reduce(into: [:]) {
                $0[$1.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: $1)
            }
    }
}

/// The Span context received from `DatadogCore`.
internal struct SpanContext: Decodable {
    static let key = "span_context"

    enum CodingKeys: String, CodingKey {
        case traceID = "dd.trace_id"
        case spanID = "dd.span_id"
    }

    let traceID: TraceID?
    let spanID: SpanID?
}

/// The RUM context received from `DatadogCore`.
internal struct RUMContext: Decodable {
    static let key = "rum"

    enum CodingKeys: String, CodingKey {
        case applicationID = "application.id"
        case sessionID = "session.id"
        case viewID = "view.id"
        case userActionID = "user_action.id"
    }

    /// Current RUM application ID - standard UUID string, lowecased.
    let applicationID: String
    /// Current RUM session ID - standard UUID string, lowecased.
    let sessionID: String
    /// Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
    let viewID: String?
    /// The ID of current RUM action (standard UUID `String`, lowercased).
    let userActionID: String?
}
