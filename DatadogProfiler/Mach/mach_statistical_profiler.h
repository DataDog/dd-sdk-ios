#ifndef DD_PROFILER_MACH_STATISTICAL_PROFILER_H_
#define DD_PROFILER_MACH_STATISTICAL_PROFILER_H_

#include "mach_sampling_profiler.h"
#include <random>
#include <chrono>

#ifdef __APPLE__

namespace dd {
namespace profiler {

/**
 * @brief Statistical profiler with jittered intervals and probabilistic thread sampling
 * 
 * This implementation provides unbiased statistical sampling that avoids
 * synchronization with application patterns and reduces profiling overhead.
 * 
 * Characteristics:
 * - Jittered sampling intervals to avoid bias
 * - Probabilistic thread sampling based on configured ratio
 * - Statistical randomness using proper RNG
 * - More representative sampling across different execution phases
 */
class mach_statistical_profiler : public mach_sampling_profiler {
public:
    /**
     * @brief Constructs a statistical profiler instance
     * 
     * @param base_config Base sampling configuration for the profiler
     * @param stat_config Statistical configuration for the profiler
     * @param callback Function to call with collected stack traces
     * @param user_data User data to pass to the callback
     */
    mach_statistical_profiler(
        const sampling_config_t* base_config,
        const statistical_sampling_config_t* stat_config,
        stack_trace_callback_t callback,
        void* user_data);

protected:
    /**
     * @brief Returns jittered sampling interval
     * 
     * @return Sampling interval with statistical jitter applied
     */
    uint32_t get_sampling_interval() const override;

    /**
     * @brief Probabilistically determines if thread should be sampled
     * 
     * @param thread The thread to consider for sampling
     * @return true if thread should be sampled based on statistical criteria
     */
    bool should_sample_thread(thread_t thread) override;

private:
    /**
     * @brief Statistical configuration
     */
    statistical_sampling_config_t stat_config;

    /**
     * @brief Random number generator for statistical sampling
     * 
     * Seeded with high-resolution timestamp to ensure good randomness.
     */
    mutable std::mt19937 rng;
};

} // namespace profiler
} // namespace dd

#endif // __APPLE__
#endif // DD_PROFILER_MACH_STATISTICAL_PROFILER_H_ 