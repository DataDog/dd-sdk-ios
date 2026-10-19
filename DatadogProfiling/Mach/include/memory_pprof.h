/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PPROF_H_
#define DD_MEMORY_PPROF_H_

#include "memory_allocation_window.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#ifdef __cplusplus
namespace dd::profiler { class HeapPprofEncoder; }
extern "C" {
#endif

#define DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES 8388608
#define DD_MEMORY_PPROF_MAX_UNIQUE_LOCATIONS 65536
#define DD_MEMORY_PPROF_MAX_MAPPINGS 1024
#define DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES 1024

#ifdef __cplusplus
typedef dd::profiler::HeapPprofEncoder dd_memory_pprof_encoder_t;
#else
typedef struct dd_memory_pprof_encoder dd_memory_pprof_encoder_t;
#endif

typedef struct {
    const uint8_t *data;
    size_t size;
} dd_memory_pprof_view_t;

typedef struct {
    uint64_t encoded_profiles;
    uint64_t empty_profiles_skipped;
    uint64_t invalid_profiles;
    uint64_t limit_failures;
    uint64_t omitted_class_names;
    uint64_t saturated_values;
    uint64_t unresolved_locations;
    uint64_t encoded_size_high_water;
    uint64_t storage_bytes;
    uint64_t max_payload_bytes;
} dd_memory_pprof_diagnostics_t;

/// Preallocates a reusable mmap output buffer and an encoder object with inline
/// location/mapping/class-name indexes. max_payload_bytes must be in
/// 1...DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES.
/// Borrows the process-wide image cache shared with CPU profiling; cached names
/// survive either profiler's teardown. Returns NULL on invalid capacity, allocation
/// failure, or cache initialization failure. Create outside observers.
dd_memory_pprof_encoder_t *dd_memory_pprof_encoder_create(size_t max_payload_bytes);

/// Finish all encodes and readers before destroying. NULL is a no-op.
void dd_memory_pprof_encoder_destroy(dd_memory_pprof_encoder_t *encoder);

/// Encodes fractional aggregate totals into four pprof values, rounding each
/// total once. Positive overflow (including infinity) saturates at INT64_MAX;
/// negative values and NaN reject the emission. time_nanos is collection time
/// since the Unix epoch; duration_nanos is the window duration. Both must be
/// nonnegative. An empty input skips emission and returns false.
///
/// Encoding is bounded by output, unique-location and mapping capacities.
/// Invalid input or a capacity failure discards the complete emission and
/// returns false. All calls and view readers must be serialized by the owner.
/// Run on the background profiler queue, outside allocation/deallocation
/// observers and Mach thread suspension. Swift names resolve synchronously
/// here and are consumed immediately, with a bounded copy.
/// Class labels use "allocation class". Equal class-name bytes share a string
/// entry when admitted to the bounded per-profile deduplication index; exhausting
/// its probe bound falls back to emitting another string entry.
bool dd_memory_pprof_encoder_encode(
    dd_memory_pprof_encoder_t *encoder,
    const dd_memory_aggregation_view_t *view,
    int64_t time_nanos,
    int64_t duration_nanos);

/// Borrowed encoded bytes, valid until the next encode or destroy. Empty
/// before encoding and after any skipped or failed encode. NULL is empty.
dd_memory_pprof_view_t dd_memory_pprof_encoder_view(
    const dd_memory_pprof_encoder_t *encoder);

/// Cumulative attempt counters and owned storage size: requested encoder object
/// bytes plus the page-rounded output mapping. Excludes allocator overhead,
/// resident-memory measurements, and the shared process-wide image cache. Counters
/// for omitted names, saturated values and unresolved locations also include
/// attempts that subsequently fail. NULL returns zero counters.
dd_memory_pprof_diagnostics_t dd_memory_pprof_encoder_diagnostics(
    const dd_memory_pprof_encoder_t *encoder);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_PPROF_H_
