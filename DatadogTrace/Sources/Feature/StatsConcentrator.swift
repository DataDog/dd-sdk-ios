/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - Trilean

/// Matches the protobuf `Trilean` enum used in `ClientGroupedStats.is_trace_root`.
internal enum Trilean: Int, Encodable, Hashable, Sendable {
    case notSet = 0
    case `true` = 1
    case `false` = 2
}

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

/// Running counters for a single aggregation key within a time bucket.
/// Counters use `Double` to support fractional weighted sampling (weight per span).
/// Currently weight is always 1.0, so these are effectively integers.
internal final class GroupedStats {
    var hits: Double = 0
    var topLevelHits: Double = 0
    var errors: Double = 0
    var duration: Double = 0
    /// Peer tags stored as `"key:value"` pairs for export, matching Go's `matchingPeerTags`.
    let peerTags: [String]

    init(peerTags: [String]) {
        self.peerTags = peerTags
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
internal struct ExportedBucket: Encodable, Sendable {
    let start: UInt64
    let duration: UInt64
    let stats: [ExportedGroupedStats]
}

/// A single grouped stats entry ready for serialization.
internal struct ExportedGroupedStats: Encodable, Sendable {
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

    init(
        now: Nanoseconds,
        bucketDuration: Nanoseconds = StatsConcentrator.defaultBucketDuration,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys
    ) {
        self.bucketDuration = bucketDuration
        self.bufferLen = bufferLen
        self.peerTagKeys = peerTagKeys
        self.oldestTs = StatsConcentrator.alignTimestamp(now, bucketDuration: bucketDuration)
    }

    // MARK: - Add

    /// Records a span snapshot into the appropriate time bucket.
    /// Ineligible spans are silently discarded. This method dispatches
    /// asynchronously and returns immediately without blocking the caller.
    func add(_ snapshot: SpanSnapshot) {
        guard Self.isEligible(snapshot) else {
            return
        }

        let endTime = snapshot.startTime + snapshot.duration
        let matchingPeerTags = self.matchingPeerTags(for: snapshot)
        let aggregationKey = makeAggregationKey(from: snapshot, peerTags: matchingPeerTags)
        let peerTagStrings = matchingPeerTags.map { "\($0.key):\($0.value)" }

        queue.async { [self] in
            let bucketKey = max(
                Self.alignTimestamp(endTime, bucketDuration: bucketDuration),
                oldestTs
            )
            let bucket = buckets[bucketKey, default: StatsBucket(start: bucketKey, duration: bucketDuration)]

            let group = bucket.groups[aggregationKey, default: GroupedStats(peerTags: peerTagStrings)]

            group.hits += 1
            if snapshot.isError {
                group.errors += 1
            }
            group.duration += Double(snapshot.duration)
            if snapshot.isTopLevel {
                group.topLevelHits += 1
            }

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
                        okSummary: Data(),
                        errorSummary: Data(),
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
