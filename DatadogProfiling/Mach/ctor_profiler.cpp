/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "ctor_profiler.h"

#ifdef __APPLE__

#include "profile.h"
#include "mach_sampling_profiler.h"

#include <CoreFoundation/CoreFoundation.h>
#include <cstdlib>
#include <cstring>
#include <random>
#include <mutex>

static constexpr int64_t CTOR_PROFILER_TIMEOUT_NS = 5000000000ULL; // 5 seconds

namespace dd::profiler { class ctor_profiler; }

static dd::profiler::ctor_profiler* g_ctor_profiler = nullptr;
static std::mutex g_ctor_profiler_mutex;

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
class ctor_profiler {
public:
    ctor_profiler_status_t status = CTOR_PROFILER_STATUS_NOT_STARTED;

    ctor_profiler(
        double sample_rate = 0.0,
        bool is_prewarming = false,
        int64_t timeout_ns = CTOR_PROFILER_TIMEOUT_NS
    ) : sample_rate(sample_rate), is_prewarming(is_prewarming), timeout_ns(timeout_ns) {}

    ~ctor_profiler() {
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
            status = CTOR_PROFILER_STATUS_NOT_STARTED;
            return;
        }

        if (is_prewarming) {
            status = CTOR_PROFILER_STATUS_PREWARMED;
            return;
        }

        if (!sample(sample_rate)) {
            status = CTOR_PROFILER_STATUS_SAMPLED_OUT;
            return;
        }

        // Use 101 Hz sampling frequency
        uint64_t sampling_interval_ns = 9900990; // ~101 Hz (1/101 seconds ≈ 9.9ms)

        // Create profile aggregator
        profile = new dd::profiler::profile(sampling_interval_ns);
        if (!profile) {
            status = CTOR_PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        // Configure profiler
        sampling_config_t config = SAMPLING_CONFIG_DEFAULT;
        config.sampling_interval_nanos = sampling_interval_ns;

        profiler = new mach_sampling_profiler(&config, callback, this);
        if (!profiler) {
            delete profile;
            profile = nullptr;
            status = CTOR_PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        status = CTOR_PROFILER_STATUS_RUNNING;
        if (!profiler->start_sampling()) {
            delete profiler;
            delete profile;
            profiler = nullptr;
            profile = nullptr;
            status = CTOR_PROFILER_STATUS_ALREADY_STARTED;
            return;
        }
    }

    // Non-copyable
    ctor_profiler(const ctor_profiler&) = delete;
    ctor_profiler& operator=(const ctor_profiler&) = delete;


    void stop() {
        if (!profiler) return;
        status = CTOR_PROFILER_STATUS_STOPPED;
        profiler->stop_sampling();
        delete profiler;
        profiler = nullptr;
    }

    profile* get_profile() const { return profile; }

private:
    mach_sampling_profiler* profiler = nullptr;
    profile* profile = nullptr;
    double sample_rate = 0.0;
    bool is_prewarming = false;
    int64_t timeout_ns = CTOR_PROFILER_TIMEOUT_NS; // 5 seconds default

    /**
     * Static callback function to handle collected stack traces
     *
     * @param traces Array of captured stack traces
     * @param count Number of traces in the array
     * @param ctx Context pointer to ctor_profiler instance
     */
    static void callback(const stack_trace_t* traces, size_t count, void* ctx) {
        if (!traces || count == 0 || !ctx) return;

        ctor_profiler* profiler = static_cast<ctor_profiler*>(ctx);

        dd::profiler::profile* profile = profiler->profile;
        if (!profile) return;
        profile->add_samples(traces, count);

        // Check for timeout after adding samples
        int64_t duration_ns = profile->end_timestamp() - profile->start_timestamp();
        if (duration_ns > profiler->timeout_ns) {
            profiler->stop();
            profiler->status = CTOR_PROFILER_STATUS_TIMEOUT;
        }
    }
};

} // namespace dd::profiler

/**
 * Constructor function that runs early during app launch to check if
 * constructor-based profiling should be enabled based on bundle configuration
 * and prewarming.
 * 
 * Uses high priority (65535) to run as close to main() as possible.
 */
__attribute__((constructor(65535)))
static void ctor_profiler_auto_start() {
    if (!is_profiling_enabled()) {
        return;
    }

    set_main_thread(pthread_self());

    // Create profiler and start with sample rate
    g_ctor_profiler = new dd::profiler::ctor_profiler(read_profiling_sample_rate(), is_active_prewarm());
    g_ctor_profiler->start();

    // Reset profiling defaults to be re-evaluated again
    delete_profiling_defaults();
}

// C API implementations

void ctor_profiler_stop(void) {
    std::lock_guard<std::mutex> lock(g_ctor_profiler_mutex);
    if (g_ctor_profiler) g_ctor_profiler->stop();
}

ctor_profiler_status_t ctor_profiler_get_status(void) {
    std::lock_guard<std::mutex> lock(g_ctor_profiler_mutex);
    return g_ctor_profiler ? g_ctor_profiler->status : CTOR_PROFILER_STATUS_NOT_CREATED;
}

ctor_profile_t* ctor_profiler_get_profile(void) {
    std::lock_guard<std::mutex> lock(g_ctor_profiler_mutex);
    return g_ctor_profiler ? reinterpret_cast<ctor_profile_t*>(g_ctor_profiler->get_profile()) : nullptr;
}

void ctor_profiler_destroy(void) {
    std::lock_guard<std::mutex> lock(g_ctor_profiler_mutex);
    delete g_ctor_profiler;
    g_ctor_profiler = nullptr;
}

#ifdef __cplusplus
extern "C" {
#endif

void ctor_profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns) {
    std::lock_guard<std::mutex> lock(g_ctor_profiler_mutex);
    delete g_ctor_profiler;
    g_ctor_profiler = new dd::profiler::ctor_profiler(sample_rate, is_prewarming, timeout_ns);
    g_ctor_profiler->start();
}

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
