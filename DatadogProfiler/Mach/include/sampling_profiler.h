#ifndef DD_PROFILER_SAMPLING_PROFILER_H_
#define DD_PROFILER_SAMPLING_PROFILER_H_

#include <stdint.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <pthread/qos.h>

#ifdef __cplusplus
namespace dd {
namespace profiler {

// Forward declarations of C++ implementation
struct profiler;

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
 * Default configuration values
 */
#define SAMPLING_CONFIG_DEFAULT { \
    .sampling_interval_ms = 1, \
    .profile_current_thread_only = 0, \
    .max_buffer_size = 1000, \
    .max_stack_depth = 128, \
    .qos_class = QOS_CLASS_USER_INTERACTIVE \
}

/**
 * Configuration for the sampling profiler.
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
 * Opaque handle to a profiler instance
 */
#ifdef __cplusplus
typedef dd::profiler::profiler profiler_t;
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
 * Creates a new profiler instance with default configuration.
 *
 * @param config The sampling configuration (can be NULL for defaults)
 * @param callback The callback to receive stack traces
 * @param user_data User data pointer to pass to the callback
 * @return Handle to the profiler instance or NULL on error
 */
profiler_t* profiler_create(
    const sampling_config_t* config,
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

/**
 * Gets the current sampling configuration.
 * 
 * @param profiler Handle to the profiler instance
 * @param[out] config Where to store the configuration
 * @return 1 if successful, 0 otherwise
 */
int profiler_get_config(
    const profiler_t* profiler,
    sampling_config_t* config);

#ifdef __cplusplus
}
#endif

#endif // DD_PROFILER_SAMPLING_PROFILER_H_ 
