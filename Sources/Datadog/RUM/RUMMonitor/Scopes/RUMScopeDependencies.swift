/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMSessionListener = (String, Bool) -> Void

/// Dependency container for injecting components to `RUMScopes` hierarchy.
internal struct RUMScopeDependencies {
    struct VitalsReaders {
        let frequency: TimeInterval
        let cpu: SamplingBasedVitalReader
        let memory: SamplingBasedVitalReader
        let refreshRate: ContinuousVitalReader
    }

    let rumApplicationID: String
    let sessionSampler: Sampler
    /// The start time of the application, indicated as SDK init. Measured in device time (without NTP correction).
    let sdkInitDate: Date
    let backgroundEventTrackingEnabled: Bool
    let appStateListener: AppStateListening
    let deviceInfo: RUMDevice
    let osInfo: RUMOperatingSystem
    let launchTimeProvider: LaunchTimeProviderType
    let firstPartyURLsFilter: FirstPartyURLsFilter
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Integration with Crash Reporting. It updates the crash context with RUM info.
    /// `nil` if Crash Reporting feature is not enabled.
    let crashContextIntegration: RUMWithCrashContextIntegration?
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    /// Produces `RUMViewUpdatesThrottlerType` for each started RUM view scope.
    let viewUpdatesThrottlerFactory: () -> RUMViewUpdatesThrottlerType

    let vitalsReaders: VitalsReaders?
    let onSessionStart: RUMSessionListener?
}

internal extension RUMScopeDependencies {
    init(
        rumFeature: RUMFeature,
        crashReportingFeature: CrashReportingFeature?,
        context: DatadogV1Context,
        telemetry: Telemetry?
    ) {
        self.init(
            rumApplicationID: rumFeature.configuration.applicationID,
            sessionSampler: rumFeature.configuration.sessionSampler,
            sdkInitDate: context.sdkInitDate,
            backgroundEventTrackingEnabled: rumFeature.configuration.backgroundEventTrackingEnabled,
            appStateListener: context.appStateListener,
            deviceInfo: RUMDevice(
                from: context.mobileDevice,
                telemetry: telemetry
            ),
            osInfo: RUMOperatingSystem(from: context.mobileDevice),
            launchTimeProvider: context.launchTimeProvider,
            firstPartyURLsFilter: FirstPartyURLsFilter(hosts: rumFeature.configuration.firstPartyHosts),
            eventBuilder: RUMEventBuilder(
                eventsMapper: RUMEventsMapper(
                    viewEventMapper: rumFeature.configuration.viewEventMapper,
                    errorEventMapper: rumFeature.configuration.errorEventMapper,
                    resourceEventMapper: rumFeature.configuration.resourceEventMapper,
                    actionEventMapper: rumFeature.configuration.actionEventMapper,
                    longTaskEventMapper: rumFeature.configuration.longTaskEventMapper,
                    telemetry: telemetry
                )
            ),
            eventOutput: RUMEventFileOutput(
                fileWriter: rumFeature.storage.writer
            ),
            rumUUIDGenerator: rumFeature.configuration.uuidGenerator,
            crashContextIntegration: crashReportingFeature.map { .init(crashReporting: $0) },
            ciTest: CITestIntegration.active?.rumCITest,
            viewUpdatesThrottlerFactory: { RUMViewUpdatesThrottler() },
            vitalsReaders: rumFeature.configuration.vitalsFrequency.map {
                .init(
                    frequency: $0,
                    cpu: VitalCPUReader(telemetry: telemetry),
                    memory: VitalMemoryReader(),
                    refreshRate: VitalRefreshRateReader()
                )
            },
            onSessionStart: rumFeature.configuration.onSessionStart
        )
    }
}
