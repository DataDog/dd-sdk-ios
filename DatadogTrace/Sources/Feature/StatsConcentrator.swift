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
/// The deployment a span was recorded under.
///
/// A stats payload reports one `env`, `version` and `service` for all of its buckets, so stats from
/// different deployments are never aggregated together. The application version can change at
/// runtime, for example through `Datadog._internal.set(customVersion:)`.
internal struct DeploymentIdentity: Hashable, Encodable, Sendable {
    let env: String
    let version: String
    let service: String
}

internal struct AggregationKey: Hashable, Sendable {
    static let blockedValue = "tracer_blocked_value"

    let deployment: DeploymentIdentity
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

    /// Collapses operational dimensions while retaining the payload's deployment identity.
    static func collapsed(for deployment: DeploymentIdentity) -> AggregationKey {
        return AggregationKey(
            deployment: deployment,
            service: blockedValue,
            operationName: blockedValue,
            resource: blockedValue,
            httpStatusCode: 0,
            type: blockedValue,
            spanKind: blockedValue,
            isTraceRoot: .notSet,
            synthetics: false,
            peerTagsHash: StatsUtils.fnv64a([blockedValue]),
            serviceSource: blockedValue
        )
    }
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
    // Kept separate so a real span whose fields equal the sentinel cannot occupy an overflow group.
    var overflowGroups: [DeploymentIdentity: GroupedStats] = [:]
    var collapsedSpansCount: UInt64 = 0
    var droppedSpansCount: UInt64 = 0

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

    /// The deployment identity the bucket's spans were recorded under.
    ///
    /// The version can change while spans are buffered or while the bucket sits on disk, so the
    /// uploaded payload must report this identity rather than whatever is current at flush or
    /// upload time. Reporting the latter silently reattributes traffic to another version, and
    /// `_dd.compute_stats=0` stops the backend from correcting it.
    ///
    /// Optional so that buckets written by an earlier build still decode: `StatsRequestBuilder`
    /// falls back to the upload-time context for those rather than dropping the batch.
    let env: String?
    let version: String?
    let service: String?

    /// The client payload this bucket is uploaded in, assigned when the bucket is flushed and kept in
    /// every request, retry and upload after a restart, as the agent does for fragments of one payload.
    /// `ClientStatsFeature` assigns it before storing the bucket, so it is `nil` only before that.
    let payload: PayloadIdentity?

    /// How many pieces this bucket's payload was split into to fit the storage event limit. `nil` for
    /// whole buckets.
    let pieceCount: Int?

    /// Whether this bucket holds only some of its payload's groups.
    var isPartial: Bool { pieceCount != nil }

    /// Identifies a client stats payload.
    struct PayloadIdentity: Codable, Hashable, Sendable {
        /// The tracer instance that flushed the bucket.
        let runtimeID: String
        /// Unique among the payloads of `runtimeID`, and increasing in flush order.
        let sequence: UInt64
    }

    init(
        start: UInt64,
        duration: UInt64,
        stats: [ExportedGroupedStats],
        env: String? = nil,
        version: String? = nil,
        service: String? = nil,
        payload: PayloadIdentity? = nil,
        pieceCount: Int? = nil
    ) {
        self.start = start
        self.duration = duration
        self.stats = stats
        self.env = env
        self.version = version
        self.service = service
        self.payload = payload
        self.pieceCount = pieceCount
    }

    /// Splits the bucket into partial buckets whose estimated storage JSON fits in `budget` bytes, or
    /// returns the bucket itself when it already fits. Sizes are estimated, never encoded.
    ///
    /// Latency sketches store every bin between the fastest and slowest span, so a bucket within the
    /// cardinality limit can still exceed the storage event limit, which rejects it whole. Sketches
    /// alone keep a group well below the limit, but strings such as the resource are unbounded, so a
    /// group that exceeds the budget even alone is returned in `oversizedGroups`. Estimates are
    /// conservative, so a group can be split off or rejected before its actual JSON reaches the limit.
    ///
    /// Pieces keep the bucket's `payload`, so they are uploaded as one payload.
    ///
    /// - Parameter budget: The largest encoded size of a stored bucket. Must be positive and less
    ///   than `Int.max`; see `EstimatedJSONSize`.
    func split(toFit budget: Int) -> (pieces: [ExportedBucket], oversizedGroups: [ExportedGroupedStats]) {
        // Estimate each group once, for both the whole-bucket check and the packing below.
        let groupSizes = stats.map { $0.estimatedJSONSize(budget: budget) }
        guard estimatedJSONSize(groupSizes: groupSizes, budget: budget) == .exceedsBudget else {
            return ([self], [])
        }
        // A piece repeats the bucket's metadata. When that alone exceeds the budget, nothing fits.
        guard case .fits(let headerSize) = estimatedJSONHeaderSize(budget: budget) else {
            return ([], stats)
        }

        var pieces: [[ExportedGroupedStats]] = []
        var pieceSize = headerSize
        var oversizedGroups: [ExportedGroupedStats] = []
        for (group, groupSize) in zip(stats, groupSizes) {
            guard case .fits(let size) = groupSize, size <= budget - headerSize else {
                oversizedGroups.append(group)
                continue
            }
            // Groups after the first in a piece are preceded by a comma. All sizes here are at most
            // `budget`, so the arithmetic cannot overflow.
            if pieces.isEmpty || size + 1 > budget - pieceSize {
                pieces.append([group])
                pieceSize = headerSize + size
            } else {
                pieces[pieces.count - 1].append(group)
                pieceSize += 1 + size
            }
        }
        return (pieces.map { makePartial(with: $0, of: pieces.count) }, oversizedGroups)
    }

    /// A conservative estimate of this bucket's storage JSON size, measured against `budget`.
    func estimatedJSONSize(budget: Int) -> EstimatedJSONSize {
        estimatedJSONSize(groupSizes: stats.map { $0.estimatedJSONSize(budget: budget) }, budget: budget)
    }

    /// The calculation `split(toFit:)` uses, given each group's estimate.
    private func estimatedJSONSize(groupSizes: [EstimatedJSONSize], budget: Int) -> EstimatedJSONSize {
        var size = JSONSizeEstimator(budget: budget)
        size.add(estimatedJSONHeaderSize(budget: budget))
        for (index, groupSize) in groupSizes.enumerated() {
            if index > 0 {
                size.add(bytes: 1) // separating comma
            }
            size.add(groupSize)
        }
        return size.estimate
    }

    private func estimatedJSONHeaderSize(budget: Int) -> EstimatedJSONSize {
        var size = JSONSizeEstimator(budget: budget)
        // Covers keys, punctuation, and maximum-width integers, including the payload identity and a
        // piece count, so a piece's header is never larger than this. String contents are counted
        // separately. Keep this bound in sync with the Codable fields.
        size.add(bytes: 256)
        if let env = env {
            size.add(string: env)
        }
        if let version = version {
            size.add(string: version)
        }
        if let service = service {
            size.add(string: service)
        }
        if let payload = payload {
            size.add(string: payload.runtimeID)
        }
        return size.estimate
    }

    /// A copy of this bucket uploaded in `payload`.
    func assigning(_ payload: PayloadIdentity) -> ExportedBucket {
        ExportedBucket(
            start: start,
            duration: duration,
            stats: stats,
            env: env,
            version: version,
            service: service,
            payload: payload,
            pieceCount: pieceCount
        )
    }

    private func makePartial(with stats: [ExportedGroupedStats], of pieceCount: Int) -> ExportedBucket {
        ExportedBucket(
            start: start,
            duration: duration,
            stats: stats,
            env: env,
            version: version,
            service: service,
            payload: payload,
            pieceCount: pieceCount
        )
    }
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

    /// A conservative estimate of this group's storage JSON size, measured against `budget`.
    func estimatedJSONSize(budget: Int) -> EstimatedJSONSize {
        var size = JSONSizeEstimator(budget: budget)
        // Covers all 16 keys, punctuation, booleans, and maximum-width numeric fields.
        // Variable strings, data, and peer-tag array entries are added below.
        size.add(bytes: 512)
        for string in [service, name, resource, type, spanKind, serviceSource] {
            size.add(string: string)
        }
        size.add(base64Bytes: okSummary.count)
        size.add(base64Bytes: errorSummary.count)
        for tag in peerTags {
            size.add(bytes: 1) // separating comma (conservative for the first entry)
            size.add(string: tag)
        }
        return size.estimate
    }
}

// MARK: - Storage Size Estimation

/// A conservative estimate of a value's storage JSON size, measured against a budget.
///
/// An estimate is never below the actual encoded size. It is only computed up to the budget: once a
/// value is known not to fit, its exact size is not needed, and stopping there keeps the scan of long
/// strings short. That is why an over-budget value has no size, rather than a number that could be
/// mistaken for one in later arithmetic.
internal enum EstimatedJSONSize: Equatable {
    /// The value encodes to at most this many bytes, which is within the budget.
    case fits(Int)
    /// The value encodes to more than the budget.
    case exceedsBudget
}

/// Accumulates an `EstimatedJSONSize` without encoding anything.
///
/// The running total stops at one byte over the budget, which only marks it as exceeded. The budget
/// must be positive and less than `Int.max`, so that marker can always be represented; anything else
/// is a programming error, caught in development and clamped in production.
private struct JSONSizeEstimator {
    private let budget: Int
    /// Never above `budget + 1`.
    private var total = 0

    init(budget: Int) {
        dd_assert(budget > 0 && budget < .max, "The storage size budget must be positive and less than Int.max, got \(budget).")
        self.budget = min(max(budget, 1), .max - 1)
    }

    var estimate: EstimatedJSONSize {
        total > budget ? .exceedsBudget : .fits(total)
    }

    private var remaining: Int {
        budget + 1 - total
    }

    mutating func add(bytes: Int) {
        total += min(bytes, remaining)
    }

    mutating func add(_ size: EstimatedJSONSize) {
        switch size {
        case .fits(let bytes):
            add(bytes: bytes)
        case .exceedsBudget:
            total = budget + 1
        }
    }

    mutating func add(string: String) {
        add(bytes: 2) // quotes
        let utf8 = string.utf8
        // Escaping never shortens a string, so one that does not fit unescaped needs no scan. The
        // count is cheap for native Swift strings; bridged ones may compute it.
        guard utf8.count < remaining else {
            total = budget + 1
            return
        }
        let escapeLimit = remaining - utf8.count
        let escapeBytes = utf8.withContiguousStorageIfAvailable { Self.escapeBytes(in: $0, stoppingAt: escapeLimit) }
            ?? Self.escapeBytes(in: utf8, stoppingAt: escapeLimit)
        add(bytes: utf8.count)
        add(bytes: escapeBytes)
    }

    /// Bytes that JSON escaping can add to `bytes`, an upper bound. Stops once it reaches `limit`,
    /// since the caller then only needs to know the budget is exceeded.
    private static func escapeBytes<Bytes: Sequence>(in bytes: Bytes, stoppingAt limit: Int) -> Int where Bytes.Element == UInt8 {
        var extra = 0
        for byte in bytes {
            if byte < 0x20 {
                extra += 5 // controls can use six-byte escapes
            } else if byte >= 0x80 {
                // At most three JSON bytes per UTF-8 byte even if Unicode is escaped:
                // six bytes for a two-byte scalar, twelve for a four-byte surrogate pair.
                extra += 2
            } else if byte == 0x22 || byte == 0x5c {
                extra += 1 // quote and backslash; the storage encoder does not escape slashes
            } else {
                continue
            }
            if extra >= limit {
                break
            }
        }
        return extra
    }

    mutating func add(base64Bytes count: Int) {
        add(bytes: 2) // quotes
        // Four bytes per complete triplet plus a padded quartet for any remaining bytes.
        let triplets = count / 3
        if triplets > remaining / 4 {
            total = budget + 1
        } else {
            add(bytes: triplets * 4)
            if count % 3 != 0 {
                add(bytes: 4)
            }
        }
    }
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
        // `UInt64(_:)` traps outside its range, so saturate instead. `Double(UInt64.max)` is exactly
        // 2^64, which a group's summed duration reaches with a single span whose duration saturated,
        // for example one started at `Date.distantPast`. Counters are never negative or NaN; both
        // map to 0.
        guard value > 0 else {
            return 0
        }
        guard value < Double(UInt64.max) else {
            return .max
        }
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

    /// Maximum number of regular groups retained in one time bucket, across all deployments.
    /// Overflow groups are additional to this limit. This bounds sketch count per bucket, not
    /// total memory or serialized payload bytes.
    static let defaultMaxGroupsPerBucket = 100

    /// Maximum number of overflow groups in one time bucket, one per deployment. Only the version
    /// can change at runtime, so a bucket rarely sees more than two deployments.
    static let defaultMaxOverflowGroupsPerBucket = 10

    /// Configured peer tag keys to extract from spans.
    static let defaultPeerTagKeys: [String] = [
        "peer.service",
        "db.instance",
        "db.system",
        "out.host",
        "net.peer.name",
        "server.address"
    ]

    /// Length of each aggregation window, in nanoseconds. A finished span is placed in the bucket
    /// whose start is its end time rounded down to a multiple of this value, so all spans completing
    /// within the same window aggregate together. Defaults to `defaultBucketDuration` (10s), matching
    /// the backend's stats granularity.
    private let bucketDuration: Nanoseconds

    /// How many recent bucket windows to retain before a window becomes eligible for flush. With the
    /// default of `2`, the current and immediately preceding windows are held back so late-arriving
    /// spans can still land in their window; only windows older than that are exported. This trades a
    /// small flush delay for fewer partially-filled buckets. Matches Go's `defaultBufferLen`.
    private let bufferLen: Int

    /// Span attribute keys whose values are promoted to peer tags and folded into the aggregation key
    /// for client/producer/consumer spans (e.g. `peer.service`, `db.instance`). These act as extra
    /// stats dimensions, so the set must match the backend's configured peer tags: an over- or
    /// under-broad set would split or merge groups differently than the backend expects. Defaults to
    /// `defaultPeerTagKeys`.
    private let peerTagKeys: [String]

    /// New keys beyond this limit use their deployment's overflow group; retained keys keep their detail.
    private let maxGroupsPerBucket: Int
    /// Spans that need an overflow group beyond this limit are dropped and counted.
    private let maxOverflowGroupsPerBucket: Int
    private let metricController: TraceClientStatsMetricController

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

    /// Creates a concentrator.
    ///
    /// Bucketing and flushing are driven by the `now` value passed to each `add`/`flush` call rather
    /// than by wall-clock reads, which keeps the type deterministic and testable; `now` here only
    /// seeds the initial `oldestTs`.
    ///
    /// - Parameters:
    ///   - now: Current time in nanoseconds, used to seed `oldestTs` (the earliest window that still
    ///     accepts spans).
    ///   - initialConsent: Tracking consent at creation. `.granted`/`.pending` record, `.notGranted`
    ///     drops. Defaults to `.pending` (record-but-hold) — see `currentConsent`.
    ///   - bucketDuration: See `bucketDuration`. Defaults to `defaultBucketDuration`.
    ///   - bufferLen: See `bufferLen`. Defaults to `defaultBufferLen`.
    ///   - peerTagKeys: See `peerTagKeys`. Defaults to `defaultPeerTagKeys`.
    ///   - maxGroupsPerBucket: Maximum regular groups per time bucket, clamped to at least one.
    ///     Overflow groups are additional to this limit.
    ///   - maxOverflowGroupsPerBucket: Maximum overflow groups per time bucket, clamped to at least one.
    ///   - telemetry: Receives collapsed and dropped span counts when an overflowing bucket is flushed.
    init(
        now: Nanoseconds,
        initialConsent: TrackingConsent = .pending,
        bucketDuration: Nanoseconds = StatsConcentrator.defaultBucketDuration,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys,
        maxGroupsPerBucket: Int = StatsConcentrator.defaultMaxGroupsPerBucket,
        maxOverflowGroupsPerBucket: Int = StatsConcentrator.defaultMaxOverflowGroupsPerBucket,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.bucketDuration = bucketDuration
        self.bufferLen = bufferLen
        self.peerTagKeys = peerTagKeys
        self.maxGroupsPerBucket = max(1, maxGroupsPerBucket)
        self.maxOverflowGroupsPerBucket = max(1, maxOverflowGroupsPerBucket)
        self.metricController = TraceClientStatsMetricController(telemetry: telemetry)
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

        // Saturate rather than trap: a start time clamped to `UInt64.max`, for example
        // `Date.distantFuture`, plus any positive duration would overflow and crash the host app.
        let (summedEndTime, didOverflow) = snapshot.startTime.addingReportingOverflow(snapshot.duration)
        let endTime = didOverflow ? UInt64.max : summedEndTime
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

            if let group = bucket.groups[aggregationKey] {
                group.update(with: snapshot)
                return
            }

            // Check before allocating sketches. Do not retain the original overflow keys.
            guard bucket.groups.count < maxGroupsPerBucket else {
                // One overflow group per deployment, like the agent's collapsed key, so overflow is
                // exported with the rest of its bucket and never split across payloads.
                let deployment = aggregationKey.deployment
                if let overflowGroup = bucket.overflowGroups[deployment] {
                    overflowGroup.update(with: snapshot)
                } else if bucket.overflowGroups.count < maxOverflowGroupsPerBucket {
                    let overflowGroup = GroupedStats(peerTags: [AggregationKey.blockedValue])
                    overflowGroup.update(with: snapshot)
                    bucket.overflowGroups[deployment] = overflowGroup
                } else {
                    if bucket.droppedSpansCount < .max {
                        bucket.droppedSpansCount += 1
                    }
                    return
                }
                if bucket.collapsedSpansCount < .max {
                    bucket.collapsedSpansCount += 1
                }
                return
            }

            let group = GroupedStats(peerTags: peerTagStrings)
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

            // A bucket is complete once it is older than the retention window ending at `now`, i.e.
            // when `ts <= now - window`. Comparisons stay in the `UInt64` domain: a pathological span
            // whose start time saturated to `UInt64.max` could produce a bucket key above `Int64.max`,
            // and casting that to `Int64` would trap and crash the host app.
            //
            // When `now < window`, `now - window` would be negative, so no bucket is old enough yet and
            // nothing (short of a forced flush) is eligible. Clamping the cutoff to `0` instead would
            // wrongly flush a bucket sitting exactly at `ts == 0`, so guard that case explicitly rather
            // than relying on a clamped cutoff.
            let window = UInt64(bufferLen) * bucketDuration
            let isFlushable: (UInt64) -> Bool
            if force {
                isFlushable = { _ in true }
            } else if now >= window {
                let cutoff = now - window
                isFlushable = { $0 <= cutoff }
            } else {
                isFlushable = { _ in false }
            }
            var flushed: [ExportedBucket] = []
            var keysToRemove: [UInt64] = []

            for (ts, bucket) in buckets {
                if !isFlushable(ts) {
                    continue
                }
                keysToRemove.append(ts)
                // One metric per overflowing bucket, rather than one per collapsed span. Consent
                // revocation removes the bucket and its counter together.
                metricController.sendCollapsedSpans(
                    collapsedCount: bucket.collapsedSpansCount,
                    droppedCount: bucket.droppedSpansCount,
                    limit: maxGroupsPerBucket,
                    overflowLimit: maxOverflowGroupsPerBucket
                )

                // Groups from different deployments can share a time window but never a payload, so
                // each deployment gets its own exported bucket, reporting the identity its spans were
                // recorded under.
                var statsByDeployment: [DeploymentIdentity: [ExportedGroupedStats]] = [:]
                for (key, group) in bucket.groups {
                    statsByDeployment[key.deployment, default: []].append(export(group, for: key))
                }
                for (deployment, group) in bucket.overflowGroups {
                    statsByDeployment[deployment, default: []].append(export(group, for: .collapsed(for: deployment)))
                }

                for (deployment, exportedStats) in statsByDeployment {
                    flushed.append(ExportedBucket(
                        start: bucket.start,
                        duration: bucket.duration,
                        stats: exportedStats,
                        env: deployment.env,
                        version: deployment.version,
                        service: deployment.service
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

    private func export(_ group: GroupedStats, for key: AggregationKey) -> ExportedGroupedStats {
        return ExportedGroupedStats(
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
            deployment: snapshot.deployment,
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
