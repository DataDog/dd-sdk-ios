/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Logger` sending logs to Datadog.
internal final class RemoteLogger: LoggerProtocol {
    struct Configuration {
        /// The `service` value for logs.
        /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
        let service: String
        /// The `logger.name` value for logs.
        let loggerName: String
        /// Whether to send the network info in `network.client.*` log attributes.
        let sendNetworkInfo: Bool
        /// Only logs equal or above this threshold will be sent.
        let threshold: LogLevel
        /// Allows for modifying (or dropping) logs before they get sent.
        let eventMapper: LogEventMapper?
    }

    /// `DatadogCore` instance managing this logger.
    internal let core: DatadogCoreProtocol
    /// Configuration specific to this logger.
    internal let configuration: Configuration

    /// Logger-specific attributes (must be accesset through `queue`).
    private var unsafeAttributes: [String: Encodable] = [:]
    /// Logger-specific tags (must be accesset through `queue`).
    private var unsafeTags: Set<String> = []
    /// Queue for ensuring thread-safety of tags and attributes mutation.
    private let queue: DispatchQueue

    /// Date provider for logs.
    private let dateProvider: DateProvider
    /// Builds log events.
    private let builder: LogEventBuilder
    /// Integration with RUM. It is used to correlate Logs with RUM events by injecting RUM context to `LogEvent`.
    /// Can be `nil` if the integration is disabled for this logger or if RUM feature is disabled.
    internal let rumContextIntegration: LoggingWithRUMContextIntegration?
    /// Integration with RUM. It is used to send RUM errors for logs of high severity (`.error` and above).
    /// Can be `nil` if RUM feature is disabled.
    internal let rumErrorsIntegration: LoggingWithRUMErrorsIntegration?
    /// Integration with Tracing. It is used to correlate Logs with Spans by injecting `Span` context to `LogEvent`.
    /// Can be `nil` if the integration is disabled for this logger or if Tracing feature is disabled.
    internal let activeSpanIntegration: LoggingWithActiveSpanIntegration?

    init(
        core: DatadogCoreProtocol,
        configuration: Configuration,
        dateProvider: DateProvider,
        rumContextIntegration: LoggingWithRUMContextIntegration?,
        rumErrorsIntegration: LoggingWithRUMErrorsIntegration?,
        activeSpanIntegration: LoggingWithActiveSpanIntegration?
    ) {
        self.core = core
        self.configuration = configuration
        self.dateProvider = dateProvider
        self.queue = DispatchQueue(
            label: "com.datadoghq.logger-\(configuration.loggerName)",
            target: .global(qos: .userInteractive)
        )
        self.builder = LogEventBuilder(
            service: configuration.service,
            loggerName: configuration.loggerName,
            sendNetworkInfo: configuration.sendNetworkInfo,
            eventMapper: configuration.eventMapper
        )
        self.rumContextIntegration = rumContextIntegration
        self.rumErrorsIntegration = rumErrorsIntegration
        self.activeSpanIntegration = activeSpanIntegration
    }

    // MARK: - Attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        queue.async { self.unsafeAttributes[key] = value }
    }

    func removeAttribute(forKey key: AttributeKey) {
        queue.async { self.unsafeAttributes.removeValue(forKey: key) }
    }

    // MARK: - Tags

    func addTag(withKey key: String, value: String) {
        queue.async { self.unsafeTags.insert("\(key):\(value)") }
    }

    func removeTag(withKey key: String) {
        queue.async { self.unsafeTags = self.unsafeTags.filter { !$0.hasPrefix("\(key):") } }
    }

    func add(tag: String) {
        queue.async { self.unsafeTags.insert(tag) }
    }

    func remove(tag: String) {
        queue.async { self.unsafeTags.remove(tag) }
    }

    // MARK: - Logging

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        guard level.rawValue >= configuration.threshold.rawValue else {
            return
        }

        // on user thread:
        let date = dateProvider.now
        let threadName = getCurrentThreadName()

        // SDK context must be requested on the user thread to ensure that it provides values
        // that are up-to-date for the caller.
        self.core.v1.scope(for: LoggingFeature.self)?.eventWriteContext { context, writer in
            var userAttributes: [String: Encodable] = [:]
            var internalAttributes: [String: Encodable] = [:]
            var userTags: Set<String> = []

            queue.sync {
                userAttributes = self.unsafeAttributes.merging(attributes ?? [:]) { $1 } // prefer message attributes
                userTags = self.unsafeTags

                if let rumContextAttributes = self.rumContextIntegration?.currentRUMContextAttributes {
                    internalAttributes.merge(rumContextAttributes) { $1 }
                }
                if let activeSpanAttributes = self.activeSpanIntegration?.activeSpanAttributes {
                    internalAttributes.merge(activeSpanAttributes) { $1 }
                }
            }

            let log = self.builder.createLogEvent(
                date: date,
                level: level,
                message: message,
                error: error.map { DDError(error: $0) },
                attributes: .init(
                    userAttributes: userAttributes,
                    internalAttributes: internalAttributes
                ),
                tags: userTags,
                context: context,
                threadName: threadName
            )

            if let log = log {
                writer.write(value: log)

                if log.status == .error || log.status == .critical {
                    self.rumErrorsIntegration?.addError(for: log)
                }
            }
        }
    }
}
