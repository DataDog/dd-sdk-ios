/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `Logger` sending logs to Datadog.
internal final class RemoteLogger: LoggerProtocol, Sendable {
    struct Configuration: Sendable {
        /// The `service` value for logs.
        /// See: [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
        let service: String?
        /// The `logger.name` value for logs.
        let name: String?
        /// Whether to send the network info in `network.client.*` log attributes.
        let networkInfoEnabled: Bool
        /// Only logs equal or above this threshold will be sent.
        let threshold: LogLevel
        /// Allows for modifying (or dropping) logs before they get sent.
        let eventMapper: LogEventMapper?
        /// Sampler for remote logger. Default is using `100.0` sampling rate.
        let sampler: Sampler
    }

    /// Logs feature scope.
    let featureScope: FeatureScope
    /// Configuration specific to this logger.
    let configuration: Configuration
    /// Date provider for logs.
    private let dateProvider: DateProvider
    /// Integration with RUM. It is used to correlate Logs with RUM events by injecting RUM context to `LogEvent`.
    /// Can be `false` if the integration is disabled for this logger.
    internal let rumContextIntegration: Bool
    /// Integration with Tracing. It is used to correlate Logs with Spans by injecting `Span` context to `LogEvent`.
    /// Can be `false` if the integration is disabled for this logger.
    internal let activeSpanIntegration: Bool
    /// Global attributes shared with all logger instances.
    private let globalAttributes: SynchronizedAttributes
    /// Logger-specific attributes.
    private let loggerAttributes: SynchronizedAttributes
    /// Logger-specific tags.
    private let loggerTags: SynchronizedTags
    /// Backtrace reporter for attaching binary images to cross-platform errors.
    private let backtraceReporter: BacktraceReporting?

    init(
        featureScope: FeatureScope,
        globalAttributes: SynchronizedAttributes,
        configuration: Configuration,
        dateProvider: DateProvider,
        rumContextIntegration: Bool,
        activeSpanIntegration: Bool,
        backtraceReporter: BacktraceReporting?
    ) {
        self.featureScope = featureScope
        self.globalAttributes = globalAttributes
        self.loggerAttributes = SynchronizedAttributes(attributes: [:])
        self.loggerTags = SynchronizedTags(tags: [])
        self.configuration = configuration
        self.dateProvider = dateProvider
        self.rumContextIntegration = rumContextIntegration
        self.activeSpanIntegration = activeSpanIntegration
        self.backtraceReporter = backtraceReporter
    }

    // MARK: - Attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        loggerAttributes.addAttribute(key: key, value: value)
    }

    func removeAttribute(forKey key: AttributeKey) {
        loggerAttributes.removeAttribute(forKey: key)
    }

    // MARK: - Tags

    func addTag(withKey key: String, value: String) {
        loggerTags.addTag("\(key):\(value)")
    }

    func removeTag(withKey key: String) {
        loggerTags.removeTags(where: { $0.hasPrefix("\(key):") })
    }

    func add(tag: String) {
        loggerTags.addTag(tag)
    }

    func remove(tag: String) {
        loggerTags.removeTag(tag)
    }

    // MARK: - Logging

    /// Holds all state captured synchronously on the user thread before
    /// handing off to the async write path.
    private struct PreparedLogContext {
        let date: Date
        let threadName: String
        let level: LogLevel
        let message: String
        let error: DDError?
        let tags: Set<String>
        let combinedAttributes: [String: AttributeValue]
        let errorFingerprint: String?
        let addBinaryImages: Bool
    }

    /// Captures all user-thread-sensitive state synchronously.
    /// Returns `nil` if the log should be dropped (sampled out or below threshold).
    private func prepareLogContext(
        level: LogLevel,
        message: String,
        error: DDError?,
        attributes: [String: Encodable & Sendable]?
    ) -> PreparedLogContext? {
        guard configuration.sampler.sample() else { return nil }
        guard level.rawValue >= configuration.threshold.rawValue else { return nil }

        // on user thread:
        let date = dateProvider.now
        let threadName = Thread.current.dd.name

        // capture current tags and attributes before handing off to the async write path
        let tags = loggerTags.getTags()
        let globalAttributes = globalAttributes.getAttributes()
        let loggerAttributes = loggerAttributes.getAttributes()
        var logAttributes = attributes

        let errorFingerprint: String? = logAttributes?.removeValue(forKey: Logs.Attributes.errorFingerprint)?.dd.decode()
        let addBinaryImages = logAttributes?.removeValue(forKey: CrossPlatformAttributes.includeBinaryImages)?.dd.decode() ?? false
        let userAttributes = loggerAttributes
            .merging(logAttributes ?? [:]) { $1 } // prefer `logAttributes`

        let combinedAttributes: [String: AttributeValue] = globalAttributes
            .merging(userAttributes) { $1 }

        return PreparedLogContext(
            date: date,
            threadName: threadName,
            level: level,
            message: message,
            error: error,
            tags: tags,
            combinedAttributes: combinedAttributes,
            errorFingerprint: errorFingerprint,
            addBinaryImages: addBinaryImages
        )
    }

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable & Sendable]?) {
        guard let prepared = prepareLogContext(level: level, message: message, error: error.map { DDError(error: $0) }, attributes: attributes) else {
            return
        }
        Task { [weak self] in
            await self?.writeLog(prepared)
        }
    }

    /// Async write path — bridges `eventWriteContext`, builds the event, and writes it.
    private func writeLog(_ prepared: PreparedLogContext) async {
        guard let (context, writer) = await featureScope.eventWriteContext() else {
            return
        }

        var internalAttributes: [String: AttributeValue] = [:]

        // When bundle with RUM is enabled, link RUM context (if available):
        if rumContextIntegration, let rum = context.additionalContext(ofType: RUMCoreContext.self) {
            internalAttributes[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
            internalAttributes[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
            internalAttributes[LogEvent.Attributes.RUM.viewID] = rum.viewID
            internalAttributes[LogEvent.Attributes.RUM.actionID] = rum.userActionID
        }

        // When bundle with Trace is enabled, link Trace context (if available):
        if activeSpanIntegration, let spanContext = context.additionalContext(ofType: TraceCoreContext.Span.self) {
            internalAttributes[LogEvent.Attributes.Trace.traceID] = spanContext.traceID
            internalAttributes[LogEvent.Attributes.Trace.spanID] = spanContext.spanID
        }

        // When binary images are requested, add them
        var binaryImages: [BinaryImage]?
        if prepared.addBinaryImages {
            // TODO: RUM-4072 Replace full backtrace reporter with simpler binary image fetcher
            binaryImages = try? backtraceReporter?.generateBacktrace()?.binaryImages
        }

        let builder = LogEventBuilder(
            service: configuration.service ?? context.service,
            loggerName: configuration.name,
            networkInfoEnabled: configuration.networkInfoEnabled,
            eventMapper: configuration.eventMapper
        )

        guard let log = await builder.createLogEvent(
            date: prepared.date,
            level: prepared.level,
            message: prepared.message,
            error: prepared.error,
            errorFingerprint: prepared.errorFingerprint,
            binaryImages: binaryImages,
            attributes: .init(
                userAttributes: prepared.combinedAttributes,
                internalAttributes: internalAttributes
            ),
            tags: prepared.tags,
            context: context,
            threadName: prepared.threadName
        ) else {
            return
        }

        writer.write(value: log)

        guard log.status == .error || log.status == .critical else {
            return
        }

        // Add back in fingerprint and error source type
        var busCombinedAttributes = prepared.combinedAttributes
        if let errorSourcetype = prepared.error?.sourceType {
            busCombinedAttributes[CrossPlatformAttributes.errorSourceType] = errorSourcetype
        }
        if let errorFingerprint = prepared.errorFingerprint {
            busCombinedAttributes[Logs.Attributes.errorFingerprint] = errorFingerprint
        }

        featureScope.send(
            message: .payload(
                RUMErrorMessage(
                    time: prepared.date,
                    message: log.error?.message ?? log.message,
                    source: "logger",
                    type: log.error?.kind,
                    stack: log.error?.stack,
                    attributes: busCombinedAttributes,
                    binaryImages: binaryImages
                )
            )
        )
    }
}

extension RemoteLogger: InternalLoggerProtocol {
    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: AttributeValue]?
    ) {
        var ddError: DDError?
        // Find and remove source_type if it's in the attributes
        var logAttributes = attributes
        let sourceType = logAttributes?.removeValue(forKey: CrossPlatformAttributes.errorSourceType) as? String

        if errorKind != nil || errorMessage != nil || stackTrace != nil {
            // Cross platform frameworks don't necessarily send all values for errors. Send empty strings
            // for any values that are empty.
            ddError = DDError(type: errorKind ?? "", message: errorMessage ?? "", stack: stackTrace ?? "", sourceType: sourceType ?? "ios")
        }

        guard let prepared = prepareLogContext(level: level, message: message, error: ddError, attributes: logAttributes) else {
            return
        }
        Task { [weak self] in
            await self?.writeLog(prepared)
        }
    }

    func critical(
        message: String,
        error: Error?,
        attributes: [String: AttributeValue]?
    ) async {
        guard let prepared = prepareLogContext(level: .critical, message: message, error: error.map { DDError(error: $0) }, attributes: attributes) else {
            return
        }
        await writeLog(prepared)
    }
}
