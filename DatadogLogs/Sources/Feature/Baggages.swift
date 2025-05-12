/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
