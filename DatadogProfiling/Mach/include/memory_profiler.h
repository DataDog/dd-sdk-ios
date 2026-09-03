/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PROFILER_H_
#define DD_MEMORY_PROFILER_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// Memory Profiler RFC reference implementation (RUM-16460)
//
// The API remains internal while the RFC is under review. The sampling,
// live-table, snapshot, and lifecycle behavior is implemented with the
// correctness guarantees expected from the production design.
// =====================================================================

// MARK: - Configuration

/**
 * Default Poisson sampling rate in bytes.
 *
 * Every byte of allocated memory has probability 1/B of being represented
 * in the sampled set. Lower values produce denser samples (more overhead);
 * higher values produce sparser samples (less overhead, less precision for
 * small allocations).
 *
 * 512 KB is the same rate used by Go's heap profiler and heapprofd.
 */
#define DD_MEMORY_POISSON_DEFAULT_RATE_BYTES (512ULL * 1024ULL)

/**
 * Maximum stack frames captured per sampled allocation.
 *
 * Mirrors the CPU profiler's default. Frames beyond this are discarded.
 */
#define DD_MEMORY_DEFAULT_STACK_DEPTH 64

/**
 * Origin of a sampled allocation: which interception path recorded it.
 */
typedef enum {
    /// malloc_zone hook (raw C / unclassified allocations).
    DD_MEMORY_SOURCE_ZONE = 0,
    /// Objective-C +allocWithZone: swizzle.
    DD_MEMORY_SOURCE_OBJC = 1,
    /// Pure-Swift swift_allocObject rebinding.
    DD_MEMORY_SOURCE_SWIFT = 2
} dd_memory_source_t;

// MARK: - Status and diagnostics

/**
 * Snapshot of overhead and counters for the running profiler.
 */
typedef struct dd_memory_diagnostics {
    /** Total bytes allocated since profiler start (across all hooked allocations). */
    uint64_t total_bytes_allocated;
    /** Total allocations seen (not sampled count — every call). */
    uint64_t total_allocations;
    /** Number of allocations actually sampled (subset of total_allocations). */
    uint64_t sampled_allocations;
    /** Sampled allocations dropped because they could not enter the live table. */
    uint64_t dropped_samples;
    /** Sampled allocations dropped from the per-window alloc log (window full). */
    uint64_t dropped_alloc_records;
    /** Number of sampled frees recorded. */
    uint64_t sampled_frees;
    /** Number of sampled allocations currently considered live. */
    uint64_t live_sampled_allocations;
    /** Number of reentrant calls skipped via the reentrancy guard. */
    uint64_t reentrant_skips;
    /** Number of hook calls that fell through unsampled (the common case). */
    uint64_t unsampled_calls;
} dd_memory_diagnostics_t;

/**
 * One sampled live allocation in the heap snapshot.
 */
typedef struct dd_memory_sample {
    /** Allocation pointer (informational; do not dereference). */
    uint64_t addr;
    /** Allocation size in bytes. */
    uint64_t size;
    /** Poisson scaling weight: 1/P where P is the probability this allocation was sampled.
     *  Multiply size by weight to recover the unbiased byte total. */
    double weight;
    /** Class name for Objective-C/Swift instances; NULL for raw C allocations. */
    const char* class_name;
    /** Interception path that recorded this sample. */
    dd_memory_source_t source;
    /** Stack frame instruction pointers, deepest at index 0. */
    uint64_t frames[DD_MEMORY_DEFAULT_STACK_DEPTH];
    /** Number of valid entries in `frames`. */
    uint32_t frame_count;
    /** Monotonic timestamp of allocation, nanoseconds since profiler start. */
    uint64_t timestamp_ns;
} dd_memory_sample_t;

/**
 * Heap snapshot result.
 *
 * Caller takes ownership of `samples` and must release it with
 * `dd_memory_snapshot_destroy`.
 */
typedef struct dd_memory_snapshot {
    dd_memory_sample_t* samples;
    size_t sample_count;
    /** Monotonic timestamp of snapshot capture, nanoseconds since profiler start. */
    uint64_t timestamp_ns;
} dd_memory_snapshot_t;

// MARK: - Lifecycle

/**
 * Starts the profiler in passive mode: allocates the sample table, initializes
 * the Poisson sampler, and flips the enabled flag — but installs NO malloc_zone
 * hooks. Allocations must be reported externally via dd_memory_observe_allocation.
 *
 * Used by the +allocWithZone: interception (objc_alloc_hook): the Obj-C
 * runtime hands the swizzle a freshly-allocated object with its class identity
 * intact, and we observe it through this passive path.
 *
 * @param poisson_rate_bytes Average bytes between sampled allocations. Pass 0 for default.
 * @return true if the passive mode was activated; false if sample table allocation failed.
 */
bool dd_memory_profiler_start_passive(uint64_t poisson_rate_bytes);

/**
 * Records an externally-observed allocation. Goes through the same Poisson
 * sampler, reentrancy guard, and side-table machinery as the zone-hook path.
 *
 * @param ptr Allocation pointer; NULL is a no-op.
 * @param size Allocation size in bytes.
 * @param class_name Optional class name (e.g. from class_getName for Obj-C instances).
 *                   Must outlive the sample (typically a static string from the Obj-C runtime).
 *                   Pass NULL when no class identity is available.
 */
void dd_memory_observe_allocation(const void* ptr, uint64_t size, const char* class_name);

/**
 * Records an externally-observed allocation, tagged with its interception source.
 * Same machinery as dd_memory_observe_allocation; the source is stored on the
 * sample and surfaces as a pprof label.
 *
 * @param ptr Allocation pointer; NULL is a no-op.
 * @param size Allocation size in bytes.
 * @param class_name Optional class name; must outlive the sample. NULL when unavailable.
 * @param source Interception path recording this allocation.
 */
void dd_memory_observe_allocation_with_source(const void* ptr, uint64_t size,
                                              const char* class_name,
                                              dd_memory_source_t source);

/**
 * Produces a class name for a sampled allocation. Must not allocate in a way
 * that depends on the profiler being re-entrant; it is called inside the
 * reentrancy guard, so any allocation it triggers is short-circuited.
 *
 * @param context Opaque value passed through from the observe call.
 * @return Class name that outlives the sample, or NULL if unavailable.
 */
typedef const char* (*dd_memory_class_name_resolver_t)(void* context);

/**
 * Records an externally-observed allocation, resolving the class name lazily.
 *
 * Identical to dd_memory_observe_allocation_with_source except that the class
 * name is produced by `resolver` ONLY when the allocation is sampled. Use this
 * whenever obtaining the name costs more than reading a pointer out of type
 * metadata — the Swift path resolves and caches a demangled type name, which at
 * cache saturation degrades badly and must never run per allocation.
 *
 * The size is still required up front: Poisson sampling decrements a byte
 * counter by it and the weight is derived from it, so it cannot be deferred.
 *
 * @param ptr Allocation pointer; NULL is a no-op.
 * @param size Allocation size in bytes.
 * @param resolver Called only on the sampled path; may be NULL for no name.
 * @param context Opaque argument forwarded to `resolver`.
 * @param source Interception path recording this allocation.
 */
void dd_memory_observe_allocation_resolved(const void* ptr, uint64_t size,
                                           dd_memory_class_name_resolver_t resolver,
                                           void* context,
                                           dd_memory_source_t source);

/**
 * Records an externally-observed Objective-C object deallocation.
 *
 * If the pointer belongs to a sampled allocation, it is removed from the live
 * sample table and sampled_frees is incremented. Unsampled pointers are a no-op.
 *
 * @param ptr Object pointer before its storage is released; NULL is a no-op.
 */
void dd_memory_observe_deallocation(const void* ptr);

/**
 * Disables sampling and removes hooks.
 *
 * The hook function pointers may remain installed (we cannot reliably restore
 * the original pointers if another tool installed hooks after us). Instead,
 * the global enabled flag is cleared and hooks short-circuit to the original
 * implementations.
 *
 * Safe to call multiple times.
 */
void dd_memory_profiler_stop(void);

/**
 * Returns true if profiling is currently enabled and hooks are installed.
 */
bool dd_memory_profiler_is_running(void);

// MARK: - Snapshot

/**
 * Captures a heap snapshot of currently-live sampled allocations.
 *
 * The returned snapshot is a point-in-time copy. Allocations and frees
 * continuing on other threads will not affect the returned data.
 *
 * @return Snapshot with allocated samples array. Caller releases with
 *         `dd_memory_snapshot_destroy`. Returns a snapshot with
 *         sample_count == 0 if profiling is disabled.
 */
dd_memory_snapshot_t dd_memory_snapshot_capture(void);

/**
 * Captures and RESETS the current window's allocation log, which feeds `alloc_*`.
 *
 * Unlike dd_memory_snapshot_capture (a point-in-time view of the live set that
 * is never reset), this returns every allocation SAMPLED since the last capture
 * or session start — including ones already freed — and then clears the window
 * so the next emission accumulates fresh. Pair one call per emission window with
 * one dd_memory_snapshot_capture, and feed both to dd_memory_snapshots_to_pprof.
 *
 * @return Snapshot of this window's sampled allocations (each carries size,
 *         weight, class_name, source, stack). Caller releases with
 *         dd_memory_snapshot_destroy. sample_count == 0 if the window was empty
 *         or profiling is disabled.
 */
dd_memory_snapshot_t dd_memory_alloc_window_capture(void);

/**
 * Releases memory owned by a snapshot.
 *
 * @param snapshot Snapshot to release. NULL is a no-op.
 */
void dd_memory_snapshot_destroy(dd_memory_snapshot_t* snapshot);

// MARK: - Diagnostics

/**
 * Returns a copy of the current diagnostic counters.
 */
dd_memory_diagnostics_t dd_memory_profiler_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_MEMORY_PROFILER_H_
