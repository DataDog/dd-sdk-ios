#include "mach_profiler.h"
#include "mach_sampling_profiler.h"

#ifdef __APPLE__
#if !TARGET_OS_WATCH

extern "C" {

/**
 * Creates a profiler instance.
 * Uses fixed intervals for consistent sampling behavior.
 */
profiler_t* profiler_create(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* ctx) {
    if (!callback) return nullptr;

    return reinterpret_cast<profiler_t*>(
        new dd::profiler::mach_sampling_profiler(config, callback, ctx)
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

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
