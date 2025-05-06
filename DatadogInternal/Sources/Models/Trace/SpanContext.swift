/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The Span context received from `DatadogCore`.
public struct SpanContext: Codable {
    public enum CodingKeys: String, CodingKey {
        case traceID = "dd.trace_id"
        case spanID = "dd.span_id"
    }

    public let traceID: String?
    public let spanID: String?

    public init(traceID: String?, spanID: String?) {
        self.traceID = traceID
        self.spanID = spanID
    }
}
