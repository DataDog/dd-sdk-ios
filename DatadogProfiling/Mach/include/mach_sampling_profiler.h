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
#include <vector>

/**
 * Default sampling configuration with safe default values.
 * For C++ use only. Use sampling_config_get_default() from Swift.
 */
static const sampling_config_t SAMPLING_CONFIG_DEFAULT = {
    SAMPLING_CONFIG_DEFAULT_INTERVAL_NS,  // sampling_interval_nanos
    0,                                       // profile_current_thread_only
    SAMPLING_CONFIG_DEFAULT_BUFFER_SIZE,     // max_buffer_size
    SAMPLING_CONFIG_DEFAULT_STACK_DEPTH,     // max_stack_depth
    SAMPLING_CONFIG_DEFAULT_THREAD_COUNT,    // max_thread_count
    QOS_CLASS_USER_INTERACTIVE,              // qos_class
    NULL                                     // ignore_thread
};

/**
 * Callback type for receiving stack traces.
 * This is called whenever a batch of stack traces is captured.
 *
 * @param traces Vector of captured stack traces. The callback takes ownership.
 * @param blocking If true, the callback must block until the resolver is ready.
 * @param ctx Context pointer passed during profiler creation
 */
typedef void (*stack_trace_callback_t)(std::vector<stack_trace_t>& traces, bool blocking, void* ctx);

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Sets the main thread pthread identifier.
 *
 * This function should be called from the main thread early in the process lifecycle.
 *
 * @param thread The pthread identifier for the main thread
 */
void set_main_thread(pthread_t thread);

/**
 * Destroys the frames of a stack trace, freeing any memory allocated by that struct
 * but not the image struct itself.
 * 
 * @param trace Pointer to stack trace to clean up (can be nullptr)
 */
void stack_trace_destroy(stack_trace_t* trace);

#ifdef __cplusplus
}
#endif

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
     * @brief Flushes the current sample buffer to the callback
     * @param blocking If true, blocks until the callback accepts the data
     */
    void flush_buffer(bool blocking = false);

    /**
     * @brief Atomic flag indicating if profiling is currently running
     */
    std::atomic<bool> running;

    /**
     * @brief Gets the thread handle for the sampling thread
     * @return The pthread_t handle
     */
    pthread_t get_sampling_thread() const { return sampling_thread; }

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
     * @param[out] out_trace The stack trace to fill
     * @return true if a valid trace was captured
     */
    bool capture_stack_trace(thread_t thread, uint64_t interval_nanos, stack_trace_t& out_trace);

private:
    /**
     * @brief Static entry point for the sampling thread
     */
    static void* sampling_thread_entry(void* arg);

    /**
     * @brief Mutex to protect start/stop operations from concurrent access
     */
    std::mutex state_mutex;

    /**
     * @brief Mutex to protect buffer operations
     */
    std::mutex buffer_mutex;
};

} // namespace dd::profiler

#endif // __APPLE__
#endif // DD_PROFILER_MACH_SAMPLING_PROFILER_H_ 
