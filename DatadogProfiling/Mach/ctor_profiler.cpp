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

/**
 * Reads the DatadogProfiling configuration from the main bundle's Info.plist
 * and extracts the AppLaunchProfileSampleRate value.
 *
 * @return The sample rate as a double, or 0.0 if not found or invalid
 */
double read_app_launch_sample_rate() {
    CFBundleRef main_bundle = CFBundleGetMainBundle();
    if (!main_bundle) return 0.0;
    
    CFDictionaryRef info_dict = CFBundleGetInfoDictionary(main_bundle);
    if (!info_dict) return 0.0;
    
    // Look for DatadogProfiling dictionary
    CFDictionaryRef profiling_dict = (CFDictionaryRef)CFDictionaryGetValue(info_dict, CFSTR("DatadogProfiling"));
    if (!profiling_dict || CFGetTypeID(profiling_dict) != CFDictionaryGetTypeID()) return 0.0;
    
    // Look for AppLaunchProfileSampleRate key
    CFNumberRef sample_rate_ref = (CFNumberRef)CFDictionaryGetValue(profiling_dict, CFSTR("AppLaunchProfileSampleRate"));
    if (!sample_rate_ref || CFGetTypeID(sample_rate_ref) != CFNumberGetTypeID()) return 0.0;
    
    double sample_rate = 0.0;
    if (!CFNumberGetValue(sample_rate_ref, kCFNumberDoubleType, &sample_rate)) return 0.0;
    
    // Validate sample rate is between 0 and 100
    if (sample_rate < 0.0) return 0.0;
    if (sample_rate > 100.0) return 100.0;
    
    return sample_rate;
}

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
     * Start the profiler using constructor configuration
     */
    void start() {
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
        config.max_buffer_size = 10000; // Larger buffer to delay stack aggregation

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
            status = CTOR_PROFILER_STATUS_START_FAILED;
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
    // Create profiler and start with sample rate
    g_ctor_profiler = new dd::profiler::ctor_profiler(read_app_launch_sample_rate(), is_active_prewarm());
    g_ctor_profiler->start();
}

// C API implementations

void ctor_profiler_stop(void) {
    if (g_ctor_profiler) g_ctor_profiler->stop();
}

ctor_profiler_status_t ctor_profiler_get_status(void) {
    return g_ctor_profiler ? g_ctor_profiler->status : CTOR_PROFILER_STATUS_NOT_STARTED;
}

ctor_profile_t* ctor_profiler_get_profile(void) {
    return g_ctor_profiler ? reinterpret_cast<ctor_profile_t*>(g_ctor_profiler->get_profile()) : nullptr;
}

void ctor_profiler_destroy(void) {
    delete g_ctor_profiler;
    g_ctor_profiler = nullptr;
}

void ctor_profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns) {
    delete g_ctor_profiler;
    g_ctor_profiler = new dd::profiler::ctor_profiler(sample_rate, is_prewarming, timeout_ns);
    g_ctor_profiler->start();
}

#endif // __APPLE__
