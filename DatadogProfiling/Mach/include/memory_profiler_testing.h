/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PROFILER_TESTING_H_
#define DD_MEMORY_PROFILER_TESTING_H_

#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#ifdef __cplusplus
extern "C" {
#endif

/// Stops and drains interception, clears bounded stores and debug overrides.
void dd_memory_test_reset(void);

/// Bypasses Poisson selection for the next allocation on the calling thread.
/// The deterministic test sample has weight one.
void dd_memory_test_force_next_sample(void);

void dd_memory_test_force_start_failure(bool enabled);
/// Rejects captures without consuming allocation records.
void dd_memory_test_force_capture_failure(bool enabled);
uint64_t dd_memory_test_sampled_count(void);
uint64_t dd_memory_test_live_count(void);
uint64_t dd_memory_test_session_generation(void);

/// Bypasses sampling and stack capture, retaining production recording,
/// generation checks, and live-set admission. The address must remain alive.
bool dd_memory_test_record_sample(const dd_memory_live_sample_t *sample,
                                  uint64_t session_generation);

/// Inserts an unknown-source sample of weight one for an address.
bool dd_memory_test_insert_sample(const void *address, uint64_t size,
                                  uint64_t session_generation);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_PROFILER_TESTING_H_
