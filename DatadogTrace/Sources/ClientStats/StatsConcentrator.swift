/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Nanosecond-precision timestamp or duration.
internal typealias Nanoseconds = UInt64

/// Aggregates `SpanSnapshot`s into time-bucketed stats (hit counts, error counts,
/// duration distributions) keyed by an `AggregationKey`.
///
/// Thread-safety: All public methods dispatch onto a dedicated serial queue
/// so that `DDSpan.finish()` pays only the cost of enqueuing.
internal final class StatsConcentrator: @unchecked Sendable {
    /// Default bucket width: 10 seconds (in nanoseconds).
    static let defaultBucketDuration: Nanoseconds = 10_000_000_000

    /// OTel span kinds that qualify a span for stats, regardless of top-level or measured status.
    static let eligibleSpanKinds: Set<String> = ["server", "consumer", "client", "producer"]

    private let bucketDuration: Nanoseconds
    private let queue: DispatchQueue

    @ReadWriteLock
    private var buckets: [Nanoseconds: StatsBucket] = [:]

    /// Peer tag keys considered for downstream-service aggregation.
    private let peerTagKeys: [String]

    init(
        bucketDuration: Nanoseconds = StatsConcentrator.defaultBucketDuration,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys
    ) {
        self.bucketDuration = bucketDuration
        self.peerTagKeys = peerTagKeys
        self.queue = DispatchQueue(label: "com.datadoghq.client-stats.concentrator", qos: .utility)
    }

    /// Enqueues a span snapshot for stats aggregation.
    ///
    /// Called from `DDSpan.finish()` — the actual aggregation runs on a
    /// background serial queue to keep the caller's thread fast.
    func add(_ snapshot: SpanSnapshot) {
        queue.async { [weak self] in
            self?.aggregate(snapshot)
        }
    }

    /// Returns all buckets whose start time is strictly older than `cutoff`,
    /// removing them from the internal storage.
    func flush(olderThan cutoff: Nanoseconds) -> [StatsBucket] {
        var flushed: [StatsBucket] = []
        _buckets.mutate { buckets in
            let staleKeys = buckets.keys.filter { $0 < cutoff }
            for key in staleKeys {
                if let bucket = buckets.removeValue(forKey: key) {
                    flushed.append(bucket)
                }
            }
        }
        return flushed
    }

    // MARK: - Private

    private func aggregate(_ snapshot: SpanSnapshot) {
        guard Self.isEligible(snapshot) else {
            return
        }

        let bucketKey = alignedBucketStart(for: snapshot)
        _buckets.mutate { buckets in
            let key = AggregationKey(snapshot: snapshot, peerTagKeys: self.peerTagKeys)
            var group = buckets[bucketKey, default: StatsBucket(start: bucketKey, duration: self.bucketDuration)]
                .groups[key, default: ClientGroupedStats()]

            group.hits += 1
            if snapshot.isError {
                group.errors += 1
            }
            group.duration += snapshot.duration

            buckets[bucketKey, default: StatsBucket(start: bucketKey, duration: self.bucketDuration)]
                .groups[key] = group
        }
    }

    /// Returns the bucket start time (aligned to `bucketDuration` boundaries)
    /// based on the span's end time.
    private func alignedBucketStart(for snapshot: SpanSnapshot) -> Nanoseconds {
        let endTime = snapshot.startTime + snapshot.duration
        return endTime - (endTime % bucketDuration)
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

    // MARK: - Constants

    static let defaultPeerTagKeys: [String] = [
        "peer.service",
        "out.host",
        "server.address",
        "network.destination.name",
        "peer.hostname",
    ]
}

// MARK: - Supporting Types

/// One time bucket containing grouped stats.
internal struct StatsBucket: Sendable {
    let start: Nanoseconds
    let duration: Nanoseconds
    var groups: [AggregationKey: ClientGroupedStats] = [:]
}

/// The unique combination of fields that identifies a stats group within a bucket.
internal struct AggregationKey: Hashable, Sendable {
    let service: String
    let operationName: String
    let resource: String
    let httpStatusCode: UInt32
    let type: String
    let spanKind: String
    let isTraceRoot: Bool
    let isSynthetics: Bool
    let peerTagsHash: UInt64
    let serviceSource: String

    init(snapshot: SpanSnapshot, peerTagKeys: [String]) {
        self.service = snapshot.service
        self.operationName = snapshot.operationName
        self.resource = snapshot.resource
        self.httpStatusCode = snapshot.httpStatusCode
        self.type = snapshot.type
        self.spanKind = snapshot.spanKind ?? ""
        self.isTraceRoot = snapshot.parentSpanID == nil
        self.isSynthetics = snapshot.isSynthetics
        self.serviceSource = snapshot.serviceSource ?? ""
        self.peerTagsHash = FNV1aHash.hash(peerTags: snapshot.peerTags, keys: peerTagKeys)
    }
}

/// Accumulated stats for one aggregation group within a bucket.
internal struct ClientGroupedStats: Sendable {
    var hits: UInt64 = 0
    var errors: UInt64 = 0
    var duration: Nanoseconds = 0
}
