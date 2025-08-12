/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_PROFILER_H_
#define DD_PROFILER_PROFILER_H_

#include <stdint.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <pthread/qos.h>

#ifdef __cplusplus

namespace dd::profiler {
// Forward declaration
    class mach_sampling_profiler;
}

extern "C" {
#endif

/**
 * Structure representing a binary image loaded in memory.
 */
typedef struct binary_image {
    uint64_t load_address; ///< Base address where the image is loaded
    uuid_t uuid;           ///< UUID of the binary
    const char* filename;  ///< Filename of the binary
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
 * Default sampling configuration with safe default values
 */
static const sampling_config_t SAMPLING_CONFIG_DEFAULT = {
    1000000,                    // sampling_interval_nanos (1ms)
    0,                          // profile_current_thread_only
    1000,                       // max_buffer_size
    128,                        // max_stack_depth
    100,                        // max_thread_count
    QOS_CLASS_USER_INTERACTIVE  // qos_class
};

/**
 * Opaque handle to a profiler instance
 */
#ifdef __cplusplus
typedef dd::profiler::mach_sampling_profiler profiler_t;
#else
typedef struct profiler profiler_t;
#endif

/**
 * Callback type for receiving stack traces.
 * This is called whenever a batch of stack traces is captured.
 *
 * @param traces Array of captured stack traces
 * @param count Number of traces in the array
 * @param ctx Context pointer passed during profiler creation
 */
typedef void (*stack_trace_callback_t)(const stack_trace_t* traces, size_t count, void* ctx);

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

#ifdef __cplusplus
}
#endif

#endif // DD_PROFILER_PROFILER_H_
