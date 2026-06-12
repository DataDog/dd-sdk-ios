/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Encodes timeseries batches using delta compression.
///
/// The first value in each array is absolute; subsequent values are deltas from the previous.
/// All floating-point fields are scaled by `10^precision` and stored as `Int64`.
internal enum DeltaEncoder {
    private static let precision = 4
    private static let scale = 10_000.0

    /// Encodes a batch of memory samples using delta compression.
    ///
    /// Returns `nil` if the batch contains one or fewer samples.
    ///
    /// Output format:
    /// ```
    /// {
    ///   "precision": 4,
    ///   "ts": [absoluteNs, delta1, delta2, ...],
    ///   "memory_footprint": [scaledInt64, delta1, delta2, ...],
    ///   "memory_percent": [scaledInt64, delta1, ...]
    /// }
    /// ```
    static func encodeMemory(_ batch: [RUMTimeseriesMemoryEvent.Timeseries.Data]) -> [String: Any]? {
        guard batch.count > 1 else {
            return nil
        }

        var ts: [Int64] = []
        var memoryFootprint: [Int64] = []
        var memoryPercent: [Int64] = []

        for (index, sample) in batch.enumerated() {
            if index == 0 {
                ts.append(sample.timestamp)
                memoryFootprint.append(Int64.ddWithNoOverflow(sample.dataPoint.memoryFootprint * scale))
                memoryPercent.append(Int64.ddWithNoOverflow(sample.dataPoint.memoryPercent * scale))
            } else {
                let prev = batch[index - 1]
                let (tsDelta, _) = sample.timestamp.subtractingReportingOverflow(prev.timestamp)
                ts.append(tsDelta)
                let curMax = Int64.ddWithNoOverflow(sample.dataPoint.memoryFootprint * scale)
                let prevMax = Int64.ddWithNoOverflow(prev.dataPoint.memoryFootprint * scale)
                let (maxDelta, _) = curMax.subtractingReportingOverflow(prevMax)
                memoryFootprint.append(maxDelta)
                let curPct = Int64.ddWithNoOverflow(sample.dataPoint.memoryPercent * scale)
                let prevPct = Int64.ddWithNoOverflow(prev.dataPoint.memoryPercent * scale)
                let (pctDelta, _) = curPct.subtractingReportingOverflow(prevPct)
                memoryPercent.append(pctDelta)
            }
        }

        return [
            "precision": precision,
            "resolution": "ns",
            "ts": ts,
            "memory_footprint": memoryFootprint,
            "memory_percent": memoryPercent
        ]
    }

    /// Encodes a batch of CPU samples using delta compression.
    ///
    /// Returns `nil` if the batch contains one or fewer samples.
    ///
    /// Output format:
    /// ```
    /// {
    ///   "precision": 4,
    ///   "ts": [absoluteNs, delta1, delta2, ...],
    ///   "cpu_usage": [scaledInt64, delta1, delta2, ...]
    /// }
    /// ```
    static func encodeCPU(_ batch: [RUMTimeseriesCpuEvent.Timeseries.Data]) -> [String: Any]? {
        guard batch.count > 1 else {
            return nil
        }

        var ts: [Int64] = []
        var cpuUsage: [Int64] = []

        for (index, sample) in batch.enumerated() {
            if index == 0 {
                ts.append(sample.timestamp)
                cpuUsage.append(Int64.ddWithNoOverflow(sample.dataPoint.cpuUsage * scale))
            } else {
                let prev = batch[index - 1]
                let (tsDelta, _) = sample.timestamp.subtractingReportingOverflow(prev.timestamp)
                ts.append(tsDelta)
                let cur = Int64.ddWithNoOverflow(sample.dataPoint.cpuUsage * scale)
                let prv = Int64.ddWithNoOverflow(prev.dataPoint.cpuUsage * scale)
                let (delta, _) = cur.subtractingReportingOverflow(prv)
                cpuUsage.append(delta)
            }
        }

        return [
            "precision": precision,
            "resolution": "ns",
            "ts": ts,
            "value": cpuUsage
        ]
    }
}
