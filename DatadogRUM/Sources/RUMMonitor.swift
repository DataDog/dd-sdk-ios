/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

/// A class enabling Datadog RUM features.
///
/// `RUMMonitor` allows recording user events that can be explored and analyzed in Datadog Dashboards.
/// There can be only one active `RUMMonitor`, and it should be registered/retrieved through `Global.rum`:
///
///     import Datadog
///
///     // register
///     Global.rum = RUMMonitor.initialize()
///
///     // use
///     Global.rum.startView(...)
///
public class RUMMonitor {
    internal struct LaunchArguments {
        static let DebugRUM = "DD_DEBUG_RUM"
    }

    /// Initializes the Datadog RUM Monitor.
    // swiftlint:disable:next function_default_parameter_at_end
    public static func initialize(
        in core: DatadogCoreProtocol = CoreRegistry.default,
        configuration: RUMConfiguration
    ) throws {
        do {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `RUMMonitor.initialize()`."
                )
            }

            let feature = DatadogRUMFeature(in: core, configuration: configuration)
            try core.register(feature: feature)

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

                urlSessionHandler.publish(to: feature.monitor)
                try core.register(urlSessionHandler: urlSessionHandler)
            }

            feature.monitor.notifySDKInit()

            // Now that RUM is initialized, override the debugRUM value
            let debugRumOverride = configuration.processInfo.arguments.contains(LaunchArguments.DebugRUM)
            if debugRumOverride {
                consolePrint("⚠️ Overriding RUM debugging due to \(LaunchArguments.DebugRUM) launch argument")
                feature.monitor.debug = true
            }

            TelemetryCore(core: core)
                .configuration(
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
        } catch {
            consolePrint("\(error)")
            throw error
        }
    }

    public static func shared(in core: DatadogCoreProtocol = CoreRegistry.default) -> RUMMonitorProtocol {
        do {
            guard !(core is NOPDatadogCore) else {
                throw ProgrammerError(
                    description: "Datadog SDK must be initialized and RUM feature must be enabled before calling `RUMMonitor.shared(in:)`."
                )
            }
            guard let feature = core.get(feature: DatadogRUMFeature.self) else {
                throw ProgrammerError(
                    description: "RUM feature must be enabled before calling `RUMMonitor.shared(in:)`."
                )
            }

            return feature.monitor
        } catch {
            consolePrint("\(error)")
            return NOPRUMMonitor()
        }
    }
}
