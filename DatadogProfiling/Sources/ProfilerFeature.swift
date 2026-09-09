/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class ProfilerFeature: DatadogRemoteFeature {
    enum Constants {
        static let maxFileSize = 10.MB.asUInt32()
        static let maxObjectSize = 10.MB.asUInt32()
        static let maxObjectsInFile = 1
    }
    static let name = "profiler"

    let profilingSamplerProvider: ProfilingSamplerProvider
    let telemetryController: ProfilingTelemetryController
    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver

    /// Setting max-file-age to minimum will force creating a batch per profile.
    /// It is necessary as the profiling intake only accepts one profile per request.
    let performanceOverride: PerformancePresetOverride? = PerformancePresetOverride(
        // Add 5 MB to accommodate base64 expansion when encoding the pprof attachment.
        maxFileSize: Constants.maxFileSize + 5.MB.asUInt32(),
        maxObjectSize: Constants.maxObjectSize + 5.MB.asUInt32(),
        maxObjectsInFile: Constants.maxObjectsInFile
    )

    init(
        core: DatadogCoreProtocol,
        configuration: Profiling.Configuration,
        requestBuilder: FeatureRequestBuilder,
        telemetryController: ProfilingTelemetryController,
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaChecker(),
        userDefaults: UserDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME) ?? .standard //swiftlint:disable:this required_reason_api_name
    ) {
        self.requestBuilder = requestBuilder
        self.telemetryController = telemetryController

        let continuousSampleRate = configuration.debugSDK ? .maxSampleRate : configuration.continuousSampleRate
        let appLaunchSampleRate = configuration.debugSDK ? .maxSampleRate : configuration.applicationLaunchSampleRate
        self.profilingSamplerProvider = ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate)

        let cpuTimeSamplesEnabled = configuration.featureFlags[.cpuTimeSamples]
        Self.setProfilingEnabled(in: userDefaults)
        Self.setCPUTimeSamplesEnabled(cpuTimeSamplesEnabled, in: userDefaults)
        Self.setAppLaunch(sampleRate: appLaunchSampleRate, in: userDefaults)

        let datadogProfiler = DatadogProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            telemetryController: telemetryController,
            minProfileDuration: configuration.minProfileDuration,
            isAppLaunchProfilingEnabled: appLaunchSampleRate > 0
        )
        self.messageReceiver = CombinedFeatureMessageReceiver([
            ProfilingContextMessageReceiver(profilingSamplerProvider: profilingSamplerProvider),
            quotaChecker,
            datadogProfiler
        ])
    }

    private static func setProfilingEnabled(in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        userDefaults.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
    }

    private static func setAppLaunch(sampleRate: SampleRate, in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        userDefaults.setValue(sampleRate, forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
    }

    private static func setCPUTimeSamplesEnabled(_ enabled: Bool, in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        userDefaults.setValue(enabled, forKey: DD_PROFILING_RECORD_CPU_TIME_KEY)
    }
}

#endif
