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
// Memory Profiler POC (RUM-16460)
//
// Validation spike for the iOS Memory Profiling RFC. Not for production
// use — this is a tool to answer 4 existential questions before the RFC
// is written. Findings documented in Simao's Brain wiki under
// wiki/synthesis/ios-memory-profiling-poc-findings.md.
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

// MARK: - Status and diagnostics

/**
 * Status returned by hook installation.
 */
typedef enum {
    /// Hooks were not installed because the profiler was already running.
    DD_MEMORY_STATUS_ALREADY_INSTALLED = 0,
    /// Hooks installed by replacing function pointers in the default zone
    /// without needing mprotect (zone struct page was already writable).
    DD_MEMORY_STATUS_INSTALLED_DIRECT = 1,
    /// Hooks installed via mprotect to make the zone struct page writable.
    /// Indicates the default zone resides on a read-only page on this OS.
    DD_MEMORY_STATUS_INSTALLED_MPROTECT = 2,
    /// Hooks could not be installed: the zone struct could not be made
    /// writable. This is the App Store risk path the POC is meant to detect.
    DD_MEMORY_STATUS_FAILED_READ_ONLY_ZONE = 3,
    /// Hooks could not be installed: malloc_default_zone returned NULL.
    DD_MEMORY_STATUS_FAILED_NO_ZONE = 4,
    /// Hooks could not be installed: another tool has already replaced the
    /// zone function pointers (probable collision with another SDK or sanitizer).
    DD_MEMORY_STATUS_FAILED_COLLISION = 5
} dd_memory_install_status_t;

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
 * Installs malloc_zone hooks and starts Poisson sampling on the default zone.
 *
 * @param poisson_rate_bytes Average bytes between sampled allocations.
 *                           Use DD_MEMORY_POISSON_DEFAULT_RATE_BYTES for default (512 KB).
 * @return Status indicating which installation path was taken or why it failed.
 */
dd_memory_install_status_t dd_memory_profiler_start(uint64_t poisson_rate_bytes);

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
