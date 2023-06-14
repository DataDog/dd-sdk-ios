/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal typealias RUMFeature = DatadogRUMFeature

// TODO: RUMM-2922 Rename to `RUMFeature`
internal final class DatadogRUMFeature: DatadogRemoteFeature {
    static let name = "rum"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let monitor: RUMMonitorProtocol

    let instrumentation: RUMInstrumentation
    /// Telemetry target for this instance of RUM feature.
    let telemetry: TelemetryCore

    internal struct LaunchArguments {
        static let DebugRUM = "DD_DEBUG_RUM"
    }

    convenience init(in core: DatadogCoreProtocol, configuration: RUMConfiguration) throws {
        try self.init(
            with: Monitor(
                core: core,
                dependencies: RUMScopeDependencies(
                    core: core,
                    configuration: configuration
                ),
                dateProvider: configuration.dateProvider
            ),
            in: core,
            configuration: configuration
        )
    }

    private init(
        with monitor: Monitor,
        in core: DatadogCoreProtocol,
        configuration: RUMConfiguration
    ) throws {
        let instrumentation = RUMInstrumentation(
            configuration: configuration.instrumentation,
            dateProvider: configuration.dateProvider
        )
        instrumentation.publish(to: monitor)

        if let firstPartyHosts = configuration.firstPartyHosts {
            let urlSessionHandler = URLSessionRUMResourcesHandler(
                dateProvider: configuration.dateProvider,
                rumAttributesProvider: configuration.rumAttributesProvider,
                distributedTracing: .init(
                    sampler: configuration.tracingSampler,
                    firstPartyHosts: firstPartyHosts,
                    traceIDGenerator: configuration.traceIDGenerator
                )
            )

            urlSessionHandler.publish(to: monitor)
            try core.register(urlSessionHandler: urlSessionHandler)
        }

        monitor.notifySDKInit()

        // Now that RUM is initialized, override the debugRUM value
        let debugRumOverride = configuration.processInfo.arguments.contains(LaunchArguments.DebugRUM)
        if debugRumOverride {
            consolePrint("⚠️ Overriding RUM debugging due to \(LaunchArguments.DebugRUM) launch argument")
            monitor.setDebugging(enabled: true)
        }

        let telemetry = TelemetryCore(core: core)
        telemetry.configuration(
            mobileVitalsUpdatePeriod: configuration.vitalsFrequency?.toInt64Milliseconds,
            sessionSampleRate: Int64(withNoOverflow: configuration.sessionSampler.samplingRate),
            telemetrySampleRate: Int64(withNoOverflow: configuration.telemetrySampler.samplingRate),
            traceSampleRate: Int64(withNoOverflow: configuration.tracingSampler.samplingRate),
            trackBackgroundEvents: configuration.backgroundEventTrackingEnabled,
            trackFrustrations: configuration.frustrationTrackingEnabled,
            trackInteractions: configuration.instrumentation.uiKitRUMUserActionsPredicate != nil,
            trackLongTask: configuration.instrumentation.longTaskThreshold != nil,
            trackNativeLongTasks: configuration.instrumentation.longTaskThreshold != nil,
            trackNativeViews: configuration.instrumentation.uiKitRUMViewsPredicate != nil,
            trackNetworkRequests: configuration.firstPartyHosts != nil,
            useFirstPartyHosts: configuration.firstPartyHosts.map { !$0.hosts.isEmpty }
        )

        self.monitor = monitor
        self.instrumentation = instrumentation
        self.requestBuilder = RequestBuilder(customIntakeURL: configuration.customIntakeURL)
        self.messageReceiver = CombinedFeatureMessageReceiver(
            TelemetryReceiver(
                dateProvider: configuration.dateProvider,
                sampler: configuration.telemetrySampler,
                configurationExtraSampler: configuration.configurationTelemetrySampler
            ),
            ErrorMessageReceiver(monitor: monitor),
            WebViewEventReceiver(
                dateProvider: configuration.dateProvider,
                commandSubscriber: monitor
            ),
            CrashReportReceiver(
                applicationID: configuration.applicationID,
                dateProvider: configuration.dateProvider,
                sessionSampler: configuration.sessionSampler,
                backgroundEventTrackingEnabled: configuration.backgroundEventTrackingEnabled,
                uuidGenerator: configuration.uuidGenerator,
                ciTest: configuration.testExecutionId.map { .init(testExecutionId: $0) }
            )
        )
        self.telemetry = telemetry
    }
}

extension DatadogRUMFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        (monitor as? Monitor)?.queue.sync { }
    }
}
