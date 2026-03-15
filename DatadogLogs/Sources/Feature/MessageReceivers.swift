/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receiver to consume a Log message
internal struct LogMessageReceiver: FeatureMessageReceiver, @unchecked Sendable {
    /// The log event mapper
    let logEventMapper: LogEventMapper?

    /// The feature scope to write log events.
    let featureScope: FeatureScope

    /// Process messages receives from the bus.
    ///
    /// - Parameter message: The Feature message
    func receive(message: FeatureMessage) {
        guard case let .payload(log as LogMessage) = message else {
            return
        }

        let logEventMapper = logEventMapper
        Task {
            guard let (context, writer) = await featureScope.eventWriteContext() else { return }
            let level: LogLevel = {
                switch log.level {
                case .debug: return .debug
                case .info: return .info
                case .notice: return .notice
                case .warn: return .warn
                case .error: return .error
                case .critical: return .critical
                }
            }()

            let builder = LogEventBuilder(
                service: log.service ?? context.service,
                loggerName: log.logger,
                networkInfoEnabled: log.networkInfoEnabled ?? false,
                eventMapper: logEventMapper
            )

            let event = await builder.createLogEvent(
                date: log.date,
                level: level,
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
                threadName: log.thread
            )

            writer.write(value: event)
        }
    }
}

/// Receiver to consume a Log event coming from Browser SDK.
internal struct WebViewLogReceiver: FeatureMessageReceiver, @unchecked Sendable {
    /// The feature scope to write log events.
    let featureScope: FeatureScope

    /// Process messages receives from the bus.
    ///
    /// - Parameter message: The Feature message
    func receive(message: FeatureMessage) {
        guard case let .webview(.log(event)) = message else {
            return
        }

        nonisolated(unsafe) var webEvent = event

        Task {
            guard let (context, writer) = await featureScope.eventWriteContext() else { return }
            let tagsKey = LogEventEncoder.StaticCodingKeys.tags.rawValue
            let dateKey = LogEventEncoder.StaticCodingKeys.date.rawValue

            if let tags = webEvent[tagsKey] as? String, !tags.isEmpty {
                webEvent[tagsKey] = "\(context.ddTags),\(tags)"
            } else {
                webEvent[tagsKey] = context.ddTags
            }

            if let timestampInMs = webEvent[dateKey] as? Int {
                let serverTimeOffsetInMs = context.serverTimeOffset.dd.toInt64Milliseconds
                let correctedTimestamp = Int64(timestampInMs) + serverTimeOffsetInMs
                webEvent[dateKey] = correctedTimestamp
            }

            if let rum = context.additionalContext(ofType: RUMCoreContext.self) {
                webEvent[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
                webEvent[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
                webEvent[LogEvent.Attributes.RUM.viewID] = rum.viewID
                webEvent[LogEvent.Attributes.RUM.actionID] = rum.userActionID
            }

            writer.write(value: AnyEncodable(webEvent))
        }
    }
}
