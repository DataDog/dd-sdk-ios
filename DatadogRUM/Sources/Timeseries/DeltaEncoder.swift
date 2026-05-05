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
    private static let scale = Int64(10_000)

    /// Encodes a batch of memory samples using delta compression.
    ///
    /// Returns `nil` if the batch contains one or fewer samples.
    ///
    /// Output format:
    /// ```
    /// {
    ///   "precision": 4,
    ///   "ts": [absoluteNs, delta1, delta2, ...],
    ///   "memory_max": [scaledInt64, delta1, delta2, ...],
    ///   "memory_percent": [scaledInt64, delta1, ...]
    /// }
    /// ```
    static func encodeMemory(_ batch: [RUMTimeseriesMemoryEvent.Timeseries.Data]) -> [String: Any]? {
        guard batch.count > 1 else {
            return nil
        }

        var ts: [Int64] = []
        var memoryMax: [Int64] = []
        var memoryPercent: [Int64] = []

        for (index, sample) in batch.enumerated() {
            if index == 0 {
                ts.append(sample.timestamp)
                memoryMax.append(Int64(round(sample.dataPoint.memoryMax * Double(scale))))
                memoryPercent.append(Int64(round(sample.dataPoint.memoryPercent * Double(scale))))
            } else {
                let prev = batch[index - 1]
                ts.append(sample.timestamp - prev.timestamp)
                memoryMax.append(
                    Int64(round(sample.dataPoint.memoryMax * Double(scale))) -
                    Int64(round(prev.dataPoint.memoryMax * Double(scale)))
                )
                memoryPercent.append(
                    Int64(round(sample.dataPoint.memoryPercent * Double(scale))) -
                    Int64(round(prev.dataPoint.memoryPercent * Double(scale)))
                )
            }
        }

        return [
            "precision": precision,
            "resolution": "ns",
            "ts": ts,
            "memory_max": memoryMax,
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
                cpuUsage.append(Int64(round(sample.dataPoint.cpuUsage * Double(scale))))
            } else {
                let prev = batch[index - 1]
                ts.append(sample.timestamp - prev.timestamp)
                cpuUsage.append(
                    Int64(round(sample.dataPoint.cpuUsage * Double(scale))) -
                    Int64(round(prev.dataPoint.cpuUsage * Double(scale)))
                )
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
