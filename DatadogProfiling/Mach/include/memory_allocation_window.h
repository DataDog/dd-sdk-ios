/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_ALLOCATION_WINDOW_H_
#define DD_MEMORY_ALLOCATION_WINDOW_H_

#include "memory_live_set.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#ifdef __cplusplus
extern "C" {
#endif

#define DD_MEMORY_ALLOCATION_WINDOW_CAPACITY 4096
static const size_t DD_MEMORY_AGGREGATION_CAPACITY =
    DD_MEMORY_ALLOCATION_WINDOW_CAPACITY + DD_MEMORY_LIVE_SET_CAPACITY;

typedef struct dd_memory_allocation_window dd_memory_allocation_window_t;

/// Aggregation key: allocation stack, class identity and allocation source.
/// Obj-C class names are owned by the closed window. Swift class names resolve
/// through metadata outside the intercepted allocation/deallocation path.
typedef struct {
    const char *class_name;
    const HeapMetadata *swift_metadata;
    dd_swift_class_name_resolver_t swift_name_resolver;
    uint64_t frames[DD_MEMORY_LIVE_SET_MAX_FRAMES];
    uint32_t frame_count;
    dd_memory_live_sample_source_t source;
} dd_memory_aggregation_key_t;

/// Independent allocation and live-set totals for one key. All four totals
/// remain fractional; individual addresses, sizes and weights are not retained.
typedef struct {
    dd_memory_aggregation_key_t key;
    double alloc_objects;
    double alloc_space;
    double inuse_objects;
    double inuse_space;
} dd_memory_aggregate_t;

typedef struct {
    const dd_memory_aggregate_t *samples;
    size_t count;
} dd_memory_aggregation_view_t;

typedef struct {
    uint64_t capacity;
    uint64_t recorded_allocations;
    uint64_t peak_recorded_allocations;
    uint64_t dropped_alloc_records;
    uint64_t omitted_class_names;
    /// Requested recorder, live table and snapshot object bytes; excludes
    /// allocator overhead and does not measure resident memory.
    uint64_t storage_bytes;
    dd_memory_live_set_diagnostics_t live_set;
} dd_memory_allocation_window_diagnostics_t;

typedef struct {
    /// Counts for the closed allocation window; cleared by the next close/start.
    uint64_t recorded_allocations;
    uint64_t peak_recorded_allocations;
    uint64_t dropped_alloc_records;
    uint64_t omitted_class_names;
    /// Captured at the same boundary as the live snapshot.
    dd_memory_live_set_diagnostics_t live_set;
} dd_memory_closed_window_diagnostics_t;

/// Preallocates bounded recorder and aggregation buffers with calloc and live
/// table/snapshot objects with their inline arrays.
/// Returns NULL on failure. No allocation/deallocation operation allocates memory.
/// Capacity values are initial bounds; RUM-18833 owns field sizing/sign-off.
dd_memory_allocation_window_t *dd_memory_allocation_window_create(void);

/// Stop and drain all observers/readers before destroying; stop alone does not
/// drain lock-free deallocation misses. NULL is a no-op.
void dd_memory_allocation_window_destroy(dd_memory_allocation_window_t *window);

/// Starts a new sampler lifetime, clearing both allocation totals and live objects.
/// Returns a nonzero generation token, or zero on failure.
uint64_t dd_memory_allocation_window_start(dd_memory_allocation_window_t *window);

/// Rejects subsequent records and closes. Capture the final window before stopping.
void dd_memory_allocation_window_stop(dd_memory_allocation_window_t *window);

/// Submit each selected allocation exactly once, while the object remains alive.
/// Records the allocation BEFORE live-set admission. Recorder overflow drops only
/// the allocation record; live admission is still attempted. The result describes
/// live admission; allocation loss is exposed by diagnostics. weight is the
/// sampler's object_weight; bytes are accumulated as double(size) * weight.
/// Swift metadata/resolvers follow the same lifetime contract as the live set.
dd_memory_live_insert_result_t dd_memory_allocation_window_record(
    dd_memory_allocation_window_t *window, uint64_t generation,
    const dd_memory_live_sample_t *sample);

/// Does not modify allocation totals. Misses retain the live set's bounded,
/// lock-free probe path.
bool dd_memory_allocation_window_remove(
    dd_memory_allocation_window_t *window, uint64_t generation, const void *address);

/// Closes one allocation window and captures the remaining live objects.
/// On success, alloc_* comes solely from drained allocation records, and inuse_*
/// solely from the live snapshot. Live objects survive subsequent windows.
/// On failure, allocation records are retained and the output view is empty.
/// Record/capture ordering is serialized; aggregation and Swift name resolution
/// must run outside allocation observers and Mach thread suspension.
///
/// Lifecycle, close, view and closed-diagnostics readers must be serialized by
/// the owner on the background profiler queue. record/remove may run concurrently.
/// Returned views survive record/remove/stop, until the next close/start/destroy.
bool dd_memory_allocation_window_close(
    dd_memory_allocation_window_t *window, uint64_t generation);

dd_memory_aggregation_view_t dd_memory_allocation_window_view(
    const dd_memory_allocation_window_t *window);

dd_memory_closed_window_diagnostics_t dd_memory_allocation_window_closed_diagnostics(
    const dd_memory_allocation_window_t *window);

/// Current-window counters, read coherently under the recorder lock. Live-set
/// diagnostic fields may reflect different instants. Counters reset on start;
/// window counters also reset after a successful close.
dd_memory_allocation_window_diagnostics_t dd_memory_allocation_window_diagnostics(
    dd_memory_allocation_window_t *window);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_ALLOCATION_WINDOW_H_
