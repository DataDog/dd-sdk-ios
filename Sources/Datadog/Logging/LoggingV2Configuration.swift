/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Creates Logging Feature Configuration.
/// - Parameters:
///   - intake: The Logging intake URL.
///   - logEventMapper: The log event mapper.
/// - Returns: The Logging feature configuration.
internal func createLoggingConfiguration(
    intake: URL,
    logEventMapper: LogEventMapper?
) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "logging",
        requestBuilder: LoggingRequestBuilder(intake: intake),
        messageReceiver: LoggingMessageReceiver(logEventMapper: logEventMapper)
    )
}

/// The Logging URL Request Builder for formatting and configuring the `URLRequest`
/// to upload logs data.
internal struct LoggingRequestBuilder: FeatureRequestBuilder {
    /// The logs intake.
    let intake: URL

    /// The logs request body format.
    let format = DataFormat(prefix: "[", suffix: "]", separator: ",")

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: intake,
            queryItems: [
                .ddsource(source: context.source)
            ],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ]
        )

        let data = format.format(events)
        return builder.uploadRequest(with: data)
    }
}

/// Defines keys referencing RUM messages supported on the bus.
internal enum LoggingMessageKeys {
    /// The key references a log entry message.
    static let log = "log"

    /// The key references a crash message.
    static let crash = "crash"

    /// The key references a browser log message.
    static let browserLog = "browser-log"
}

internal struct LoggingMessageReceiver: FeatureMessageReceiver {
    /// The log event mapper
    let logEventMapper: LogEventMapper?

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .custom(let key, let attributes) where key == LoggingMessageKeys.log:
            return log(attributes: attributes, to: core)
        case .custom(let key, let attributes) where key == LoggingMessageKeys.crash:
            return crash(attributes: attributes, to: core)
        case .custom(let key, let baggage) where key == LoggingMessageKeys.browserLog:
            return write(event: baggage.all(), to: core)
        default:
            return false
        }
    }

    private func write(event: [String: Any], to core: DatadogCoreProtocol) -> Bool {
        var event = event

        let versionKey = LogEventEncoder.StaticCodingKeys.applicationVersion.rawValue
        let envKey = LogEventEncoder.StaticCodingKeys.environment.rawValue
        let tagsKey = LogEventEncoder.StaticCodingKeys.tags.rawValue
        let dateKey = LogEventEncoder.StaticCodingKeys.date.rawValue

        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext { context, writer in
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

            if let attributes = context.featuresAttributes["rum"] {
                event.merge(attributes.all()) { $1 }
            }

            writer.write(value: AnyEncodable(event))
        }

        return true
    }

    private func crash(attributes: FeatureBaggage, to core: DatadogCoreProtocol) -> Bool {
        guard let event = attributes["log", type: LogEvent.self] else {
            return false
        }

        // crash reporting is considering the user consent from previous session, if an event reached
        // the message bus it means that consent was granted and we can safely bypass current consent.
        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext(bypassConsent: true) { _, writer in
            writer.write(value: event)
        }

        return true
    }

    private func log(attributes: FeatureBaggage, to core: DatadogCoreProtocol) -> Bool {
        guard
            let loggerName: String = attributes["loggerName"],
            let date: Date = attributes["date"],
            let message: String = attributes["message"],
            let level: LogLevel = attributes["level"],
            let threadName: String = attributes["threadName"]
        else {
            return false
        }

        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext { context, writer in
            let builder = LogEventBuilder(
                service: attributes["service"] ?? context.service,
                loggerName: loggerName,
                sendNetworkInfo: attributes["sendNetworkInfo"] ?? false,
                eventMapper: logEventMapper
            )

            builder.createLogEvent(
                date: date,
                level: level,
                message: message,
                error: attributes["error"],
                attributes: .init(
                    userAttributes: attributes["userAttributes"] ?? [:],
                    internalAttributes: attributes["internalAttributes"]
                ),
                tags: [],
                context: context,
                threadName: threadName,
                callback: writer.write
            )
        }

        return true
    }
}
