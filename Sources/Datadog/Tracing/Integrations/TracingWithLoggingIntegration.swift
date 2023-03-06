/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogLogs

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

    struct Configuration {
        /// The `service` value for logs.
        /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
        let service: String?
        /// The `logger.name` value for logs.
        let loggerName: String
        /// Whether to send the network info in `network.client.*` log attributes.
        let sendNetworkInfo: Bool
    }

    /// `DatadogCore` instance managing this integration.
    weak var core: DatadogCoreProtocol?
    /// Builds log events.
    let configuration: Configuration

    init(
        core: DatadogCoreProtocol,
        tracerConfiguration: DatadogTracer.Configuration
    ) {
        self.init(
            core: core,
            configuration: .init(
                service: tracerConfiguration.serviceName,
                loggerName: "trace",
                sendNetworkInfo: tracerConfiguration.sendNetworkInfo
            )
        )
    }

    init(core: DatadogCoreProtocol, configuration: Configuration) {
        self.core = core
        self.configuration = configuration
    }

    func writeLog(withSpanContext spanContext: DDSpanContext, fields: [String: Encodable], date: Date, else fallback: @escaping () -> Void) {
        guard let core = core else {
            return
        }

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
            TracingAttributes.traceID: spanContext.traceID.toString(.decimal),
            TracingAttributes.spanID: spanContext.spanID.toString(.decimal)
        ]

        var extractedError: DDError?
        if level == .error {
            extractedError = DDError(
                type: errorKind ?? Constants.defaultErrorProperty,
                message: message,
                stack: errorStack ?? Constants.defaultErrorProperty
            )
        }

        core.send(
            message: .custom(
                key: "log",
                baggage: [
                    "date": date,
                    "loggerName": configuration.loggerName,
                    "service": configuration.service,
                    "threadName": Thread.current.dd.name,
                    "message": message,
                    "level": level,
                    "error": extractedError,
                    "userAttributes": AnyEncodable(userAttributes),
                    "internalAttributes": internalAttributes,
                    "sendNetworkInfo": configuration.sendNetworkInfo
                ]
            ),
            else: fallback
        )
    }
}
