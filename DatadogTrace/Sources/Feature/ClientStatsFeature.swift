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
    static let name = "tracing-client-stats"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    let concentrator: StatsConcentrator
    private let featureScope: FeatureScope
    private let dateProvider: DateProvider
    private var flushTimer: Timer?

    /// Interval between periodic flushes (default: 30 seconds).
    let flushInterval: TimeInterval

    init(
        core: DatadogCoreProtocol,
        configuration: Trace.Configuration,
        dateProvider: DateProvider,
        flushInterval: TimeInterval = 30
    ) {
        self.requestBuilder = StatsRequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.messageReceiver = NOPFeatureMessageReceiver()
        self.performanceOverride = nil
        self.dateProvider = dateProvider
        self.flushInterval = flushInterval
        self.featureScope = core.scope(for: ClientStatsFeature.self)

        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        self.concentrator = StatsConcentrator(now: now)

        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
    }

    /// Flushes completed buckets and writes them to the feature storage for upload.
    func flushStats(force: Bool = false) {
        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        let exportedBuckets = concentrator.flush(now: now, force: force)

        guard !exportedBuckets.isEmpty else {
            return
        }

        featureScope.eventWriteContext { _, writer in
            for bucket in exportedBuckets {
                writer.write(value: bucket)
            }
        }
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: flushInterval,
            repeats: true
        ) { [weak self] _ in
            self?.flushStats()
        }
    }
}

extension ClientStatsFeature: Flushable {
    func flush() {
        flushStats(force: true)
    }
}
