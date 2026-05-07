/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_SAMPLING_PROFILER_H_
#define DD_PROFILER_MACH_SAMPLING_PROFILER_H_

#include "dd_profiler.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <atomic>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_info.h>
#include <memory>
#include <mutex>
#include <pthread.h>
#include <unordered_map>
#include <vector>

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

#ifdef __cplusplus
}
#endif

namespace dd::profiler {

class aggregation_worker;

/**
 * @brief Mach-based sampling profiler
 * 
 * A sampling engine. Collects raw stack frames at a configured interval and
 * delivers them to the callback. Binary image resolution is the responsibility
 * of the callback consumer.
 */
class mach_sampling_profiler {
public:
    using flush_action_t = void (*)(void* ctx);

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
        void* ctx,
        uint64_t hard_limit_bytes);

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
     * @brief Stops the sampling process.
     *
     * If called from a thread owned by this profiler, this requests an
     * asynchronous stop and returns immediately. Full join and reset are
     * performed only when called from another thread.
     */
    void stop_sampling();

    /**
     * @brief Requests a flush of buffered samples and blocks until complete.
     *
     * If provided, `action` runs after all work before this request has
     * completed and before later buffered work is processed.
     */
    void request_flush(flush_action_t action = nullptr, void* action_ctx = nullptr);

    /**
     * @brief Requests that sampling stop at the next safe point.
     *
     * This does not join threads or reset internal state.
     */
    void request_stop();

    /**
     * @brief Returns and resets diagnostics accumulated since the last consume.
     */
    void consume_diagnostics(dd_profiler_diagnostics_t* out);

    /**
     * @brief Atomic flag indicating whether the sampling loop should keep running.
     */
    std::atomic<bool> should_sample;

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
    pthread_t sampling_thread{};
    /// Cached Mach thread id for hot-path internal-thread filtering.
    std::atomic<thread_t> sampling_thread_mach{MACH_PORT_NULL};

    /**
     * @brief Thread to profile when in single-thread mode
     */
    pthread_t target_thread{};  

    /**
     * @brief Buffer for collecting stack traces
     */
    std::vector<stack_trace_t> sample_buffer;

    /**
     * @brief Serialized aggregation worker used to drain sampled traces off-thread.
     */
    std::unique_ptr<aggregation_worker> worker;

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
    void sample_thread(thread_t thread, uint64_t interval_nanos, uint64_t cpu_time_nanos);

    /**
     * @brief Returns true when the thread is owned by the profiler itself.
     */
    bool is_profiler_internal_thread(thread_t thread) const;

    /**
     * @brief Returns CPU time consumed since the previous observation for this thread.
     */
    uint64_t thread_cpu_time_delta_nanos(thread_t thread);

    /**
     * @brief Removes CPU-time state for threads no longer present in the task.
     */
    void prune_thread_cpu_time_state(const thread_t* threads, mach_msg_type_number_t count);

private:
    /**
     * @brief Static entry point for the sampling thread
     */
    static void* sampling_thread_entry(void* arg);

    /**
     * @brief Mutex to protect start/stop operations from concurrent access
     */
    std::mutex state_mutex;
    /// Indicates whether `sampling_thread` currently refers to a live session thread.
    std::atomic<bool> has_sampling_thread{false};
    std::unordered_map<thread_t, uint64_t> previous_thread_cpu_time_nanos;
};

} // namespace dd::profiler

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_PROFILER_MACH_SAMPLING_PROFILER_H_ 
