/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receiver to consume a Log message
internal struct LogMessageReceiver: FeatureMessageReceiver {
    /// The log event mapper
    let logEventMapper: LogEventMapper?

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(log as LogMessage) = message else {
            return false
        }

        core.scope(for: LogsFeature.self).eventWriteContext { context, writer in
            let builder = LogEventBuilder(
                service: log.service ?? context.service,
                loggerName: log.logger,
                networkInfoEnabled: log.networkInfoEnabled ?? false,
                eventMapper: logEventMapper
            )

            builder.createLogEvent(
                date: log.date,
                level: {
                    switch log.level {
                    case .debug: return .debug
                    case .info: return .info
                    case .notice: return .notice
                    case .warn: return .warn
                    case .error: return .error
                    case .critical: return .critical
                    }
                }(),
                message: log.message,
                error: log.error,
                errorFingerprint: nil,
                binaryImages: nil,
                attributes: .init(
                    userAttributes: log.userAttributes ?? [:],
                    internalAttributes: log.internalAttributes
                ),
                tags: [],
                context: context,
                threadName: log.thread,
                callback: writer.write
            )
        }

        return false
    }
}

/// Receiver to consume a Log event coming from Browser SDK.
internal struct WebViewLogReceiver: FeatureMessageReceiver {
    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case var .webview(.log(event)) = message else {
            return false
        }

        let versionKey = LogEventEncoder.StaticCodingKeys.applicationVersion.rawValue
        let envKey = LogEventEncoder.StaticCodingKeys.environment.rawValue
        let tagsKey = LogEventEncoder.StaticCodingKeys.tags.rawValue
        let dateKey = LogEventEncoder.StaticCodingKeys.date.rawValue

        core.scope(for: LogsFeature.self).eventWriteContext { context, writer in
            let ddTags = "\(versionKey):\(context.version),\(envKey):\(context.env)"

            if let tags = event[tagsKey] as? String, !tags.isEmpty {
                event[tagsKey] = "\(ddTags),\(tags)"
            } else {
                event[tagsKey] = ddTags
            }

            if let timestampInMs = event[dateKey] as? Int {
                let serverTimeOffsetInMs = context.serverTimeOffset.toInt64Milliseconds
                let correctedTimestamp = Int64(timestampInMs) + serverTimeOffsetInMs
                event[dateKey] = correctedTimestamp
            }

            if let rum = context.additionalContext(ofType: RUMCoreContext.self) {
                event[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
                event[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
                event[LogEvent.Attributes.RUM.viewID] = rum.viewID
                event[LogEvent.Attributes.RUM.actionID] = rum.userActionID
            }

            writer.write(value: AnyEncodable(event))
        }

        return true
    }
}
