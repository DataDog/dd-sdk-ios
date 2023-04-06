/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Dependency container for injecting components to `RUMScopes` hierarchy.
internal struct RUMScopeDependencies {
    struct VitalsReaders {
        let frequency: TimeInterval
        let cpu: SamplingBasedVitalReader
        let memory: SamplingBasedVitalReader
        let refreshRate: ContinuousVitalReader
    }

    weak var core: DatadogCoreProtocol?
    let rumApplicationID: String
    let sessionSampler: Sampler
    let backgroundEventTrackingEnabled: Bool
    let frustrationTrackingEnabled: Bool
    let firstPartyHosts: FirstPartyHosts
    let eventBuilder: RUMEventBuilder
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    /// Produces `RUMViewUpdatesThrottlerType` for each started RUM view scope.
    let viewUpdatesThrottlerFactory: () -> RUMViewUpdatesThrottlerType

    let vitalsReaders: VitalsReaders?
    let onSessionStart: RUMSessionListener?
}

internal extension RUMScopeDependencies {
    init(
        core: DatadogCoreProtocol,
        configuration: RUMConfiguration
    ) {
        self.init(
            core: core,
            rumApplicationID: configuration.applicationID,
            sessionSampler: configuration.sessionSampler,
            backgroundEventTrackingEnabled: configuration.backgroundEventTrackingEnabled,
            frustrationTrackingEnabled: configuration.frustrationTrackingEnabled,
            firstPartyHosts: configuration.firstPartyHosts,
            eventBuilder: RUMEventBuilder(
                eventsMapper: RUMEventsMapper(
                    viewEventMapper: configuration.viewEventMapper,
                    errorEventMapper: configuration.errorEventMapper,
                    resourceEventMapper: configuration.resourceEventMapper,
                    actionEventMapper: configuration.actionEventMapper,
                    longTaskEventMapper: configuration.longTaskEventMapper
                )
            ),
            rumUUIDGenerator: configuration.uuidGenerator,
            ciTest: CITestIntegration.active?.rumCITest,
            viewUpdatesThrottlerFactory: { RUMViewUpdatesThrottler() },
            vitalsReaders: configuration.vitalsFrequency.map {
                .init(
                    frequency: $0,
                    cpu: VitalCPUReader(),
                    memory: VitalMemoryReader(),
                    refreshRate: VitalRefreshRateReader()
                )
            },
            onSessionStart: configuration.onSessionStart
        )
    }
}
