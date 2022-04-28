/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMSessionListener = (String, Bool) -> Void

/// Dependency container for injecting components to `RUMScopes` hierarchy.
internal struct RUMScopeDependencies {
    let rumApplicationID: String
    let sessionSampler: Sampler
    /// The start time of the application, indicated as SDK init. Measured in device time (without NTP correction).
    let sdkInitDate: Date
    let backgroundEventTrackingEnabled: Bool
    let appStateListener: AppStateListening
    let userInfoProvider: RUMUserInfoProvider
    let launchTimeProvider: LaunchTimeProviderType
    let connectivityInfoProvider: RUMConnectivityInfoProvider
    let serviceName: String
    let applicationVersion: String
    let sdkVersion: String
    let source: String
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Adjusts RUM events time (device time) to server time.
    let dateCorrector: DateCorrectorType
    /// Integration with Crash Reporting. It updates the crash context with RUM info.
    /// `nil` if Crash Reporting feature is not enabled.
    let crashContextIntegration: RUMWithCrashContextIntegration?
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    /// Produces `RUMViewUpdatesThrottlerType` for each started RUM view scope.
    let viewUpdatesThrottlerFactory: () -> RUMViewUpdatesThrottlerType

    let vitalCPUReader: SamplingBasedVitalReader
    let vitalMemoryReader: SamplingBasedVitalReader
    let vitalRefreshRateReader: ContinuousVitalReader

    let onSessionStart: RUMSessionListener?
}

internal extension RUMScopeDependencies {
    init(rumFeature: RUMFeature) {
        self.init(
            rumApplicationID: rumFeature.configuration.applicationID,
            sessionSampler: rumFeature.configuration.sessionSampler,
            sdkInitDate: rumFeature.sdkInitDate,
            backgroundEventTrackingEnabled: rumFeature.configuration.backgroundEventTrackingEnabled,
            appStateListener: rumFeature.appStateListener,
            userInfoProvider: RUMUserInfoProvider(userInfoProvider: rumFeature.userInfoProvider),
            launchTimeProvider: rumFeature.launchTimeProvider,
            connectivityInfoProvider: RUMConnectivityInfoProvider(
                networkConnectionInfoProvider: rumFeature.networkConnectionInfoProvider,
                carrierInfoProvider: rumFeature.carrierInfoProvider
            ),
            serviceName: rumFeature.configuration.common.serviceName,
            applicationVersion: rumFeature.configuration.common.applicationVersion,
            sdkVersion: rumFeature.configuration.common.sdkVersion,
            source: rumFeature.configuration.common.source,
            eventBuilder: RUMEventBuilder(
                eventsMapper: rumFeature.eventsMapper
            ),
            eventOutput: RUMEventFileOutput(
                fileWriter: rumFeature.storage.writer
            ),
            rumUUIDGenerator: rumFeature.configuration.uuidGenerator,
            dateCorrector: rumFeature.dateCorrector,
            crashContextIntegration: RUMWithCrashContextIntegration(),
            ciTest: CITestIntegration.active?.rumCITest,
            viewUpdatesThrottlerFactory: { RUMViewUpdatesThrottler() },
            vitalCPUReader: rumFeature.vitalCPUReader,
            vitalMemoryReader: rumFeature.vitalMemoryReader,
            vitalRefreshRateReader: rumFeature.vitalRefreshRateReader,
            onSessionStart: rumFeature.onSessionStart
        )
    }
}
