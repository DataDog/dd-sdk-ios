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
// `@unchecked Sendable`: finished spans are recorded from any thread. The only mutable state is the
// flush timer, set once in `init`, and the two lock-protected suspension flags.
internal final class ClientStatsFeature: DatadogRemoteFeature, @unchecked Sendable {
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

        // Observe context changes through the message bus. The core delivers the current context
        // right after registration, so the concentrator learns the real consent before the first
        // flush even though it starts in the `.pending` default.
        let receiver = TraceClientStatsContextReceiver(concentrator: concentrator)
        self.messageReceiver = receiver

        startFlushTimer()
        receiver.appMayBeSuspendedDidChange = { [weak self] mayBeSuspended in
            self?.appMayBeSuspendedDidChange(mayBeSuspended)
        }
    }

    deinit {
        flushTimer?.cancel()
    }

    /// Why buffered stats are flushed to storage.
    enum FlushReason {
        /// The periodic timer, which flushes only buckets older than the buffer window.
        case periodic
        /// The app may be suspended, such as in the background on iOS, and then terminated without the
        /// periodic flush running again, so every buffered bucket is flushed.
        case appMayBeSuspended
        /// SDK teardown through `Flushable`, which flushes every buffered bucket.
        case teardown
    }

    /// The longest a span finished while the app may be suspended stays only in memory. Spans finished
    /// within it are flushed together, so a burst of spans flushes once.
    static let suspendableFlushDelay: TimeInterval = 1

    /// Records a finished span. While the app may be suspended, it is also flushed to storage within
    /// `suspendableFlushDelay`.
    func record(_ snapshot: SpanSnapshot) {
        concentrator.add(snapshot)
        if appMayBeSuspended {
            scheduleSuspendableFlush()
        }
    }

    /// Flushes buffered buckets and writes them to the feature storage for upload.
    func flushStats(_ reason: FlushReason = .periodic) {
        let force = reason != .periodic
        let now = dateProvider.now.timeIntervalSince1970.dd.toNanoseconds
        let (exportedBuckets, clearGeneration) = concentrator.flushForStorage(now: now, force: force)

        guard !exportedBuckets.isEmpty else {
            return
        }

        featureScope.eventWriteContext { [concentrator, metricController, runtimeID, sequenceNumbers] context, writer in
            var pieces: [ExportedBucket] = []
            var oversizedGroups: [ExportedGroupedStats] = []
            for bucket in exportedBuckets {
                // Identify each payload here, in write order, so sequence numbers increase in the order
                // payloads are stored and stay the same across retries and restarts.
                let payload = ExportedBucket.PayloadIdentity(runtimeID: runtimeID, sequence: sequenceNumbers.next())
                let stored = bucket.shiftedToServerClock(by: context.serverTimeOffset).assigning(payload)
                let split = stored.split(toFit: Self.maxStoredBucketSize)
                pieces += split.pieces
                oversizedGroups += split.oversizedGroups
            }
            // `Datadog.clearAllData()` may have run since the buckets were exported. Their data was
            // collected before it, so they must not reach storage after it.
            var isWritten = false
            concentrator.performUnlessCleared(since: clearGeneration) {
                pieces.forEach { writer.write(value: $0) }
                isWritten = true
            }
            guard isWritten else {
                return
            }
            if !oversizedGroups.isEmpty {
                DD.logger.warn("Client-side stats dropped \(oversizedGroups.count) group(s) whose strings or bucket metadata exceed the storage budget.")
            }
            // Report only after the write: in some cases the event write context is not
            // available, and we do not want to signal a flush that never reached storage.
            metricController.send(for: exportedBuckets, oversizedGroups: oversizedGroups, isTeardown: reason == .teardown)
        }
    }

    /// Whether the app may currently be suspended, as last reported by the context receiver.
    @ReadWriteLock
    private var appMayBeSuspended = false
    /// Whether a flush of spans finished while the app may be suspended is already scheduled.
    @ReadWriteLock
    private var isSuspendableFlushScheduled = false

    private func appMayBeSuspendedDidChange(_ mayBeSuspended: Bool) {
        appMayBeSuspended = mayBeSuspended
        if mayBeSuspended {
            // Flush on the feature's queue, not the message bus queue this is called on: flushing waits
            // for pending aggregation and exports every buffered sketch.
            flushQueue.async { [weak self] in
                self?.flushStats(.appMayBeSuspended)
            }
        }
    }

    // TODO: RUM-19008 Nothing keeps the app running until this flush: stats of a span that finishes in the
    // second before the system suspends the app stay in memory, and are lost if the app is then terminated.
    private func scheduleSuspendableFlush() {
        var isAlreadyScheduled = false
        _isSuspendableFlushScheduled.mutate {
            isAlreadyScheduled = $0
            $0 = true
        }
        guard !isAlreadyScheduled else {
            return
        }
        flushQueue.asyncAfter(deadline: .now() + Self.suspendableFlushDelay) { [weak self] in
            self?.isSuspendableFlushScheduled = false
            self?.flushStats(.appMayBeSuspended)
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

extension ClientStatsFeature: DataClearable {
    func clearAllData() {
        concentrator.clearAllData()
    }
}

extension ClientStatsFeature: Flushable {
    func flush() {
        flushStats(.teardown)
    }
}

/// Forwards context changes from the message bus to client-side stats.
///
/// Tracking consent goes to the `StatsConcentrator`, and moves into or out of a state where the app may
/// be suspended, such as the background on iOS, go to `ClientStatsFeature`.
///
/// Holds the concentrator weakly: it is owned by `ClientStatsFeature`, while the bus owns this
/// receiver, so a weak reference avoids keeping the concentrator alive past the feature.
internal final class TraceClientStatsContextReceiver: FeatureMessageReceiver {
    weak var concentrator: StatsConcentrator?

    /// Called with the new value whenever the app moves into or out of a state where it may be
    /// suspended. Set once by `ClientStatsFeature` before it is registered. It must not block, since it
    /// runs on the message bus queue that every feature shares.
    var appMayBeSuspendedDidChange: ((Bool) -> Void)?

    /// Whether the last context showed an app that may be suspended.
    @ReadWriteLock
    private var mayBeSuspended = false

    init(concentrator: StatsConcentrator?) {
        self.concentrator = concentrator
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }
        concentrator?.updateConsent(context.trackingConsent)

        let isNowSuspendable = context.applicationStateHistory.currentState.applicationMayBeSuspended
        var didChange = false
        _mayBeSuspended.mutate {
            didChange = isNowSuspendable != $0
            $0 = isNowSuspendable
        }
        if didChange {
            appMayBeSuspendedDidChange?(isNowSuspendable)
        }
        return true
    }
}
