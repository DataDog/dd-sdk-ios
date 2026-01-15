/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_CTOR_PROFILER_H_
#define DD_PROFILER_CTOR_PROFILER_H_

#include <stdint.h>
#include <stdbool.h>

/**
 * @file ctor_profiler.h
 * @brief Constructor-based profiler for application launch performance analysis
 * 
 * This profiler automatically starts during the earliest phase of application startup
 * by using GCC/Clang's __attribute__((constructor)) mechanism. It provides 101 Hz
 * sampling of stack traces from process initialization until manually stopped.
 * 
 * # Automatic Startup
 * 
 * The profiler automatically checks if the profiling was enabled before, and starts it if so.
 * No manual initialization is required.
 * 
 * # Profiling Characteristics
 * 
 * - **Timing**: Starts via __attribute__((constructor(65535))) - very early in process lifecycle
 * - **Sampling Rate**: 101 Hz (~9.9ms intervals) - optimized for launch profiling without performance impact
 * - **Buffer Size**: 10,000 samples to capture entire launch phase
 * - **Stack Depth**: 64 frames maximum per trace
 * - **Thread Coverage**: All threads in the process
 *
 * # Usage Example
 * 
 * ```c
 * #include "ctor_profiler.h"
 * 
 * // Profiling starts automatically if enabled before
 *
 * int main(int argc, char* argv[]) {
 *     // Your app initialization...
 *     
 *     // Stop profiling when launch phase is complete
 *     if (ctor_profiler_is_active()) {
 *         ctor_profiler_stop();
 *     }
 *     
 *     // Continue with normal app execution...
 *     return 0;
 * }
 * ```
 * 
 * # Swift Integration
 * 
 * This API is designed for Swift interoperability:
 * 
 * ```swift
 * import DatadogProfiling
 * 
 * func applicationDidFinishLaunching() {
 *     // Stop constructor profiling when app launch is complete
 *     if ctor_profiler_is_active() != 0 {
 *         ctor_profiler_stop()
 *     }
 * }
 * ```
 * 
 * # Performance Considerations
 * 
 * - Profiling starts right before main()
 * - Uses 101 Hz sampling frequency - provides good resolution without impacting launch performance
 * - Automatically stops when ctor_profiler_stop() is called
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

#ifdef __cplusplus
namespace dd::profiler {

class profile;

} // namespace dd::profiler

extern "C" {
#endif

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
    CTOR_PROFILER_STATUS_NOT_CREATED = 0,       ///< Profiler was not created
    CTOR_PROFILER_STATUS_NOT_STARTED = 1,       ///< Profiler was never started
    CTOR_PROFILER_STATUS_RUNNING = 2,           ///< Profiler is currently running
    CTOR_PROFILER_STATUS_STOPPED = 3,           ///< Profiler was stopped manually
    CTOR_PROFILER_STATUS_TIMEOUT = 4,           ///< Profiler was stopped due to timeout
    CTOR_PROFILER_STATUS_PREWARMED = 5,         ///< Profiler was not started due to prewarming
    CTOR_PROFILER_STATUS_SAMPLED_OUT = 6,       ///< Profiler was not started due to sample rate
    CTOR_PROFILER_STATUS_ALLOCATION_FAILED = 7, ///< Memory allocation failed
    CTOR_PROFILER_STATUS_ALREADY_STARTED = 8,   ///< Failed to start profiler because it is already started
} ctor_profiler_status_t;

/**
 * Opaque handle to a constructor profile instance
 */
#ifdef __cplusplus
typedef dd::profiler::profile ctor_profile_t;
#else
typedef struct profile ctor_profile_t;
#endif


/**
 * @brief Gets the current status of the constructor profiler
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
 * let status = ctor_profiler_get_status()
 * switch status {
 * case CTOR_PROFILER_STATUS_ACTIVE:
 *     print("Profiler is running")
 * case CTOR_PROFILER_STATUS_PREWARMED:
 *     print("Profiler was not started due to app prewarming")
 * case CTOR_PROFILER_STATUS_LOW_SAMPLE_RATE:
 *     print("Profiler was not started due to low sample rate")
 * default:
 *     print("Profiler status: \(status)")
 * }
 * ```
 */
ctor_profiler_status_t ctor_profiler_get_status(void);

/**
 * @brief Stops constructor-based profiling if it's currently running
 * 
 * This function should be called when the application has finished its launch phase
 * and no longer needs constructor-based profiling. It will:
 * 
 * - Stop the sampling thread
 * - Flush any remaining collected samples
 * - Set the profiler state to inactive
 * 
 * After calling this function, `ctor_profiler_get_status()` will return `CTOR_PROFILER_STATUS_STOPPED`.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 * 
 * @warning Once stopped, constructor profiling cannot be restarted in the same process
 * 
 * @see `ctor_profiler_get_status()`
 */
void ctor_profiler_stop(void);

/**
 * @brief Retrieves the aggregated profile data from constructor profiling
 * 
 * Returns a typed handle to the profile data collected during constructor-based
 * profiling. This data contains deduplicated stack traces, binary mappings, and
 * sample metadata that can be serialized for analysis.
 * 
 * @return Typed handle to profile data, or NULL if:
 *         - Profiling was never started
 *         - No samples were collected
 *         - Profile data has been destroyed
 * 
 * @note The returned handle remains valid until destroyed
 * @note This function can be called before or after stopping the profiler
 * @note The profile data accumulates all samples from constructor start to stop
 * 
 * @see `ctor_profiler_stop()`, `ctor_profiler_destroy()`
 */
ctor_profile_t* ctor_profiler_get_profile(void);

/**
 * @brief Destroys the constructor profiler data and frees all associated memory
 *
 * This function should be called when the profile data is no longer needed
 * to free memory resources. After calling this function, `ctor_profiler_get_profile()`
 * will return NULL.
 *
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 *
 * @warning After calling this function, any previously returned profile handles become invalid
 *
 * @see `ctor_profiler_get_profile()`
 */
void ctor_profiler_destroy(void);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
#endif // DD_PROFILER_CTOR_PROFILER_H_
