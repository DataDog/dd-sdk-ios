/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

/// Private message-bus metadata. It is removed by RUM before customer attributes
/// are written and does not change the public or intake event format.
private let rumErrorTargetViewIDAttribute = "_dd.internal.rum.error.target_view_id"
private let rumErrorTargetActionIDAttribute = "_dd.internal.rum.error.target_action_id"
private let rumErrorTargetSceneIDAttribute = "_dd.internal.rum.error.target_scene_id"
private let rumErrorCapturedContextAttribute = "_dd.internal.rum.error.context_captured"

/// `Logger` sending logs to Datadog.
internal final class RemoteLogger: LoggerProtocol, Sendable {
    struct Configuration: @unchecked Sendable {
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

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        internalLog(level: level, message: message, error: error.map { DDError(error: $0) }, attributes: attributes)
    }

    func internalLog(level: LogLevel, message: String, error: DDError?, attributes: [String: Encodable]?, completionHandler: @escaping CompletionHandler = NOPCompletionHandler) {
        guard configuration.sampler.sample() else {
            return
        }
        guard level.rawValue >= configuration.threshold.rawValue else {
            return
        }

        // on user thread:
        let date = dateProvider.now
        let threadName = Thread.current.dd.name
        let rumContextHandoff = RUMContextHandoff.current

        // capture current tags and attributes before opening the write event context
        let tags = loggerTags.getTags()
        let globalAttributes = globalAttributes.getAttributes()
        let loggerAttributes = loggerAttributes.getAttributes()
        var logAttributes = attributes

        let errorFingerprint: String? = logAttributes?.removeValue(forKey: Logs.Attributes.errorFingerprint)?.dd.decode()
        let addBinaryImages = logAttributes?.removeValue(forKey: CrossPlatformAttributes.includeBinaryImages)?.dd.decode() ?? false
        let userAttributes = loggerAttributes
            .merging(logAttributes ?? [:]) { $1 } // prefer `logAttributes``

        let combinedAttributes: [String: any Encodable] = globalAttributes
            .merging(userAttributes) { $1 } // prefer `userAttribute`

        // SDK context must be requested on the user thread to ensure that it provides values
        // that are up-to-date for the caller.
        featureScope.eventWriteContext { [weak self] context, writer in
            guard let self else {
                return
            }

            var internalAttributes: [String: Encodable] = [:]
            var rumViewID: String?
            var rumActionID: String?
            // A present handoff with no RUM snapshot means the source scene is
            // known but its view is not ready. Preserve that fact for the
            // mirrored RUM error instead of falling back to another window.
            var didCaptureRUMContext = rumContextHandoff != nil

            // When bundle with RUM is enabled, link RUM context (if available):
            var rum = rumContextHandoff != nil
                ? rumContextHandoff?.rumContext
                : context.additionalContext(ofType: RUMCoreContext.self)
            if rumContextHandoff?.hasPendingUserAction == true {
                rum = mergeAcceptedUIEventAction(
                    into: rum,
                    from: context.additionalContext(ofType: RUMCoreContext.self),
                    excluding: rumContextHandoff?.excludedUserActionID
                )
            }
            if self.rumContextIntegration, let rum, rum.sessionSampler.isSampled {
                internalAttributes[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
                internalAttributes[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
                internalAttributes[LogEvent.Attributes.RUM.viewID] = rum.viewID
                internalAttributes[LogEvent.Attributes.RUM.actionID] = rum.userActionID
                rumViewID = rum.viewID.flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
                rumActionID = rum.userActionID.flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
                // A normal core snapshot with no view is not an authoritative
                // absence: RUM's legacy off-view / background-event handling
                // must still decide where the mirrored error belongs. Only a
                // concrete view or the explicit UI-event tri-state handoff is
                // frozen for delayed message-bus delivery.
                didCaptureRUMContext = rumContextHandoff != nil || rumViewID != nil
            }

            // When bundle with Trace is enabled, link Trace context (if available):
            if self.activeSpanIntegration, let spanContext = context.additionalContext(ofType: TraceCoreContext.Span.self) {
                internalAttributes[LogEvent.Attributes.Trace.traceID] = spanContext.traceID
                internalAttributes[LogEvent.Attributes.Trace.spanID] = spanContext.spanID
            }

            // When binary images are requested, add them
            var binaryImages: [BinaryImage]?
            if addBinaryImages {
                do {
                    binaryImages = try self.backtraceReporter?.binaryImages()
                } catch {
                    self.featureScope.telemetry.error(error)
                }
            }

            let builder = LogEventBuilder(
                service: self.configuration.service ?? context.service,
                loggerName: self.configuration.name,
                networkInfoEnabled: self.configuration.networkInfoEnabled,
                eventMapper: self.configuration.eventMapper
            )

            builder.createLogEvent(
                date: date,
                level: level,
                message: message,
                error: error,
                errorFingerprint: errorFingerprint,
                binaryImages: binaryImages,
                attributes: .init(
                    userAttributes: combinedAttributes,
                    internalAttributes: internalAttributes
                ),
                tags: tags,
                context: context,
                threadName: threadName
            ) { log in
                writer.write(value: log, completion: completionHandler)

                guard log.status == .error || log.status == .critical else {
                    return
                }

                // Add back in fingerprint and error source type
                var busCombinedAttributes = combinedAttributes
                // These keys are an SDK-private routing envelope. Customer
                // attributes with the same spelling must never become control
                // data for ErrorMessageReceiver.
                busCombinedAttributes.removeValue(forKey: rumErrorTargetViewIDAttribute)
                busCombinedAttributes.removeValue(forKey: rumErrorTargetActionIDAttribute)
                busCombinedAttributes.removeValue(forKey: rumErrorTargetSceneIDAttribute)
                busCombinedAttributes.removeValue(forKey: rumErrorCapturedContextAttribute)
                if let errorSourcetype = error?.sourceType {
                    busCombinedAttributes[CrossPlatformAttributes.errorSourceType] = errorSourcetype
                }
                if let errorFingerprint = errorFingerprint {
                    busCombinedAttributes[Logs.Attributes.errorFingerprint] = errorFingerprint
                }
                if let rumViewID {
                    busCombinedAttributes[rumErrorTargetViewIDAttribute] = rumViewID
                }
                if let rumActionID {
                    busCombinedAttributes[rumErrorTargetActionIDAttribute] = rumActionID
                }
                if let uiEventSceneIdentifier = rumContextHandoff?.sceneIdentifier {
                    busCombinedAttributes[rumErrorTargetSceneIDAttribute] = uiEventSceneIdentifier
                }
                if didCaptureRUMContext {
                    busCombinedAttributes[rumErrorCapturedContextAttribute] = true
                }

                self.featureScope.send(
                    message: .payload(
                        RUMErrorMessage(
                            time: date,
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
    }
}

private func mergeAcceptedUIEventAction(
    into captured: RUMCoreContext?,
    from current: RUMCoreContext?,
    excluding excludedUserActionID: String?
) -> RUMCoreContext? {
    guard let captured,
          let current,
          let currentActionID = current.userActionID,
          UUID(uuidString: currentActionID) != nil,
          currentActionID != excludedUserActionID else {
        return captured
    }

    guard captured.applicationID == current.applicationID,
          captured.sessionID == current.sessionID,
          captured.viewID == current.viewID else {
        return captured
    }
    return RUMCoreContext(
        applicationID: captured.applicationID,
        sessionID: captured.sessionID,
        sessionSampler: captured.sessionSampler,
        viewID: captured.viewID,
        userActionID: currentActionID,
        viewServerTimeOffset: captured.viewServerTimeOffset,
        viewPath: captured.viewPath,
        viewName: captured.viewName
    )
}

extension RemoteLogger: InternalLoggerProtocol {
    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?
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

        internalLog(level: level, message: message, error: ddError, attributes: logAttributes)
    }

    func critical(
        message: String,
        error: Error?,
        attributes: [String: Encodable]?,
        completionHandler: @escaping CompletionHandler
    ) {
        internalLog(
            level: .critical,
            message: message,
            error: error.map { DDError(error: $0) },
            attributes: attributes,
            completionHandler: completionHandler
        )
    }
}
