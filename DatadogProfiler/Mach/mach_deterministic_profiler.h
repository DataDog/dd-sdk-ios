/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_DETERMINISTIC_PROFILER_H_
#define DD_PROFILER_MACH_DETERMINISTIC_PROFILER_H_

#include "mach_sampling_profiler.h"

#ifdef __APPLE__

namespace dd {
namespace profiler {

/**
 * @brief Deterministic profiler with fixed intervals and exhaustive thread sampling
 * 
 * This implementation provides predictable, repeatable profiling behavior
 * suitable for debugging and consistent performance measurements.
 * 
 * Characteristics:
 * - Fixed sampling intervals (no jitter)
 * - Samples all threads in every cycle
 * - Deterministic and repeatable behavior
 * - Lower overhead for statistical calculations
 */
class mach_deterministic_profiler : public mach_sampling_profiler {
public:
    /**
     * @brief Constructs a deterministic profiler instance
     * 
     * @param config Configuration for the profiler
     * @param callback Function to call with collected stack traces
     * @param user_data User data to pass to the callback
     */
    mach_deterministic_profiler(
        const sampling_config_t* config,
        stack_trace_callback_t callback,
        void* user_data);

protected:
    /**
     * @brief Returns fixed sampling interval
     * 
     * @return Fixed sampling interval from configuration in nanoseconds
     */
    uint64_t get_sampling_interval() const override;

    /**
     * @brief Always returns true to sample all threads
     * 
     * @param thread The thread to consider (ignored)
     * @return Always true for deterministic sampling
     */
    bool should_sample_thread(thread_t thread) override;
};

} // namespace profiler
} // namespace dd

#endif // __APPLE__
#endif // DD_PROFILER_MACH_DETERMINISTIC_PROFILER_H_ 