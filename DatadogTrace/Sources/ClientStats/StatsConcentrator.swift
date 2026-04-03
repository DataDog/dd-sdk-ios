/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Aggregates `SpanSnapshot`s into time-bucketed stats (hit counts, error counts,
/// duration distributions) keyed by an `AggregationKey`.
///
/// Thread-safety: All public methods dispatch onto a dedicated serial queue
/// so that `DDSpan.finish()` pays only the cost of enqueuing.
internal final class StatsConcentrator {
    /// Default bucket width: 10 seconds (in nanoseconds).
    static let defaultBucketDuration: UInt64 = 10_000_000_000

    private let bucketDuration: UInt64
    private let queue: DispatchQueue

    @ReadWriteLock
    private var buckets: [UInt64: StatsBucket] = [:]

    /// Peer tag keys considered for downstream-service aggregation.
    private let peerTagKeys: [String]

    init(
        bucketDuration: UInt64 = StatsConcentrator.defaultBucketDuration,
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
    func flush(olderThan cutoff: UInt64) -> [StatsBucket] {
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
            var bucket = buckets[bucketKey] ?? StatsBucket(start: bucketKey, duration: self.bucketDuration)
            let key = AggregationKey(snapshot: snapshot, peerTagKeys: self.peerTagKeys)
            var group = bucket.groups[key] ?? ClientGroupedStats()

            group.hits += 1
            if snapshot.isError {
                group.errors += 1
            }
            group.duration += snapshot.duration

            bucket.groups[key] = group
            buckets[bucketKey] = bucket
        }
    }

    /// Returns the bucket start time (aligned to `bucketDuration` boundaries)
    /// based on the span's end time.
    private func alignedBucketStart(for snapshot: SpanSnapshot) -> UInt64 {
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
        if let kind = snapshot.spanKind?.lowercased(),
           ["server", "consumer", "client", "producer"].contains(kind) {
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
internal struct StatsBucket {
    let start: UInt64
    let duration: UInt64
    var groups: [AggregationKey: ClientGroupedStats] = [:]
}

/// The unique combination of fields that identifies a stats group within a bucket.
internal struct AggregationKey: Hashable {
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
        self.peerTagsHash = Self.computePeerTagsHash(from: snapshot.peerTags, keys: peerTagKeys)
    }

    /// FNV-1a 64-bit hash of sorted peer tag key-value pairs.
    private static func computePeerTagsHash(from tags: [String: String], keys: [String]) -> UInt64 {
        let relevant = keys
            .compactMap { key -> (String, String)? in
                guard let value = tags[key], !value.isEmpty else {
                    return nil
                }
                return (key, value)
            }
            .sorted { $0.0 < $1.0 }

        guard !relevant.isEmpty else {
            return 0
        }

        var hash: UInt64 = 14_695_981_039_346_656_037 // FNV offset basis
        for (key, value) in relevant {
            for byte in "\(key)=\(value),".utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211 // FNV prime
            }
        }
        return hash
    }
}

/// Accumulated stats for one aggregation group within a bucket.
internal struct ClientGroupedStats {
    var hits: UInt64 = 0
    var errors: UInt64 = 0
    var duration: UInt64 = 0
}
