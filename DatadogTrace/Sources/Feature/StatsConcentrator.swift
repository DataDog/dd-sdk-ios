/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - Aggregation Key

/// The set of dimensions by which spans are grouped within a time bucket.
/// Matches the Go reference `BucketsAggregationKey` in `aggregation.go`.
internal struct AggregationKey: Hashable, Sendable {
    let service: String
    let operationName: String
    let resource: String
    let httpStatusCode: UInt32
    let type: String
    let spanKind: String
    let isTraceRoot: Trilean
    let synthetics: Bool
    let peerTagsHash: UInt64
    let serviceSource: String
}

// MARK: - Grouped Stats

/// Running counters and latency distributions for a single aggregation key within a
/// time bucket.
///
/// Counters use `Double` to support fractional weighted sampling (weight per span).
/// Currently weight is always 1.0, so these are effectively integers.
///
/// `duration` is the total nanoseconds across all spans in the group; `okSummary` and
/// `errorSummary` are DDSketches tracking the distribution of those same durations
/// split by `isError`. Both representations are required by the v1.2.0 stats payload.
///
/// Each sketch is bounded by `DDSketch.makeForStats()` to 2048 bins (max ~16 KB per
/// sketch), so a fully saturated group caps at roughly 32 KB of sketch memory.
internal final class GroupedStats {
    var hits: Double = 0
    var topLevelHits: Double = 0
    var errors: Double = 0
    var duration: Double = 0
    var okSummary: DDSketch = .makeForStats()
    var errorSummary: DDSketch = .makeForStats()
    /// Peer tags stored as `"key:value"` pairs for export, matching Go's `matchingPeerTags`.
    let peerTags: [String]

    init(peerTags: [String]) {
        self.peerTags = peerTags
    }

    /// Absorbs a single span into the group: bumps the relevant counters and adds the
    /// span's duration (in nanoseconds) to the matching latency sketch.
    func update(with snapshot: SpanSnapshot) {
        let durationDouble = Double(snapshot.duration)

        hits += 1
        duration += durationDouble
        if snapshot.isTopLevel {
            topLevelHits += 1
        }
        if snapshot.isError {
            errors += 1
            errorSummary.add(durationDouble)
        } else {
            okSummary.add(durationDouble)
        }
    }
}

// MARK: - Stats Bucket

/// A single time bucket holding grouped stats keyed by aggregation dimensions.
internal final class StatsBucket {
    let start: UInt64
    let duration: UInt64
    var groups: [AggregationKey: GroupedStats] = [:]

    init(start: UInt64, duration: UInt64) {
        self.start = start
        self.duration = duration
    }
}

// MARK: - Exportable Bucket

/// A flushed bucket ready for serialization and upload.
///
/// Conforms to `Codable` so it can be written to the feature's storage as JSON and later
/// decoded back by `StatsRequestBuilder` for encoding into the MessagePack wire payload.
internal struct ExportedBucket: Codable, Sendable {
    let start: UInt64
    let duration: UInt64
    let stats: [ExportedGroupedStats]
}

/// A single grouped stats entry ready for serialization.
internal struct ExportedGroupedStats: Codable, Sendable {
    let service: String
    let name: String
    let resource: String
    let httpStatusCode: UInt32
    let type: String
    let spanKind: String
    let isTraceRoot: Trilean
    let synthetics: Bool
    let hits: UInt64
    let errors: UInt64
    let duration: UInt64
    let topLevelHits: UInt64
    let okSummary: Data
    let errorSummary: Data
    let peerTags: [String]
    let serviceSource: String
}

// MARK: - Eligible Span Kinds

/// Span kinds eligible for stats computation per the v1.2.0 spec.
private let eligibleSpanKinds: Set<String> = ["server", "consumer", "client", "producer"]

/// Span kinds for which peer tags should be included in the aggregation key.
private let peerTagSpanKinds: Set<String> = ["client", "producer", "consumer"]

// MARK: - Stats Utilities

/// Utility functions for stats computation.
internal enum StatsUtils {
    /// Computes an FNV-64a hash of sorted tag strings, matching Go's `tagsFnvHash`.
    static func fnv64a(_ tags: [String]) -> UInt64 {
        if tags.isEmpty {
            return 0
        }
        let sorted = tags.sorted()
        var hash: UInt64 = 14_695_981_039_346_656_037 // FNV offset basis
        let prime: UInt64 = 1_099_511_628_211

        for (i, tag) in sorted.enumerated() {
            if i > 0 {
                hash ^= 0 // null separator byte
                hash = hash &* prime
            }
            for byte in tag.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return hash
    }

    /// Converts a floating-point count to `UInt64` using stochastic rounding.
    ///
    /// In the Go reference, each span contributes a fractional sampling weight to its
    /// group counters. When exporting, the float totals are rounded to integers with
    /// probabilistic correction so that expected values remain unbiased. Currently
    /// the iOS SDK always uses weight 1.0 (no weighted sampling), so this reduces
    /// to simple truncation.
    static func stochasticRound(_ value: Double) -> UInt64 {
        let truncated = UInt64(value)
        let fractional = value - Double(truncated)
        if Double.random(in: 0..<1) < fractional {
            return truncated + 1
        }
        return truncated
    }
}

// MARK: - Stats Concentrator

/// Aggregates `SpanSnapshot`s into time-bucketed stats (hit counts, error counts,
/// duration totals) keyed by aggregation dimensions.
///
/// Thread-safety: All mutations are dispatched onto a dedicated serial queue.
/// `add()` dispatches asynchronously so the caller's thread is never blocked.
/// `flush()` dispatches synchronously to drain pending adds before collecting results.
internal final class StatsConcentrator: @unchecked Sendable {
    /// Default bucket duration: 10 seconds in nanoseconds.
    static let defaultBucketDuration: Nanoseconds = 10_000_000_000

    /// How many recent bucket windows to keep before flushing. A value of 2 means
    /// the current and previous buckets are retained; older buckets become eligible
    /// for flush. Matches Go's `defaultBufferLen`.
    static let defaultBufferLen = 2

    /// Configured peer tag keys to extract from spans.
    static let defaultPeerTagKeys: [String] = [
        "peer.service",
        "db.instance",
        "db.system",
        "out.host",
        "net.peer.name",
        "server.address"
    ]

    private let bucketDuration: Nanoseconds
    private let bufferLen: Int
    private let peerTagKeys: [String]

    /// Serial queue protecting `buckets` and `oldestTs`.
    private let queue = DispatchQueue(label: "com.datadoghq.stats-concentrator", qos: .utility)

    private var buckets: [UInt64: StatsBucket] = [:]
    private var oldestTs: UInt64

    /// The user's current tracking consent. `.granted` and `.pending` are both recording states;
    /// `.notGranted` stops aggregation and drops any data buffered in memory. Confined to `queue`,
    /// so consent transitions stay ordered with `add`, `flush`, and the revoke clear and cannot be
    /// observed out of order across threads.
    ///
    /// Starts at `.pending`, the SDK's default until consent is known. This is a record-but-hold
    /// state: spans in the startup window are aggregated, yet nothing is uploaded until the first
    /// context message confirms consent, because the flush writer is consent-gated and the buffer
    /// is cleared if consent turns out to be `.notGranted`. Defaulting to a recording state (rather
    /// than `.notGranted`) avoids dropping spans that are stamped `_dd.compute_stats=0`, which would
    /// otherwise leave the backend with no stats and no client bucket for that window.
    private var currentConsent: TrackingConsent

    init(
        now: Nanoseconds,
        initialConsent: TrackingConsent = .pending,
        bucketDuration: Nanoseconds = StatsConcentrator.defaultBucketDuration,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys
    ) {
        self.bucketDuration = bucketDuration
        self.bufferLen = bufferLen
        self.peerTagKeys = peerTagKeys
        self.oldestTs = StatsConcentrator.alignTimestamp(now, bucketDuration: bucketDuration)
        self.currentConsent = initialConsent
    }

    // MARK: - Add

    /// Records a span snapshot into the appropriate time bucket.
    /// Ineligible spans are silently discarded. This method dispatches
    /// asynchronously and returns immediately without blocking the caller.
    func add(_ snapshot: SpanSnapshot) {
        guard Self.isEligible(snapshot) else {
            return
        }

        // The public tracing API accepts custom start/finish dates, and the SDK's time conversion
        // clamps to `UInt64.max` rather than trapping. A pathological span (e.g. a far-future start
        // plus any positive duration) can therefore saturate `startTime`, making this addition
        // overflow. Drop such a snapshot instead of crashing the host app or mis-bucketing it in the
        // far future.
        let (endTime, overflow) = snapshot.startTime.addingReportingOverflow(snapshot.duration)
        guard !overflow else {
            return
        }
        let matchingPeerTags = self.matchingPeerTags(for: snapshot)
        let aggregationKey = makeAggregationKey(from: snapshot, peerTags: matchingPeerTags)
        let peerTagStrings = matchingPeerTags.map { "\($0.key):\($0.value)" }

        queue.async { [self] in
            // Drop the span when consent is not granted. Checking on the serial queue (rather than
            // off-queue) keeps the decision ordered with consent changes and the revoke clear, so a
            // span recorded around a revocation cannot slip past or be re-added after the buffer is
            // cleared.
            guard currentConsent != .notGranted else {
                return
            }

            let bucketKey = max(
                Self.alignTimestamp(endTime, bucketDuration: bucketDuration),
                oldestTs
            )
            let bucket = buckets[bucketKey, default: StatsBucket(start: bucketKey, duration: bucketDuration)]

            let group = bucket.groups[aggregationKey, default: GroupedStats(peerTags: peerTagStrings)]
            group.update(with: snapshot)

            bucket.groups[aggregationKey] = group
            buckets[bucketKey] = bucket
        }
    }

    // MARK: - Flush

    /// Flushes completed buckets and returns them for export.
    ///
    /// - Parameter now: Current time in nanoseconds.
    /// - Parameter force: When `true`, flushes all buckets regardless of age.
    ///   Used during SDK teardown.
    /// - Returns: Array of exported buckets ready for serialization.
    func flush(now: Nanoseconds, force: Bool) -> [ExportedBucket] {
        return queue.sync {
            // Never export while consent is not granted. The storage writer already drops these
            // writes, but returning early avoids needlessly serializing the sketches.
            guard currentConsent != .notGranted else {
                return []
            }

            let cutoff = force ? Int64.max : Int64(now) - Int64(bufferLen) * Int64(bucketDuration)
            var flushed: [ExportedBucket] = []
            var keysToRemove: [UInt64] = []

            for (ts, bucket) in buckets {
                if Int64(ts) > cutoff {
                    continue
                }
                keysToRemove.append(ts)

                let exportedStats: [ExportedGroupedStats] = bucket.groups.map { key, group in
                    ExportedGroupedStats(
                        service: key.service,
                        name: key.operationName,
                        resource: key.resource,
                        httpStatusCode: key.httpStatusCode,
                        type: key.type,
                        spanKind: key.spanKind,
                        isTraceRoot: key.isTraceRoot,
                        synthetics: key.synthetics,
                        hits: StatsUtils.stochasticRound(group.hits),
                        errors: StatsUtils.stochasticRound(group.errors),
                        duration: StatsUtils.stochasticRound(group.duration),
                        topLevelHits: StatsUtils.stochasticRound(group.topLevelHits),
                        okSummary: group.okSummary.toProtoBytes(),
                        errorSummary: group.errorSummary.toProtoBytes(),
                        peerTags: group.peerTags,
                        serviceSource: key.serviceSource
                    )
                }

                if !exportedStats.isEmpty {
                    flushed.append(ExportedBucket(
                        start: bucket.start,
                        duration: bucket.duration,
                        stats: exportedStats
                    ))
                }
            }

            for key in keysToRemove {
                buckets.removeValue(forKey: key)
            }

            let aligned = Self.alignTimestamp(now, bucketDuration: bucketDuration)
            let offset = UInt64(bufferLen - 1) * bucketDuration
            let newOldestTs = aligned >= offset ? aligned - offset : 0
            if newOldestTs > oldestTs {
                oldestTs = newOldestTs
            }

            return flushed
        }
    }

    // MARK: - Consent

    /// Updates the tracking consent that gates aggregation.
    ///
    /// `.granted` and `.pending` are both recording states, so transitions between them need no
    /// action: data already written to storage is migrated by the core, and in-memory data keeps
    /// accumulating. Revoking consent (`→ .notGranted`) discards the in-memory buffer so spans
    /// aggregated before the revocation are never uploaded, even if consent is later re-granted.
    func updateConsent(_ consent: TrackingConsent) {
        queue.async { [self] in
            currentConsent = consent
            // Revoking consent discards everything buffered in memory so spans aggregated before
            // the revocation are never uploaded, even if consent is later granted again. Running on
            // the queue orders this clear with any in-flight `add` and `flush` work.
            if consent == .notGranted {
                buckets.removeAll()
            }
        }
    }

    // MARK: - Eligibility

    /// A span is eligible for stats if it is top-level, measured, or has a
    /// qualifying `span_kind` (server, consumer, client, producer).
    static func isEligible(_ snapshot: SpanSnapshot) -> Bool {
        if snapshot.isTopLevel {
            return true
        }
        if snapshot.isMeasured {
            return true
        }
        if let kind = snapshot.spanKind?.lowercased(), eligibleSpanKinds.contains(kind) {
            return true
        }
        return false
    }

    // MARK: - Private

    /// Aligns a nanosecond timestamp to the bucket boundary.
    static func alignTimestamp(_ ts: UInt64, bucketDuration: UInt64) -> UInt64 {
        return ts - ts % bucketDuration
    }

    /// Extracts matching peer tags from the snapshot based on span kind rules.
    private func matchingPeerTags(for snapshot: SpanSnapshot) -> [String: String] {
        let kind = snapshot.spanKind?.lowercased() ?? ""
        guard peerTagSpanKinds.contains(kind) else {
            return [:]
        }
        var result: [String: String] = [:]
        for key in peerTagKeys {
            if let value = snapshot.peerTags[key], !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    /// Builds an `AggregationKey` from a span snapshot and its matching peer tags.
    private func makeAggregationKey(from snapshot: SpanSnapshot, peerTags: [String: String]) -> AggregationKey {
        let isTraceRoot: Trilean = snapshot.parentSpanID == nil ? .true : .false
        let peerTagStrings = peerTags.map { "\($0.key):\($0.value)" }

        return AggregationKey(
            service: snapshot.service,
            operationName: snapshot.operationName,
            resource: snapshot.resource,
            httpStatusCode: snapshot.httpStatusCode,
            type: snapshot.type,
            spanKind: snapshot.spanKind ?? "",
            isTraceRoot: isTraceRoot,
            synthetics: false,
            peerTagsHash: StatsUtils.fnv64a(peerTagStrings),
            serviceSource: snapshot.serviceSource
        )
    }
}
