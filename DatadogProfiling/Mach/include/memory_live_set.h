/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_LIVE_SET_H_
#define DD_MEMORY_LIVE_SET_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "swift_class_name.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DD_MEMORY_LIVE_SET_CAPACITY 4096
#define DD_MEMORY_LIVE_SET_MAX_PROBE 32
#define DD_MEMORY_LIVE_SET_MAX_FRAMES 64
#define DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES 128

typedef struct dd_memory_live_set dd_memory_live_set_t;
typedef struct dd_memory_live_snapshot dd_memory_live_snapshot_t;

typedef enum {
    DD_MEMORY_LIVE_SAMPLE_SOURCE_UNKNOWN = 0,
    DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC = 1,
    DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT = 2
} dd_memory_live_sample_source_t;

/// An Obj-C sample copies its runtime class name, including the trailing '\0',
/// on insertion when it fits in DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES.
/// Longer names are omitted. A snapshot owns copies of stored names. Swift
/// name bytes may be temporary: store metadata and the resolver instead,
/// then resolve a snapshot sample outside the allocation hot path.
typedef struct {
    const void *address;
    uint64_t size;
    double weight;
    /// Obj-C name only; pass NULL for Swift samples. Captured names point into
    /// snapshot storage.
    const char *class_name;
    /// Swift samples carry both fields instead of retaining resolver output.
    const HeapMetadata *swift_metadata;
    dd_swift_class_name_resolver_t swift_name_resolver;
    uint64_t frames[DD_MEMORY_LIVE_SET_MAX_FRAMES];
    uint32_t frame_count;
    dd_memory_live_sample_source_t source;
} dd_memory_live_sample_t;

/// Borrowed records and Obj-C name bytes owned by a snapshot. Valid until that
/// snapshot is captured again (including a failed capture) or destroyed.
typedef struct {
    const dd_memory_live_sample_t *samples;
    size_t count;
} dd_memory_live_snapshot_view_t;

/// Allocates fixed-capacity sample and name storage once. Returns
/// NULL on allocation failure. Create outside allocation/deallocation observers.
dd_memory_live_snapshot_t *dd_memory_live_snapshot_create(void);

/// Releases snapshot storage. The caller must first finish captures and readers
/// using this snapshot or its views. NULL is a no-op.
void dd_memory_live_snapshot_destroy(dd_memory_live_snapshot_t *snapshot);

/// Returns the latest capture without copying. Before capture, after failure,
/// or for NULL, the view is empty. A snapshot's captures and readers must be
/// serialized by its owner; separate snapshots can be used independently.
dd_memory_live_snapshot_view_t dd_memory_live_snapshot_view(
    const dd_memory_live_snapshot_t *snapshot);

typedef struct {
    const char *data;
    uint64_t length;
} dd_memory_live_class_name_t;

/// The returned bytes are borrowed. Consume or copy them immediately; do not
/// retain the view. Call outside the intercepted allocation/deallocation path.
dd_memory_live_class_name_t dd_memory_live_sample_class_name(
    const dd_memory_live_sample_t *sample);

typedef enum {
    DD_MEMORY_LIVE_SET_INSERTED,
    DD_MEMORY_LIVE_SET_DROPPED,
    DD_MEMORY_LIVE_SET_DUPLICATE,
    DD_MEMORY_LIVE_SET_STALE_GENERATION,
    DD_MEMORY_LIVE_SET_INVALID_SAMPLE
} dd_memory_live_insert_result_t;

typedef struct {
    uint64_t generation;
    uint64_t generation_transitions;
    uint64_t occupancy;
    uint64_t peak_occupancy;
    uint64_t tombstones;
    uint64_t peak_tombstones;
    uint64_t dropped_samples;
    uint64_t duplicate_samples;
    uint64_t omitted_class_names;
    uint64_t stale_generation_rejections;
    uint64_t snapshot_failures;
    /// Probe statistics count sampled insertion attempts. Unsampled free
    /// misses do not update telemetry on the intercepted hot path.
    uint64_t probe_count;
    uint64_t total_probe_length;
    uint64_t max_probe_length;
    /// Requested allocation size in bytes, including inline table storage.
    /// Excludes allocator overhead.
    uint64_t table_bytes;
    /// Requested snapshot allocation size used by a successful capture.
    /// Excludes allocator overhead.
    uint64_t snapshot_bytes_high_water;
    /// At least one insertion exhausted its bounded probe window in this
    /// generation. This can occur while other slots remain empty; use
    /// dropped_samples and occupancy to assess the extent of admission loss.
    bool reached_admission_limit;
    bool is_active;
} dd_memory_live_set_diagnostics_t;

/// Diagnostics captured under the table lock with the snapshot. Empty after
/// creation or a failed capture. Readers follow the snapshot's serialization contract.
dd_memory_live_set_diagnostics_t dd_memory_live_snapshot_diagnostics(
    const dd_memory_live_snapshot_t *snapshot);

/// Requested snapshot object bytes, including before its first capture.
/// Excludes allocator overhead and does not measure resident memory.
uint64_t dd_memory_live_snapshot_storage_bytes(const dd_memory_live_snapshot_t *snapshot);

/// Allocates the table and its inline slots once. Returns NULL if allocation fails.
/// Operations on an existing table and snapshot do not allocate memory.
dd_memory_live_set_t *dd_memory_live_set_create(void);

/// The caller must first stop and drain all allocation/deallocation hooks and
/// all snapshot/diagnostics readers. stop() alone does not drain miss-only
/// removals, which do not take the state lock.
void dd_memory_live_set_destroy(dd_memory_live_set_t *table);

/// Clears the table and starts a new generation. A zero result means failure.
/// Call only when starting a new sampler lifetime; consecutive RUM sessions
/// may keep the same live set while memory profiling remains active.
uint64_t dd_memory_live_set_start(dd_memory_live_set_t *table);

/// Rejects new work and waits for mutations and snapshots holding the state
/// lock. A removal that only probes for a missing address may finish afterward;
/// stop the hooks and drain their callbacks before destroying the table.
/// Capture any final snapshot before stop(); snapshots reject stopped
/// generations. Samples and diagnostic counters are retained until start()
/// clears the table and resets the counters for the new generation.
void dd_memory_live_set_stop(dd_memory_live_set_t *table);

/// Submit each sampled allocation at most once and report its deallocation
/// through remove(). A duplicate preserves the admitted sample. A missed
/// deallocation can retain stale data and reject address reuse as DUPLICATE
/// until remove() observes that address or start() clears the table.
/// The allocation accumulator must record alloc_* before calling this function:
/// drop-new here affects only inuse_*.
/// Admission failure retains existing samples and drops the new one. Sustained
/// saturation favors earlier surviving allocations and censors inuse_*;
/// associate each capture with admission/drop diagnostics from its generation.
dd_memory_live_insert_result_t dd_memory_live_set_insert(
    dd_memory_live_set_t *table, uint64_t generation,
    const dd_memory_live_sample_t *sample);

/// Report each observed deallocation before storage can be reused. Repeated
/// removals before address reuse are harmless. This ends the observed
/// object lifetime; teardown observation can precede actual storage release.
/// A miss performs at most DD_MEMORY_LIVE_SET_MAX_PROBE contiguous address-index
/// reads, without touching sample storage or acquiring the state lock.
bool dd_memory_live_set_remove(dd_memory_live_set_t *table,
                               uint64_t generation, const void *address);

/// Copies one coherent point-in-time view into reusable snapshot storage,
/// including owned Obj-C name bytes. Swift names resolve through stored
/// metadata. Snapshot storage is independent of the table and survives table
/// stop, restart or destruction. A capture replaces the previous contents;
/// failure leaves an empty view. Create storage outside the intercepted hot path.
/// Capture holds the state lock across the full scan and copy, blocking sampled
/// inserts and sampled-object removals on all threads. Integration must capture
/// on a background serial profiler queue at emission boundaries: event/lifecycle
/// flushes and enabled periodic captures in 60-second windows.
/// Do not call from allocation/deallocation observers or while suspending
/// threads for Mach sampling.
bool dd_memory_live_set_snapshot(dd_memory_live_set_t *table,
                                 uint64_t generation,
                                 dd_memory_live_snapshot_t *snapshot);

/// Reads each field atomically without the state lock; fields may reflect
/// different instants. When associating diagnostics with a snapshot, serialize
/// lifecycle changes with both reads on the profiler queue.
dd_memory_live_set_diagnostics_t
dd_memory_live_set_diagnostics(const dd_memory_live_set_t *table);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_MEMORY_LIVE_SET_H_
