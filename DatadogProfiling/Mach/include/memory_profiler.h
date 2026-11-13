/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PROFILER_H_
#define DD_MEMORY_PROFILER_H_

#include "memory_allocation_window.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#ifdef __cplusplus
extern "C" {
#endif

#define DD_PROFILING_MEMORY_SAMPLE_RATE_KEY "profiling_memory_sample_rate"

typedef enum {
    DD_MEMORY_CAPTURE_FAILED,
    DD_MEMORY_CAPTURE_IDLE,
    DD_MEMORY_CAPTURE_READY,
} dd_memory_capture_status_t;

typedef struct {
    /// Borrowed until the next capture, start or stop. A READY empty view records
    /// the final tracked object being freed; encoding/upload belongs to the caller.
    dd_memory_aggregation_view_t aggregation;
    /// Window origin since the Unix epoch and sleep-inclusive window duration.
    int64_t time_nanos;
    int64_t duration_nanos;
} dd_memory_capture_t;

/// Starts the process-wide memory sampler, or adopts it without clearing data.
/// Failure of either runtime hook disables both and releases the recorder.
bool dd_memory_profiler_start(void);
bool dd_memory_profiler_is_running(void);
bool dd_memory_profiler_is_paused(void);
/// Current window origin, or zero while stopped.
int64_t dd_memory_profiler_window_start_time_nanos(void);

/// Rejects new sampled allocations and drains admitted allocation observers.
/// Frees remain observed and the live set survives. Capture after pausing uses
/// the frozen end boundary. Resume starts a new active window at the current time.
void dd_memory_profiler_pause(void);
void dd_memory_profiler_resume(void);

/// Disables and drains both hooks before destroying their recorder.
/// Capture any final window first. Repeated stops are harmless.
void dd_memory_profiler_stop(void);

/// Closes the allocation window and captures the surviving live objects.
/// IDLE means no sampled allocation attempt and unchanged live occupancy since
/// the preceding capture; READY may contain no samples after the last free.
/// Start, pause, resume, capture, view consumption and stop must be serialized
/// by the background profiler owner, outside native observation callbacks.
dd_memory_capture_status_t dd_memory_profiler_capture(dd_memory_capture_t *capture);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_PROFILER_H_
