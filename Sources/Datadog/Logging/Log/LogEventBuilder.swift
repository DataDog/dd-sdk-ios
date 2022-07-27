/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `LogEvent` from data received from the user and provided internally by the SDK.
internal struct LogEventBuilder {
    /// The `service` value for logs.
    /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String
    /// The `logger.name` value for logs.
    let loggerName: String
    /// Whether to send the network info in `network.client.*` log attributes.
    let sendNetworkInfo: Bool
    /// Allows for modifying (or dropping) logs before they get sent.
    let eventMapper: LogEventMapper?

    /// Creates `LogEvent`.
    ///
    /// To ensure that logs include precise and correct information, some parameters must be collected synchronously on the caller thread
    /// whereas other don't. For example, it is important to sign logs with a `date` read exactly from the moment of public API call, but
    /// network info and other parts of the SDK `context` can be provided asynchronously.
    ///
    /// This is to guarantee the right order of logs in Datadog app when using multiple loggers on the same thread and to make sure
    /// that reported application context is accurate for the moment of log creation.
    ///
    /// - Parameters:
    ///   - date: date of creating the log
    ///   - level: the severity level of the log
    ///   - message: the message of the log
    ///   - error: eventual error to associate with log
    ///   - attributes: attributes to associate with log (user and internal attributes, separate)
    ///   - tags: tags to associate with log
    ///   - context: SDK context from the moment of creating log
    ///   - threadName: the name of the thread on which the log is created.
    ///
    /// - Returns: the `LogEvent` or `nil` if the log was dropped by the user (from event mapper API).
    ///
    /// - Note: `date` and `threadName` must be collected on the user thread.
    func createLogEvent(
        date: Date,
        level: LogLevel,
        message: String,
        error: DDError?,
        attributes: LogEvent.Attributes,
        tags: Set<String>,
        context: DatadogV1Context,
        threadName: String
    ) -> LogEvent? {
        let userInfo = context.userInfoProvider.value

        let log = LogEvent(
            date: date.addingTimeInterval(context.dateCorrector.offset),
            status: level.asLogStatus,
            message: message,
            error: error.map {
                .init(
                    kind: $0.type,
                    message: $0.message,
                    stack: $0.stack
                )
            },
            serviceName: service,
            environment: context.env,
            loggerName: loggerName,
            loggerVersion: context.sdkVersion,
            threadName: threadName,
            applicationVersion: context.version,
            userInfo: .init(
                id: userInfo.id,
                name: userInfo.name,
                email: userInfo.email,
                extraInfo: userInfo.extraInfo
            ),
            networkConnectionInfo: sendNetworkInfo ? context.networkConnectionInfoProvider.current : nil,
            mobileCarrierInfo: sendNetworkInfo ? context.carrierInfoProvider.current : nil,
            attributes: attributes,
            tags: !tags.isEmpty ? Array(tags) : nil
        )

        if let mapper = eventMapper {
            return mapper(log)
        }

        return log
    }
}

/// Returns the name of current thread if available or the nature of thread otherwise: `"main" | "background"`.
internal func getCurrentThreadName() -> String {
    if let customName = Thread.current.name, !customName.isEmpty {
        return customName
    } else {
        return Thread.isMainThread ? "main" : "background"
    }
}

internal extension LogLevel {
    var asLogStatus: LogEvent.Status {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }
}
