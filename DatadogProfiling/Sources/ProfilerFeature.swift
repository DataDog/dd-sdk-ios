/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class ProfilerFeature: DatadogRemoteFeature {
    static let name = "profiler"

    let profiler: Profiler

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    /// Setting max-file-age to minimum will force creating a batch per profile.
    /// It is necessary as the profiling intake only accepts one profile per request.
    let performanceOverride = PerformancePresetOverride(maxFileSize: .min)

    init(
        profiler: Profiler,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver
    ) {
        self.profiler = profiler
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
    }
}
