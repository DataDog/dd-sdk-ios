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
    private let metricController: TraceClientStatsMetricController
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
            customIntakeURL: configuration.customStatsEndpoint,
            telemetry: core.telemetry,
            runtimeID: UUID().uuidString,
            sequenceNumberProvider: StatsSequenceNumberProvider()
        )
        self.performanceOverride = nil
        self.dateProvider = dateProvider
        self.flushInterval = flushInterval
        self.featureScope = core.scope(for: ClientStatsFeature.self)
        self.metricController = TraceClientStatsMetricController(telemetry: featureScope.telemetry)

        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        let concentrator = StatsConcentrator(now: now)
        self.concentrator = concentrator

        // Observe consent changes through the message bus. The core delivers the current context
        // right after registration, so the concentrator learns the real consent before the first
        // flush even though it starts in the `.pending` default.
        self.messageReceiver = TraceClientStatsConsentReceiver(concentrator: concentrator)

        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
    }

    /// Flushes completed buckets and writes them to the feature storage for upload.
    ///
    /// - Parameter force: When `true`, flushes all buckets regardless of age (used during
    ///   SDK teardown via `Flushable`). When `false`, only buckets older than the buffer
    ///   window are flushed (normal periodic flush).
    func flushStats(force: Bool = false) {
        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        let exportedBuckets = concentrator.flush(now: now, force: force)

        guard !exportedBuckets.isEmpty else {
            return
        }

        featureScope.eventWriteContext { [metricController] _, writer in
            for bucket in exportedBuckets {
                writer.write(value: bucket)
            }
            // Report only after the write: in some cases the event write context is not
            // available, and we do not want to signal a flush that never reached storage.
            metricController.send(for: exportedBuckets, force: force)
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

/// Forwards tracking-consent changes from the message bus to the `StatsConcentrator`.
///
/// Holds the concentrator weakly: it is owned by `ClientStatsFeature`, while the bus owns this
/// receiver, so a weak reference avoids keeping the concentrator alive past the feature.
internal struct TraceClientStatsConsentReceiver: FeatureMessageReceiver {
    weak var concentrator: StatsConcentrator?

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }
        concentrator?.updateConsent(context.trackingConsent)
        return true
    }
}
