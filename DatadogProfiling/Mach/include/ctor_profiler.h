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
 * The profiler automatically checks the application's Info.plist for configuration
 * and starts profiling if enabled. No manual initialization is required.
 * 
 * # Configuration
 * 
 * Add the following to your application's Info.plist to enable constructor profiling:
 * 
 * ```xml
 * <key>DatadogProfiling</key>
 * <dict>
 *     <key>AppLaunchProfileSampleRate</key>
 *     <real>20.0</real>
 * </dict>
 * ```
 * 
 * - `AppLaunchProfileSampleRate`: Sample rate percentage (0.0-100.0)
 *   - 0.0 = profiling disabled
 *   - 100.0 = always profile
 *   - Values between 0-100 can be used for probabilistic sampling
 * 
 * # Profiling Characteristics
 * 
 * - **Timing**: Starts via __attribute__((constructor(101))) - very early in process lifecycle
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
 * // Profiling starts automatically if configured in Info.plist
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
 * - Profiling starts before main() and most static initializers
 * - Uses 101 Hz sampling frequency - provides good resolution without impacting launch performance
 * - Automatically stops when ctor_profiler_stop() is called
 * - No overhead when disabled via Info.plist configuration
 * - Designed to have minimal impact on application launch time and user experience
 * 
 * # Thread Safety
 * 
 * All functions are thread-safe and can be called from any thread.
 */

#ifdef __APPLE__

#ifdef __cplusplus
namespace dd::profiler {

class profile;

} // namespace dd::profiler

extern "C" {
#endif

/**
 * Status codes for constructor profiler operations
 */
typedef enum {
    CTOR_PROFILER_STATUS_NOT_STARTED = 0,       ///< Profiler was never started
    CTOR_PROFILER_STATUS_RUNNING = 1,           ///< Profiler is currently running
    CTOR_PROFILER_STATUS_STOPPED = 2,           ///< Profiler was stopped manually
    CTOR_PROFILER_STATUS_TIMEOUT = 3,           ///< Profiler was stopped due to timeout
    CTOR_PROFILER_STATUS_ERROR = 4,             ///< Profiler encountered an error
    CTOR_PROFILER_STATUS_PREWARMED = 5,         ///< Profiler was not started due to prewarming
    CTOR_PROFILER_STATUS_SAMPLED_OUT = 6,       ///< Profiler was not started due to sample rate
    CTOR_PROFILER_STATUS_NO_CONFIG = 7,         ///< Profiler was not started due to missing config
    CTOR_PROFILER_STATUS_ALLOCATION_FAILED = 8, ///< Memory allocation failed
    CTOR_PROFILER_STATUS_START_FAILED = 9,      ///< Failed to start sampling
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
 * @note This function is thread-safe and can be called from any thread
 * @note Useful for debugging profiler initialization and lifecycle issues
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
 *
 * @see ctor_profiler_is_active()
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
 * - Clean up all allocated resources
 * - Set the profiler state to inactive
 * 
 * After calling this function, ctor_profiler_is_active() will return 0.
 * 
 * @note This function is thread-safe and can be called from any thread
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 * 
 * @warning Once stopped, constructor profiling cannot be restarted in the same process
 * 
 * @see ctor_profiler_is_active()
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
 * @see ctor_profiler_stop(), ctor_profiler_destroy_profile()
 */
ctor_profile_t* ctor_profiler_get_profile(void);

/**
 * @brief Destroys the constructor profile data and frees all associated memory
 *
 * This function should be called when the profile data is no longer needed
 * to free memory resources. After calling this function, ctor_profiler_get_profile()
 * will return NULL.
 *
 * @note This function is thread-safe and can be called from any thread
 * @note Safe to call multiple times - subsequent calls are no-ops
 * @note Safe to call even if profiling was never started
 *
 * @warning After calling this function, any previously returned profile handles become invalid
 *
 * @see ctor_profiler_get_profile()
 */
void ctor_profiler_destroy(void);

/**
 * @brief Manually starts constructor profiling for testing purposes
 *
 * This function bypasses the automatic constructor-based startup mechanism and allows
 * manual control over profiling for testing scenarios. Unlike the automatic startup,
 * this function:
 *
 * - Ignores Info.plist configuration
 * - Bypasses prewarming detection
 * - Uses the provided sample rate with probabilistic sampling
 * - Can be called at any time during application lifecycle
 * - Destroys any existing profiler instance before creating a new one
 *
 * The profiler uses 101 Hz sampling frequency and 10,000 sample buffer.
 * It will automatically stop when the specified timeout is reached.
 *
 * @param sample_rate Sample rate percentage (0.0-100.0)
 *                    - 0.0 will not start profiling (STATUS_NO_CONFIG)
 *                    - Values 0.0-100.0 use probabilistic sampling
 *                    - Values > 100.0 are treated as 100%
 * @param is_prewarming Whether the app is in prewarming state
 *                      - true: Will not start profiling (STATUS_PREWARMED)
 *                      - false: Normal profiling behavior
 * @param timeout_ns Timeout in nanoseconds after which profiling automatically stops
 *                   - Default: 5000000000ULL (5 seconds)
 *                   - Timeout checking occurs during sample processing
 *
 * @note This function is thread-safe and can be called from any thread
 * @note Safe to call multiple times - destroys existing instance before creating new one
 * @note Check ctor_profiler_get_status() for detailed status after calling
 * @note Designed for unit tests, integration tests, and development builds
 *
 * @warning FOR TESTING USE ONLY - Not intended for production environments
 * @warning May impact application performance if used inappropriately
 *
 * Possible status codes after calling:
 * - CTOR_PROFILER_STATUS_RUNNING: Successfully started
 * - CTOR_PROFILER_STATUS_PREWARMED: Not started due to active prewarming
 * - CTOR_PROFILER_STATUS_NO_CONFIG: Not started due to sample_rate == 0.0
 * - CTOR_PROFILER_STATUS_SAMPLED_OUT: Not started due to probabilistic sampling
 * - CTOR_PROFILER_STATUS_ALLOCATION_FAILED: Memory allocation failed
 * - CTOR_PROFILER_STATUS_START_FAILED: Failed to start sampling thread
 *
 * @see ctor_profiler_get_status(), ctor_profiler_stop(), ctor_profiler_get_profile()
 */
void ctor_profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
#endif // DD_PROFILER_CTOR_PROFILER_H_
