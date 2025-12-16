/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_SAMPLING_PROFILER_H_
#define DD_PROFILER_MACH_SAMPLING_PROFILER_H_

#include "mach_profiler.h"

#ifdef __APPLE__

#include <atomic>
#include <mutex>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_info.h>
#include <vector>
#include <pthread.h>

namespace dd::profiler {

/**
 * @brief Mach-based sampling profiler
 * 
 * Provides fixed-interval sampling for consistent profiling behavior.
 * Can be extended for statistical variations.
 */
class mach_sampling_profiler {
public:
    /**
     * @brief Constructs a new profiler instance
     * 
     * @param config Configuration for the profiler
     * @param callback Function to call with collected stack traces
     * @param ctx Context to pass to the callback
     */
    mach_sampling_profiler(
        const sampling_config_t* config,
        stack_trace_callback_t callback,
        void* ctx);

    /**
     * @brief Destructor that ensures profiling is stopped
     */
    ~mach_sampling_profiler();

    /**
     * @brief Starts the sampling process
     * 
     * @return true if sampling was started successfully
     */
    bool start_sampling();

    /**
     * @brief Stops the sampling process
     */
    void stop_sampling();

    /**
     * @brief Atomic flag indicating if profiling is currently running
     */
    std::atomic<bool> running;

protected:
    /**
     * @brief Configuration for the profiler
     */
    sampling_config_t config;

    /**
     * @brief Callback function to receive collected stack traces
     */
    stack_trace_callback_t callback;

    /**
     * @brief Context passed to the callback function
     */
    void* ctx;

    /**
     * @brief Thread handle for the sampling thread
     */
    pthread_t sampling_thread;

    /**
     * @brief Thread to profile when in single-thread mode
     */
    pthread_t target_thread;  

    /**
     * @brief Buffer for collecting stack traces
     */
    std::vector<stack_trace_t> sample_buffer;

    /**
     * @brief Main sampling loop that collects stack traces from threads
     */
    void main();

    /**
     * @brief Samples a single thread's stack (common implementation)
     * 
     * @param thread The thread to sample
     * @param interval_nanos The actual sampling interval in nanoseconds for this sample
     */
    void sample_thread(thread_t thread, uint64_t interval_nanos);

    /**
     * @brief Flushes the sample buffer (common implementation)
     */
    void flush_buffer();

private:
    /**
     * @brief Static entry point for the sampling thread
     */
    static void* sampling_thread_entry(void* arg);

    /**
     * @brief Mutex to protect start/stop operations from concurrent access
     */
    std::mutex state_mutex;
};

} // namespace dd::profiler

#endif // __APPLE__
#endif // DD_PROFILER_MACH_SAMPLING_PROFILER_H_ 
