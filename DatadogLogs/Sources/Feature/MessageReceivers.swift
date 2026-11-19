/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
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

        return true
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
        var event: WebViewMessage.Event
        let capture: WebViewMessageWithRUMContext?
        switch message {
        case let .webview(.log(browserEvent)):
            event = browserEvent
            capture = nil
        case let .payload(message as WebViewMessageWithRUMContext):
            guard case let .log(browserEvent) = message.message else {
                return false
            }
            event = browserEvent
            capture = message
        default:
            return false
        }

        let tagsKey = LogEventEncoder.StaticCodingKeys.tags.rawValue
        let dateKey = LogEventEncoder.StaticCodingKeys.date.rawValue

        core.scope(for: LogsFeature.self).eventWriteContext { context, writer in
            event[tagsKey] = DDTag.merge(context.ddTags, with: event[tagsKey] as? String)

            if let timestampInMs = event[dateKey] as? Int {
                let serverTimeOffsetInMs = context.serverTimeOffset.dd.toInt64Milliseconds
                let correctedTimestamp = Int64(timestampInMs) + serverTimeOffsetInMs
                event[dateKey] = correctedTimestamp
            }

            let currentRUM = context.additionalContext(ofType: RUMCoreContext.self)
            let rum: RUMCoreContext?
            if let capture {
                rum = capture.rumContext(in: core, sessionID: currentRUM?.sessionID)
                event[LogEvent.Attributes.RUM.applicationID] = nil
                event[LogEvent.Attributes.RUM.sessionID] = nil
                event[LogEvent.Attributes.RUM.viewID] = nil
                event[LogEvent.Attributes.RUM.actionID] = nil
            } else {
                rum = currentRUM
            }
            if let rum, rum.sessionSampler.isSampled {
                event[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
                event[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
                event[LogEvent.Attributes.RUM.viewID] = rum.viewID
                event[LogEvent.Attributes.RUM.actionID] = rum.userActionID
            }

            // Add native anonymous_id to the event's usr object
            if let anonymousId = context.userInfo?.anonymousId {
                var usr = event[LogEvent.Attributes.User.key] as? [String: Any] ?? [:]
                usr[LogEvent.Attributes.User.anonymousId] = anonymousId
                event[LogEvent.Attributes.User.key] = usr
            }

            writer.write(value: AnyEncodable(event))
        }

        return true
    }
}
