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

    /// Largest encoded bucket written as one storage event; larger buckets are split. Below half the
    /// 1 MB event limit, so a piece still fits when a custom `DataEncryption` doubles its size, as
    /// hex encoding does, plus the 6-byte batch block header.
    static let maxStoredBucketSize = 500_000

    /// Largest stats batch file. Each file is uploaded as one request, so this keeps a request within
    /// the 1.5 MB the agent's stats writer targets, half the intake's limit of about 3 MB compressed.
    /// Stored JSON is larger than the MessagePack body built from it.
    static let maxBatchSize: UInt32 = 1_536 * 1_024

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    let concentrator: StatsConcentrator
    /// The `RuntimeID` of the client stats payloads this feature stores: the identity under which
    /// their sequence numbers are unique. It belongs to the stats feature, not to the tracer, because
    /// the SDK has no tracer or process-level ID to reuse and the sequence counter has to live with the
    /// code that stores the payloads. The name matches the stats protocol field.
    private let runtimeID = UUID().uuidString
    /// Sequence numbers for those payloads, taken in write order.
    private let sequenceNumbers = StatsSequenceNumberProvider()
    private let featureScope: FeatureScope
    private let dateProvider: DateProvider
    private let metricController: TraceClientStatsMetricController
    /// Runs the periodic flush off the main thread: it waits for pending aggregation and exports every
    /// completed bucket's sketches.
    private let flushQueue = DispatchQueue(label: "com.datadoghq.client-stats-flush", qos: .utility)
    private var flushTimer: DispatchSourceTimer?

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
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(maxFileSize: Self.maxBatchSize)
        self.dateProvider = dateProvider
        self.flushInterval = flushInterval
        self.featureScope = core.scope(for: ClientStatsFeature.self)
        self.metricController = TraceClientStatsMetricController(telemetry: featureScope.telemetry)

        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        let concentrator = StatsConcentrator(now: now, telemetry: featureScope.telemetry)
        self.concentrator = concentrator

        // Observe consent changes through the message bus. The core delivers the current context
        // right after registration, so the concentrator learns the real consent before the first
        // flush even though it starts in the `.pending` default.
        self.messageReceiver = TraceClientStatsConsentReceiver(concentrator: concentrator)

        startFlushTimer()
    }

    deinit {
        flushTimer?.cancel()
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

        featureScope.eventWriteContext { [metricController, runtimeID, sequenceNumbers] _, writer in
            var oversizedGroups: [ExportedGroupedStats] = []
            for bucket in exportedBuckets {
                // Identify each payload here, in write order, so sequence numbers increase in the order
                // payloads are stored and stay the same across retries and restarts.
                let payload = ExportedBucket.PayloadIdentity(runtimeID: runtimeID, sequence: sequenceNumbers.next())
                let split = bucket.assigning(payload).split(toFit: Self.maxStoredBucketSize)
                for piece in split.pieces {
                    writer.write(value: piece)
                }
                oversizedGroups += split.oversizedGroups
            }
            if !oversizedGroups.isEmpty {
                DD.logger.warn("Client-side stats dropped \(oversizedGroups.count) group(s) whose strings or bucket metadata exceed the storage budget.")
            }
            // Report only after the write: in some cases the event write context is not
            // available, and we do not want to signal a flush that never reached storage.
            metricController.send(for: exportedBuckets, oversizedGroups: oversizedGroups, force: force)
        }
    }

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: flushQueue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.flushStats()
        }
        timer.resume()
        flushTimer = timer
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
