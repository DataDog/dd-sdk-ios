/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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

    /// Log levels ordered by their severity, with `.debug` being the least severe and
    /// `.critical` being the most severe.
    public enum LogLevel: Int, Codable {
        case debug
        case info
        case notice
        case warn
        case error
        case critical
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
            TracingAttributes.traceID: String(spanContext.traceID),
            TracingAttributes.spanID: String(spanContext.spanID)
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
                    "loggerName": "trace",
                    "service": service,
                    "threadName": Thread.current.dd.name,
                    "message": message,
                    "level": level,
                    "error": extractedError,
                    "userAttributes": AnyEncodable(userAttributes),
                    "internalAttributes": internalAttributes,
                    "networkInfoEnabled": networkInfoEnabled
                ]
            ),
            else: fallback
        )
    }
}
