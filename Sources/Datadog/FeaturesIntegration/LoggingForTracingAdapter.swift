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
            loggingOutput: LogFileOutput(
                logBuilder: LogBuilder(
                    applicationVersion: tracingFeature.configuration.applicationVersion,
                    environment: tracingFeature.configuration.environment,
                    serviceName: tracerConfiguration.serviceName ?? tracingFeature.configuration.serviceName,
                    loggerName: "trace",
                    userInfoProvider: tracingFeature.userInfoProvider,
                    networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.networkConnectionInfoProvider : nil,
                    carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.carrierInfoProvider : nil
                ),
                fileWriter: loggingFeature.storage.writer
            )
        )
    }

    /// Bridges logs created by Tracing feature to Logging feature's output.
    internal struct AdaptedLogOutput {
        private struct Constants {
            static let defaultLogMessage = "Span event"
        }

        private struct TracingAttributes {
            static let traceID = "dd.trace_id"
            static let spanID = "dd.span_id"

            // TODO: RUMM-478 Add tracing log attributes to the list of reserved log attributes in `LogSanitizer`
        }

        /// Actual `LogOutput` bridged to `LoggingFeature`.
        let loggingOutput: LogOutput

        func writeLog(withSpanContext spanContext: DDSpanContext, fields: [String: Encodable], date: Date) {
            var attributes = fields

            // get the log message
            let message = (attributes.removeValue(forKey: OTLogFields.message) as? String) ?? Constants.defaultLogMessage

            // infer the log level
            let isErrorEvent = fields[OTLogFields.event] as? String == "error"
            let hasErrorKind = fields[OTLogFields.errorKind] != nil
            let level: LogLevel = (isErrorEvent || hasErrorKind) ? .error : .info

            // set tracing attributes
            attributes[TracingAttributes.traceID] = "\(spanContext.traceID.rawValue)"
            attributes[TracingAttributes.spanID] = "\(spanContext.spanID.rawValue)"

            loggingOutput.writeLogWith(level: level, message: message, date: date, attributes: attributes, tags: [])
        }
    }
}
