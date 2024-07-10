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

    /// RUM feature scope.
    let featureScope: FeatureScope
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
    ///   - featureScope: RUM feature scope.
    ///   - dateProvider: Current device time provider.
    ///   - sampler: Telemetry events sampler.
    ///   - configurationExtraSampler: Extra sampler for configuration events (applied on top of `sampler`).
    ///   - metricsExtraSampler: Extra sampler for metric events (applied on top of `sampler`).
    init(
        featureScope: FeatureScope,
        dateProvider: DateProvider,
        sampler: Sampler,
        configurationExtraSampler: Sampler,
        metricsExtraSampler: Sampler
    ) {
        self.featureScope = featureScope
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

        return receive(telemetry: telemetry)
    }

    /// Receives a Telemetry message from the bus.
    ///
    /// - Parameter telemetry: The telemetry message to consume.
    /// - Returns: Always `true`.
    private func receive(telemetry: TelemetryMessage) -> Bool {
        switch telemetry {
        case let .debug(id, message, attributes):
            debug(id: id, message: message, attributes: attributes)
        case let .error(id, message, kind, stack):
            error(id: id, message: message, kind: kind, stack: stack)
        case .configuration(let configuration):
            send(configuration: configuration)
        case let .metric(name, attributes):
            metric(name: name, attributes: attributes)
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
    private func debug(id: String, message: String, attributes: [String: Encodable]?) {
        let date = dateProvider.now

        record(event: id) { context, writer in
            let rum = try? context.baggages[RUMFeature.name]?.decode(type: RUMCoreContext.self)

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    message: message,
                    os: .init(context.device),
                    telemetryInfo: attributes ?? [:]
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
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
    private func error(id: String, message: String, kind: String, stack: String) {
        let date = dateProvider.now

        record(event: id) { context, writer in
            let rum = try? context.baggages[RUMFeature.name]?.decode(type: RUMCoreContext.self)

            let event = TelemetryErrorEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    error: .init(kind: kind, stack: stack),
                    message: message,
                    os: .init(context.device),
                    telemetryInfo: [:]
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
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
    private func send(configuration: DatadogInternal.ConfigurationTelemetry) {
        guard configurationExtraSampler.sample() else {
            return
        }

        let date = dateProvider.now

        self.record(event: "_dd.configuration") { context, writer in
            let rum = try? context.baggages[RUMFeature.name]?.decode(type: RUMCoreContext.self)

            let event = TelemetryConfigurationEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    configuration: .init(configuration),
                    device: .init(context.device),
                    os: .init(context.device),
                    telemetryInfo: [:]
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func metric(name: String, attributes: [String: Encodable]) {
        guard metricsExtraSampler.sample() else {
            return
        }

        let date = dateProvider.now

        record(event: nil) { context, writer in
            let rum = try? context.baggages[RUMFeature.name]?.decode(type: RUMCoreContext.self)

            // Override sessionID using standard `SDKMetricFields`, otherwise use current RUM session ID:
            var attributes = attributes
            let sessionIDOverride: String? = attributes.removeValue(forKey: SDKMetricFields.sessionIDOverrideKey)?.dd.decode()
            let sessionID = sessionIDOverride ?? rum?.sessionID

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionID.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    message: "[Mobile Metric] \(name)",
                    os: .init(context.device),
                    telemetryInfo: attributes
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func record(event id: String?, operation: @escaping (DatadogContext, Writer) -> Void) {
        guard sampler.sample() else {
            return
        }

        featureScope.eventWriteContext { context, writer in
            // reset recorded events on session renewal
            let rum = try? context.baggages[RUMFeature.name]?.decode(type: RUMCoreContext.self)

            if rum?.sessionID != self.currentSessionID {
                self.currentSessionID = rum?.sessionID
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
            appHangThreshold: configuration.appHangThreshold,
            backgroundTasksEnabled: configuration.backgroundTasksEnabled,
            batchProcessingLevel: configuration.batchProcessingLevel,
            batchSize: configuration.batchSize,
            batchUploadFrequency: configuration.batchUploadFrequency,
            compressIntakeRequests: nil,
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
            storeContextsAcrossPages: nil,
            telemetryConfigurationSampleRate: nil,
            telemetrySampleRate: configuration.telemetrySampleRate,
            telemetryUsageSampleRate: nil,
            traceSampleRate: configuration.traceSampleRate,
            tracerApi: configuration.tracerAPI,
            tracerApiVersion: configuration.tracerAPIVersion,
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackCrossPlatformLongTasks: configuration.trackCrossPlatformLongTasks,
            trackErrors: configuration.trackErrors,
            trackFlutterPerformance: configuration.trackFlutterPerformance,
            trackFrustrations: configuration.trackFrustrations,
            // `track_interactions` is deprecated in favor of `track_user_interactions`.
            // We still send it for backward compatibility
            trackInteractions: configuration.trackUserInteractions,
            trackLongTask: configuration.trackLongTask,
            trackNativeErrors: nil,
            trackNativeLongTasks: configuration.trackNativeLongTasks,
            trackNativeViews: configuration.trackNativeViews,
            trackNetworkRequests: configuration.trackNetworkRequests,
            trackResources: nil,
            trackSessionAcrossSubdomains: nil,
            trackUserInteractions: configuration.trackUserInteractions,
            trackViewsManually: configuration.trackViewsManually,
            trackingConsent: nil,
            unityVersion: configuration.unityVersion,
            useAllowedTracingOrigins: nil,
            useAllowedTracingUrls: nil,
            useBeforeSend: nil,
            useCrossSiteSessionCookie: nil,
            useExcludedActivityUrls: nil,
            useFirstPartyHosts: configuration.useFirstPartyHosts,
            useLocalEncryption: configuration.useLocalEncryption,
            usePartitionedCrossSiteSessionCookie: nil,
            useProxy: configuration.useProxy,
            useSecureSessionCookie: nil,
            useTracing: configuration.useTracing,
            useWorkerUrl: nil,
            viewTrackingStrategy: nil
        )
    }
}

fileprivate extension RUMTelemetryDevice {
    init(_ device: DeviceInfo) {
        self.init(
            architecture: device.architecture,
            brand: device.brand,
            model: device.model
        )
    }
}

fileprivate extension RUMTelemetryOperatingSystem {
    init(_ device: DeviceInfo) {
        self.init(
            build: device.osBuildNumber,
            name: device.osName,
            version: device.osVersion
        )
    }
}
