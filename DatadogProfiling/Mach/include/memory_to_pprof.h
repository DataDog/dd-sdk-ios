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
 * Convert a heap snapshot into serialized heap-pprof bytes.
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
 * @param snapshot Heap snapshot captured with dd_memory_snapshot_capture().
 *                 May be NULL or have sample_count == 0; both return 0.
 * @param out_data Output parameter for the allocated buffer.  The caller is
 *                 responsible for releasing it with free(). Set to NULL on
 *                 failure.
 * @return Number of bytes written to *out_data, or 0 on failure / empty input.
 */
size_t dd_memory_snapshot_to_pprof(const dd_memory_snapshot_t* snapshot, uint8_t** out_data);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_MEMORY_TO_PPROF_H_
