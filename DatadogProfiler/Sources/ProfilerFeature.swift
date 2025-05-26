/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class ProfilerFeature: DatadogRemoteFeature {
    static let name = "profiler"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride = PerformancePresetOverride(maxFileSize: .min, maxObjectSize: nil)

    private(set) var startDate: Date?
    private var profiler: MachProfiler?


    init(
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
    ) {
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
    }

    func start(currentThreadOnly: Bool = false) {
        profiler = MachProfiler(
            currentThreadOnly: currentThreadOnly,
            qos: .userInteractive
        )
        startDate = Date()
        profiler?.start()
    }

    func stop() throws -> Data? {
        profiler?.stop()
        return try profiler?.serializedData()
    }

    deinit {
        profiler?.stop()
    }
}
