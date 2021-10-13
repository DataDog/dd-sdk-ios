/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Adapts the Logging feature for Tracing. This stands for a thin integration layer between features.
internal struct LoggingForTracingAdapter {
    private let loggingFeature: LoggingFeature

    init(loggingFeature: LoggingFeature) {
        self.loggingFeature = loggingFeature
    }

    // MARK: - LogOutput

    func resolveLogOutput(usingTracingFeature tracingFeature: TracingFeature, tracerConfiguration: Tracer.Configuration) -> AdaptedLogOutput {
        return AdaptedLogOutput(
            logBuilder: LogEventBuilder(
                applicationVersion: tracingFeature.configuration.common.applicationVersion,
                environment: tracingFeature.configuration.common.environment,
                serviceName: tracerConfiguration.serviceName ?? tracingFeature.configuration.common.serviceName,
                loggerName: "trace",
                userInfoProvider: tracingFeature.userInfoProvider,
                networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.networkConnectionInfoProvider : nil,
                carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.carrierInfoProvider : nil,
                dateCorrector: loggingFeature.dateCorrector,
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

    internal struct TracingAttributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    /// Bridges logs created by Tracing feature to Logging feature's output.
    internal struct AdaptedLogOutput {
        private struct Constants {
            static let defaultLogMessage = "Span event"
            static let defaultErrorProperty = "Unknown"
        }

        /// Log builder using Tracing configuration.
        let logBuilder: LogEventBuilder
        /// Actual `LogOutput` bridged to `LoggingFeature`.
        let loggingOutput: LogOutput

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
}
