/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `Logger` sending logs to Datadog.
internal final class RemoteLogger: Logger {
    struct Configuration {
        /// The `service` value for logs.
        /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
        let service: String?
        /// The `logger.name` value for logs.
        let loggerName: String
        /// Whether to send the network info in `network.client.*` log attributes.
        let sendNetworkInfo: Bool
        /// Only logs equal or above this threshold will be sent.
        let threshold: LogLevel
        /// Allows for modifying (or dropping) logs before they get sent.
        let eventMapper: LogEventMapper?
        /// Sampler for remote logger. Default is using `100.0` sampling rate.
        let sampler: Sampler
    }

    /// `DatadogCore` instance managing this logger.
    internal let core: DatadogCoreProtocol
    /// Configuration specific to this logger.
    internal let configuration: Configuration
    /// Date provider for logs.
    private let dateProvider: DateProvider
    /// Integration with RUM. It is used to correlate Logs with RUM events by injecting RUM context to `LogEvent`.
    /// Can be `false` if the integration is disabled for this logger.
    internal let rumContextIntegration: Bool
    /// Integration with Tracing. It is used to correlate Logs with Spans by injecting `Span` context to `LogEvent`.
    /// Can be `false` if the integration is disabled for this logger.
    internal let activeSpanIntegration: Bool
    /// Logger-specific attributes.
    @ReadWriteLock
    private var attributes: [String: Encodable] = [:]
    /// Logger-specific tags.
    @ReadWriteLock
    private var tags: Set<String> = []

    init(
        core: DatadogCoreProtocol,
        configuration: Configuration,
        dateProvider: DateProvider,
        rumContextIntegration: Bool,
        activeSpanIntegration: Bool
    ) {
        self.core = core
        self.configuration = configuration
        self.dateProvider = dateProvider
        self.rumContextIntegration = rumContextIntegration
        self.activeSpanIntegration = activeSpanIntegration
    }

    // MARK: - Attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        _attributes.mutate { $0[key] = value }
    }

    func removeAttribute(forKey key: AttributeKey) {
        _attributes.mutate { $0.removeValue(forKey: key) }
    }

    // MARK: - Tags

    func addTag(withKey key: String, value: String) {
        _tags.mutate { $0.insert("\(key):\(value)") }
    }

    func removeTag(withKey key: String) {
        _tags.mutate { $0 = $0.filter { !$0.hasPrefix("\(key):") } }
    }

    func add(tag: String) {
        _tags.mutate { $0.insert(tag) }
    }

    func remove(tag: String) {
        _tags.mutate { $0.remove(tag) }
    }

    // MARK: - Logging

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        internalLog(level: level, message: message, error: error.map { DDError(error: $0) }, attributes: attributes)
    }

    func log(level: LogLevel, message: String, errorKind: String?, errorMessage: String?, stackTrace: String?, attributes: [String: Encodable]?) {
        var ddError: DDError?
        if errorKind != nil || errorMessage != nil || stackTrace != nil {
            // Cross platform frameworks don't necessarilly send all values for errors. Send empty strings
            // for any values that are empty.
            ddError = DDError(type: errorKind ?? "", message: errorMessage ?? "", stack: stackTrace ?? "")
        }

        internalLog(level: level, message: message, error: ddError, attributes: attributes)
    }

    func internalLog(level: LogLevel, message: String, error: DDError?, attributes: [String: Encodable]?) {
        guard configuration.sampler.sample() else {
            return
        }
        guard level.rawValue >= configuration.threshold.rawValue else {
            return
        }

        // on user thread:
        let date = dateProvider.now
        let threadName = Thread.current.dd.name

        // capture current tags and attributes before opening the write event context
        let tags = self.tags
        var logAttributes = attributes
        let isCrash = logAttributes?.removeValue(forKey: CrossPlatformAttributes.errorLogIsCrash) as? Bool ?? false
        let userAttributes = self.attributes
            .merging(logAttributes ?? [:]) { $1 } // prefer message attributes

        // SDK context must be requested on the user thread to ensure that it provides values
        // that are up-to-date for the caller.
        self.core.scope(for: LogsFeature.name)?.eventWriteContext { context, writer in
            var internalAttributes: [String: Encodable] = [:]
            let contextAttributes = context.featuresAttributes

            if self.rumContextIntegration, let attributes: [String: AnyCodable?] = contextAttributes["rum"]?.ids {
                let attributes = attributes.compactMapValues { $0 }
                internalAttributes.merge(attributes) { $1 }
            }

            if self.activeSpanIntegration, let attributes = contextAttributes["tracing"] {
                let attributes = attributes.compactMapValues(AnyEncodable.init)
                internalAttributes.merge(attributes) { $1 }
            }

            let builder = LogEventBuilder(
                service: self.configuration.service ?? context.service,
                loggerName: self.configuration.loggerName,
                sendNetworkInfo: self.configuration.sendNetworkInfo,
                eventMapper: self.configuration.eventMapper
            )

            builder.createLogEvent(
                date: date,
                level: level,
                message: message,
                error: error,
                attributes: .init(
                    userAttributes: userAttributes,
                    internalAttributes: internalAttributes
                ),
                tags: tags,
                context: context,
                threadName: threadName
            ) { log in
                writer.write(value: log)

                guard (log.status == .error || log.status == .critical) && !isCrash else {
                    return
                }

                self.core.send(
                    message: .error(
                        message: log.error?.message ?? log.message,
                        baggage: [
                            "type": log.error?.kind,
                            "stack": log.error?.stack,
                            "source": "logger",
                            "attributes": userAttributes
                        ]
                    )
                )
            }
        }
    }
}
