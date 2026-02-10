/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_MACH_PROFILER_H_
#define DD_PROFILER_MACH_PROFILER_H_

#include <stdint.h>
#include <sys/types.h>
#include <stdbool.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_info.h>
#include "symbolication.h"

/**
 * @file mach_profiler.h
 * @brief Mach-based profiler for application performance analysis
 * 
 * This profiler provides high-frequency sampling of stack traces across all threads.
 * It can start automatically during the earliest phase of application startup
 * (via constructor attribute) or be controlled manually.
 * 
 * # Startup
 * 
 * The profiler can automatically check if profiling was enabled in a previous session
 * and start capturing data immediately.
 * 
 * # Profiling Characteristics
 * 
 * - **Sampling Rate**: 101 Hz (~9.9ms intervals) - optimized for performance
 * - **Buffer Size**: 100,000 samples
 * - **Stack Depth**: 128 frames maximum per trace
 * - **Thread Coverage**: All threads in the process
 *
 * # Performance Considerations
 * 
 * - Profiling starts right before main()
 * - Uses 101 Hz sampling frequency - provides good resolution without impacting launch performance
 * - Automatically stops when profiler_stop() is called
 * - No overhead when the feature is disabled
 * - Designed to have minimal impact on application launch time and user experience
 * 
 * # Thread Safety
 * 
 * All functions are thread-safe and can be called from any thread.
 */

#ifdef __APPLE__

// UserDefaults constants centralized for Profiling
#define DD_PROFILING_USER_DEFAULTS_SUITE_NAME "com.datadoghq.ios-sdk.profiling"
#define DD_PROFILING_IS_ENABLED_KEY "is_profiling_enabled"
#define DD_PROFILING_SAMPLE_RATE_KEY "profiling_sample_rate"

/**
 * Default sampling configuration values.
 */
/// Sampling frequency. Default to ~101 Hz (1/101 seconds ≈ 9.9ms)
#define SAMPLING_CONFIG_DEFAULT_FREQUENCY_HZ    101     // 101 Hz
/// Sampling interval. Default to 9.9ms
#define SAMPLING_CONFIG_DEFAULT_INTERVAL_NS     9900990 // ~101 Hz (1/101 seconds ≈ 9.9ms)
/// Max buffer size of samples. It is a larger buffer to delay stack aggregation.
#define SAMPLING_CONFIG_DEFAULT_BUFFER_SIZE     100000
/// Max frames per trace.
#define SAMPLING_CONFIG_DEFAULT_STACK_DEPTH     128
/// Max threads count.
#define SAMPLING_CONFIG_DEFAULT_THREAD_COUNT    100

#ifdef __cplusplus
namespace dd::profiler {

class profile;

} // namespace dd::profiler

extern "C" {
#endif

/**
 * Represents a single stack frame in a profile.
 */
typedef struct stack_frame {
    /** The instruction pointer */
    uint64_t instruction_ptr;
    /** The binary image information */
    binary_image_t image;
} stack_frame_t;

/**
 * Represents a complete stack trace.
 */
typedef struct stack_trace {
    /** Thread ID */
    mach_port_t tid;
    /** Thread name  */
    const char* thread_name;
    /** Timestamp in nanoseconds since system boot */
    uint64_t timestamp;
    /** Actual sampling interval in nanoseconds for this sample */
    uint64_t sampling_interval_nanos;
    /** The stack frames array */
    stack_frame_t* frames;
    /** Number of frames in the trace */
    uint32_t frame_count;
} stack_trace_t;

/**
 * Configuration for sampling profilers.
 */
typedef struct sampling_config {
    /** Sampling interval in nanoseconds */
    uint64_t sampling_interval_nanos;  // default: 1000000 (1ms)
    /** Whether to profile only the current thread */
    uint8_t profile_current_thread_only;
    /** Maximum number of samples to buffer before calling the callback */
    size_t max_buffer_size;
    /** Maximum number of stack frames to capture per trace */
    uint32_t max_stack_depth;  // default: 128
    /** Maximum number of threads to sample per cycle (0 = no limit) */
    uint32_t max_thread_count;  // default: 100
    /** QoS class for the sampling thread */
    qos_class_t qos_class;
    /** Thread to ignore during sampling (e.g. the resolver thread) */
    pthread_t ignore_thread;
} sampling_config_t;


/**
 * Checks if profiling is enabled in UserDefaults.
 *
 * Reads the profiling enabled state from UserDefaults suite to determine
 * if the profiling feature was previously enabled via Profiling.enable().
 *
 * @return true if profiling is enabled, false otherwise
 *
 * @note Reads from suite "com.datadoghq.ios-sdk" with key "is_profiling_enabled"
 * @note Returns false if the key doesn't exist or on read errors
 */
bool is_profiling_enabled();

/**
 * Deletes the profiling defaults from UserDefaults.
 *
 * Removes the profiling enabled state, allowing the session to start with a clean state.
 */
void delete_profiling_defaults();

/**
 * Status codes for constructor profiler operations
 */
typedef enum {
    PROFILER_STATUS_NOT_CREATED = 0,       ///< Profiler was not created
    PROFILER_STATUS_NOT_STARTED = 1,       ///< Profiler was never started
    PROFILER_STATUS_RUNNING = 2,           ///< Profiler is currently running
    PROFILER_STATUS_STOPPED = 3,           ///< Profiler was stopped manually
    PROFILER_STATUS_TIMEOUT = 4,           ///< Profiler was stopped due to timeout
    PROFILER_STATUS_PREWARMED = 5,         ///< Profiler was not started due to prewarming
    PROFILER_STATUS_SAMPLED_OUT = 6,       ///< Profiler was not started due to sample rate
    PROFILER_STATUS_ALLOCATION_FAILED = 7, ///< Memory allocation failed
    PROFILER_STATUS_ALREADY_STARTED = 8,   ///< Failed to start profiler because it is already started
} profiler_status_t;

/**
 * Opaque handle to a constructor profile instance
 */
#ifdef __cplusplus
typedef dd::profiler::profile profiler_profile_t;
#else
typedef struct profile profiler_profile_t;
#endif


/**
 * @brief Gets the current status of the profiler
 *
 * This function provides detailed information about the profiler's current state,
 * including why it may not have started or why it stopped.
 *
 * @return Current profiler status code
 *
 * # Swift Usage Example
 *
 * ```swift
 * import DatadogProfiling
 *
 * let status = profiler_get_status()
 * switch status {
 * case PROFILER_STATUS_RUNNING:
 *     print("Profiler is running")
 * case PROFILER_STATUS_PREWARMED:
 *     print("Profiler was not started due to app prewarming")
 * case PROFILER_STATUS_SAMPLED_OUT:
 *     print("Profiler was not started due to sample rate")
 * default:
 *     print("Profiler status: \(status)")
 * }
 * ```
 */
profiler_status_t profiler_get_status(void);

/**
 * @brief Starts profiling if it's currently stopped or ignored otherwise.
 *
 * After calling this function, `profiler_get_status()` will return `PROFILER_STATUS_RUNNING`.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 */
void profiler_start(void);

/**
 * @brief Stops profiling if it's currently running.
 *
 * After calling this function, `profiler_get_status()` will return `PROFILER_STATUS_STOPPED`.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 */
void profiler_stop(void);

/**
 * @brief Retrieves the aggregated profile data
 * 
 * Returns a typed handle to the profile data collected. This data contains
 * deduplicated stack traces, binary mappings, and sample metadata that 
 * can be serialized for analysis.
 * 
 * @param cleanup If true, the current profile data will be cleared and a new segment started.
 * @return Typed handle to profile data, or NULL if:
 *         - Profiling was never started
 *         - No samples were collected
 *         - Profile data has been destroyed
 * 
 * @note The returned handle remains valid until destroyed via `profiler_destroy()`
 * @note This function can be called before or after stopping the profiler
 * 
 * @see `profiler_stop()`, `profiler_destroy()`
 */
profiler_profile_t* profiler_get_profile(bool cleanup);

/**
 * @brief Destroys the profiler data and frees all associated memory
 *
 * This function should be called when the profile data is no longer needed
 * to free memory resources. After calling this function, `profiler_get_profile()`
 * will return NULL.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 *
 * @warning After calling this function, any previously returned profile handles become invalid
 *
 * @see `profiler_get_profile()`
 */
void profiler_destroy(void);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
#endif // DD_PROFILER_MACH_PROFILER_H_
