#include "include/mach_profiler.h"
#include "mach_deterministic_profiler.h"
#include "mach_statistical_profiler.h"

#ifdef __APPLE__

extern "C" {

/**
 * Creates a deterministic profiler instance.
 * Uses fixed intervals and samples all threads predictably.
 */
profiler_t* profiler_create_deterministic(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* user_data) {
    if (!callback) return nullptr;
    
    return reinterpret_cast<profiler_t*>(
        new dd::profiler::mach_deterministic_profiler(config, callback, user_data)
    );
}

/**
 * Creates a statistical profiler instance.
 * Uses jittered intervals and probabilistic thread sampling for unbiased results.
 */
profiler_t* profiler_create_statistical(
    const sampling_config_t* base_config,
    const statistical_sampling_config_t* stat_config,
    stack_trace_callback_t callback,
    void* user_data) {
    if (!callback) return nullptr;
    
    return reinterpret_cast<profiler_t*>(
        new dd::profiler::mach_statistical_profiler(base_config, stat_config, callback, user_data)
    );
}

/**
 * Destroys a profiler instance.
 */
void profiler_destroy(profiler_t* profiler) {
    if (!profiler) return;
    delete reinterpret_cast<dd::profiler::mach_sampling_profiler*>(profiler);
}

/**
 * Starts profiling.
 */
int profiler_start(profiler_t* profiler) {
    if (!profiler) return 0;
    dd::profiler::mach_sampling_profiler* prof = reinterpret_cast<dd::profiler::mach_sampling_profiler*>(profiler);
    return prof->start_sampling() ? 1 : 0;
}

/**
 * Stops profiling.
 */
void profiler_stop(profiler_t* profiler) {
    if (!profiler) return;
    dd::profiler::mach_sampling_profiler* prof = reinterpret_cast<dd::profiler::mach_sampling_profiler*>(profiler);
    prof->stop_sampling();
}

/**
 * Checks if profiling is currently running.
 */
int profiler_is_running(const profiler_t* profiler) {
    if (!profiler) return 0;
    const dd::profiler::mach_sampling_profiler* prof = reinterpret_cast<const dd::profiler::mach_sampling_profiler*>(profiler);
    return prof->running ? 1 : 0;
}

} // extern "C"

#endif // __APPLE__ 
