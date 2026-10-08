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

typedef enum {
    DD_MEMORY_LIVE_SAMPLE_SOURCE_UNKNOWN = 0,
    DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC = 1,
    DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT = 2
} dd_memory_live_sample_source_t;

/// An Obj-C sample copies its NUL-terminated runtime class name on insertion
/// when it fits in DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES. Longer names are
/// omitted. A snapshot copies stored names into caller-owned storage. Swift
/// name bytes may be temporary: store metadata and the resolver instead,
/// then resolve a snapshot sample outside the allocation hot path.
typedef struct {
    const void *address;
    uint64_t size;
    double weight;
    /// Obj-C name only; pass NULL for Swift samples. Snapshot copies point
    /// into the caller's class-name storage.
    const char *class_name;
    /// Swift samples carry both fields instead of retaining resolver output.
    const HeapMetadata *swift_metadata;
    dd_swift_class_name_resolver_t swift_name_resolver;
    uint64_t frames[DD_MEMORY_LIVE_SET_MAX_FRAMES];
    uint32_t frame_count;
    dd_memory_live_sample_source_t source;
} dd_memory_live_sample_t;

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
    /// Page-rounded mmap storage owned by the table.
    uint64_t table_bytes;
    /// Largest combined caller-declared sample and class-name buffers used by
    /// a successful capture.
    uint64_t snapshot_bytes_high_water;
    bool reached_admission_limit;
    bool is_active;
} dd_memory_live_set_diagnostics_t;

/// Allocates the table once with mmap. Returns NULL if allocation fails.
/// No operation on an existing table allocates memory.
dd_memory_live_set_t *dd_memory_live_set_create(void);

/// The caller must first stop and drain all allocation/deallocation hooks and
/// all snapshot/diagnostics readers. stop() alone does not drain miss-only
/// removals, which do not take a slot lock.
void dd_memory_live_set_destroy(dd_memory_live_set_t *table);

/// Clears the table and starts a new generation. A zero result means failure.
/// Call only when starting a new sampler lifetime; consecutive RUM sessions
/// may keep the same live set while memory profiling remains active.
uint64_t dd_memory_live_set_start(dd_memory_live_set_t *table);

/// Rejects new work and waits for inserts and snapshots holding the insertion
/// lock. A removal that only probes for a missing address may finish afterward;
/// stop the hooks and drain their callbacks before destroying the table.
void dd_memory_live_set_stop(dd_memory_live_set_t *table);

/// The allocation accumulator must record alloc_* before calling this function:
/// drop-new here affects only inuse_*.
dd_memory_live_insert_result_t dd_memory_live_set_insert(
    dd_memory_live_set_t *table, uint64_t generation,
    const dd_memory_live_sample_t *sample);

/// A miss performs at most DD_MEMORY_LIVE_SET_MAX_PROBE slot reads.
bool dd_memory_live_set_remove(dd_memory_live_set_t *table,
                               uint64_t generation, const void *address);

/// Copies one coherent point-in-time view into caller-owned storage. Pass an
/// array of DD_MEMORY_LIVE_SET_CAPACITY records to guarantee enough samples.
/// Obj-C names are copied into class_names, including their NUL terminators;
/// class_name_bytes_required reports the needed size even if that buffer is
/// short. It may be NULL when this size is not needed. Swift names continue to
/// resolve through stored metadata. Returns false, with *count == 0, for a
/// stale generation or short buffer. Snapshot storage must be allocated
/// outside the intercepted hot path. Do not call while suspending threads for
/// Mach sampling: capture acquires every slot lock.
bool dd_memory_live_set_snapshot(dd_memory_live_set_t *table,
                                 uint64_t generation,
                                 dd_memory_live_sample_t *output,
                                 size_t output_capacity, char *class_names,
                                 size_t class_names_capacity, size_t *count,
                                 size_t *class_name_bytes_required);

dd_memory_live_set_diagnostics_t
dd_memory_live_set_diagnostics(const dd_memory_live_set_t *table);

/// Hash bucket for deterministic collision tests and admission sizing.
size_t dd_memory_live_set_bucket(const void *address);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_MEMORY_LIVE_SET_H_
