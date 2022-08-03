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
    let backgroundEventTrackingEnabled: Bool
    let appStateListener: AppStateListening
    let launchTimeProvider: LaunchTimeProviderType
    let firstPartyURLsFilter: FirstPartyURLsFilter
    let eventBuilder: RUMEventBuilder
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
        context: DatadogV1Context
    ) {
        self.init(
            rumApplicationID: rumFeature.configuration.applicationID,
            sessionSampler: rumFeature.configuration.sessionSampler,
            backgroundEventTrackingEnabled: rumFeature.configuration.backgroundEventTrackingEnabled,
            appStateListener: context.appStateListener,
            launchTimeProvider: context.launchTimeProvider,
            firstPartyURLsFilter: FirstPartyURLsFilter(hosts: rumFeature.configuration.firstPartyHosts),
            eventBuilder: RUMEventBuilder(
                eventsMapper: RUMEventsMapper(
                    viewEventMapper: rumFeature.configuration.viewEventMapper,
                    errorEventMapper: rumFeature.configuration.errorEventMapper,
                    resourceEventMapper: rumFeature.configuration.resourceEventMapper,
                    actionEventMapper: rumFeature.configuration.actionEventMapper,
                    longTaskEventMapper: rumFeature.configuration.longTaskEventMapper
                )
            ),
            rumUUIDGenerator: rumFeature.configuration.uuidGenerator,
            crashContextIntegration: crashReportingFeature.map { .init(crashReporting: $0) },
            ciTest: CITestIntegration.active?.rumCITest,
            viewUpdatesThrottlerFactory: { RUMViewUpdatesThrottler() },
            vitalsReaders: rumFeature.configuration.vitalsFrequency.map {
                .init(
                    frequency: $0,
                    cpu: VitalCPUReader(),
                    memory: VitalMemoryReader(),
                    refreshRate: VitalRefreshRateReader()
                )
            },
            onSessionStart: rumFeature.configuration.onSessionStart
        )
    }
}
