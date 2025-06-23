/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_SAMPLING_PROFILER_H_
#define DD_PROFILER_MACH_SAMPLING_PROFILER_H_

#include "include/mach_profiler.h"

#ifdef __APPLE__

#include <atomic>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_info.h>
#include <mach/mach_time.h>
#include <vector>
#include <pthread.h>

namespace dd {
namespace profiler {

/**
 * @brief Abstract base class for Mach-based sampling profilers
 * 
 * Provides common functionality for sampling threads and managing
 * stack trace collection, with virtual methods for sampling strategy.
 */
class mach_sampling_profiler {
public:
    /**
     * @brief Constructs a new profiler instance
     * 
     * @param config Configuration for the profiler
     * @param callback Function to call with collected stack traces
     * @param user_data User data to pass to the callback
     */
    mach_sampling_profiler(
        const sampling_config_t* config,
        stack_trace_callback_t callback,
        void* user_data);

    /**
     * @brief Virtual destructor that ensures profiling is stopped
     */
    virtual ~mach_sampling_profiler();

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

    /**
     * @brief Virtual method to get the current sampling interval
     * 
     * @return Current sampling interval in milliseconds
     */
    virtual uint32_t get_sampling_interval() const = 0;

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
     * @brief User data passed to the callback function
     */
    void* user_data;

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
     * 
     * Uses virtual methods get_sampling_interval() and should_sample_thread()
     * to implement different sampling strategies in subclasses.
     */
    void main();

    /**
     * @brief Virtual method to determine if a thread should be sampled
     * 
     * @param thread The thread to consider for sampling
     * @return true if the thread should be sampled, false otherwise
     */
    virtual bool should_sample_thread(thread_t thread) = 0;

    /**
     * @brief Samples a single thread's stack (common implementation)
     * 
     * @param thread The thread to sample
     */
    void sample_thread(thread_t thread);

    /**
     * @brief Flushes the sample buffer (common implementation)
     */
    void flush_buffer();

private:
    /**
     * @brief Static entry point for the sampling thread
     */
    static void* sampling_thread_entry(void* arg);
};

} // namespace profiler
} // namespace dd

#endif // __APPLE__
#endif // DD_PROFILER_MACH_SAMPLING_PROFILER_H_ 