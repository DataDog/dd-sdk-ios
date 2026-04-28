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

// MARK: - FNV-64a Hash

/// Computes an FNV-64a hash of sorted tag strings, matching Go's `tagsFnvHash`.
internal func fnv64a(_ tags: [String]) -> UInt64 {
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

// MARK: - Stochastic Rounding

/// Converts a floating-point count to UInt64 using stochastic rounding.
/// When weight is always 1.0, this is effectively a truncation to integer.
internal func stochasticRound(_ value: Double) -> UInt64 {
    let truncated = UInt64(value)
    let fractional = value - Double(truncated)
    if Double.random(in: 0..<1) < fractional {
        return truncated + 1
    }
    return truncated
}

// MARK: - Stats Concentrator

/// Aggregates `SpanSnapshot`s into time-bucketed stats (hit counts, error counts,
/// duration totals) keyed by aggregation dimensions.
///
/// Thread-safety: Access to `buckets` and `oldestTs` is protected by a `ReadWriteLock`.
/// `add()` and `flush()` can be called from any thread.
internal final class StatsConcentrator: @unchecked Sendable {
    /// Default bucket duration: 10 seconds in nanoseconds.
    static let defaultBucketDuration: Nanoseconds = 10_000_000_000

    /// Number of bucket-duration windows to keep before flushing.
    /// Matches Go's `defaultBufferLen = 2` (current + previous bucket).
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

    @ReadWriteLock
    private var buckets: [UInt64: StatsBucket] = [:]

    @ReadWriteLock
    private var oldestTs: UInt64

    init(
        bucketDuration: Nanoseconds = StatsConcentrator.defaultBucketDuration,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys,
        now: Nanoseconds
    ) {
        self.bucketDuration = bucketDuration
        self.bufferLen = bufferLen
        self.peerTagKeys = peerTagKeys
        self.oldestTs = StatsConcentrator.alignTimestamp(now, bucketDuration: bucketDuration)
    }

    // MARK: - Add

    /// Records a span snapshot into the appropriate time bucket.
    /// Ineligible spans are silently discarded.
    func add(_ snapshot: SpanSnapshot) {
        guard Self.isEligible(snapshot) else {
            return
        }

        let endTime = snapshot.startTime + snapshot.duration
        let matchingPeerTags = self.matchingPeerTags(for: snapshot)
        let aggregationKey = makeAggregationKey(from: snapshot, peerTags: matchingPeerTags)
        let peerTagStrings = matchingPeerTags.map { "\($0.key):\($0.value)" }

        _buckets.mutate { buckets in
            let bucketKey = max(
                Self.alignTimestamp(endTime, bucketDuration: self.bucketDuration),
                self.oldestTs
            )
            let bucket = buckets[bucketKey, default: StatsBucket(start: bucketKey, duration: self.bucketDuration)]

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
    /// - Parameter force: When `true`, flushes all buckets regardless of age.
    ///   Used during SDK teardown.
    /// - Parameter now: Current time in nanoseconds.
    /// - Returns: Array of exported buckets ready for serialization.
    func flush(now: Nanoseconds, force: Bool) -> [ExportedBucket] {
        var flushed: [ExportedBucket] = []

        _buckets.mutate { buckets in
            let cutoff = Int64(now) - Int64(self.bufferLen) * Int64(self.bucketDuration)
            var keysToRemove: [UInt64] = []

            for (ts, bucket) in buckets {
                if !force && Int64(ts) > cutoff {
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
                        hits: stochasticRound(group.hits),
                        errors: stochasticRound(group.errors),
                        duration: stochasticRound(group.duration),
                        topLevelHits: stochasticRound(group.topLevelHits),
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
        }

        let aligned = Self.alignTimestamp(now, bucketDuration: bucketDuration)
        let offset = UInt64(bufferLen - 1) * bucketDuration
        let newOldestTs = aligned >= offset ? aligned - offset : 0
        _oldestTs.mutate { oldest in
            if newOldestTs > oldest {
                oldest = newOldestTs
            }
        }

        return flushed
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
            peerTagsHash: fnv64a(peerTagStrings),
            serviceSource: snapshot.serviceSource
        )
    }
}
