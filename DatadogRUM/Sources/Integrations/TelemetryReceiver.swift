/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class TelemetryReceiver: FeatureMessageReceiver {
    /// Maximum number of telemetry events allowed per RUM  sessions.
    static let maxEventsPerSessions: Int = 100

    let dateProvider: DateProvider

    let sampler: Sampler

    let configurationExtraSampler: Sampler
    let metricsExtraSampler: Sampler

    /// Keeps track of current session
    @ReadWriteLock
    private var currentSessionID: String?

    /// Keeps track of event's ids recorded in current RUM session.
    @ReadWriteLock
    private var eventIDs: Set<String> = []

    /// Number of events recorded in current  RUM session.
    @ReadWriteLock
    private var eventsCount: Int = 0

    /// Creates a RUM Telemetry instance.
    ///
    /// - Parameters:
    ///   - dateProvider: Current device time provider.
    ///   - sampler: Telemetry events sampler.
    ///   - configurationExtraSampler: Extra sampler for configuration events (applied on top of `sampler`).
    ///   - metricsExtraSampler: Extra sampler for metric events (applied on top of `sampler`).
    init(
        dateProvider: DateProvider,
        sampler: Sampler,
        configurationExtraSampler: Sampler,
        metricsExtraSampler: Sampler
    ) {
        self.dateProvider = dateProvider
        self.sampler = sampler
        self.configurationExtraSampler = configurationExtraSampler
        self.metricsExtraSampler = metricsExtraSampler
    }

    /// Receives a message from the bus.
    ///
    /// The receiver will only consume `TelemetryMessage`.
    ///
    /// - Parameters:
    ///   - message: The message to consume.
    ///   - core: The core sending the message.
    /// - Returns: `true` if the message is a `.telemetry` case.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .telemetry(telemetry) = message else {
            return false
        }

        return receive(telemetry: telemetry, from: core)
    }

    /// Receives a Telemetry message from the bus.
    ///
    /// - Parameter telemetry: The telemetry message to consume.
    /// - Returns: Always `true`.
    func receive(telemetry: TelemetryMessage, from core: DatadogCoreProtocol) -> Bool {
        switch telemetry {
        case let .debug(id, message, attributes):
            debug(id: id, message: message, attributes: attributes, in: core)
        case let .error(id, message, kind, stack):
            error(id: id, message: message, kind: kind, stack: stack, in: core)
        case .configuration(let configuration):
            send(configuration: configuration, in: core)
        case let .metric(name, attributes):
            metric(name: name, attributes: attributes, in: core)
        }

        return true
    }

    /// Sends a `TelemetryDebugEvent` event.
    /// see. https://github.com/DataDog/rum-events-format/blob/master/schemas/telemetry/debug-schema.json
    ///
    /// The current RUM context info is applied if available, including session ID, view ID,
    /// and action ID.
    ///
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: The debug message.
    ///   - attributes: Custom attributes attached to the log (optional).
    private func debug(id: String, message: String, attributes: [String: Encodable]?, in core: DatadogCoreProtocol) {
        let date = dateProvider.now

        record(event: id, in: core) { context, writer in
            let rumAttributes: [String: String?]? = context.featuresAttributes[RUMFeature.name]?.ids
            let rum = rumAttributes?.compactMapValues { $0 }
            let applicationId = rum?[RUMContextAttributes.IDs.applicationID]
            let sessionId = rum?[RUMContextAttributes.IDs.sessionID]
            let viewId = rum?[RUMContextAttributes.IDs.viewID]
            let actionId = rum?[RUMContextAttributes.IDs.userActionID]

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: applicationId.map { .init(id: $0) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    message: message,
                    telemetryInfo: attributes ?? [:]
                ),
                version: context.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    /// Sends a `TelemetryErrorEvent` event.
    /// see. https://github.com/DataDog/rum-events-format/blob/master/schemas/telemetry/error-schema.json
    ///
    /// The current RUM context info is applied if available, including session ID, view ID,
    /// and action ID.
    ///
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: Body of the log
    ///   - kind: The error type or kind (or code in some cases).
    ///   - stack: The stack trace or the complementary information about the error.
    private func error(id: String, message: String, kind: String?, stack: String?, in core: DatadogCoreProtocol) {
        let date = dateProvider.now

        record(event: id, in: core) { context, writer in
            let rumAttributes: [String: String?]? = context.featuresAttributes[RUMFeature.name]?.ids
            let attributes = rumAttributes?.compactMapValues { $0 }
            let applicationId = attributes?[RUMContextAttributes.IDs.applicationID]
            let sessionId = attributes?[RUMContextAttributes.IDs.sessionID]
            let viewId = attributes?[RUMContextAttributes.IDs.viewID]
            let actionId = attributes?[RUMContextAttributes.IDs.userActionID]

            let event = TelemetryErrorEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: applicationId.map { .init(id: $0) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(error: .init(kind: kind, stack: stack), message: message),
                version: context.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    /// Sends the configuration telemetry.
    ///
    /// The configuration can be partial, the telemetry should support accumulation of
    /// configuration for lazy initialization of the SDK.
    ///
    /// - Parameter configuration: The SDK configuration.
    private func send(configuration: DatadogInternal.ConfigurationTelemetry, in core: DatadogCoreProtocol) {
        guard configurationExtraSampler.sample() else {
            return
        }

        let date = dateProvider.now

        self.record(event: "_dd.configuration", in: core) { context, writer in
            let rumAttributes: [String: String?]? = context.featuresAttributes[RUMFeature.name]?.ids
            let attributes = rumAttributes?.compactMapValues { $0 }
            let applicationId = attributes?[RUMContextAttributes.IDs.applicationID]
            let sessionId = attributes?[RUMContextAttributes.IDs.sessionID]
            let viewId = attributes?[RUMContextAttributes.IDs.viewID]
            let actionId = attributes?[RUMContextAttributes.IDs.userActionID]

            let event = TelemetryConfigurationEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: applicationId.map { .init(id: $0) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(configuration: .init(configuration)),
                version: context.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func metric(name: String, attributes: [String: Encodable], in core: DatadogCoreProtocol) {
        guard metricsExtraSampler.sample() else {
            return
        }

        let date = dateProvider.now

        record(event: nil, in: core) { context, writer in
            let rumAttributes: [String: String?]? = context.featuresAttributes[RUMFeature.name]?.ids
            let rum = rumAttributes?.compactMapValues { $0 }
            let applicationId = rum?[RUMContextAttributes.IDs.applicationID]
            let sessionId = rum?[RUMContextAttributes.IDs.sessionID]
            let viewId = rum?[RUMContextAttributes.IDs.viewID]
            let actionId = rum?[RUMContextAttributes.IDs.userActionID]

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: applicationId.map { .init(id: $0) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    message: "[Mobile Metric] \(name)",
                    telemetryInfo: attributes
                ),
                version: context.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func record(event id: String?, in core: DatadogCoreProtocol, operation: @escaping (DatadogContext, Writer) -> Void) {
        guard
            let rum = core.scope(for: RUMFeature.name),
            sampler.sample()
        else {
            return
        }

        rum.eventWriteContext { context, writer in
            // reset recorded events on session renewal
            let rumAttributes: [String: String?]? = context.featuresAttributes[RUMFeature.name]?.ids
            let attributes = rumAttributes?.compactMapValues { $0 }
            let sessionId = attributes?[RUMContextAttributes.IDs.sessionID]

            if sessionId != self.currentSessionID {
                self.currentSessionID = sessionId
                self.eventIDs = []
                self.eventsCount = 0
            }

            // record up to `maxEventsPerSessions`, discard duplicates for events with `id`
            if self.eventsCount < TelemetryReceiver.maxEventsPerSessions {
                if id == nil {
                    self.eventsCount += 1
                    operation(context, writer)
                } else if let eventID = id, !self.eventIDs.contains(eventID) {
                    self.eventIDs.insert(eventID)
                    self.eventsCount += 1
                    operation(context, writer)
                }
            }
        }
    }
}

private extension TelemetryConfigurationEvent.Telemetry.Configuration {
    init(_ configuration: DatadogInternal.ConfigurationTelemetry) {
        self.init(
            actionNameAttribute: nil,
            allowFallbackToLocalStorage: nil,
            allowUntrustedEvents: nil,
            batchSize: configuration.batchSize,
            batchUploadFrequency: configuration.batchUploadFrequency,
            dartVersion: configuration.dartVersion,
            defaultPrivacyLevel: nil,
            forwardConsoleLogs: nil,
            forwardErrorsToLogs: nil,
            forwardReports: nil,
            initializationType: nil,
            mobileVitalsUpdatePeriod: configuration.mobileVitalsUpdatePeriod,
            premiumSampleRate: nil,
            reactNativeVersion: nil,
            reactVersion: nil,
            replaySampleRate: nil,
            selectedTracingPropagators: nil,
            sessionReplaySampleRate: nil,
            sessionSampleRate: configuration.sessionSampleRate,
            silentMultipleInit: nil,
            telemetryConfigurationSampleRate: nil,
            telemetrySampleRate: configuration.telemetrySampleRate,
            traceSampleRate: configuration.traceSampleRate,
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackCrossPlatformLongTasks: configuration.trackCrossPlatformLongTasks,
            trackErrors: configuration.trackErrors,
            trackFlutterPerformance: configuration.trackFlutterPerformance,
            trackFrustrations: configuration.trackFrustrations,
            trackInteractions: configuration.trackInteractions,
            trackLongTask: configuration.trackLongTask,
            trackNativeErrors: nil,
            trackNativeLongTasks: configuration.trackNativeLongTasks,
            trackNativeViews: configuration.trackNativeViews,
            trackNetworkRequests: configuration.trackNetworkRequests,
            trackResources: nil,
            trackSessionAcrossSubdomains: nil,
            trackViewsManually: configuration.trackViewsManually,
            useAllowedTracingOrigins: nil,
            useAllowedTracingUrls: nil,
            useBeforeSend: nil,
            useCrossSiteSessionCookie: nil,
            useExcludedActivityUrls: nil,
            useFirstPartyHosts: configuration.useFirstPartyHosts,
            useLocalEncryption: configuration.useLocalEncryption,
            useProxy: configuration.useProxy,
            useSecureSessionCookie: nil,
            useTracing: configuration.useTracing,
            useWorkerUrl: nil,
            viewTrackingStrategy: nil
        )
    }
}
