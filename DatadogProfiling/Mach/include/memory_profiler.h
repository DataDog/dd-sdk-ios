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

#define DD_MEMORY_POISSON_DEFAULT_RATE_BYTES (512ULL * 1024ULL)

/// Starts process-wide allocation recording using the reviewed fixed-interval
/// Poisson sampler, allocation recorder, and live set. Repeated starts preserve
/// the current generation and its samples. If either interception path fails,
/// both paths are disabled and no recording remains active.
/// Lifecycle and capture calls belong on the background serial profiler queue;
/// the pre-main startup path may start recording before that queue is created.
/// Never call start/stop from allocation or deallocation observers.
bool dd_memory_profiler_start(void);

/// Disables and drains both interception paths before stopping the recorder.
/// Installed trampolines remain in place and forward without observation.
void dd_memory_profiler_stop(void);

bool dd_memory_profiler_is_running(void);

/// Captures aggregated heap values on the profiler queue. A draining capture
/// closes the allocation window; a non-draining capture reports only inuse_*
/// and leaves alloc_* for the next periodic close. The borrowed view survives
/// concurrent recording, until the next capture/start. A successful empty
/// capture returns true; failure returns false with an empty view and retains
/// allocation records. Stop also invalidates the borrowed view.
/// Do not capture while suspending threads
/// for Mach sampling or from an allocation/deallocation observer.
bool dd_memory_profiler_capture(bool drain_allocations,
                                dd_memory_aggregation_view_t *out_view);

/// Current bounded-store diagnostics, including independent allocation and
/// live-set drops. Does not add per-allocation telemetry to the hook fast path.
dd_memory_allocation_window_diagnostics_t dd_memory_profiler_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_PROFILER_H_
