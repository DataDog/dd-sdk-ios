#include "mach_statistical_profiler.h"

#ifdef __APPLE__

#include <thread>
#include <chrono>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/vm_map.h>
#include <algorithm>

namespace dd {
namespace profiler {

/**
 * Constructs a statistical profiler instance.
 *
 * @param base_config Base sampling configuration for the profiler
 * @param stat_config Statistical configuration for the profiler
 * @param callback Function to call with collected stack traces
 * @param user_data User data to pass to the callback
 */
mach_statistical_profiler::mach_statistical_profiler(
    const sampling_config_t* base_config,
    const statistical_sampling_config_t* stat_config,
    stack_trace_callback_t callback,
    void* user_data)
    : mach_sampling_profiler(base_config, callback, user_data)
    , stat_config(STATISTICAL_SAMPLING_CONFIG_DEFAULT)
    , rng(static_cast<unsigned int>(std::chrono::steady_clock::now().time_since_epoch().count())) {
        if (stat_config) this->stat_config = *stat_config;
}

/**
 * Returns jittered sampling interval.
 *
 * @return Sampling interval with statistical jitter applied in nanoseconds
 */
uint64_t mach_statistical_profiler::get_sampling_interval() const {
    if (stat_config.jitter_percentage == 0) {
        return config.sampling_interval_nanos;
    }
    
    // Calculate jitter range: ±(base_interval * jitter_percentage / 100)
    uint64_t base_interval = config.sampling_interval_nanos;
    uint64_t jitter_range = (base_interval * stat_config.jitter_percentage) / 100;
    
    // Generate random offset: [-jitter_range, +jitter_range]
    std::uniform_int_distribution<int64_t> dist(
        -static_cast<int64_t>(jitter_range), 
        static_cast<int64_t>(jitter_range)
    );
    int64_t jitter = dist(rng);
    
    // Ensure we don't go below 1ms minimum interval (1,000,000 nanoseconds)
    int64_t jittered_interval = static_cast<int64_t>(base_interval) + jitter;
    return static_cast<uint64_t>(std::max(1000000LL, jittered_interval));
}

/**
 * Probabilistically determines if thread should be sampled.
 *
 * @param thread The thread to consider for sampling
 * @return true if thread should be sampled based on statistical criteria
 */
bool mach_statistical_profiler::should_sample_thread(thread_t thread) {
    if (stat_config.thread_sampling_ratio >= 1.0f) {
        return true;  // Sample all threads
    }
    if (stat_config.thread_sampling_ratio <= 0.0f) {
        return false; // Sample no threads
    }
    
    // Generate random value [0.0, 1.0) and compare to sampling ratio
    std::uniform_real_distribution<float> dist(0.0f, 1.0f);
    return dist(rng) < stat_config.thread_sampling_ratio;
}

} // namespace profiler
} // namespace dd

#endif // __APPLE__ 
