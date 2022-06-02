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

    /// Log builder using Tracing configuration.
    let logBuilder: LogEventBuilder
    /// Actual `LogOutput` bridged to `LoggingFeature`.
    let loggingOutput: LogOutput

    init(
        tracerConfiguration: Tracer.Configuration,
        loggingFeature: LoggingFeature,
        context: DatadogV1Context
    ) {
        self.init(
            logBuilder: LogEventBuilder(
                sdkVersion: context.sdkVersion,
                applicationVersion: context.version,
                environment: context.env,
                serviceName: tracerConfiguration.serviceName ?? context.service,
                loggerName: "trace",
                userInfoProvider: context.userInfoProvider,
                networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? context.networkConnectionInfoProvider : nil,
                carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? context.carrierInfoProvider : nil,
                dateCorrector: context.dateCorrector,
                logEventMapper: loggingFeature.configuration.logEventMapper
            ),
            loggingOutput: LogFileOutput(
                fileWriter: loggingFeature.storage.writer,

                // The RUM Errors integration is not set for this instance of the `LogFileOutput`, as RUM Errors for
                // spans are managed through more comprehensive `TracingWithRUMErrorsIntegration`.
                // Having additional integration here would produce duplicated RUM Errors for span errors set through `span.log()` API.
                rumErrorsIntegration: nil
            )
        )
    }

    init(logBuilder: LogEventBuilder, loggingOutput: LogOutput) {
        self.logBuilder = logBuilder
        self.loggingOutput = loggingOutput
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

        let log = logBuilder.createLogWith(
            level: level,
            message: message,
            error: extractedError,
            date: date,
            attributes: LogEvent.Attributes(
                userAttributes: userAttributes,
                internalAttributes: internalAttributes
            ),
            tags: []
        )

        if let event = log {
            loggingOutput.write(log: event)
        }
    }
}
