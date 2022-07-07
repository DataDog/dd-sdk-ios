/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the current active span attributes for produced `Logs`.
internal struct LoggingWithActiveSpanIntegration {
    struct Attributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    /// Produces `Log` attributes describing the current active span.
    /// Returns `nil` and prints warning if global `Tracer` is not registered.
    var activeSpanAttributes: [String: Encodable]? {
        guard let tracer = Global.sharedTracer as? Tracer else {
            DD.logger.warn("Tracing feature is enabled, but no `Tracer` is registered. The Tracing integration with Logging will not work.")
            return nil
        }

        if let activeSpanContext = tracer.activeSpan?.context as? DDSpanContext {
            return [
                Attributes.traceID: "\(activeSpanContext.traceID.rawValue)",
                Attributes.spanID: "\(activeSpanContext.spanID.rawValue)"
            ]
        } else {
            return nil
        }
    }
}
