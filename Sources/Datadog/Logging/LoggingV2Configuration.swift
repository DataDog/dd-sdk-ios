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
    dateProvider: DateProvider,
    logEventMapper: LogEventMapper?
) -> DatadogFeatureConfiguration {
    return DatadogFeatureConfiguration(
        name: "logging",
        requestBuilder: LoggingRequestBuilder(intake: intake),
        messageReceiver: CombinedFeatureMessageReceiver(
            LogMessageReceiver(logEventMapper: logEventMapper),
            CrashLogReceiver(dateProvider: dateProvider),
            WebViewLogReceiver()
        )
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
    static let crash = "crash-log"

    /// The key references a browser log message.
    static let browserLog = "browser-log"
}

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
        guard
            case let .custom(key, attributes) = message, key == LoggingMessageKeys.log,
            let loggerName: String = attributes["loggerName"],
            let date: Date = attributes["date"],
            let message: String = attributes["message"],
            let level: LogLevel = attributes["level"],
            let threadName: String = attributes["threadName"]
        else {
            return false
        }

        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext(bypassConsent: false) { context, writer in
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

/// Receiver to consume a Crash Log message as Log.
internal struct CrashLogReceiver: FeatureMessageReceiver {
    /// Time provider.
    let dateProvider: DateProvider

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard
            case let .custom(key, attributes) = message, key == LoggingMessageKeys.crash,
            let report = attributes["report", type: DDCrashReport.self],
            let context = attributes["context", type: CrashContext.self]
        else {
            return false
        }

        // The `report.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let date = (report.date ?? dateProvider.now)
            .addingTimeInterval(context.serverTimeOffset)

        var errorAttributes: [AttributeKey: AttributeValue] = [:]
        errorAttributes[DDError.threads] = report.threads
        errorAttributes[DDError.binaryImages] = report.binaryImages
        errorAttributes[DDError.meta] = report.meta
        errorAttributes[DDError.wasTruncated] = report.wasTruncated

        let user = context.userInfo
        let deviceInfo = context.device

        let event = LogEvent(
            date: date,
            status: .emergency,
            message: report.message,
            error: .init(
                kind: report.type,
                message: report.message,
                stack: report.stack
            ),
            serviceName: context.service,
            environment: context.env,
            loggerName: "crash-reporter",
            loggerVersion: context.sdkVersion,
            threadName: nil,
            applicationVersion: context.version,
            dd: .init(
                device: .init(architecture: deviceInfo.architecture)
            ),
            userInfo: .init(
                id: user?.id,
                name: user?.name,
                email: user?.email,
                extraInfo: user?.extraInfo ?? [:]
            ),
            networkConnectionInfo: context.networkConnectionInfo,
            mobileCarrierInfo: context.carrierInfo,
            attributes: .init(userAttributes: [:], internalAttributes: errorAttributes),
            tags: nil
        )

        // crash reporting is considering the user consent from previous session, if an event reached
        // the message bus it means that consent was granted and we can safely bypass current consent.
        core.v1.scope(for: LoggingFeature.self)?.eventWriteContext(bypassConsent: true, forceNewBatch: false) { _, writer in
            writer.write(value: event)
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
        guard case let .custom(key, baggage) = message, key == LoggingMessageKeys.browserLog else {
            return false
        }

        var event: [String: Any] = baggage.all()

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
}
