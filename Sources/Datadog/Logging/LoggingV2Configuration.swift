/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
        case .custom(let key, let attributes) where key == "log":
            return log(attributes: attributes, to: core)
        default:
            return false
        }
    }

    private func log(attributes: FeatureMessageAttributes, to core: DatadogCoreProtocol) -> Bool {
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

            let log = builder.createLogEvent(
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
                threadName: threadName
            )

            if let log = log {
                writer.write(value: log)
            }
        }

        return true
    }
}
