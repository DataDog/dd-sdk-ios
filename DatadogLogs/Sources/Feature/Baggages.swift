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
}

/// The Span context received from `DatadogCore`.
internal struct SpanContext: Decodable {
    static let key = "span_context"

    enum CodingKeys: String, CodingKey {
        case traceID = "dd.trace_id"
        case spanID = "dd.span_id"
    }

    let traceID: String?
    let spanID: String?

    var internalAttributes: [String: String?] {
        [
            CodingKeys.traceID.rawValue: traceID,
            CodingKeys.spanID.rawValue: spanID
        ]
    }
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

    var internalAttributes: [String: String] {
        var context: [String: String] = [
            "application_id": applicationID,
            "session_id": sessionID
        ]

        context["view.id"] = viewID
        context["user_action.id"] = userActionID
        return context
    }
}
