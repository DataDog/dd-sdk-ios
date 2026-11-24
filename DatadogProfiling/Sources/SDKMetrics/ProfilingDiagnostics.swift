/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

// Keep native types out of the distributed Swift module interface.
@_implementationOnly import DatadogMachProfiler

/// Diagnostics for the CPU and memory captures described by one profiling report.
internal struct ProfilingDiagnostics: Encodable {
    enum Constants {
        static let diagnosticsKey = "profiling_diagnostics"
    }

    let cpu: CPUDiagnostics?
    let memory: MemoryDiagnostics?

    /// Diagnostics for the CPU profiler's aggregation worker.
    struct CPUDiagnostics: Encodable {
        /// Number of sampled batches dropped during aggregation.
        let droppedBatchCount: UInt64
        /// Number of sampled stack traces contained in dropped batches.
        let droppedSampleCount: UInt64
        /// Maximum queued aggregation memory observed, in bytes.
        let maxPendingBytes: UInt64

        enum CodingKeys: String, CodingKey {
            case droppedBatchCount = "dropped_batch_count"
            case droppedSampleCount = "dropped_sample_count"
            case maxPendingBytes = "max_pending_bytes"
        }

        static func consume() -> CPUDiagnostics {
            let diagnostics = dd_profiler_diagnostics()
            return CPUDiagnostics(
                droppedBatchCount: diagnostics.dropped_batch_count,
                droppedSampleCount: diagnostics.dropped_sample_count,
                maxPendingBytes: diagnostics.max_pending_bytes
            )
        }
    }
}
#endif
