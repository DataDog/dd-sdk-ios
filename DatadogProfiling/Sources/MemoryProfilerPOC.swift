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
// Memory Profiler POC — Swift entry point (RUM-16460)
//
// Wraps the C++ POC implementation in a Swift-friendly interface so
// tests, benchmarks, and an eventual experimental SDK API can drive it
// without touching the C ABI directly.
//
// NOT FOR PRODUCTION USE. This is a validation spike. Nothing here is
// wired into the public SDK surface.
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
    /// Currently always nil in this POC — type attribution is deferred.
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
    let sampledFrees: UInt64
    let liveSampledAllocations: UInt64
    let reentrantSkips: UInt64
    let unsampledCalls: UInt64
}

/// Per-category memory size breakdown returned by the VM walker.
internal struct VMCategory: Sendable {
    let virtualBytes: UInt64
    let residentBytes: UInt64
    let dirtyBytes: UInt64
    let regionCount: UInt32
}

/// Full VM decomposition snapshot. Sums approximately to phys_footprint.
internal struct VMSnapshot: Sendable {
    let physFootprint: UInt64
    let residentSize: UInt64
    let virtualSize: UInt64
    let walkDurationNs: UInt64
    let totalRegions: UInt32
    let managedHeap: VMCategory
    let dylibs: VMCategory
    let stacks: VMCategory
    let mappedFiles: VMCategory
    let jitCode: VMCategory
    let other: VMCategory
}

/// Outcome of `MemoryProfilerPOC.start()`.
///
/// The first thing the POC validates is whether the default zone struct
/// is writable. The case distinguishes the three install paths and the
/// three failure modes — the RFC will quote these directly when it talks
/// about App Store risk.
internal enum MemoryInstallStatus: Sendable {
    case alreadyInstalled
    case installedDirect
    case installedViaMprotect
    case failedReadOnlyZone
    case failedNoZone
    case failedCollisionWithOtherHook

    init(_ raw: dd_memory_install_status_t) {
        switch raw {
        case DD_MEMORY_STATUS_ALREADY_INSTALLED: self = .alreadyInstalled
        case DD_MEMORY_STATUS_INSTALLED_DIRECT: self = .installedDirect
        case DD_MEMORY_STATUS_INSTALLED_MPROTECT: self = .installedViaMprotect
        case DD_MEMORY_STATUS_FAILED_READ_ONLY_ZONE: self = .failedReadOnlyZone
        case DD_MEMORY_STATUS_FAILED_NO_ZONE: self = .failedNoZone
        case DD_MEMORY_STATUS_FAILED_COLLISION: self = .failedCollisionWithOtherHook
        default: self = .failedNoZone
        }
    }
}

/// Swift facade for the POC. All methods are static; the underlying C
/// state is process-wide.
internal enum MemoryProfilerPOC {
    /// Default Poisson rate (512 KB).
    static let defaultPoissonRateBytes: UInt64 = UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)

    /// Installs malloc_zone hooks and starts Poisson sampling.
    /// - Parameter poissonRateBytes: Mean bytes between samples. Pass 0 for default.
    /// - Returns: How the install went. Tests and the findings doc consume this.
    @discardableResult
    static func start(poissonRateBytes: UInt64 = defaultPoissonRateBytes) -> MemoryInstallStatus {
        let raw = dd_memory_profiler_start(poissonRateBytes)
        return MemoryInstallStatus(raw)
    }

    /// Disables sampling. Hook function pointers remain installed; the
    /// hooks short-circuit via the global enabled flag.
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
            sampledFrees: raw.sampled_frees,
            liveSampledAllocations: raw.live_sampled_allocations,
            reentrantSkips: raw.reentrant_skips,
            unsampledCalls: raw.unsampled_calls
        )
    }

    /// Walks the process VM map and returns the categorized snapshot.
    /// Useful for the RSS↔managed-memory bridge the RFC needs.
    static func walkVMRegions() -> VMSnapshot {
        let raw = dd_vm_walk_regions()
        return VMSnapshot(
            physFootprint: raw.phys_footprint,
            residentSize: raw.resident_size,
            virtualSize: raw.virtual_size,
            walkDurationNs: raw.walk_duration_ns,
            totalRegions: raw.total_regions,
            managedHeap: VMCategory(raw.managed_heap),
            dylibs: VMCategory(raw.dylibs),
            stacks: VMCategory(raw.stacks),
            mappedFiles: VMCategory(raw.mapped_files),
            jitCode: VMCategory(raw.jit_code),
            other: VMCategory(raw.other)
        )
    }
}

extension VMCategory {
    init(_ raw: dd_vm_category_t) {
        self.init(
            virtualBytes: raw.virtual_bytes,
            residentBytes: raw.resident_bytes,
            dirtyBytes: raw.dirty_bytes,
            regionCount: raw.region_count
        )
    }
}

#endif // !os(watchOS)
