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

    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    let performanceOverride: PerformancePresetOverride?

    let requestBuilder: FeatureRequestBuilder
    let availabilityStore: ResourceAvailabilityStore
    let writer: ResourcesWriter

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) {
        let scope = core.scope(for: ResourcesFeature.self)
        let availabilityStore = ResourceAvailabilityStore(scope: scope)
        self.availabilityStore = availabilityStore
        self.writer = ResourcesWriter(scope: scope, availabilityStore: availabilityStore)
        self.requestBuilder = ResourceRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: SessionReplay.maxObjectSize,
            maxObjectSize: SessionReplay.maxObjectSize,
            maxFileAgeForRead: 48.hours
        )
    }
}
#endif
