/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Write interface for a custom carrier
public protocol TracePropagationHeadersWriter {
    var traceHeaderFields: [String: String] { get }

    /// Inject a span context into the custom carrier
    ///
    /// - parameter spanContext: context to inject into the custom carrier
    func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)
}

extension TracePropagationHeadersWriter {
    public func write(traceID: TraceID, spanID: SpanID) {
        write(traceID: traceID, spanID: spanID, parentSpanID: nil)
    }
}
