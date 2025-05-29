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

    /// Sampler for all telemetry events.
    let sampler: Sampler
    /// Additional sampler for configuration telemetry events, applied in addition to the `sampler`.
    let configurationExtraSampler: Sampler

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
    init(
        featureScope: FeatureScope,
        dateProvider: DateProvider,
        sampler: Sampler,
        configurationExtraSampler: Sampler
    ) {
        self.featureScope = featureScope
        self.dateProvider = dateProvider
        self.sampler = sampler
        self.configurationExtraSampler = configurationExtraSampler
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
        case let .metric(metric):
            if sampled(event: metric) {
                send(metric: metric)
            }
        case .usage(let usage):
            if sampled(event: usage) {
                send(usage: usage)
            }
        }

        return true
    }

    private func sampled(event: SampledTelemetry) -> Bool {
        return Sampler(samplingRate: event.sampleRate).sample()
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
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                effectiveSampleRate: Double(self.sampler.samplingRate),
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
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryErrorEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                effectiveSampleRate: Double(self.sampler.samplingRate),
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

    private func send(usage: DatadogInternal.UsageTelemetry) {
        let date = dateProvider.now

        self.record(event: nil) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryUsageEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                effectiveSampleRate: Double(usage.sampleRate.composed(with: self.sampler.samplingRate)),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    os: .init(context.device),
                    usage: .init(usage),
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
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryConfigurationEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                effectiveSampleRate: Double(self.configurationExtraSampler.samplingRate.composed(with: self.sampler.samplingRate)),
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

    private func send(metric: MetricTelemetry) {
        let date = dateProvider.now

        record(event: nil) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            // Override sessionID using standard `SDKMetricFields`, otherwise use current RUM session ID:
            var attributes = metric.attributes
            let sessionIDOverride: String? = attributes.removeValue(forKey: SDKMetricFields.sessionIDOverrideKey)?.dd.decode()
            let sessionID = sessionIDOverride ?? rum?.sessionID

            // Override applicationID using standard `SDKMetricFields`, otherwise use current RUM application ID:
            let applicationIDOverride: String? = attributes.removeValue(forKey: SDKMetricFields.applicationIDOverrideKey)?.dd.decode()
            let applicationID = applicationIDOverride ?? rum?.applicationID

            // Calculates the composition of sample rates. The metric can have up to 3 layers of sampling.
            var effectiveSampleRate = metric.sampleRate.composed(with: self.sampler.samplingRate)
            if let headSampleRate = attributes.removeValue(forKey: SDKMetricFields.headSampleRate) as? SampleRate {
                effectiveSampleRate = effectiveSampleRate.composed(with: headSampleRate)
            }

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: applicationID.map { .init(id: $0) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
                effectiveSampleRate: Double(effectiveSampleRate),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionID.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    message: "[Mobile Metric] \(metric.name)",
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
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

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

private extension TelemetryUsageEvent.Telemetry.Usage {
    init(_ usage: UsageTelemetry) {
        switch usage.event {
        case .setTrackingConsent(let consent):
            self = .telemetryCommonFeaturesUsage(value: .setTrackingConsent(value: .init(trackingConsent: .init(consent: consent))))
        case .stopSession:
            self = .telemetryCommonFeaturesUsage(value: .stopSession(value: .init()))
        case .startView:
            self = .telemetryCommonFeaturesUsage(value: .startView(value: .init()))
        case .addAction:
            self = .telemetryCommonFeaturesUsage(value: .addAction(value: .init()))
        case .addError:
            self = .telemetryCommonFeaturesUsage(value: .addError(value: .init()))
        case .setGlobalContext:
            self = .telemetryCommonFeaturesUsage(value: .setGlobalContext(value: .init()))
        case .setUser:
            self = .telemetryCommonFeaturesUsage(value: .setUser(value: .init()))
        case .setAccount:
            self = .telemetryCommonFeaturesUsage(value: .setAccount(value: .init()))
        case .addFeatureFlagEvaluation:
            self = .telemetryCommonFeaturesUsage(value: .addFeatureFlagEvaluation(value: .init()))
        case .addViewLoadingTime(let viewLoadingTime):
            self = .telemetryMobileFeaturesUsage(
                value: .addViewLoadingTime(
                    value: .init(
                        noActiveView: viewLoadingTime.noActiveView,
                        noView: viewLoadingTime.noView,
                        overwritten: viewLoadingTime.overwritten
                    )
                )
            )
        }
    }
}

private extension TelemetryUsageEvent.Telemetry.Usage.TelemetryCommonFeaturesUsage.SetTrackingConsent.TrackingConsent {
    init(consent: DatadogInternal.TrackingConsent) {
        switch consent {
        case .granted:
            self = .granted
        case .notGranted:
            self = .notGranted
        case .pending:
            self = .pending
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
            imagePrivacyLevel: configuration.imagePrivacyLevel,
            initializationType: nil,
            invTimeThresholdMs: configuration.invTimeThresholdMs,
            isMainProcess: nil,
            mobileVitalsUpdatePeriod: configuration.mobileVitalsUpdatePeriod,
            premiumSampleRate: nil,
            reactNativeVersion: nil,
            reactVersion: nil,
            replaySampleRate: nil,
            selectedTracingPropagators: nil,
            sessionPersistence: nil,
            sessionReplaySampleRate: configuration.sessionReplaySampleRate,
            sessionSampleRate: configuration.sessionSampleRate,
            silentMultipleInit: nil,
            startRecordingImmediately: configuration.startRecordingImmediately,
            storeContextsAcrossPages: nil,
            telemetryConfigurationSampleRate: nil,
            telemetrySampleRate: configuration.telemetrySampleRate,
            telemetryUsageSampleRate: nil,
            textAndInputPrivacyLevel: configuration.textAndInputPrivacyLevel,
            tnsTimeThresholdMs: configuration.tnsTimeThresholdMs,
            touchPrivacyLevel: configuration.touchPrivacyLevel,
            traceSampleRate: configuration.traceSampleRate,
            tracerApi: configuration.tracerAPI,
            tracerApiVersion: configuration.tracerAPIVersion,
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackCrossPlatformLongTasks: configuration.trackCrossPlatformLongTasks,
            trackErrors: configuration.trackErrors,
            trackFeatureFlagsForEvents: nil,
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
