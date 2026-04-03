/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Computes client-side APM stats (hit counts, error rates, latency distributions)
/// on all eligible finished spans — including sampled-out ones — and uploads them
/// as a separate payload to `/api/v0.2/stats`.
///
/// Registered as a companion `DatadogRemoteFeature` alongside `TraceFeature`
/// when `Trace.Configuration.statsComputationEnabled` is `true`.
internal final class ClientStatsFeature: DatadogRemoteFeature {
    static let name = "client-stats"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    /// The concentrator that aggregates span snapshots into time-bucketed stats.
    let concentrator: StatsConcentrator

    init(
        core: DatadogCoreProtocol,
        configuration: Trace.Configuration
    ) {
        self.requestBuilder = StatsRequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.messageReceiver = NOPFeatureMessageReceiver()
        self.performanceOverride = nil
        self.concentrator = StatsConcentrator()
    }
}
