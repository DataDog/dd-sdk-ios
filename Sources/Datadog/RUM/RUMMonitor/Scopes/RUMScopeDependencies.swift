/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

    let core: DatadogCoreProtocol
    let rumApplicationID: String
    let sessionSampler: Sampler
    let backgroundEventTrackingEnabled: Bool
    let frustrationTrackingEnabled: Bool
    let firstPartyHosts: FirstPartyHosts
    let eventBuilder: RUMEventBuilder
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?

    let vitalsReaders: VitalsReaders?
    let onSessionStart: RUMSessionListener?
}

internal extension RUMScopeDependencies {
    init(
        core: DatadogCoreProtocol,
        rumFeature: RUMFeature
    ) {
        self.init(
            core: core,
            rumApplicationID: rumFeature.configuration.applicationID,
            sessionSampler: rumFeature.configuration.sessionSampler,
            backgroundEventTrackingEnabled: rumFeature.configuration.backgroundEventTrackingEnabled,
            frustrationTrackingEnabled: rumFeature.configuration.frustrationTrackingEnabled,
            firstPartyHosts: rumFeature.configuration.firstPartyHosts,
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
            ciTest: CITestIntegration.active?.rumCITest,
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
