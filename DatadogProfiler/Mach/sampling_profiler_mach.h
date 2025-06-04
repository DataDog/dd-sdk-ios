#ifndef DD_PROFILER_SAMPLING_PROFILER_MACH_H_
#define DD_PROFILER_SAMPLING_PROFILER_MACH_H_

#include "sampling_profiler.h"

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
 * @brief Internal implementation of the CPU profiler for macOS/iOS
 * 
 * This class implements a sampling profiler that collects stack traces
 * from threads at regular intervals. It supports both system-wide profiling
 * and single-thread profiling modes.
 */
struct profiler {
    /**
     * @brief Configuration for the profiler
     * 
     * Contains settings like sampling interval, max stack depth,
     * and whether to profile only the current thread.
     */
    sampling_config_t config;

    /**
     * @brief Callback function to receive collected stack traces
     * 
     * This function is called whenever the sample buffer is full
     * or when profiling is stopped.
     */
    stack_trace_callback_t callback;

    /**
     * @brief User data passed to the callback function
     */
    void* user_data;

    /**
     * @brief Atomic flag indicating if profiling is currently running
     */
    std::atomic<bool> running;

    /**
     * @brief Thread handle for the sampling thread
     * 
     * This thread is responsible for collecting stack traces
     * at regular intervals.
     */
    pthread_t sampling_thread;

    /**
     * @brief Thread to profile when in single-thread mode
     * 
     * When profile_current_thread_only is true, only this thread
     * will be profiled.
     */
    pthread_t target_thread;  

    /**
     * @brief Buffer for collecting stack traces
     * 
     * Stack traces are collected in this buffer until it reaches
     * the maximum size specified in the configuration.
     */
    std::vector<stack_trace_t> sample_buffer;

    /**
     * @brief Constructs a new profiler instance
     * 
     * @param config Configuration for the profiler
     * @param callback Function to call with collected stack traces
     * @param user_data User data to pass to the callback
     */
    profiler(
        const sampling_config_t* config,
        stack_trace_callback_t callback,
        void* user_data);

    /**
     * @brief Destructor that ensures profiling is stopped
     */
    ~profiler();

    /**
     * @brief Samples a single thread's stack
     * 
     * @param thread The thread to sample
     */
    void sample_thread(thread_t thread);

    /**
     * @brief Gets a stack trace from a thread
     * 
     * @param thread The thread to get the stack trace from
     * @return A stack trace containing frame information
     */
    stack_trace_t get_thread_trace(thread_t thread);

    /**
     * @brief Main sampling loop that collects stack traces
     * 
     * This function runs in a separate thread and periodically
     * samples all threads (or just the target thread in single-thread mode).
     */
    void sampling_loop();

    /**
     * @brief Captures a stack trace from a thread
     * 
     * @param thread The thread to capture the stack trace from
     */
    void capture_stack_trace(thread_t thread);

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
     * @brief Flushes the sample buffer
     * 
     * Calls the callback with all collected stack traces
     * and clears the buffer.
     */
    void flush_buffer();
};

} // namespace profiler
} // namespace dd

#endif // __APPLE__
#endif // DD_PROFILER_SAMPLING_PROFILER_MACH_H_ 
