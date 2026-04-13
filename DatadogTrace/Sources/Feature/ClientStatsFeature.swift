/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Computes client-side APM stats (hit counts, error rates, latency distributions)
/// on all finished spans and uploads them to the Datadog stats intake.
///
/// Registered as a separate `DatadogRemoteFeature` alongside `TraceFeature`
/// so that it has its own storage and upload pipeline.
internal final class ClientStatsFeature: DatadogRemoteFeature {
    static let name = "client-stats"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    init(core: DatadogCoreProtocol, configuration: Trace.Configuration) {
        self.requestBuilder = StatsRequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.messageReceiver = NOPFeatureMessageReceiver()
        self.performanceOverride = nil
    }
}
