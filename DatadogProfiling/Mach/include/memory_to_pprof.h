/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_TO_PPROF_H_
#define DD_MEMORY_TO_PPROF_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdint.h>
#include <stddef.h>
#include "memory_profiler.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Convert a heap snapshot into serialized heap-pprof bytes with optional RUM
 * correlation labels.
 *
 * Converts the live allocations in `snapshot` into a pprof protobuf buffer
 * with four Go-aligned sample types (alloc_objects/count, alloc_space/bytes,
 * inuse_objects/count, inuse_space/bytes) and period_type space/bytes with
 * period DD_MEMORY_POISSON_DEFAULT_RATE_BYTES (524288).
 *
 * Samples that share the same resolved stack are aggregated into a single pprof
 * sample. For this first implementation `alloc_*` equals `inuse_*` because a
 * single snapshot only carries the live set — true period deltas are a deferred
 * follow-up.
 *
 * When a non-NULL, non-empty RUM correlation ID is supplied the corresponding
 * string label (`session_id`, `view_id`, `application_id`) is attached to every
 * emitted pprof sample (Go-aligned label names). All samples in the snapshot
 * carry the same values because the snapshot is point-in-time. NULL or empty
 * strings are silently omitted (no label is added for that ID).
 *
 * @param snapshot        Heap snapshot captured with dd_memory_snapshot_capture().
 *                        May be NULL or have sample_count == 0; both return 0.
 * @param session_id      Current RUM session UUID string, or NULL/empty to omit.
 * @param view_id         Current RUM view UUID string, or NULL/empty to omit.
 * @param application_id  Current RUM application UUID string, or NULL/empty to omit.
 * @param out_data        Output parameter for the allocated buffer.  The caller is
 *                        responsible for releasing it with free(). Set to NULL on
 *                        failure.
 * @return Number of bytes written to *out_data, or 0 on failure / empty input.
 */
size_t dd_memory_snapshot_to_pprof(
    const dd_memory_snapshot_t* snapshot,
    const char* session_id,
    const char* view_id,
    const char* application_id,
    uint8_t** out_data);

/**
 * Convert an independent live-set snapshot and per-window allocation snapshot
 * into one serialized heap-pprof buffer.
 *
 * `inuse_snapshot` (from dd_memory_snapshot_capture) feeds `inuse_objects` /
 * `inuse_space`; `alloc_snapshot` (from dd_memory_alloc_window_capture) feeds
 * `alloc_objects` / `alloc_space`. Both are aggregated by (stack, class_name,
 * source); a key present in only one snapshot gets zeros on the other side.
 * Either snapshot may be NULL or empty. Returns 0 (and sets *out_data to NULL)
 * when both are empty.
 *
 * Same label and period semantics as dd_memory_snapshot_to_pprof. Caller releases
 * *out_data with free().
 */
size_t dd_memory_snapshots_to_pprof(
    const dd_memory_snapshot_t* inuse_snapshot,
    const dd_memory_snapshot_t* alloc_snapshot,
    const char* session_id,
    const char* view_id,
    const char* application_id,
    uint8_t** out_data);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_MEMORY_TO_PPROF_H_
