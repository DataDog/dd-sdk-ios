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

// =====================================================================
// Memory profiler introspection bridge (RUM-16460)
//
// Thin Swift wrapper over the passive sampler's C introspection API
// (heap snapshot + diagnostic counters). The sampler is fed in production
// by the +allocWithZone: / swift_allocObject interception paths; this
// bridge only reads its state and is used by tests.
// =====================================================================

/// One sampled live allocation captured in a heap snapshot.
internal struct MemorySample: Sendable, Equatable {
    /// Allocation pointer value (informational only).
    let address: UInt64
    /// Allocation size in bytes.
    let size: UInt64
    /// Poisson scaling weight: multiply size by this to recover the
    /// unbiased byte total this sample represents.
    let weight: Double
    /// Stack frame instruction pointers, deepest at index 0.
    let frames: [UInt64]
    /// Monotonic timestamp of allocation, nanoseconds since profiler start.
    let timestampNs: UInt64
    /// Class name for Obj-C/Swift instances; nil for raw C allocations.
    let className: String?
}

/// Point-in-time snapshot of live sampled allocations.
internal struct MemorySnapshot: Sendable {
    /// Monotonic timestamp of snapshot capture, nanoseconds since start.
    let timestampNs: UInt64
    /// Live sampled allocations at capture time.
    let samples: [MemorySample]
}

/// Diagnostic counters exposed by the running profiler.
internal struct MemoryProfilerDiagnostics: Sendable {
    let totalBytesAllocated: UInt64
    let totalAllocations: UInt64
    let sampledAllocations: UInt64
    let droppedSamples: UInt64
    /// Sampled allocations dropped because the per-window alloc log was full.
    /// Every drop is unrecoverable understatement in `alloc_*`, so this is the
    /// counter the back-pressure controller exists to hold at zero.
    let droppedAllocRecords: UInt64
    let sampledFrees: UInt64
    let liveSampledAllocations: UInt64
    let reentrantSkips: UInt64
    let unsampledCalls: UInt64
    /// Configured base interval for the session.
    let baseRateBytes: UInt64
    /// Interval currently in force; `baseRateBytes` unless widened.
    let effectiveRateBytes: UInt64
    /// Peak fill of the fixed-capacity structures this session, in entries.
    let occupancyHighWater: UInt64
    let rateWidenEvents: UInt64
    let rateNarrowEvents: UInt64

    /// How far back-pressure has widened the interval, as a multiple of the base.
    var rateMultiplier: UInt64 {
        baseRateBytes > 0 ? effectiveRateBytes / baseRateBytes : 1
    }
}

/// Swift facade over the passive sampler's C introspection API. All methods
/// are static; the underlying C state is process-wide.
internal enum MemoryProfilerProbe {
    /// Disables sampling. The interception trampolines stay installed
    /// (never-restore) and short-circuit via the global enabled flag.
    static func stop() {
        dd_memory_profiler_stop()
    }

    /// True while profiling is enabled.
    static var isRunning: Bool {
        dd_memory_profiler_is_running()
    }

    /// Returns a point-in-time copy of the live sampled set.
    static func captureSnapshot() -> MemorySnapshot {
        var raw = dd_memory_snapshot_capture()
        defer { dd_memory_snapshot_destroy(&raw) }

        let samples: [MemorySample]
        if raw.sample_count > 0, let samplesPtr = raw.samples {
            let buffer = UnsafeBufferPointer(start: samplesPtr, count: raw.sample_count)
            samples = buffer.map { rawSample in
                // The C struct stores a fixed-capacity frames[] array;
                // copy only the valid prefix into a Swift Array.
                let frameCount = Int(rawSample.frame_count)
                let frames: [UInt64] = withUnsafeBytes(of: rawSample.frames) { ptr in
                    let base = ptr.bindMemory(to: UInt64.self).baseAddress!
                    return Array(UnsafeBufferPointer(start: base, count: frameCount))
                }
                let className: String? = rawSample.class_name.flatMap { String(cString: $0) }
                return MemorySample(
                    address: rawSample.addr,
                    size: rawSample.size,
                    weight: rawSample.weight,
                    frames: frames,
                    timestampNs: rawSample.timestamp_ns,
                    className: className
                )
            }
        } else {
            samples = []
        }

        return MemorySnapshot(timestampNs: raw.timestamp_ns, samples: samples)
    }

    /// Returns a snapshot of diagnostic counters.
    static func diagnostics() -> MemoryProfilerDiagnostics {
        let raw = dd_memory_profiler_diagnostics()
        return MemoryProfilerDiagnostics(
            totalBytesAllocated: raw.total_bytes_allocated,
            totalAllocations: raw.total_allocations,
            sampledAllocations: raw.sampled_allocations,
            droppedSamples: raw.dropped_samples,
            droppedAllocRecords: raw.dropped_alloc_records,
            sampledFrees: raw.sampled_frees,
            liveSampledAllocations: raw.live_sampled_allocations,
            reentrantSkips: raw.reentrant_skips,
            unsampledCalls: raw.unsampled_calls,
            baseRateBytes: raw.base_rate_bytes,
            effectiveRateBytes: raw.effective_rate_bytes,
            occupancyHighWater: raw.occupancy_high_water,
            rateWidenEvents: raw.rate_widen_events,
            rateNarrowEvents: raw.rate_narrow_events
        )
    }

    /// Drains the current `alloc_*` window, returning every allocation sampled
    /// since the last drain and resetting the window. This is also the point at
    /// which the back-pressure controller re-evaluates relief, so tests that
    /// exercise adaptation must drive windows through this call.
    static func captureAllocWindow() -> MemorySnapshot {
        var raw = dd_memory_alloc_window_capture()
        defer { dd_memory_snapshot_destroy(&raw) }

        guard raw.sample_count > 0, let samplesPtr = raw.samples else {
            return MemorySnapshot(timestampNs: raw.timestamp_ns, samples: [])
        }

        let samples = UnsafeBufferPointer(start: samplesPtr, count: raw.sample_count).map { rawSample in
            MemorySample(
                address: rawSample.addr,
                size: rawSample.size,
                weight: rawSample.weight,
                frames: [],
                timestampNs: rawSample.timestamp_ns,
                className: rawSample.class_name.flatMap { String(cString: $0) }
            )
        }
        return MemorySnapshot(timestampNs: raw.timestamp_ns, samples: samples)
    }
}

#endif // !os(watchOS)
