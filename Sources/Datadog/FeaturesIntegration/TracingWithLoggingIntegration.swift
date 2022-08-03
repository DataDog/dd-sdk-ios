/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Integration between Tracing and Logging Features to allow sending logs for spans (`span.log(fields:timestamp:)`)
internal struct TracingWithLoggingIntegration {
    internal struct TracingAttributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    private struct Constants {
        static let defaultLogMessage = "Span event"
        static let defaultErrorProperty = "Unknown"
    }

    /// `DatadogCore` instance managing this integration.
    let core: DatadogCoreProtocol
    /// Builds log events.
    let logBuilder: LogEventBuilder

    init(
        core: DatadogCoreProtocol,
        context: DatadogV1Context,
        tracerConfiguration: Tracer.Configuration,
        loggingFeature: LoggingFeature
    ) {
        self.init(
            core: core,
            logBuilder: LogEventBuilder(
                service: tracerConfiguration.serviceName ?? context.service,
                loggerName: "trace",
                sendNetworkInfo: tracerConfiguration.sendNetworkInfo,
                eventMapper: loggingFeature.configuration.logEventMapper
            )
        )
    }

    init(core: DatadogCoreProtocol, logBuilder: LogEventBuilder) {
        self.core = core
        self.logBuilder = logBuilder
    }

    func writeLog(withSpanContext spanContext: DDSpanContext, fields: [String: Encodable], date: Date) {
        var userAttributes = fields

        // get the log message and optional error kind
        let errorKind = userAttributes.removeValue(forKey: OTLogFields.errorKind) as? String
        let message = (userAttributes.removeValue(forKey: OTLogFields.message) as? String) ?? Constants.defaultLogMessage
        let errorStack = userAttributes.removeValue(forKey: OTLogFields.stack) as? String

        // infer the log level
        let isErrorEvent = fields[OTLogFields.event] as? String == "error"
        let hasErrorKind = errorKind != nil
        let level: LogLevel = (isErrorEvent || hasErrorKind) ? .error : .info

        // set tracing attributes
        let internalAttributes = [
            TracingAttributes.traceID: "\(spanContext.traceID.rawValue)",
            TracingAttributes.spanID: "\(spanContext.spanID.rawValue)"
        ]

        var extractedError: DDError?
        if level == .error {
            extractedError = DDError(
                type: errorKind ?? Constants.defaultErrorProperty,
                message: message,
                stack: errorStack ?? Constants.defaultErrorProperty
            )
        }

        let threadName = getCurrentThreadName()

        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext { context, writer in
            let log = logBuilder.createLogEvent(
                date: date,
                level: level,
                message: message,
                error: extractedError,
                attributes: .init(
                    userAttributes: userAttributes,
                    internalAttributes: internalAttributes
                ),
                tags: [],
                context: context,
                threadName: threadName
            )

            if let log = log {
                writer.write(value: log)
            }
        }
    }
}
