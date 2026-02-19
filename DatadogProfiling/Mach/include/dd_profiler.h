/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_PROFILER_H_
#define DD_PROFILER_PROFILER_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <pthread.h>
#include <pthread/qos.h>

/**
 * Structure representing a binary image loaded in memory.
 */
typedef struct binary_image {
    /** Base address where the image is loaded */
    uint64_t load_address;
    /** UUID of the binary */
    uuid_t uuid;
    /** Filename of the binary */
    const char* filename;
} binary_image_t;

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
} sampling_config_t;

/**
 * Default sampling configuration values.
 */
/// Sampling frequency. Default to ~101 Hz (1/101 seconds ≈ 9.9ms)
#define SAMPLING_CONFIG_DEFAULT_INTERVAL_HZ     101     // 101 Hz
#define SAMPLING_CONFIG_DEFAULT_INTERVAL_NANOS  1000000 // 1ms
/// Max buffer size of samples. It is a larger buffer to delay stack aggregation.
#define SAMPLING_CONFIG_DEFAULT_BUFFER_SIZE     10000
/// Max frames per trace.
#define SAMPLING_CONFIG_DEFAULT_STACK_DEPTH     128
/// Max threads count.
#define SAMPLING_CONFIG_DEFAULT_THREAD_COUNT    100

/**
 * Default sampling configuration with safe default values.
 * For C++ use only. Use sampling_config_get_default() from Swift.
 */
static const sampling_config_t SAMPLING_CONFIG_DEFAULT = {
    SAMPLING_CONFIG_DEFAULT_INTERVAL_NANOS,  // sampling_interval_nanos
    0,                                       // profile_current_thread_only
    SAMPLING_CONFIG_DEFAULT_BUFFER_SIZE,     // max_buffer_size
    SAMPLING_CONFIG_DEFAULT_STACK_DEPTH,     // max_stack_depth
    SAMPLING_CONFIG_DEFAULT_THREAD_COUNT,    // max_thread_count
    QOS_CLASS_USER_INTERACTIVE               // qos_class
};

/**
 * Callback type for receiving stack traces.
 * This is called whenever a batch of stack traces is captured.
 *
 * Traces are delivered with raw instruction pointers only — binary image
 * information (UUID, filename) is **not** resolved. The callback is free
 * to resolve frames in-place (e.g., via `resolve_stack_trace_frames`)
 * before further processing.
 *
 * @param traces Mutable array of captured stack traces
 * @param count Number of traces in the array
 * @param ctx Context pointer passed during profiler creation
 */
typedef void (*stack_trace_callback_t)(stack_trace_t* traces, size_t count, void* ctx);

// UserDefaults constants centralized for Profiling
#define DD_PROFILING_USER_DEFAULTS_SUITE_NAME "com.datadoghq.ios-sdk.profiling"
#define DD_PROFILING_IS_ENABLED_KEY "is_profiling_enabled"
#define DD_PROFILING_SAMPLE_RATE_KEY "profiling_sample_rate"

#ifdef __cplusplus

namespace dd::profiler {
// Forward declarations
    class mach_sampling_profiler;
    class profile;
}

extern "C" {
#endif

/**
 * Opaque handle to a profiler instance
 */
#ifdef __cplusplus
typedef dd::profiler::mach_sampling_profiler profiler_t;
#else
typedef struct profiler profiler_t;
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
 * Creates a profiler instance.
 *
 * Uses fixed intervals for consistent sampling behavior.
 *
 * @param config The base sampling configuration (can be NULL for defaults)
 * @param callback The callback to receive stack traces
 * @param ctx Context pointer to pass to the callback
 * @return Handle to the profiler instance or NULL on error
 */
profiler_t* profiler_create(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* ctx);

/**
 * Destroys a profiler instance.
 *
 * @param profiler Handle to the profiler instance
 */
void profiler_destroy(profiler_t* profiler);

/**
 * Starts the profiler.
 *
 * @param profiler Handle to the profiler instance
 * @return 1 if successfully started, 0 otherwise
 */
int profiler_start(profiler_t* profiler);

/**
 * Stops the profiler.
 *
 * @param profiler Handle to the profiler instance
 */
void profiler_stop(profiler_t* profiler);

/**
 * Checks if the profiler is currently running.
 *
 * @param profiler Handle to the profiler instance
 * @return 1 if running, 0 otherwise
 */
int profiler_is_running(const profiler_t* profiler);

// MARK: - DD Profiler (auto-start) API

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
bool is_profiling_enabled(void);

/**
 * Deletes the profiling defaults from UserDefaults.
 *
 * Removes the profiling enabled state, allowing the session to start with a clean state.
 */
void delete_profiling_defaults(void);

/**
 * Status codes for the dd profiler operations
 */
typedef enum {
    DD_PROFILER_STATUS_NOT_CREATED = 0,       ///< Profiler was not created
    DD_PROFILER_STATUS_NOT_STARTED = 1,       ///< Profiler was never started
    DD_PROFILER_STATUS_RUNNING = 2,           ///< Profiler is currently running
    DD_PROFILER_STATUS_STOPPED = 3,           ///< Profiler was stopped manually
    DD_PROFILER_STATUS_TIMEOUT = 4,           ///< Profiler was stopped due to timeout
    DD_PROFILER_STATUS_PREWARMED = 5,         ///< Profiler was not started due to prewarming
    DD_PROFILER_STATUS_SAMPLED_OUT = 6,       ///< Profiler was not started due to sample rate
    DD_PROFILER_STATUS_ALLOCATION_FAILED = 7, ///< Memory allocation failed
    DD_PROFILER_STATUS_ALREADY_STARTED = 8,   ///< Failed to start profiler because it is already started
} dd_profiler_status_t;

/**
 * Opaque handle to a dd profiler profile instance
 */
#ifdef __cplusplus
typedef dd::profiler::profile dd_profile_t;
#else
typedef struct profile dd_profile_t;
#endif

/**
 * @brief Gets the current status of the dd profiler
 *
 * This function provides detailed information about the profiler's current state,
 * including why it may not have started or why it stopped.
 *
 * @return Current profiler status code
 */
dd_profiler_status_t dd_profiler_get_status(void);

/**
 * @brief Stops profiling if it's currently running
 *
 * This function should be called when the application no longer needs profiling. It will:
 *
 * - Stop the sampling thread
 * - Flush any remaining collected samples
 * - Set the profiler state to inactive
 *
 * After calling this function, `dd_profiler_get_status()` will return `DD_PROFILER_STATUS_STOPPED`.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 *
 * @warning Once stopped, profiling cannot be restarted in the same process
 *
 * @see `dd_profiler_get_status()`
 */
void dd_profiler_stop(void);

/**
 * @brief Retrieves the aggregated profile data from profiling
 *
 * Returns a typed handle to the profile data collected during profiling. This data
 * contains deduplicated stack traces, binary mappings, and sample metadata that can
 * be serialized for analysis.
 *
 * @return Typed handle to profile data, or NULL if:
 *         - Profiling was never started
 *         - No samples were collected
 *         - Profile data has been destroyed
 *
 * @note The returned handle remains valid until destroyed
 * @note This function can be called before or after stopping the profiler
 * @note The profile data accumulates all samples from start to stop
 *
 * @see `dd_profiler_stop()`, `dd_profiler_destroy()`
 */
dd_profile_t* dd_profiler_get_profile(void);

/**
 * @brief Destroys the dd profiler data and frees all associated memory
 *
 * This function should be called when the profile data is no longer needed
 * to free memory resources. After calling this function, `dd_profiler_get_profile()`
 * will return NULL.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 *
 * @warning After calling this function, any previously returned profile handles become invalid
 *
 * @see `dd_profiler_get_profile()`
 */
void dd_profiler_destroy(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_PROFILER_H_
