/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Integration between Tracing and Logging Features to allow sending logs for spans (`span.log(fields:timestamp:)`)
internal struct TracingWithLoggingIntegration {
    private struct Constants {
        static let defaultLogMessage = "Span event"
        static let defaultErrorProperty = "Unknown"
        /// Key referencing the trace ID.
        static let traceIDKey = "dd.trace_id"
        /// Key referencing the span ID.
        static let spanIDKey = "dd.span_id"
    }

    /// `DatadogCore` instance managing this integration.
    weak var core: DatadogCoreProtocol?
    let service: String?
    let networkInfoEnabled: Bool

    init(core: DatadogCoreProtocol, service: String?, networkInfoEnabled: Bool) {
        self.core = core
        self.service = service
        self.networkInfoEnabled = networkInfoEnabled
    }

    // swiftlint:disable function_default_parameter_at_end
    func writeLog(
        withSpanContext spanContext: DDSpanContext,
        message: String? = nil,
        fields: [String: Encodable],
        date: Date,
        else fallback: @escaping () -> Void
    ) {
        guard let core = core else {
            return
        }

        var userAttributes = fields

        // get the log message and optional error kind
        let errorKind: String? = userAttributes.removeValue(forKey: OTLogFields.errorKind)?.dd.decode()
        let message = userAttributes.removeValue(forKey: OTLogFields.message)?.dd.decode() ?? message ?? Constants.defaultLogMessage
        let errorStack: String? = userAttributes.removeValue(forKey: OTLogFields.stack)?.dd.decode()

        // infer the log level
        let isErrorEvent = fields[OTLogFields.event] as? String == "error"
        let hasErrorKind = errorKind != nil
        let level: LogMessage.Level = (isErrorEvent || hasErrorKind) ? .error : .info

        let extractedError: DDError? = level == .error ?
            DDError(
                type: errorKind ?? Constants.defaultErrorProperty,
                message: message,
                stack: errorStack ?? Constants.defaultErrorProperty
            )
        : nil

        core.send(
            message: .payload(
                LogMessage(
                    logger: "trace",
                    service: service,
                    date: date,
                    message: message,
                    error: extractedError,
                    level: level,
                    thread: Thread.current.dd.name,
                    networkInfoEnabled: networkInfoEnabled,
                    userAttributes: userAttributes,
                    internalAttributes: [
                        Constants.traceIDKey: String(spanContext.traceID, representation: .hexadecimal),
                        Constants.spanIDKey: String(spanContext.spanID, representation: .hexadecimal)
                    ]
                )
            ),
            else: fallback
        )
    }
    // swiftlint:enable function_default_parameter_at_end
}
