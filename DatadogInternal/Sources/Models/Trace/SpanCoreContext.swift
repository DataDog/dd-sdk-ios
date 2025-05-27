/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The Trace context received from `Core`.
public struct SpanCoreContext: AdditionalContext {
    public static let key = "span_context"

    /// The Trace ID
    public let traceID: String
    /// The Span ID
    public let spanID: String

    /// Creates a Span context.
    /// - Parameters:
    ///   - traceID: The Trace ID
    ///   - spanID: The Span ID
    public init(traceID: String, spanID: String) {
        self.traceID = traceID
        self.spanID = spanID
    }
}
