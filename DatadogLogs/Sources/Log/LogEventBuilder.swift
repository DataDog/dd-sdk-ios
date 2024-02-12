/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builds `LogEvent` from data received from the user and provided internally by the SDK.
internal struct LogEventBuilder {
    /// The `service` value for logs.
    /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String
    /// The `logger.name` value for logs.
    let loggerName: String?
    /// Whether to send the network info in `network.client.*` log attributes.
    let networkInfoEnabled: Bool
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
    ///   - callback: The callback to return the modified `LogEvent`.
    ///
    /// - Note: `date` and `threadName` must be collected on the user thread.
    func createLogEvent(
        date: Date,
        level: LogLevel,
        message: String,
        error: DDError?,
        attributes: LogEvent.Attributes,
        tags: Set<String>,
        context: DatadogContext,
        threadName: String,
        callback: @escaping (LogEvent) -> Void
    ) {
        let userInfo = context.userInfo ?? .empty

        let log = LogEvent(
            date: date.addingTimeInterval(context.serverTimeOffset),
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
            loggerName: loggerName ?? context.applicationBundleIdentifier,
            loggerVersion: context.sdkVersion,
            threadName: threadName,
            applicationVersion: context.version,
            applicationBuildNumber: context.buildNumber,
            buildId: context.buildId,
            dd: LogEvent.Dd(
                device: LogEvent.DeviceInfo(
                    brand: context.device.brand,
                    name: context.device.name,
                    model: context.device.model,
                    architecture: context.device.architecture
                )
            ),
            os: .init(
                name: context.device.osName,
                version: context.device.osVersion,
                build: context.device.osBuildNumber
            ),
            userInfo: .init(
                id: userInfo.id,
                name: userInfo.name,
                email: userInfo.email,
                extraInfo: userInfo.extraInfo
            ),
            networkConnectionInfo: networkInfoEnabled ? context.networkConnectionInfo : nil,
            mobileCarrierInfo: networkInfoEnabled ? context.carrierInfo : nil,
            attributes: attributes,
            tags: !tags.isEmpty ? Array(tags) : nil
        )

        eventMapper?.map(event: log, callback: callback) ?? callback(log)
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
