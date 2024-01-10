/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal class ResourcesFeature: DatadogRemoteFeature {
    static var name = "session-replay-resources"
    static var maxObjectSize = 10.MB.asUInt64()

    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    let performanceOverride: PerformancePresetOverride?

    let requestBuilder: FeatureRequestBuilder

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) {
        self.requestBuilder = ResourceRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: ResourcesFeature.maxObjectSize,
            maxObjectSize: ResourcesFeature.maxObjectSize
        )
    }
}
#endif
