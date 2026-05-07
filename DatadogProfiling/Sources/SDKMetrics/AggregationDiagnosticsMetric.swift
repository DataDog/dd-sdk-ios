/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

/// Tracks profiling aggregation diagnostics to be added to telemetry metrics.
internal final class AggregationDiagnosticsMetric {
    internal enum Constants {
        /// Namespace for bundling profiling diagnostics.
        static let diagnosticsKey = "profiling_diagnostics"
    }

    /// Number of sampled batches dropped during aggregation.
    let droppedBatchCount: UInt64
    /// Number of sampled stack traces contained in dropped batches.
    let droppedSampleCount: UInt64
    /// Maximum queued aggregation memory observed, in bytes.
    let maxPendingBytes: UInt64

    init(
        droppedBatchCount: UInt64 = 0,
        droppedSampleCount: UInt64 = 0,
        maxPendingBytes: UInt64 = 0
    ) {
        self.droppedBatchCount = droppedBatchCount
        self.droppedSampleCount = droppedSampleCount
        self.maxPendingBytes = maxPendingBytes
    }

    func asMetricAttributes() -> [String: Encodable]? {
        [Constants.diagnosticsKey: Attributes(aggregation: self)]
    }
}

extension AggregationDiagnosticsMetric: Encodable {
    enum CodingKeys: String, CodingKey {
        case droppedBatchCount = "dropped_batch_count"
        case droppedSampleCount = "dropped_sample_count"
        case maxPendingBytes = "max_pending_bytes"
    }
}

extension AggregationDiagnosticsMetric {
    static func consumeDiagnostics() -> AggregationDiagnosticsMetric {
        let diagnostics = dd_profiler_diagnostics()

        return AggregationDiagnosticsMetric(
            droppedBatchCount: diagnostics.dropped_batch_count,
            droppedSampleCount: diagnostics.dropped_sample_count,
            maxPendingBytes: diagnostics.max_pending_bytes
        )
    }

    /// Container to encode Profiling diagnostics according to the spec.
    internal struct Attributes: Encodable {
        /// Diagnostics for the serialized aggregation worker.
        let aggregation: AggregationDiagnosticsMetric
    }
}

#endif
