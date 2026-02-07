/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_PROFILER_TESTING_H_
#define DD_PROFILER_MACH_PROFILER_TESTING_H_

#include "mach_profiler.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Manually starts profiling for testing purposes
 *
 * This function bypasses the automatic constructor-based startup mechanism and allows
 * manual control over profiling for testing scenarios.
 *
 * The profiler uses 101 Hz sampling frequency and 10,000 sample buffer.
 * It will automatically stop when the specified timeout is reached.
 *
 * @param sample_rate Sample rate percentage (0.0-100.0)
 *                    - 0.0 will not start profiling
 *                    - Values 0.0-100.0 use probabilistic sampling
 *                    - Values > 100.0 are treated as 100%
 * @param is_prewarming Whether the app is in prewarming state
 *                      - true: Will not start profiling
 *                      - false: Normal profiling behavior
 * @param timeout_ns Timeout in nanoseconds after which profiling automatically stops
 *                   - Default: 5000000000ULL (5 seconds)
 *                   - Timeout checking occurs during sample processing
 *
 * @note Safe to call multiple times - destroys existing instance before creating new one
 * @note Check `profiler_get_status()` for detailed status after calling
 * @note Designed for unit tests, integration tests, and development builds
 *
 * @warning FOR TESTING USE ONLY - Not intended for production environments
 * @warning May impact application performance if used inappropriately
 *
 * @see `profiler_get_status()`, `profiler_stop()`, `profiler_get_profile()`
 */
void profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns);

#ifdef __cplusplus
}
#endif

#endif // DD_PROFILER_MACH_PROFILER_TESTING_H_
