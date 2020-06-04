/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Bridges logs created by Tracing feature to Logging feature's output. This stands for the thin integration layer
/// between Tracing and Logging features.
internal struct TracingToLoggingOutput {
    /// Open Tracing standard log fields:
    /// https://github.com/opentracing/specification/blob/master/semantic_conventions.md#log-fields-table
    struct OpenTracingFields {
        static let message = "message"
        // TODO: RUMM-477 Support all standard OT log fields and expose them to the user
    }

    /// Datadog reserved log fields.
    struct DatadogFields {
        // TODO: RUMM-478 Add tracing log attributes to the list of reserved log attributes in `LogSanitizer`
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    struct DefaultFieldValues {
        static let message = "Span event"
    }

    // MARK: - TraceLogOutput

    /// `LogOutput` provided by the `Logging` feature.
    let loggingOutput: LogOutput

    func writeLog(withSpanContext spanContext: DDSpanContext, fields: [String: Encodable], date: Date) {
        let message = (fields[OpenTracingFields.message] as? String) ?? DefaultFieldValues.message
        var logAttributes = fields.filter { $0.key != OpenTracingFields.message }

        logAttributes[DatadogFields.traceID] = "\(spanContext.traceID.rawValue)"
        logAttributes[DatadogFields.spanID] = "\(spanContext.spanID.rawValue)"

        loggingOutput.writeLogWith(level: .info, message: message, date: date, attributes: logAttributes, tags: [])
    }
}
