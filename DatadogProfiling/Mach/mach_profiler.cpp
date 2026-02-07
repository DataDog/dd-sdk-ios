/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "mach_profiler.h"

#ifdef __APPLE__

#include "profile.h"
#include "mach_sampling_profiler.h"

#include <CoreFoundation/CoreFoundation.h>
#include <cstdlib>
#include <cstring>
#include <random>
#include <mutex>
#include <pthread.h>

namespace dd::profiler { class mach_profiler; }

static dd::profiler::mach_profiler* mach_profiler = nullptr;
static std::mutex g_mach_profiler_mutex;

/**
 * Checks if ThreadSanitizer is enabled
 * and without options to avoid halts.
 *
 * @return true if ThreadSanitizer is enabled, false otherwise
 */
bool is_thread_sanitizer_enabled() {
#if __has_feature(thread_sanitizer)
    const char* tsanOptions = getenv("TSAN_OPTIONS");
    if (tsanOptions != nullptr) {
        return (strstr(tsanOptions, "halt_on_error=0") == nullptr)
        || (strstr(tsanOptions, "report_bugs=0") == nullptr);
    }
    return true;
#endif
    return false;
}

/**
 * Checks if the current process was launched via pre-warming by examining
 * the ActivePrewarm environment variable.
 *
 * @return true if the process is actively pre-warmed, false otherwise
 */
bool is_active_prewarm() {
    const char* prewarm = getenv("ActivePrewarm");
    return prewarm != nullptr && strcmp(prewarm, "1") == 0;
}

/**
 * Determines whether profiling should be enabled based on the sample rate
 * using probabilistic sampling.
 *
 * @param sample_rate The sample rate percentage (0.0 to 100.0)
 * @return true if profiling should be enabled, false otherwise
 */
bool sample(double sample_rate) {
    if (sample_rate <= 0.0) return false;
    if (sample_rate >= 100.0) return true;

    // Use probabilistic sampling based on the sample rate (0-100%)
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_real_distribution<double> dis(0.0, 100.0);

    double random_value = dis(gen);
    return random_value < sample_rate;
}

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Reads the DatadogProfiling info from the `UserDefaults`
 * to validate that the feature was enabled before.
 *
 * @return If Profiling was enabled, or false if the key is not found
 */
bool is_profiling_enabled() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_PROFILING_IS_ENABLED_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suiteName);

    bool result = false;

    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
            result = CFBooleanGetValue((CFBooleanRef)value);
        }
        CFRelease(value);
    }

    return result;
}

/**
 * Reads the DatadogProfiling sample rate from the `UserDefaults`
 *
 * @return The sample rate as a double, or 0.0 if not found or invalid
 */
double read_profiling_sample_rate() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_PROFILING_SAMPLE_RATE_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suiteName);
    
    double sample_rate = 0.0;
    
    if (value) {
        if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &sample_rate);
        }
        CFRelease(value);
    }
    
    // Validate sample rate is between 0 and 100
    if (sample_rate < 0.0) return 0.0;
    if (sample_rate > 100.0) return 100.0;
    
    return sample_rate;
}

/**
 * Deletes the DatadogProfiling defaults from the `UserDefaults`
 * to be re-evaluated during `Profiling.enable()`.
 */
void delete_profiling_defaults() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef isEnabledKey = CFSTR(DD_PROFILING_IS_ENABLED_KEY);
    CFStringRef sampleRateKey = CFSTR(DD_PROFILING_SAMPLE_RATE_KEY);

    CFPreferencesSetValue(isEnabledKey, NULL, suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue(sampleRateKey, NULL, suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

#ifdef __cplusplus
}
#endif

namespace dd::profiler {

/**
 * Encapsulates profiler state and operations
 */
class mach_profiler {
public:
    profiler_status_t status = PROFILER_STATUS_NOT_STARTED;

    mach_profiler(
        double sample_rate = 0.0,
        bool is_prewarming = false
    ) : sample_rate(sample_rate), is_prewarming(is_prewarming) {}

    ~mach_profiler() {
        if (profiler) delete profiler;
        if (profile) delete profile;
    }

    /**
     * Start the profiler using constructor configuration.
     * 
     */
    void start() {
        if (is_thread_sanitizer_enabled()) {
            printf("[DATADOG SDK] 🐶 → Profiling is disabled because ThreadSanitizer is active. Please disable ThreadSanitizer to enable profiling.\n");
            status = PROFILER_STATUS_NOT_STARTED;
            return;
        }

        if (status == PROFILER_STATUS_RUNNING) return;

        if (is_prewarming) {
            status = PROFILER_STATUS_PREWARMED;
            return;
        }

        if (!sample(sample_rate)) {
            status = PROFILER_STATUS_SAMPLED_OUT;
            return;
        }

        // Create profile aggregator
        if (!create_profile()) {
            return;
        }

        // Configure profiler
        sampling_config_t config = SAMPLING_CONFIG_DEFAULT;
        config.sampling_interval_nanos = SAMPLING_CONFIG_DEFAULT_INTERVAL_NS;

        profiler = new mach_sampling_profiler(&config, callback, this);
        if (!profiler) {
            delete profile;
            profile = nullptr;
            status = PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        status = PROFILER_STATUS_RUNNING;
        if (!profiler->start_sampling()) {
            delete profiler;
            delete profile;
            profiler = nullptr;
            profile = nullptr;
            status = PROFILER_STATUS_ALREADY_STARTED;
            return;
        }
    }

    // Non-copyable
    mach_profiler(const mach_profiler&) = delete;
    mach_profiler& operator=(const mach_profiler&) = delete;


    void stop() {
        if (!profiler) return;
        status = PROFILER_STATUS_STOPPED;
        profiler->stop_sampling();
    }

    /**
     * Retrieves the profile data.
     * 
     * @param cleanup If true, takes ownership of the profile data, removing it from the profiler.
     *                Subsequent calls will return nullptr.
     * @return The profile data, or nullptr if none exists
     */
    profile* get_profile(bool cleanup = false) {
        if (profiler) {
            profiler->flush_buffer();
        }
        dd::profiler::profile* p = profile;
        if (cleanup) {
            profile = nullptr;
            create_profile();
        }
        return p;
    }

private:
    mach_sampling_profiler* profiler = nullptr;
    profile* profile = nullptr;
    double sample_rate = 0.0;
    bool is_prewarming = false;

    /**
     * Internal helper to create a fresh profile aggregator.
     * 
     * @return true if successful, false on allocation failure
     */
    bool create_profile() {
        // Create profile aggregator
        profile = new dd::profiler::profile(SAMPLING_CONFIG_DEFAULT_INTERVAL_NS);
        if (!profile) {
            status = PROFILER_STATUS_ALLOCATION_FAILED;
            return false;
        }
        return true;
    }

    /**
     * Static callback function to handle collected stack traces
     *
     * @param traces Array of captured stack traces
     * @param count Number of traces in the array
     * @param ctx Context pointer to mach_profiler instance
     */
    static void callback(const stack_trace_t* traces, size_t count, void* ctx) {
        if (!traces || count == 0 || !ctx) return;

        mach_profiler* profiler = static_cast<mach_profiler*>(ctx);

        dd::profiler::profile* profile = profiler->profile;
        if (!profile) return;
        profile->add_samples(traces, count);

        // Check for timeout after adding samples
        int64_t duration_ns = profile->end_timestamp() - profile->start_timestamp();
    }
};

} // namespace dd::profiler

/**
 * Wrapper for pthread_create to call profiler_cache_binary_images
 */
static void* cache_binary_images_thread_entry(void*) {
    pthread_setname_np("com.datadoghq.profiler.cache-images");
    profiler_cache_binary_images();
    return nullptr;
}

/**
 * Pre-cache binary images in a background thread
 */
static void start_binary_image_caching() {
    pthread_t cache_thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_UTILITY, 0);
    if (pthread_create(&cache_thread, &attr, cache_binary_images_thread_entry, nullptr) == 0) {
        pthread_detach(cache_thread);
    }
    pthread_attr_destroy(&attr);
}

/**
 * Constructor function that runs early during app launch to check if
 * constructor-based profiling should be enabled based on bundle configuration
 * and prewarming.
 * 
 * Uses high priority (65535) to run as close to main() as possible.
 */
__attribute__((constructor(65535)))
static void mach_profiler_auto_start() {
    if (!is_profiling_enabled()) {
        return;
    }

    set_main_thread(pthread_self());

    // Pre-cache binary images in a background thread
    start_binary_image_caching();

    // Create profiler and start with sample rate
    mach_profiler = new dd::profiler::mach_profiler(read_profiling_sample_rate(), is_active_prewarm());
    mach_profiler->start();

    // Reset profiling defaults to be re-evaluated again
    delete_profiling_defaults();
}

// C API implementations

extern "C" {

void profiler_start(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    if (mach_profiler) mach_profiler->start();
}

void profiler_stop(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    if (mach_profiler) mach_profiler->stop();
}

profiler_status_t profiler_get_status(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    return mach_profiler ? mach_profiler->status : PROFILER_STATUS_NOT_CREATED;
}

profiler_profile_t* profiler_get_profile(bool cleanup) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    return mach_profiler ? reinterpret_cast<profiler_profile_t*>(mach_profiler->get_profile(cleanup)) : nullptr;
}

void profiler_destroy(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    delete mach_profiler;
    mach_profiler = nullptr;
}

void profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    delete mach_profiler;
    mach_profiler = new dd::profiler::mach_profiler(sample_rate, is_prewarming);
    mach_profiler->start();
}

} // extern "C"

#endif // __APPLE__
