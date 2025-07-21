#include "mach_deterministic_profiler.h"

#ifdef __APPLE__

#include <thread>
#include <chrono>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/vm_map.h>

namespace dd {
namespace profiler {

/**
 * Constructs a deterministic profiler instance.
 *
 * @param config The sampling configuration to use
 * @param callback Function to call with collected stack traces
 * @param user_data User data to pass to the callback
 */
mach_deterministic_profiler::mach_deterministic_profiler(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* user_data)
    : mach_sampling_profiler(config, callback, user_data) {
}

/**
 * Returns fixed sampling interval.
 *
 * @return Fixed sampling interval from configuration in nanoseconds
 */
uint64_t mach_deterministic_profiler::get_sampling_interval() const {
    return config.sampling_interval_nanos;
}

/**
 * Always returns true to sample all threads.
 * Deterministic profiler samples every thread in every cycle.
 *
 * @param thread The thread to consider (ignored in deterministic mode)
 * @return Always true for deterministic sampling
 */
bool mach_deterministic_profiler::should_sample_thread(thread_t thread) {
    return true; // Deterministic profiler samples all threads
}

} // namespace profiler
} // namespace dd

#endif // __APPLE__ 