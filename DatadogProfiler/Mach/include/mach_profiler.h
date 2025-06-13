#ifndef DD_PROFILER_PROFILER_H_
#define DD_PROFILER_PROFILER_H_

#include <stdint.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <pthread/qos.h>

#ifdef __cplusplus
namespace dd {
namespace profiler {

// Forward declarations of C++ implementation  
class mach_profiler;

} // namespace profiler
} // namespace dd

extern "C" {
#endif

#define MAX_STACK_DEPTH 128

/**
 * Structure representing a binary image loaded in memory.
 */
typedef struct {
    uint64_t load_address;  ///< Base address where the image is loaded
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
    /** The stack frames array */
    stack_frame_t* frames;
    /** Number of frames in the trace */
    uint32_t frame_count;
} stack_trace_t;

/**
 * Base configuration for sampling profilers.
 * Contains common settings shared by all profiler types.
 */
typedef struct sampling_config {
    /** Sampling interval in milliseconds */
    uint32_t sampling_interval_ms;  // default: 1ms
    /** Whether to profile only the current thread */
    uint8_t profile_current_thread_only;
    /** Maximum number of samples to buffer before calling the callback */
    size_t max_buffer_size;
    /** Maximum number of stack frames to capture per trace */
    uint32_t max_stack_depth;  // default: 128
    /** QoS class for the sampling thread */
    qos_class_t qos_class;
} sampling_config_t;

/**
 * Configuration for statistical sampling behavior.
 * Contains settings specific to statistical/jittered sampling.
 * Used in conjunction with sampling_config_t for statistical profilers.
 */
typedef struct statistical_sampling_config {
    /** Percentage of jitter to apply to sampling intervals (0-100) */
    uint32_t jitter_percentage;  // default: 50 (±50% jitter)  
    /** Ratio of threads to sample (0.0-1.0, 1.0 = all threads) */
    float thread_sampling_ratio;  // default: 1.0 (sample all threads)
} statistical_sampling_config_t;

/**
 * Default base configuration values
 */
#define SAMPLING_CONFIG_DEFAULT { \
    .sampling_interval_ms = 1, \
    .profile_current_thread_only = 0, \
    .max_buffer_size = 1000, \
    .max_stack_depth = 128, \
    .qos_class = QOS_CLASS_USER_INTERACTIVE \
}

/**
 * Default statistical configuration values
 */
#define STATISTICAL_SAMPLING_CONFIG_DEFAULT { \
    .jitter_percentage = 50, \
    .thread_sampling_ratio = 1.0f \
}

/**
 * Opaque handle to a profiler instance
 */
#ifdef __cplusplus
typedef dd::profiler::mach_profiler profiler_t;
#else
typedef struct profiler profiler_t;
#endif

/**
 * Callback type for receiving stack traces.
 * This is called whenever a batch of stack traces is captured.
 *
 * @param traces Array of captured stack traces
 * @param count Number of traces in the array
 * @param user_data User data pointer passed during profiler creation
 */
typedef void (*stack_trace_callback_t)(const stack_trace_t* traces, size_t count, void* user_data);

/**
 * Creates a deterministic profiler instance.
 * 
 * Uses fixed intervals and samples all threads predictably.
 *
 * @param config The base sampling configuration (can be NULL for defaults)
 * @param callback The callback to receive stack traces
 * @param user_data User data pointer to pass to the callback
 * @return Handle to the deterministic profiler instance or NULL on error
 */
profiler_t* profiler_create_deterministic(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* user_data);

/**
 * Creates a statistical profiler instance.
 * 
 * Uses jittered intervals and probabilistic thread sampling for unbiased results.
 *
 * @param base_config The base sampling configuration (can be NULL for defaults)
 * @param stat_config The statistical sampling configuration (can be NULL for defaults)
 * @param callback The callback to receive stack traces
 * @param user_data User data pointer to pass to the callback
 * @return Handle to the statistical profiler instance or NULL on error
 */
profiler_t* profiler_create_statistical(
    const sampling_config_t* base_config,
    const statistical_sampling_config_t* stat_config,
    stack_trace_callback_t callback,
    void* user_data);

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