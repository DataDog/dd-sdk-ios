/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_VM_REGION_WALKER_H_
#define DD_VM_REGION_WALKER_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// VM Region Walker (RUM-16460)
//
// Decomposes phys_footprint into category buckets using mach_vm_region_recurse.
// Answers RFC question: "Why doesn't profiling memory match dashboard RSS?"
// by showing the user that 170 MB phys_footprint = 25 MB managed + 80 MB
// dylibs + 35 MB stacks + 30 MB other.
// =====================================================================

/**
 * Per-category memory breakdown.
 *
 * All sizes in bytes. Resident sizes are physical pages currently in RAM;
 * dirty sizes are pages modified by the process (resident or swapped).
 *
 * The categories are derived from the Mach `user_tag` field per region
 * (see <mach/vm_statistics.h>), grouped into buckets useful for the user.
 */
typedef struct dd_vm_category {
    /** Total virtual size (resident + non-resident). */
    uint64_t virtual_bytes;
    /** Resident size (physical pages currently in RAM). */
    uint64_t resident_bytes;
    /** Dirty bytes (anonymous + modified file-backed pages). */
    uint64_t dirty_bytes;
    /** Number of distinct VM regions in this category. */
    uint32_t region_count;
} dd_vm_category_t;

/**
 * Full VM decomposition snapshot.
 *
 * `phys_footprint` is the total reported by `task_info(TASK_VM_INFO)`,
 * which is the number iOS uses for jetsam decisions. The category breakdown
 * should sum approximately to `phys_footprint` modulo allocator metadata
 * and per-region rounding.
 */
typedef struct dd_vm_snapshot {
    /// Total physical footprint from task_info(TASK_VM_INFO).
    /// This is what the OS uses for jetsam/OOM decisions.
    uint64_t phys_footprint;
    /// Resident set size from task_info(TASK_VM_INFO).
    uint64_t resident_size;
    /// Total virtual address space size.
    uint64_t virtual_size;
    /// Walk wall-clock duration in nanoseconds.
    uint64_t walk_duration_ns;
    /// Total VM regions walked.
    uint32_t total_regions;
    /// Allocator-managed heap (VM_MEMORY_MALLOC and friends).
    /// This is the bucket the existing profiler reports.
    dd_vm_category_t managed_heap;
    /// Mapped dylibs and main executable (VM_MEMORY_DYLIB, VM_MEMORY_SHARED_PMAP).
    dd_vm_category_t dylibs;
    /// Thread stacks (VM_MEMORY_STACK).
    dd_vm_category_t stacks;
    /// Memory-mapped files and shared memory (VM_MEMORY_FILE, MAPPED_FILE).
    dd_vm_category_t mapped_files;
    /// JIT and dynamically generated code regions.
    dd_vm_category_t jit_code;
    /// Catch-all for unrecognized user_tag values.
    dd_vm_category_t other;
} dd_vm_snapshot_t;

/**
 * Walks the current process's VM regions and produces a categorized snapshot.
 *
 * Uses mach_vm_region_recurse repeatedly to enumerate every VM submap and
 * region. Aggregates region sizes into categories by `user_tag`.
 *
 * Safe to call concurrently with allocations on other threads; the snapshot
 * is not guaranteed to be transactionally consistent but the totals are
 * close to what tools like `vmmap` would report at the same moment.
 *
 * @return Filled snapshot. On error, returns a zeroed snapshot.
 */
dd_vm_snapshot_t dd_vm_walk_regions(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_VM_REGION_WALKER_H_
