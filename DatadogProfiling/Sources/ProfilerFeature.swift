/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class ProfilerFeature: DatadogRemoteFeature {
    static let name = "profiler"

    internal enum Constants {
        /// The key to check if Profiling is enabled .
        static let isProfilingEnabledKey = "is_profiling_enabled"
    }

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let telemetryController: ProfilingTelemetryController

    /// Setting max-file-age to minimum will force creating a batch per profile.
    /// It is necessary as the profiling intake only accepts one profile per request.
    let performanceOverride = PerformancePresetOverride(maxFileSize: .min)

    init(
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
        telemetryController: ProfilingTelemetryController,
        dataStore: DataStore
    ) {
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
        self.telemetryController = telemetryController

        setProfilingEnabled(in: dataStore)
    }

    private func setProfilingEnabled(in dataStore: DataStore) {
        dataStore.setValue(withUnsafeBytes(of: true) { Data($0) }, forKey: Constants.isProfilingEnabledKey)
    }
}
