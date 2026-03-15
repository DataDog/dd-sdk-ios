/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal actor TelemetryReceiver: FeatureMessageReceiver {
    /// Maximum number of telemetry events allowed per RUM  sessions.
    static let maxEventsPerSessions: Int = 100

    /// A name of the telemetry attribute set for all ERROR and DEBUG telemetry events (including metrics).
    /// The value of this attribute represents the number of milliseconds elapsed from the process start
    /// to the moment the telemetry event was recorded.
    static let uptimeAttributeName: String = "process_uptime"

    /// RUM feature scope.
    nonisolated let featureScope: FeatureScope
    nonisolated let dateProvider: DateProvider

    /// Sampler for all telemetry events.
    nonisolated let sampler: Sampler
    /// Additional sampler for configuration telemetry events, applied in addition to the `sampler`.
    nonisolated let configurationExtraSampler: Sampler

    private struct RecordState {
        var currentSessionID: String?
        var eventIDs: Set<String> = []
        var eventsCount: Int = 0
    }

    private var recordState = RecordState()

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
    /// - Parameter message: The message to consume.
    nonisolated func receive(message: FeatureMessage) {
        guard case let .telemetry(telemetry) = message else {
            return
        }

        receive(telemetry: telemetry)
    }

    /// Receives a Telemetry message from the bus.
    ///
    /// - Parameter telemetry: The telemetry message to consume.
    nonisolated private func receive(telemetry: TelemetryMessage) {
        switch telemetry {
        case let .debug(id, message, attributes):
            let date = dateProvider.now
            Task { await self.debugAsync(id: id, message: message, attributes: attributes, date: date) }
        case let .error(id, message, kind, stack):
            let date = dateProvider.now
            Task { await self.errorAsync(id: id, message: message, kind: kind, stack: stack, date: date) }
        case .configuration(let configuration):
            let date = dateProvider.now
            Task { await self.sendConfigurationAsync(configuration: configuration, date: date) }
        case let .metric(metric):
            // Skip upload_quality metrics — they are aggregated by TelemetryInterceptor
            guard metric.name != UploadQualityMetric.name else { return }
            if sampled(event: metric) {
                let date = dateProvider.now
                Task { await self.sendMetricAsync(metric: metric, date: date) }
            }
        case .usage(let usage):
            if sampled(event: usage) {
                let date = dateProvider.now
                Task { await self.sendUsageAsync(usage: usage, date: date) }
            }
        }
    }

    nonisolated private func sampled(event: SampledTelemetry) -> Bool {
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
    private func debugAsync(id: String, message: String, attributes: [String: AttributeValue]?, date: Date) async {
        await record(event: id) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let uptimeMs = date.timeIntervalSince(context.launchInfo.processLaunchDate).dd.toInt64Milliseconds
            var attributes = attributes ?? [:]
            attributes[TelemetryReceiver.uptimeAttributeName] = uptimeMs

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
                effectiveSampleRate: Double(self.sampler.samplingRate),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    message: message,
                    os: .init(osInfo: context.os),
                    telemetryInfo: attributes
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
    private func errorAsync(id: String, message: String, kind: String, stack: String, date: Date) async {
        await record(event: id) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let uptimeMs = date.timeIntervalSince(context.launchInfo.processLaunchDate).dd.toInt64Milliseconds
            let attributes: [String: AttributeValue] = [
                TelemetryReceiver.uptimeAttributeName: uptimeMs
            ]

            let event = TelemetryErrorEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
                effectiveSampleRate: Double(self.sampler.samplingRate),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    error: .init(kind: kind, stack: stack),
                    message: message,
                    os: .init(osInfo: context.os),
                    telemetryInfo: attributes
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func sendUsageAsync(usage: DatadogInternal.UsageTelemetry, date: Date) async {
        await record(event: nil) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryUsageEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
                effectiveSampleRate: Double(usage.sampleRate.composed(with: self.sampler.samplingRate)),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    os: .init(osInfo: context.os),
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
    private func sendConfigurationAsync(configuration: DatadogInternal.ConfigurationTelemetry, date: Date) async {
        guard configurationExtraSampler.sample() else {
            return
        }

        await record(event: "_dd.configuration") { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            let event = TelemetryConfigurationEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
                effectiveSampleRate: Double(self.configurationExtraSampler.samplingRate.composed(with: self.sampler.samplingRate)),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: rum.map { .init(id: $0.sessionID) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    configuration: .init(configuration),
                    device: .init(context.device),
                    os: .init(osInfo: context.os),
                    telemetryInfo: [:]
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func sendMetricAsync(metric: MetricTelemetry, date: Date) async {
        await record(event: nil) { context, writer in
            let rum = context.additionalContext(ofType: RUMCoreContext.self)

            var attributes = metric.attributes
            let sessionIDOverride: String? = attributes.removeValue(forKey: SDKMetricFields.sessionIDOverrideKey)?.dd.decode()
            let sessionID = sessionIDOverride ?? rum?.sessionID

            var effectiveSampleRate = metric.sampleRate.composed(with: self.sampler.samplingRate)
            if let headSampleRate = attributes.removeValue(forKey: SDKMetricFields.headSampleRate) as? SampleRate {
                effectiveSampleRate = effectiveSampleRate.composed(with: headSampleRate)
            }

            let uptimeMs = date.timeIntervalSince(context.launchInfo.processLaunchDate).dd.toInt64Milliseconds
            attributes[TelemetryReceiver.uptimeAttributeName] = uptimeMs

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: rum?.userActionID.map { .init(id: $0) },
                application: rum.map { .init(id: $0.applicationID) },
                date: date.addingTimeInterval(context.serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
                effectiveSampleRate: Double(effectiveSampleRate),
                experimentalFeatures: nil,
                service: "dd-sdk-ios",
                session: sessionID.map { .init(id: $0) },
                source: .init(rawValue: context.source) ?? .ios,
                telemetry: .init(
                    device: .init(context.device),
                    message: "[Mobile Metric] \(metric.name)",
                    os: .init(osInfo: context.os),
                    telemetryInfo: attributes
                ),
                version: context.sdkVersion,
                view: rum?.viewID.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    private func record(event id: String?, operation: (DatadogContext, Writer) -> Void) async {
        guard sampler.sample() else {
            return
        }

        guard let (context, writer) = await featureScope.eventWriteContext() else { return }

        let rum = context.additionalContext(ofType: RUMCoreContext.self)

        if rum?.sessionID != recordState.currentSessionID {
            recordState.currentSessionID = rum?.sessionID
            recordState.eventIDs = []
            recordState.eventsCount = 0
        }

        var shouldWrite = false
        if recordState.eventsCount < TelemetryReceiver.maxEventsPerSessions {
            if id == nil {
                recordState.eventsCount += 1
                shouldWrite = true
            } else if let eventID = id, !recordState.eventIDs.contains(eventID) {
                recordState.eventIDs.insert(eventID)
                recordState.eventsCount += 1
                shouldWrite = true
            }
        }

        if shouldWrite {
            operation(context, writer)
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
        case .addOperationStepVital(let addOperationStepVital):
            self = .telemetryCommonFeaturesUsage(
                value: .addOperationStepVital(
                    value: .init(
                        actionType: addOperationStepVital.actionType
                    )
                )
            )
        case .addGraphQLRequest:
            self = .telemetryCommonFeaturesUsage(value: .graphQLRequest(value: .init()))
        case .addViewLoadingTime(let viewLoadingTime):
            self = .telemetryCommonFeaturesUsage(value:
                    .addViewLoadingTime(value:
                            .init(
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
            swiftuiActionTrackingEnabled: configuration.swiftUIActionTrackingEnabled,
            swiftuiViewTrackingEnabled: configuration.swiftUIViewTrackingEnabled,
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
            logicalCpuCount: device.logicalCpuCount,
            model: device.model,
            totalRam: device.totalRam
        )
    }
}

fileprivate extension RUMTelemetryOperatingSystem {
    init(osInfo: OperatingSystem) {
        self.init(
            build: osInfo.build,
            name: osInfo.name,
            version: osInfo.version
        )
    }
}
