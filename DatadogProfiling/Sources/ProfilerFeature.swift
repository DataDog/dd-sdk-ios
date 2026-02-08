/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class ProfilerFeature: DatadogRemoteFeature {
    static let name = "profiler"

    internal static let maxObjectSize = 10.MB.asUInt32()

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver
    let customProfiler: CustomProfiler

    let isContinuousProfiling: Bool

    let telemetryController: ProfilingTelemetryController

    /// Setting max-file-age to minimum will force creating a batch per profile.
    /// It is necessary as the profiling intake only accepts one profile per request.
    let performanceOverride: PerformancePresetOverride? = PerformancePresetOverride(maxFileSize: maxObjectSize, maxObjectSize: maxObjectSize)

    init(
        core: DatadogCoreProtocol,
        configuration: Profiling.Configuration,
        requestBuilder: FeatureRequestBuilder,
        telemetryController: ProfilingTelemetryController,
        userDefaults: UserDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME) ?? .standard //swiftlint:disable:this required_reason_api_name
    ) {
        self.requestBuilder = requestBuilder
        self.telemetryController = telemetryController

        self.isContinuousProfiling = Sampler(
            samplingRate: configuration.debugSDK ? .maxSampleRate : configuration.continuous.sampleRate
        ).sample()

        var messageReceivers: [FeatureMessageReceiver] = [
            AppLaunchProfiler(
                isContinuousProfiling: isContinuousProfiling,
                telemetryController: telemetryController
            )
        ]
        if isContinuousProfiling {
            messageReceivers.append(ContinuousProfiler(core: core, telemetryController: telemetryController))
        }

        self.messageReceiver = CombinedFeatureMessageReceiver(messageReceivers)
        self.customProfiler = DatadogProfiler(
            core: core,
            isContinuousProfiling: isContinuousProfiling,
            telemetryController: telemetryController
        )

        setProfilingEnabled(in: userDefaults)
        let sampleRate = configuration.debugSDK ? .maxSampleRate : configuration.applicationLaunch.sampleRate
        setAppLaunch(sampleRate: sampleRate, in: userDefaults)
    }

    private func setProfilingEnabled(in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        userDefaults.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
    }

    private func setAppLaunch(sampleRate: SampleRate, in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        let previousSampleRate = userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate

        // Profiling will use the lowest sample rate
        // if there is more than one SDK instance initialized.
        if previousSampleRate == nil || previousSampleRate ?? .maxSampleRate > sampleRate {
            userDefaults.setValue(sampleRate, forKey: DD_PROFILING_SAMPLE_RATE_KEY)
        }
    }
}
