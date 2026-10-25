/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PROFILER_TESTING_H_
#define DD_MEMORY_PROFILER_TESTING_H_

#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH && defined(DEBUG)

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DD_MEMORY_TEST_HOOKS_SUCCEED,
    DD_MEMORY_TEST_SWIFT_HOOK_FAILS,
    DD_MEMORY_TEST_OBJC_HOOK_FAILS,
} dd_memory_test_hook_failure_t;

typedef struct {
    uint64_t captures_count;
    uint64_t ready_count;
    uint64_t idle_count;
    dd_memory_capture_status_t last_status;
    int64_t time_nanos;
    int64_t duration_nanos;
    uint64_t sample_count;
    double alloc_objects;
    double alloc_space;
    double inuse_objects;
    double inuse_space;
} dd_memory_profiler_test_capture_diagnostics_t;

/// Consumes only the persisted memory sample rate in the supplied suite and
/// applies the same startup gates as the process-launch constructor.
void dd_memory_profiler_auto_start_for_testing(const char *suite_name, bool prewarming,
                                              bool thread_sanitizer);

/// Stops the existing sampler, clears capture diagnostics, and uses quiet
/// observers for every subsequent normal start until reset. A configured hook
/// failure applies to every start, including restarts after a full stop.
void dd_memory_profiler_configure_for_testing(dd_memory_test_hook_failure_t failure);
/// Stops the sampler, clears diagnostics, and restores normal runtime observers.
void dd_memory_profiler_reset_for_testing(void);

/// Scalar capture results survive stop; no borrowed aggregation data is retained.
dd_memory_profiler_test_capture_diagnostics_t dd_memory_profiler_capture_diagnostics_for_testing(void);
/// Makes the next capture fail before closing its window. Consumed once.
void dd_memory_profiler_fail_next_capture_for_testing(void);

/// Installs the real hook forwarding paths with quiet observers; only the
/// explicit observer entries below submit samples. Failure is injected after
/// installing the named hook, so cleanup exercises the real drain boundary.
bool dd_memory_profiler_start_for_testing(dd_memory_test_hook_failure_t failure);
void dd_memory_profiler_record_for_testing(const dd_memory_live_sample_t *sample);
void dd_memory_profiler_remove_for_testing(const void *address);

/// Real +alloc/-release messages on a large NSObject fixture, making selection
/// overwhelmingly likely without replacing runtime functions or observers.
void *dd_memory_profiler_allocate_objc_for_testing(void);
void dd_memory_profiler_release_objc_for_testing(void *object);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH && defined(DEBUG)
#endif // DD_MEMORY_PROFILER_TESTING_H_
