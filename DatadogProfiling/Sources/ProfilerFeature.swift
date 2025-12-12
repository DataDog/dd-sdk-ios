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

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    /// Setting max-file-age to minimum will force creating a batch per profile.
    /// It is necessary as the profiling intake only accepts one profile per request.
    let performanceOverride = PerformancePresetOverride(maxFileSize: .min)

    init(
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
        userDefaults: UserDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME) ?? .standard //swiftlint:disable:this required_reason_api_name

    ) {
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver

        setProfilingEnabled(in: userDefaults)
    }

    private func setProfilingEnabled(in userDefaults: UserDefaults) { //swiftlint:disable:this required_reason_api_name
        userDefaults.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
    }
}
