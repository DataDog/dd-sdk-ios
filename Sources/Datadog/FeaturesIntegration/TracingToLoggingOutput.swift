/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Bridges logs created by Tracing feature to Logging feature's output. This stands for a thin integration layer
/// between Tracing and Logging features.
internal struct TracingToLoggingOutput {
    private struct Constants {
        static let defaultLogMessage = "Span event"
    }

    private struct TracingAttributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"

        // TODO: RUMM-478 Add tracing log attributes to the list of reserved log attributes in `LogSanitizer`
    }

    // MARK: - TraceLogOutput

    /// `LogOutput` provided by the `Logging` feature.
    let loggingOutput: LogOutput

    func writeLog(withSpanContext spanContext: DDSpanContext, fields: [String: Encodable], date: Date) {
        var attributes = fields

        // get the log message
        let message = (attributes.removeValue(forKey: OpenTracingLogFields.message) as? String) ?? Constants.defaultLogMessage

        // infer the log level
        let isErrorEvent = fields[OpenTracingLogFields.event] as? String == "error"
        let hasErrorKind = fields[OpenTracingLogFields.errorKind] != nil
        let level: LogLevel = (isErrorEvent || hasErrorKind) ? .error : .info

        // set tracing attributes
        attributes[TracingAttributes.traceID] = "\(spanContext.traceID.rawValue)"
        attributes[TracingAttributes.spanID] = "\(spanContext.spanID.rawValue)"

        loggingOutput.writeLogWith(level: level, message: message, date: date, attributes: attributes, tags: [])
    }
}
